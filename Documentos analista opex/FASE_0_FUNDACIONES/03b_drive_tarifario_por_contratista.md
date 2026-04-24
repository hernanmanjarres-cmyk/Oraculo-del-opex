# Tarifarios por Contratista — Carpeta Google Drive

## Estructura de la carpeta Drive

Crea una carpeta en Google Drive llamada **"BIA OPEX - Tarifarios 2026"**.

Dentro de esa carpeta, crea **un Google Sheets por contratista**:
```
BIA OPEX - Tarifarios 2026/
├── CIRELECTRICOS.gsheet
├── GMAS.gsheet
├── SGE.gsheet
├── POWER GRID.gsheet
├── DR TELEMEDIDA.gsheet
├── JEM.gsheet
├── C3.gsheet
├── ISELEC.gsheet
├── DISELEC.gsheet
├── GATRIA.gsheet
├── ISEMEC.gsheet
├── S&SE.gsheet
├── REHOBOT.gsheet
├── MONTAJES MTE.gsheet
├── ELECPROYECTOS.gsheet
├── MCR ELECTRICA.gsheet
├── ... (un archivo por cada contratista)
```

**Regla importante:** El nombre del archivo (sin extensión) se usa como `contratista_id` en Supabase. Usar el mismo nombre que aparece en el Excel original.

---

## Formato de cada archivo

Cada Google Sheets debe tener **una pestaña llamada exactamente `Tarifario`** con estas columnas:

| item_codigo | actividad | ENEL_AIRE_EMCALI_AFINIA | CELSIA_ELECTROHUILA_ESSA | OTROS_OR |
|-------------|-----------|------------------------|-------------------------|----------|
| 1 | Apertura de portacircuito (unidad) | 90000 | 90000 | 90000 |
| 2 | Atención básica emergencia (disponibilidad en sitio) | 250000 | 275000 | 300000 |
| 3 | Hora muerta / disponibilidad adicional | 50000 | 55000 | 60000 |
| ... | ... | ... | ... | ... |

**Columnas requeridas (nombres exactos):**
- `item_codigo` — número entero (1–80)
- `actividad` — descripción del ítem
- `ENEL_AIRE_EMCALI_AFINIA` — tarifa en COP para ORs: ENEL, AIRE, EMCALI, AFINIA
- `CELSIA_ELECTROHUILA_ESSA` — tarifa en COP para ORs: CELSIA VALLE, CELSIA TOLIMA, ELECTROHUILA, ESSA
- `OTROS_OR` — tarifa en COP para todos los demás ORs

**Notas sobre los valores:**
- Sin puntos ni comas de miles — solo el número: `90000` no `90.000`
- Celdas vacías o en 0 se omiten del sync
- Si un contratista no opera en cierto OR, dejar la celda vacía o en 0

---

## Incrementos por jornada (Anexo N°1 — global)

Los incrementos son automáticos y aplican sobre la tarifa base al momento de auditar:

| Jornada | Incremento |
|---------|-----------|
| Nocturna | +20% |
| Festiva diurna | +25% |
| Festiva nocturna | +35% |

No es necesario agregarlos en el archivo — el sistema los aplica automáticamente según la jornada de la OT.

---

## Mapeo OR → Grupo tarifario

El sistema ya tiene configurado el mapeo de cada OR a su grupo. Referencia:

| OR | Grupo tarifario |
|----|----------------|
| ENEL CUNDINAMARCA | ENEL_AIRE_EMCALI_AFINIA |
| AIRE CARIBE_SOL | ENEL_AIRE_EMCALI_AFINIA |
| AFINIA CARIBE_MAR | ENEL_AIRE_EMCALI_AFINIA |
| EMCALI CALI | ENEL_AIRE_EMCALI_AFINIA |
| CELSIA_VALLE VALLE | CELSIA_ELECTROHUILA_ESSA |
| CELSIA_TOLIMA TOLIMA | CELSIA_ELECTROHUILA_ESSA |
| ELECTROHUILA HUILA | CELSIA_ELECTROHUILA_ESSA |
| ESSA SANTANDER | CELSIA_ELECTROHUILA_ESSA |
| CEDENAR NARIÑO | OTROS_OR |
| CENS NORTE_SANTANDER | OTROS_OR |
| CHEC CALDAS | OTROS_OR |
| EBSA BOYACA | OTROS_OR |
| EPM ANTIOQUIA | OTROS_OR |
| (todos los demás) | OTROS_OR |

Si aparece un OR nuevo que no está en la lista, agrégalo en Supabase:
```sql
INSERT INTO opex_or_mapping (or_nombre, or_grupo, zona)
VALUES ('NUEVO OR NOMBRE', 'OTROS_OR', 'Interior');
```

---

## Agregar o quitar un contratista

**Agregar:** Crear un nuevo Google Sheets en la carpeta con el nombre del contratista y la pestaña `Tarifario`. El próximo sync (06:00) lo detecta automáticamente.

**Quitar:** Mover el archivo fuera de la carpeta Drive. En Supabase, las tarifas existentes quedan con `activa = true` hasta que expire `effective_to`. Si querés desactivar inmediatamente:
```sql
UPDATE opex_tarifario SET activa = false WHERE contratista_id = 'NOMBRE_CONTRATISTA';
```

---

## Configurar el workflow (paso único)

1. Obtén el ID de la carpeta Drive:
   - Abre la carpeta en Google Drive
   - La URL será: `drive.google.com/drive/folders/XXXXX`
   - Copia el `XXXXX` — ese es el Folder ID

2. En n8n, abre el workflow **WF-01 | OPEX Sync Tarifarios Drive + Budget Sheets**

3. En el nodo **"Drive: Listar Tarifarios"**, reemplaza `TARIFARIOS_DRIVE_FOLDER_ID` con el ID real

4. Asegúrate de que el Google Sheets credential tiene permiso de Drive (scope `drive.readonly`)

---

## Primer cargue: convertir el Excel actual

El Excel `Comparador de costos tarifario - contratistas.xlsx` ya tiene toda la data.
Para crear los archivos individuales de manera rápida:

1. Abre el Excel en Google Sheets (subir al Drive)
2. Para cada contratista, copia sus 3 columnas (ENEL, CELSIA, OTROS) junto con item_codigo y actividad
3. Pégalas en un nuevo Sheets con el nombre del contratista, pestaña `Tarifario`
4. Asegúrate de que los encabezados coincidan exactamente con los nombres de columna requeridos
