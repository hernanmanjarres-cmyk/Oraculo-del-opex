#!/usr/bin/env python3
"""
Genera dashboard/data.json desde Metabase.

Uso:
  export METABASE_API_KEY="..."
  python3 dashboard/generate_data.py

Lo que hace:
1. Consulta la card 71645 (Seguimiento_opex_act) → ejecutado por servicio.
2. Consulta SQL conteo de visitas exitosas INST/NORM por OR (descargos/acompañamientos).
3. Consulta SQL forecast con cascada L1/L2/L3 (las OTs abiertas con su forecast).
4. Escribe dashboard/data.json.

Pensado para ejecutarse 7am Mon-Vie (cron) o vía WF-G de n8n.
"""
import json
import os
import sys
import datetime as dt
import urllib.request
import urllib.error
from pathlib import Path

METABASE_URL = "https://bia.metabaseapp.com"
DB_GOLD = 2344
CARD_EJECUTADO = 71645
ROOT = Path(__file__).parent
OUT_JSON = ROOT / "data.json"
OUT_HTML = ROOT / "index.html"

CICLO_ACTIVACION = ['VIPE', 'INST', 'NORM', 'LEGA', 'PREV', 'REQA', 'SUCA', 'VEXT']

TARIFAS_DESCARGO = {
    "ENEL CUNDINAMARCA": 6_000_000,
    "CODENSA": 6_000_000,
    "EPM ANTIOQUIA": 3_000_000,
    "CELSIA VALLE": 3_000_000,
    "CELSIA TOLIMA": 3_000_000,
    "ESSA SANTANDER": 1_000_000,
}
TARIFA_ACOMP = 360_000


def _api(path, body=None, headers=None):
    api_key = os.environ.get("METABASE_API_KEY")
    if not api_key:
        sys.exit("ERROR: define METABASE_API_KEY en el entorno")
    hdrs = {"x-api-key": api_key, "Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(METABASE_URL + path, data=data, headers=hdrs, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} en {path}: {e.read().decode()[:300]}")


def run_card(card_id):
    return _api(f"/api/card/{card_id}/query")


def run_sql(database_id, sql):
    body = {"database": database_id, "type": "native", "native": {"query": sql}}
    return _api("/api/dataset", body)


def rows_from(resp):
    cols = [c["name"] for c in resp.get("data", {}).get("cols", [])]
    rows = resp.get("data", {}).get("rows", [])
    return [dict(zip(cols, r)) for r in rows]


SERVICE_NAME_TO_ID = {
    "Instalación": "INST",
    "Normalización de medida": "NORM",
    "Visita previa": "VIPE",
    "Verificación externa": "VEXT",
    "Legalización": "LEGA",
    "Visita prevención": "PREV",
    "Visita pre-venta": "PREV",
    "Revisión por QA": "REQA",
    "Suspensión carro canasta": "SUCA",
}


# ── Construcción del JSON ────────────────────────────────────────────────
def build_ejecutado_by_month():
    """Toma la card 71645 y devuelve { anio_mes: [{servicio, service_type_id, monto}, ...] }."""
    resp = run_card(CARD_EJECUTADO)
    rows = rows_from(resp)
    out = {}
    for r in rows:
        svc_name = r.get("service_name")
        am = r.get("anio_mes")
        if not am or svc_name not in SERVICE_NAME_TO_ID:
            continue
        out.setdefault(am, []).append({
            "servicio": svc_name,
            "service_type_id": SERVICE_NAME_TO_ID[svc_name],
            "monto": int(r.get("Sum of costo_total_ot ($)") or 0),
        })
    return out


