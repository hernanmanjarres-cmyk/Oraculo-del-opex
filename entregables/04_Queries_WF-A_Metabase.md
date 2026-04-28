# Queries WF-A — Metabase → Supabase
**Fecha:** 28 de abril de 2026  
**Estado:** Todas validadas en Metabase ✅  
**Uso:** Pegar cada SQL en un nodo HTTP Request de n8n apuntando a la API de Metabase,  
o en un nodo Postgres apuntando directo a la base de datos correspondiente.

---

## Configuración en n8n

Para cada query via API Metabase:
```
POST https://bia.metabaseapp.com/api/dataset
Headers: x-api-key: {METABASE_API_KEY}
Body: { "database": <database_id>, "type": "native", "native": { "query": "<SQL>" } }
```

---

## TABLA 1 — `contractors`
**Fuente:** `prod-electrician-services-contractor` (DB: **2311**)  
**Frecuencia:** Semanal (cambia poco)  
**Filas:** 13

```sql
SELECT
    t.contractor_id::text   AS id,
    t.contractor_name       AS contractor_name,
    t.cost_type             AS cost_type,
    t.year                  AS tariff_year,
    t.name                  AS tariff_name,
    t.valid_from            AS valid_from,
    t.valid_to              AS valid_to,
    true                    AS is_active,
    t.id                    AS source_tariff_id,
    t.created_at            AS created_at,
    t.updated_at            AS updated_at
FROM tariff t
ORDER BY t.id
```

---

## TABLA 2 — `tariff_catalog`
**Fuente:** `prod-electrician-services-contractor` (DB: **2311**)  
**Frecuencia:** Semanal (cambia poco)  
**Filas:** 2.585

```sql
SELECT
    ti.id                               AS id,
    ti.tariff_id                        AS tariff_id,
    t.contractor_id::text               AS contractor_id,
    ti.item_number                      AS item_number,
    ti.activity_name                    AS activity_name,
    ti.network_operator_groups[1]       AS network_operator_group,
    ti.amount_cop                       AS base_rate_cop,
    ROUND(ti.amount_cop * 1.20)         AS night_rate_cop,
    ROUND(ti.amount_cop * 1.20)         AS sunday_rate_cop,
    ROUND(ti.amount_cop * 1.35)         AS night_sunday_rate_cop,
    0.20                                AS night_surcharge_pct,
    0.20                                AS sunday_surcharge_pct,
    0.35                                AS night_sunday_surcharge_pct,
    ti.created_at                       AS created_at,
    ti.updated_at                       AS updated_at
FROM tariff_item ti
JOIN tariff t ON t.id = ti.tariff_id
ORDER BY ti.tariff_id, ti.item_number
```

> **Nota n8n:** `network_operator_group` devuelve el primer elemento del array  
> (`ENEL_AIRE_EMCALI_AFINIA`, `CELSIA_VALLE_ELECTROHUILA_ESSA` o `OTROS_OR`).  
> Cada ítem tiene 3 filas (una por grupo de OR).

---

## TABLA 3 — `operation_types`
**Fuente:** `prod-electrician-services-contractor` (DB: **2311**)  
**Frecuencia:** Mensual  
**Filas:** 24

```sql
SELECT
    id                  AS id,
    operation_type      AS operation_type,
    service_type_id     AS service_type_id,
    direct_hours        AS direct_hours,
    semidirect_hours    AS semidirect_hours,
    indirect_hours      AS indirect_hours,
    created_at          AS created_at,
    updated_at          AS updated_at
FROM operation_hours
ORDER BY id
```

---

## TABLA 4 — `fronteras`
**Fuente:** `prod-bia-gold` → `operations.hubspot_general` (DB: **2344**)  
**Frecuencia:** Cada hora  
**Filas:** ~5.647

