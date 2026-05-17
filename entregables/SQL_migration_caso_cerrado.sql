-- Migración: agregar columna caso_cerrado a ot_clasificacion
-- Si ya existe, no falla (IF NOT EXISTS)

ALTER TABLE "Oraculo_Opex".ot_clasificacion
  ADD COLUMN IF NOT EXISTS caso_cerrado BOOLEAN DEFAULT FALSE;

-- Backfill: marcar como cerrados los que ya tienen pipefy_id Y monto_cobro
UPDATE "Oraculo_Opex".ot_clasificacion
SET caso_cerrado = TRUE
WHERE pipefy_id IS NOT NULL
  AND monto_cobro IS NOT NULL
  AND monto_cobro > 0;

-- Backfill: marcar como cerrados los que NO requieren cobro y ya están confirmados
UPDATE "Oraculo_Opex".ot_clasificacion
SET caso_cerrado = TRUE
WHERE clasificacion_estado IN ('confirmada', 'corregida')
  AND (cotizacion IS NULL OR cotizacion NOT IN ('Sí', 'Si'));

-- Índice para queries rápidas de casos abiertos
CREATE INDEX IF NOT EXISTS idx_ot_clasif_caso_cerrado
  ON "Oraculo_Opex".ot_clasificacion (caso_cerrado);
