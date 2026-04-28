# Fuentes de datos del Agente OPEX — Inventario y plan de construcción

**Fecha:** 28 de abril de 2026
**Autor:** Hernán Manjarrés (con apoyo de Claude)
**Documento prerrequisito:** `Plan_Ejecutivo_Agente_OPEX_BIA.md` (§7 Cards Metabase requeridas)
**Propósito:** Antes de tocar Supabase y n8n (Parte II del plan), dejar definido qué fuentes Metabase ya tenemos, cuáles tienen gaps y qué hay que construir o ajustar para que WF-A pueda alimentar el cerebro.

---

## 1. Resumen ejecutivo

El proyecto necesita **cuatro cards Metabase** alimentando WF-A (ingesta horaria a Supabase): `OPEX_OTS`, `OPEX_ITEMS_OT`, `OPEX_TARIFARIO`, `OPEX_COSTO_SALES`. Adicionalmente, el alcance funcional del rol exige cubrir tres responsabilidades que hoy no tienen fuente clara: **recuperación de OPEX** (cobros a clientes / OR / agentes), **conciliación con contratistas** y **forecast de OPEX** sobre backlog.

Estado actual del catálogo:

| Card requerida (Plan §7) | Estado | Acción siguiente |
|---|---|---|
| `OPEX_OTS` | Parcial — los datos existen pero fragmentados | **Construir** card unificada en colección OPEX-HDMG sobre db `prod-bia-gold` (2344) |
| `OPEX_ITEMS_OT` | No existe — datos en `selected_tariff_items` JSONB sin explotar | **Construir** card que explote el JSONB con `LATERAL jsonb_to_recordset` |
| `OPEX_TARIFARIO` | No existe en Metabase — tarifa vive en `electrician-services-contractor` | **Exponer** vista curada (idealmente en `prod-bia-gold` schema `operations`) |
| `OPEX_COSTO_SALES` | Parcial — solo expuesta en backlog (140 filas) | **Construir** card sobre `sales_crm.fronteras` con histórico completo |

Capacidades del rol con gap de fuente:

| Responsabilidad (marco funcional §6) | Fuente actual | Acción siguiente |
|---|---|---|
| Recuperación de OPEX (cobros) | No identificada | **Investigar** con Finanzas qué tabla registra cobros a clientes/OR (probable `facturacion_dian` o sistema CRM) |
| Conciliación con contratistas | App OPS — no expuesta a BI | **Decidir**: ¿se replica acta/factura a Supabase o el agente lee desde App OPS vía API? |
| Forecast de OPEX | Backlog v3 + payback Sales | **Construir** lógica de forecast en el agente, no requiere card adicional |

---

## 2. Bases de datos disponibles

### 2.1 `prod-bia-gold` (database_id 2344) — **fuente preferida**

Capa curada en formato vista, schema `operations` para ops + schema `retention` para CX. Es la evolución de `prod-bia-bi` y debe ser la fuente única para todo lo nuevo. Tablas relevantes para OPEX:

| Tabla | Granularidad | Uso para el agente |
|---|---|---|
| `operations.opex_costs_general` (22381) | 1 fila por registro de costo (≥1 por visita) | Componentes costo: servicio, material, transporte, otros + contratista |
| `operations.visitas_general` (22375) | 1 fila por visita (uuid `id`) | Estado, tipo de servicio, contratista, electricistas, ciudad |
| `operations.hubspot_general` (22378) | 1 fila por frontera | Master comercial: kam, mercado, OR, fechas de fase, paz y salvo |
| `operations.alcances_general` (22379) | 1 fila por alcance técnico | Pre-instalación: equipos, descargos, viabilidad, payback calculado |
| `operations.tareas_general` (22380) | 1 fila por tarea HubSpot | Trazabilidad del workflow operativo |
| `operations.wms_general` (22377) | 1 fila por ítem de inventario | Equipos y certificados |
| `operations.wms_requerimientos` (22376) | 1 fila por requerimiento | Compras pendientes de equipos |

**Llaves canónicas para joins** (documentadas en cada tabla):

```
hubspot_general.codigo_interno_odoobia (= codigo_bia)
   ├── visitas_general.contract_id
   │       └── opex_costs_general.visit_id (= visitas_general.id)
   ├── alcances_general.contract_id  (también: alcances.codigo_interno_bia)
   ├── tareas_general.contract_id
   └── wms_general.contract_id  (también: wms.bia_code)
```

### 2.2 `prod-bia-bi` (database_id 21) — **fuente legada**

