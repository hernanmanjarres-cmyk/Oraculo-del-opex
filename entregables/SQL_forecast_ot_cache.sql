-- ═══════════════════════════════════════════════════════════════
-- Cache de forecast por OT — Tabla determinística
-- Se actualiza por WF-G antes de generar el resumen.
-- Mantiene el forecast estable entre ejecuciones; solo cambia si
-- la OT es nueva, se reprograma, cambia OR/contratista o se ejecuta/cancela.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "Oraculo_Opex".forecast_ot_cache (
  codigo_ot          TEXT PRIMARY KEY,
  codigo_bia         TEXT,
  contract_id        TEXT,
  service_type_id    TEXT,
  operador_de_red    TEXT,
  tipo_de_medida     TEXT,
  contratista        TEXT,
  fecha_programada   DATE,
  is_bia             BOOLEAN DEFAULT FALSE,

  -- 4 rubros + total
  servicio           NUMERIC,
  materiales         NUMERIC,
  adicionales        NUMERIC,
  transporte         NUMERIC,
  total_ot           NUMERIC,

  -- Estado
  vigente            BOOLEAN DEFAULT TRUE,
  ultima_razon       TEXT,           -- 'nueva' | 'reprogramada' | 'or_cambio' | 'contratista_cambio' | 'medida_cambio'
  ejecutada_o_cancelada_el TIMESTAMPTZ,

  -- Timestamps
  calculado_el       TIMESTAMPTZ DEFAULT NOW(),
  actualizado_el     TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para queries rápidas
CREATE INDEX IF NOT EXISTS idx_forecast_cache_vigente
  ON "Oraculo_Opex".forecast_ot_cache (vigente, fecha_programada);

CREATE INDEX IF NOT EXISTS idx_forecast_cache_actualizado
  ON "Oraculo_Opex".forecast_ot_cache (actualizado_el DESC)
  WHERE vigente = TRUE;

CREATE INDEX IF NOT EXISTS idx_forecast_cache_or
  ON "Oraculo_Opex".forecast_ot_cache (operador_de_red, vigente);


-- ═══════════════════════════════════════════════════════════════
-- Tabla de auditoría: historial de cambios al forecast
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "Oraculo_Opex".forecast_ot_history (
  id                 SERIAL PRIMARY KEY,
  codigo_ot          TEXT NOT NULL,
  razon_cambio       TEXT NOT NULL,    -- 'nueva', 'reprogramada', 'or_cambio', 'contratista_cambio', 'ejecutada', 'cancelada', 'medida_cambio'
  valor_anterior     JSONB,            -- snapshot del cache antes del cambio
  valor_nuevo        JSONB,            -- snapshot después
  created_at         TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_forecast_history_ot
  ON "Oraculo_Opex".forecast_ot_history (codigo_ot, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_forecast_history_recent
  ON "Oraculo_Opex".forecast_ot_history (created_at DESC);


-- ═══════════════════════════════════════════════════════════════
-- Verificación
-- ═══════════════════════════════════════════════════════════════
-- SELECT 'forecast_ot_cache' AS tabla, COUNT(*) FROM "Oraculo_Opex".forecast_ot_cache
-- UNION ALL
-- SELECT 'forecast_ot_history', COUNT(*) FROM "Oraculo_Opex".forecast_ot_history;
