# Diseño del Analista OPEX Virtual BIA

**Agente financiero-operativo en n8n para forecast, control y detección de desvíos de OPEX**

BIA Energy — Operaciones / Finanzas Operativas
Documento de diseño v1.0 — 23 de abril de 2026

---

## 0. Resumen ejecutivo

El Analista OPEX Virtual es un agente que monitorea la ejecución del gasto operativo de BIA Energy, compara contra tarifario/presupuesto/baseline histórico, proyecta el cierre mensual, detecta anomalías y fuga de margen, y dispara comunicaciones proactivas (tickets, correos, Slack) cuando aparece un desvío accionable. No reemplaza al analista humano: le entrega el día abierto con los casos priorizados, el reporte mensual casi cerrado y una lista corta de decisiones.

Dado que todos los datos de costos viven en Metabase/DB, el agente puede arrancar ambicioso desde el día 1: sin OCR, sin ERP externo, sin parsing de PDFs. El trabajo real está en modelar bien los umbrales, construir forecast confiable y redactar narrativa financiera que el comité entienda en 30 segundos.

La recomendación ejecutiva es atacar los tres focos en paralelo en un MVP de 4 semanas: **forecast de cierre mensual + reportería automática + detección de anomalías**, con acción de salida limitada a "alertar + abrir ticket/correo con aprobación humana". Esto cubre el dolor actual sin exponerse a riesgo financiero mientras se calibra la precisión.

---

## 1. Contexto validado y decisiones arquitectónicas clave

### Respuestas recibidas en fase de descubrimiento

- **Foco MVP:** forecast y control presupuestal + reportería de cierre mensual + detección de anomalías y fuga de margen (los tres simultáneamente).
- **Fuente de datos:** todo en Metabase/DB. Sin OCR, sin ERP externo, sin parsing de PDFs.
- **Nivel de automatización:** detectar + abrir tickets/correos automáticos (acción comunicativa, no financiera). Aprobación humana antes del envío.
- **Referencias disponibles:** tarifario por contratista/servicio + presupuesto mensual por zona/contratista + baseline histórico (3–6 meses). Triple lente de comparación.

### Decisiones arquitectónicas derivadas

1. El agente es **analítico y comunicativo**, no transaccional. No toca contabilidad, no glosa facturas automáticamente, no crea notas crédito.
2. **Tres capas de comparación** se ejecutan en paralelo sobre cada transacción/OT: (a) tarifa esperada, (b) línea presupuestal, (c) baseline histórico estadístico. Cada capa genera una alerta independiente con severidad propia.
3. **Motor de forecast separado** del motor de anomalías. Forecast es pronóstico prospectivo; anomalía es detección retrospectiva. Mezclar ambos ensucia la interpretación.
4. **IA solo en narrativa y clasificación de causa raíz**. Los umbrales, cálculos y modelos estadísticos son determinísticos y testeables.
5. **Cadencia múltiple:** tiempo real para alertas críticas, diaria para seguimiento, semanal para forecast, mensual para cierre. Evitar recalcular todo en cada ciclo.
6. **Versionado del tarifario y del presupuesto** en tabla con `effective_from`/`effective_to`. Toda comparación es "a la fecha de la transacción".
7. **Trazabilidad forense desde el día 1.** Cada alerta guarda: fuente, regla disparada, valor observado, valor esperado, delta, severidad, evidencia (query + snapshot). Auditoría tiene que poder reproducir la alerta 6 meses después.

---

## 2. Descripción conceptual del agente

### Misión

Cerrar el mes antes del cierre. Convertir el OPEX de "revisión mensual reactiva" en "gestión continua con alertas tempranas, forecast confiable y cierre casi automatizado".

### Principios de diseño

- **Evidencia siempre.** Cada número lleva su query, fecha y valor de referencia.
- **Explicable a Finanzas.** Las narrativas del agente tienen que pasar el filtro de un comité financiero.
- **Determinístico primero, IA después.** Modelos estadísticos explícitos; IA solo en redacción y clasificación cualitativa.
- **Baja fricción para el analista.** El default es "aprobar con un click"; editar es la excepción.
- **Conservador en acción.** Alerta temprano, pero solo envía comunicación externa con aprobación humana en MVP.
- **Observable y reversible.** Dashboard de precisión, log de decisiones, kill switch, modo dry-run.

### Roles del agente

- **Monitor:** vigila la ejecución en tiempo casi real contra las tres referencias.
- **Pronosticador:** proyecta el cierre de mes por categoría, zona, contratista, tipo de servicio.
- **Detective:** identifica anomalías, outliers y patrones de fuga de margen.
- **Narrador financiero:** redacta resumen ejecutivo, comentarios del mes, explicaciones de variación.
- **Coordinador:** prepara correos/tickets a contratistas u operaciones para aclaración de desvíos, y los deja listos para envío con aprobación humana.
- **Auditor:** mantiene trazabilidad completa (quién vio qué alerta, qué se envió, qué respuesta llegó, cómo cerró).

---

## 3. Alcance funcional

### 3.1 Monitoreo continuo real vs. referencias

Consulta periódica (cada 1–6 h configurable) sobre OTs cerradas y costos imputados. Calcula por cada transacción el delta contra:

