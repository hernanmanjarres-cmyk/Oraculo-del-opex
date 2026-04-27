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

---

# Apéndice A — Estado de implementación real (actualizado 2026-04-27)

> Este apéndice documenta lo que efectivamente se construyó, cómo se desvió del diseño original y los patrones operativos aprendidos durante la implementación. El documento de diseño (secciones 0–24) es la visión canónica; este apéndice es el espejo de la realidad.

## A.1 Stack real vs. diseño original

| Componente | Diseño (sec. 5.2 / 19) | Implementación real | Razón del cambio |
|---|---|---|---|
| Orquestador | n8n self-hosted en Cloud Run | **n8n cloud 1.123.33** (proyecto "Oráculo del OPEX") | Time-to-market; sin necesidad de infra propia para MVP |
| Base de datos | Cloud SQL Postgres dedicado | **Supabase** (Session Pooler `aws-1-us-east-1.pooler.supabase.com`, user `postgres.jgyvgckbintxqrihitcw`, port 5432, SSL Ignore) | Ya existe en BIA; ahorra setup |
| LLM primario | Gemini 2.x Flash/Pro | **OpenAI gpt-4o-mini** | Cuota Gemini free-tier agotada en pruebas; gpt-4o-mini es barato y suficiente para clasificación |
| LLM fallback | Claude API | **No configurado** (sin créditos en cuenta) | Pendiente; OpenAI cubre el rol primario hoy |
| Tarifario/Budget | Tablas versionadas en Cloud SQL | **Google Sheets "Tarifarios BIA"** sincronizado a `opex_tarifario` en Supabase vía WF-01 (cron diario 06:00) | El equipo OPEX ya gestiona Sheets; se mantiene como fuente de verdad y se sincroniza |
| Triggers | Cloud Scheduler | **Schedule Trigger nativo de n8n** | Suficiente en cloud n8n |
| Storage de evidencia | Cloud Storage | **No implementado** (snapshot in-row en JSONB) | Pospuesto a Fase 3 |
| Ticketing | Linear/Jira/Notion + Slack | **Slack canales dedicados** (sin sistema de tickets externo) | Operaciones aún no formaliza ticketing; Slack como cola |
| Generación PDF | Puppeteer / Gotenberg | **No implementado todavía** (WF-07 entrega Slack + Sheet) | Diferido a iteración posterior |
| Secret Manager | Secret Manager GCP | **n8n credentials store** | Suficiente para el alcance actual |

## A.2 Credenciales y recursos productivos

| Recurso | ID / valor | Notas |
|---|---|---|
| Supabase Postgres | Credential id `92nLfZ0IlzU004no` ("Supabase Oráculo del Opex") | Session Pooler; SSL Ignore |
| Slack OAuth | Credential id `3` ("Slack OPEX BIA") | Usado en `chat.postMessage` cuando aplica |
| Slack Header Auth (HTTP Request) | Credential id `GciOWwHMTLVJJuAu` ("Header Auth account 12") | Patrón obligatorio para Block Kit dinámico (ver A.6) |
| Google Sheets | Credential id `4` (Service Account "Google OPEX BIA") | Lectura del libro "Tarifarios BIA" |
| Metabase | API Key inline en WF-02 nodo "Metabase: Fetch Costos OPEX" | Pendiente reemplazar el placeholder `METABASE_API_KEY_AQUI` |
| OpenAI | Credential propia configurada en n8n | Modelo `gpt-4o-mini` para clasificación/narrativa |
| Sheet tarifarios | ID `1ATh2kaZZHnWAh8UHDJKKYd5lccqvUAolU6ElJhAU4zk` | Pestaña `Contratistas` con columnas `contratista_id | sheets_file_id | hoja | activo` |

### Canales Slack operativos

| Canal | ID | Uso |
|---|---|---|
| `#opex-alertas` | `C0AVCTBV665` | Alertas críticas (anomalías severidad alta, forecast crítico) |
| `#opex-aprobacion` | `C0AUWJ91V1T` | Cola de aprobación (alertas medias, cierres pendientes de revisión) |
| `#opex-cierre` | `C0AUXUFH1HU` | Resumen mensual y cierres |
| `#opex-errors` | `C0AUTK8B1HR` | Error Trigger global, fallos de workflows |

### Metabase cards de referencia

