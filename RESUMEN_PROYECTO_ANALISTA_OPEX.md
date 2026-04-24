# Analista OPEX Virtual BIA — Resumen del Proyecto

**Fecha de corte:** 2026-04-24  
**Estado:** FASE 1 OPERATIVA — los 9 workflows activos en n8n, datos reales fluyendo

---

## Qué es esto

Agente autónomo en n8n que monitorea el gasto OPEX de BIA Energy contra tarifarios contratados, presupuesto mensual y baseline histórico. Detecta anomalías, proyecta el cierre mensual con EWMA, y dispara alertas a Slack con aprobación humana. Cada cierre de alerta retroalimenta un mecanismo evolutivo que recalibra umbrales automáticamente.

---

## Stack

| Componente | Detalle |
|---|---|
| **n8n cloud** | Proyecto "Oráculo del OPEX" — 9 workflows activos |
| **Supabase (Postgres)** | Session Pooler: `aws-1-us-east-1.pooler.supabase.com`, user `postgres.jgyvgckbintxqrihitcw`, SSL Ignore, port 5432. Credential ID: 2 |
| **Google Sheets** | Service Account "Google OPEX BIA" (credential ID 4). Sheet tarifarios ID: `1ATh2kaZZHnWAh8UHDJKKYd5lccqvUAolU6ElJhAU4zk` |
| **Slack** | Credential ID 3 "Slack OPEX BIA". Canales: alertas `C0AVCTBV665`, aprobacion `C0AUWJ91V1T`, cierre `C0AUXUFH1HU`, errors `C0AUTK8B1HR` |
| **Metabase** | `https://bia.metabaseapp.com` — Card principal: 66793 "Costos asociados a opex" |
| **LLM** | Gemini 2.0 Flash — credential "Gemini API BIA" |

---

## Estructura de archivos

```
Analista Opex/
├── Documentos analista opex/
│   ├── FASE_0_FUNDACIONES/
│   │   ├── 00_supabase_schema.sql          ← DDL completo de las 12 tablas
│   │   └── 00b_tarifario_or_patch.sql      ← Patch: OR grupos, get_tarifa_vigente(), incrementos jornada
│   ├── FASE_1_WORKFLOWS/
│   │   ├── wf_01_data_sync_drive.json      ← ✅ ACTIVO — Sync tarifarios Google Sheets → Supabase (cron 06:00)
│   │   └── wf_02_opex_monitor.json         ← ✅ ACTIVO — Monitor Metabase → alertas (cron cada 2h)
│   │   ├── wf_03_daily_slack_summary.json  ← ✅ ACTIVO — Resumen diario 07:30 Slack
│   │   └── wf_04_slack_approval_webhook.json ← ✅ ACTIVO — Webhook aprobaciones Slack
│   ├── FASE_2_WORKFLOWS/
│   │   ├── wf_05_anomaly_detector.json     ← ✅ ACTIVO — Detector anomalías multi-capa
│   │   ├── wf_06_forecast_rolling.json     ← ✅ ACTIVO — EWMA forecast + alertas budget
│   │   └── wf_07_monthly_close.json        ← ✅ ACTIVO — Cierre mensual automatizado
│   └── FASE_3_EVOLUTIVO/
│       ├── wf_08_alert_feedback_loop.json  ← ✅ ACTIVO — Feedback loop cierre alertas
│       └── wf_09_monthly_recalibration.json ← ✅ ACTIVO — Recalibración mensual umbrales
├── metabase_cards_n8n_documentation.md    ← Documentación cards Metabase con schemas exactos
└── RESUMEN_PROYECTO_ANALISTA_OPEX.md      ← Este archivo
```

---

## Schema Supabase

### Tablas principales

```sql
opex_tarifario          -- Tarifas versionadas por contratista+item+OR grupo+año
opex_budget             -- Presupuesto mensual por zona/contratista/categoría
opex_transactions       -- Transacciones OPEX espejo de Metabase (fuente de verdad)
opex_alerts             -- Alertas generadas con estado trazable
opex_cases              -- Cierre de alertas: causa raíz, resolución, veredicto
opex_approvals          -- Cola de aprobación (comunicaciones pendientes)
opex_communications     -- Log inmutable de mensajes enviados
opex_forecasts          -- Proyecciones rolling con banda de confianza (P80)
opex_closes             -- Cierres mensuales generados
opex_rules              -- Umbrales versionados (mutable para recalibración)
opex_agent_log          -- Log de ejecución del agente
opex_or_mapping         -- 23 ORs → 3 grupos tarifarios + zona geográfica
```