Es el origen del que se nutre `prod-bia-gold`. Las cards existentes (66727, 66793, 65209, 55705, 55707, 55773, 63163) corren contra este DB. **Recomendación:** las cards nuevas que se creen para el agente deben apuntar a `prod-bia-gold` (2344) para alinearnos al modelo curado y dejar de depender del schema `ops_bi` que será deprecado.

### 2.3 `electrician-scopes-prod` (database_id 1916)

Solo usada hoy por la card 55707. Ya está absorbida en `operations.alcances_general` vía dblink, así que no necesitamos llamarla directamente.

---

## 3. Cards requeridas por el plan vs. realidad

### 3.1 OPEX_OTS — granularidad OT, una fila por work order

**Lo que pide el plan:**
`ot_id, fecha_creacion, fecha_cierre, contratista_id, tipo_servicio, tipo_medida, ciudad, zona, OR, frontera_id, costo_total, estado, tiene_acta`

**Lo que hay hoy:**
- Card **66793** (`Costos asociados a opex`) tiene la mayoría de las columnas pero a granularidad **visita** (uuid `visit_id`, 26.139 filas), no work order. Para varias OTs hay múltiples visitas; para resumir a OT hay que agrupar por `titulo` (patrón `{tipo}_{codigo_bia}_{num}`).
- Card **63163** (`Opex Costs General`) tiene la data cruda con `wo_id` y status, pero sin contexto operativo (mercado, ciudad, OR).

**Gap:**
- No existe una card unificada al nivel OT.
- Falta columna explícita `tiene_acta` (derivable de `act_pdf_url IS NOT NULL` en visitas_general).
- Falta `zona` como dimensión separada de mercado (Costa/Centro/Interior); hoy `mercado` cubre ese rol parcialmente pero el plan habla de zonas más finas (referencia: documento `Resumen_proyecto_CAC_Sales.md` que define COSTA/CENTRO/Interior con reglas DANE).

**Propuesta:**
Crear card **`OPEX_OTS`** en colección 13993 OPEX-HDMG, sobre db 2344, con SQL del tipo:

```sql
WITH costos_por_visita AS (
  SELECT
    ocg.visit_id,
    SUM(ocg.service_cost + ocg.material_cost + ocg.transport_cost + ocg.other_cost) AS costo_total,
    MAX(ocg.contractor_id) AS contratista_id
  FROM operations.opex_costs_general ocg
  WHERE ocg.status = 'accepted'
  GROUP BY ocg.visit_id
),
ots AS (
  SELECT
    vg.title AS ot_id,
    MIN(vg.fecha_visita) AS fecha_creacion,
    MAX(CASE WHEN vg.electrician_status_id = 'CLOSURE_SUCCESSFUL'
             THEN vg.updated_at END) AS fecha_cierre,
    MAX(cv.contratista_id) AS contratista_id,
    MAX(vg.service_type_id) AS tipo_servicio,         -- VIPE/INST/ALRT/NORM/DESX
    MAX(hg.tipo_de_medida) AS tipo_medida,
    MAX(vg.city_name) AS ciudad,
    MAX(hg.departamento) AS departamento,
    -- zona derivada por reglas (COSTA/CENTRO/Interior) en CASE explícito
    MAX(vg.operador_de_red) AS operador_red,
    MAX(vg.internal_bia_code) AS frontera_id,
    SUM(cv.costo_total) AS costo_total,
    MAX(vg.electrician_status_id) AS estado,
    BOOL_OR(vg.act_pdf_url IS NOT NULL) AS tiene_acta
  FROM operations.visitas_general vg
  LEFT JOIN costos_por_visita cv ON cv.visit_id = vg.id
  LEFT JOIN operations.hubspot_general hg
    ON hg.codigo_interno_odoobia = vg.internal_bia_code
  GROUP BY vg.title
)
SELECT * FROM ots;
```

**Nota:** la lógica de `zona` (COSTA/CENTRO/Interior) debe replicar lo definido en `Resumen_proyecto_CAC_Sales.md §2`. Si `prod-bia-gold` no expone aún esa columna, codificarla en el CASE de la card.

### 3.2 OPEX_ITEMS_OT — composición ítem por ítem

**Lo que pide el plan:**
`ot_id, item_codigo, item_nombre, cantidad, valor_unitario, valor_total`

**Lo que hay hoy:**
- La columna `selected_tariff_items` (JSONB) en `operations.opex_costs_general` tiene la composición pero **no está explotada** en ninguna card.

**Gap:**
- Estructura completa del JSONB no está documentada en este repo. Antes de armar la card hay que abrir 2-3 registros y verificar qué keys trae (probable: `[{item_id, item_code, item_name, qty, unit_price, total}]` o similar).