- **Tarifa pactada** (por contratista, tipo de servicio, OR, ventana de vigencia).
- **Línea presupuestal** (mensual, por zona/contratista/categoría).
- **Baseline histórico** (promedio móvil 3–6 meses, con desviación estándar).

Genera alertas tipificadas (sección 12) y las prioriza por severidad.

### 3.2 Forecast de cierre mensual

Proyección rolling del cierre del mes por categoría, zona, contratista y tipo de servicio usando:

- Tendencia de ejecución al día de corte vs. ritmo esperado.
- Estacionalidad intra-mes (primera/segunda quincena).
- OTs programadas aún sin ejecutar (pipeline).
- Ajustes por decisiones conocidas (ej. una zona sin brigada BIA hasta fin de mes).

Salida: tabla y gráfica "ejecutado / comprometido / proyectado / budget" con semáforo de desviación y alerta de cruces de umbral (+5%, +10%, +20%).

### 3.3 Detección de anomalías y fuga de margen

Detección multi-capa sobre cada OT/transacción:

- **Sobrecobro vs tarifa:** costo unitario > tarifa pactada × (1 + tolerancia).
- **Outlier estadístico:** costo fuera de banda (z-score > 2.5 por tipo+zona+contratista).
- **Duplicado:** mismo contratista, misma OT o misma dirección+fecha cobrados dos veces.
- **Sin soporte/cierre:** cobro registrado sobre OT sin acta de cierre o sin evidencia.
- **Patrón sistemático:** mismo contratista supera el baseline en ≥N OTs consecutivas.
- **Material sin OT asociada:** consumo de inventario imputado a OPEX sin OT emparejada.
- **Retrabajos encubiertos:** OTs reabiertas o pareadas sospechosamente.

### 3.4 Cierre mensual automatizado

Al cierre del mes:

- Genera reporte ejecutivo (PDF/Slack/Sheet) con ejecución, variación vs budget, top 5 desviaciones, top contratistas por gasto, top zonas, anomalías detectadas y cerradas.
- Exporta pivots estándar para Finanzas (por zona, por OR, por tipo de servicio, por contratista).
- Entrega lista de conciliación abierta (alertas activas al cierre).
- Resumen narrativo redactado por IA (2–3 párrafos) listo para presentar.

### 3.5 Comunicación proactiva

Ante un desvío accionable, prepara:

- **Ticket interno** para Operaciones o Finanzas con contexto completo.
- **Correo al contratista** solicitando aclaración o soporte documental.
- **Mensaje Slack** al analista con resumen y botones.

Todo queda en estado "borrador" hasta que un humano apruebe el envío. Se registra qué se envió, a quién, cuándo y si llegó respuesta.

### 3.6 Aprendizaje continuo

Cada alerta cerrada alimenta la base de casos: tipo, causa raíz, contratista, resolución, tiempo de cierre. Con 3+ meses de historia, el agente puede:

- Recalibrar umbrales automáticamente.
- Sugerir ajustes al tarifario y al presupuesto.
- Estimar tasa de falsos positivos por tipo de regla.
- Priorizar qué tipos de alerta auditar más a fondo.

---

## 4. Fases de implementación

### Fase 1 — Monitor + reporte básico (semanas 1–2)

- Consultas Metabase/DB sobre transacciones de OPEX.
- Comparación vs tarifario y vs baseline histórico.
- Dashboard v0 en Metabase (real vs budget por zona/contratista).
- Resumen diario en Slack (ejecución del día, top desviaciones, pipeline).
- **Salida:** el analista deja de abrir 10 dashboards para construir el estado del día.

### Fase 2 — Forecast + detección de anomalías + comunicación (semanas 3–4)

- Motor de forecast rolling con proyección a cierre de mes.
- Detector de anomalías multi-capa (sobrecobro, outlier, duplicado, sin soporte).
- Plantillas de ticket y correo con IA para narrativa.
- Flujo Slack con aprobación antes de enviar comunicación externa.
- Cierre mensual v0 (reporte ejecutivo + pivots + resumen IA).
- **Salida:** MVP entregable al final de semana 4.

### Fase 3 — Cierre asistido y recalibración (meses 2–3)

- Cierre mensual robusto con conciliación asistida.
- Recalibración de umbrales con 3 meses de historia de casos.
- Detección de patrones sistemáticos (mismo contratista, mismo OR).
- Integración con calendario de pagos para priorizar alertas antes del run de pagos.
- Dashboard ejecutivo con KPIs de control (ahorro detectado, tiempo de cierre).

### Fase 4 — Control continuo + acciones (meses 4–6)

- Acciones automatizadas de bajo riesgo (ej. retención de pago pendiente de soporte, apertura automática de glosa con doble aprobación).
- Sugerencias activas de ajuste tarifario y presupuestal.
- Modelos predictivos por contratista (reputación de cumplimiento, probabilidad de desvío).
- Auditoría mensual automatizada.

---

## 5. Arquitectura recomendada en n8n

### 5.1 Componentes lógicos

