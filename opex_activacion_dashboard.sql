-- =====================================================================
-- Dashboard OPEX de Activación — query base
-- =====================================================================
-- Granularidad     : una fila por OT (visita)
-- Imputación       : por fecha_visita
-- Status de costos : todos los cargados (accepted + pending + rejected)
-- Ventana          : últimos 12 meses rolling
-- Ciclo            : Activación únicamente (8 service_type_id)
-- Base de datos    : prod-bia-gold
--
-- Notas:
--   * Los 4 rubros y `costo_total_ot` reflejan solo costo del contratista
--     externo (is_bia = false). El costo BIA (HH interna) va aparte.
--   * `costo_total_ot_bia` = costo_total_ot + costo_bia.
--   * `acompanamiento`: COP 360.000 fijo por cada INST.
--   * `descargo`: solo para INST de fronteras Semidirectas o Indirectas,
--     valor según operador_de_red (ENEL 6M, EPM 3M, ESSA 3M, CELSIA 1M).
-- =====================================================================

WITH service_names AS (
    SELECT * FROM (VALUES
        ('PREV', 'Visita pre-venta'),
        ('VIPE', 'Visita previa'),
        ('INST', 'Instalación'),
        ('NORM', 'Normalización de medida'),
        ('REQA', 'Revisión por QA'),
        ('LEGA', 'Legalización'),
        ('VEXT', 'Verificación externa'),
        ('SUCA', 'Suministro de carro canasta')
    ) AS s(service_type_id, service_name)
),

costos_por_visita AS (
    SELECT
        visit_id,
        -- Costos del contratista externo (is_bia = false)
        SUM(CASE WHEN NOT COALESCE(is_bia, false) THEN COALESCE(service_cost,   0) ELSE 0 END) AS costo_servicio,
        SUM(CASE WHEN NOT COALESCE(is_bia, false) THEN COALESCE(material_cost,  0) ELSE 0 END) AS costo_materiales,
        SUM(CASE WHEN NOT COALESCE(is_bia, false) THEN COALESCE(transport_cost, 0) ELSE 0 END) AS costo_transporte,
        SUM(CASE WHEN NOT COALESCE(is_bia, false) THEN COALESCE(other_cost,     0) ELSE 0 END) AS costo_otros,
        SUM(CASE WHEN NOT COALESCE(is_bia, false) THEN
              COALESCE(service_cost,   0)
            + COALESCE(material_cost,  0)
            + COALESCE(transport_cost, 0)
            + COALESCE(other_cost,     0)
        ELSE 0 END) AS costo_total_ot,
        -- Costo BIA (HH interna)
        SUM(CASE WHEN COALESCE(is_bia, false) THEN
              COALESCE(service_cost,   0)
            + COALESCE(material_cost,  0)
            + COALESCE(transport_cost, 0)
            + COALESCE(other_cost,     0)
        ELSE 0 END) AS costo_bia,
        STRING_AGG(DISTINCT status, ', ' ORDER BY status) AS status_cobro
    FROM operations.opex_costs_general
    GROUP BY visit_id
)

SELECT
    -- Identificadores
    v.title                                              AS codigo_ot,
    v.internal_bia_code                                  AS codigo_bia,
    v.contract_id,
    v.contract_name,

    -- Fechas
    v.fecha_visita,
    TO_CHAR(v.fecha_visita, 'YYYY-MM')                   AS anio_mes,

    -- Servicio y estado (legibles)
    sn.service_name,
    CASE
        WHEN v.electrician_status_id = 'CLOSURE_SUCCESSFUL' THEN 'Cierre Exitoso'
        WHEN v.electrician_status_id = 'CLOSURE_FAILED'     THEN 'Cierre Fallido'
        WHEN v.electrician_status_id ILIKE '%CANCEL%'       THEN 'Cancelado'
        ELSE v.electrician_status_id
    END                                                  AS estado_ot,
    v.reason                                             AS razon_cierre,
    v.observation                                        AS observacion_cierre,

    -- Contratista y geografía
    v.contratista,
    h.operador_de_red,
    h.ciudad,
    h.departamento,

    -- Características de la frontera
    h.tipo_de_medida,
    h.tipo_de_mercado,

    -- Status del cobro
    cv.status_cobro,

    -- Rubros del contratista externo
    COALESCE(cv.costo_servicio,    0)                    AS costo_servicio,
    COALESCE(cv.costo_materiales,  0)                    AS costo_materiales,
    COALESCE(cv.costo_transporte,  0)                    AS costo_transporte,
    COALESCE(cv.costo_otros,       0)                    AS costo_otros,
    COALESCE(cv.costo_total_ot,    0)                    AS costo_total_ot,

    -- Costo BIA y total combinado
    COALESCE(cv.costo_bia,         0)                    AS costo_bia,
    COALESCE(cv.costo_total_ot, 0)
      + COALESCE(cv.costo_bia,  0)                       AS costo_total_ot_bia,

    -- Acompañamiento: constante COP 360.000 por cada INST
    CASE
        WHEN v.service_type_id = 'INST' THEN 360000
        ELSE 0
    END                                                  AS acompanamiento,

    -- Descargo: solo INST de Semidirecta o Indirecta, valor por OR
    CASE
        WHEN v.service_type_id = 'INST'
         AND h.tipo_de_medida IN (
                'Semidirecta',
                'Indirecta interior',
                'Indirecta exterior en poste'
             )
        THEN
            CASE
                WHEN UPPER(h.operador_de_red) LIKE '%ENEL%'   THEN 6000000
                WHEN UPPER(h.operador_de_red) LIKE '%EPM%'    THEN 3000000
                WHEN UPPER(h.operador_de_red) LIKE '%ESSA%'   THEN 3000000
                WHEN UPPER(h.operador_de_red) LIKE '%CELSIA%' THEN 1000000
                ELSE 0
            END
        ELSE 0
    END                                                  AS descargo

FROM operations.visitas_general v
LEFT JOIN costos_por_visita cv
       ON cv.visit_id::text = v.id::text
LEFT JOIN operations.hubspot_general h
       ON h.codigo_bia = v.internal_bia_code
LEFT JOIN service_names sn
       ON sn.service_type_id = v.service_type_id

WHERE v.service_type_id IN ('PREV','VIPE','INST','NORM','REQA','LEGA','VEXT','SUCA')
  AND v.fecha_visita >= (CURRENT_DATE - INTERVAL '12 months')
  AND v.fecha_visita <= CURRENT_DATE

ORDER BY v.fecha_visita DESC, v.title;
