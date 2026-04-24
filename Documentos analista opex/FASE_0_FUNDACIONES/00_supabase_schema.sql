-- ============================================================
-- ANALISTA OPEX VIRTUAL — BIA Energy
-- Schema Supabase (Postgres)
-- Ejecutar en orden. Requiere extensión pgcrypto (habilitada por defecto en Supabase).
-- ============================================================

-- Habilitar extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. TARIFARIO VERSIONADO
-- Fuente de verdad de precios por contratista, servicio y OR.
-- Cada registro tiene vigencia. Las comparaciones usan la versión
-- activa a la fecha de la transacción (effective_from <= fecha <= effective_to).
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_tarifario (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contratista_id   TEXT NOT NULL,
  contratista_nombre TEXT NOT NULL,
  tipo_servicio    TEXT NOT NULL,        -- NORM, INST, REQA, MANT, etc.
  zona             TEXT,                 -- Bogotá, Medellín, Cali, Costa, etc.
  or_codigo        TEXT,                 -- Código de OR si aplica
  unidad           TEXT NOT NULL,        -- und, hora, viaje, m, etc.
  tarifa           NUMERIC(18,4) NOT NULL,
  moneda           TEXT NOT NULL DEFAULT 'COP',
  tolerancia_pct   NUMERIC(5,2) NOT NULL DEFAULT 3.00, -- tolerancia de desvío aceptable (%)
  es_tarifa_variable BOOLEAN DEFAULT FALSE,
  cap_mensual      NUMERIC(18,2),        -- cap mensual si aplica
  notas            TEXT,
  effective_from   DATE NOT NULL,
  effective_to     DATE,                 -- NULL = vigente hasta nuevo registro
  version          INTEGER NOT NULL DEFAULT 1,
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  creado_por       TEXT,
  CONSTRAINT chk_tarifa_positiva CHECK (tarifa > 0),
  CONSTRAINT chk_vigencia CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE INDEX idx_tarifario_lookup ON opex_tarifario (contratista_id, tipo_servicio, zona, effective_from, effective_to);
CREATE INDEX idx_tarifario_vigente ON opex_tarifario (effective_from, effective_to) WHERE effective_to IS NULL;

COMMENT ON TABLE opex_tarifario IS 'Tarifas por contratista/servicio/zona con versionado. Toda comparación usa effective_from <= tx_fecha <= effective_to.';

-- ============================================================
-- 2. PRESUPUESTO MENSUAL VERSIONADO
-- Budget OPEX por mes, zona, contratista y categoría contable.
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_budget (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anio             INTEGER NOT NULL,
  mes              INTEGER NOT NULL CHECK (mes BETWEEN 1 AND 12),
  zona             TEXT,
  contratista_id   TEXT,
  categoria_contable TEXT NOT NULL,      -- cuenta contable o categoría
  tipo_servicio    TEXT,
  monto_budget     NUMERIC(18,2) NOT NULL,
  moneda           TEXT NOT NULL DEFAULT 'COP',
  version          INTEGER NOT NULL DEFAULT 1,
  effective_from   DATE NOT NULL,
  effective_to     DATE,
  notas            TEXT,
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  creado_por       TEXT,
  CONSTRAINT chk_budget_positivo CHECK (monto_budget >= 0)
);

CREATE INDEX idx_budget_lookup ON opex_budget (anio, mes, zona, contratista_id, categoria_contable);

COMMENT ON TABLE opex_budget IS 'Presupuesto mensual OPEX por zona/contratista/categoría. Versionado con effective_from/to.';

-- ============================================================
-- 3. TRANSACCIONES OPEX (espejo / staging desde Metabase)
-- Las transacciones de la fuente se copian aquí para análisis.
-- El agente lee SOLO esta tabla; nunca la fuente directa en producción.
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_transactions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tx_id_fuente     TEXT UNIQUE NOT NULL,  -- ID original en Metabase/fuente
  ot_id            TEXT,                  -- ID de la Orden de Trabajo
  contratista_id   TEXT NOT NULL,
  contratista_nombre TEXT,
  tipo_servicio    TEXT NOT NULL,
  zona             TEXT,
  or_codigo        TEXT,
  direccion        TEXT,
  categoria_contable TEXT,
  cantidad         NUMERIC(18,4),
  costo_unitario   NUMERIC(18,4),
  costo_total      NUMERIC(18,2) NOT NULL,
  moneda           TEXT DEFAULT 'COP',
  fecha_tx         DATE NOT NULL,         -- fecha de la transacción (para lookup de tarifa)
  fecha_factura    DATE,
  estado_ot        TEXT,                  -- abierta, cerrada, cancelada
  tiene_acta_cierre BOOLEAN DEFAULT FALSE,
  notas_ot         TEXT,
  notas_factura    TEXT,
  ingestado_en     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  procesado        BOOLEAN DEFAULT FALSE  -- FALSE hasta que el monitor lo analice
);

