# Diccionario de cards Metabase usadas por WF-01b

**Última revisión:** 2026-04-27.

---

## Card 65209 — Backlog de fronteras (estado activo)

**URL:** `https://bia.metabaseapp.com/question/65209` (validar)
**Propósito:** Listado de fronteras vigentes en el ciclo de activación con costos estimados, banda de priorización y aging.
**Tamaño aproximado:** Variable según cierre de mes; en muestreo del 2026-04-27 ~ algunos miles de filas.
**Filtros default sugeridos al consumir desde n8n:** banda ∈ (`INSTALAR`, `INSTALAR - MENOS PRIORITARIO`).

### 1.1 Identificadores

| Campo | Tipo | Descripción |
|---|---|---|
| `codigo_bia` | string | ID interno único de la frontera en BIA |
| `contract_id` | string | ID del contrato comercial asociado |
| `nombre_frontera` | string | Nombre comercial / cliente |

### 1.2 Contexto geográfico y operativo

| Campo | Tipo | Descripción |
|---|---|---|
| `operador_de_red` | string | OR — uno de los 14 listados en sección "Mapeo de zona" del diseño WF-01b |
| `tipo_de_medida` | enum | `Directa` / `Semidirecta` / `Indirecta` (NO confundir con `tipo_servicio`) |
| `tipo_de_mercado` | string | Regulado / No regulado |
| `kwh_mes` | number | Consumo mensual estimado en kWh |
| `ciudad` | string | Ciudad de la frontera |
| `departamento` | string | Departamento |

### 1.3 Estado del pipeline

| Campo | Tipo | Descripción |
|---|---|---|
| `fase_actual` | enum | `Visita previa`, `Asignación de equipos`, `Activar - Instalar`, `Gestión de paz y salvo`, `On Hold` |
| `fecha_inst_exitosa` | date \| null | Fecha de instalación exitosa (si ya ocurrió) |
| `fecha_programada` | date \| null | Próxima fecha programada en el pipeline |

### 1.4 Costos y priorización

| Campo | Tipo | Descripción |
|---|---|---|
| `costo_opex_estimado` | number | Costo OPEX total estimado del ciclo de activación |
| `cac_kwh` | number | Costo de adquisición de cliente por kWh |
| `costo_opex_sales` | number | Costo OPEX modelo Sales |
| `payback_sales` | number | Meses de payback bajo modelo Sales |
| `delta_opex` | number | Diferencia entre OPEX estimado y referencial |
| `semaforo_delta` | enum | Indicador de criticidad del delta |
| `banda` | enum | 🟢 `INSTALAR` / 🟡 `INSTALAR - MENOS PRIORITARIO` / 🔴 `DESPRIORIZAR` / ⚪ `SIN PAYBACK` |

### 1.5 Costos detallados (para WF-01b)

| Campo | Tipo | Descripción |
|---|---|---|
| `costo_est_visita_previa` | number | Costo estimado de VIPES |
| `costo_est_instalacion_ajustado` | number | Costo estimado de INST |
| `costo_est_legalizacion` | number | Costo estimado de LEGA |
| `costo_total_estimado_visitas` | number | Suma de los anteriores (sanity check) |

### 1.6 Aging

| Campo | Tipo | Descripción |
|---|---|---|
| `fecha_firma_del_contrato` | date | Fecha de firma del contrato |
| `aging_neto_dias` | number | Días desde firma hasta hoy (descontando On Hold) |

### 1.7 Mapeo a `tipo_servicio` canónico

| `fase_actual` | → `tipo_servicio` |
|---|---|
| `Visita previa` | `VIPES` |
| `Asignación de equipos` | (se ignora — es tránsito) |
| `Activar - Instalar` | `INST` |
| `Gestión de paz y salvo` | `LEGA` |
| `On Hold` | (se ignora — bandera de pausa) |

`NORM` no surge directamente del backlog activo; se modelará como servicio derivado.

---

## Card 19440 — Histórico de visitas (últimos 12 meses)

**URL:** `https://bia.metabaseapp.com/question/19440` (validar)
**Propósito:** Histórico de visitas reales ejecutadas con contratista asignado, zona implícita por OR, y tipo de servicio. Fuente para construir la matriz `(zona, tipo_servicio) → contratista_id` que usa WF-01b.
**Filtro temporal:** Columna `fecha Visita` en últimos 12 meses (año pasado y este año).
**Tamaño:** ~27.4 MB en export JSON al 2026-04-27 (cercano al límite de 32 MB).
**Pendiente:** Documentar el listado completo de campos. Procesamiento del archivo está pendiente por tamaño.

### Campos esperados (a confirmar al procesar)

- `fecha_visita` (filtro temporal)
- `contratista` o `contratista_id` (clave para la matriz)
- `operador_de_red` (para derivar zona)
- `tipo_de_servicio` o equivalente (VIPES / INST / NORM / LEGA)
- `codigo_bia` o `contract_id` (para correlacionar con backlog)
- Resultado / estado de la visita
- Costo real (si está disponible)

### Estrategia para construir la matriz

```sql
-- Pseudo-SQL
SELECT
  CASE
    WHEN operador_de_red = 'ENEL CUNDINAMARCA' THEN 'centro'
    WHEN operador_de_red IN ('AFINIA CARIBE_MAR', 'AIRE CARIBE_SOL') THEN 'costa'
    ELSE 'interior'
  END AS zona,
  tipo_servicio,
  contratista_id,
  COUNT(*) AS n_visitas
FROM card_19440_histórico
GROUP BY 1, 2, 3
ORDER BY zona, tipo_servicio, n_visitas DESC;
```

Por cada `(zona, tipo_servicio)`, el `contratista_id` con más visitas es el default.

---

## Card 66793 — Costos asociados a OPEX (referencia, ya documentada)

Usada por WF-02 (monitor horario). No es input de WF-01b. Documentada en el design doc principal sección 5 y en `metabase_cards_n8n_documentation.md`.
