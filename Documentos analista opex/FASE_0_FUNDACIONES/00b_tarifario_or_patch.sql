-- ============================================================
-- PATCH 00B: Adaptar opex_tarifario a estructura real del Excel
-- Ejecutar en Supabase SQL Editor DESPUÉS de 00_supabase_schema.sql
-- ============================================================

-- 1. Recrear opex_tarifario con estructura correcta
DROP TABLE IF EXISTS opex_tarifario CASCADE;

CREATE TABLE opex_tarifario (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contratista_id   TEXT NOT NULL,
  contratista_nombre TEXT,
  item_codigo      INTEGER NOT NULL,
  actividad        TEXT NOT NULL,
  or_grupo         TEXT NOT NULL
                   CHECK (or_grupo IN (
                     'ENEL_AIRE_EMCALI_AFINIA',
                     'CELSIA_ELECTROHUILA_ESSA',
                     'OTROS_OR'
                   )),
  tarifa_cop       NUMERIC(14,2) NOT NULL CHECK (tarifa_cop >= 0),
  anio             INTEGER NOT NULL DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT,
  effective_from   DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_to     DATE,
  activa           BOOLEAN NOT NULL DEFAULT TRUE,
  cargado_en       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (contratista_id, item_codigo, or_grupo, anio)
);

CREATE INDEX idx_tarifario_contratista ON opex_tarifario(contratista_id);
CREATE INDEX idx_tarifario_lookup ON opex_tarifario(contratista_id, item_codigo, or_grupo, activa);

-- 2. Agregar item_codigo y or_nombre a opex_transactions
ALTER TABLE opex_transactions
  ADD COLUMN IF NOT EXISTS item_codigo INTEGER,
  ADD COLUMN IF NOT EXISTS or_nombre   TEXT;

-- 3. Tabla de mapeo OR → grupo tarifario + zona geográfica
CREATE TABLE IF NOT EXISTS opex_or_mapping (
  or_nombre TEXT PRIMARY KEY,
  or_grupo  TEXT NOT NULL
            CHECK (or_grupo IN (
              'ENEL_AIRE_EMCALI_AFINIA',
              'CELSIA_ELECTROHUILA_ESSA',
              'OTROS_OR'
            )),
  zona      TEXT
);

INSERT INTO opex_or_mapping (or_nombre, or_grupo, zona) VALUES
  ('ENEL CUNDINAMARCA',    'ENEL_AIRE_EMCALI_AFINIA', 'Centro'),
  ('AIRE CARIBE_SOL',      'ENEL_AIRE_EMCALI_AFINIA', 'Costa'),
  ('AFINIA CARIBE_MAR',    'ENEL_AIRE_EMCALI_AFINIA', 'Costa'),
  ('EMCALI CALI',          'ENEL_AIRE_EMCALI_AFINIA', 'Interior'),
  ('CELSIA_VALLE VALLE',   'CELSIA_ELECTROHUILA_ESSA', 'Interior'),
  ('CELSIA_TOLIMA TOLIMA', 'CELSIA_ELECTROHUILA_ESSA', 'Interior'),
  ('ELECTROHUILA HUILA',   'CELSIA_ELECTROHUILA_ESSA', 'Interior'),
  ('ESSA SANTANDER',       'CELSIA_ELECTROHUILA_ESSA', 'Interior'),
  ('CEDENAR NARIÑO',       'OTROS_OR', 'Interior'),
  ('CENS NORTE_SANTANDER', 'OTROS_OR', 'Interior'),
  ('CEO CAUCA',            'OTROS_OR', 'Interior'),
  ('CETSA TULUA',          'OTROS_OR', 'Interior'),
  ('CHEC CALDAS',          'OTROS_OR', 'Interior'),
  ('EBSA BOYACA',          'OTROS_OR', 'Interior'),
  ('EDEQ QUINDIO',         'OTROS_OR', 'Interior'),
  ('EEP CARTAGO',          'OTROS_OR', 'Interior'),
  ('EEP PEREIRA',          'OTROS_OR', 'Interior'),
  ('EMCARTAGO',            'OTROS_OR', 'Interior'),
  ('EMSA',                 'OTROS_OR', 'Interior'),
  ('EMSA META',            'OTROS_OR', 'Interior'),
  ('ENERCA CASANARE',      'OTROS_OR', 'Interior'),
  ('ENER RAM SAS',         'OTROS_OR', 'Interior'),
  ('EPM ANTIOQUIA',        'OTROS_OR', 'Interior')
