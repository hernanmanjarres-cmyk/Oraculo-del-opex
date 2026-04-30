# Arquitectura MVC — Oráculo del OPEX · BIA Energy

**Proyecto:** Agente de IA para monitoreo de costos OPEX  
**Stack:** n8n Cloud · Supabase (PostgreSQL) · Claude AI · Slack · Metabase  
**Fecha:** 30 de abril de 2026

---

## Entregable 1 — Diagrama de Estructura de Carpetas (MVC)

```
Oraculo-del-opex/
│
├── 📂 model/                              ← CAPA MODELO (datos y esquema)
│   ├── 03_DDL_Supabase_OPEX_Agent.sql     → Schema principal (10 tablas fuente)
│   ├── 08_DDL_Memoria_Feedback_Prefs.sql  → Schema IA (agent_memory, agent_user_prefs)
│   └── 02_Diseno_BD.dbml                  → Diseño entidad-relación
│
├── 📂 controller/                         ← CAPA CONTROLADOR (lógica de negocio)
│   │
│   ├── 📂 ingesta/                        → Sincronización de datos (CRUD Read + Write)
│   │   ├── 05_WF-A1_Ingesta_Horaria.json  → Ejecuta cada hora (incremental updated_at)
│   │   └── 05_WF-A2_Ingesta_Semanal.json  → Ejecuta cada semana (full scan)
│   │
│   ├── 📂 agente/                         → Inteligencia artificial (CRUD Read + Write)
│   │   ├── 06_WF-B_Agente_Claude.json             → Orquestador principal (Claude AI)
│   │   ├── 06_WF-B-T1_Tool_QuerySupabase.json     → Herramienta: SQL libre a Supabase
│   │   ├── 06_WF-B-T2_Tool_BacklogAlerts.json     → Herramienta: alertas del backlog
│   │   └── 06_WF-B-T3_Tool_CostoEstimado.json     → Herramienta: cálculo de costo OPEX
│   │
│   └── 📂 receptor/                       → Entrada de eventos (routing)
│       └── 07_WF-C_Slack_Receptor.json    → Recibe Slack Events API, enruta a WF-B
│
├── 📂 view/                               ← CAPA VISTA (interfaces de usuario)
│   ├── [Slack] #opex-alertas              → Alertas automáticas de desvíos
│   ├── [Slack] #opex-aprobacion           → Flujo de aprobación de anomalías
│   ├── [Slack] #opex-cierre               → Reportes de cierre mensual
│   ├── [Slack] #opex-errors               → Errores del sistema
│   └── [Metabase] Cards 66793 / 65209 / 19440  → Dashboards de costos y backlog
│
└── 📂 docs/                               ← DOCUMENTACIÓN
    ├── 01_Fuentes_de_datos_Metabase.md    → Catálogo de fuentes y campos
    ├── 04_Queries_WF-A_Metabase.md        → Queries de extracción Metabase
    ├── 09_Arquitectura_MVC_OPEX.md        → Este documento
    └── Requerimientos_BD_Agente_OPEX_BIA.docx → Requerimientos formales
```

### Mapeo MVC

| Capa | Tecnología | Responsabilidad |
|------|-----------|-----------------|
| **Model** | Supabase (PostgreSQL) | Almacena, valida y sirve los datos. DDL define el esquema. |
| **Controller** | n8n Cloud + Claude AI | Procesa solicitudes, ejecuta lógica, escribe/lee del modelo. |
| **View** | Slack + Metabase | Presenta resultados al usuario. No contiene lógica de negocio. |

### CRUD por capa

| Operación | Quién la ejecuta | Sobre qué tabla |
|-----------|-----------------|-----------------|
| **Create** | WF-A1 (INSERT) | fronteras, visits, opex_costs, opex_cost_items, contractors |
| **Read** | WF-B herramientas (SELECT) | Todas las tablas vía query_supabase |
| **Update** | WF-A1 (UPSERT) / WF-C (feedback) | Tablas fuente / agent_memory.feedback |
| **Delete** | WF-A1 (DELETE selectivo) | opex_cost_items (re-ingesta limpia) |

---

## Entregable 2 — Diagrama de Base de Datos (Tablas y Relaciones)