```sql
SELECT
    codigo_bia                              AS bia_code,
    contract_id                             AS contract_id,
    titulo                                  AS frontier_title,
    fase_actual                             AS current_phase,
    sic                                     AS sic_code,
    niu                                     AS niu,
    nic                                     AS nic,
    operador_de_red                         AS grid_operator,
    tipo_de_mercado                         AS market_type,
    tipo_de_medida                          AS measurement_type,
    nivel_de_tension                        AS voltage_level,
    factor_de_medida                        AS measurement_factor,
    energia                                 AS energy_kwh_month,
    ciudad                                  AS city,
    departamento                            AS department,
    direccion_de_la_frontera                AS address,
    kam_asignado                            AS kam_assigned,
    operation_account_executive             AS operation_account_executive,
    numero_de_documento_de_la_empresa       AS company_nit,
    razon_social_de_la_empresa              AS company_name,
    codigo_ciiu                             AS company_ciiu,
    propiedad_de_equipos_en_zona            AS equipment_ownership,
    fecha_firma_del_contrato                AS contract_sign_date,
    fecha_real_de_registro                  AS installation_date,
    fecha_real_de_activacion                AS activation_date,
    es_frontera_comercial                   AS is_commercial_border,
    recibio_paz_y_salvo                     AS received_paz_y_salvo,
    fecha_de_vencimiento_de_paz_y_salvo     AS paz_y_salvo_expiry_date,
    numero_de_requerimiento_xm              AS xm_requirement_number,
    razon_on_hold_y_desistimiento           AS on_hold_reason,
    detalle_de_on_hold_y_desistimiento      AS on_hold_detail,
    serial_medidor_registrado               AS meter_serial_registered,
    tiempo_total_gestion_paz_y_salvo_dias   AS days_in_paz_y_salvo,
    tiempo_total_visita_previa_dias         AS days_in_visita_previa,
    tiempo_total_asignacion_equipos_dias    AS days_in_asignacion_equipos,
    tiempo_total_activar_instalar_dias      AS days_in_activar_instalar,
    tiempo_total_completado_dias            AS days_in_completado,
    tiempo_total_on_hold_dias               AS days_in_on_hold,
    tiempo_total_desistidos_dias            AS days_in_desistidos,
    creado_el                               AS source_created_at
FROM operations.hubspot_general
```

---

## TABLA 5 — `visits`
**Fuente:** `prod-bia-gold` → `operations.visitas_general` (DB: **2344**)  
**Frecuencia:** Cada hora  
**Filas:** ~26.139

```sql
SELECT
    id                      AS id,
    internal_bia_code       AS bia_code,
    contract_id             AS contract_id,
    title                   AS work_order_title,
    service_type_id         AS service_type_id,
    service_name            AS service_name,
    visit_type_id           AS visit_type_id,
    electrician_status_id   AS electrician_status_id,
    estado                  AS status_label,
    status_app              AS status_app,
    contratista             AS contractor_name,
    electrician_id          AS electrician_id,
    electricistas           AS electricians,
    operador_de_red         AS grid_operator,
    city_name               AS city,
    department              AS department,
    address                 AS address,
    company_id              AS company_id,
    company_name            AS company_name,
    measurement_type_id     AS measurement_type_id,
    act_pdf_url             AS act_pdf_url,
    fecha_visita            AS visit_date,
    observation             AS observation,
    reason                  AS reason,
    created_at              AS created_at,
    updated_at              AS updated_at,
    deleted_at              AS deleted_at
FROM operations.visitas_general
```

> **Nota n8n:** `contract_id` llega como **string** aquí (a diferencia de `fronteras`  
> donde es numeric). Castear con `contract_id::integer` si necesitas hacer join.

---

## TABLA 6 — `opex_costs`
**Fuente:** `prod-bia-gold` → `operations.opex_costs_general` (DB: **2344**)  
**Frecuencia:** Cada hora  
**Filas:** ~23.349

```sql
SELECT
    id                      AS id,
    visit_id                AS visit_id,
    wo_id                   AS wo_id,
    visit_title             AS visit_title,
    service_cost            AS service_cost,
    material_cost           AS material_cost,
    transport_cost          AS transport_cost,
    other_cost              AS other_cost,
    COALESCE(service_cost,0)
    + COALESCE(material_cost,0)
    + COALESCE(transport_cost,0)
    + COALESCE(other_cost,0)    AS total_cost,
    status                  AS status,
    enabled                 AS enabled,
    contractor_id           AS contractor_id,
    service_tariff_id       AS service_tariff_id,
    electrician_status_id   AS electrician_status_id,
    act_pdf_url             AS act_pdf_url,
    is_bia                  AS is_bia,
    comments                AS comments,
    details                 AS details,
    user_id                 AS user_id,
    visit_start             AS visit_start,
    created_at              AS created_at,
    updated_at              AS updated_at
FROM operations.opex_costs_general
WHERE enabled = true
```

> **Nota n8n:** Filtrar `status = 'accepted'` si solo quieres costos validados.  
> `total_cost` se calcula aquí porque en Supabase es columna generada.

---

## TABLA 7 — `opex_cost_items`
**Fuente:** `prod-bia-gold` → `operations.opex_costs_general` JSONB (DB: **2344**)  
**Frecuencia:** Cada hora  
**Estructura JSONB validada:** `[{"amount":"285000","quantity":"1","item_number":"46","activity_name":"..."}]`

```sql
SELECT
    oc.id                                           AS opex_cost_id,
    oc.visit_id                                     AS visit_id,
    (item->>'item_number')::integer                 AS item_number,
    item->>'activity_name'                          AS activity_name,
    (item->>'quantity')::numeric                    AS quantity,
    (item->>'amount')::numeric                      AS amount_cop,
    (item->>'quantity')::numeric
        * (item->>'amount')::numeric                AS total_cop
FROM operations.opex_costs_general oc,
     jsonb_array_elements(oc.selected_tariff_items::jsonb) AS item
WHERE oc.selected_tariff_items IS NOT NULL
  AND oc.selected_tariff_items != 'null'
  AND oc.selected_tariff_items != '[]'
  AND oc.enabled = true
```

