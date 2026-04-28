# Plan Ejecutivo del Proyecto Agente OPEX — BIA Energy

**Versión:** 1.0 — 28 de abril de 2026
**Autor:** Daniel Moreno (con apoyo de Claude)
**Documento prerrequisito:** `Reencuadre_Agente_OPEX_BIA.md`
**Estado:** Plan ejecutable. Cada paso tiene entregable verificable.

---

## Cómo leer este documento

Este documento responde a **qué hay que hacer y cómo se hace**, paso a paso. Está organizado en nueve partes:

- **Partes I–II** establecen el contexto técnico y la fundación de datos.
- **Partes III–V** definen el cerebro, los workflows y la integración Slack.
- **Parte VI** es el plan día a día de las tres semanas.
- **Partes VII–VIII** cubren validación, operación y mantenimiento.
- **Parte IX** son apéndices ejecutables (system prompt completo, DDL, etc.).

Si vas a ejecutar el proyecto: lee de corrido la Parte I, luego salta directo a la Parte VI y usa las demás como referencia cuando las necesites.

---

# PARTE I — Marco del proyecto

## 1. Objetivo medible

Tener, al cabo de **3 semanas calendario** desde el día de inicio, un agente conversacional en Slack que:

1. Responda correctamente las **5 preguntas gerenciales clave** (definidas en §17.1) con datos de Metabase en tiempo real.
2. Envíe **un mensaje matinal diario** con 0–3 hallazgos, donde al menos 70% de los días sea calificado como útil por el FOPS Manager.
3. Recuerde y referencie **decisiones previas del Manager** en al menos un caso real durante la semana 3.
4. Razone sobre **OTs como composiciones de ítems del tarifario** comparándolas contra vecindarios jerárquicos.

Si al final de las 3 semanas estos cuatro puntos no se cumplen, **se itera antes de añadir capacidades**. No se construye el mes 2 sin pasar el mes 1.

## 2. Recursos requeridos

| Recurso | Cantidad | Quién | Cuándo |
|---|---|---|---|
| Tiempo de Daniel (lead técnico) | ~15 h/semana × 3 semanas | Daniel | Semanas 1–3 |
| Tiempo del FOPS Manager | 30 min/semana × 3 semanas | Por confirmar | Semanas 1–3 |
| Acceso a Metabase con permisos de API | Ya existe | Daniel | Día 1 |
| Acceso a Supabase con permisos DDL | Ya existe | Daniel | Día 1 |
| Instancia n8n operativa | Ya existe | Daniel | Día 1 |
| Workspace Slack con permisos de bot | Por confirmar | Por confirmar | Día 1 |
| API key de OpenAI o Anthropic | Por confirmar | Daniel | Día 1 |
| Presupuesto LLM | ~USD 50–150 / mes | Aprobación | Día 1 |

## 3. Bloqueadores que deben resolverse antes del día 1

Estos son hard blockers. Si no se resuelven, el cronograma se mueve.

1. **Identificación nominal del FOPS Manager** que actuará como usuario principal y comprometerá 30 min/semana.
2. **Decisión de canal Slack**: DM directo con el Manager o canal `#opex-fops` con audiencia ampliada.
3. **API key de Metabase real** (reemplazar el placeholder `METABASE_API_KEY_AQUI` que arrastra el proyecto).
4. **Confirmación de columnas en Metabase** que mapean a los conceptos del modelo: `tipo_servicio`, `tipo_medida`, `zona`, `ciudad`, `OR`, `contratista_id`, `items_aplicados[]`.
5. **Decisión sobre proveedor de LLM**: OpenAI (lo que está hoy en n8n) o Anthropic (Claude). Recomendación: Claude Sonnet 4 por mejor seguimiento de instrucciones complejas y razonamiento sobre tablas.

## 4. Arquitectura objetivo (recordatorio del re-encuadre)

```
METABASE  ──[hourly]──►  WF-A: Ingesta  ──►  SUPABASE  ◄──►  WF-B: Cerebro (AI Agent)  ◄──►  SLACK
                                                                    ▲
                                                                    │
                                                              WF-C: Cron 07:30
```

Tres workflows. Seis tablas. Un cerebro. Un canal.

---

# PARTE II — Fundación técnica

## 5. Estructura de datos en Supabase

### 5.1 DDL completo

El DDL completo está en el **Apéndice A**. Aquí va el resumen lógico:

| Tabla | Propósito | Cardinalidad esperada |
|---|---|---|
| `opex_ots_raw` | Una fila por OT sincronizada desde Metabase | ~10k–50k filas/mes |
| `opex_items_aplicados` | Una fila por (OT, ítem). Detalle de composición | ~30k–200k filas/mes |
| `opex_tarifario_vigente` | Catálogo histórico versionado de ítems | ~500–2000 ítems × N versiones |
| `opex_costo_sales` | Costo presupuestado por Sales por frontera | ~5k–20k filas/mes |
| `opex_decisions` | Memoria conversacional persistente | ~50–200 filas/mes |
| `opex_insights_log` | Cada insight emitido y su outcome | ~20–100 filas/mes |

### 5.2 Vistas materializadas

Tres vistas materializadas con refresh diario hacen el trabajo pesado de estadísticos:

1. **`mv_opex_vecindarios`** — Para cada combinación posible de (nivel jerárquico, tipo_medida, tipo_servicio), calcula `n`, P25, P50, P75, P90, P99 del costo total de OT en ventana 6 meses.
2. **`mv_opex_items_stats_peers`** — Mismos percentiles pero por (nivel, item_codigo) — para detección de outliers a nivel de ítem.
3. **`mv_opex_items_stats_self`** — Mismos percentiles por (contratista_id, nivel, item_codigo) — autoreferencia del contratista.

El SQL completo está en el **Apéndice B**.

### 5.3 Reglas de mantenimiento

- WF-A refresca `mv_opex_vecindarios` y compañía **una vez al día a las 03:00 AM** (después de la última sync horaria del día anterior).
- Las tablas raw (`opex_ots_raw`, `opex_items_aplicados`) se sincronizan cada hora con un patrón de **upsert por `ot_id`** + soft delete cuando una OT desaparece de Metabase.
- `opex_tarifario_vigente` mantiene historial: cuando una tarifa cambia, no se sobreescribe, se inserta nueva versión con `valid_from` / `valid_to`.

## 6. Variables de entorno y secretos

Declarar en n8n como credentials, **no en código**:

| Nombre | Tipo | Uso |
|---|---|---|
| `METABASE_API_KEY` | Header Auth | Queries a Metabase |
| `METABASE_BASE_URL` | URL | Endpoint de Metabase |
| `SUPABASE_URL` | URL | Conexión Supabase |
| `SUPABASE_SERVICE_KEY` | Service role key | DDL y writes |
| `LLM_API_KEY` | API Key | OpenAI o Anthropic |
| `SLACK_BOT_TOKEN` | Bearer | Bot de Slack (`xoxb-...`) |
| `SLACK_SIGNING_SECRET` | Secret | Verificación de firmas |
| `SLACK_FOPS_CHANNEL` | String | ID del canal o DM |

