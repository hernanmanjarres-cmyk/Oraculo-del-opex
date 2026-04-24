# Documentación Metabase para Proyecto n8n — BIA Energy

Documentación consolidada de 7 cards de Metabase usadas como fuentes de datos para pipelines de n8n.

> **Fecha de captura:** 2026-04-24
> **Instancia Metabase:** `https://bia.metabaseapp.com`
> **Capturado por:** Daniel Moreno (OPS / CGM) con asistencia Claude

---

## 1. Contexto general

### 1.1. Bases de datos involucradas

| database_id | Nombre interno | Engine | Uso |
|---|---|---|---|
| `21` | `prod-bia-bi` | PostgreSQL | Data warehouse principal. Contiene `hubspot`, `ops`, `ops_bi`, `cgm`, `facturacion_dian`, `sales_crm`, etc. **Usado por 6 de 7 cards.** |
| `1916` | `electrician-scopes-prod` | PostgreSQL | BD operativa de alcances técnicos (visitas previas, informes de electricistas). Schema único `public`. **Solo usada por card 55707.** |

### 1.2. Colecciones de Metabase

| collection_id | Nombre | Cards que contiene |
|---|---|---|
| `13531` | Vistas BI de Operaciones | 55707, 55705, 63163, 55773 |
| `968`   | OPS SJJ                  | 65209 |
| `13993` | OPEX-HDMG                | 66727, 66793 |

### 1.3. Cómo ejecutar cards desde n8n

La API pública de Metabase permite ejecutar cards guardadas y recibir resultados en JSON/CSV/XLSX. Endpoints relevantes (autenticación vía `X-Metabase-Session` o API Key en header `x-api-key`):

```
POST https://bia.metabaseapp.com/api/card/{card_id}/query/json
POST https://bia.metabaseapp.com/api/card/{card_id}/query/csv
POST https://bia.metabaseapp.com/api/card/{card_id}/query/xlsx
```

Para cards con parámetros (66727 y 66793), el body JSON debe incluir:

```json
{
  "parameters": [
    {
      "id": "<parameter_id_uuid>",
      "type": "string/=",
      "value": "<valor>",
      "target": ["variable", ["template-tag", "<slug>"]]
    }
  ]
}
```

Para cards sin parámetros, body `{}` o sin body funciona.

> **Tip para n8n:** usa un nodo **HTTP Request** con método `POST`, autenticación por credencial HTTP Header genérica con el token Metabase. Los campos `id`, `slug` y `target` de parámetros los tienes listados en cada card más abajo.

### 1.4. Nota sobre el SQL nativo

Las 7 cards son de tipo `native` (SQL puro, no query builder). El SQL completo **no es retornado por la API de Metabase** para cards guardadas; si necesitas replicar lógica en dbt o pegar el SQL en un nodo PostgreSQL de n8n, debes **abrir la card en la UI y copiar el SQL** manualmente. Esta documentación cubre esquema de salida y parámetros — que es lo que n8n consume directamente vía la API `POST /query/json`.

---

## 2. Card 55707 — `Alcances General`

- **URL:** https://bia.metabaseapp.com/question/55707-alcances-general
- **Database:** `1916` (`electrician-scopes-prod`, schema `public`)
- **Colección:** `13531` Vistas BI de Operaciones
- **Creador:** juan.salazar@bia.app
- **Creada:** 2026-03-24 · **Actualizada:** 2026-04-14
- **Parámetros:** ninguno
- **Volumen actual:** ~5.703 filas

### Propósito
Consolida los **alcances técnicos** (visitas previas e instalaciones) con todos los campos que diligencia el electricista: equipos encontrados, equipos a instalar, certificados de CTs/PTs, memoria de cálculo, info de transformador, maniobras, descargos, requerimientos de materiales, viabilidad. Es la vista maestra de la gestión técnica pre-instalación.