| Card ID | Nombre | Uso |
|---|---|---|
| **66793** | Costos asociados a opex | **Fuente principal de WF-02** (~26k filas, filtrada a últimos 30 días en Code node). Columnas clave: `titulo` (ID único OT), `contratista`, `operador_de_red`, `fecha_programada`, `total_cost`, `fase_actual`, `mercado`, `tipo_de_servicio` |
| 66727 | CAC_BIA | Agregado por cliente |
| 63163 | Opex Costs General | Detalle costos por visita |
| 55773 | Visitas General | Master visitas |

> Documentación completa de cards en `metabase_cards_n8n_documentation.md` en la raíz del proyecto.

## A.3 Workflows construidos (FASE 1 + FASE 2)

Los 9 workflows de las fases 1–2 están **activos en n8n cloud**. JSON versionados en `Documentos analista opex/FASE_1_WORKFLOWS/` y `FASE_2_WORKFLOWS/`.

### WF-01 — Sync Tarifarios desde Sheets (`wf_01_data_sync_sheets.json`)

- **Trigger:** Cron diario 06:00.
- **Flujo:** Lee la pestaña `Contratistas` del libro "Tarifarios BIA" → SplitInBatches por contratista (output 1 = loop, output 0 = done) → Lee la pestaña dinámica indicada por la columna `hoja` → INSERT/UPSERT a `opex_tarifario`.
- **Estado:** ✅ ~3,600 tarifas reales cargadas (18 contratistas × 67 ítems × 3 grupos OR).
- **Pendiente:** rama de Budget desconectada hasta crear el Sheet de presupuesto mensual con columnas `mes | anio | zona | contratista_id | categoria | monto_budget`.
- **Contratistas activos:** GMAS, POWER_GRID, DR_TELEMEDIDA, SGE, JEM, AR_INGENIERIA, C3, C3_BOGOTA, ISELEC, DISELEC, GATRIA, ISEMEC, ISEMEC_BOGOTA, S&SE, REHOBOT, MONTAJES_MTE, ELECPROYECTOS, MCR.

### WF-02 — OPEX Monitor (`wf_02_opex_monitor.json`)

- **Trigger:** Cron horario.
- **Flujo:** Fetch Metabase card 66793 → Code node consolida 26k filas en 1 batch SQL → INSERT a `opex_transactions` → Query enriquecido con `get_tarifa_vigente()` → Reglas A1–A9, A13 → Slack alertas altas a `#opex-alertas`.
- **Estado:** ✅ Operativo. Pendiente: reemplazar `METABASE_API_KEY_AQUI`.

### WF-03 — Daily Slack Summary (`wf_03_daily_slack_summary.json`)

- **Trigger:** Cron 07:30.
- **Flujo:** Agrega métricas del día anterior + MTD + forecast actual → Code "Formatear Resumen" + HTTP Request a `chat.postMessage` con Block Kit dinámico.
- **Estado:** ✅ Operativo. Botón "Abrir dashboard" sin `url` (placeholder hasta que exista dashboard Metabase OPEX).

### WF-04 — Slack Approval Webhook (`wf_04_slack_approval_webhook.json`)

- **Trigger:** Webhook (signing secret pendiente de validación).
- **Switch v3.2** enruta el `action_id` recibido a 4 ramas:
  - `aprobar` → marca alerta `resolved` + crea registro en `opex_cases` con `veredicto = 'confirmado'`.
  - `falso_positivo` → marca alerta `false_positive` + caso `veredicto = 'false_positive'`.
  - `pausar` → flag global `agente_pausado = true`.
  - `ver_cola` → responde con resumen de cola actual.
- **Decisión:** rama "Rechazar" eliminada del diseño (parser, switch rule, nodo Postgres "Marcar Rechazado"). El analista usa "Falso positivo" para descartar.
- **Estado:** ✅ Cerrado y operativo en producción.

### WF-05 — Anomaly Detector (`wf_05_anomaly_detector.json`)

