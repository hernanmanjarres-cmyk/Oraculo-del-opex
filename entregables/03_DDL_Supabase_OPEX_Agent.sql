-- ============================================================
-- DDL: Agente OPEX BIA Energy — Supabase (PostgreSQL 14)
-- Fecha: 28 de abril de 2026
-- Autor: Hernan Manjarres
-- Fuentes validadas: prod-bia-gold (DB 2344)
--                    prod-electrician-services-contractor (DB 2311)
-- ============================================================
-- Ejecutar en orden. El agente n8n (WF-A) alimenta estas tablas
-- desde Metabase vía ingesta horaria.
-- ============================================================

-- ============================================================
-- 1. CONTRACTORS
-- Fuente: prod-electrician-services-contractor.public.tariff
-- 13 contratistas activos (Tarifario 2026)
-- ============================================================
CREATE TABLE IF NOT EXISTS contractors (
    id                  UUID            PRIMARY KEY,
    contractor_name     VARCHAR(255)    NOT NULL,
    cost_type           VARCHAR(100)    DEFAULT 'service',
    tariff_year         INTEGER,
    tariff_name         VARCHAR(255),
    valid_from          DATE,
    valid_to            DATE,
    is_active           BOOLEAN         DEFAULT true,
    source_tariff_id    BIGINT,         -- id en tabla tariff origen
    created_at          TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ,
    ingested_at         TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE contractors IS 'Contratistas de campo. Fuente: prod-electrician-services-contractor.public.tariff (13 registros - SGE, POWER GRID, C3, ISELEC, DISELEC, GATRIA, ISEMEC, SISE, REHOBOT, MONTAJES MTE, ELECPROYECTOS, MCR ELECTRICA + Anexo N1)';

-- ============================================================
-- 2. TARIFF_CATALOG
-- Fuente: prod-electrician-services-contractor.public.tariff_item
-- ~199 items por contratista x 13 = 2585 filas totales
-- Estructura real: tariff_id + item_number + OR group + amount_cop
-- ============================================================
CREATE TABLE IF NOT EXISTS tariff_catalog (
    id                      BIGINT          PRIMARY KEY,
    tariff_id               BIGINT          NOT NULL,   -- FK a tariff origen
    contractor_id           UUID            REFERENCES contractors(id),
    item_number             INTEGER         NOT NULL,
    activity_name           VARCHAR(500)    NOT NULL,
    network_operator_group  VARCHAR(100)    NOT NULL,   -- ENEL_AIRE_EMCALI_AFINIA | CELSIA_VALLE_ELECTROHUILA_ESSA | OTROS_OR
    base_rate_cop           NUMERIC         NOT NULL,
    night_rate_cop          NUMERIC         GENERATED ALWAYS AS (ROUND(base_rate_cop * 1.20)) STORED,
    sunday_rate_cop         NUMERIC         GENERATED ALWAYS AS (ROUND(base_rate_cop * 1.20)) STORED,
    night_sunday_rate_cop   NUMERIC         GENERATED ALWAYS AS (ROUND(base_rate_cop * 1.35)) STORED,
    night_surcharge_pct     NUMERIC         DEFAULT 0.20,
    sunday_surcharge_pct    NUMERIC         DEFAULT 0.20,
    night_sunday_surcharge_pct NUMERIC      DEFAULT 0.35,
    created_at              TIMESTAMPTZ,
    updated_at              TIMESTAMPTZ,
    ingested_at             TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tariff_catalog_contractor ON tariff_catalog(contractor_id);
CREATE INDEX IF NOT EXISTS idx_tariff_catalog_item ON tariff_catalog(item_number);
CREATE INDEX IF NOT EXISTS idx_tariff_catalog_or_group ON tariff_catalog(network_operator_group);

COMMENT ON TABLE tariff_catalog IS 'Items de tarifa por contratista x grupo de OR. Fuente: prod-electrician-services-contractor.public.tariff_item (2585 filas). Recargos: nocturno +20%, dominical +20%, nocturno+dominical +35% (columnas calculadas automáticamente).';
COMMENT ON COLUMN tariff_catalog.night_rate_cop IS 'base_rate_cop * 1.20 — recargo nocturno (+20%). Columna calculada.';
COMMENT ON COLUMN tariff_catalog.sunday_rate_cop IS 'base_rate_cop * 1.20 — recargo dominical (+20%). Columna calculada.';
COMMENT ON COLUMN tariff_catalog.night_sunday_rate_cop IS 'base_rate_cop * 1.35 — recargo nocturno + dominical (+35%). Columna calculada.';
COMMENT ON COLUMN tariff_catalog.network_operator_group IS 'Grupos OR: ENEL_AIRE_EMCALI_AFINIA | CELSIA_VALLE_ELECTROHUILA_ESSA | OTROS_OR';

-- ============================================================
-- 3. OPERATION_TYPES
-- Fuente: prod-electrician-services-contractor.public.operation_hours
-- 24 tipos de servicio con horas estimadas por tipo de medida
-- ============================================================
CREATE TABLE IF NOT EXISTS operation_types (
    id                  BIGINT          PRIMARY KEY,
    operation_type      VARCHAR(255)    NOT NULL,
    service_type_id     VARCHAR(50)     NOT NULL UNIQUE,  -- INST, VIPE, VICO, LEGA, NOTE, ALRT, DESX, NORM, etc.
    direct_hours        NUMERIC,
    semidirect_hours    NUMERIC,
    indirect_hours      NUMERIC,
    created_at          TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ,
    ingested_at         TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE operation_types IS 'Tipos de operación con horas estimadas por tipo de medida. Fuente: prod-electrician-services-contractor.public.operation_hours (24 tipos: INST, VIPE, VICO, LEGA, NOTE, ALRT, DESX, NORM, AING, PRRU, etc.)';

-- ============================================================
-- 4. FRONTERAS
-- Fuente: prod-bia-gold.operations.hubspot_general
-- ~5,647 filas — tabla maestra de fronteras/contratos
-- ============================================================
CREATE TABLE IF NOT EXISTS fronteras (
    bia_code                            VARCHAR(50)     PRIMARY KEY,
    contract_id                         NUMERIC,
    frontier_title                      TEXT,
    current_phase                       TEXT,           -- Completado, On Hold, Desistidos, Visita previa, etc.
    sic_code                            TEXT,           -- Código SIC (ej: frt85123)
    niu                                 TEXT,
    nic                                 TEXT,
    grid_operator                       TEXT,           -- ENEL CUNDINAMARCA, AIRE CARIBE, CODENSA, etc.
    market_type                         TEXT,           -- regulated / non-regulated
    measurement_type                    TEXT,           -- Directa / Semidirecta / Indirecta
    voltage_level                       TEXT,           -- level_1 / level_2 / level_3 / level_4
    measurement_factor                  NUMERIC,
    energy_kwh_month                    NUMERIC,
    city                                TEXT,
    department                          TEXT,
    address                             TEXT,
    kam_assigned                        VARCHAR(255),
    operation_account_executive         VARCHAR(255),
    company_nit                         VARCHAR(100),
    company_name                        VARCHAR(500),
    company_ciiu                        BIGINT,
    equipment_ownership                 TEXT,           -- or / user
    contract_sign_date                  TIMESTAMPTZ,
    installation_date                   TIMESTAMPTZ,   -- fecha_real_de_registro (registro ante XM)
    activation_date                     TIMESTAMPTZ,   -- fecha_real_de_activacion
    is_commercial_border                TEXT,           -- Si / No
    received_paz_y_salvo                TEXT,
    paz_y_salvo_expiry_date             TIMESTAMPTZ,
    xm_requirement_number               TEXT,
    on_hold_reason                      TEXT,
    on_hold_detail                      TEXT,
    meter_serial_registered             TEXT,
    -- Pipeline phase durations (días en cada etapa)
    days_in_paz_y_salvo                 NUMERIC,
    days_in_visita_previa               NUMERIC,
    days_in_asignacion_equipos          NUMERIC,
    days_in_activar_instalar            NUMERIC,
    days_in_completado                  NUMERIC,
    days_in_on_hold                     NUMERIC,
    days_in_desistidos                  NUMERIC,
    source_created_at                   TIMESTAMPTZ,
    ingested_at                         TIMESTAMPTZ     DEFAULT NOW(),
    updated_at                          TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fronteras_contract_id ON fronteras(contract_id);
CREATE INDEX IF NOT EXISTS idx_fronteras_phase ON fronteras(current_phase);
CREATE INDEX IF NOT EXISTS idx_fronteras_grid_operator ON fronteras(grid_operator);
CREATE INDEX IF NOT EXISTS idx_fronteras_sic ON fronteras(sic_code);

COMMENT ON TABLE fronteras IS 'Tabla maestra de fronteras/contratos. Fuente: prod-bia-gold.operations.hubspot_general (~5,647 filas). Clave canónica: bia_code = codigo_bia en todas las fuentes.';
COMMENT ON COLUMN fronteras.installation_date IS 'Mapea fecha_real_de_registro (registro ante XM). No confundir con activation_date.';

-- ============================================================
-- 5. VISITS
-- Fuente: prod-bia-gold.operations.visitas_general
-- ~26,139 filas — 1 fila por visita / work order
-- ============================================================
CREATE TABLE IF NOT EXISTS visits (
    id                      UUID            PRIMARY KEY,
    bia_code                VARCHAR(50)     REFERENCES fronteras(bia_code),
    contract_id             VARCHAR(50),    -- llega como string en esta fuente
    work_order_title        VARCHAR(255),   -- patrón: {TIPO}_{bia_code}_{num}
    service_type_id         VARCHAR(50),    -- INST, VIPE, VICO, LEGA, NOTE, ALRT, DESX, NORM, etc.
    service_name            VARCHAR(255),   -- Instalación, Visita previa, Emergencia, etc.
    visit_type_id           VARCHAR(50),
    electrician_status_id   VARCHAR(50),    -- CLOSURE_SUCCESSFUL, CLOSURE_FAILED, CLOSURE_CANCELLED
    status_label            VARCHAR(100),   -- Cierre Exitoso, Fallido, Cancelado (ES)
    status_app              VARCHAR(50),    -- COMPLETED, CANCELLED, etc.
    contractor_name         VARCHAR(255),   -- BIA, GMAS, C3, POWER GRID, etc.
    electrician_id          VARCHAR(255),
    electricians            TEXT,           -- nombres separados por coma
    grid_operator           VARCHAR(255),
    city                    VARCHAR(255),
    department              VARCHAR(255),
    address                 TEXT,
    company_id              VARCHAR(255),
    company_name            VARCHAR(255),
    measurement_type_id     VARCHAR(50),
    act_pdf_url             VARCHAR(1000),
    is_bia                  BOOLEAN,        -- true = costo interno BIA
    visit_date              TIMESTAMPTZ,
    observation             TEXT,
    reason                  TEXT,
    created_at              TIMESTAMPTZ,
    updated_at              TIMESTAMPTZ,
    deleted_at              TIMESTAMPTZ,
    ingested_at             TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_visits_bia_code ON visits(bia_code);
CREATE INDEX IF NOT EXISTS idx_visits_service_type ON visits(service_type_id);
CREATE INDEX IF NOT EXISTS idx_visits_status ON visits(electrician_status_id);
CREATE INDEX IF NOT EXISTS idx_visits_date ON visits(visit_date);
CREATE INDEX IF NOT EXISTS idx_visits_contractor ON visits(contractor_name);

COMMENT ON TABLE visits IS 'Visitas de campo (work orders). Fuente: prod-bia-gold.operations.visitas_general (~26,139 filas). PK: id (uuid) = visit_id en opex_costs.';

-- ============================================================
-- 6. OPEX_COSTS
-- Fuente: prod-bia-gold.operations.opex_costs_general
--         prod-electrician-services-contractor.public.opex_costs
-- ~23,349 filas — 1 fila por registro de costo
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_costs (
    id                      BIGINT          PRIMARY KEY,
    visit_id                UUID            REFERENCES visits(id),
    wo_id                   VARCHAR(255),
    visit_title             VARCHAR(255),
    service_cost            NUMERIC         DEFAULT 0,
    material_cost           NUMERIC         DEFAULT 0,
    transport_cost          NUMERIC         DEFAULT 0,
    other_cost              NUMERIC         DEFAULT 0,
    total_cost              NUMERIC         GENERATED ALWAYS AS (
                                COALESCE(service_cost,0)
                                + COALESCE(material_cost,0)
                                + COALESCE(transport_cost,0)
                                + COALESCE(other_cost,0)
                            ) STORED,
    status                  VARCHAR(50),    -- accepted, pending, rejected, validation
    enabled                 BOOLEAN         DEFAULT true,
    contractor_id           VARCHAR(255),
    service_tariff_id       BIGINT,         -- FK a tariff.id en origen
    electrician_status_id   VARCHAR(50),
    act_pdf_url             VARCHAR(1000),
    is_bia                  BOOLEAN,
    comments                VARCHAR(1000),
    details                 TEXT,
    user_id                 VARCHAR(255),
    visit_start             TIMESTAMPTZ,
    created_at              TIMESTAMPTZ,
    updated_at              TIMESTAMPTZ,
    ingested_at             TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_opex_costs_visit_id ON opex_costs(visit_id);
CREATE INDEX IF NOT EXISTS idx_opex_costs_status ON opex_costs(status);
CREATE INDEX IF NOT EXISTS idx_opex_costs_contractor ON opex_costs(contractor_id);
CREATE INDEX IF NOT EXISTS idx_opex_costs_tariff ON opex_costs(service_tariff_id);

COMMENT ON TABLE opex_costs IS 'Costos operativos por visita. Fuente: prod-bia-gold.operations.opex_costs_general (~23,349 filas). total_cost calculado automáticamente. status=accepted = registros válidos.';
COMMENT ON COLUMN opex_costs.total_cost IS 'Suma calculada: service_cost + material_cost + transport_cost + other_cost. Columna generada.';

-- ============================================================
-- 7. OPEX_COST_ITEMS
-- Fuente: campo JSONB selected_tariff_items de opex_costs
-- Estructura real validada: [{amount, quantity, item_number, activity_name}]
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_cost_items (
    id              BIGSERIAL       PRIMARY KEY,
    opex_cost_id    BIGINT          REFERENCES opex_costs(id),
    visit_id        UUID            REFERENCES visits(id),
    item_number     INTEGER,
    activity_name   TEXT,
    quantity        NUMERIC         DEFAULT 1,
    amount_cop      NUMERIC,
    total_cop       NUMERIC         GENERATED ALWAYS AS (quantity * amount_cop) STORED,
    ingested_at     TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_opex_cost_items_visit ON opex_cost_items(visit_id);
CREATE INDEX IF NOT EXISTS idx_opex_cost_items_item ON opex_cost_items(item_number);

COMMENT ON TABLE opex_cost_items IS 'Explotación del JSONB selected_tariff_items de opex_costs. Estructura real: [{amount, quantity, item_number, activity_name}]. total_cop = quantity * amount_cop (calculado).';

-- ============================================================
-- 8. SCOPES (ALCANCES)
-- Fuente: prod-bia-gold.operations.alcances_general
-- ~5,743 filas — alcances técnicos previos a visita
-- ============================================================
CREATE TABLE IF NOT EXISTS scopes (
    id                              UUID            PRIMARY KEY,
    bia_code                        TEXT            REFERENCES fronteras(bia_code),
    contract_id                     TEXT,
    scope_type                      TEXT,           -- INST, VIPE, NORM, ALRT, DESX
    current_phase                   TEXT,           -- COMPLETED, IN_PROGRESS
    measurement_type_found          TEXT,           -- Directa, Semidirecta, Indirecta
    measurement_type_to_install     TEXT,
    voltage_level                   TEXT,
    measurement_factor_found        TEXT,
    viable_to_install               TEXT,           -- Sí / No
    payback_calculation             TEXT,
    payback_value                   TEXT,
    payback_calc_link               TEXT,
    meter_serial                    TEXT,
    requires_or_disconnection       TEXT,
    disconnection_affects_users     TEXT,
    is_commercial_border            TEXT,
    antenna_location                TEXT,
    requires_high_gain_antenna      TEXT,
    contact_name                    TEXT,
    contact_phone                   TEXT,
    contact_email                   TEXT,
    title                           TEXT,
    created_at                      TIMESTAMPTZ,
    ingested_at                     TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scopes_bia_code ON scopes(bia_code);
CREATE INDEX IF NOT EXISTS idx_scopes_type ON scopes(scope_type);
CREATE INDEX IF NOT EXISTS idx_scopes_phase ON scopes(current_phase);

COMMENT ON TABLE scopes IS 'Alcances técnicos (formulario pre-visita). Fuente: prod-bia-gold.operations.alcances_general (~5,743 filas). Fuente origen: electrician-scopes-prod.public.requirements (vía dblink).';

-- ============================================================
-- 9. BACKLOG_SCORING
-- Fuente: card 65209 — Backlog v3 (prod-bia-bi)
-- ~140 filas activas — fronteras en pipeline de instalación
-- ============================================================
CREATE TABLE IF NOT EXISTS backlog_scoring (
    bia_code                    VARCHAR(50)     PRIMARY KEY REFERENCES fronteras(bia_code),
    contract_id                 INTEGER,
    frontier_name               TEXT,
    grid_operator               TEXT,
    measurement_type            TEXT,
    market_type                 TEXT,
    current_phase               TEXT,
    city                        TEXT,
    department                  TEXT,
    kwh_per_month               NUMERIC,
    scheduled_date              TIMESTAMPTZ,
    successful_install_date     TIMESTAMPTZ,
    contract_sign_date          TIMESTAMPTZ,
    -- Costos estimados
    estimated_vipe_cost         NUMERIC,
    estimated_install_cost_adj  NUMERIC,        -- ajustado por región
    estimated_legalization_cost NUMERIC,
    total_estimated_visit_cost  NUMERIC,
    estimated_opex_cost         NUMERIC,        -- total OPS
    -- Costos Sales
    sales_opex_cost             NUMERIC,
    sales_payback_months        NUMERIC,
    -- Delta y semáforos
    opex_delta                  NUMERIC,        -- sales - estimado (negativo = Sales subestimó)
    delta_traffic_light         TEXT,           -- HOLGURA / AJUSTADO / DÉFICIT MODERADO / DÉFICIT ALTO
    recommendation_band         TEXT,           -- INSTALAR / INSTALAR - MENOS PRIORITARIO / DESESTIMAR
    cac_per_kwh                 NUMERIC,
    net_aging_days              INTEGER,
    updated_at                  TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE backlog_scoring IS 'Scoring del backlog activo. Fuente: card 65209 - Backlog v3 (~140 filas). Actualizar en cada ejecución de WF-A. Campos de semáforo: delta_traffic_light y recommendation_band.';

-- ============================================================
-- 10. OPEX_NEIGHBORHOODS (para forecast por vecindario)
-- Vista materializada calculada sobre visitas + opex_costs
-- Se recalibra mensualmente con datos históricos aceptados
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_neighborhoods (
    id                  BIGSERIAL       PRIMARY KEY,
    market_region       VARCHAR(50)     NOT NULL,   -- Costa / Centro / Interior
    measurement_type    VARCHAR(50)     NOT NULL,   -- Directa / Semidirecta / Indirecta
    service_type_id     VARCHAR(50)     NOT NULL,   -- INST, VIPE, ALRT, NORM, DESX
    avg_total_cost      NUMERIC,
    p50_total_cost      NUMERIC,
    p75_total_cost      NUMERIC,
    p90_total_cost      NUMERIC,
    total_work_orders   INTEGER,
    calculated_at       TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(market_region, measurement_type, service_type_id)
);

COMMENT ON TABLE opex_neighborhoods IS 'Costos promedio por segmento (zona x tipo medida x tipo servicio). Usado para forecast del backlog. Recalibrar mensualmente con WF recalibración.';

-- ============================================================
-- 11. OPEX_RECOVERY (futuro — fuente pendiente con Finanzas)
-- ============================================================
CREATE TABLE IF NOT EXISTS opex_recovery (
    id                  BIGSERIAL       PRIMARY KEY,
    bia_code            VARCHAR(50)     REFERENCES fronteras(bia_code),
    month               INTEGER         CHECK (month BETWEEN 1 AND 12),
    year                INTEGER,
    recoverable_amount  NUMERIC,
    recovered_amount    NUMERIC,
    recovery_status     VARCHAR(50),    -- pending / recovered / unrecoverable
    recovery_source     VARCHAR(100),   -- client / grid_operator / agent
    notes               TEXT,
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE opex_recovery IS 'FUTURA — recuperación de OPEX cobrado. Fuente por confirmar con Finanzas (posible: facturacion_dian.invoices). No bloquea WF-A.';

-- ============================================================
-- VISTAS ÚTILES PARA EL AGENTE
-- ============================================================

-- Vista: OPEX total por frontera (equivale a card 66727 CAC_BIA)
CREATE OR REPLACE VIEW v_opex_by_frontier AS
SELECT
    f.bia_code,
    f.market_type,
    f.measurement_type,
    f.grid_operator,
    f.city,
    COUNT(DISTINCT v.id)            AS total_visits,
    SUM(oc.total_cost)              AS total_opex_cost,
    SUM(CASE WHEN v.is_bia THEN oc.total_cost ELSE 0 END) AS bia_cost,
    SUM(CASE WHEN NOT v.is_bia THEN oc.total_cost ELSE 0 END) AS contractor_cost,
    MAX(v.visit_date)               AS last_visit_date
FROM fronteras f
JOIN visits v ON v.bia_code = f.bia_code
JOIN opex_costs oc ON oc.visit_id = v.id
WHERE oc.status = 'accepted'
GROUP BY f.bia_code, f.market_type, f.measurement_type, f.grid_operator, f.city;

-- Vista: Alerta backlog con déficit alto
CREATE OR REPLACE VIEW v_backlog_alerts AS
SELECT
    bs.bia_code,
    bs.frontier_name,
    bs.recommendation_band,
    bs.delta_traffic_light,
    bs.opex_delta,
    bs.cac_per_kwh,
    bs.net_aging_days,
    bs.scheduled_date,
    f.kam_assigned,
    f.grid_operator,
    f.measurement_type
FROM backlog_scoring bs
JOIN fronteras f ON f.bia_code = bs.bia_code
WHERE bs.recommendation_band ILIKE '%DESESTIMAR%'
   OR bs.delta_traffic_light ILIKE '%DÉFICIT ALTO%'
   OR bs.net_aging_days > 30;

-- ============================================================
-- TABLA DE CONTROL DE INGESTA (para WF-A en n8n)
-- ============================================================
CREATE TABLE IF NOT EXISTS ingestion_log (
    id              BIGSERIAL       PRIMARY KEY,
    table_name      VARCHAR(100)    NOT NULL,
    source_card_id  INTEGER,
    source_db       VARCHAR(100),
    rows_ingested   INTEGER,
    rows_updated    INTEGER,
    rows_failed     INTEGER         DEFAULT 0,
    status          VARCHAR(50),    -- success / partial / failed
    error_detail    TEXT,
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE ingestion_log IS 'Log de cada ejecución de WF-A. Una fila por tabla por ejecución. Permite detectar fallos y calcular SLA de ingesta.';