### Esquema de salida (columnas clave)

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | ID del alcance |
| `contract_id` | integer | FK al contrato |
| `codigo_interno_bia` | text | Código BIA (p.ej. `CO0700006491`) |
| `fase_actual` | text | `COMPLETED`, `IN_PROGRESS`, etc. |
| `creado_el` | date/timestamp | Fecha de creación |
| `tipo_de_alcance` | text | `INST` (instalación), `VIPE` (visita previa), `NORM` (normalización), `ALRT` (emergencia), `DESX` (desconexión) |
| `tipo_de_medida_encontrado` / `tipo_de_medida_a_instalar` | text | `Directa`, `Semidirecta`, `Indirecta` |
| `ubicacion_de_la_medida` | text | Texto libre |
| `factor_de_medida_encontrado` / `factor_de_medida_a_instalar` | text | Factor de medida |
| `nivel_de_tension` / `nivel_de_tension_a_instalar` | text | `1`, `2`, `3`, `4` |
| `red_de_media_tension_v` | text | Tensión MT (V) |
| `serie_del_medidor` | text | Serial |
| `numero_de_elementos`, `marca_del_medidor`, `clase_energia_activa`, `clase_energia_reactiva`, `corriente_maxima_a`, `tension_maxima_v`, `constante` | text | Specs medidor |
| `tipo_de_celda_del_medidor`, `estado_de_celda_del_medidor`, `tipo_de_proteccion` | text | Infraestructura |
| `capacidad_del_totalizador_a`, `fases_del_totalizador`, `marca_del_totalizador` | text | Totalizador |
| `calibre_cable_acometida`, `numero_de_cables_por_fase_acometida`, `calibre_cable_parcial`, `numero_de_cables_por_fase_parcial` | text | Cableado |
| `voltage_fase_r_v`, `voltage_fase_s_v`, `voltage_fase_t_v`, `corriente_fase_r_a`, `corriente_fase_s_a`, `corriente_fase_t_a` | text | Mediciones in-situ |
| `tipo_de_bloque_de_pruebas`, `marca_bloque_de_pruebas`, `condicion_bloque_de_pruebas`, `requiere_cambio_bloque`, `tipo_de_bloque_de_pruebas_a_instalar` | text | Bloque de pruebas |
| `se_encontro_planta_de_respaldo`, `capacidad_kva_hp` | text | Planta respaldo |
| `requiere_descargos_del_or`, `el_descargo_afecta_a_otros_usuarios`, `a_cuantos_usuarios_afecta`, `nombre_y_descripcion_de_usuarios_que_afecta` | text | Gestión descargos OR |
| `equipos_necesarios`, `tiempo_de_corte_h`, `maniobra`, `observaciones`, `requerimientos`, `requerimientos_adicionales_viabilidad` | text largo | Narrativa técnica |
| `viable_para_instalar` | text | `Sí`/`No` |
| `tipo_de_punto_de_medicion`, `se_require_cambio_de_equipos` | text | — |
| `relacion_de_transformacion_del_tc_a_instalar`, `burden_del_tc_a_instalar`, `clase_del_tc_a_instalar`, `tipo_de_tc_a_instalar` | text | CTs a instalar |
| `relacion_de_transformacion_del_tp_a_instalar`, `burden_del_tp_a_instalar`, `clase_del_tp_a_instalar`, `tipo_de_tp_a_instalar` | text | PTs a instalar |
| `ubicacion_de_la_antena`, `requiere_antena_de_alta_ganancia`, `operador_de_red_celular` | text | Telecom |
| `nombre`, `telefono`, `correo` | text | Contacto en sitio |
| `calculo_de_pb`, `valor_de_pb_calculado`, `enlace_memoria_de_calculo` | text/url | Cálculo de payback |
| `existen_seccionamientos_externos`, `reubicacion_equipos_de_medida` | text | — |
| `certificado_celda` | url | PDF celda |
| `certificado_compliance_cts`, `certificado_calibrate_cts_one/two/three`, `serial_cts_one/two/three` | url/text | Certificados CTs |
| `certificado_compliance_pts`, `certificado_calibrate_pts_one/two/three`, `serial_pts_one/two/three` | url/text | Certificados PTs |
| `certificado_test_block` | url | Certificado bloque pruebas |
| `es_frontera_comercial_` | text | `Si`/`No` |
| `info_trafo` | jsonb (string) | Array JSON con info de transformadores: `{groupId, transformerUsage, transformerNumber, transformerLocation, installedCapacityKva, transformerCapacityKva}` |
| `installed_capacity_kva` | text/null | Capacidad instalada (kVA) |

### Notas para n8n
- `info_trafo` llega como **string JSON** — parsear con nodo `Code` o Function antes de mapear.
- Muchas columnas son texto libre y pueden venir `""` (string vacío) o `null`. Normalizar en n8n.
- `creado_el` llega a veces como `YYYY-MM-DD` y a veces como timestamp ISO con microsegundos — parsear flexible.
- Es la única card que apunta a `database_id=1916`; el resto van a `21`.

---

## 3. Card 55705 — `Hubspot General`

- **URL:** https://bia.metabaseapp.com/question/55705-hubspot-general
- **Database:** `21` (`prod-bia-bi`)
- **Colección:** `13531` Vistas BI de Operaciones
- **Creador:** juan.salazar@bia.app
- **Creada:** 2026-03-24 · **Actualizada:** 2026-04-20
- **Parámetros:** ninguno
- **Volumen actual:** ~5.670 filas