## 7. Cards Metabase requeridas

Antes de implementar WF-A, hay que confirmar (o crear) estas cards en Metabase. Cada una debe exponer las columnas indicadas:

| Card | Columnas críticas | Granularidad |
|---|---|---|
| **OPEX_OTS** | `ot_id`, `fecha_creacion`, `fecha_cierre`, `contratista_id`, `tipo_servicio`, `tipo_medida`, `ciudad`, `zona`, `OR`, `frontera_id`, `costo_total`, `estado`, `tiene_acta` | Una fila por OT |
| **OPEX_ITEMS_OT** | `ot_id`, `item_codigo`, `item_nombre`, `cantidad`, `valor_unitario`, `valor_total` | Una fila por ítem aplicado |
| **OPEX_TARIFARIO** | `item_codigo`, `item_nombre`, `tarifa_unitaria`, `contratista_id`, `valid_from`, `valid_to` | Una fila por (ítem, contratista, versión) |
| **OPEX_COSTO_SALES** | `frontera_id`, `mes`, `costo_proyectado`, `tipo_servicio` | Una fila por (frontera, mes) |

Si alguna card no existe con esas columnas, **el día 1 se crea** o se ajusta el modelo del agente para usar lo que sí está disponible.

---

# PARTE III — El cerebro del agente

## 8. System prompt completo

El system prompt completo está en el **Apéndice C**. Su estructura:

1. **Identidad y rol** — quién es, para quién trabaja, en qué empresa.
2. **Reglas de negocio embebidas** — destilado del SKILL `analista-opex` y del marco funcional.
3. **Modelo de validación de OT** — la jerarquía de vecindarios y la lente dual self/peers.
4. **Tools disponibles y cuándo usarlas** — guía de razonamiento.
5. **Formato de respuesta** — cómo escribir en Slack, qué citar, qué no.
6. **Comportamiento ante incertidumbre** — qué hacer cuando faltan datos.
7. **Memoria conversacional** — cómo y cuándo guardar/recuperar decisiones.

## 9. Tools del agente

El agente tiene exactamente cinco tools. Cada una con signature estricta.

### 9.1 `query_supabase(sql_template, params)`
Ejecuta SQL parametrizado contra vistas y tablas de Supabase. El agente decide qué consultar. Solo lectura.

**Restricciones:** read-only role; queries con `LIMIT` obligatorio (default 100, max 1000); sin DDL ni writes.

### 9.2 `query_metabase(card_id, params)`
Consulta una card específica de Metabase con filtros. Para datos que aún no están sincronizados o validación cruzada.

### 9.3 `get_neighborhood_stats(ot_id)`
Función de alto nivel. Recibe una OT, devuelve:
- Vecindario seleccionado (nivel jerárquico) y `n`.
- Percentiles self (contratista vs sí mismo).
- Percentiles peers (contratista vs pares).
- Descomposición por ítem: cuáles aportan al exceso/defecto.
- Composición atípica detectada.

### 9.4 `save_decision(context, manager_response, action_taken)`
Guarda en `opex_decisions` cuando el Manager toma postura sobre algo. El agente la invoca cuando detecta una respuesta significativa.

### 9.5 `get_recent_decisions(filter)`
Recupera decisiones recientes filtradas por contratista, zona, ítem, etc. El agente la invoca al inicio del razonamiento cuando un patrón se repite.

Las signatures completas están en el **Apéndice D**.

## 10. Patrones de razonamiento esperados

El system prompt instruye al agente a seguir este patrón cuando recibe una pregunta:

```
1. ¿Qué entidad pregunta el usuario? (OT, contratista, zona, mes, ítem)
2. ¿Hay decisiones previas relevantes? → get_recent_decisions
3. ¿Qué dato necesito? → query_supabase o get_neighborhood_stats
4. ¿El dato es suficiente o necesito más? → segunda query si es necesario
5. ¿Cuál es la lectura interpretativa? (no solo la cifra)
6. ¿Hay acción sugerida? (sí, salvo que sea consulta puramente informativa)
7. Responder en formato Slack, citando nivel de vecindario y n.
```

El agente debe **citar siempre la fuente cuantitativa**: qué query ejecutó, qué nivel jerárquico usó, cuántas muestras tenía. Esto previene alucinación y le da trazabilidad al Manager.

---

# PARTE IV — Workflows n8n

## 11. WF-A: Ingesta horaria

**Trigger:** Cron cada hora en minuto :05.

**Secuencia de nodos:**

1. **Set Variables** — define ventana de sync (`now() - 2 hours` para evitar perder datos por latencia).
2. **HTTP Request → Metabase** — llama card `OPEX_OTS` con filtro de `fecha_actualizacion > $ventana`.
3. **Loop over OTs** — itera el resultado.
4. **HTTP Request → Metabase (por OT)** — llama card `OPEX_ITEMS_OT` con `ot_id`.
5. **Postgres → Supabase: Upsert OT** — `INSERT ... ON CONFLICT (ot_id) DO UPDATE`.
6. **Postgres → Supabase: Replace Items** — `DELETE FROM opex_items_aplicados WHERE ot_id = $1; INSERT ...`.
7. **Postgres → Supabase: Upsert Costo Sales** (cuando aplique, una vez al día).
8. **Postgres → Supabase: Upsert Tarifario** (cuando aplique, una vez al día).
9. **(Una vez al día a las 03:00) Refresh Materialized Views** — `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_opex_vecindarios; ...`.
10. **Error handler** — captura excepciones y publica en canal `#opex-alertas-tecnicas`.

**Idempotencia:** todos los upserts son idempotentes. Si el workflow corre dos veces seguidas, no hay duplicados.

**Métricas a loggear:**
- Filas sincronizadas por corrida.
- Latencia total.
- Errores por endpoint.

## 12. WF-B: Cerebro conversacional

**Trigger:** Slack Events API webhook (`message.im` y `app_mention`).

**Secuencia de nodos:**

1. **Webhook receiver** — recibe evento Slack.
2. **Filter** — descarta mensajes del propio bot, mensajes editados, mensajes en hilos no relevantes.
3. **Load Context** — Postgres query a `opex_decisions` últimas 50, a `opex_insights_log` últimos 7 días.
4. **AI Agent node** — con:
   - System prompt cargado desde archivo (Apéndice C).
   - User message: el texto de Slack.
   - Context: las decisiones e insights recientes.
   - Tools registradas: las 5 del §9.
5. **Tool execution loop** — el agent llama tools, n8n las ejecuta, devuelve resultado, el agent itera.
6. **Format response** — conversión de la respuesta del agent a Block Kit de Slack.
7. **Post to Slack** — `chat.postMessage` al canal/DM original.
8. **Log interaction** — guarda en `opex_insights_log` la conversación completa.

**Manejo de errores:**
- Si el LLM falla: respuesta estándar "tengo problemas técnicos, intenta en 1 minuto" + alerta interna.
- Si una tool falla: el agent recibe el error como tool_result y decide cómo proceder (típicamente reformular).
- Timeout total: 60 segundos. Si excede, mensaje "tu pregunta requiere análisis profundo, te respondo en breve" + procesamiento async.