CREATE INDEX idx_tx_fecha ON opex_transactions (fecha_tx DESC);
CREATE INDEX idx_tx_contratista ON opex_transactions (contratista_id, fecha_tx);
CREATE INDEX idx_tx_procesado ON opex_transactions (procesado) WHERE procesado = FALSE;
CREATE INDEX idx_tx_ot ON opex_transactions (ot_id);

COMMENT ON TABLE opex_transactions IS 'Espejo de transacciones OPEX desde Metabase. El agente lee esta tabla para análisis; procesado=false marca pendientes.';

-- ============================================================
-- 4. BASELINE HISTÓRICO
-- Promedio móvil y desviación estándar por (tipo_servicio, zona, contratista).
-- Se recalcula semanalmente por el agente.
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_baseline (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contratista_id   TEXT NOT NULL,
  tipo_servicio    TEXT NOT NULL,
  zona             TEXT NOT NULL,
  ventana_meses    INTEGER NOT NULL DEFAULT 3,
  n_observaciones  INTEGER NOT NULL,
  costo_medio      NUMERIC(18,4) NOT NULL,
  costo_std        NUMERIC(18,4) NOT NULL,
  costo_p10        NUMERIC(18,4),
  costo_p90        NUMERIC(18,4),
  fecha_calculo    DATE NOT NULL,
  periodo_desde    DATE NOT NULL,
  periodo_hasta    DATE NOT NULL,
  CONSTRAINT chk_obs_minimas CHECK (n_observaciones >= 0)
);

CREATE UNIQUE INDEX idx_baseline_unique ON opex_baseline (contratista_id, tipo_servicio, zona, ventana_meses, fecha_calculo);

COMMENT ON TABLE opex_baseline IS 'Baseline histórico por (contratista, tipo_servicio, zona). Se usa para z-score en detector de outliers. Requiere mínimo 10 obs para ser válido.';