**Propuesta:**
Crear card **`OPEX_ITEMS_OT`** en colección 13993, sobre db 2344, con SQL del tipo:

```sql
SELECT
  vg.title AS ot_id,
  ocg.visit_id,
  item->>'item_codigo' AS item_codigo,
  item->>'item_nombre' AS item_nombre,
  (item->>'cantidad')::numeric AS cantidad,
  (item->>'valor_unitario')::numeric AS valor_unitario,
  (item->>'valor_total')::numeric AS valor_total
FROM operations.opex_costs_general ocg
JOIN operations.visitas_general vg ON vg.id = ocg.visit_id
CROSS JOIN LATERAL jsonb_array_elements(ocg.selected_tariff_items) AS item
WHERE ocg.status = 'accepted'
  AND ocg.selected_tariff_items IS NOT NULL;
```

**Tarea previa:** ejecutar manualmente
`SELECT visit_id, selected_tariff_items FROM operations.opex_costs_general WHERE selected_tariff_items IS NOT NULL LIMIT 5;`
para confirmar nombres exactos de keys.

### 3.3 OPEX_TARIFARIO — catálogo histórico versionado

**Lo que pide el plan:**
`item_codigo, item_nombre, tarifa_unitaria, contratista_id, valid_from, valid_to`

**Lo que hay hoy:**
- **Nada en Metabase.** La búsqueda con term `tarifario` solo arroja una card de retención (id 9811, base de datos distinta, no aplica).
- El tarifario debería vivir en una tabla del DB origen `electrician-services-contractor` (cita la documentación de 63163: `service_tariff_id` apunta a una tabla de tarifas).

**Gap mayor:**
La tabla raw del tarifario no está expuesta en `prod-bia-gold`. Sin esto, no podemos:
- Validar si una OT cobró tarifas vigentes o caducas.
- Detectar cambios tarifarios y su impacto.
- Construir el modelo de "vecindarios por contratista" del plan (§5.2).

**Propuesta — paso 1 (operativo, esta semana):**
Solicitar al equipo de Data que cree vista curada `operations.tarifario_general` en `prod-bia-gold` con la tabla origen `electrician-services-contractor.service_tariffs` (o el nombre real que tenga). Estructura mínima:
- `item_codigo`, `item_nombre`, `unidad`
- `contratista_id`, `nombre_contratista`
- `tarifa_unitaria`
- `valid_from`, `valid_to` (NULL = vigente)

**Propuesta — paso 2 (alternativa si Data no responde a tiempo):**
Conectar el agente directo a `electrician-services-contractor` vía SQL en una card temporal de Metabase. No es la solución definitiva pero desbloquea WF-A.

### 3.4 OPEX_COSTO_SALES — costo proyectado por Sales

**Lo que pide el plan:**
`frontera_id, mes, costo_proyectado, tipo_servicio`

**Lo que hay hoy:**
- Card **65209** (`Ejercicio_validacion_backlog_v3`) trae `costo_opex_sales` y `payback_sales` — pero solo para las ~140 fronteras del backlog activo. Validado en query de prueba: la card retorna data fresca al 23 de abril.
- La fuente de ese campo es `sales_crm.fronteras.payback_sales` (mencionado en doc de 65209).

**Gap:**
- No hay card que exponga **toda la historia** de costos proyectados por Sales (no solo backlog activo). El plan necesita el universo completo para calcular delta histórico.

**Propuesta:**
Crear card **`OPEX_COSTO_SALES`** en colección 13993, sobre db 2344 (asumiendo que `sales_crm.fronteras` ya está replicada al gold; si no, mientras tanto sobre db 21):

```sql
SELECT
  f.codigo_bia AS frontera_id,
  f.fecha_proyeccion,
  EXTRACT(MONTH FROM f.fecha_proyeccion)::int AS mes,
  EXTRACT(YEAR FROM f.fecha_proyeccion)::int AS anio,
  f.costo_opex_sales AS costo_proyectado,
  f.payback_sales,
  f.tipo_de_medida AS tipo_servicio,
  f.kwh_mes
FROM sales_crm.fronteras f
WHERE f.costo_opex_sales IS NOT NULL;
```

**Nota:** validar con Sales que `costo_opex_sales` es un solo número o si tienen breakdown por tipo de servicio (visita previa / instalación / legalización separados).

---

## 4. Capacidades del rol no cubiertas por el plan

Tres responsabilidades del marco funcional (`analista_de_opex_bia_energy.md` §6) requieren fuentes que el plan §7 no menciona:

### 4.1 Recuperación de OPEX