1. Triggers múltiples: cron cada 1–6 h (monitoreo), diario 07:00 (resumen), semanal lunes 07:00 (forecast), mensual día 1 (cierre).
2. Nodo de consulta Metabase/Postgres (transacciones, tarifario vigente, budget, baselines).
3. Normalización + enriquecimiento (match con tarifa vigente a la fecha, categorización contable, geocoding ligero).
4. Tres motores paralelos: comparador tarifario, detector de anomalías estadísticas, pronosticador rolling.
5. Motor de reglas de severidad y priorización.
6. Nodo de IA (Gemini 2.x primario, Claude fallback) para: narrativa financiera, clasificación de causa raíz, redacción de correos/tickets.
7. Generador de artefactos (Slack, correo borrador, ticket, reporte PDF).
8. Cola de aprobación (tabla en Postgres + mensajes Slack con botones).
9. Ejecutor de envío tras aprobación (SMTP/Gmail API, Slack API, ticketing API).
10. Persistencia en Cloud SQL Postgres con tablas versionadas.
11. Dashboard Metabase alimentado por las tablas del agente.
12. Manejo de errores con canal dedicado #bia-opex-errors.

### 5.2 Topología de infraestructura

- n8n self-hosted en Google Cloud Run (continuidad con el stack del Planner).
- Cloud SQL Postgres dedicado para tablas del agente OPEX (separado lógicamente del Planner, mismo cluster físico).
- Cloud Storage para snapshots mensuales, PDFs del cierre y evidencia histórica.
- Secret Manager para credenciales de Metabase, Slack, Gmail/SMTP, Gemini, Claude.
- Cloud Scheduler como fuente de triggers programados.
- Cloud Logging + Error Reporting.
- Recomendado: integrar con el mismo sistema de ticketing interno que use Operaciones (Linear, Jira, Notion, GitHub Issues, o canal Slack dedicado si no hay).

### 5.3 Separación entre lógica determinística e IA

| Categoría | Determinístico | IA (Gemini/Claude) |
|---|---|---|
| Cálculo de variación vs tarifa | Fórmula sobre DB | — |
| Baselines y z-scores | Estadística sobre DB | — |
| Forecast rolling | Modelo explícito (EWMA, regresión) | Ajuste cualitativo en casos raros |
| Detección de duplicados | Matching por clave | Desambiguación en coincidencias parciales |
| Categorización contable | Lookup en catálogo | Clasificación cuando notas son ambiguas |
| Severidad de alerta | Umbrales fijos | Re-ranking en borde |
| Clasificación de causa raíz | — | Clasificador LLM con taxonomía fija |
| Narrativa de cierre mensual | — | Redacción guiada con datos inyectados |
| Redacción de correo al contratista | — | Generación guiada con plantilla |
| Resumen diario Slack | Estructura fija | Frase explicativa por bloque |
| Detección de patrón sistemático | Agregación SQL + umbral | Lectura de notas para contexto |

---

## 6. Diagrama lógico del flujo

```
[Cron 1-6h]   [Cron diario]   [Cron semanal]   [Cron mensual]
      │              │                │                │
      ▼              ▼                ▼                ▼
[Consulta Metabase] (transacciones, tarifario, budget, baselines)
      │
      ▼
[Normalización + match tarifa vigente]
      │
      ├──────────────┬───────────────┬────────────────┐
      ▼              ▼               ▼                ▼
[Comparador    [Detector      [Forecast          [Generador
 tarifario]     anomalías]     rolling]           pivots cierre]
      │              │               │                │
      └──────────────┴───────────────┴────────────────┘
                           │
                           ▼
              [Motor de severidad + priorización]
                           │
                           ▼
              [Nodo IA: narrativa + causa raíz + redacción]
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
    [Slack resumen]  [Borrador correo] [Borrador ticket]
            │              │              │
            ▼              ▼              ▼
    [Cola de aprobación humana en Slack / dashboard]
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
          [Aprobar]   [Editar]    [Descartar]
              │            │            │
              ▼            ▼            ▼
         [Enviar]   [Reabrir IA]  [Log motivo]
              │
              ▼
     [Log auditoría] ──► Dashboard Metabase + Cierre mensual
```

---

## 7. Lista de nodos sugeridos en n8n

| Nodo | Función | Notas |
|---|---|---|
| Schedule Trigger × 4 | Cron para monitoreo, diario, semanal, mensual | Usar Cloud Scheduler en producción |
| Postgres / HTTP (Metabase) | Lectura de transacciones, tarifario, budget, baseline | Queries parametrizadas y versionadas |
| Code (normalización) | Match a tarifa vigente, categorización, geocoding | Con tests unitarios |
| Code (comparador tarifario) | Calcula delta vs tarifa por transacción | Tolerancia configurable por categoría |
| Code (detector anomalías) | z-score, duplicados, sin soporte, patrón sistemático | Cada detector es un módulo independiente |
| Code (forecast) | EWMA / regresión / promedio móvil por categoría | Validar método con histórico antes de promover |
| Google Gemini Chat Model | Narrativa financiera, causa raíz, redacción correo | Structured output para causa raíz |
| Anthropic Chat Model | Redacción larga de cierre mensual y postmortems | Fallback de calidad |
| If / Switch | Bifurca según severidad y tipo de alerta | — |
| Merge | Combina salida de los tres motores por transacción | — |
| Slack — Send Message | Resumen diario, alertas, cola de aprobación | Block Kit con botones |
| Webhook (interactivity) | Recibe aprobaciones / rechazos desde Slack | Validar signing secret |
| Gmail / SMTP | Envío de correos tras aprobación | Dirección remitente dedicada |
| HTTP Request (ticketing) | Creación de ticket tras aprobación | Conector según sistema elegido |
| Postgres (writes) | alerts, approvals, communications, forecasts, closes | Tablas con retención 24 meses |
| PDF generator (Puppeteer / Gotenberg) | Reporte mensual en PDF | Plantilla HTML versionada |
| Error Trigger | Captura errores | Publica en #bia-opex-errors |
| Wait | Timeout de aprobación con escalamiento | Fallback: pasa a revisión manual |