- **Trigger:** Cron horario.
- **Flujo:** N detectores en paralelo (A1–A9, **A12 fuga silenciosa**, A13) → "Combinar Resultados Detectores" (`$input.all()`) → AI Agent + sub-node OpenAI gpt-4o-mini para `causa_raiz` y `narrativa` → Code "Enriquecer Alerta con IA" recupera `alerta` original vía `$('Combinar Resultados Detectores').item.json` → Code "Formatear Notificación Slack" → HTTP Request a `chat.postMessage`.
- **A12 (fuga silenciosa)** implementada con `get_tarifa_vigente()`:

  ```sql
  WITH tx_con_tarifa AS (
    SELECT t.contratista_id, t.contratista_nombre, t.costo_total, t.cantidad,
      get_tarifa_vigente(
        t.contratista_id, t.item_codigo,
        COALESCE(NULLIF(t.or_nombre,''), 'OTROS_OR'),
        t.fecha_tx::DATE, 'diurna'
      ) AS tarifa_vigente
    FROM opex_transactions t
    WHERE t.fecha_tx >= DATE_TRUNC('month', CURRENT_DATE)
      AND t.cantidad IS NOT NULL AND t.cantidad > 0
      AND t.item_codigo IS NOT NULL
  )
  SELECT 'A12' AS codigo_alerta, ...
  FROM tx_con_tarifa ct
  WHERE ct.tarifa_vigente IS NOT NULL
  GROUP BY ct.contratista_id
  HAVING SUM(ct.cantidad * ct.tarifa_vigente) > 0
    AND ((SUM(ct.costo_total) - SUM(ct.cantidad * ct.tarifa_vigente))
         / NULLIF(SUM(ct.cantidad * ct.tarifa_vigente), 0)) > 0.08
    AND NOT EXISTS (...)
  ```

- **Estado:** ✅ Operativo end-to-end con gpt-4o-mini.

### WF-06 — Forecast Rolling EWMA (`wf_06_forecast_rolling.json`)

- **Trigger:** Cron diario 05:30.
- **Flujo:** 3 queries encadenadas serialmente (histórico 25 días → pipeline OTs pendientes → budget) → Code "Calcular EWMA" (proyección central + P20/P80) → INSERT a `opex_forecasts` con mapeo explícito de 18 columnas → Code "Formatear Forecast Slack" + HTTP Request a `#opex-alertas` cuando se dispara A10.
- **Decisiones técnicas:**
  - `alwaysOutputData: true` en los 3 nodos query (evita romper la cadena cuando una query devuelve 0 filas).
  - Postgres Insert en `mappingMode: defineBelow` con 18 columnas explícitas (autoMap fallaba con flags internos `generar_alerta_A10/A8` que no existen en el schema).
- **Estado:** ✅ Refactor completo committeado (`3e8d563`). Validación final del flujo en curso.

### WF-07 — Cierre Mensual (`wf_07_monthly_close.json`)

- **Trigger:** Cron día 1 de cada mes a las 09:00.
- **Flujo:** Query agregada del mes anterior (ejecución, budget, alertas, top desviaciones, top contratistas, por zona, forecast día 20) → Code "Preparar Datos para IA" arma `prompt_ia` y CSVs de pivots → AI Agent + sub-node OpenAI gpt-4o-mini genera narrativa ejecutiva (3 párrafos, ≤250 palabras) → Code "Armar Reporte Final" recupera datos vía `$('Preparar Datos para IA').first().json`, monta `mensaje_slack` y `slack_blocks` (sección + divider + actions con botón "Aprobar cierre" / "Ver dashboard") → INSERT en `opex_closes` con `estado='borrador'` + HTTP Request a `#opex-cierre` (`C0AUXUFH1HU`).
- **Estado:** ✅ Refactor completo committeado (`44d8cef`). Cierre queda en `borrador` hasta aprobación humana.

### WF-08 — Feedback Loop / Cierre de Alertas (`wf_08_alert_feedback_loop.json`)

- **Trigger:** Webhook `POST /opex-close-alert` (llamado desde WF-04 al cerrar una alerta o desde dashboard).
- **Flujo:** ACK 200 inmediato + rama de procesamiento → Validar payload (`alert_id`, `veredicto`, `causa_raiz_*`, `monto_recuperado`) → Query la alerta con `causa_raiz_sugerida` (IA) → Code "Preparar Datos del Case" calcula `tiempo_resolucion_horas` y compara causa raíz IA vs humana (`ia_acerto`) → Postgres ejecuta UPDATE en `opex_alerts.estado` + INSERT en `opex_cases` con `RETURNING id, codigo_alerta` → Postgres recalcula `fp_rate` / `tp_rate` / `n_falsos_positivos` / `n_activaciones` en `opex_rules` (ventana 30 días) → Code "Evaluar Threshold" arma `slack_blocks` si `fp_rate ≥ 0.40` → If con config v2 → HTTP Request a `#opex-alertas` (`C0AVCTBV665`) avisando degradación de calidad.
- **Estado:** ✅ Refactor completo committeado (`44d8cef`). Webhook listo para integrarse desde WF-04.