### Propósito
Vista maestra de **fronteras/contratos** con su ciclo de vida comercial: datos del cliente (NIT, razón social, CIIU), ubicación, OR, mercado, tipo de medida, fechas de firma/registro/activación, paz y salvo, y los **timestamps de cada fase del pipeline de activación** (gestión paz y salvo → visita previa → asignación equipos → activar/instalar → completado / on hold / desistidos).

Es la fuente canónica para KPIs de conversion funnel, time-to-activation, y estado vigente de cartera.

### Esquema de salida

| Columna | Tipo | Descripción |
|---|---|---|
| `titulo` | text | Nombre descriptivo de la frontera |
| `fase_actual` | text | `Completado`, `Desistidos`, `On Hold`, `Visita previa`, etc. |
| `codigo_bia` | text | Código BIA |
| `contract_id` | integer | FK contrato |
| `kam_asignado` | text (email) | KAM comercial |
| `direccion_de_la_frontera` | text | — |
| `departamento`, `ciudad` | text | — |
| `operador_de_red` | text | p.ej. `ENEL CUNDINAMARCA`, `AIRE CARIBE_SOL` |
| `tipo_de_mercado` | text | `regulated` / `non-regulated` |
| `antiguo_comercializador` | text | — |
| `direccion_para_registro` | text/null | — |
| `url_paz_y_salvo` | url/null | Enlace al documento |
| `energia` | integer | kWh/mes estimado |
| `sic` | text/null | Código SIC (p.ej. `frt85123`) |
| `tipo_de_medida` | text | `Directa`/`Semidirecta`/`Indirecta` |
| `identificador_bia_de_la_empresa` | integer | ID interno empresa |
| `propiedad_de_equipos_en_zona` | text | `or`/`user` |
| `tipo_de_documento_de_la_empresa` | text | `NIT` |
| `numero_de_documento_de_la_empresa` | text | — |
| `razon_social_de_la_empresa` | text | — |
| `codigo_ciiu` | integer | — |
| `fecha_firma_del_contrato` | timestamp | — |
| `nivel_de_tension` | text | `level_1`/`level_2`/`level_3`/`level_4` |
| `factor_de_medida` | integer | — |
| `niu`, `nic` | text/null | Identificadores OR |
| `primera_vez_entro_gestion_paz_y_salvo` / `_salio_` / `tiempo_total_*_dias` | timestamp / integer | Fases de gestión paz y salvo |
| `primera_vez_entro_visita_previa` / `_salio_` / `tiempo_total_*` | timestamp / integer | Fase visita previa |
| `primera_vez_entro_asignacion_equipos` / `_salio_` / `tiempo_total_*` | timestamp / integer | Fase asignación equipos |
| `primera_vez_entro_activar_instalar` / `_salio_` / `tiempo_total_*` | timestamp / integer | Fase instalación |
| `primera_vez_entro_completado` / `_salio_` / `tiempo_total_*` | timestamp / integer | Completado |
| `primera_vez_entro_on_hold` / `_salio_` / `tiempo_total_*` | timestamp / integer | On hold |
| `primera_vez_entro_desistidos` / `_salio_` / `tiempo_total_*` | timestamp / integer | Desistidos |
| `operation_account_executive` | text (email) | Ejecutivo de operaciones |
| `fecha_de_solicitud_de_paz_y_salvo` | timestamp | — |
| `serial_medidor_registrado` | text | Serial(es) separados por `/` si son múltiples |
| `fecha_real_de_registro` | timestamp | Fecha de registro ante XM |
| `fecha_real_de_activacion` | timestamp | Fecha de activación frontera |
| `razon_on_hold_y_desistimiento`, `detalle_de_on_hold_y_desistimiento` | text/null | — |
| `es_frontera_comercial` | text | `Si`/`No` |
| `recibio_paz_y_salvo` | text | `Si`/`No` |
| `fecha_de_vencimiento_de_paz_y_salvo` | timestamp | — |
| `numero_de_requerimiento_xm` | text | Número requerimiento ante XM/ASIC |
| `creado_el` | timestamp | — |

### Notas para n8n
- Es la card más rica en datos comerciales — suele ser el **join master** contra las demás.
- Las columnas `primera_vez_entro_*` / `primera_vez_salio_*` permiten calcular SLAs por fase en n8n.
- `serial_medidor_registrado` puede ser múltiple separado por `/` (medida indirecta con varios medidores); split antes de joinear con otras fuentes.
- `tipo_de_mercado` en esta vista viene en inglés (`regulated`/`non-regulated`), a diferencia de 66727 y 66793 que lo traducen a `Costa`/`Interior`/`Centro` o `Regulada`/`No Regulada`. Normalizar antes de cruces.