---

## 8. Datos requeridos y fuentes

| Dato | Fuente primaria | Uso |
|---|---|---|
| Transacciones de OPEX por OT | Metabase | Insumo principal |
| Categoría contable por transacción | Metabase (catálogo) | Agregación y reporte |
| Tarifario vigente (por contratista, servicio, OR) | Tabla versionada en Cloud SQL | Comparación tarifa |
| Presupuesto mensual (por zona, contratista, categoría) | Tabla versionada en Cloud SQL | Forecast y control |
| Baseline histórico (3–6 meses) | Vista materializada en DB | Detección de outliers |
| OT asociada (tipo, estado, cierre, evidencia) | Metabase | Validación de soporte |
| Notas de OT y de factura | Metabase | IA — causa raíz, duplicados |
| Acta de cierre / evidencia | Metabase / storage | Validación "sin soporte" |
| Pipeline de OTs pendientes | Metabase | Forecast de cierre |
| Calendario de pagos a contratistas | Sheet o DB | Priorizar alertas antes de pagar |
| Log del agente (alerts, approvals, comms) | Cloud SQL | Auditoría y mejora continua |
| Catálogo de causas raíz | Tabla de referencia | Clasificación consistente |
| Lista de contratistas sensibles / VIP | Tabla de referencia | Flags y políticas especiales |

---

## 9. Reglas de negocio iniciales

### 9.1 Reglas duras (determinísticas)

1. Toda transacción con `costo > tarifa_vigente × (1 + tolerancia)` genera alerta de sobrecobro. Tolerancia por defecto 3%.
2. Toda transacción con `z_score > 2.5` contra baseline `(tipo, zona, contratista)` genera alerta de outlier.
3. Dos transacciones del mismo contratista en misma OT/dirección y fecha idéntica → alerta de posible duplicado.
4. Transacción sobre OT sin acta de cierre → alerta "sin soporte".
5. Ejecución mensual > budget × 1.05 (a mitad de mes) → alerta de desvío presupuestal grado 1; > 1.10 → grado 2; > 1.20 → crítica.
6. Proyección de cierre > budget × 1.10 → alerta de forecast crítico a al menos 5 días del fin de mes.
7. Contratista con ≥3 alertas activas en el mes → flag de patrón sistemático y escalamiento.
8. Material sin OT asociada → alerta de imputación huérfana.
9. Toda comunicación externa (correo a contratista) requiere aprobación humana en MVP.
10. Toda alerta queda con estado trazable (`open`, `ack`, `in_progress`, `resolved`, `false_positive`).
11. Toda resolución captura causa raíz seleccionada + texto libre opcional.
12. Cada regla se ejecuta contra la versión del tarifario/budget vigente a la fecha de la transacción (no la actual).

### 9.2 Reglas blandas (IA + heurística)

- Clasificación de causa raíz sobre notas de la OT y de la factura.
- Narrativa explicativa de variación por categoría ("El mes cierra 8% por encima del budget principalmente por X y Y").
- Identificación de "historia" en patrones (un contratista que va escalando desvíos mes a mes).
- Redacción del correo de aclaración con tono profesional consistente.
- Sugerencia de ajuste tarifario cuando un contratista sistemáticamente factura por encima y la operación lo valida.

---

## 10. Motor de forecast

El forecast es el núcleo que convierte al agente en proactivo. Se recomienda arrancar con métodos simples, explicables y explícitos antes de saltar a ML.

### 10.1 Método por defecto

**EWMA (Exponentially Weighted Moving Average) + ajuste por pipeline:**

```
proyección_cierre = ejecutado_al_día + (ritmo_ewma × días_restantes) + costo_esperado_pipeline
```

Donde:

- `ritmo_ewma` = promedio ponderado del gasto diario de los últimos 20 días, con peso α = 0.3.
- `costo_esperado_pipeline` = Σ OTs programadas × tarifa esperada × probabilidad de ejecución.

### 10.2 Método secundario

**Regresión lineal sobre acumulado** del mes, con corrección por estacionalidad intra-mes (primera/segunda quincena suele tener patrón distinto).

### 10.3 Validación

Antes de promover un método, se valida con backtesting sobre los últimos 3–6 meses: error absoluto medio (MAE) y sesgo. Se elige el método con menor MAE por categoría. Métodos por categoría pueden diferir.

