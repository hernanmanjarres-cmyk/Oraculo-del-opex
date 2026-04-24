-- ============================================================
-- KPIs Y QUERIES PARA DASHBOARD — ANALISTA OPEX BIA
-- Ejecutar en Supabase SQL Editor o conectar a Metabase
-- ============================================================

-- ============================================================
-- BLOQUE 1: DASHBOARD EJECUTIVO (vista diaria)
-- ============================================================

-- 1.1 Estado del mes en curso
SELECT
  EXTRACT(YEAR FROM CURRENT_DATE)::INT AS anio,
  EXTRACT(MONTH FROM CURRENT_DATE)::INT AS mes,
  TO_CHAR(CURRENT_DATE, 'Month YYYY') AS periodo,
  EXTRACT(DAY FROM CURRENT_DATE)::INT AS dia_del_mes,
  EXTRACT(DAY FROM DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::INT AS dias_en_mes,
  EXTRACT(DAY FROM DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::INT
    - EXTRACT(DAY FROM CURRENT_DATE)::INT AS dias_restantes,
  -- Ejecución
  COALESCE(SUM(t.costo_total), 0) AS ejecutado_mtd,
  -- Budget
  (SELECT COALESCE(SUM(b.monto_budget), 0)
   FROM opex_budget b
   WHERE b.anio = EXTRACT(YEAR FROM CURRENT_DATE)
     AND b.mes = EXTRACT(MONTH FROM CURRENT_DATE)
     AND b.zona IS NULL AND b.contratista_id IS NULL) AS budget_mes,
  -- % ejecutado vs budget
  CASE WHEN (SELECT SUM(monto_budget) FROM opex_budget WHERE anio = EXTRACT(YEAR FROM CURRENT_DATE)
             AND mes = EXTRACT(MONTH FROM CURRENT_DATE) AND zona IS NULL) > 0 THEN
    ROUND(
      SUM(t.costo_total) /
      (SELECT SUM(monto_budget) FROM opex_budget WHERE anio = EXTRACT(YEAR FROM CURRENT_DATE)
       AND mes = EXTRACT(MONTH FROM CURRENT_DATE) AND zona IS NULL) * 100,
      1
    )
  ELSE NULL END AS pct_ejecutado_vs_budget
FROM opex_transactions t
WHERE EXTRACT(YEAR FROM t.fecha_tx) = EXTRACT(YEAR FROM CURRENT_DATE)
  AND EXTRACT(MONTH FROM t.fecha_tx) = EXTRACT(MONTH FROM CURRENT_DATE);

-- 1.2 Alertas abiertas por severidad
SELECT
  severidad,
  COUNT(*) AS total,
  MIN(generada_en) AS alerta_mas_vieja,
  MAX(generada_en) AS alerta_mas_reciente,
  AVG(EXTRACT(EPOCH FROM (NOW() - generada_en))/3600) AS horas_promedio_abierta
FROM opex_alerts
WHERE estado IN ('open','ack','in_progress')
GROUP BY severidad
ORDER BY CASE severidad WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END;

-- 1.3 Top 10 desviaciones activas (para tabla del dashboard)
SELECT
  a.codigo_alerta,
  a.severidad,
  a.contratista_nombre,
  a.zona,
  a.tipo_servicio,
  a.valor_observado,
  a.valor_esperado,
  a.delta_pct,
  a.narrativa_corta,
  a.causa_raiz_sugerida,
  a.generada_en,
  EXTRACT(EPOCH FROM (NOW() - a.generada_en))/3600 AS horas_abierta
FROM opex_alerts a
WHERE a.estado IN ('open','ack','in_progress')
ORDER BY
  CASE a.severidad WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END,
  ABS(a.delta_pct) DESC NULLS LAST
LIMIT 10;

-- 1.4 Forecast del mes (último cálculo, por zona)
SELECT
  f.zona,
  f.contratista_id,
  f.ejecutado_mtd,
  f.proyeccion_central,
  f.proyeccion_p20,
  f.proyeccion_p80,
  f.budget_mes,
  f.desviacion_pct,
  f.nivel_confianza,
  f.ritmo_ewma,
  f.pipeline_esperado,
  f.fecha_calculo
FROM opex_forecasts f
WHERE f.anio = EXTRACT(YEAR FROM CURRENT_DATE)::INT
  AND f.mes = EXTRACT(MONTH FROM CURRENT_DATE)::INT
  AND f.fecha_calculo = (
    SELECT MAX(f2.fecha_calculo)
    FROM opex_forecasts f2
    WHERE f2.anio = f.anio AND f2.mes = f.mes
  )
ORDER BY ABS(f.desviacion_pct) DESC NULLS LAST;

-- ============================================================
-- BLOQUE 2: ANÁLISIS POR CONTRATISTA
-- ============================================================

-- 2.1 Ejecución y alertas por contratista (mes en curso)
SELECT
  t.contratista_id,
  t.contratista_nombre,
  SUM(t.costo_total) AS ejecutado_mes,
  COUNT(*) AS n_transacciones,
  COUNT(DISTINCT t.ot_id) AS n_ots,
  -- Alertas del mes
  (SELECT COUNT(*) FROM opex_alerts a
   WHERE a.contratista_id = t.contratista_id
     AND a.estado IN ('open','ack','in_progress')
     AND EXTRACT(MONTH FROM a.generada_en) = EXTRACT(MONTH FROM CURRENT_DATE)) AS alertas_activas,
  -- FP rate histórico
  (SELECT ROUND(fp_rate * 100, 1) FROM opex_rules r
   WHERE r.tipo_detector = 'tarifa' LIMIT 1) AS nota_fp_rate
FROM opex_transactions t
WHERE EXTRACT(YEAR FROM t.fecha_tx) = EXTRACT(YEAR FROM CURRENT_DATE)
  AND EXTRACT(MONTH FROM t.fecha_tx) = EXTRACT(MONTH FROM CURRENT_DATE)
GROUP BY t.contratista_id, t.contratista_nombre
ORDER BY ejecutado_mes DESC;

-- 2.2 Historial de alertas por contratista (últimos 3 meses)
SELECT
  a.contratista_id,
  a.contratista_nombre,
  a.codigo_alerta,
  COUNT(*) AS n_alertas,
  SUM(CASE WHEN a.estado = 'false_positive' THEN 1 ELSE 0 END) AS n_fp,
  SUM(CASE WHEN a.estado = 'resolved' THEN 1 ELSE 0 END) AS n_resueltas,
  ROUND(AVG(ABS(a.delta_pct)), 2) AS delta_medio_pct
FROM opex_alerts a
WHERE a.generada_en >= NOW() - INTERVAL '3 months'
GROUP BY a.contratista_id, a.contratista_nombre, a.codigo_alerta
ORDER BY a.contratista_id, n_alertas DESC;

-- ============================================================
-- BLOQUE 3: ANÁLISIS POR ZONA
-- ============================================================

-- 3.1 Ejecución vs budget por zona (mes en curso)
SELECT
  t.zona,
  SUM(t.costo_total) AS ejecutado_mes,
  COALESCE((
    SELECT SUM(b.monto_budget)
    FROM opex_budget b
    WHERE b.anio = EXTRACT(YEAR FROM CURRENT_DATE)
      AND b.mes = EXTRACT(MONTH FROM CURRENT_DATE)
      AND b.zona = t.zona
  ), 0) AS budget_zona,
  CASE WHEN COALESCE((
    SELECT SUM(b.monto_budget)
    FROM opex_budget b
    WHERE b.anio = EXTRACT(YEAR FROM CURRENT_DATE)
      AND b.mes = EXTRACT(MONTH FROM CURRENT_DATE)
      AND b.zona = t.zona
  ), 0) > 0 THEN
    ROUND(
      (SUM(t.costo_total) / (
        SELECT SUM(b.monto_budget)
        FROM opex_budget b
        WHERE b.anio = EXTRACT(YEAR FROM CURRENT_DATE)
          AND b.mes = EXTRACT(MONTH FROM CURRENT_DATE)
          AND b.zona = t.zona
      ) - 1) * 100,
      1
    )
  ELSE NULL END AS desvio_vs_budget_pct
FROM opex_transactions t
WHERE EXTRACT(YEAR FROM t.fecha_tx) = EXTRACT(YEAR FROM CURRENT_DATE)
  AND EXTRACT(MONTH FROM t.fecha_tx) = EXTRACT(MONTH FROM CURRENT_DATE)
  AND t.zona IS NOT NULL
GROUP BY t.zona
ORDER BY desvio_vs_budget_pct DESC NULLS LAST;

-- ============================================================
-- BLOQUE 4: MÉTRICAS DEL AGENTE (panel de calidad)
-- ============================================================

-- 4.1 KPIs de calidad del agente
SELECT
  -- Cobertura de alertas útiles
  COUNT(*) FILTER (WHERE veredicto = 'confirmado')::FLOAT / NULLIF(COUNT(*), 0) * 100 AS cobertura_util_pct,
  -- Tasa de falsos positivos global
  COUNT(*) FILTER (WHERE veredicto = 'false_positive')::FLOAT / NULLIF(COUNT(*), 0) * 100 AS fp_rate_global_pct,
  -- Tiempo mediano de resolución (alertas altas/críticas)
  PERCENTILE_CONT(0.5) WITHIN GROUP (
    ORDER BY c.tiempo_resolucion_horas
  ) AS tiempo_mediano_horas,
  -- Monto recuperado total
  SUM(c.monto_recuperado) AS monto_recuperado_total,
  -- Precisión de la IA
  COUNT(*) FILTER (WHERE c.ia_acerto = true)::FLOAT /
    NULLIF(COUNT(*) FILTER (WHERE c.ia_acerto IS NOT NULL), 0) * 100 AS precision_ia_pct,
  -- Total de casos
  COUNT(*) AS total_casos
FROM opex_cases c
WHERE c.cerrado_en >= NOW() - INTERVAL '3 months';

-- 4.2 FP rate por regla (para ajustar umbrales)
SELECT
  r.codigo_regla,
  r.nombre,
  r.severidad,
  r.fp_rate * 100 AS fp_rate_pct,
  r.tp_rate * 100 AS tp_rate_pct,
  r.n_activaciones,
  r.n_falsos_positivos,
  -- Umbral actual
  COALESCE(r.umbral_pct_min::TEXT, r.umbral_zscore::TEXT, 'N/A') AS umbral_actual,
  -- Semáforo
  CASE
    WHEN r.fp_rate >= 0.40 THEN '🔴 Alto'
    WHEN r.fp_rate >= 0.20 THEN '🟡 Medio'
    ELSE '🟢 Bajo'
  END AS semaforo_fp
FROM opex_rules r
WHERE r.activa = true
ORDER BY r.fp_rate DESC;

-- 4.3 Tendencia mensual del agente (meses de cierre)
SELECT
  cl.anio,
  cl.mes,
  cl.ejecucion_total,
  cl.budget_total,
  cl.variacion_pct,
  cl.alertas_detectadas,
  cl.alertas_cerradas,
  cl.monto_recuperado,
  cl.error_forecast_pct,
  cl.estado AS estado_cierre
FROM opex_closes cl
ORDER BY cl.anio DESC, cl.mes DESC
LIMIT 12;

-- ============================================================
-- BLOQUE 5: AUDITORÍA Y TRAZABILIDAD
-- ============================================================

-- 5.1 Últimas comunicaciones enviadas
SELECT
  c.enviado_en,
  c.tipo_comunicacion,
  c.destinatario,
  c.asunto,
  c.enviado_por,
  c.canal,
  a.codigo_alerta,
  a.contratista_nombre,
  a.zona
FROM opex_communications c
LEFT JOIN opex_alerts a ON a.id = c.alert_id
ORDER BY c.enviado_en DESC
LIMIT 50;

-- 5.2 Cola de aprobación pendiente (para el analista)
SELECT
  ap.id,
  ap.tipo_comunicacion,
  ap.destinatario,
  ap.asunto,
  ap.creado_en,
  ap.expira_en,
  EXTRACT(EPOCH FROM (ap.expira_en - NOW()))/3600 AS horas_para_expirar,
  a.codigo_alerta,
  a.severidad,
  a.contratista_nombre,
  a.narrativa_corta
FROM opex_approvals ap
LEFT JOIN opex_alerts a ON a.id = ap.alert_id
WHERE ap.estado = 'pendiente'
ORDER BY
  CASE a.severidad WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 ELSE 3 END,
  ap.creado_en ASC;

-- 5.3 Log de ejecuciones del agente (últimas 24h)
SELECT
  workflow_nombre,
  inicio,
  fin,
  duracion_seg,
  estado,
  registros_procesados,
  alertas_generadas,
  dry_run
FROM opex_agent_log
WHERE inicio >= NOW() - INTERVAL '24 hours'
ORDER BY inicio DESC;

-- ============================================================
-- BLOQUE 6: BACKTEST DEL FORECAST
-- ============================================================

-- 6.1 Error del forecast por mes
SELECT
  cl.anio,
  cl.mes,
  cl.ejecucion_total AS real,
  cl.forecast_dia20,
  cl.error_forecast_pct,
  CASE
    WHEN ABS(cl.error_forecast_pct) <= 3 THEN '✅ Bueno (≤3%)'
    WHEN ABS(cl.error_forecast_pct) <= 5 THEN '🟡 Aceptable (3-5%)'
    ELSE '🔴 Desviado (>5%)'
  END AS calidad_forecast
FROM opex_closes cl
WHERE cl.forecast_dia20 IS NOT NULL
ORDER BY cl.anio DESC, cl.mes DESC;

-- 6.2 MAE del forecast (media de error absoluto, meta ≤3%)
SELECT
  ROUND(AVG(ABS(error_forecast_pct)), 2) AS mae_forecast_pct,
  COUNT(*) AS meses_con_backtest,
  MIN(ABS(error_forecast_pct)) AS mejor_mes_pct,
  MAX(ABS(error_forecast_pct)) AS peor_mes_pct,
  CASE WHEN AVG(ABS(error_forecast_pct)) <= 3 THEN '✅ Meta alcanzada' ELSE '⚠️ Meta no alcanzada' END AS estado_meta
FROM opex_closes
WHERE error_forecast_pct IS NOT NULL;