### Funciones Postgres clave

```sql
-- Resuelve tarifa vigente aplicando incremento de jornada
get_tarifa_vigente(
  p_contratista_id TEXT,
  p_item_codigo    INTEGER,
  p_or_nombre      TEXT,
  p_fecha          DATE DEFAULT CURRENT_DATE,
  p_jornada        TEXT DEFAULT 'diurna'
) RETURNS NUMERIC

-- Helper zona desde nombre OR
get_zona_from_or(p_or_nombre TEXT) RETURNS TEXT
```

### OR grupos tarifarios (opex_or_mapping)

| Grupo | ORs |
|---|---|
| `ENEL_AIRE_EMCALI_AFINIA` | ENEL CUNDINAMARCA, AIRE CARIBE_SOL, AFINIA CARIBE_MAR, EMCALI CALI |
| `CELSIA_ELECTROHUILA_ESSA` | CELSIA_VALLE, CELSIA_TOLIMA, ELECTROHUILA HUILA, ESSA SANTANDER |
| `OTROS_OR` | CEDENAR, CENS, CEO, CETSA, CHEC, EBSA, EDEQ, EEP, EMCARTAGO, EMSA, ENERCA, ENER RAM, EPM (13 ORs) |

### Incrementos de jornada (opex_config)

```
increment_nocturna:          0.20  (+20% sobre tarifa base)
increment_festiva_diurna:    0.25  (+25% sobre tarifa base)
increment_festiva_nocturna:  0.35  (+35% sobre tarifa base)
```

---

## Google Sheets — Tarifarios BIA

**Archivo:** ID `1ATh2kaZZHnWAh8UHDJKKYd5lccqvUAolU6ElJhAU4zk`

**Pestaña `Contratistas`** (registro maestro de contratistas):

| Columna | Descripción |
|---|---|
| `contratista_id` | ID único en mayúsculas y guiones bajos (ej: `GMAS`, `AR_INGENIERIA`) |
| `sheets_file_id` | ID del Google Sheet con el tarifario (mismo para todos: el ID del archivo) |
| `hoja` | Nombre exacto de la pestaña del contratista en el Sheet (ej: `tarifario GMAS`) |
| `activo` | `si` / `no` — controla si WF-01 sincroniza ese contratista |

**Pestañas de tarifario** (una por contratista activo):

| Columna | Descripción |
|---|---|
| `item_codigo` | Número entero del ítem (1–67) |
| `actividad` | Descripción de la actividad |
| `ENEL_AIRE_EMCALI_AFINIA` | Tarifa COP para ese grupo OR |
| `CELSIA_ELECTROHUILA_ESSA` | Tarifa COP para ese grupo OR |
| `OTROS_OR` | Tarifa COP para ese grupo OR |

**Contratistas activos (18):** GMAS, POWER_GRID, DR_TELEMEDIDA, SGE, JEM, AR_INGENIERIA, C3, C3_BOGOTA, ISELEC, DISELEC, GATRIA, ISEMEC, ISEMEC_BOGOTA, S&SE, REHOBOT, MONTAJES_MTE, ELECPROYECTOS, MCR

---

## Metabase — Card 66793 "Costos asociados a opex"

**Endpoint:** `POST https://bia.metabaseapp.com/api/card/66793/query/json`  
**Header:** `x-api-key: <API_KEY>`  
**Body:** `{}`

**Columnas clave usadas en WF-02:**

| Columna Metabase | Campo en opex_transactions | Notas |
|---|---|---|
| `titulo` | `tx_id_fuente` / `ot_id` | ID único OT: `{tipo}_{codigo_bia}_{num}` |
| `contratista` | `contratista_nombre` | Se normaliza a `contratista_id` (UPPER + `_`) |
| `tipo_de_servicio` | `tipo_servicio` | |
| `mercado` | `zona` | Costa / Interior / Centro |
| `operador_de_red` | `or_nombre` | Nombre exacto del OR |
| `fecha_programada` | `fecha_tx` | Se toma solo la parte DATE |
| `total_cost` | `costo_total` / `costo_unitario` | Ya calculado en Metabase |
| `fase_actual` | `tiene_acta_cierre` | `true` si `fase_actual === 'Cierre Exitoso'` |
| `journey` | `notas_ot` | Historial de fases |