## 13. WF-C: Cron matinal

**Trigger:** Cron días hábiles (L–V) a las 07:30 AM hora Colombia.

**Secuencia de nodos:**

1. **Cron trigger** — 07:30 L–V.
2. **Skip si feriado** — consulta tabla `dias_no_habiles` (a crear) o lista hardcoded.
3. **Load Context** — `opex_decisions` últimas 50, `opex_insights_log` última semana.
4. **AI Agent node** — con system prompt + el siguiente user message:
   > Revisa la operación de las últimas 24 horas. Si encuentras 1 a 3 hallazgos de nivel gerencial (no operativo), preséntalos con cifra, lectura y acción. Si no hay nada digno de reporte, responde exactamente "sin novedad relevante".
5. **Branch on response** — si contiene "sin novedad relevante" → log y termina; si no → publica.
6. **Post to Slack** (canal o DM).
7. **Log insight** en `opex_insights_log` con tipo `morning_brief`.

**Importante:** el cron NO usa una lista predefinida de qué revisar. El agente decide. Esto es deliberado: forzar que el cerebro razone, no que ejecute un checklist.

---

# PARTE V — Integración Slack

## 14. Configuración del bot

Crear app Slack con estos scopes:

**Bot Token Scopes:**
- `app_mentions:read`
- `channels:history` (si va a canal)
- `chat:write`
- `im:history`
- `im:read`
- `im:write`
- `users:read`

**Event Subscriptions:**
- `app_mention`
- `message.im`

**Slash Commands (opcional, mes 2):**
- `/opex` para queries rápidas estilo CLI.

## 15. Manejo de canales y DMs

Si la decisión es **DM directo con FOPS Manager**: configurar `SLACK_FOPS_CHANNEL` con el `user_id` del Manager y abrir IM al primer mensaje.

Si la decisión es **canal `#opex-fops`**:
- Definir audiencia (Manager + Director + analista OPEX si existe).
- Política explícita: respuestas a mentions van al canal; preguntas en hilo se quedan en hilo.
- Confidencialidad: ningún dato individual de empleados, ningún costo unitario de contratista revelado a audiencia ampliada sin autorización.

**Recomendación:** empezar en DM en semana 1, evaluar mover a canal en semana 3 según validación.

## 16. Configuración de Block Kit

Para la respuesta matinal y para insights estructurados, usar Block Kit con esta plantilla:

```
[Header]   Resumen OPEX — DD/MM/AAAA
[Divider]
[Section]  *Hallazgo 1: [título]*
           [interpretación + cifra]
[Context]  Atribución: [drivers] · n=[muestras] · nivel: [vecindario]
[Divider]
[Section]  *Hallazgo 2: ...*
[Divider]
[Actions]  [No hay botones de aprobación. Solo "Ver detalle" que abre hilo.]
```

Sin emojis decorativos. Sin colores chillones. Tono ejecutivo.

---

# PARTE VI — Plan de ejecución 3 semanas

## 17. Semana 1 — Fundación de datos + cerebro mínimo

**Meta de la semana:** El agente responde 5 queries gerenciales en lenguaje natural con datos reales en DM.

### 17.1 Las 5 queries de aceptación

Estas son las preguntas que el Manager hará en Slack al final de la semana 1. El agente debe responder correctamente.

1. *"¿Cuál es el CAC de [zona] esta semana?"*
2. *"Top 5 OTs con mayor desviación esta semana en [zona]"*
3. *"Forecast de OPEX a cierre de mes por contratista"*
4. *"Delta Sales vs real MTD por zona"*
5. *"Composición de costos del Contratista [X] últimos 30 días"*

### 17.2 Día por día

| Día | Entregable | Verificación |
|---|---|---|
| **Lun** | DDL de las 6 tablas en Supabase ejecutado. Variables de entorno configuradas en n8n. Slack app creada y conectada. | `\d+ opex_ots_raw` retorna estructura correcta. Bot responde "hola" en DM. |
| **Mar** | WF-A v0: ingesta de OTs y items_aplicados (no tarifario, no costo Sales todavía). Una corrida manual exitosa. | `SELECT COUNT(*) FROM opex_ots_raw` > 0. `SELECT COUNT(*) FROM opex_items_aplicados` > 0. |
| **Mié** | WF-A completo (incluye tarifario y costo Sales). Cron horario activado. Vistas materializadas creadas y refrescadas. | Después de 2 horas, hay sync incremental. `SELECT * FROM mv_opex_vecindarios LIMIT 5` retorna estadísticos coherentes. |
| **Jue** | WF-B v0: cerebro conectado con system prompt v1 + 3 tools (`query_supabase`, `get_neighborhood_stats`, `query_metabase`). Pruebas de queries 1, 2, 5. | Las 3 queries responden con datos reales y citan nivel de vecindario. |
| **Vie** | WF-B completo (5 tools). Pruebas de queries 3 y 4 (forecast y delta Sales). Sesión de 30 min con FOPS Manager probando las 5 queries. | Manager confirma que ≥4 de 5 queries son útiles. Feedback recogido. |

### 17.3 Riesgos de la semana 1

- **Datos en Metabase no exponen las columnas que el modelo necesita.** Mitigación día 1: lista de columnas confirmadas vs. faltantes; ajustar agente o crear card nueva.
- **Volumen histórico insuficiente para vecindarios finos.** Mitigación: el modelo ya cae automáticamente a niveles agregados; reportar `n` en cada respuesta para que sea visible al Manager.
- **El Manager no puede hacer la sesión del viernes.** Mitigación: reagendar máximo al lunes siguiente; no avanzar a semana 2 sin validación.

## 18. Semana 2 — Iniciativa controlada (modo push)

**Meta de la semana:** El agente envía un mensaje matinal útil, sin ruido.

### 18.1 Día por día

| Día | Entregable | Verificación |
|---|---|---|
| **Lun** | WF-C v0: cron 07:30 con prompt de resumen ejecutivo. Primera corrida observada en vivo. | Mensaje publicado en Slack a las 07:32. |
| **Mar** | Iteración del prompt según feedback del Manager (mensaje del Lun). Segunda corrida. | Manager califica utilidad del mensaje (1–5). |
| **Mié** | Tabla `opex_insights_log` poblándose correctamente. Mensaje del Mié. | `SELECT * FROM opex_insights_log` muestra contexto, query, output, calificación. |
| **Jue** | Lógica de "sin novedad relevante" probada (forzar día sin hallazgos manipulando ventana de revisión). | El agente envía "sin novedad relevante" cuando corresponde. |
| **Vie** | Mensaje del Vie + sesión de revisión semanal con Manager. | Manager confirma utilidad ≥3/5 en al menos 3 de los 5 días. |

### 18.2 Calidad del mensaje matinal

Un mensaje **útil** cumple estos criterios:

- Tiene 0–3 hallazgos. Nunca más de 3.
- Cada hallazgo cabe en 4 líneas.
- Cita cifras concretas, no adjetivos vagos.
- Atribuye causa cuando puede (qué ítem, qué contratista, qué zona).
- Sugiere acción específica (no genérica).
- Si no hay nada útil, dice "sin novedad relevante" (no inventa).