def build_conteos_ejecutadas():
    """Conteo de visitas exitosas (CLOSURE_SUCCESSFUL) por OR + service_type."""
    sql = f"""
SELECT COALESCE(h.operador_de_red, 'Sin OR') AS operador_de_red,
       v.service_type_id,
       COUNT(*) AS n_exitosas
FROM operations.visitas_general v
LEFT JOIN operations.hubspot_general h ON h.codigo_bia = v.internal_bia_code
WHERE v.fecha_visita >= date_trunc('month', CURRENT_DATE)
  AND v.fecha_visita < date_trunc('month', CURRENT_DATE) + INTERVAL '1 month'
  AND v.service_type_id IN ('VIPE','INST','NORM','LEGA','PREV','REQA','SUCA','VEXT')
  AND v.electrician_status_id = 'CLOSURE_SUCCESSFUL'
  -- Cuenta TODAS las INST/NORM exitosas (BIA o externo).
  -- El descargo se paga al OR independiente del contratista; el acompañamiento es costo interno.
GROUP BY 1, 2
""".strip()
    rows = rows_from(run_sql(DB_GOLD, sql))
    out = {}
    for r in rows:
        out.setdefault(r["operador_de_red"], {})[r["service_type_id"]] = int(r["n_exitosas"])
    return out


def build_ots_abiertas():
    """OTs abiertas (no cerradas/canceladas) con forecast P80+P50+P50+AVG, cascada L1/L2/L3."""
    sql = """
WITH otas_abiertas AS (
  SELECT v.id::text AS codigo_ot, v.title AS ot_title, v.service_name,
    v.internal_bia_code AS codigo_bia,
    v.service_type_id, v.electrician_status_id, h.operador_de_red, h.tipo_de_medida, v.contratista,
    v.fecha_visita::date AS fecha_programada,
    to_char(v.fecha_visita, 'YYYY-MM') AS mes_id,
    (v.contratista = 'BIA') AS is_bia
  FROM operations.visitas_general v
  LEFT JOIN operations.hubspot_general h ON h.codigo_bia = v.internal_bia_code
  WHERE v.fecha_visita >= date_trunc('month', CURRENT_DATE)
    AND v.fecha_visita < '2027-01-01'
    AND v.service_type_id IN ('VIPE','INST','NORM','LEGA','PREV','REQA','SUCA','VEXT')
    AND (v.electrician_status_id IS NULL
         OR v.electrician_status_id NOT IN ('CLOSURE_SUCCESSFUL','CLOSURE_FAILED','CLOSURE_CANCELED'))
),
base_hist AS (
  SELECT h.operador_de_red, v.service_type_id, h.tipo_de_medida,
    oc.service_cost, oc.material_cost, oc.other_cost, oc.transport_cost
  FROM operations.visitas_general v
  JOIN operations.opex_costs_general oc ON oc.visit_id::text = v.id::text
  LEFT JOIN operations.hubspot_general h ON h.codigo_bia = v.internal_bia_code
  WHERE v.fecha_visita >= (date_trunc('month', CURRENT_DATE) - INTERVAL '12 months')
    AND v.fecha_visita < date_trunc('month', CURRENT_DATE)
    AND v.service_type_id IN ('VIPE','INST','NORM','LEGA','PREV','REQA','SUCA','VEXT')
    AND v.electrician_status_id = 'CLOSURE_SUCCESSFUL'
    AND oc.service_cost > 0 AND (oc.is_bia=false OR oc.is_bia IS NULL)
    AND COALESCE(oc.status,'accepted')='accepted'
),
hist_l1 AS (
  SELECT operador_de_red, service_type_id,
    CASE WHEN service_type_id IN ('INST','NORM') THEN tipo_de_medida ELSE 'ALL' END AS tipo_medida_key,
    PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY service_cost) AS p80_servicio,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NULLIF(material_cost,0)) AS p50_materiales,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NULLIF(other_cost,0)) AS p50_adicionales,
    AVG(transport_cost) AS avg_transporte
  FROM base_hist GROUP BY 1,2,3
),
hist_l2 AS (
  SELECT operador_de_red, service_type_id,
    PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY service_cost) AS p80_servicio,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NULLIF(material_cost,0)) AS p50_materiales,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NULLIF(other_cost,0)) AS p50_adicionales,
    AVG(transport_cost) AS avg_transporte
  FROM base_hist GROUP BY 1,2
),
hist_l3 AS (
  SELECT service_type_id,
    PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY service_cost) AS p80_servicio,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NULLIF(material_cost,0)) AS p50_materiales,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NULLIF(other_cost,0)) AS p50_adicionales,
    AVG(transport_cost) AS avg_transporte
  FROM base_hist GROUP BY 1
)
SELECT a.codigo_ot, a.ot_title, a.service_name, a.codigo_bia, a.service_type_id, a.electrician_status_id,
  a.operador_de_red, a.tipo_de_medida, a.contratista, a.fecha_programada::text AS fecha_programada,
  a.mes_id, a.is_bia,
  CASE WHEN a.is_bia THEN 0 ELSE ROUND(COALESCE(l1.p80_servicio, l2.p80_servicio, l3.p80_servicio, 0)) END AS servicio,
  CASE WHEN a.service_type_id IN ('INST','NORM') THEN ROUND(COALESCE(l1.p50_materiales, l2.p50_materiales, l3.p50_materiales, 0)) ELSE 0 END AS materiales,
  CASE WHEN a.service_type_id IN ('INST','NORM') THEN ROUND(COALESCE(l1.p50_adicionales, l2.p50_adicionales, l3.p50_adicionales, 0)) ELSE 0 END AS adicionales,
  ROUND(COALESCE(l1.avg_transporte, l2.avg_transporte, l3.avg_transporte, 0)) AS transporte,
  ROUND(
    (CASE WHEN a.is_bia THEN 0 ELSE COALESCE(l1.p80_servicio, l2.p80_servicio, l3.p80_servicio, 0) END) +
    (CASE WHEN a.service_type_id IN ('INST','NORM') THEN COALESCE(l1.p50_materiales, l2.p50_materiales, l3.p50_materiales, 0) ELSE 0 END) +
    (CASE WHEN a.service_type_id IN ('INST','NORM') THEN COALESCE(l1.p50_adicionales, l2.p50_adicionales, l3.p50_adicionales, 0) ELSE 0 END) +
    COALESCE(l1.avg_transporte, l2.avg_transporte, l3.avg_transporte, 0)
  ) AS total_ot
FROM otas_abiertas a
LEFT JOIN hist_l1 l1 ON l1.operador_de_red=a.operador_de_red AND l1.service_type_id=a.service_type_id
  AND l1.tipo_medida_key=(CASE WHEN a.service_type_id IN ('INST','NORM') THEN a.tipo_de_medida ELSE 'ALL' END)
LEFT JOIN hist_l2 l2 ON l2.operador_de_red=a.operador_de_red AND l2.service_type_id=a.service_type_id
LEFT JOIN hist_l3 l3 ON l3.service_type_id=a.service_type_id
ORDER BY total_ot DESC NULLS LAST, a.fecha_programada
""".strip()
    return rows_from(run_sql(DB_GOLD, sql))