---

## 4. Card 63163 — `Opex Costs General`

- **URL:** https://bia.metabaseapp.com/question/63163-opex-costs-general
- **Database:** `21` (`prod-bia-bi`)
- **Colección:** `13531` Vistas BI de Operaciones
- **Creador:** juan.salazar@bia.app
- **Creada:** 2026-04-14
- **Parámetros:** ninguno
- **Volumen actual:** ~23.295 filas

### Propósito
Registro de **costos OPEX por visita** (work order / visit). Une cada visita de electricista con el desglose económico: servicio, materiales, transporte, otros. Es la base de costos para CAC, payback y márgenes operativos.

### Esquema de salida

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | integer | PK interna del registro de costo |
| `wo_id` | text | Work order ID (patrón `{tipo}_{codigo_bia}_{number}`, p.ej. `NOTE_CO0800000810_1163086553`) |
| `visit_id` | uuid | FK a la visita |
| `service_cost` | integer | COP — costo servicio |
| `material_cost` | integer | COP — costo materiales |
| `transport_cost` | integer | COP — costo transporte |
| `other_cost` | integer | COP — otros |
| `comments`, `details` | text | Notas |
| `user_id` | text | Usuario que registró |
| `created_at` | timestamp | — |
| `updated_at` | timestamp | — |
| `enabled` | boolean | Vigente |
| `status` | text | `accepted`, `pending`, `rejected`, etc. |
| `service_tariff_id` | integer | FK a tarifa del contratista |
| `selected_tariff_items` | jsonb/null | Items específicos de la tarifa |
| `contractor_id` | uuid | FK contratista |
| `visit_start` | timestamp | — |
| `visit_title` | text | Mismo patrón que `wo_id` |
| `electrician_status_id` | text | `CLOSURE_SUCCESSFUL`, `CLOSURE_FAILED`, `CLOSURE_CANCELLED`, etc. |
| `act_pdf_url` | url | PDF del acta de visita |
| `is_bia` | boolean | `true` si la visita la hizo BIA directamente, `false` si contratista externo |

### Notas para n8n
- El total OPEX por visita = `service_cost + material_cost + transport_cost + other_cost`. En n8n usar un nodo `Set` para calcular `total_cost` si la card no lo trae.
- `status='accepted'` filtra registros válidos (no rechazados).
- Para costear una frontera completa hay que **agregar por `codigo_bia`** extraído de `wo_id` o cruzando por `visit_id` contra otras fuentes.
- `is_bia=false` indica costo pagado a contratista externo (GMAS, C3 BOGOTA, etc.); `is_bia=true` es costo interno.

---

## 5. Card 55773 — `Visitas General`

- **URL:** https://bia.metabaseapp.com/question/55773-visitas-general
- **Database:** `21` (`prod-bia-bi`)
- **Colección:** `13531` Vistas BI de Operaciones
- **Creador:** juan.salazar@bia.app
- **Creada:** 2026-03-24 · **Actualizada:** 2026-04-21
- **Parámetros:** ninguno
- **Volumen actual:** ~26.139 filas

### Propósito
Registro maestro de **visitas de electricista** (pre-visita, instalación, emergencia, desconexión, normalización). Contiene la información operativa de cada visita: agenda, ejecutante, ubicación, estado de cierre. Se cruza 1:1 (o 1:N) con `Opex Costs General` vía `visit_id`.

### Esquema de salida

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | PK visita (= `visit_id` en otras cards) |
| `pipe_id` | text/null | Legacy Pipefy ID |
| `contract_name` | text | Nombre descriptivo del contrato |
| `contratista` | text | `BIA`, `GMAS`, `C3 BOGOTA`, `Dinovi`, etc. (puede ser `""`) |
| `operador_de_red` | text | — |
| `updated_by` | text | Usuario/servicio que actualizó |
| `electrician_status_id` | text | `CLOSURE_SUCCESSFUL`, `CLOSURE_FAILED`, etc. |
| `act_pdf_url` | url | Acta |
| `measurement_type_id` | text/null | — |
| `visit_type_id` | text | `PRE_VISIT`, `GENERIC_VISIT`, etc. |
| `internal_bia_code` | text | Código BIA |
| `service_type_id` | text | `VIPE`, `INST`, `ALRT`, `NORM`, `DESX` |
| `service_name` | text | `Visita previa`, `Instalación`, `Emergencia`, `Normalización`, `Desconexión` |
| `status_app` | text | `COMPLETED`, `CANCELLED`, etc. |
| `pipe_name` | text/null | — |
| `wo_generate_by` | text/null | — |
| `title` | text | Mismo patrón `{tipo}_{codigo}_{num}` |
| `status` | text | `CLOSED`, `OPEN` |
| `department`, `city_name`, `address` | text | Ubicación |
| `company_id`, `company_name` | text | Empresa |
| `contract_id` | text | FK contrato (ojo: **string** aquí, no integer) |
| `card_id` | integer | Card ID (legacy) |
| `emails` | text | Correos de notificación |
| `observation` | text | — |
| `fecha_visita` | timestamp | Agendada |
| `created_at`, `updated_at`, `deleted_at` | timestamp | — |
| `reason` | text/null | Razón de cancelación |
| `electrician_id` | text/null | FK electricista |
| `estado` | text | Traducción ES de `electrician_status_id`: `Cierre Exitoso`, `Cierre Fallido`, `Cierre Cancelado` |
| `electricistas` | text/null | Nombres de electricistas separados por coma |