ON CONFLICT (or_nombre) DO UPDATE
  SET or_grupo = EXCLUDED.or_grupo, zona = EXCLUDED.zona;

-- 4. Incrementos de jornada en opex_config (Anexo N°1)
INSERT INTO opex_config (clave, valor, descripcion) VALUES
  ('increment_nocturna',         '0.20', 'Incremento jornada nocturna (+20% sobre tarifa base)'),
  ('increment_festiva_diurna',   '0.25', 'Incremento festiva diurna (+25% sobre tarifa base)'),
  ('increment_festiva_nocturna', '0.35', 'Incremento festiva nocturna (+35% sobre tarifa base)')
ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;

-- 5. Función actualizada: get_tarifa_vigente
DROP FUNCTION IF EXISTS get_tarifa_vigente(TEXT, TEXT, TEXT, DATE);
DROP FUNCTION IF EXISTS get_tarifa_vigente(TEXT, INTEGER, TEXT, DATE, TEXT);

CREATE FUNCTION get_tarifa_vigente(
  p_contratista_id TEXT,
  p_item_codigo    INTEGER,
  p_or_nombre      TEXT,
  p_fecha          DATE DEFAULT CURRENT_DATE,
  p_jornada        TEXT DEFAULT 'diurna'
) RETURNS NUMERIC AS $$
DECLARE
  v_or_grupo    TEXT;
  v_tarifa_base NUMERIC;
  v_incremento  NUMERIC := 0;
BEGIN
  SELECT or_grupo INTO v_or_grupo
  FROM opex_or_mapping WHERE or_nombre = p_or_nombre;
  IF v_or_grupo IS NULL THEN v_or_grupo := 'OTROS_OR'; END IF;

  SELECT tarifa_cop INTO v_tarifa_base
  FROM opex_tarifario
  WHERE contratista_id = p_contratista_id
    AND item_codigo    = p_item_codigo
    AND or_grupo       = v_or_grupo
    AND effective_from <= p_fecha
    AND (effective_to IS NULL OR effective_to >= p_fecha)
    AND activa = true
  ORDER BY effective_from DESC
  LIMIT 1;

  IF v_tarifa_base IS NULL THEN RETURN NULL; END IF;

  IF p_jornada <> 'diurna' THEN
    SELECT COALESCE(valor::NUMERIC, 0) INTO v_incremento
    FROM opex_config WHERE clave = 'increment_' || p_jornada;
  END IF;

  RETURN ROUND(v_tarifa_base * (1 + v_incremento), 2);
END;
$$ LANGUAGE plpgsql STABLE;

-- 6. Helper: zona desde OR
CREATE OR REPLACE FUNCTION get_zona_from_or(p_or_nombre TEXT)
RETURNS TEXT AS $$
  SELECT zona FROM opex_or_mapping WHERE or_nombre = p_or_nombre;
$$ LANGUAGE sql STABLE;

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
SELECT 'opex_tarifario OK' AS resultado
  FROM information_schema.tables
  WHERE table_name = 'opex_tarifario' AND table_schema = 'public';

SELECT 'opex_or_mapping: ' || COUNT(*) || ' ORs' AS resultado
  FROM opex_or_mapping;

SELECT 'incrementos: ' || COUNT(*) || ' configs' AS resultado
  FROM opex_config WHERE clave LIKE 'increment_%';