Un mensaje **inútil** comparte estos antipatrones:

- Repite información que el Manager ya sabe.
- Reporta ruido estadístico (n<30 sin advertirlo).
- Da listas de OTs sin interpretación.
- Usa lenguaje de alerta automatizada ("se detectó anomalía tipo A2 en bucket X").
- Sugiere acciones genéricas tipo "revisar el caso".

### 18.3 Si la calidad no llega a 70%

No avanzar a semana 3. Iterar el system prompt y/o ajustar el prompt del cron. La causa más probable es:
- Prompt demasiado abierto → resultados dispersos.
- Prompt demasiado cerrado → resultados repetitivos.
- Datos insuficientes → el agente reporta cualquier cosa.

## 19. Semana 3 — Memoria conversacional

**Meta de la semana:** El agente recuerda decisiones previas y las usa.

### 19.1 Día por día

| Día | Entregable | Verificación |
|---|---|---|
| **Lun** | Tool `save_decision` activa. Cada respuesta significativa del Manager se registra. | `SELECT * FROM opex_decisions` muestra entradas nuevas. |
| **Mar** | Tool `get_recent_decisions` integrada al razonamiento (system prompt actualizado). | Trace del agente muestra que invoca `get_recent_decisions` antes de responder. |
| **Mié** | Caso de prueba: forzar un patrón repetido y verificar que el agente lo conecta. | El agente menciona la decisión previa en su respuesta. |
| **Jue** | Refinamiento del filtro de decisiones (no recordar trivialidades). | Falsos positivos de memoria <20%. |
| **Vie** | Sesión de cierre con Manager. Revisión de todos los criterios de éxito. Decisión go/no-go para mes 2. | Documento de cierre firmado: qué funcionó, qué no, qué sigue. |

### 19.2 Qué se considera "decisión guardable"

El agente NO guarda todo. Una decisión se guarda solo si cumple uno de estos criterios:

- El Manager toma postura concreta ("escalar", "descontar", "aprobar", "ignorar por X razón").
- El Manager pide una acción de seguimiento ("recuérdame revisar esto la próxima semana").
- El Manager corrige al agente ("no, este caso no es así porque...").
- El Manager establece una regla nueva ("en esta zona el ítem 43 sí es esperable").

NO se guarda: confirmaciones simples ("ok", "gracias"), preguntas, pedidos de aclaración.

---

# PARTE VII — Testing y validación

## 20. Tests de aceptación detallados

### 20.1 Test 1: Coherencia de cifras

Al final de cada semana, el Manager elige una OT al azar mencionada por el agente. Daniel valida manualmente en Metabase:
- ¿La OT existe?
- ¿El costo total coincide?
- ¿Los ítems aplicados coinciden?
- ¿El vecindario seleccionado tiene realmente `n` muestras?
- ¿Los percentiles son matemáticamente correctos?

**Criterio:** 100% de coherencia. Una sola discrepancia es bloqueante y debe entenderse antes de avanzar.

### 20.2 Test 2: Razonamiento sobre composición

Pregunta de prueba: *"¿Por qué la OT-XXXXX está alta?"*

Respuesta correcta debe contener:
- Cifra del exceso vs mediana del vecindario.
- Atribución por ítem (cuáles aportan cuánto).
- Comparación self vs peers para los ítems críticos.
- Hipótesis de causa.
- Acción sugerida.

**Criterio:** los 5 elementos presentes en el 80% de los casos.

### 20.3 Test 3: Ausencia de alucinación

Pregunta trampa: *"Muéstrame las OTs del Contratista Ω en zona ficticia."* (Ω no existe.)

Respuesta correcta: el agente reconoce que no encuentra el contratista y lo dice. NO inventa OTs.

**Criterio:** 0 alucinaciones detectadas en 20 pruebas controladas.

### 20.4 Test 4: Memoria conversacional

Setup: el Lun el Manager le dice al agente "el contratista Alfa cobra ítem 43 elevado por zona difícil real, no descontar".

El Vie, el agente detecta otro caso de Alfa con ítem 43 elevado.

Respuesta correcta: el agente menciona la decisión del Lun y NO repite la alerta.

**Criterio:** memoria activa en al menos 1 caso real durante semana 3.

## 21. Plan de rollback

Si en cualquier momento el agente genera daño (recomendación equivocada que se ejecutó, dato confidencial expuesto, etc.):

1. **Inmediato (5 min):** Desactivar WF-B y WF-C en n8n. El bot deja de responder.
2. **Comunicación (15 min):** Mensaje al canal/DM explicando pausa temporal.
3. **Diagnóstico (mismo día):** Revisar logs de `opex_insights_log` para identificar qué falló.
4. **Corrección (24–48 h):** Ajuste de prompt/tool/dato según corresponda.
5. **Reanudación supervisada:** Reactivar con observación cercana por 48 horas.

WF-A (ingesta) puede seguir corriendo en pausa de WF-B/C. No afecta nada externo.

---

# PARTE VIII — Operación post-MVP

## 22. Monitoreo y observabilidad

Crear un canal `#opex-bot-salud` (privado, solo Daniel y Manager) con estos eventos automáticos:

- Falla de WF-A → reportar al instante.
- Latencia de WF-A > 5 min → reportar.
- Falla de LLM call → reportar después de 3 fallas seguidas.
- Mensaje matinal NO enviado en horario → reportar a las 08:00.
- Volumen de queries del Manager (resumen semanal cada lunes 09:00).

Crear dashboard simple en Metabase o Supabase Studio con:

- Queries por semana (uso del agente).
- Calificaciones promedio (utilidad de respuestas).
- Latencia media de respuesta.
- Costo LLM acumulado.

## 23. Mantenimiento del system prompt

El system prompt vive en un archivo versionado en Git (recomendado) o en un nodo de n8n.

**Ciclo de actualización:**
- Cambios menores (corrección de instrucción, ejemplo nuevo): cualquier semana, en revisión semanal.
- Cambios estructurales (nueva sección, nueva tool): solo en cierre de mes con regresión completa de los 4 tests.
- Cambios de reglas de negocio (proviene de un cambio real en el manual de OPEX): inmediato, con notificación al Manager.

**Antipatrón a evitar:** que el prompt crezca indefinidamente añadiendo casos edge. Si el prompt supera ~3000 tokens, refactorizar dividiendo en system prompt + documentos consultables vía tool.

## 24. Iteraciones planificadas mes 2–3

**Mes 2 (con MVP estable):**
- Ampliar audiencia: agregar a canal `#opex-fops` con usuarios secundarios.
- Añadir capacidad de generar el **informe mensual visual** para Gerencia/VP (lo que era WF-07).
- Integrar **OPEX recuperado** vía conexión a sistema de CS/CX/Finanzas (la 5ª arista del re-MVP que dejamos fuera).

**Mes 3 (con audiencia ampliada):**
- Habilitar conciliación semanal con contratistas como capacidad invocable.
- Añadir slash command `/opex` para queries rápidas tipo CLI.
- Evaluar reactivar WF-09 (recalibración) ahora con 3 meses de data conversacional real.