### Notas para n8n
- **`contract_id` aquí es string**, en 55705 es integer — castear antes de joinear.
- `service_type_id` controla el tipo de visita; úsalo para filtrar pipelines específicos (solo instalaciones, solo emergencias, etc.).
- `electrician_status_id` = `CLOSURE_SUCCESSFUL` es la señal de éxito operativo; los otros estados requieren reintento o escalamiento.
- Se puede joinear con `Opex Costs General` (card 63163) por `id` ↔ `visit_id`.

---

## 6. Card 65209 — `Ejercicio_validacion_backlog_v3`

- **URL:** https://bia.metabaseapp.com/question/65209-ejercicio-validacion-backlog-v3
- **Database:** `21` (`prod-bia-bi`)
- **Colección:** `968` OPS SJJ
- **Creador:** hernan.manjarres@bia.app
- **Creada:** 2026-04-17 · **Actualizada:** 2026-04-20
- **Parámetros:** ninguno
- **Volumen actual:** ~140 filas

### Propósito
**Priorización del backlog de instalaciones pendientes.** Para cada frontera en estado pre-instalación: calcula el **CAC por kWh**, compara el **OPEX estimado** (visita previa + instalación + legalización) contra el **costo OPEX de ventas (sales)** vía `payback_sales`, y clasifica cada frontera en una **banda de recomendación**: `🟢 INSTALAR` / `🟡 INSTALAR - MENOS PRIORITARIO` / `🔴 DESESTIMAR`, con un semáforo adicional sobre el delta OPEX.

Es la evolución de la card 60226 y 62611 (Backlog v2), ahora parametrizada con costos ajustados por región.

### Esquema de salida

| Columna | Tipo | Descripción |
|---|---|---|
| `codigo_bia` | text | — |
| `contract_id` | integer | — |
| `nombre_frontera` | text | Título descriptivo |
| `operador_de_red` | text | — |
| `tipo_de_medida` | text | `Directa`/`Semidirecta`/`Indirecta` |
| `tipo_de_mercado` | text | `regulated`/`non-regulated` |
| `kwh_mes` | numeric | Consumo mensual estimado |
| `fase_actual` | text | Fase en el pipeline (ej. `Visita previa`) |
| `ciudad`, `departamento` | text | — |
| `fecha_inst_exitosa` | timestamp/null | Si ya está instalada |
| `fecha_programada` | timestamp/null | Próxima visita agendada |
| `costo_opex_estimado` | numeric (COP) | OPEX proyectado por operaciones |
| `cac_kwh` | numeric | CAC / kWh mensual — métrica de rentabilidad |
| `costo_opex_sales` | numeric (COP) | OPEX que asume Sales (de tabla `sales_crm.fronteras`) |
| `payback_sales` | numeric (meses) | Payback según Sales |
| `delta_opex` | numeric (COP) | `costo_opex_sales - costo_opex_estimado` (negativo = Sales subestimó) |
| `semaforo_delta` | text | `🟢 HOLGURA`, `🟡 AJUSTADO`, `🟠 DÉFICIT MODERADO`, `🔴 DÉFICIT ALTO` |
| `banda` | text | Recomendación final: `🟢 INSTALAR`, `🟡 INSTALAR - MENOS PRIORITARIO`, `🔴 DESESTIMAR` |
| `fecha_firma_del_contrato` | timestamp | — |
| `aging_neto_dias` | integer | Días desde firma descontando on-hold |
| `costo_est_visita_previa` | numeric | — |
| `costo_est_instalacion_ajustado` | numeric | Instalación con ajuste OPEX por región |
| `costo_est_legalizacion` | numeric | — |
| `costo_total_estimado_visitas` | numeric | Suma de los tres anteriores |