### 10.4 Confianza y banda

Cada forecast entrega: punto central + banda alta/baja (P80) + nivel de confianza. Si el budget cae dentro de la banda, alerta es amarilla; si está fuera, roja.

### 10.5 Re-forecast

El forecast se recalcula diario y se muestra evolución semana a semana: "el lunes proyectábamos $X, hoy $Y, delta Z%". Eso permite detectar degradación temprana.

---

## 11. Motor de detección de anomalías

Cinco detectores independientes, combinados en el motor de severidad.

### 11.1 Sobrecobro vs tarifa

`alerta si costo_unitario > tarifa_vigente × (1 + tolerancia)`. Tolerancia por defecto 3%, configurable por categoría.

### 11.2 Outlier estadístico

`alerta si abs((costo - baseline_mean) / baseline_std) > 2.5`, donde el baseline es por `(tipo_servicio, zona, contratista)` con ventana rolling de 3–6 meses. Mínimo 10 observaciones para usar el baseline; si no, se usa el baseline general por `(tipo_servicio, zona)`.

### 11.3 Duplicado

`alerta si existen ≥2 transacciones con (contratista, dirección, fecha±1 día, monto±5%)` o `(OT_id, contratista, categoría)` repetido.

### 11.4 Sin soporte

`alerta si transacción está sobre una OT que no tiene estado = cerrada con acta`, por más de 7 días después de la facturación.

### 11.5 Patrón sistemático

`alerta si un mismo (contratista, zona) tiene ≥ N outliers en ventana de 30 días`, donde N depende del volumen. Escalamiento automático: señal de revisar tarifario o desempeño.

### 11.6 Fuga silenciosa de margen

`alerta si la diferencia (costo_real - costo_teórico) para un (cliente, OR, mes) supera X%`. Detecta no un outlier individual, sino degradación agregada.

---

## 12. Matriz de alertas

| ID | Tipo | Condición | Severidad | Acción por defecto |
|---|---|---|---|---|
| A1 | Sobrecobro vs tarifa ≤ 5% | Costo 3–5% por encima de tarifa | Baja | Solo log |
| A2 | Sobrecobro vs tarifa > 5% | Costo 5–15% por encima | Media | Slack + ticket interno |
| A3 | Sobrecobro vs tarifa > 15% | Costo > 15% por encima | Alta | Slack urgente + correo contratista (aprobación humana) |
| A4 | Outlier z > 2.5 | Fuera de banda histórica | Media | Slack + ticket |
| A5 | Outlier z > 3.5 | Muy fuera de banda | Alta | Slack urgente + correo contratista |
| A6 | Duplicado probable | Match por clave | Alta | Slack + ticket (retener validación) |
| A7 | Sin soporte > 7 días | Factura sin acta de cierre | Media | Correo a operaciones para adjuntar soporte |
| A8 | Desvío budget > 5% intra-mes | Real acumulado > budget × 1.05 | Media | Slack + entrada en cierre |
| A9 | Desvío budget > 10% | Real > budget × 1.10 | Alta | Slack urgente + escalamiento a coordinador |
| A10 | Forecast > budget × 1.10 (≥5 días al cierre) | Proyección supera budget con margen temporal | Alta | Slack + reunión sugerida |
| A11 | Patrón sistemático | ≥3 alertas activas mismo contratista en mes | Crítica | Slack crítico + revisión de contrato/tarifario |
| A12 | Fuga silenciosa | Costo agregado vs teórico > X% | Alta | Análisis profundo + ticket para finanzas |
| A13 | Material sin OT | Consumo imputado sin OT asociada | Media | Ticket a operaciones para emparejar |
| A14 | Contratista recurrente sin confirmar | Desvíos sistemáticos por X meses | Crítica | Revisión de relación comercial |

*Gobernanza: umbrales viven en tabla `opex_rules` versionada. Cambios por PR con aprobación Finanzas + Operaciones. Se mide tasa de falsos positivos por regla mensualmente.*

---

## 13. Formatos de comunicación

### 13.1 Resumen diario Slack (07:30)

```
*Analista OPEX BIA — 23/abr/2026*
Ejecución del día anterior: *$X.XXX.XXX*  |  MTD: *$Y.YYY.YYY* (⚠ 8.2% sobre budget)

🔴 Alertas altas/críticas: *4*
🟡 Alertas medias: *11*
🟢 Cerradas ayer: *7*

*Top 3 desviaciones del día:*
• Contratista Beta — NORM Bogotá — $1.2M vs $980k esperado (+22%)
• Cobro duplicado posible — OT-48201 — Contratista Alfa
• 5 facturas sin acta de cierre > 7 días

Forecast cierre mes: *$Z.ZZZ.ZZZ*  (budget $W.WWW.WWW, +6.1%)

[Ver cola de aprobación (4)]   [Abrir dashboard]   [Pausar alertas no críticas]
```

### 13.2 Alerta individual con cola de aprobación