-- ============================================================
-- 5. REGLAS DE NEGOCIO VERSIONADAS (umbrales configurables)
-- Esta es la única tabla que el agente puede mutar (via recalibración aprobada).
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_rules (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_regla     TEXT NOT NULL,         -- A1, A2, ..., A14
  nombre           TEXT NOT NULL,
  descripcion      TEXT,
  tipo_detector    TEXT NOT NULL,         -- tarifa, outlier, duplicado, soporte, patron, fuga
  severidad        TEXT NOT NULL CHECK (severidad IN ('baja','media','alta','critica')),
  -- umbrales principales
  umbral_pct_min   NUMERIC(8,4),          -- % mínimo de desvío para activar
  umbral_pct_max   NUMERIC(8,4),          -- % máximo (si hay rango)
  umbral_zscore    NUMERIC(6,3),          -- z-score para detectores estadísticos
  umbral_n_alertas INTEGER,               -- N alertas para patrón sistemático
  umbral_dias      INTEGER,               -- días para regla de soporte
  -- acción por defecto
  accion_default   TEXT[],                -- ['slack','ticket','correo_borrador']
  requiere_aprobacion BOOLEAN DEFAULT TRUE,
  -- métricas evolutivas
  fp_rate          NUMERIC(5,4) DEFAULT 0, -- tasa de falsos positivos rolling 30 días
  tp_rate          NUMERIC(5,4) DEFAULT 0,
  n_activaciones   INTEGER DEFAULT 0,
  n_falsos_positivos INTEGER DEFAULT 0,
  -- versionado
  activa           BOOLEAN DEFAULT TRUE,
  version          INTEGER NOT NULL DEFAULT 1,
  effective_from   DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_to     DATE,
  creado_en        TIMESTAMPTZ DEFAULT NOW(),
  modificado_en    TIMESTAMPTZ DEFAULT NOW(),
  modificado_por   TEXT
);

CREATE INDEX idx_rules_codigo ON opex_rules (codigo_regla, activa);

COMMENT ON TABLE opex_rules IS 'Umbrales y configuración de reglas de detección. Única tabla mutable por recalibración. Cambios requieren aprobación del analista.';

-- Insertar reglas iniciales (valores conservadores para MVP)
INSERT INTO opex_rules (codigo_regla, nombre, tipo_detector, severidad, umbral_pct_min, umbral_pct_max, accion_default, effective_from) VALUES
('A1',  'Sobrecobro leve vs tarifa',        'tarifa',    'baja',    3.0,  5.0,  ARRAY['log'],                               CURRENT_DATE),
('A2',  'Sobrecobro moderado vs tarifa',     'tarifa',    'media',   5.0,  15.0, ARRAY['slack','ticket'],                    CURRENT_DATE),
('A3',  'Sobrecobro crítico vs tarifa',      'tarifa',    'alta',    15.0, NULL, ARRAY['slack_urgente','correo_borrador'],    CURRENT_DATE),
('A4',  'Outlier estadístico moderado',      'outlier',   'media',   NULL, NULL, ARRAY['slack','ticket'],                    CURRENT_DATE),
('A5',  'Outlier estadístico crítico',       'outlier',   'alta',    NULL, NULL, ARRAY['slack_urgente','correo_borrador'],    CURRENT_DATE),
('A6',  'Duplicado probable',               'duplicado', 'alta',    NULL, NULL, ARRAY['slack','ticket'],                    CURRENT_DATE),
('A7',  'Sin soporte documental > 7 días',  'soporte',   'media',   NULL, NULL, ARRAY['correo_borrador'],                   CURRENT_DATE),
('A8',  'Desvío budget intra-mes > 5%',     'budget',    'media',   5.0,  10.0, ARRAY['slack'],                             CURRENT_DATE),
('A9',  'Desvío budget intra-mes > 10%',    'budget',    'alta',    10.0, 20.0, ARRAY['slack_urgente','escalamiento'],       CURRENT_DATE),
('A10', 'Forecast > budget x1.10',          'forecast',  'alta',    10.0, NULL, ARRAY['slack_urgente'],                     CURRENT_DATE),
('A11', 'Patrón sistemático contratista',   'patron',    'critica', NULL, NULL, ARRAY['slack_critico','ticket'],             CURRENT_DATE),
('A12', 'Fuga silenciosa de margen',        'fuga',      'alta',    NULL, NULL, ARRAY['slack','ticket'],                    CURRENT_DATE),
('A13', 'Material sin OT asociada',         'soporte',   'media',   NULL, NULL, ARRAY['ticket'],                            CURRENT_DATE),
('A14', 'Contratista recurrente sin confirmar', 'patron', 'critica', NULL, NULL, ARRAY['slack_critico'],                    CURRENT_DATE)
ON CONFLICT DO NOTHING;