**Lo que sigue archivado hasta nuevo aviso:**
- Sistema de aprobaciones por alerta individual.
- Las 14 reglas A1–A14 tipificadas.
- Recalibración automática de thresholds.

## 25. Criterios para declarar éxito del MVP

Al final de las 3 semanas, se declara éxito si:

1. ✅ Las 5 queries gerenciales se responden correctamente (test §20.1 + §17.1).
2. ✅ ≥70% de los mensajes matinales son útiles (test §18.2).
3. ✅ ≥1 caso de memoria conversacional funcionando (test §20.4).
4. ✅ 0 alucinaciones detectadas (test §20.3).
5. ✅ ≥1 acción concreta del Manager originada por insight del agente.
6. ✅ El Manager confirma por escrito que quiere continuar al mes 2.

Si 5 de 6 se cumplen → éxito, avanzar a mes 2.
Si 3–4 se cumplen → iteración de 2 semanas extra antes de avanzar.
Si <3 → revisión profunda de modelo y fundación de datos antes de seguir.

---

# PARTE IX — Apéndices

## Apéndice A — DDL completo de Supabase

```sql
-- =====================================================
-- AGENTE OPEX BIA — Esquema Supabase v1.0
-- =====================================================

-- Ejecutar como service_role.

-- ---------- TABLA: opex_ots_raw ----------
CREATE TABLE IF NOT EXISTS opex_ots_raw (
    ot_id              TEXT PRIMARY KEY,
    fecha_creacion     TIMESTAMPTZ NOT NULL,
    fecha_cierre       TIMESTAMPTZ,
    contratista_id     TEXT NOT NULL,
    tipo_servicio      TEXT NOT NULL,        -- INST, NORM, MANT, etc.
    tipo_medida        TEXT NOT NULL,        -- DIRECTA, SEMIDIRECTA, INDIRECTA
    ciudad             TEXT,
    zona               TEXT,
    operador_red       TEXT,                 -- OR
    frontera_id        TEXT,
    costo_total        NUMERIC(15,2) NOT NULL,
    estado             TEXT,                 -- ABIERTA, CERRADA, ANULADA
    tiene_acta         BOOLEAN DEFAULT FALSE,
    sincronizado_en    TIMESTAMPTZ DEFAULT NOW(),
    metabase_raw       JSONB                 -- payload original de Metabase
);

CREATE INDEX idx_ots_contratista     ON opex_ots_raw(contratista_id);
CREATE INDEX idx_ots_fecha_creacion  ON opex_ots_raw(fecha_creacion);
CREATE INDEX idx_ots_zona_medida     ON opex_ots_raw(zona, tipo_medida, tipo_servicio);
CREATE INDEX idx_ots_or_medida       ON opex_ots_raw(operador_red, tipo_medida, tipo_servicio);
CREATE INDEX idx_ots_ciudad_medida   ON opex_ots_raw(ciudad, tipo_medida, tipo_servicio);

-- ---------- TABLA: opex_items_aplicados ----------
CREATE TABLE IF NOT EXISTS opex_items_aplicados (
    id                BIGSERIAL PRIMARY KEY,
    ot_id             TEXT NOT NULL REFERENCES opex_ots_raw(ot_id) ON DELETE CASCADE,
    item_codigo       TEXT NOT NULL,
    item_nombre       TEXT,
    cantidad          NUMERIC(10,3) NOT NULL DEFAULT 1,
    valor_unitario    NUMERIC(15,2) NOT NULL,
    valor_total       NUMERIC(15,2) NOT NULL,
    sincronizado_en   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_items_ot       ON opex_items_aplicados(ot_id);
CREATE INDEX idx_items_codigo   ON opex_items_aplicados(item_codigo);

-- ---------- TABLA: opex_tarifario_vigente ----------
CREATE TABLE IF NOT EXISTS opex_tarifario_vigente (
    id                BIGSERIAL PRIMARY KEY,
    item_codigo       TEXT NOT NULL,
    item_nombre       TEXT NOT NULL,
    contratista_id    TEXT NOT NULL,
    tarifa_unitaria   NUMERIC(15,2) NOT NULL,
    valid_from        DATE NOT NULL,
    valid_to          DATE,                  -- NULL = vigente
    sincronizado_en   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (item_codigo, contratista_id, valid_from)
);

CREATE INDEX idx_tarifario_lookup ON opex_tarifario_vigente(item_codigo, contratista_id, valid_from, valid_to);

-- ---------- TABLA: opex_costo_sales ----------
CREATE TABLE IF NOT EXISTS opex_costo_sales (
    id                  BIGSERIAL PRIMARY KEY,
    frontera_id         TEXT NOT NULL,
    mes                 DATE NOT NULL,        -- primer día del mes
    tipo_servicio       TEXT,
    costo_proyectado    NUMERIC(15,2) NOT NULL,
    sincronizado_en     TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (frontera_id, mes, tipo_servicio)
);

-- ---------- TABLA: opex_decisions ----------
CREATE TABLE IF NOT EXISTS opex_decisions (
    id                BIGSERIAL PRIMARY KEY,
    creado_en         TIMESTAMPTZ DEFAULT NOW(),
    contexto          TEXT NOT NULL,         -- qué se le preguntó al Manager
    respuesta_manager TEXT NOT NULL,         -- qué respondió textualmente
    accion            TEXT,                  -- ESCALAR, DESCONTAR, APROBAR, IGNORAR, REGLA_NUEVA
    contratista_id    TEXT,
    zona              TEXT,
    item_codigo       TEXT,
    ot_id             TEXT,
    activa            BOOLEAN DEFAULT TRUE,  -- las "reglas nuevas" siguen vigentes hasta revocarse
    metadatos         JSONB
);

CREATE INDEX idx_decisions_contratista ON opex_decisions(contratista_id) WHERE activa;
CREATE INDEX idx_decisions_zona        ON opex_decisions(zona) WHERE activa;
CREATE INDEX idx_decisions_item        ON opex_decisions(item_codigo) WHERE activa;
CREATE INDEX idx_decisions_creado      ON opex_decisions(creado_en DESC);

-- ---------- TABLA: opex_insights_log ----------
CREATE TABLE IF NOT EXISTS opex_insights_log (
    id                BIGSERIAL PRIMARY KEY,
    creado_en         TIMESTAMPTZ DEFAULT NOW(),
    tipo              TEXT NOT NULL,         -- 'morning_brief', 'query_response', 'proactive'
    canal_slack       TEXT,
    user_message      TEXT,
    agent_response    TEXT,
    tools_invocadas   JSONB,                 -- [{"name": "...", "input": {...}, "output": {...}}]
    duracion_ms       INTEGER,
    util_score        SMALLINT,              -- 1-5, set por feedback del Manager
    feedback_texto    TEXT,
    metadatos         JSONB
);

CREATE INDEX idx_insights_tipo    ON opex_insights_log(tipo);
CREATE INDEX idx_insights_creado  ON opex_insights_log(creado_en DESC);

-- =====================================================
-- Permisos: rol read-only para el agente
-- =====================================================

CREATE ROLE opex_agent_readonly LOGIN PASSWORD '<DEFINIR>';
GRANT CONNECT ON DATABASE postgres TO opex_agent_readonly;
GRANT USAGE ON SCHEMA public TO opex_agent_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO opex_agent_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO opex_agent_readonly;

-- El agente escribe SOLO en estas dos tablas:
GRANT INSERT ON opex_decisions TO opex_agent_readonly;
GRANT INSERT ON opex_insights_log TO opex_agent_readonly;
GRANT USAGE ON SEQUENCE opex_decisions_id_seq TO opex_agent_readonly;
GRANT USAGE ON SEQUENCE opex_insights_log_id_seq TO opex_agent_readonly;
```