**Volumen:** ~26,141 filas totales — se filtran a últimos 30 días → ~868 filas útiles por run.

---

## WF-01 — Sync Tarifarios (cron 06:00 diario)

**Flujo:**
```
Cron → Kill Switch → ¿Activo? → Sheets: Leer Contratistas
  → Code: Filtrar Activos → SplitInBatches(1)
    → [output 1 = loop] Sheets: Leer Tarifario Contratista
      → Code: Unpivot OR Grupos → Postgres: Upsert Tarifario
        → Log Iteración → [volver a Split]
    → [output 0 = done] fin
```

**Errores resueltos:**
- `SplitInBatches` output 0 = "done" (no loop). La conexión a Sheets debe ir al **output 1** (índice 1 en JSON)
- `Log Iteración`: usar `$input.first().json.contratista_id` — nunca `$('Split').item.json` cuando hay múltiples ítems upstream (pairing se pierde)
- Sheet Name field: expresión `={{ $json.hoja }}` debe estar en modo expresión (confirmar en n8n UI)
- Rama Budget: desconectada hasta crear el Sheet de presupuesto

**Resultado:** 3,600+ tarifas cargadas (18 contratistas × ~67 ítems × 3 OR grupos)

---

## WF-02 — Monitor OPEX (cron cada 2h)

**Flujo:**
```
Cron → Kill Switch → ¿Activo? → Metabase: Fetch Costos OPEX (HTTP POST)
  → Code: Mapear Metabase → Transactions (filtro 30 días, normalización)
    → Code: Build Batch INSERT (dedup por tx_id_fuente)
      → ¿Hay datos? → Postgres: Upsert Batch Transactions (1 sola query)
        → Query Enriquecido con Tarifas (CTE + get_tarifa_vigente)
          → Motor de Reglas y Severidad
            → ¿Hay alertas? → Insertar Alertas en Supabase
                            → Agrupar Alertas Urgentes → ¿Urgentes? → Slack
                            → Marcar Transacciones Procesadas
```

**Alertas implementadas (Motor de Reglas):**

| Código | Condición | Severidad |
|---|---|---|
| A1 | `costo_total > tarifa_vigente * 1.20` | alta |
| A2 | `costo_total > tarifa_vigente * 1.10` | media |
| A3 | `!tiene_acta_cierre && días desde OT > 7` | media |
| A4 | `costo_total > baseline_promedio * 1.30` | alta |
| A5 | `costo_total > budget_mes * 0.05` (una sola OT) | alta |
| A7 | `contratista sin tarifas activas` | media |
| A8 | `forecast > budget * 1.05` | media |
| A9 | `≥3 alertas mismo contratista en el mes` | alta |
| A13 | `costo_total > 0 && !tarifa_vigente && contratista ≠ BIA` | media — OR no contratado |

**Query Enriquecido (CTE):**
```sql
WITH enriched AS (
  SELECT t.*,
    get_tarifa_vigente(t.contratista_id, i.item_codigo, t.or_nombre, t.fecha_tx::DATE, 'diurna') AS tarifa_vigente,
    i.item_codigo,
    b.monto_budget,
    f.valor_forecast
  FROM opex_transactions t
  LEFT JOIN opex_tarifario i ON i.contratista_id = t.contratista_id
    AND i.actividad ILIKE '%' || t.tipo_servicio || '%' AND i.activa = true
  LEFT JOIN opex_budget b ON b.contratista_id = t.contratista_id
    AND b.mes = EXTRACT(MONTH FROM t.fecha_tx)::INT AND b.anio = EXTRACT(YEAR FROM t.fecha_tx)::INT
  LEFT JOIN opex_forecasts f ON f.contratista_id = t.contratista_id
    AND f.periodo = DATE_TRUNC('month', t.fecha_tx)
  WHERE t.procesado = false
)
SELECT * FROM enriched LIMIT 500;
```

**Errores resueltos:**
- `column "jornada" does not exist`: opex_transactions no tiene esa columna — usar literal `'diurna'`
- `OOM (out of memory)`: 867 queries individuales → consolidado en 1 batch SQL con `Code: Build Batch INSERT`
- `ON CONFLICT DO UPDATE cannot affect row a second time`: Metabase devuelve la misma OT varias veces — **dedup por `tx_id_fuente`** en el Code node antes de construir SQL