### WF-09 — Recalibración Mensual (`wf_09_monthly_recalibration.json`)

- **Trigger:** Cron día 3 de cada mes a las 10:00 (después de cierre día 1 + revisión día 2).
- **Flujo:** Dos queries en paralelo (métricas reglas 3 meses + métricas globales del agente: MAE forecast, cobertura alertas útiles, tiempo mediano cierre, ahorro 3M, precisión IA) → Code "Calcular Propuestas" aplica reglas: si `fp_rate_3m ≥ 40%` y `casos ≥ 5` propone subir umbral (+30%) o z-score (+0.5); si `fp_rate < 10%` y `tp ≥ 3` confirma umbral → Code "Formatear Reporte" genera `slack_blocks` (header + KPIs vs metas + propuestas + actions "Aplicar todos" / "Ignorar") → HTTP Request a `#opex-alertas` → If `hay_cambios` → Code "Preparar Updates" genera SQL parametrizado (`UPDATE opex_rules SET <campo> = <valor>, version = version + 1...`) → Log en `opex_agent_log`.
- **Importante:** los UPDATEs **no se aplican automáticamente** — quedan preparados como queries y el log registra qué se propuso. La aplicación efectiva requiere acción manual o un futuro WF que reciba el botón "Aplicar todos" del Slack.
- **Estado:** ✅ Refactor completo committeado (`44d8cef`).

## A.4 Schema Supabase efectivo

Tablas operativas en uso (ver `Documentos analista opex/FASE_0_FUNDACIONES/00_supabase_schema.sql` y `00b_tarifario_or_patch.sql` para detalle):

- `opex_transactions` — transacciones ingestadas desde Metabase 66793 (columnas clave: `tx_id_fuente`, `ot_id`, `contratista_id`, `tipo_servicio`, `zona`, `fecha_tx`, `costo_total`, `cantidad`, `costo_unitario`, `tiene_acta_cierre`).
- `opex_tarifario` — tarifas vigentes por contratista/ítem/grupo OR (3 grupos × 67 ítems × 18 contratistas).
- `opex_or_mapping` — 23 ORs mapeados a sus grupos.
- `opex_budget` — presupuesto mensual por zona/contratista/categoría (vacío hasta crear el Sheet).
- `opex_baseline` — promedio móvil + desviación estándar por `(tipo_servicio, zona, contratista)` (recálculo semanal pendiente).
- `opex_rules` — catálogo de reglas A1–A14 con umbrales versionados, `fp_rate` y `tp_rate` evolutivos.
- `opex_alerts` — alertas tipificadas con severidad y estado (`open|ack|in_progress|resolved|false_positive`). **Append-only**, contiene `query_evidencia` y `snapshot_json` para trazabilidad forense.
- `opex_cases` — casos cerrados con `veredicto` ∈ `('confirmado','false_positive','pendiente','escalado')` (CHECK constraint), `causa_raiz_codigo`, `causa_raiz_texto`, `causa_raiz_ia`, `ia_acerto`, `monto_recuperado`, `tiempo_resolucion_horas`.
- `opex_approvals` — cola de aprobación (definida en schema pero **no se usa hoy**; WF-04 y WF-05 actualizan directamente `opex_alerts`/`opex_cases`).
- `opex_forecasts` — proyecciones rolling diarias (18 columnas mapeadas explícitamente desde WF-06).
- `opex_closes` — snapshot del cierre mensual (`narrativa_ejecutiva`, `top_drivers_json`, `pivot_zona_csv`, `pivot_contratista_csv`, `error_forecast_pct`, `estado='borrador'` hasta aprobación).
- `opex_agent_log` — bitácora de ejecuciones de cada workflow.
- `opex_config` — flags globales (incluye `agente_pausado` que WF-04 pone en `true` cuando el analista pulsa "Pausar").
- `get_tarifa_vigente(contratista_id, item_codigo, or_nombre, fecha, jornada)` — función SQL con incrementos por jornada.

> **Notación:** todas las tablas usan nombres en inglés (`opex_alerts`, `opex_cases`, etc.) según el schema en `00_supabase_schema.sql`.

## A.5 Decisiones de alcance modificadas