```mermaid
erDiagram

    %% ── TABLAS FUENTE (ingesta desde Metabase) ──────────────────

    contractors {
        UUID id PK
        VARCHAR contractor_name
        INTEGER tariff_year
        BOOLEAN is_active
        TIMESTAMPTZ updated_at
    }

    tariff_catalog {
        BIGINT id PK
        UUID contractor_id FK
        INTEGER item_number
        VARCHAR activity_name
        VARCHAR network_operator_group
        NUMERIC base_rate_cop
        NUMERIC night_rate_cop
        NUMERIC sunday_rate_cop
    }

    operation_types {
        BIGINT id PK
        VARCHAR service_type_id
        VARCHAR operation_type
        NUMERIC direct_hours
        NUMERIC semidirect_hours
        NUMERIC indirect_hours
    }

    fronteras {
        VARCHAR bia_code PK
        TEXT frontier_title
        TEXT current_phase
        TEXT grid_operator
        TEXT measurement_type
        TEXT city
        VARCHAR kam_assigned
        TIMESTAMPTZ updated_at
    }

    visits {
        UUID id PK
        VARCHAR bia_code FK
        VARCHAR service_type_id
        VARCHAR electrician_status_id
        VARCHAR contractor_name
        TIMESTAMPTZ visit_date
        TIMESTAMPTZ updated_at
    }

    opex_costs {
        BIGINT id PK
        UUID visit_id FK
        NUMERIC service_cost
        NUMERIC material_cost
        NUMERIC total_cost
        VARCHAR status
        VARCHAR contractor_id
        TIMESTAMPTZ updated_at
    }

    opex_cost_items {
        BIGSERIAL id PK
        BIGINT opex_cost_id FK
        UUID visit_id FK
        INTEGER item_number
        TEXT activity_name
        NUMERIC quantity
        NUMERIC amount_cop
        NUMERIC total_cop
    }

    scopes {
        UUID id PK
        TEXT bia_code FK
        TEXT scope_type
        TEXT current_phase
        TIMESTAMPTZ updated_at
    }

    backlog_scoring {
        VARCHAR bia_code PK
        VARCHAR frontier_name
        VARCHAR recommendation_band
        VARCHAR delta_traffic_light
        NUMERIC opex_delta
        NUMERIC cac_per_kwh
        INTEGER net_aging_days
        VARCHAR kam_assigned
    }

    %% ── TABLAS DEL AGENTE (gestionadas por n8n) ─────────────────

    opex_alerts {
        BIGSERIAL id PK
        VARCHAR bia_code FK
        VARCHAR alert_type
        VARCHAR estado
        NUMERIC valor_detectado
        TIMESTAMPTZ created_at
    }

    opex_cases {
        BIGSERIAL id PK
        BIGINT alert_id FK
        VARCHAR veredicto
        TEXT notas
        TIMESTAMPTZ resolved_at
    }

    opex_forecasts {
        BIGSERIAL id PK
        VARCHAR bia_code FK
        NUMERIC forecast_cop
        DATE forecast_month
        TIMESTAMPTZ created_at
    }

    agent_memory {
        SERIAL id PK
        TEXT user_id
        TEXT session_id
        TEXT question
        TEXT answer
        TEXT channel_id
        SMALLINT feedback
        TEXT feedback_note
        TIMESTAMPTZ created_at
    }

    agent_user_prefs {
        TEXT user_id PK
        TEXT display_name
        TEXT response_style
        TEXT notes
        TIMESTAMPTZ updated_at
    }

    %% ── RELACIONES ───────────────────────────────────────────────

    contractors       ||--o{ tariff_catalog    : "tiene ítems"
    fronteras         ||--o{ visits            : "tiene visitas"
    fronteras         ||--o{ scopes            : "tiene alcances"
    fronteras         ||--o{ opex_alerts       : "genera alertas"
    fronteras         ||--o{ opex_forecasts    : "tiene forecast"
    fronteras         }o--o| backlog_scoring   : "scoring activo"
    visits            ||--o| opex_costs        : "tiene costo"
    opex_costs        ||--o{ opex_cost_items   : "tiene ítems"
    opex_alerts       ||--o| opex_cases        : "genera caso"
    operation_types   ||--o{ visits            : "clasifica"
    agent_memory      }o--|| agent_user_prefs  : "pertenece a"
```

### Leyenda de relaciones

| Símbolo | Significado |
|---------|------------|
| `\|\|--o{` | Uno a muchos (obligatorio → opcional) |
| `\|\|--o\|` | Uno a uno (obligatorio → opcional) |
| `}o--o\|` | Muchos a uno (opcional → opcional) |

### Grupos de tablas

| Grupo | Tablas | Origen |
|-------|--------|--------|
| **Maestras** | contractors, fronteras, operation_types | Metabase (externas) |
| **Transaccionales** | visits, opex_costs, opex_cost_items, scopes | Metabase (externas) |
| **Scoring** | backlog_scoring | Metabase (calculada) |
| **Agente** | opex_alerts, opex_cases, opex_forecasts | n8n (generadas) |
| **Memoria IA** | agent_memory, agent_user_prefs | n8n (aprendizaje) |

---

*Generado automáticamente desde el repositorio del proyecto. Stack: n8n 1.123.33 · Supabase (PostgreSQL 14) · Claude Sonnet 4.6 · Slack Events API.*