```
:warning: *Sobrecobro > 15% — OT-48217*
Contratista: Alfa  |  Tipo: INST  |  Zona: Medellín
Costo reportado: $520.000   Tarifa vigente: $430.000 (delta +20.9%)

Causa raíz sugerida (IA): "Facturación con material no contemplado en tarifa plana"
Evidencia: query OPEX-0428 | acta cierre no adjunta

Acciones propuestas:
• Correo al contratista solicitando desglose (borrador listo)
• Ticket a operaciones para validar alcance

[✉️ Enviar correo (ver borrador)]   [🎫 Crear ticket]   [👀 Abrir en dashboard]   [❌ Falso positivo]
```

### 13.3 Borrador de correo al contratista

```
Asunto: Solicitud de aclaración — OT-48217

Estimado equipo Contratista Alfa,

Al revisar la ejecución del 22/abr/2026 identificamos una diferencia respecto a
la tarifa vigente en la OT-48217 (INST, Medellín, Cra 65 #45-12):

  • Valor facturado: $520.000
  • Tarifa de referencia: $430.000
  • Diferencia: +20.9%

Agradecemos compartir el desglose de materiales, horas adicionales o conceptos
extraordinarios que justifiquen la diferencia, junto con el acta de cierre
correspondiente.

Fecha límite de respuesta: 27/abr/2026.

Cordial saludo,
Equipo OPEX — BIA Energy
```

### 13.4 Resumen ejecutivo de cierre mensual

Generado automáticamente el día 1 del mes siguiente, con 2–3 párrafos de narrativa por categoría, tabla resumen y pivots anexos. Diseñado para comité de operaciones.

```
*Cierre OPEX — Marzo 2026*

Ejecución total: $XXX  (budget $YYY, variación +/- Z%)

Narrativa (IA): El mes cerró X% sobre presupuesto, con Bogotá como principal
driver (+15% vs budget) explicado por mayor volumen de NORM y dos contratos
de servicio extraordinario. Medellín y Cali ejecutaron en línea. El
Contratista Alfa concentró 3 alertas sistemáticas; se recomienda revisión de
tarifario antes de abril.

Top drivers de variación:
• ...
• ...

Anomalías detectadas y cerradas: 42  |  Abiertas al cierre: 5
Ahorro estimado por alertas atendidas: $XXX

Anexos: pivot_zona.xlsx | pivot_contratista.xlsx | alertas_abiertas.csv
```

### 13.5 Alerta crítica de forecast

```
:rotating_light: *Forecast crítico — Marzo 2026*
Proyección cierre: *$X* | Budget: *$Y* | Variación proyectada: *+12.3%*
Días restantes: 8   |   Confianza: 82%

Principales contribuyentes a la desviación:
1. Zona Bogotá (+$X)
2. Contratista Alfa (+$Y)
3. Tipo REQA sobre-ejecutado (+$Z)

Acción sugerida: reunión breve con coordinador y plan de contención de los 3
drivers antes del día 25.

[Agendar reunión]   [Ver dashboard]   [Abrir plan de contención]
```

---

## 14. Roles y aprobadores

| Rol | Responsabilidad | Interacción con el agente |
|---|---|---|
| Analista OPEX | Revisar alertas, aprobar comunicaciones, cerrar casos | Interlocutor principal en Slack / dashboard |
| Coordinador Finanzas Operativas | Validar desvíos críticos, autorizar acciones de grado alto | Escalamiento en críticos + revisión cierre mensual |
| Coordinador Operaciones | Contexto operativo para desvíos (por qué un outlier) | Recibe tickets del agente |
| Product Ops / Ingeniería | Mantener agente, reglas, infra | Dueño de código, matrices, pipelines |
| Auditor interno | Revisar trazabilidad y calidad de alertas | Consulta tablas de logs y reportes mensuales |
| Contratistas externos | Responder solicitudes de aclaración | Reciben correos iniciados desde el agente tras aprobación humana |

---

## 15. Riesgos del proyecto

| Categoría | Riesgo | Mitigación |
|---|---|---|
| Técnico | Tarifario/budget desactualizados generan falsos positivos masivos | Tabla versionada + alertas de "tarifa expirada" + monitoreo de tasa de falsos positivos |
| Técnico | Baseline con datos contaminados (periodo atípico) | Ventanas de baseline configurables + exclusión de outliers para calcular el propio baseline |
| Técnico | Forecast se degrada por cambios operativos (ej. nueva zona) | Re-forecast diario + alerta si el error del forecast supera umbral |
| Operativo | Fatiga de alertas (ruido Slack) | Diseño tiered + severidad + digests + umbrales auto-ajustables |
| Operativo | Contratistas perciben correos como "auditoría automatizada hostil" | Todo correo externo con aprobación humana + tono profesional + plantilla revisada por legal |
| Financiero | Falso positivo en comunicación externa daña relación | MVP no acciona contabilidad; toda comunicación requiere aprobación; historial de falsos positivos visible |
| Financiero | Forecast con sesgo optimista induce decisiones malas | Reportar banda de confianza + evolución histórica del forecast + backtesting |
| Gobierno | Sin trazabilidad podría violar auditoría SOX-like | Logs inmutables + snapshot de evidencia + retención 24 meses |
| Adopción | Analista no confía en IA y sigue proceso manual | Transparencia total + precisión visible + empezar con alertas, IA solo en narrativa |
| Costos | Consumo de LLM escala con volumen | Filtro determinístico fuerte; IA solo en cola aprobación y cierre mensual |

