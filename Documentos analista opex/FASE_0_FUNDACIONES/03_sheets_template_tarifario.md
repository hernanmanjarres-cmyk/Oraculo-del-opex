# Template Google Sheets: Tarifario y Budget OPEX

El workflow `wf_01` lee datos desde Google Sheets y los carga a Supabase.  
Los Sheets **deben tener exactamente estas columnas** en la primera fila (fila 1 = encabezados).

---

## Sheet 1: Tarifario de Contratistas

**Nombre de la hoja (pestaña):** `Tarifario`

| Columna (header exacto) | Tipo | Descripción | Ejemplo |
|------------------------|------|-------------|---------|
| `contratista_id` | Texto | Código único del contratista | `CTR-001` |
| `contratista_nombre` | Texto | Nombre del contratista | `Contratista Alfa S.A.S` |
| `tipo_servicio` | Texto | Tipo de servicio | `NORM`, `INST`, `REQA`, `MANT` |
| `zona` | Texto | Zona geográfica (dejar vacío si aplica a todas) | `Bogotá`, `Medellín`, `Costa` |
| `or_codigo` | Texto | Código de OR si la tarifa es específica por OR | `OR-BOG-01` |
| `unidad` | Texto | Unidad de medida | `und`, `hora`, `viaje`, `m` |
| `tarifa` | Número | Tarifa sin formato, sin símbolo de moneda | `430000` |
| `moneda` | Texto | Siempre COP para Colombia | `COP` |
| `tolerancia_pct` | Número | % de tolerancia aceptable (por defecto 3) | `3` |
| `es_tarifa_variable` | Texto | `SI` o `NO` | `NO` |
| `cap_mensual` | Número | Cap mensual en COP (dejar vacío si no aplica) | `5000000` |
| `notas` | Texto | Observaciones, condiciones especiales | `Incluye viáticos zona rural` |
| `effective_from` | Fecha | Fecha desde que rige (formato YYYY-MM-DD) | `2026-01-01` |
| `effective_to` | Fecha | Fecha hasta que rige (vacío = vigente) | *(vacío)* |

### Reglas importantes del Sheet Tarifario

- **Una fila por tarifa.** Si un contratista tiene tarifas distintas por zona, son filas separadas.
- **`effective_from` es obligatorio.** Usa el formato `YYYY-MM-DD` (ej: `2026-01-01`).
- **`effective_to` vacío** significa que la tarifa está vigente actualmente.
- Si actualizas una tarifa, **no borres la fila anterior**. Pon `effective_to` en la fila vieja y crea una fila nueva con la tarifa actualizada.
- La columna `tarifa` debe ser número puro — sin puntos de miles, sin `$`, sin espacios. Ejemplo correcto: `430000`. Incorrecto: `$430.000`.
- Si `zona` está vacío, esa tarifa aplica a todas las zonas (se usa como fallback).

### Ejemplo de filas:

```
contratista_id | contratista_nombre    | tipo_servicio | zona     | unidad | tarifa  | effective_from | effective_to
CTR-001        | Contratista Alfa      | NORM          | Bogotá   | und    | 430000  | 2026-01-01     |
CTR-001        | Contratista Alfa      | NORM          | Medellín | und    | 410000  | 2026-01-01     |
CTR-001        | Contratista Alfa      | INST          |          | hora   | 85000   | 2026-01-01     |
CTR-002        | Contratista Beta      | REQA          | Costa    | viaje  | 650000  | 2025-07-01     | 2025-12-31
CTR-002        | Contratista Beta      | REQA          | Costa    | viaje  | 680000  | 2026-01-01     |
```

---

## Sheet 2: Presupuesto Mensual

**Nombre de la hoja (pestaña):** `Budget`

| Columna (header exacto) | Tipo | Descripción | Ejemplo |
|------------------------|------|-------------|---------|
| `anio` | Número | Año del presupuesto | `2026` |
| `mes` | Número | Mes (1–12) | `4` |
| `zona` | Texto | Zona (vacío = total empresa) | `Bogotá` |
| `contratista_id` | Texto | ID del contratista (vacío = todos los contratistas de esa zona) | `CTR-001` |
| `categoria_contable` | Texto | Categoría o cuenta contable | `OPEX-NORM`, `OPEX-MANT` |
| `tipo_servicio` | Texto | Tipo de servicio (vacío = todos) | `NORM` |
| `monto_budget` | Número | Monto en COP (número puro, sin formato) | `12500000` |
| `moneda` | Texto | `COP` | `COP` |
| `notas` | Texto | Observaciones del presupuesto | `Incluye campaña especial Q2` |
| `effective_from` | Fecha | Fecha de carga del budget | `2026-04-01` |

### Reglas importantes del Sheet Budget

- El presupuesto puede existir a distintos niveles de granularidad: empresa total, por zona, por zona+contratista, por zona+contratista+categoría.
- El agente usa el presupuesto más específico que encuentre para cada análisis.
- Si el presupuesto está en unidades diferentes a COP, especificarlo en la columna `moneda` y convertir manualmente antes de cargar.
- Para cargarlo por primera vez: ingresa todo el presupuesto del año con `effective_from = 2026-01-01`.

### Ejemplo de filas (distintas granularidades):

```
anio | mes | zona     | contratista_id | categoria_contable | monto_budget | effective_from
2026 | 4   |          |                | OPEX-TOTAL         | 150000000    | 2026-04-01
2026 | 4   | Bogotá   |                | OPEX-NORM          | 45000000     | 2026-04-01
2026 | 4   | Bogotá   | CTR-001        | OPEX-NORM          | 18000000     | 2026-04-01
2026 | 4   | Medellín |                | OPEX-MANT          | 22000000     | 2026-04-01
```

---

## Configuración del Google Drive

1. Crea un Google Sheet con **dos pestañas**: `Tarifario` y `Budget`
2. Comparte el Sheet con el email del Service Account de Google Cloud (ver guía `02_n8n_credentials_setup.md`)
3. Copia el **ID del Sheet** desde la URL y pégalo en la variable `OPEX_SHEETS_ID_TARIFARIO` en n8n

> Si prefieres tener un Sheet para el tarifario y otro para el budget, también funciona. Solo deberás configurar `OPEX_SHEETS_ID_BUDGET` como variable separada en n8n.

---

## Validaciones que hace el workflow al importar

El workflow `wf_01` valida los datos del Sheet antes de cargarlos a Supabase:

| Validación | Acción si falla |
|-----------|----------------|
| `tarifa` > 0 | Salta la fila y la reporta en `opex_agent_log` |
| `effective_from` tiene formato de fecha válido | Salta la fila |
| `contratista_id` no está vacío | Salta la fila |
| `tipo_servicio` no está vacío | Salta la fila |
| `monto_budget` >= 0 | Salta la fila |
| Cambio de tarifa > 20% vs versión anterior | Alerta en Slack antes de cargar |

Si hay errores de validación, el workflow genera un mensaje Slack en `#bia-opex-errors` con la lista de filas fallidas para corrección manual.
