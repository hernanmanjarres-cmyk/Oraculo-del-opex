# WF-01b — Budget Teórico desde Pipeline

**Estado:** En diseño (no implementado).
**Fecha de diseño:** 2026-04-27.
**Disparador propuesto:** Cron día 25 23:00 (cierre del backlog del mes siguiente) + ejecución manual on-demand.

---

## 1. Pivote conceptual respecto al diseño original

El diseño original (sec. 8 del documento maestro) asumía que `opex_budget` se llenaba **manualmente** desde un Google Sheet por Finanzas. La rama Budget de WF-01 leía esa hoja y hacía upsert en la tabla.

**Decisión del usuario (2026-04-27):**
> "yo no quiero poner un budget, yo quiero que el agente calcule según las fronteras que tengo cuanto aproximadamente me va costar hacer las instalaciones, apoyándose en data de metabase y tarifarios cargados."

**Implicación:**
- Finanzas **no** interactúa con este agente.
- El "presupuesto" pasa a ser un **Budget Teórico** = costo proyectado del ciclo de activación de las fronteras vigentes en el backlog.
- WF-01b reemplaza la rama Budget de WF-01 (queda desconectada).
- La rama Budget Sheet de WF-01 se considera **deprecada**.

---

## 2. Alcance del Budget Teórico

| Dimensión | Valor |
|---|---|
| **Fuente principal** | Metabase card **65209** (backlog de fronteras) |
| **Tarifa por servicio** | Función Supabase `get_tarifa_vigente()` + tabla `opex_tarifario` |
| **Mapeo histórico** | Metabase card **19440** (histórico de visitas últimos 12 meses) — para derivar `contratista_id` por `zona` × `tipo_servicio` |
| **Ciclo cubierto** | Solo **activación**: VIPES, INST, NORM, LEGA (no incluye otras categorías OPEX como mantenimiento, calibración, etc.) |
| **Bandas incluidas en cálculo** | 🟢 INSTALAR y 🟡 INSTALAR - MENOS PRIORITARIO |
| **Bandas excluidas del cálculo** | 🔴 DESPRIORIZAR y ⚪ SIN PAYBACK (se documentan aparte para análisis pero no entran al budget) |
| **Granularidad de salida** | `mes / anio / zona / contratista_id / categoria_contable / tipo_servicio` |

---

## 3. Taxonomía canónica de `tipo_servicio`

El usuario corrigió explícitamente que `tipo_servicio` **no es** `tipo_de_medida` (esa es la dimensión Directa/Semidirecta/Indirecta). Los valores canónicos son:

| Código | Descripción | Equivalente en pipeline |
|---|---|---|
| `VIPES` | Visita previa | Fase "Visita previa" del backlog |
| `INST` | Instalación | Fase "Activar - Instalar" del backlog |
| `NORM` | Normalización de medida | Servicio derivado (no siempre presente) |
| `LEGA` | Legalización | Fase "Gestión de paz y salvo" del backlog |

`opex_budget.tipo_servicio` debe poblarse con uno de estos cuatro códigos.

---

## 4. Mapeo de zona

El usuario aclaró que **`zona` ≠ `operador_de_red`**. La regla canónica es:

| Zona BIA | Operadores de red incluidos |
|---|---|
| `centro` | ENEL CUNDINAMARCA |
| `costa` | AFINIA CARIBE_MAR, AIRE CARIBE_SOL |
| `interior` | EPM ANTIOQUIA, EMCALI CALI, CENS NORTE_SANTANDER, EBSA BOYACA, EMSA META, ESSA SANTANDER, CHEC CALDAS, CELSIA_TOLIMA TOLIMA, ELECTROHUILA HUILA, EDEQ QUINDIO, CEDENAR NARIÑO (y cualquier OR no listado en `centro` o `costa`) |

Esta lógica se aplica como CASE/Map en el primer Code node después de leer card 65209.

---

## 5. Asignación de contratista

El usuario indicó:
> "la del contratista debemos incluirla de la data historica, normalmente que contratista trabaja en que zona... lo que me pides lo podemos sacar de esa data."