1. **Rama "Rechazar" eliminada de WF-04.** El diseño (sec. 9.1) preveía estado `rejected`. En la práctica el analista utiliza "Falso positivo" para descartar, evitando ambigüedad operativa.
2. **`opex_approvals` deprecada.** WF-05 originalmente insertaba en una cola intermedia; se eliminó el nodo "Crear en Cola de Aprobación" y la actualización se hace directa sobre `opex_alerts`.
3. **AI Agent reemplaza nodo LLM standalone.** El sub-nodo `lmChatGoogleGemini` / `lmChatOpenAi` solo expone puerto `ai_languageModel`, no `main`. El patrón productivo es **AI Agent + sub-node** conectados por `ai_languageModel`.
4. **Gemini → OpenAI gpt-4o-mini.** Cuota free-tier de Gemini se agotó en pruebas; gpt-4o-mini es barato (~$0.15 por millón de tokens input) y suficiente para clasificación de causa raíz y narrativa corta.
5. **Slack v2.2 nativo no se usa para Block Kit dinámico** (ver A.6).
6. **Budget pasa a ser Teórico calculado por el sistema (2026-04-27).** El diseño original asumía un Sheet poblado por Finanzas. El usuario decidió que el agente debe **calcular** el budget desde el backlog vigente (Metabase card 65209) + tarifa vigente, sin input humano. Implica nuevo WF-01b y deprecación de la rama Budget Sheet de WF-01. Detalle en A.10 y `Documentos analista opex/FASE_4_BUDGET_TEORICO/`.

## A.6 Patrones técnicos aprendidos

### Patrón 1 — Slack Block Kit dinámico vía HTTP Request

El nodo Slack v2.2 de n8n **rechaza arrays de blocks generados en runtime** (acepta solo blocks "estáticos" o un único string). Para enviar Block Kit con contenido dinámico:

```
[Code: Formatear Notificación Slack]
  → genera { channel, slack_blocks }
[HTTP Request → POST https://slack.com/api/chat.postMessage]
  Authentication: Header Auth (credential GciOWwHMTLVJJuAu)
  Body: { channel: {{$json.channel}}, blocks: {{$json.slack_blocks}} }
```

Este patrón está aplicado en WF-03, WF-05, WF-06 y se extenderá a WF-07 y WF-09.

### Patrón 2 — Switch v3.2 requiere config completa al importar JSON

El Switch v3.2 **ignora silenciosamente las condiciones** si faltan campos. Sin `mode`, `combinator`, `operator.name` u `options`, todos los items caen al Output 0 sin error. Config mínima:

```json
{
  "parameters": {
    "mode": "rules",
    "rules": {
      "values": [{
        "conditions": {
          "options": { "caseSensitive": true, "typeValidation": "loose", "version": 2 },
          "conditions": [{
            "leftValue": "={{ $json.campo }}",
            "rightValue": "valor",
            "operator": { "type": "string", "operation": "equals", "name": "filter.operator.equals" }
          }],
          "combinator": "and"
        },
        "renameOutput": true,
        "outputKey": "rama"
      }]
    },
    "options": { "fallbackOutput": "none" }
  }
}
```

Aplicado en WF-04 (y en cualquier futuro Switch). Síntoma característico: todo va a Output 0 aunque upstream genere valores diferentes.

### Patrón 3 — Cross-references en n8n con merges convergentes

Cuando varios detectores en paralelo se unen en un Merge/Combinar:

- Usar `$input.all()` (no `$('NodeName').all()`) — este último falla con "Node X hasn't been executed" si una rama upstream tuvo 0 items en el contexto del item actual.
- En Code nodes que necesitan recuperar el `alerta` original tras el AI Agent: `$('Combinar Resultados Detectores').item.json` — patrón usado en WF-05 "Enriquecer Alerta con IA".

### Patrón 4 — `alwaysOutputData: true` en queries encadenadas

Cuando una query devuelve 0 filas y otros nodos downstream necesitan ejecutarse igual, marcar `alwaysOutputData: true` en el nodo Postgres. Aplicado en los 3 nodos query de WF-06.

### Patrón 5 — Postgres Insert con mapeo explícito

Para tablas con columnas que no coinciden 1:1 con el JSON de entrada (caso típico: flags internos como `generar_alerta_A10`), usar `mappingMode: "defineBelow"` con un objeto `value` explícito. `autoMapInputData` falla con "Column X does not exist" si hay claves extra.

### Patrón 6 — Postgres Insert con `RETURNING` para encadenar datos