### Notas para n8n
- Es una card **de decisión** — útil como trigger: "si `banda = 🔴 DESESTIMAR`, notificar KAM por Slack y pausar en Odoo".
- `cac_kwh` < 30 suele ser buen indicador (verificar con el equipo de SJJ).
- Los emojis en `semaforo_delta` y `banda` vienen literales en el string; si n8n hace matching por texto, comparar `banda.includes('INSTALAR')` en lugar de igualdad exacta para evitar problemas de encoding.
- Este backlog es **chico (~140 filas)** — se puede traer completo en cada ejecución sin paginación.

---

## 7. Card 66727 — `CAC_BIA`

- **URL:** https://bia.metabaseapp.com/question/66727-cac-bia
- **Database:** `21` (`prod-bia-bi`)
- **Colección:** `13993` OPEX-HDMG
- **Creador:** hernan.manjarres@bia.app
- **Creada:** 2026-04-21
- **Volumen actual:** ~5.557 filas

### Propósito (de la propia descripción de la card)
> Vista de activación por código BIA — consolida información de Hubspot, Visitas y Costos OPEX para mostrar, por cada cliente, su mercado (Centro/Costa/Interior), tipo de medida, tipo de energía, fecha y mes de la primera instalación exitosa, y el desglose de costos asociados (OPEX total, contratista, servicio, materiales, transporte, adicionales y BIA).

Es la vista **agregada a nivel de código BIA** de los costos reales de adquisición. Equivale al "row por cliente" después de consolidar todas sus visitas.

### Parámetros

| Nombre | Slug | Parameter ID | Tipo | Template tag |
|---|---|---|---|---|
| Tipo De Mercado | `tipo_de_mercado` | `fc0f2b30-20b6-4ab4-80c3-5f567a0d42ef` | `string/=` | `tipo_de_mercado` |
| Codigo Bia | `codigo_bia` | `e8cf66e8-028b-45ae-91e5-f2e52107266a` | `string/=` | `codigo_bia` |
| Tipo De Medida | `tipo_de_medida` | `d1e69e96-72da-42d7-b296-8e110aedb448` | `string/=` | `tipo_de_medida` |
| Tipo De Energia | `tipo_de_energia` | `11a33908-bb0e-4d1a-beb3-9dddb95c563e` | `string/=` | `tipo_de_energia` |

### Ejemplo de body para `POST /api/card/66727/query/json`

```json
{
  "parameters": [
    {
      "id": "fc0f2b30-20b6-4ab4-80c3-5f567a0d42ef",
      "type": "string/=",
      "value": "Costa",
      "target": ["variable", ["template-tag", "tipo_de_mercado"]]
    },
    {
      "id": "d1e69e96-72da-42d7-b296-8e110aedb448",
      "type": "string/=",
      "value": "Directa",
      "target": ["variable", ["template-tag", "tipo_de_medida"]]
    }
  ]
}
```

Todos los parámetros son opcionales — si no se envían, devuelve el universo completo (~5.557 filas).

### Esquema de salida

| Columna | Tipo | Descripción |
|---|---|---|
| `codigo_bia` | text | — |
| `contract_id` | integer | — |
| `mercado` | text | `Costa`, `Interior`, `Centro` (traducido desde OR/departamento) |
| `medida_alcance` | text | `Directa`/`Semidirecta`/`Indirecta` |
| `tipo_de_energia` | text | `Regulada`/`No Regulada` (traducido desde `regulated`/`non-regulated`) |
| `f_instalacion` | timestamp/null | Fecha primera instalación exitosa |
| `mes` | integer/null | Mes de instalación (1–12) |
| `costo_opex` | numeric (COP) | OPEX total del cliente |
| `costo_contratista` | numeric | Costos pagados a contratistas externos |
| `costo_servicio` | numeric | Componente servicio |
| `costo_materiales` | numeric | Componente materiales |
| `transporte` | numeric | Transporte |
| `adicionales` | numeric | Otros |
| `costo_bia` | numeric | Costos internos BIA (visitas con `is_bia=true`) |

### Notas para n8n
- **Valores válidos conocidos:**
  - `tipo_de_mercado`: `Costa`, `Interior`, `Centro`
  - `tipo_de_medida`: `Directa`, `Semidirecta`, `Indirecta`
  - `tipo_de_energia`: `Regulada`, `No Regulada`
- `f_instalacion=null` → el cliente aún no tiene instalación exitosa registrada (costos son de visitas previas, emergencias, etc.).
- Para agregar CAC total: `SUM(costo_opex)` agrupando por `mercado` o `tipo_de_energia`.
- Es la card canónica para dashboards CAC — usarla en n8n para alimentar Google Sheets o Metabase dashboards ejecutivos.