**Resultado última ejecución:** 26,141 filas Metabase → 868 filtradas → 414 enriquecidas → 26 alertas generadas

---

## Workflows WF-03 al WF-09 (activos, no modificados en esta sesión)

| WF | Nombre | Trigger | Función |
|---|---|---|---|
| WF-03 | Resumen Diario Slack | Cron 07:30 L-V | Agrega alertas del día, top 3 desviaciones, estado forecast |
| WF-04 | Webhook Aprobaciones | Webhook Slack interactivity | Aprobar/Rechazar/FalsoPositivo → actualiza opex_cases |
| WF-05 | Detector Anomalías | Cron cada 4h | Outlier z-score, duplicados, sin soporte, patrón sistemático |
| WF-06 | Forecast Rolling EWMA | Cron 08:00 diario | EWMA α=0.3, ajuste pipeline OTs, banda P80 |
| WF-07 | Cierre Mensual | Cron día 1 09:00 | Reporte ejecutivo + narrativa Gemini + CSV pivots |
| WF-08 | Feedback Loop | Trigger por cierre alerta | Graba opex_cases, calcula fp_rate por regla |
| WF-09 | Recalibración Mensual | Cron día 3 de mes | Propone ajuste umbrales si fp_rate > 40%, botones Slack |

---

## Pendiente

### Crítico
- **Budget Sheet**: Crear Google Sheet con columnas `mes | anio | zona | contratista_id | categoria | monto_budget` → reconectar rama Budget en WF-01 (actualmente desconectada, placeholder `SHEETS_ID_BUDGET_AQUI`)

### Validación operacional
- Revisar las 26 alertas generadas en Supabase: `SELECT tipo_alerta, severidad, COUNT(*) FROM opex_alerts GROUP BY 1,2;`
- Verificar que WF-04 (aprobaciones Slack) recibe callbacks correctamente — probar botón Aprobar/Rechazar en Slack
- Monitorear WF-03 a las 07:30 del día siguiente para validar resumen diario

### Informativo
- Dos contratistas inactivos tienen mismatch en nombre de pestaña (`MATSIELECTRICAS_REPRE` vs `MATSIELECTRICAS_REPRESENTACIONES`, `D&J_SOLUCIONES_ELECTRICAS` sin pestaña) — no afecta porque ambos tienen `activo: no`

---

## Decisiones de diseño importantes

1. **1 libro Google Sheets, N pestañas**: Un solo archivo "Tarifarios BIA" con una pestaña por contratista más la pestaña `Contratistas` como registro maestro. WF-01 lee la columna `hoja` para saber qué pestaña leer por contratista.

2. **Celda vacía = no opera en ese OR**: Si un contratista no tiene tarifa para un grupo OR, la celda queda vacía en el Excel → WF-01 no inserta esa fila → `get_tarifa_vigente()` devuelve NULL → Motor de Reglas dispara **A13** (operando en OR no contratado).

3. **Batch INSERT único**: Toda la data del run se consolida en un solo `INSERT ... VALUES (r1),(r2),...` para evitar OOM en n8n cloud. Sin dedup previo por `tx_id_fuente`, Postgres lanza error de conflicto duplicado.

4. **Slack formato "text"**: En n8n 1.123.33 el nodo Slack usa `format: "text"`, no `"blocksUi"`.

5. **opex_transactions.procesado**: Flag para que el Query Enriquecido solo procese registros nuevos (`WHERE procesado = false`). Se marca `true` al final del run en "Marcar Transacciones Procesadas".

---

## Comandos de verificación rápida (Supabase SQL Editor)

```sql
-- Estado general
SELECT COUNT(*) FROM opex_transactions;
SELECT COUNT(*) FROM opex_tarifario WHERE activa = true;
SELECT COUNT(*) FROM opex_alerts;

-- Alertas por tipo y severidad
SELECT tipo_alerta, severidad, COUNT(*) 
FROM opex_alerts 
GROUP BY 1, 2 
ORDER BY 3 DESC;

-- Tarifas por contratista
SELECT contratista_id, COUNT(*) as items
FROM opex_tarifario WHERE activa = true
GROUP BY 1 ORDER BY 1;

-- Transacciones sin tarifa (candidatos A13)
SELECT contratista_id, or_nombre, COUNT(*) as txs
FROM opex_transactions
WHERE procesado = false
GROUP BY 1, 2 ORDER BY 3 DESC;
```