En WF-04 (rama Falso Positivo), el `RETURNING codigo_alerta` permite que el siguiente nodo acceda a `$json.codigo_alerta` directamente sin cross-references frágiles.

### Patrón 7 — Batch SQL para Metabase

WF-02 consolida ~26k filas de Metabase en 1 batch SQL (en lugar de N items individuales) usando un Code node que compone el INSERT. Evita OOM y reduce ~26k queries a 1.

## A.7 Errores recurrentes documentados

| Síntoma | Causa | Resolución |
|---|---|---|
| `opex_cases_veredicto_check` violation | Valor `'real_problem'` no permitido | Schema solo acepta `('confirmado','false_positive','pendiente','escalado')` — usar `'confirmado'` |
| Switch enruta todo a Output 0 | Falta `mode/combinator/operator.name` al importar JSON | Aplicar config completa A.6 patrón 2 |
| "Node X hasn't been executed" | Cross-reference frágil en merge convergente | Usar `$input.all()` en lugar de `$('X').all()` |
| Slack node v2.2 rechaza blocks dinámicos | Limitación del nodo nativo | Migrar a Code + HTTP Request (A.6 patrón 1) |
| Gemini API quota exceeded (`limit: 0`) | Free tier agotado | Migrar a OpenAI gpt-4o-mini |
| "Cannot assign to read only property 'name'" | Convergent paralelo sin items en una rama | Usar `$input.all()` |
| AI Agent reemplaza JSON downstream | Output del agente sustituye al item original | Recuperar contexto vía `$('NodeAnterior').item.json` en Code post-AI |
| Workflow se detiene en query con 0 filas | Comportamiento default Postgres node | `alwaysOutputData: true` |
| "Column X does not exist" en Insert | Flags internos no existentes en schema | `mappingMode: "defineBelow"` con mapeo explícito |
| SplitInBatches: salida incorrecta | Output 0 = done, Output 1 = loop | Conectar el procesamiento al Output 1 |
| Log Iteración con múltiples ítems upstream | `$('Split').item.json` falla | Usar `$input.first().json` |

## A.8 Estado operativo (snapshot 2026-04-27)

✅ **Refactor unificado completado en los 9 workflows.** Todos los WF productivos ya usan:
- Credencial Postgres `92nLfZ0IlzU004no` "Supabase Oráculo del Opex".
- Slack vía Code + HTTP Request `chat.postMessage` con Header Auth `GciOWwHMTLVJJuAu` (Block Kit dinámico).
- Switch/If con config v2 completa.
- `alwaysOutputData: true` donde aplica.
- AI Agent + sub-node OpenAI gpt-4o-mini para clasificación/narrativa.

| WF | Estado | Disparador | Notas |
|---|---|---|---|
| WF-01 | ✅ Operativo | Cron 06:00 diario | ~3,600 tarifas sincronizadas |
| WF-02 | ✅ Operativo | Cron horario | Pendiente reemplazar `METABASE_API_KEY_AQUI` |
| WF-03 | ✅ Operativo | Cron 07:30 | Botón "Abrir dashboard" sin URL |
| WF-04 | ✅ Operativo | Webhook Slack | 4 ramas (Aprobar / FP / Pausar / Ver cola) |
| WF-05 | ✅ Operativo | Cron horario | A1–A13 + A12 con `get_tarifa_vigente`, OpenAI gpt-4o-mini |
| WF-06 | ✅ Refactor committeado | Cron 05:30 | Validación end-to-end final en curso |
| WF-07 | ✅ Refactor committeado | Cron día 1 09:00 | Cierre queda en `borrador` |
| WF-08 | ✅ Refactor committeado | Webhook `/opex-close-alert` | Integración desde WF-04 pendiente |
| WF-09 | ✅ Refactor committeado | Cron día 3 10:00 | UPDATEs preparados pero no aplicados |

