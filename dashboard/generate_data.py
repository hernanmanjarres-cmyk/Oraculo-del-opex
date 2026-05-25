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
OUT_FILE = ROOT / "data.json"

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


# ── Construcción del JSON ────────────────────────────────────────────────
def build_ejecutado_por_servicio(anio_mes):
    """Filtra la card 71645 al mes actual."""
    mapping = {
        "Instalación": "INST",
        "Normalización de medida": "NORM",
        "Visita previa": "VIPE",
        "Verificación externa": "VEXT",
        "Legalización": "LEGA",
        "Visita prevención": "PREV",
        "Revisión por QA": "REQA",
        "Suspensión carro canasta": "SUCA",
    }
    resp = run_card(CARD_EJECUTADO)
    rows = rows_from(resp)
    acc = {svc: 0 for svc in mapping}
    for r in rows:
        svc_name = r.get("service_name")
        if r.get("anio_mes") == anio_mes and svc_name in acc:
            acc[svc_name] += int(r.get("Sum of costo_total_ot ($)") or 0)
    return [
        {"servicio": k, "service_type_id": mapping[k], "monto": v}
        for k, v in acc.items()
    ]


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
  AND v.contratista != 'BIA'
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
  SELECT v.id::text AS codigo_ot, v.internal_bia_code AS codigo_bia,
    v.service_type_id, v.electrician_status_id, h.operador_de_red, h.tipo_de_medida, v.contratista,
    v.fecha_visita::date AS fecha_programada, (v.contratista = 'BIA') AS is_bia
  FROM operations.visitas_general v
  LEFT JOIN operations.hubspot_general h ON h.codigo_bia = v.internal_bia_code
  WHERE v.fecha_visita >= date_trunc('month', CURRENT_DATE)
    AND v.fecha_visita < date_trunc('month', CURRENT_DATE) + INTERVAL '1 month'
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
SELECT a.codigo_ot, a.codigo_bia, a.service_type_id, a.electrician_status_id,
  a.operador_de_red, a.tipo_de_medida, a.contratista, a.fecha_programada::text AS fecha_programada, a.is_bia,
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


def main():
    now = dt.datetime.now(dt.timezone(dt.timedelta(hours=-5)))  # Bogotá
    anio_mes = now.strftime("%Y-%m")
    mes_label = {
        "01":"Enero","02":"Febrero","03":"Marzo","04":"Abril","05":"Mayo","06":"Junio",
        "07":"Julio","08":"Agosto","09":"Septiembre","10":"Octubre","11":"Noviembre","12":"Diciembre"
    }[now.strftime("%m")] + " " + now.strftime("%Y")

    print(f"Generando data para {anio_mes}…")
    ejecutado = build_ejecutado_por_servicio(anio_mes)
    conteos = build_conteos_ejecutadas()
    otas = build_ots_abiertas()
    print(f"  ejecutado por servicio: {len(ejecutado)} categorías")
    print(f"  OR con visitas exitosas: {len(conteos)}")
    print(f"  OTs abiertas: {len(otas)}")

    payload = {
        "fecha_corte": now.strftime("%Y-%m-%d"),
        "mes_label": mes_label,
        "anio_mes": anio_mes,
        "meta_default": 21_000_000,
        "ejecutado_por_servicio": ejecutado,
        "tarifas_descargo_por_or": TARIFAS_DESCARGO,
        "tarifa_acompanamiento": TARIFA_ACOMP,
        "conteo_inst_norm_ejecutadas_por_or": conteos,
        "ots_abiertas": otas,
        "generated_at": now.isoformat(timespec="seconds"),
        "source": {
            "ejecutado": f"Metabase card {CARD_EJECUTADO}",
            "forecast": "SQL operations.visitas_general + opex_costs_general, hist 12m excluyendo mes actual",
        },
    }

    OUT_FILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"✅ Escrito: {OUT_FILE}")


if __name__ == "__main__":
    main()
