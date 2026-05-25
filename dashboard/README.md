# Dashboard OPEX Activación

Dashboard HTML autónomo para seguimiento del OPEX del ciclo de activación.
**No necesita servidor, ni login, ni nada técnico** — abrís el archivo y ya.

## Paso 1 — Ver el dashboard AHORA (más fácil imposible)

1. Abrí Finder.
2. Andá a la carpeta `dashboard/`.
3. **Doble click en `index.html`**.
4. Se abre en tu navegador (Safari, Chrome, lo que tengas por defecto).
5. ✅ Ya está. Vas a ver los datos actuales del mes (al 22 de mayo de 2026).

**Por qué funciona ahora**: la data está embebida adentro del propio `index.html`. No hay fetch, no hay servidor, no hay configuración. Cuando regeneres los datos (paso 3) el HTML se actualiza solo.

## Paso 2 — Compartirlo con otras personas

### Opción A (rápida): mandá el archivo
- `index.html` es **un solo archivo autocontenido**. Mandalo por Slack/email a quien quieras.
- La persona hace doble click → ve el mismo dashboard.
- ⚠️ Verá los datos que estaban embebidos al momento de mandárselo (no actualizados en tiempo real).

### Opción B (pública, siempre fresca): GitHub Pages
1. En github.com, andá al repo `Oraculo-del-opex` → Settings → Pages.
2. Source: **Deploy from a branch**.
3. Branch: `feature/dashboard-opex-activacion` (o `main` cuando lo fusiones).
4. Folder: `/dashboard`. Click Save.
5. Esperá 1-2 min. Aparece la URL: `https://hernanmanjarres-cmyk.github.io/Oraculo-del-opex/`.
6. Cualquiera con esa URL lo puede ver desde el celu o la web.

## Paso 3 — Refrescar datos (cuando querés ver cifras actuales)

Esto regenera tanto `data.json` como la data embebida en `index.html`.

```bash
# 1. Conseguí una API key de Metabase (en bia.metabaseapp.com, perfil → personal API tokens).
export METABASE_API_KEY="metabase_..."

# 2. Corré el generador.
cd "/Users/hernanmanjarres/Documents/Automatizaciones/Analista Opex"
python3 dashboard/generate_data.py
```

Sale algo así:
```
Generando data para 2026-05…
  ejecutado por servicio: 8 categorías
  OR con visitas exitosas: 4
  OTs abiertas: 5
✅ Escrito: data.json
✅ HTML actualizado: index.html
```

Volvé a abrir `index.html` (o recargá si estaba abierto) y vas a ver los nuevos números.

## Paso 4 — Cómo usar el dashboard

### KPIs arriba
- **Ejecutado contratistas**: lo que ya se gastó en visitas exitosas (card Metabase 71645).
- **Descargos + Acompañamientos**: lo ya pagado por descargos a OR y los $360k por INST/NORM ejecutadas.
- **Forecast pendiente**: proyección de las OTs todavía abiertas + cualquier "gasto adicional" que vos cargues.
- **Total proyectado**: la suma — comparada con la meta. Verde si vas bajo, amarillo si te acercás, rojo si te pasás.

### Presupuesto editable
- Cambiá el valor de la meta efectiva → todo se recalcula al instante.
- Se guarda en tu navegador (no en archivo). Si alguien más abre el HTML verá el default ($21M).

### Gastos adicionales por OT
- En la tabla de "OTs abiertas", la columna **Gasto adicional** es editable.
- Cargá ahí costos que sabés que van a ocurrir pero no están en la base (ej: imprevistos, materiales extra).
- Se suma automáticamente al forecast.
- Se guarda en localStorage del navegador.

## Paso 5 (futuro) — Bot envía screenshot 7am Lun-Vie

Plan documentado en el README pero no implementado todavía:
1. GitHub Action que corre `generate_data.py` cada lun-vie 7am Bogotá.
2. Servicio externo (htmlcsstoimage.com, urlbox.io) que toma screenshot del HTML.
3. Nodo HTTP en WF-G que llama al servicio + sube la imagen a Slack con un texto breve.

Cuando confirmes que el dashboard funciona, lo armamos en otro PR.

---

## Estructura de archivos

```
dashboard/
├── index.html        # El dashboard. Data embebida adentro. Doble click → funciona.
├── data.json         # Mismo contenido en JSON (sidecar, para inspección/futuras integraciones).
├── generate_data.py  # Regenera el HTML y JSON desde Metabase.
└── README.md         # Este archivo.
```

## Preguntas frecuentes

**P: ¿Por qué no se actualiza solo?**
R: Porque la data está embebida. Corré `python3 dashboard/generate_data.py` cuando quieras refrescar. (Con GitHub Pages + GitHub Action eso se automatiza.)

**P: ¿Si edito un gasto adicional y otra persona abre el mismo HTML, ¿lo ve?**
R: No. Eso vive en el localStorage del navegador de cada uno. Es feature, no bug — cada uno juega con sus "qué pasaría si".

**P: ¿Y si quiero compartir los adicionales que cargué?**
R: Por ahora hay que coordinarlo manual. Para hacerlo persistente habría que agregar Supabase o algo similar — siguiente iteración.

**P: ¿Funciona en celular?**
R: Sí, es responsive. Probalo desde GitHub Pages en el celu.