**Qué pide el rol:**
> "Hacer seguimiento mensual del OPEX cobrado y recuperado"
> "Validar que se ejecuten los cobros que correspondan a clientes, OR u otros agentes"
> KPI: `Valor recuperado de OPEX por mes`, `% de recuperación de OPEX sobre el total cobrable`

**Estado:** la búsqueda en Metabase con términos `recuperacion`, `cobro`, `facturacion`, `dian`, `recaudo` no arroja cards en colecciones de OPS. La tabla `facturacion_dian` aparece mencionada en `metabase_cards_n8n_documentation.md §1.1` como uno de los schemas de db 21, pero no hay cards expuestas que la usen para recuperación.

**Acción siguiente:**
1. Revisar con Hernán (FOPS / Finanzas) qué tabla registra hoy los cobros a clientes y OR por OPEX recuperable. Posibilidades: `facturacion_dian.invoices`, `sales_crm.cobros_recuperables`, o tabla nueva en App OPS.
2. Si no existe tracking estructurado, **bloquear el KPI de recuperación hasta que exista** o construir un staging manual en Supabase que el FOPS Manager pueda actualizar.

### 4.2 Conciliación con contratistas

**Qué pide el rol:**
> "Conciliar económicamente con contratistas"
> "Preparar insumos para emisión de órdenes de compra"
> KPIs: `% de facturación conciliada sin reproceso`, `Tiempo de conciliación`

**Estado:** la conciliación se hace hoy en App OPS y no está expuesta en Metabase como tabla curada. La columna `act_pdf_url` en `opex_costs_general` da trazabilidad al acta pero no al estado de conciliación (aceptado/rechazado/pendiente por contratista).

**Acción siguiente:**
- Decisión arquitectónica: ¿el agente lee desde App OPS vía API, o se replica el estado de conciliación a Supabase?
- Recomendación: empezar **fuera del scope de las 3 semanas del plan**. Capturar este KPI en mes 2.

### 4.3 Forecast de OPEX

**Qué pide el rol:**
> "Construir y mantener forecast de OPEX para el backlog operativo"
> KPI: `Forecast vs gasto real`

**Estado:** no requiere card adicional. El backlog (65209) + un costo esperado por (zona × tipo de medida) extraído de `OPEX_OTS` históricas permite armar el forecast en el agente.

**Acción siguiente:** sin gap de datos. El forecast se construye en SQL/Supabase como vista derivada de `mv_opex_vecindarios` (Plan §5.2) cruzada con backlog.

---

## 5. Plan de trabajo recomendado para esta semana

Orden sugerido para no quedarnos esperando la creación de cards:

| Paso | Acción | Bloqueante | Responsable |
|---|---|---|---|
| 1 | Validar `selected_tariff_items` JSONB en `opex_costs_general` con 5 muestras | No | Hernán |
| 2 | Solicitar a Data la vista `operations.tarifario_general` en gold | Sí (para tarifario y vecindarios) | Hernán → Data |
| 3 | Crear cards `OPEX_OTS`, `OPEX_ITEMS_OT`, `OPEX_COSTO_SALES` en colección 13993 | Depende de paso 1 | Hernán |
| 4 | Confirmar con Finanzas la tabla de recuperación de OPEX | No bloquea WF-A | Hernán |
| 5 | Listar columnas adicionales si el equipo de Data va a montar `tarifario_general` | Depende de paso 2 | Hernán |
| 6 | Validar el SQL de las 3 cards con datos reales (≥100 filas cada una) | Sí (antes de WF-A) | Hernán |

Una vez los pasos 1-3 estén listos, podemos comenzar el DDL de Supabase (Plan §5) sin esperar a tarifario, porque las vistas `mv_opex_items_stats_*` (§5.2) pueden poblarse incrementalmente.

---

## 6. Fuentes de referencia

- `Solo para información/analista_de_opex_bia_energy.md` — Marco funcional del rol.
- `Solo para información/Resumen_proyecto_CAC_Sales.md` — Definición de zonas COSTA/CENTRO/Interior y reglas DANE.
- `Solo para información/metabase_cards_n8n_documentation.md` — Documentación detallada de las 7 cards existentes.
- `Plan_Ejecutivo_Agente_OPEX_BIA.md` — Plan de 3 semanas (§5 DDL Supabase, §7 cards requeridas, §11 WF-A).
- Card 65209 — Backlog v3 validado al 28 de abril de 2026 (141 filas, frescas).
- Database 2344 `prod-bia-gold` — Capa curada destino, schema `operations` con 7 tablas relevantes.
- Colección 13993 `OPEX-HDMG` — Donde van las cards nuevas del agente.
