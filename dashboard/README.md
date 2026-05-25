# Dashboard OPEX Activación

Dashboard HTML estático para seguimiento del OPEX del ciclo de activación.
Cualquiera con el link puede consultarlo. No necesita login.

## Qué hace

- KPIs en tiempo real: ejecutado, descargos+acompañamientos, forecast, total proyectado.
- Input editable de **presupuesto** del mes (se guarda en localStorage del navegador).
- Barra de progreso vs meta con código de colores (verde / amarillo / rojo).
- Ejecutado por servicio (Instalación, Normalización, etc.) desde la card 71645.
- Tabla de **OTs abiertas** con forecast por rubro (servicio + materiales + adicionales + transporte).
- Columna editable de **gasto adicional** por OT — útil para registrar costos no previstos no presentes en base de datos. Se guarda en el navegador.
- Total se recalcula al cambiar cualquier input.

## Estructura

```
dashboard/
├── index.html         # El dashboard (estático, autosuficiente)
├── data.json          # Datos del mes (regenerado por el script)
├── generate_data.py   # Refresca data.json desde Metabase
└── README.md          # Este archivo
```

## Cómo ver el dashboard localmente

```bash
cd dashboard
python3 -m http.server 8080
# Abre http://localhost:8080
```

(No funciona abriendo `index.html` directo en el browser porque `fetch('data.json')` requiere un servidor HTTP por CORS local.)

## Cómo refrescar los datos

```bash
export METABASE_API_KEY="tu_api_key_de_metabase"
python3 dashboard/generate_data.py
```

Escribe `dashboard/data.json` con datos frescos:
- Ejecutado por servicio → card Metabase 71645
- Conteos de visitas exitosas → SQL gold layer
- OTs abiertas con forecast → SQL con cascada L1/L2/L3 sobre histórico de 12 meses

## Despliegue público (GitHub Pages)

1. En GitHub: Settings → Pages → Source: `feature/dashboard-opex-activacion` branch, folder `/dashboard`
2. URL: `https://hernanmanjarres-cmyk.github.io/Oraculo-del-opex/`
3. Para refrescar automáticamente cada día:
   - Agregar GitHub Action que corra `generate_data.py` cada lunes-viernes 7am Bogotá
   - Commit/push del `data.json` actualizado
4. El dashboard cargará siempre el `data.json` más reciente

## Integración con WF-G (envío de screenshot 7am Lun-Vie)

Plan (TODO):

1. **Refrescar data.json antes del envío**:
   - Nodo Code en WF-G que llame a `generate_data.py` (vía GitHub Action o lambda)
   - Alternativa: el propio WF-G consulta la card y SQL, genera JSON, hace commit por GitHub API

2. **Tomar screenshot del dashboard**:
   - Servicios como `htmlcsstoimage.com`, `urlbox.io`, `screenshotone.com`
   - Configurar nodo HTTP en WF-G que llame al servicio con URL del dashboard → recibe URL del PNG

3. **Postear en Slack**:
   - Nodo Slack que sube el PNG con texto breve:
     > "📊 OPEX Activación al <fecha> | Ejecutado <X>, Proyectado <Y> | Meta <Z> | <Status emoji>"
   - El mensaje principal con el screenshot, los detalles textuales en hilo (manteniendo el patrón actual)

4. **Cron**: ya existe (lun-vie 7am Bogotá).

Esto requiere:
- API key de un servicio de screenshot (~$5-20/mes)
- URL pública del dashboard (GitHub Pages)
- Token de GitHub para hacer commit del data.json (si lo hacemos por API)

Sugiero implementarlo en un siguiente PR. Por ahora el dashboard ya es funcional manualmente.