⏳ **Pendientes operativos:**
- Reemplazar `METABASE_API_KEY_AQUI` en WF-02.
- ~~Crear Sheet de Budget mensual y reconectar la rama Budget de WF-01.~~ **Deprecado el 2026-04-27** — el budget pasa a ser calculado por el sistema vía WF-01b (ver A.10).
- Diseñar e implementar WF-01b (Budget Teórico desde Pipeline) según A.10.
- Procesar card Metabase 19440 (histórico 12 meses) para construir matriz `(zona, tipo_servicio) → contratista_id`.
- Validar end-to-end de WF-06, WF-07, WF-08, WF-09 en n8n cloud (reimportar y ejecutar manual).
- Conectar el ACK de WF-04 hacia el webhook `/opex-close-alert` de WF-08 (hoy WF-04 actualiza directo; WF-08 es la versión "rica" con métricas).
- Botón "Abrir dashboard" en WF-03 / WF-07 sin `url` hasta que exista dashboard Metabase OPEX.
- Validación de signing secret en webhook WF-04 y WF-08.
- Aplicación efectiva de los UPDATEs propuestos por WF-09 (hoy solo se loguean): falta WF que reciba el botón "Aplicar todos" del Slack y ejecute las queries.
- Generación de PDF para cierre mensual (Puppeteer/Gotenberg) — diferida.
- Storage de evidencia en bucket externo — diferido.
- Configuración de credencial Claude API como fallback de OpenAI — diferida.

## A.9 Repositorio y versionado

- **Repo:** `https://github.com/hernanmanjarres-cmyk/Oraculo-del-opex.git`
- **Branch principal:** `main`
- **Estructura:**
  - `Documentos analista opex/FASE_0_FUNDACIONES/` — schemas SQL, setup credenciales, plantillas Sheets, runbooks.
  - `Documentos analista opex/FASE_1_WORKFLOWS/` — JSON de WF-01 a WF-04.
  - `Documentos analista opex/FASE_2_WORKFLOWS/` — JSON de WF-05 a WF-07.
  - `Documentos analista opex/FASE_3_EVOLUTIVO/` — JSON de WF-08 (feedback loop) y WF-09 (recalibración).
  - `Documentos analista opex/FASE_4_BUDGET_TEORICO/` — diseño de WF-01b (Budget Teórico desde Pipeline) y diccionario de cards Metabase 65209 / 19440.
  - `Documentos analista opex/DOCS_OPERATIVOS/` — runbooks operativos.
  - `metabase_cards_n8n_documentation.md` (raíz) — documentación de cards Metabase.

Cada workflow está versionado en JSON; los cambios productivos en n8n cloud se exportan al repo con commit descriptivo.

---

## A.10 Budget Teórico desde Pipeline (WF-01b en diseño)

**Detalle completo:** `Documentos analista opex/FASE_4_BUDGET_TEORICO/01_WF_01b_diseno.md`.

### Resumen

El usuario decidió el 2026-04-27 que el agente debe **calcular** el presupuesto OPEX en lugar de leerlo de un Sheet. Esto reemplaza la rama Budget de WF-01 y agrega un nuevo workflow (WF-01b) que combina:

- **Backlog activo** desde Metabase card **65209** (fronteras vigentes con costos estimados, banda y fase).
- **Tarifa vigente** desde la función Supabase `get_tarifa_vigente()`.
- **Asignación de contratista** derivada del histórico (Metabase card **19440**, últimos 12 meses).

### Reglas de negocio nuevas

- **Zonas canónicas:**
  - `centro` = ENEL CUNDINAMARCA.
  - `costa` = AFINIA CARIBE_MAR + AIRE CARIBE_SOL.
  - `interior` = el resto del país.
- **`tipo_servicio` canónico** (≠ `tipo_de_medida`): `VIPES`, `INST`, `NORM`, `LEGA`.
- **Bandas que entran al budget:** 🟢 `INSTALAR` y 🟡 `INSTALAR - MENOS PRIORITARIO`. Las bandas 🔴 y ⚪ se monitorean para análisis pero no suman al budget.
- **Ciclo cubierto:** Solo activación. Otras categorías OPEX (mantenimiento, calibración, telemedida) no entran a este motor.
- **Finanzas no participa** en este agente: no hay aprobaciones humanas sobre el budget calculado.

### Pendientes para implementar

1. Procesar card 19440 (~27.4 MB) para construir matriz `(zona, tipo_servicio) → contratista_id`.
2. Decidir dónde persistir esa matriz (`opex_zona_contratista_default` vs JSON en `opex_config`).
3. Confirmar mapeo `fase_actual` → `tipo_servicio` para los cuatro códigos canónicos (NORM en particular).
4. Definir `categoria_contable` para Budget Teórico.
5. Construir y testear WF-01b en n8n cloud.
6. Limpieza: decidir si la rama Budget Sheet de WF-01 se elimina del JSON o queda desconectada como referencia histórica.

