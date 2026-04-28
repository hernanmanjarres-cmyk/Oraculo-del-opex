# Diseño Base de Datos — Agente OPEX BIA Energy
## Prompt para dbdiagram.io

> **Instrucciones:**
> 1. Ve a **https://dbdiagram.io/d**
> 2. Borra todo el código del editor izquierdo
> 3. Copia y pega el bloque DBML de abajo
> 4. El diagrama se genera automáticamente con todas las relaciones

---

```dbml
// ============================================================
// BASE DE DATOS: Agente OPEX BIA Energy — Supabase (PostgreSQL)
// Fecha: 28 de abril de 2026
// ============================================================

Table fronteras {
  codigo_bia            varchar   [pk]
  contract_id           integer
  nombre_frontera       varchar
  operador_de_red       varchar
  tipo_de_medida        varchar
  tipo_de_mercado       varchar
  mercado               varchar
  ciudad                varchar
  departamento          varchar
  kam_asignado          varchar
  fase_actual           varchar
  kwh_mes               numeric
  nivel_de_tension      varchar
  factor_de_medida      integer
  fecha_firma_contrato  timestamp
  fecha_activacion      timestamp
  es_frontera_comercial boolean
  ingested_at           timestamp

  Note: "Fuente: Card 55705 — Hubspot General | ~5.670 filas | Tabla maestra de fronteras/contratos"
}

Table contratistas {
  id      varchar   [pk]
  nombre  varchar
  tipo    varchar
  activo  boolean

  Note: "Derivado de opex_costs_general + visitas_general | BIA / GMAS / C3 BOGOTA / Dinovi"
}

Table tarifario {
  item_codigo     varchar   [pk]
  item_nombre     varchar
  unidad          varchar
  contratista_id  varchar
  tarifa_unitaria numeric
  valid_from      date
  valid_to        date

  Note: "PENDIENTE — requiere vista operations.tarifario_general en prod-bia-gold (DB 2344)"
}

Table visitas {
  id                    varchar   [pk]
  codigo_bia            varchar
  contract_id           integer
  titulo                varchar
  service_type_id       varchar
  tipo_de_servicio      varchar
  contratista           varchar
  electrician_status_id varchar
  estado                varchar
  fecha_visita          timestamp
  ciudad                varchar
  operador_de_red       varchar
  act_pdf_url           varchar
  is_bia                boolean
  ingested_at           timestamp

  Note: "Fuente: Card 55773 — Visitas General | ~26.139 filas | 1 fila por work order"
}

Table opex_costos {
  id                integer   [pk]
  visit_id          varchar
  wo_id             varchar
  service_cost      integer
  material_cost     integer
  transport_cost    integer
  other_cost        integer
  total_cost        integer
  status            varchar
  contractor_id     varchar
  service_tariff_id varchar
  created_at        timestamp
  ingested_at       timestamp

  Note: "Fuente: Card 63163 — Opex Costs General | ~23.295 filas | 1 fila por registro de costo"
}

Table opex_items_ot {
  id             integer   [pk, increment]
  visit_id       varchar
  ot_id          varchar
  item_codigo    varchar
  item_nombre    varchar
  cantidad       numeric
  valor_unitario numeric
  valor_total    numeric

  Note: "PENDIENTE — explotación del JSONB selected_tariff_items de opex_costos"
}

Table alcances {
  id                        varchar   [pk]
  codigo_bia                varchar
  contract_id               integer
  tipo_de_alcance           varchar
  fase_actual               varchar
  tipo_de_medida_encontrado varchar
  tipo_de_medida_a_instalar varchar
  viable_para_instalar      varchar
  valor_de_pb_calculado     varchar
  requiere_descargos_del_or varchar
  creado_el                 timestamp
  ingested_at               timestamp

  Note: "Fuente: Card 55707 — Alcances General (DB 1916) | ~5.703 filas"
}

Table backlog_scoring {
  codigo_bia          varchar   [pk]
  costo_opex_estimado numeric
  costo_opex_sales    numeric
  payback_sales       numeric
  delta_opex          numeric
  semaforo_delta      varchar
  banda               varchar
  cac_kwh             numeric
  aging_neto_dias     integer
  fecha_programada    timestamp
  updated_at          timestamp

  Note: "Fuente: Card 65209 — Backlog v3 | ~140 filas | fronteras en proceso de instalación"
}

Table mv_opex_vecindarios {
  id             integer   [pk, increment]
  zona           varchar
  tipo_medida    varchar
  tipo_servicio  varchar
  costo_promedio numeric
  costo_p75      numeric
  n_ots          integer
  calculado_en   timestamp

  Note: "Vista materializada para forecast — calculada sobre visitas + opex_costos históricos"
}

Table recuperacion_opex {
  id             integer   [pk, increment]
  codigo_bia     varchar
  mes            integer
  anio           integer
  valor_cobrable numeric
  valor_cobrado  numeric
  estado         varchar
  fuente         varchar

  Note: "FUTURA — fuente por confirmar con Finanzas (posible: facturacion_dian.invoices)"
}

// ============================================================
// RELACIONES
// ============================================================

Ref: visitas.codigo_bia         > fronteras.codigo_bia
Ref: alcances.codigo_bia        > fronteras.codigo_bia
Ref: backlog_scoring.codigo_bia > fronteras.codigo_bia
Ref: recuperacion_opex.codigo_bia > fronteras.codigo_bia

Ref: opex_costos.visit_id       > visitas.id
Ref: opex_items_ot.visit_id     > visitas.id

Ref: opex_costos.contractor_id  > contratistas.id
Ref: tarifario.contratista_id   > contratistas.id

Ref: opex_costos.service_tariff_id > tarifario.item_codigo
```

---

## Mapa de relaciones

```
fronteras (1) ──< visitas (N)           codigo_bia
fronteras (1) ──< alcances (N)          codigo_bia
fronteras (1) ──  backlog_scoring (1)   codigo_bia
fronteras (1) ──< recuperacion_opex (N) codigo_bia

visitas (1) ──< opex_costos (N)         visit_id
visitas (1) ──< opex_items_ot (N)       visit_id

contratistas (1) ──< opex_costos (N)    contractor_id
contratistas (1) ──< tarifario (N)      contratista_id

tarifario (1) ──< opex_costos (N)       service_tariff_id
```