---

## 16. Supuestos que deben validarse

1. Los datos de transacciones en Metabase están categorizados contablemente de forma consistente (o existe un mapeo claro).
2. El tarifario vigente es consultable con fecha de efectividad y está actualizado.
3. El budget mensual existe con granularidad (zona, contratista, categoría) suficiente para alertas de grado 1.
4. Existe acta/evidencia de cierre digital o referenciable en la OT para la regla "sin soporte".
5. El analista OPEX está dispuesto a usar Slack como cola principal de aprobación.
6. Finanzas tolera un MVP donde el agente no ejecuta acciones contables en 4–6 semanas.
7. Existe dirección de correo dedicada (ej. opex@bia.app) para comunicaciones salientes.
8. Se puede conectar con sistema de ticketing interno (o Slack canal dedicado basta como v0).
9. Existe presupuesto Cloud (~US$200–500/mes, ligeramente superior al del Planner por reporte y snapshots).

---

## 17. Métricas de éxito

| KPI | Definición | Meta 3 meses |
|---|---|---|
| MAE del forecast mensual | Error absoluto medio entre proyección a día 20 y cierre real | ≤ 3% |
| Cobertura de alertas útiles | alertas accionadas / total alertas | ≥ 60% |
| Tasa de falsos positivos | falsos positivos / total alertas | ≤ 20% |
| Tiempo cierre alerta alta/crítica | mediana entre detección y resolución | ≤ 48 h |
| Ahorro detectado (directo) | Σ montos glosados/ajustados por alerta confirmada | Reportado mensual |
| Ahorro evitado (indirecto) | Σ montos de forecast corregido por intervención | Reportado mensual |
| % alertas cerradas sin intervención externa | Resueltas internamente / total | ≥ 50% |
| Tiempo de cierre mensual | días desde fin de mes hasta reporte ejecutivo listo | ≤ 3 días (vs baseline actual) |
| Adopción de recomendaciones IA | aceptadas / generadas | ≥ 70% |
| Cobertura de reglas ejecutándose | reglas activas / reglas definidas | 100% |
| Precisión de clasificación de causa raíz | F1 sobre muestra auditada | ≥ 0.80 |
| Horas ahorradas al analista | h estimadas automatizadas/semana | ≥ 15 h/semana |

---

## 18. Roadmap hacia control continuo

| Hito | Objetivo | Cuándo |
|---|---|---|
| Kickoff + descubrimiento | Validar supuestos, modelo de datos, vigencia de tarifario/budget | Semana 0 |
| Fase 1 | Monitor + dashboard + resumen diario | Semana 2 |
| Fase 2 — MVP | Forecast + anomalías + comunicación con aprobación + cierre v0 | Semana 4 |
| Piloto controlado | Uso real por 4–6 semanas con el analista titular | Semanas 5–10 |
| Versión 3 meses | Cierre asistido + recalibración + integración ticketing + dashboard ejecutivo | Mes 3 |
| Versión 6 meses | Acciones contables de bajo riesgo con doble aprobación + modelos predictivos por contratista | Mes 6 |

---

## 19. Recomendaciones de herramientas complementarias

- **n8n self-hosted (Cloud Run):** orquestación, continuidad con el Planner.
- **Gemini 2.x Flash/Pro:** LLM primario por costo y contexto amplio para narrativa mensual.
- **Claude API (Haiku/Sonnet):** fallback de calidad para redacción de cierre mensual y correos delicados.
- **Cloud SQL Postgres:** almacén del agente (alerts, approvals, comms, forecasts, closes, rules versionadas).
- **Metabase:** dashboards operativos y ejecutivos, pivots, drill-down.
- **Gmail API o SendGrid:** envío de correos tras aprobación. Dominio remitente dedicado.
- **Sistema de ticketing (el que ya usen Operaciones/Finanzas):** Linear, Jira, Notion, o canal Slack con convención si no hay.
- **Puppeteer / Gotenberg:** generación de PDF del cierre mensual desde HTML versionado.
- **Cloud Scheduler + Cloud Logging:** triggers y observabilidad.
- **Git + GitHub Actions:** versionado de reglas, prompts, workflows n8n, plantillas de correo.
- **Opcional — Looker Studio:** solo si Finanzas prefiere ese dashboard sobre Metabase.
- **No recomendado duplicar:** hojas de Google como fuente de verdad para tarifario/budget. Si existen, se migran a tabla versionada en DB durante fase 0.

---

## 20. Gobierno, control y seguridad

- Bitácora completa en tablas: `opex_alerts`, `opex_approvals`, `opex_communications`, `opex_forecasts`, `opex_closes`, `opex_rules`. Inmutables (solo append).
- Tarifario y budget con campos `effective_from`/`effective_to`. Cada cálculo guarda la versión usada.
- Control de cambios de reglas y umbrales vía Git. Changelog aprobado por Finanzas + Operaciones.
- Modo simulación (`dry_run=true`): el agente genera todo pero no envía correos ni crea tickets.
- Modo auditoría: vistas read-only en Metabase sobre las seis tablas del agente.
- Kill switch en Slack (`/opex pause`) y flag en DB.
- Doble aprobación obligatoria para: correos a contratistas con desvío > 15%, acciones contables en fase 4, cambios de tarifario sugeridos por el agente.
- Manejo de errores: canal Slack dedicado, reintento con backoff, fallback a revisión humana si falla 3 veces.
- Retención: logs 24 meses en Postgres + export anual a Cloud Storage.
- Seguridad del correo saliente: dominio dedicado con SPF/DKIM/DMARC + footer legal estándar + lista blanca de dominios destino.