-- Setear umbrales especiales
UPDATE opex_rules SET umbral_zscore = 2.5, umbral_n_alertas = NULL WHERE codigo_regla = 'A4';
UPDATE opex_rules SET umbral_zscore = 3.5, umbral_n_alertas = NULL WHERE codigo_regla = 'A5';
UPDATE opex_rules SET umbral_n_alertas = 3, umbral_dias = 30 WHERE codigo_regla = 'A11';
UPDATE opex_rules SET umbral_dias = 7 WHERE codigo_regla = 'A7';
UPDATE opex_rules SET umbral_n_alertas = 3 WHERE codigo_regla = 'A14';

-- ============================================================
-- 6. ALERTAS GENERADAS
-- Log inmutable de todas las alertas. Solo append.
-- Estados: open → ack → in_progress → resolved | false_positive
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_alerts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_alerta    TEXT NOT NULL,         -- A1..A14
  rule_id          UUID REFERENCES opex_rules(id),
  tx_id            UUID REFERENCES opex_transactions(id),
  ot_id            TEXT,
  contratista_id   TEXT NOT NULL,
  contratista_nombre TEXT,
  tipo_servicio    TEXT,
  zona             TEXT,
  -- valores observados vs esperados
  valor_observado  NUMERIC(18,4),
  valor_esperado   NUMERIC(18,4),
  delta_absoluto   NUMERIC(18,4),
  delta_pct        NUMERIC(8,4),
  zscore           NUMERIC(8,4),
  -- clasificación
  severidad        TEXT NOT NULL,
  estado           TEXT NOT NULL DEFAULT 'open' CHECK (estado IN ('open','ack','in_progress','resolved','false_positive')),
  -- evidencia forense
  query_evidencia  TEXT,                  -- query SQL que generó la alerta
  snapshot_json    JSONB,                 -- snapshot de datos al momento de la alerta
  -- narración IA
  causa_raiz_sugerida TEXT,              -- clasificación LLM
  narrativa_corta  TEXT,                 -- frase explicativa
  -- trazabilidad
  generada_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ack_en           TIMESTAMPTZ,
  ack_por          TEXT,
  resuelta_en      TIMESTAMPTZ,
  resuelta_por     TEXT,
  -- versiones usadas para la comparación
  tarifario_version INTEGER,
  budget_version   INTEGER,
  rule_version     INTEGER
);

CREATE INDEX idx_alerts_estado ON opex_alerts (estado, severidad, generada_en DESC);
CREATE INDEX idx_alerts_contratista ON opex_alerts (contratista_id, generada_en DESC);
CREATE INDEX idx_alerts_open ON opex_alerts (estado) WHERE estado = 'open';

COMMENT ON TABLE opex_alerts IS 'Alertas generadas por el agente. Inmutable (append-only). Trazabilidad forense completa con query + snapshot.';

-- ============================================================
-- 7. CASOS — CIERRE DE ALERTAS (mecanismo evolutivo)
-- Cada alerta cerrada genera un caso con causa raíz y veredicto.
-- Esta tabla alimenta la recalibración de umbrales.
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_cases (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id         UUID NOT NULL REFERENCES opex_alerts(id),
  codigo_alerta    TEXT NOT NULL,
  contratista_id   TEXT,
  tipo_servicio    TEXT,
  zona             TEXT,
  -- veredicto humano
  veredicto        TEXT NOT NULL CHECK (veredicto IN ('confirmado','false_positive','pendiente','escalado')),
  causa_raiz_codigo TEXT,                 -- código del catálogo de causas
  causa_raiz_texto TEXT,                  -- texto libre del analista
  causa_raiz_ia    TEXT,                  -- lo que sugirió la IA
  ia_acertó        BOOLEAN,               -- si la causa raíz IA fue correcta
  -- resolución
  accion_tomada    TEXT,
  monto_recuperado NUMERIC(18,2) DEFAULT 0,
  monto_ajustado   NUMERIC(18,2) DEFAULT 0,
  -- tiempos
  cerrado_en       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cerrado_por      TEXT,
  tiempo_resolucion_horas NUMERIC(8,2),  -- calculado automáticamente
  -- canal de cierre
  canal_cierre     TEXT DEFAULT 'slack'   -- slack, dashboard, api
);