## Apéndice B — SQL de vistas materializadas

```sql
-- =====================================================
-- VISTA MATERIALIZADA: mv_opex_vecindarios
-- Estadísticos por nivel jerárquico × medida × servicio
-- Ventana móvil 6 meses
-- =====================================================

CREATE MATERIALIZED VIEW mv_opex_vecindarios AS
WITH ots_ventana AS (
    SELECT *
    FROM opex_ots_raw
    WHERE fecha_creacion >= NOW() - INTERVAL '6 months'
      AND estado IN ('CERRADA', 'ABIERTA')
)
-- Nivel 1: ciudad + medida + servicio
SELECT
    'ciudad_medida_servicio'                AS nivel,
    ciudad                                  AS dim1,
    tipo_medida                             AS dim2,
    tipo_servicio                           AS dim3,
    NULL::TEXT                              AS dim4,
    COUNT(*)                                AS n,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY costo_total) AS p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY costo_total) AS p50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY costo_total) AS p75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY costo_total) AS p90,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY costo_total) AS p99,
    AVG(costo_total)                        AS media,
    STDDEV(costo_total)                     AS desv
FROM ots_ventana
WHERE ciudad IS NOT NULL
GROUP BY ciudad, tipo_medida, tipo_servicio
HAVING COUNT(*) >= 5

UNION ALL

-- Nivel 2: OR + medida + servicio
SELECT
    'or_medida_servicio',
    operador_red, tipo_medida, tipo_servicio, NULL,
    COUNT(*),
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY costo_total),
    AVG(costo_total), STDDEV(costo_total)
FROM ots_ventana
WHERE operador_red IS NOT NULL
GROUP BY operador_red, tipo_medida, tipo_servicio
HAVING COUNT(*) >= 5

UNION ALL

-- Nivel 3: zona + medida + servicio
SELECT
    'zona_medida_servicio',
    zona, tipo_medida, tipo_servicio, NULL,
    COUNT(*),
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY costo_total),
    AVG(costo_total), STDDEV(costo_total)
FROM ots_ventana
WHERE zona IS NOT NULL
GROUP BY zona, tipo_medida, tipo_servicio
HAVING COUNT(*) >= 5

UNION ALL

-- Nivel 4: medida + servicio (fallback)
SELECT
    'medida_servicio',
    tipo_medida, tipo_servicio, NULL, NULL,
    COUNT(*),
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY costo_total),
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY costo_total),
    AVG(costo_total), STDDEV(costo_total)
FROM ots_ventana
GROUP BY tipo_medida, tipo_servicio
HAVING COUNT(*) >= 5;

CREATE INDEX idx_mv_vecindarios ON mv_opex_vecindarios(nivel, dim1, dim2, dim3);

-- =====================================================
-- VISTA MATERIALIZADA: mv_opex_items_stats_peers
-- Estadísticos por ítem × nivel jerárquico
-- =====================================================

CREATE MATERIALIZED VIEW mv_opex_items_stats_peers AS
WITH items_ventana AS (
    SELECT i.*, o.ciudad, o.zona, o.operador_red,
           o.tipo_medida, o.tipo_servicio, o.contratista_id
    FROM opex_items_aplicados i
    JOIN opex_ots_raw o USING (ot_id)
    WHERE o.fecha_creacion >= NOW() - INTERVAL '6 months'
)
SELECT
    'zona_medida_servicio_item' AS nivel,
    zona AS dim1, tipo_medida AS dim2, tipo_servicio AS dim3, item_codigo AS dim4,
    COUNT(*) AS n,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY valor_total) AS p50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valor_total) AS p75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY valor_total) AS p90,
    AVG(valor_total)::NUMERIC(15,2) AS media,
    -- Frecuencia de aparición del ítem en este vecindario
    (COUNT(DISTINCT ot_id)::NUMERIC /
     NULLIF((SELECT COUNT(*) FROM opex_ots_raw o2
             WHERE o2.zona = items_ventana.zona
               AND o2.tipo_medida = items_ventana.tipo_medida
               AND o2.tipo_servicio = items_ventana.tipo_servicio
               AND o2.fecha_creacion >= NOW() - INTERVAL '6 months'), 0)
    ) AS frecuencia_aparicion
FROM items_ventana
WHERE zona IS NOT NULL
GROUP BY zona, tipo_medida, tipo_servicio, item_codigo
HAVING COUNT(*) >= 5;

CREATE INDEX idx_mv_items_peers ON mv_opex_items_stats_peers(dim1, dim2, dim3, dim4);

-- =====================================================
-- VISTA MATERIALIZADA: mv_opex_items_stats_self
-- Mismo cálculo pero por contratista (autoreferencia)
-- =====================================================

CREATE MATERIALIZED VIEW mv_opex_items_stats_self AS
WITH items_ventana AS (
    SELECT i.*, o.ciudad, o.zona, o.operador_red,
           o.tipo_medida, o.tipo_servicio, o.contratista_id
    FROM opex_items_aplicados i
    JOIN opex_ots_raw o USING (ot_id)
    WHERE o.fecha_creacion >= NOW() - INTERVAL '6 months'
)
SELECT
    contratista_id,
    zona, tipo_medida, tipo_servicio, item_codigo,
    COUNT(*) AS n,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY valor_total) AS p50,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY valor_total) AS p90,
    AVG(valor_total)::NUMERIC(15,2) AS media,
    (COUNT(DISTINCT ot_id)::NUMERIC /
     NULLIF((SELECT COUNT(*) FROM opex_ots_raw o2
             WHERE o2.contratista_id = items_ventana.contratista_id
               AND o2.zona = items_ventana.zona
               AND o2.tipo_medida = items_ventana.tipo_medida
               AND o2.tipo_servicio = items_ventana.tipo_servicio
               AND o2.fecha_creacion >= NOW() - INTERVAL '6 months'), 0)
    ) AS frecuencia_aparicion
FROM items_ventana
WHERE zona IS NOT NULL
GROUP BY contratista_id, zona, tipo_medida, tipo_servicio, item_codigo
HAVING COUNT(*) >= 3;

CREATE INDEX idx_mv_items_self ON mv_opex_items_stats_self(contratista_id, zona, tipo_medida, tipo_servicio, item_codigo);

-- =====================================================
-- Función helper: refresh diario
-- =====================================================
CREATE OR REPLACE FUNCTION refresh_opex_views()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_opex_vecindarios;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_opex_items_stats_peers;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_opex_items_stats_self;
END;
$$ LANGUAGE plpgsql;
```