---

## 21. Preguntas de clarificación pendientes

1. ¿Cuál es la granularidad mínima con que existe budget mensual hoy (zona? contratista? categoría contable?)? ¿Está digital y consultable?
2. ¿Dónde vive el tarifario por contratista y con qué cadencia se actualiza? ¿Tiene fechas de vigencia?
3. ¿Qué tabla/vista en Metabase es la fuente de verdad de transacciones OPEX y quién la mantiene?
4. ¿Existe una dirección de correo corporativa para comunicaciones salientes (p. ej. opex@bia.app) con SPF/DKIM configurados?
5. ¿Qué sistema de ticketing usa Operaciones/Finanzas hoy? ¿Está conectado o se empieza con canal Slack dedicado?
6. ¿Qué umbrales de desviación se consideran hoy "aceptables" (tolerancia tarifa, desvío budget)?
7. ¿Quién aprueba correos salientes a contratistas: el analista OPEX o debe escalar al coordinador?
8. ¿Hay contratos o contratistas con tratamiento especial (p. ej. tarifa variable, cap mensual, gain-share) que deban modelarse?
9. ¿Existe política formal de glosa / retención de pago, o el agente solo alerta sin recomendar retención?
10. ¿Qué políticas aplican para el cierre mensual: fecha de corte, plazo de revisión, formato del reporte esperado por Finanzas corporativa?

---

## 22. MVP ejecutable en 4 semanas

| Semana | Entregable | Criterio de aceptación |
|---|---|---|
| 1 | Infra base (n8n + Postgres + Slack app + Cloud Scheduler) + queries OPEX + tablas versionadas de tarifario/budget cargadas + baseline histórico calculado | Dashboard v0 muestra ejecución real vs budget vs baseline del mes en curso |
| 2 | Comparador tarifario + detector de outlier + resumen diario Slack + cola de aprobación con borradores de correo/ticket | Analista recibe resumen 07:30 con alertas tipificadas y puede aprobar/rechazar al menos 10 alertas/día |
| 3 | Forecast rolling EWMA + validación con backtest + alertas de desvío budget + alertas de forecast crítico | Forecast mostrado en dashboard con banda de confianza; backtest 3 meses con MAE reportado |
| 4 | Cierre mensual v0 (reporte ejecutivo IA + pivots + PDF) + plantillas de correo con aprobación + dashboard ejecutivo + documentación operativa | Cierre de abril generado automáticamente el 1 de mayo con narrativa, pivots y anexos |

**Supuesto operativo:** un dev 60% + analista OPEX champion 30% + acceso priorizado a Metabase durante las 4 semanas.

---

## 23. Automatizable hoy vs. pendiente de madurez

### Automatizable hoy (sin bloqueos)

- Monitoreo real vs tarifario, budget y baseline.
- Forecast EWMA + regresión + validación backtest.
- Detección de outliers, duplicados, sin soporte.
- Resumen diario, alertas, cola de aprobación en Slack.
- Generación de correos y tickets con aprobación humana.
- Cierre mensual automatizado con narrativa IA.
- Dashboard operativo y ejecutivo.

### Requiere madurez de datos, reglas o gobierno

- Acciones contables automáticas (glosa, retención, nota crédito).
- Recalibración automática de umbrales (mínimo 3 meses de casos cerrados).
- Modelos predictivos por contratista (requieren histórico suficiente).
- Sugerencia automática de ajuste tarifario (requiere proceso formal de revisión con contratistas).
- Detección de fraude intencional (requiere investigación adicional y reglas legales, no es objetivo del MVP).

---

## 24. Cierre

El Analista OPEX Virtual es, de los dos agentes diseñados, el que puede arrancar más ambicioso porque los datos están limpios en Metabase y la "acción" del MVP se limita a comunicación con aprobación humana — bajo riesgo financiero, alto valor inmediato. El camino a 3 meses es consolidar forecast, cerrar ciclo con Finanzas y automatizar el cierre mensual. El camino a 6 meses introduce acciones contables de bajo riesgo con doble aprobación y modelos predictivos por contratista.

Las dos decisiones críticas para arrancar son: (a) confirmar granularidad del budget y vigencia del tarifario, y (b) acordar con Finanzas el protocolo de comunicación saliente a contratistas (tono, plazos, doble aprobación para desvíos altos). Con esas dos palancas resueltas, el agente puede entregar valor medible desde la semana 2.

**Próximo paso sugerido:** sesión de 60 min con el analista OPEX + coordinador de Finanzas para validar las 10 preguntas abiertas, acordar umbrales iniciales y consensuar la plantilla de correo saliente.