CREATE INDEX idx_cases_alert ON opex_cases (alert_id);
CREATE INDEX idx_cases_contratista ON opex_cases (contratista_id, cerrado_en DESC);
CREATE INDEX idx_cases_veredicto ON opex_cases (veredicto, cerrado_en DESC);
CREATE INDEX idx_cases_regla ON opex_cases (codigo_alerta, cerrado_en DESC);

COMMENT ON TABLE opex_cases IS 'Cierre de alertas con veredicto humano. Alimenta fp_rate en opex_rules y el motor de recalibración mensual.';

-- ============================================================
-- 8. COLA DE APROBACIÓN (comunicaciones pendientes)
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_approvals (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id         UUID REFERENCES opex_alerts(id),
  tipo_comunicacion TEXT NOT NULL CHECK (tipo_comunicacion IN ('correo_contratista','ticket_interno','slack_urgente','correo_operaciones')),
  destinatario     TEXT NOT NULL,
  asunto           TEXT,
  cuerpo_borrador  TEXT NOT NULL,
  contexto_json    JSONB,                 -- datos de la alerta para el aprobador
  estado           TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobado','rechazado','editado','enviado','expirado')),
  -- aprobación
  aprobado_en      TIMESTAMPTZ,
  aprobado_por     TEXT,
  cuerpo_editado   TEXT,                  -- si el aprobador editó el borrador
  motivo_rechazo   TEXT,
  -- envío
  enviado_en       TIMESTAMPTZ,
  -- expiración
  expira_en        TIMESTAMPTZ,           -- si no se aprueba antes, pasa a revisión manual
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Slack metadata
  slack_ts         TEXT,                  -- timestamp del mensaje Slack con botones
  slack_channel    TEXT
);

CREATE INDEX idx_approvals_estado ON opex_approvals (estado, creado_en DESC);
CREATE INDEX idx_approvals_pendiente ON opex_approvals (estado) WHERE estado = 'pendiente';

COMMENT ON TABLE opex_approvals IS 'Cola de comunicaciones pendientes de aprobación humana. Todo correo externo y ticket pasa por aquí antes de enviarse.';

-- ============================================================
-- 9. LOG DE COMUNICACIONES ENVIADAS (inmutable)
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_communications (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_id      UUID NOT NULL REFERENCES opex_approvals(id),
  alert_id         UUID REFERENCES opex_alerts(id),
  tipo_comunicacion TEXT NOT NULL,
  destinatario     TEXT NOT NULL,
  asunto           TEXT,
  cuerpo_final     TEXT NOT NULL,
  enviado_en       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  enviado_por      TEXT,
  canal            TEXT,                  -- smtp, slack_api, jira_api, etc.
  respuesta_recibida TEXT,
  respuesta_en     TIMESTAMPTZ,
  id_externo       TEXT                   -- ID del ticket/correo en el sistema externo
);

COMMENT ON TABLE opex_communications IS 'Log inmutable de toda comunicación enviada desde el agente. Retención 24 meses.';