## Apéndice C — System prompt completo del agente

```
Eres un asesor económico operacional para el equipo FOPS de BIA Energy, empresa colombiana de comercialización de energía. Tu usuario principal es el Manager FOPS. Trabajas en Slack.

# TU ROL

Tu trabajo es ayudar al Manager FOPS a entender el comportamiento del OPEX (gasto operacional con contratistas de campo) en tiempo real, identificar desviaciones materiales, atribuir causa, y sugerir acción. NO eres un sistema de tickets, NO apruebas alertas individuales, NO mandas listas.

# REGLAS DE NEGOCIO QUE DEBES CONOCER

## Cómo funciona el OPEX en BIA
1. BIA contrata operaciones de campo (instalaciones, mantenimientos, normalizaciones, visitas) a múltiples contratistas en distintas zonas del país.
2. Cada operación se gestiona como una OT (Orden de Trabajo) en App OPS.
3. El contratista carga en App OPS los ítems aplicados del tarifario vigente para esa OT. Cada OT tiene N ítems.
4. El costo total de una OT = suma de los ítems aplicados (incluyendo desplazamiento como ítem independiente).
5. Sin acta firmada/cargada en 24h, la OT no se reconoce y no se paga (regla de negocio fija).
6. El planner del contratista puede editar ítems antes del cierre.
7. Sales pre-costea las fronteras al venderlas. El delta (Sales vs real) es métrica clave.

## Tipos de servicio principales
- INST: instalación de medidor
- NORM: normalización (reemplazo, recableado, etc.)
- MANT: mantenimiento preventivo
- VISITA: revisión sin cambio de hardware

## Tipos de medida
- DIRECTA: medidor mide directo (residencial, pequeño comercial)
- SEMIDIRECTA: con TC (transformadores de corriente) — comercial mediano
- INDIRECTA: con TC y TP (de potencial) — industrial / alta tensión

# MODELO DE VALIDACIÓN DE OT — EL CORAZÓN DE TU TRABAJO

Una OT NO se valida contra una sola tarifa. Se valida así:

## Paso 1: construir el vecindario comparable
Dada una OT con sus atributos, busca su vecindario en este orden de prioridad. Usa el primer nivel que tenga al menos 30 muestras en 6 meses:
1. ciudad + tipo_medida + tipo_servicio
2. operador_red + tipo_medida + tipo_servicio
3. zona + tipo_medida + tipo_servicio
4. tipo_medida + tipo_servicio (fallback nacional)

SIEMPRE reporta qué nivel usaste y cuántas muestras (n).

## Paso 2: lente dual self vs peers
- SELF: el contratista comparado contra sí mismo en ese vecindario.
- PEERS: el contratista contra los demás del mismo vecindario.

Interpretación:
- alto self + normal peers → contratista está cobrando distinto a su histórico, pero alineado al mercado (probablemente legítimo)
- normal self + alto peers → patrón histórico desfavorable del contratista vs mercado (renegociar)
- alto en ambos → caso individual atípico (investigar OT)
- normal en ambos → ruido (ignorar)

## Paso 3: descomposición por ítem
Cuando una OT está fuera de rango, NO te quedes en "está alta". Descompón:
- ¿Qué ítems aparecen aquí que no son típicos en el vecindario? (composición atípica)
- ¿Qué ítems están fuera de su distribución esperada? (precio outlier por ítem)
- ¿Qué % del exceso explica cada ítem? (atribución cuantitativa)

# TUS HERRAMIENTAS

Tienes 5 tools. Úsalas con criterio:

1. query_supabase(sql, params) — ejecuta SQL contra Supabase. Solo lectura.
2. query_metabase(card_id, params) — para datos no sincronizados o validación cruzada.
3. get_neighborhood_stats(ot_id) — atajo: dada una OT, te devuelve vecindario, stats self/peers, descomposición.
4. save_decision(contexto, respuesta_manager, accion) — guarda cuando el Manager toma postura.
5. get_recent_decisions(filtro) — siempre consúltala al inicio si la pregunta involucra contratista, zona o ítem.

# PATRÓN DE RAZONAMIENTO

Para cada interacción:
1. ¿Qué entidad pregunta el usuario?
2. ¿Hay decisiones previas relevantes? → get_recent_decisions
3. ¿Qué dato necesito? → query_supabase o get_neighborhood_stats
4. ¿Necesito más contexto? → segunda query si aplica
5. ¿Cuál es la lectura interpretativa? (no solo la cifra)
6. ¿Qué acción concreta sugiero?
7. Responder en formato Slack.

# FORMATO DE RESPUESTA

- Cifras concretas, no adjetivos vagos. "$4.2M sobre presupuesto" sí; "significativamente alto" no.
- Cita siempre nivel de vecindario y n. Ejemplo: "comparado contra OR-medida (n=47)".
- Atribución cuantitativa cuando aplique. "El ítem 43 aporta 13 puntos del 28% de exceso."
- Acción específica al final. "Pedir soporte fotográfico de acceso difícil; si no hay, descontar $150k."
- Tono ejecutivo. Sin emojis decorativos. Sin lenguaje de alerta automática.
- Máximo 3 hallazgos por mensaje proactivo.
- Cuando no hay nada útil que reportar, di "sin novedad relevante". NO inventes.

# COMPORTAMIENTO ANTE INCERTIDUMBRE

- Si una query no devuelve datos suficientes, dilo. NO inventes cifras.
- Si el vecindario tiene n<30, sube de nivel y avisa.
- Si una OT no existe, dilo. NO inventes una OT.
- Si te preguntan algo fuera de OPEX (RRHH, finanzas corporativas, etc.), redirige.
- Si hay ambigüedad en la pregunta del Manager, pide aclaración antes de inventar.

# MEMORIA CONVERSACIONAL

Guarda en opex_decisions cuando el Manager:
- Toma postura concreta (escalar, descontar, aprobar, ignorar por X razón).
- Pide seguimiento (recuérdame revisar esto).
- Te corrige (no, este caso es así porque...).
- Establece regla nueva (en zona X el ítem 43 sí es esperable).

NO guardes confirmaciones triviales (ok, gracias, listo).

Cuando una decisión guardada esté activa y vuelva a aparecer el mismo patrón, mencionala explícitamente. Ejemplo: "La semana pasada quedaste de hablar con Supply sobre Contratista Alfa; el patrón sigue activo."

# QUÉ NO HACER

- No mandes alertas tipificadas estilo "ALERTA A2: sobrecobro tarifario".
- No saludes en cada mensaje proactivo.
- No expliques tu razonamiento interno a menos que te pregunten cómo llegaste.
- No uses jerga estadística sin contexto. "p99" sí explicado, "z-score" no.
- No prometas acciones que no puedas ejecutar (no tienes acceso a App OPS para modificar OTs).
- No reveles datos de un contratista a otro contratista, ni datos personales de empleados.
```

## Apéndice D — Signatures de tools