> **Nota n8n:** Esta query explota el JSONB automáticamente — una fila por ítem.  
> Si una visita tiene 3 ítems, genera 3 filas con el mismo `opex_cost_id`.

---

## TABLA 8 — `scopes`
**Fuente:** `prod-bia-gold` → `operations.alcances_general` (DB: **2344**)  
**Frecuencia:** Cada hora  
**Filas:** ~5.743

```sql
SELECT
    id                                          AS id,
    codigo_interno_bia                          AS bia_code,
    contract_id                                 AS contract_id,
    tipo_de_alcance                             AS scope_type,
    fase_actual                                 AS current_phase,
    tipo_de_medida_encontrado                   AS measurement_type_found,
    tipo_de_medida_a_instalar                   AS measurement_type_to_install,
    nivel_de_tension                            AS voltage_level,
    factor_de_medida_encontrado                 AS measurement_factor_found,
    viable_para_instalar                        AS viable_to_install,
    calculo_de_pb                               AS payback_calculation,
    valor_de_pb_calculado                       AS payback_value,
    enlace_memoria_de_calculo                   AS payback_calc_link,
    serie_del_medidor                           AS meter_serial,
    requiere_descargos_del_or                   AS requires_or_disconnection,
    el_descargo_afecta_a_otros_usuarios         AS disconnection_affects_users,
    es_frontera_comercial                       AS is_commercial_border,
    ubicacion_de_la_antena                      AS antenna_location,
    requiere_antena_de_alta_ganancia            AS requires_high_gain_antenna,
    nombre                                      AS contact_name,
    telefono                                    AS contact_phone,
    correo                                      AS contact_email,
    creado_el                                   AS created_at
FROM operations.alcances_general
```

---

## TABLA 9 — `backlog_scoring`
**Fuente:** Card **65209** — Backlog v3 (DB: **21**)  
**Frecuencia:** Cada hora  
**Filas:** ~147 (backlog activo)  
**Método:** Ejecutar via API con `card_id=65209` (no SQL directo)

```
POST https://bia.metabaseapp.com/api/card/65209/query/json
Headers: x-api-key: {METABASE_API_KEY}
Body: {}
```

**Mapeo de campos (card → Supabase):**

| Campo card | Campo Supabase |
|---|---|
| `codigo_bia` | `bia_code` |
| `contract_id` | `contract_id` |
| `nombre_frontera` | `frontier_name` |
| `operador_de_red` | `grid_operator` |
| `tipo_de_medida` | `measurement_type` |
| `tipo_de_mercado` | `market_type` |
| `fase_actual` | `current_phase` |
| `ciudad` | `city` |
| `departamento` | `department` |
| `kwh_mes` | `kwh_per_month` |
| `fecha_programada` | `scheduled_date` |
| `fecha_inst_exitosa` | `successful_install_date` |
| `fecha_firma_del_contrato` | `contract_sign_date` |
| `costo_est_visita_previa` | `estimated_vipe_cost` |
| `costo_est_instalacion_ajustado` | `estimated_install_cost_adj` |
| `costo_est_legalizacion` | `estimated_legalization_cost` |
| `costo_total_estimado_visitas` | `total_estimated_visit_cost` |
| `costo_opex_estimado` | `estimated_opex_cost` |
| `costo_opex_sales` | `sales_opex_cost` |
| `payback_sales` | `sales_payback_months` |
| `delta_opex` | `opex_delta` |
| `semaforo_delta` | `delta_traffic_light` |
| `banda` | `recommendation_band` |
| `cac_kwh` | `cac_per_kwh` |
| `aging_neto_dias` | `net_aging_days` |

> **Nota n8n:** `semaforo_delta` y `banda` traen emojis en el string  
> (ej: `"🟢 INSTALAR"`). Usar `.includes('INSTALAR')` para comparar, no igualdad exacta.

---

## Resumen de bases de datos y frecuencias

| Tabla Supabase | DB Metabase | ID | Frecuencia |
|---|---|---|---|
| `contractors` | prod-electrician-services-contractor | 2311 | Semanal |
| `tariff_catalog` | prod-electrician-services-contractor | 2311 | Semanal |
| `operation_types` | prod-electrician-services-contractor | 2311 | Mensual |
| `fronteras` | prod-bia-gold | 2344 | Cada hora |
| `visits` | prod-bia-gold | 2344 | Cada hora |
| `opex_costs` | prod-bia-gold | 2344 | Cada hora |
| `opex_cost_items` | prod-bia-gold | 2344 | Cada hora |
| `scopes` | prod-bia-gold | 2344 | Cada hora |
| `backlog_scoring` | prod-bia-bi (card 65209) | 21 | Cada hora |