-- ============================================================
-- 10. FORECASTS ROLLING
-- Una fila por (categoría, zona, contratista, fecha_calculo).
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_forecasts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anio             INTEGER NOT NULL,
  mes              INTEGER NOT NULL,
  fecha_calculo    DATE NOT NULL,         -- día en que se calculó el forecast
  dia_del_mes      INTEGER NOT NULL,      -- día en que estamos al calcular
  -- dimensiones de agregación
  zona             TEXT,
  contratista_id   TEXT,
  categoria_contable TEXT,
  tipo_servicio    TEXT,
  -- valores
  ejecutado_mtd    NUMERIC(18,2) NOT NULL,
  ritmo_ewma       NUMERIC(18,4),         -- gasto diario EWMA
  pipeline_esperado NUMERIC(18,2) DEFAULT 0,
  proyeccion_central NUMERIC(18,2) NOT NULL,
  proyeccion_p20   NUMERIC(18,2),         -- banda baja
  proyeccion_p80   NUMERIC(18,2),         -- banda alta
  budget_mes       NUMERIC(18,2),
  desviacion_pct   NUMERIC(8,4),          -- (proyeccion_central - budget) / budget
  nivel_confianza  NUMERIC(5,4),
  metodo           TEXT DEFAULT 'ewma',   -- ewma, regresion, promedio_historico
  -- backtest
  mae_backtest_pct NUMERIC(8,4),
  -- alertas de forecast generadas
  alerta_generada  BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_forecasts_periodo ON opex_forecasts (anio, mes, fecha_calculo DESC);

COMMENT ON TABLE opex_forecasts IS 'Proyecciones rolling de cierre mensual. Se recalcula diariamente. Incluye banda de confianza P20/P80 y resultado de backtest.';

-- ============================================================
-- 11. CIERRES MENSUALES
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_closes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anio             INTEGER NOT NULL,
  mes              INTEGER NOT NULL,
  -- ejecución total
  ejecucion_total  NUMERIC(18,2) NOT NULL,
  budget_total     NUMERIC(18,2),
  variacion_pct    NUMERIC(8,4),
  -- resumen de alertas
  alertas_detectadas INTEGER DEFAULT 0,
  alertas_cerradas INTEGER DEFAULT 0,
  alertas_abiertas_cierre INTEGER DEFAULT 0,
  falsos_positivos INTEGER DEFAULT 0,
  monto_recuperado NUMERIC(18,2) DEFAULT 0,
  -- narrativa IA
  narrativa_ejecutiva TEXT,
  top_drivers_json JSONB,                 -- top 5 drivers de variación
  -- artefactos
  pivot_zona_csv   TEXT,
  pivot_contratista_csv TEXT,
  pivot_tipo_csv   TEXT,
  -- estado del cierre
  estado           TEXT DEFAULT 'borrador' CHECK (estado IN ('borrador','revisado','aprobado')),
  -- forecast vs real (para backtest)
  forecast_dia20   NUMERIC(18,2),         -- proyección que había el día 20
  error_forecast_pct NUMERIC(8,4),        -- (forecast_dia20 - real) / real
  -- metadata
  generado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  aprobado_en      TIMESTAMPTZ,
  aprobado_por     TEXT,
  UNIQUE (anio, mes)
);

COMMENT ON TABLE opex_closes IS 'Resumen de cierre mensual con narrativa IA, pivots y métricas de precisión del forecast. Un registro por mes.';