**Estrategia:**
1. Procesar card 19440 (histórico de visitas últimos 12 meses) para construir una **matriz de asignación** `(zona, tipo_servicio) → contratista_id` con la moda (contratista que más veces aparece en esa combinación).
2. Persistir esa matriz en una tabla `opex_zona_contratista_default` (a crear) o en `opex_config` como JSON.
3. WF-01b lee esa matriz y la usa para asignar `contratista_id` a cada fila del backlog.

**Pendiente operativo:**
- Generar la matriz inicial corriendo un análisis one-shot sobre card 19440 (archivo de 27.4 MB que el usuario compartió).
- Definir el WF que la mantiene (¿semanal? ¿al vuelo dentro del WF-01b?).

---

## 6. Pipeline de cálculo (alto nivel)

```
[Cron día 25 23:00]
   │
[HTTP Request → Metabase card 65209] (backlog activo)
   │
[Code: Filtrar bandas INSTALAR + INSTALAR - MENOS PRIORITARIO]
   │
[Code: Mapear operador_de_red → zona (centro/costa/interior)]
   │
[Code: Derivar tipo_servicio canónico desde fase_actual]
   │
[Postgres: SELECT matriz_zona_contratista_default]
   │
[Code: Asignar contratista_id según (zona, tipo_servicio)]
   │
[SplitInBatches por (zona, contratista_id, tipo_servicio)]
   │
[Postgres: SELECT get_tarifa_vigente(contratista_id, item_codigo, or_nombre, fecha, jornada)]
   │
[Code: Calcular monto_budget = SUM(tarifa × cantidad_fronteras)]
   │
[Postgres: UPSERT opex_budget]
   │
[Slack: Notificar resumen a #opex-cierre]
```

---

## 7. Schema target — `opex_budget` (sin cambios)

```sql
CREATE TABLE opex_budget (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anio INTEGER NOT NULL,
  mes INTEGER NOT NULL CHECK (mes BETWEEN 1 AND 12),
  zona TEXT,
  contratista_id TEXT,
  categoria_contable TEXT NOT NULL,
  tipo_servicio TEXT,
  monto_budget NUMERIC(18,2) NOT NULL,
  moneda TEXT NOT NULL DEFAULT 'COP',
  version INTEGER NOT NULL DEFAULT 1,
  effective_from DATE NOT NULL,
  effective_to DATE,
  notas TEXT,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  creado_por TEXT,
  CONSTRAINT chk_budget_positivo CHECK (monto_budget >= 0)
);
```

**Llenado por WF-01b:**
- `categoria_contable`: fijo en `'CICLO_ACTIVACION'` (o equivalente convenido).
- `tipo_servicio`: VIPES / INST / NORM / LEGA.
- `creado_por`: `'WF-01b-budget-teorico'`.
- `version`: incrementar al recorrer ejecuciones nuevas del mismo (anio, mes).
- `notas`: incluir conteo de fronteras y banda promedio.

---

## 8. Pendientes para implementar WF-01b

| # | Tarea | Bloqueante |
|---|---|---|
| 1 | Procesar card 19440 (27.4 MB) para generar matriz `(zona, tipo_servicio) → contratista_id` | Resolver tooling para procesar archivo de >20 MB |
| 2 | Crear tabla `opex_zona_contratista_default` o JSON en `opex_config` | Decidir estrategia de almacenamiento |
| 3 | Mapear `fase_actual` (card 65209) → `tipo_servicio` canónico | Confirmar que las fases del backlog cubren VIPES/INST/NORM/LEGA |
| 4 | Definir `categoria_contable` para Budget Teórico | Coordinar con cuentas de `opex_transactions` |
| 5 | Decidir si `WF-01` mantiene su rama Budget desconectada o se elimina del JSON | Limpieza |
| 6 | Construir y testear WF-01b en n8n cloud | Depende de 1–4 |

---

## 9. Cards de Metabase referenciadas

Ver `02_cards_metabase.md` en este mismo directorio para el diccionario completo de campos de cards 65209 y 19440.