---

## 8. Card 66793 — `Costos asociados a opex`

- **URL:** https://bia.metabaseapp.com/question/66793-costos-asociados-a-opex
- **Database:** `21` (`prod-bia-bi`)
- **Colección:** `13993` OPEX-HDMG
- **Creador:** hernan.manjarres@bia.app
- **Creada:** 2026-04-21
- **Volumen actual:** ~26.139 filas (coincide con `Visitas General` — es join 1:1)

### Propósito
Es la **vista detallada por visita** para OPEX, complementaria a la card 66727 (que agrega por `codigo_bia`). Cada fila es una visita con su desglose de costos y metadatos operativos. Permite rastrear qué componente específico disparó un OPEX alto en un cliente.

### Parámetros

| Nombre | Slug | Parameter ID | Tipo | Template tag |
|---|---|---|---|---|
| Codigo Bia | `codigo_bia` | `1c43f3c9-7ce8-4341-9501-776bfce319f9` | `string/=` | `codigo_bia` |
| Tipo De Medida | `tipo_de_medida` | `6b92922c-9a4e-4ce3-aeca-8fc9c94cd977` | `string/=` | `tipo_de_medida` |
| Titulo Ot | `titulo_OT` | `4d3f706e-43f6-4b5b-a042-a360145483e6` | `string/=` | `titulo_OT` |
| Tipo De Mercado | `tipo_de_mercado` | `0c146346-59d0-4b91-9902-d2b3b55f0bdb` | `string/=` | `tipo_de_mercado` |

### Ejemplo de body

```json
{
  "parameters": [
    {
      "id": "1c43f3c9-7ce8-4341-9501-776bfce319f9",
      "type": "string/=",
      "value": "CO0500005492",
      "target": ["variable", ["template-tag", "codigo_bia"]]
    }
  ]
}
```

### Esquema de salida

| Columna | Tipo | Descripción |
|---|---|---|
| `tipo_de_servicio` | text | `Visita previa`, `Instalación`, `Desconexión`, `Emergencia`, `Normalización` |
| `journey` | text | `Activation`, `Retention`, `Service`, etc. — etapa del customer journey |
| `fase_actual` | text | `Cierre Exitoso`, `Cierre Fallido`, `Cierre Cancelado`, `Pendiente` |
| `titulo` | text | Work order title (`{tipo}_{codigo}_{num}`) |
| `codigo_bia` | text | — |
| `contract_id` | text | **String aquí** (consistente con 55773) |
| `visit_id` | uuid | FK |
| `nombre_de_frontera`, `direccion`, `ciudad` | text | — |
| `operador_de_red` | text | — |
| `contratista` | text/null | — |
| `fecha_programada` | date | Agenda |
| `mes` | integer | Mes de la visita (1–12) |
| `hora_programada` | text (`HH:MM`) | — |
| `tipo_de_medida_alcance` | text | — |
| `mercado` | text | `Costa`/`Interior`/`Centro` |
| `costos_bia` | numeric | Costos BIA (internos) |
| `service_cost` | numeric | — |
| `material_cost` | numeric | — |
| `transport_cost` | numeric | — |
| `other_cost` | numeric | — |
| `total_cost` | numeric | **Ya viene precalculado** (suma de los anteriores + `costos_bia`) |

### Notas para n8n
- Es la **granularidad más fina para analizar OPEX**. Úsala para investigar por qué un cliente específico tiene CAC alto.
- **Ya incluye `total_cost`** — a diferencia de `Opex Costs General` (63163) que requiere cálculo en n8n.
- `journey` permite segmentar: instalaciones (Activation) vs. mantenimiento post-venta (Retention/Service).
- Si filtras por `codigo_bia` y sumas `total_cost`, debería coincidir con `costo_opex` de la card 66727 para ese mismo código.

---

## 9. Relaciones entre cards

Gráfico lógico de joins más útiles para n8n:

```
                    ┌─────────────────────┐
                    │  Hubspot General    │ (55705)
                    │  granularidad: FRT  │
                    │  PK: codigo_bia     │
                    └──────────┬──────────┘
                               │ codigo_bia / contract_id
         ┌─────────────────────┼──────────────────────────┐
         │                     │                          │
         ▼                     ▼                          ▼
┌─────────────────┐   ┌────────────────────┐   ┌─────────────────────┐
│ Alcances Gen.   │   │  Visitas General   │   │ Backlog v3 (65209)  │
│ (55707)         │   │  (55773)           │   │ granularidad: FRT   │
│ granular: ALC   │◄─┤  PK: id (=visit_id)│   │ (solo pre-instal.)  │
│ FK: contract_id │   └──────┬─────────────┘   └─────────────────────┘
└─────────────────┘          │ visit_id
  (DB: 1916)                 │
                             ▼
                  ┌─────────────────────────┐
                  │  Opex Costs General     │
                  │  (63163)                │
                  │  PK: id  FK: visit_id   │
                  └─────────────────────────┘
                             │
                             │ agregación por codigo_bia
                             ▼
                  ┌─────────────────────────┐       ┌─────────────────────────┐
                  │  Costos asoc. opex      │       │  CAC_BIA (66727)        │
                  │  (66793)                │──agg──►  1 fila por codigo_bia │
                  │  1 fila por visita      │       │  costos consolidados    │
                  └─────────────────────────┘       └─────────────────────────┘
```

**Claves recomendadas para joins en n8n:**
- `codigo_bia` (text) — presente en TODAS las cards del DB 21. **Clave canónica.**
- `contract_id` — ojo con el tipo: `integer` en 55705, 63163, 65209, 66727 vs. `string` en 55773 y 66793. Castear.
- `visit_id` ↔ `id` entre 55773 y 63163 — joins a nivel de visita.

---

## 10. Recomendaciones para el pipeline n8n

1. **Credenciales Metabase.** Crea una credencial `HTTP Header Auth` con header `x-api-key: {METABASE_API_KEY}` (o `X-Metabase-Session` con session token). Reusa en todos los HTTP Request nodes.

2. **Estrategia de extracción:**
   - Cards sin parámetros (55707, 55705, 63163, 55773, 65209) → extraer completo en una corrida, almacenar en staging (Google Sheets / Postgres / S3) y dedup por PK.
   - Cards con parámetros (66727, 66793) → pueden filtrarse desde n8n pasando `parameters` en el body, útil para workflows reactivos (ej: "cuando un KAM manda un `codigo_bia` por Slack, devuelve el detalle de costos").

3. **Paginación.** La API `/query/json` no pagina — devuelve todo el resultado de la query. Metabase recorta a 2.000 filas por default en la UI, pero vía API con `row_limit` explícito o exportando por `/query/csv` se obtiene el total. Para volúmenes >10k (63163, 55773, 66793), considerar descargar como CSV y procesar con nodo `Spreadsheet File`.

4. **Cache y frecuencia.** Estas cards corren SQL pesado contra `prod-bia-bi`. Programar pulls cada 1–6 horas (no en tiempo real) y cachear en n8n.

5. **Normalizaciones recomendadas:**
   - `tipo_de_mercado`: unificar a un solo vocabulario (decidir entre `regulated/non-regulated` vs. `Regulada/No Regulada` vs. `Costa/Interior/Centro` que es otra dimensión —región, no mercado).
   - `contract_id`: cast a integer en toda la etapa de staging.
   - Fechas: todas ISO 8601 pero con variantes de timezone. Normalizar a `UTC` en n8n usando `DateTime.fromISO(...)`.

6. **Monitoreo.** Card 65209 (backlog v3) es buena candidata para alertar en Slack cuando aparezcan fronteras con `banda = 🔴 DESESTIMAR` o `aging_neto_dias > 30`.

---

## 11. Cheatsheet rápido

```
# Ejecutar card sin parámetros (n8n HTTP Request)
POST https://bia.metabaseapp.com/api/card/{card_id}/query/json
Headers: x-api-key: {TOKEN}
Body: {}

# Ejecutar card con parámetros
POST https://bia.metabaseapp.com/api/card/{card_id}/query/json
Headers: x-api-key: {TOKEN}, Content-Type: application/json
Body: {
  "parameters": [
    {"id": "<uuid>", "type": "string/=", "value": "<val>",
     "target": ["variable", ["template-tag", "<slug>"]]}
  ]
}

# Export masivo CSV (para >2000 filas)
POST https://bia.metabaseapp.com/api/card/{card_id}/query/csv
```

| card_id | Nombre | DB | Params | Filas | Uso típico |
|---|---|---|---|---|---|
| 55707 | Alcances General | 1916 | — | 5.703 | Detalle técnico por alcance |
| 55705 | Hubspot General | 21 | — | 5.670 | Master comercial fronteras |
| 63163 | Opex Costs General | 21 | — | 23.295 | Detalle costos por visita |
| 55773 | Visitas General | 21 | — | 26.139 | Master operativo visitas |
| 65209 | Backlog v3 | 21 | — | 140 | Priorización backlog |
| 66727 | CAC_BIA | 21 | 4 | 5.557 | CAC agregado por cliente |
| 66793 | Costos asoc. opex | 21 | 4 | 26.139 | Detalle costos por visita (OPEX) |