```yaml
# Tool 1: query_supabase
name: query_supabase
description: Ejecuta SQL parametrizado contra Supabase (read-only).
parameters:
  type: object
  properties:
    sql:
      type: string
      description: |
        SQL a ejecutar. Debe incluir LIMIT obligatorio (default 100, máx 1000).
        Solo SELECT. Sin DDL, sin DML, sin INSERT/UPDATE/DELETE.
        Usa $1, $2... para parámetros (NUNCA concatenes strings de usuario).
    params:
      type: array
      description: Parámetros posicionales del SQL.
      items: {type: string}
  required: [sql]

# Tool 2: query_metabase
name: query_metabase
description: Consulta una card Metabase con filtros.
parameters:
  type: object
  properties:
    card_id:
      type: integer
      description: ID de la card en Metabase.
    filters:
      type: object
      description: Diccionario {nombre_filtro: valor}.
  required: [card_id]

# Tool 3: get_neighborhood_stats
name: get_neighborhood_stats
description: |
  Para una OT dada, devuelve su vecindario seleccionado, percentiles self y peers,
  y descomposición por ítem. Atajo de alto nivel para validar OTs individuales.
parameters:
  type: object
  properties:
    ot_id:
      type: string
  required: [ot_id]
returns:
  type: object
  properties:
    nivel_seleccionado: {type: string}     # ej. "or_medida_servicio"
    n_muestras: {type: integer}
    costo_ot: {type: number}
    p50_peers: {type: number}
    p90_peers: {type: number}
    p50_self: {type: number}
    p90_self: {type: number}
    desviacion_pct_peers: {type: number}
    desviacion_pct_self: {type: number}
    items_outlier:
      type: array
      items:
        type: object
        properties:
          item_codigo: {type: string}
          aporte_exceso: {type: number}    # % del exceso total
          frecuencia_aparicion_self: {type: number}
          frecuencia_aparicion_peers: {type: number}
    composicion_atipica:
      type: array
      items: {type: string}                # códigos de ítem inusuales

# Tool 4: save_decision
name: save_decision
description: Guarda una decisión significativa del Manager.
parameters:
  type: object
  properties:
    contexto: {type: string}
    respuesta_manager: {type: string}
    accion:
      type: string
      enum: [ESCALAR, DESCONTAR, APROBAR, IGNORAR, REGLA_NUEVA, SEGUIMIENTO]
    contratista_id: {type: string}
    zona: {type: string}
    item_codigo: {type: string}
    ot_id: {type: string}
  required: [contexto, respuesta_manager, accion]

# Tool 5: get_recent_decisions
name: get_recent_decisions
description: |
  Recupera decisiones recientes activas, filtradas por contratista, zona, ítem.
  Llamar al inicio del razonamiento cuando la pregunta involucra alguna de estas dimensiones.
parameters:
  type: object
  properties:
    contratista_id: {type: string}
    zona: {type: string}
    item_codigo: {type: string}
    ot_id: {type: string}
    desde:
      type: string
      format: date
      description: ISO date. Default últimos 30 días.
  required: []
```

## Apéndice E — Glosario

| Término | Definición |
|---|---|
| **OT** | Orden de Trabajo. Una operación de campo. |
| **OPEX** | Gasto operacional, en este proyecto = costo de operaciones de campo con contratistas. |
| **CAC** | Costo de Adquisición/Activación de Cliente. Métrica derivada del OPEX. |
| **Frontera** | Punto regulatorio de medida en el sistema eléctrico. |
| **OR** | Operador de Red. Empresa regulada dueña de la red eléctrica de una zona. |
| **App OPS** | Aplicación operativa donde contratistas cargan OTs e ítems. |
| **Vecindario** | Conjunto de OTs comparables a una OT dada según jerarquía geográfica/operativa. |
| **Self** | Lente de comparación: contratista vs sí mismo. |
| **Peers** | Lente de comparación: contratista vs pares del mismo vecindario. |
| **Composición** | Conjunto de ítems aplicados en una OT. |
| **Atribución** | Descomposición cuantitativa: qué % del exceso de costo aporta cada ítem. |
| **Decisión guardable** | Postura del Manager que el agente debe recordar para usos futuros. |

## Apéndice F — Decisiones pendientes vivas

Esta lista se actualiza durante el proyecto. Cualquier decisión no resuelta aquí bloquea la fase correspondiente.

| # | Decisión | Bloquea | Responsable | Estado |
|---|---|---|---|---|
| 1 | Identidad del FOPS Manager | Día 1 | Daniel + dirección | Pendiente |
| 2 | DM vs canal `#opex-fops` | Día 1 | Manager + Daniel | Pendiente |
| 3 | API key Metabase real | Día 1 (WF-A) | Daniel | Pendiente |
| 4 | Mapeo de columnas Metabase ↔ modelo | Día 1 | Daniel | Pendiente |
| 5 | Proveedor LLM (OpenAI/Anthropic) | Día 1 | Daniel + presupuesto | Pendiente |
| 6 | Procesamiento card 19440 (~27.4 MB) | Semana 1 | Daniel | Pendiente |
| 7 | Definición operativa de "zona" | Semana 1 | Validar con FOPS | Pendiente |
| 8 | Política de qué datos exponer en canal vs DM | Semana 3 si va a canal | Manager + cumplimiento | Pendiente |

## Apéndice G — Checklist de cierre por fase

### Cierre semana 1 (no avanzar sin esto)
- [ ] Las 6 tablas creadas en Supabase y con datos.
- [ ] Las 3 vistas materializadas creadas y con stats coherentes.
- [ ] WF-A corriendo cada hora sin errores en últimas 48 h.
- [ ] WF-B respondiendo en Slack.
- [ ] Las 5 queries de §17.1 validadas por el Manager.
- [ ] System prompt v1 versionado en Git o backup.

### Cierre semana 2 (no avanzar sin esto)
- [ ] WF-C activo en cron 07:30 L–V.
- [ ] ≥3 mensajes matinales calificados ≥3/5 por el Manager.
- [ ] `opex_insights_log` poblándose.
- [ ] Lógica "sin novedad relevante" probada al menos 1 vez.

### Cierre semana 3 / cierre MVP
- [ ] `opex_decisions` con ≥5 decisiones reales guardadas.
- [ ] Memoria conversacional funcionando en ≥1 caso real.
- [ ] Test de no-alucinación pasado (20 pruebas, 0 fallas).
- [ ] ≥1 acción concreta del Manager originada por insight del agente.
- [ ] Manager confirma por escrito continuar al mes 2.
- [ ] Documento de aprendizajes escrito (qué funcionó, qué no, qué sigue).

---

# Cierre

Este plan es ejecutable tal como está. Si en algún paso aparece ambigüedad real (no inventada), se documenta en el Apéndice F y se resuelve antes de seguir. La regla de oro durante las 3 semanas es: **no añadir capacidades hasta que las actuales pasen su test**.

El éxito del MVP no se mide por features construidos sino por una sola cosa: que el FOPS Manager, al final de la semana 3, diga sin titubear "esto me sirve, sigamos".

Si esto se logra, el mes 2 construye sobre cimientos reales. Si no se logra, el mes 2 no debe construirse — debe iterarse el mes 1.

*Fin del plan ejecutivo.*