def build_ots_ejecutadas():
    """OTs exitosas del mes con costo real desde opex_costs_general."""
    sql = """
SELECT v.id::text AS codigo_ot,
       v.title AS ot_title,
       v.service_name,
       v.internal_bia_code AS codigo_bia,
       v.service_type_id,
       v.electrician_status_id,
       h.operador_de_red,
       h.tipo_de_medida,
       v.contratista,
       v.fecha_visita::text AS fecha_visita,
       to_char(v.fecha_visita, 'YYYY-MM') AS mes_id,
       (v.contratista = 'BIA') AS is_bia,
       ROUND(SUM(oc.service_cost + oc.material_cost + oc.transport_cost + oc.other_cost)) AS costo_real
FROM operations.visitas_general v
LEFT JOIN operations.opex_costs_general oc ON oc.visit_id::text = v.id::text
LEFT JOIN operations.hubspot_general h ON h.codigo_bia = v.internal_bia_code
WHERE v.fecha_visita >= date_trunc('month', CURRENT_DATE)
  AND v.fecha_visita < date_trunc('month', CURRENT_DATE) + INTERVAL '1 month'
  AND v.service_type_id IN ('VIPE','INST','NORM','LEGA','PREV','REQA','SUCA','VEXT')
  AND v.electrician_status_id = 'CLOSURE_SUCCESSFUL'
  AND (oc.is_bia = false OR oc.is_bia IS NULL)
  AND COALESCE(oc.status, 'accepted') = 'accepted'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
ORDER BY costo_real DESC NULLS LAST, v.fecha_visita
""".strip()
    return rows_from(run_sql(DB_GOLD, sql))