-- ============================================================
-- 12. LOG DE EJECUCIÓN DEL AGENTE
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_agent_log (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id      TEXT NOT NULL,         -- identificador del workflow n8n
  workflow_nombre  TEXT NOT NULL,
  run_id           TEXT,                  -- ID del run en n8n
  inicio           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fin              TIMESTAMPTZ,
  duracion_seg     NUMERIC(8,2),
  estado           TEXT CHECK (estado IN ('ok','error','advertencia','dry_run')),
  registros_procesados INTEGER DEFAULT 0,
  alertas_generadas INTEGER DEFAULT 0,
  errores_json     JSONB,
  dry_run          BOOLEAN DEFAULT FALSE,  -- modo simulación activo
  kill_switch_activo BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_agent_log_workflow ON opex_agent_log (workflow_id, inicio DESC);
CREATE INDEX idx_agent_log_errores ON opex_agent_log (estado) WHERE estado = 'error';

COMMENT ON TABLE opex_agent_log IS 'Log de ejecución de todos los workflows. Kill switch y modo dry_run registrados aquí.';

-- ============================================================
-- CONFIGURACIÓN DEL AGENTE (tabla de control global)
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_config (
  clave            TEXT PRIMARY KEY,
  valor            TEXT NOT NULL,
  descripcion      TEXT,
  modificado_en    TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO opex_config (clave, valor, descripcion) VALUES
  ('kill_switch',         'false',                'Si true, el agente no genera alertas ni envía comunicaciones'),
  ('dry_run',             'false',                'Si true, el agente genera todo pero no envía correos ni tickets'),
  ('slack_channel_alertas', '#opex-alertas',      'Canal Slack para alertas operativas'),
  ('slack_channel_cierre',  '#opex-cierre',       'Canal Slack para cierre mensual'),
  ('slack_channel_errores', '#bia-opex-errors',   'Canal Slack para errores del agente'),
  ('slack_channel_aprobacion', '#opex-aprobacion','Canal Slack para cola de aprobación'),
  ('email_remitente',     'opex@bia.app',          'Email de salida para comunicaciones a contratistas'),
  ('timeout_aprobacion_h', '48',                  'Horas antes de que una aprobación pendiente expire'),
  ('metabase_last_sync',  '2026-01-01T00:00:00Z', 'Última sincronización con Metabase (actualiza el agente)'),
  ('forecast_alpha',      '0.3',                  'Parámetro alpha para EWMA del forecast'),
  ('baseline_ventana_meses', '3',                 'Ventana de meses para calcular baseline histórico'),
  ('fp_rate_threshold',   '0.40',                 'Tasa de FP que dispara sugerencia de recalibración')
ON CONFLICT (clave) DO NOTHING;

COMMENT ON TABLE opex_config IS 'Configuración global del agente. Kill switch y dry_run se leen al inicio de cada workflow.';

-- ============================================================
-- VISTAS DE CONVENIENCIA
-- ============================================================

-- Alertas abiertas con contexto completo
CREATE OR REPLACE VIEW v_alertas_abiertas AS
SELECT
  a.id,
  a.codigo_alerta,
  a.severidad,
  a.estado,
  a.contratista_nombre,
  a.tipo_servicio,
  a.zona,
  a.valor_observado,
  a.valor_esperado,
  a.delta_pct,
  a.causa_raiz_sugerida,
  a.narrativa_corta,
  a.generada_en,
  EXTRACT(EPOCH FROM (NOW() - a.generada_en))/3600 AS horas_abierta
FROM opex_alerts a
WHERE a.estado IN ('open','ack','in_progress')
ORDER BY
  CASE a.severidad WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END,
  a.generada_en DESC;

-- Tasa de falsos positivos por regla (últimos 30 días)
CREATE OR REPLACE VIEW v_fp_rate_por_regla AS
SELECT
  c.codigo_alerta,
  COUNT(*) AS total_casos,
  SUM(CASE WHEN c.veredicto = 'false_positive' THEN 1 ELSE 0 END) AS falsos_positivos,
  ROUND(SUM(CASE WHEN c.veredicto = 'false_positive' THEN 1.0 ELSE 0 END) / NULLIF(COUNT(*),0), 4) AS fp_rate,
  AVG(c.tiempo_resolucion_horas) AS tiempo_medio_horas
FROM opex_cases c
WHERE c.cerrado_en >= NOW() - INTERVAL '30 days'
GROUP BY c.codigo_alerta;

-- Resumen ejecutivo del mes en curso
CREATE OR REPLACE VIEW v_resumen_mes_actual AS
WITH mes AS (
  SELECT
    EXTRACT(YEAR FROM NOW())::INTEGER AS anio,
    EXTRACT(MONTH FROM NOW())::INTEGER AS mes
)
SELECT
  m.anio,
  m.mes,
  COALESCE(SUM(t.costo_total), 0) AS ejecutado_mtd,
  COALESCE((SELECT SUM(b.monto_budget) FROM opex_budget b
            WHERE b.anio = m.anio AND b.mes = m.mes), 0) AS budget_mes,
  COUNT(DISTINCT a.id) FILTER (WHERE a.estado IN ('open','ack','in_progress')) AS alertas_abiertas,
  COUNT(DISTINCT a.id) FILTER (WHERE a.severidad IN ('alta','critica') AND a.estado IN ('open','ack')) AS alertas_criticas_abiertas
FROM mes m
LEFT JOIN opex_transactions t ON EXTRACT(YEAR FROM t.fecha_tx) = m.anio
  AND EXTRACT(MONTH FROM t.fecha_tx) = m.mes
LEFT JOIN opex_alerts a ON EXTRACT(YEAR FROM a.generada_en) = m.anio
  AND EXTRACT(MONTH FROM a.generada_en) = m.mes
GROUP BY m.anio, m.mes;

-- ============================================================
-- FUNCIONES DE UTILIDAD
-- ============================================================

-- Obtener tarifa vigente a una fecha dada
CREATE OR REPLACE FUNCTION get_tarifa_vigente(
  p_contratista_id TEXT,
  p_tipo_servicio  TEXT,
  p_zona           TEXT,
  p_fecha          DATE
) RETURNS TABLE (
  tarifa           NUMERIC,
  tolerancia_pct   NUMERIC,
  unidad           TEXT,
  version          INTEGER
) AS $$
  SELECT tarifa, tolerancia_pct, unidad, version
  FROM opex_tarifario
  WHERE contratista_id = p_contratista_id
    AND tipo_servicio = p_tipo_servicio
    AND (zona = p_zona OR zona IS NULL)
    AND effective_from <= p_fecha
    AND (effective_to IS NULL OR effective_to >= p_fecha)
  ORDER BY (zona = p_zona) DESC, effective_from DESC
  LIMIT 1;
$$ LANGUAGE sql STABLE;

-- Calcular z-score para una transacción
CREATE OR REPLACE FUNCTION get_zscore(
  p_costo          NUMERIC,
  p_contratista_id TEXT,
  p_tipo_servicio  TEXT,
  p_zona           TEXT
) RETURNS NUMERIC AS $$
DECLARE
  v_media NUMERIC;
  v_std   NUMERIC;
  v_n     INTEGER;
BEGIN
  SELECT costo_medio, costo_std, n_observaciones
  INTO v_media, v_std, v_n
  FROM opex_baseline
  WHERE contratista_id = p_contratista_id
    AND tipo_servicio = p_tipo_servicio
    AND zona = p_zona
    AND n_observaciones >= 10
  ORDER BY fecha_calculo DESC
  LIMIT 1;

  IF v_std IS NULL OR v_std = 0 THEN
    RETURN NULL;
  END IF;

  RETURN (p_costo - v_media) / v_std;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================
-- ROW LEVEL SECURITY (recomendado en Supabase)
-- Habilitar RLS en tablas sensibles y restringir acceso por rol.
-- ============================================================

ALTER TABLE opex_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE opex_communications ENABLE ROW LEVEL SECURITY;
ALTER TABLE opex_cases ENABLE ROW LEVEL SECURITY;

-- Política: el service_role (n8n) tiene acceso total; otros roles son read-only
-- (Ajustar según roles de Supabase de tu proyecto)

CREATE POLICY "service_role_all_alerts" ON opex_alerts
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "service_role_all_comms" ON opex_communications
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "service_role_all_cases" ON opex_cases
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================================
-- FIN DEL SCHEMA
-- Verificación: SELECT table_name FROM information_schema.tables
--               WHERE table_schema = 'public' AND table_name LIKE 'opex_%';
-- Esperado: 12 tablas + 1 tabla config
-- ============================================================
