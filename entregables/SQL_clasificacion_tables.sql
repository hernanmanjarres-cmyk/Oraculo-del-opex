-- ═══════════════════════════════════════════════════════════════
-- Tablas para el sistema de clasificación interactiva de OTs
-- Ejecutar en Supabase (esquema Oraculo_Opex)
-- ═══════════════════════════════════════════════════════════════

-- 1. Tabla principal de seguimiento por OT
--    Guarda clasificación propuesta, estado de confirmación,
--    referencia al hilo de Slack, y datos de cobro.
CREATE TABLE IF NOT EXISTS "Oraculo_Opex".ot_clasificacion (
  id                    SERIAL PRIMARY KEY,
  codigo_ot             TEXT UNIQUE NOT NULL,
  tipo_de_servicio      TEXT,
  codigo_bia            TEXT,
  nombre_de_frontera    TEXT,
  costo_total           NUMERIC,
  contratista           TEXT,
  fase_actual           TEXT,
  fecha_programada      TEXT,
  periodo               TEXT,
  generada_por          TEXT,
  razon_de_cierre       TEXT,
  observacion_de_cierre TEXT,

  -- Clasificación (propuesta por IA, confirmada/corregida por humano)
  cotizacion            TEXT DEFAULT 'En revisión',
  imputable_a           TEXT DEFAULT 'En revisión',
  motivo_cierre         TEXT DEFAULT 'En revisión',
  comentarios           TEXT,
  clasificacion_estado  TEXT DEFAULT 'pendiente'
    CHECK (clasificacion_estado IN ('pendiente','confirmada','corregida')),

  -- Slack
  slack_channel         TEXT,
  slack_ts              TEXT,       -- message timestamp = thread ID

  -- Datos de cobro (CX llena vía Slack)
  link_customer         TEXT,
  monto_cobro           NUMERIC,
  pipefy_id             TEXT,
  pipefy_reminder_count INT DEFAULT 0,
  caso_cerrado          BOOLEAN DEFAULT FALSE,

  -- Timestamps
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  confirmed_at          TIMESTAMPTZ,
  confirmed_by          TEXT
);

CREATE INDEX IF NOT EXISTS idx_ot_clasif_slack_ts
  ON "Oraculo_Opex".ot_clasificacion (slack_ts);

CREATE INDEX IF NOT EXISTS idx_ot_clasif_estado
  ON "Oraculo_Opex".ot_clasificacion (clasificacion_estado);

CREATE INDEX IF NOT EXISTS idx_ot_clasif_caso_abierto
  ON "Oraculo_Opex".ot_clasificacion (caso_cerrado, pipefy_id)
  WHERE caso_cerrado = FALSE AND pipefy_id IS NULL;


-- 2. Tabla de aprendizaje (memoria del clasificador)
--    Cada corrección humana se guarda aquí.
--    El clasificador consulta los últimos 20 registros antes de tipificar.
CREATE TABLE IF NOT EXISTS "Oraculo_Opex".clasificacion_aprendizaje (
  id                    SERIAL PRIMARY KEY,
  tipo_servicio         TEXT NOT NULL,
  fase_actual           TEXT,
  obs_keywords          TEXT,        -- palabras clave extraídas de la observación
  imputable_propuesto   TEXT,
  motivo_propuesto      TEXT,
  imputable_aceptado    TEXT,
  motivo_aceptado       TEXT,
  fue_corregido         BOOLEAN DEFAULT TRUE,
  correccion_razon      TEXT,        -- por qué el humano corrigió
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_aprendizaje_tipo
  ON "Oraculo_Opex".clasificacion_aprendizaje (tipo_servicio, created_at DESC);