def main():
    now = dt.datetime.now(dt.timezone(dt.timedelta(hours=-5)))  # Bogotá
    anio_mes = now.strftime("%Y-%m")
    mes_label = {
        "01":"Enero","02":"Febrero","03":"Marzo","04":"Abril","05":"Mayo","06":"Junio",
        "07":"Julio","08":"Agosto","09":"Septiembre","10":"Octubre","11":"Noviembre","12":"Diciembre"
    }[now.strftime("%m")] + " " + now.strftime("%Y")

    print(f"Generando data para {anio_mes}…")
    ejec_by_month = build_ejecutado_by_month()
    conteos = build_conteos_ejecutadas()
    conteos_by_month = { anio_mes: conteos } if conteos else {}
    otas_abiertas = build_ots_abiertas()
    otas_ejecutadas = build_ots_ejecutadas()
    print(f"  ejecutado por mes: {sorted(ejec_by_month.keys())}")
    print(f"  OR con visitas exitosas (mes actual): {len(conteos)}")
    print(f"  OTs abiertas (mes actual + futuros): {len(otas_abiertas)}")
    print(f"  OTs ejecutadas (mes actual): {len(otas_ejecutadas)}")

    payload = {
        "fecha_corte": now.strftime("%Y-%m-%d"),
        "mes_label_actual": mes_label,
        "anio_mes_actual": anio_mes,
        "meta_default": 21_000_000,
        "ejecutado_por_servicio_by_month": ejec_by_month,
        "tarifas_descargo_por_or": TARIFAS_DESCARGO,
        "tarifa_acompanamiento": TARIFA_ACOMP,
        "conteo_inst_norm_ejecutadas_por_or_by_month": conteos_by_month,
        "ots_abiertas": otas_abiertas,
        "ots_ejecutadas": otas_ejecutadas,
        "generated_at": now.isoformat(timespec="seconds"),
        "source": {
            "ejecutado": f"Metabase card {CARD_EJECUTADO}",
            "forecast": "SQL operations.visitas_general + opex_costs_general, hist 12m excluyendo mes actual",
        },
    }

    # 1) Sidecar JSON (útil para inspección o integraciones futuras)
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"✅ Escrito: {OUT_JSON}")

    # 2) Inyectar la data directamente en el HTML (entre los marcadores ▼▼▼ y ▲▲▲)
    if OUT_HTML.exists():
        import re
        html = OUT_HTML.read_text(encoding="utf-8")
        new_block = (
            '<!-- ▼▼▼ DATA EMBEBIDA — reemplazada por generate_data.py ▼▼▼ -->\n'
            '<script id="dashboard-data" type="application/json">\n'
            + json.dumps(payload, ensure_ascii=False, indent=2)
            + '\n</script>\n'
            '<!-- ▲▲▲ FIN DATA EMBEBIDA ▲▲▲ -->'
        )
        pattern = re.compile(
            r'<!-- ▼▼▼ DATA EMBEBIDA.*?▲▲▲ FIN DATA EMBEBIDA ▲▲▲ -->',
            re.DOTALL
        )
        if pattern.search(html):
            html = pattern.sub(lambda _: new_block, html)
            OUT_HTML.write_text(html, encoding="utf-8")
            print(f"✅ HTML actualizado: {OUT_HTML}")
        else:
            print("⚠️ No encontré los marcadores en index.html — datos solo en data.json")


if __name__ == "__main__":
    main()
