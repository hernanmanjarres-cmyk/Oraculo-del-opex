# Runbook Operativo — Analista OPEX BIA

**Para:** Analista OPEX (usuario principal del agente)  
**Versión:** 1.0 — Abril 2026

---

## Rutina diaria con el agente (< 15 minutos)

### 07:30 — Recibir resumen en Slack

El agente publica automáticamente en `#opex-alertas` un resumen del día con:
- Ejecución del día anterior y MTD vs budget
- Semáforo de desviación (🟢🟡🔴)
- Alertas abiertas por severidad
- Top 3 desviaciones del día
- Forecast de cierre del mes

**Acción:** leer el resumen y decidir en cuáles alertas actuar primero.

---

### Revisar la cola de aprobación

Cuando hay alertas de severidad **media/alta/crítica**, el agente crea borradores de comunicación (correos a contratistas, tickets internos). Estos aparecen en `#opex-aprobacion`.

Para cada borrador puedes:

| Botón | Acción | Qué pasa |
|-------|--------|----------|
| `✉️ Ver borrador` | Ver el texto propuesto | Abre el borrador — puedes editarlo |
| `✅ Enviar` | Aprobar y enviar | El agente registra el envío en `opex_communications` |
| `✏️ Editar y enviar` | Modificar antes de enviar | Tu versión se guarda como `cuerpo_editado` |
| `❌ Falso positivo` | Marcar como FP | Cierra la alerta como FP y alimenta el aprendizaje del agente |

**Regla de oro:** si dudas, marca como FP y escribe en el campo de texto por qué. Esa información es la más valiosa para que el agente mejore.

---

### Cerrar alertas con causa raíz

Cuando resuelves una anomalía (hablaste con el contratista, te aclararon el cobro, ajustaron la factura), cierra la alerta en Slack o en Supabase:

1. **Desde Slack:** usa el botón `✅ Resolver` en el mensaje de la alerta
2. **Desde Supabase:** cambia el campo `estado` a `resolved` y llena `causa_raiz_sugerida` con la causa real

Causas raíz disponibles (usa exactamente estos textos):
- `Facturación incorrecta` — el contratista cobró mal y corrigió
- `Material extra no autorizado` — materiales fuera de alcance del contrato
- `Error de datos` — problema en la fuente/Metabase, no en el cobro real
- `Retrabajo` — OT repetida por falla de calidad
- `Cambio de alcance sin aprobación` — el alcance cambió sin formalizar
- `Tarifa desactualizada` — el tarifario en sistema no reflejaba el precio vigente
- `Justificado por contexto operativo` — desvío válido por razón operativa
- `Otro` — con descripción manual

---

## Rutina quincenal (días 15 y 30)

### Revisar forecast de cierre

El agente actualiza el forecast cada día a las 08:00. El día 15 y el día 28 revisa:
- ¿El forecast está dentro del budget?
- ¿Hay contratistas con ejecución que va a superar su budget mensual?
- ¿Hay acciones de contención posibles antes de fin de mes?

Consulta en Supabase: `SELECT * FROM v_resumen_mes_actual;`

### Revisar alertas viejas sin cerrar

El agente no cierra alertas automáticamente. Una alerta abierta > 7 días sin atender se debe revisar:

```sql
SELECT * FROM v_alertas_abiertas WHERE horas_abierta > 168;  -- > 7 días
```

---

## Rutina mensual (día 1-3)

### Día 1: Recibir y revisar el cierre automático

El agente genera el cierre en `#opex-cierre` a las 09:00. Revisa:
1. La narrativa generada por IA — ¿es precisa?
2. Los pivots adjuntos — ¿coinciden con lo que sabes?
3. Las alertas abiertas al cierre — ¿cuáles quedan pendientes para el mes siguiente?

Para aprobar el cierre: botón `✅ Aprobar cierre` en Slack.

### Día 3: Revisar propuestas de recalibración

El agente publica en `#opex-alertas` el informe de recalibración con:
- KPIs del agente en los últimos 3 meses (MAE forecast, cobertura, precisión IA)
- Propuestas de ajuste de umbrales con justificación

Para aprobar cambios: botón `✅ Aplicar todos los cambios`.  
Para ignorar: `⏭️ Ignorar este mes`.

**No se aplica ningún cambio de umbral sin tu aprobación explícita.**

---

## Comandos de control del agente

### Pausar el agente (emergencia)

Si el agente está generando demasiado ruido o hay un problema, pausa las alertas no críticas:
- **Desde Slack:** botón `⏸️ Pausar alertas no críticas` en el resumen diario
- **Desde Supabase:** `UPDATE opex_config SET valor = 'true' WHERE clave = 'kill_switch';`

Para reactivar:
```sql
UPDATE opex_config SET valor = 'false' WHERE clave = 'kill_switch';
```

### Modo simulación (dry_run)

Para probar cambios sin enviar comunicaciones:
```sql
UPDATE opex_config SET valor = 'true' WHERE clave = 'dry_run';
-- El agente genera todo pero no envía correos ni crea tickets
-- Revertir:
UPDATE opex_config SET valor = 'false' WHERE clave = 'dry_run';
```

---

## Qué hacer cuando el agente se equivoca

### Si genera demasiados falsos positivos de un tipo

1. Marca los FP en Slack con el botón `❌ Falso positivo`
2. Escribe en el texto libre la razón
3. El agente acumulará estos FP y el día 3 del mes propondrá ajustar el umbral
4. Si necesitas ajuste inmediato, contacta al administrador del agente para modificar `opex_rules` en Supabase

### Si el forecast está muy desviado

1. Verifica que `opex_transactions` tiene los datos correctos (sin duplicados, sin faltantes)
2. Verifica que `opex_budget` tiene el budget del mes actual cargado
3. Si hay un evento atípico (brigada especial, proyecto extraordinario), el agente no lo sabe — ajusta el pipeline en `opex_transactions` marcando las OTs pendientes como "abierta"

### Si una comunicación se envió por error

No hay forma de revertir un correo enviado. Para mitigar:
1. Verifica en `opex_communications` qué se envió (`SELECT * FROM opex_communications ORDER BY enviado_en DESC LIMIT 10;`)
2. Contacta al destinatario directamente
3. El evento queda registrado con timestamp y el aprobador

---

## Tabla de escalamiento

| Situación | Acción inmediata | Escalar a |
|-----------|-----------------|-----------|
| Alerta A11 (patrón sistemático) | Revisar contratista, pausar pagos si aplica | Coordinador Finanzas |
| Alerta A3 (sobrecobro > 15%) | No aprobar pago hasta aclaración | Coordinador Finanzas + Operaciones |
| Alerta A14 (contratista recurrente sin confirmar) | Revisar historial del contratista | Gerencia |
| FP rate > 50% en una regla | Pausar la regla específica | Administrador del agente |
| Agente no envía resumen diario | Verificar `opex_agent_log` en Supabase | Administrador del agente |
| Error crítico en `#bia-opex-errors` | Verificar causa en el log | Administrador del agente |

---

## Verificación de salud del agente

Revisa semanalmente en Supabase:

```sql
-- Últimas ejecuciones de cada workflow
SELECT workflow_nombre, MAX(inicio) as ultima_ejecucion, estado
FROM opex_agent_log
GROUP BY workflow_nombre, estado
ORDER BY ultima_ejecucion DESC;

-- Alertas generadas últimos 7 días
SELECT DATE(generada_en) as dia, COUNT(*), severidad
FROM opex_alerts
WHERE generada_en >= NOW() - INTERVAL '7 days'
GROUP BY DATE(generada_en), severidad
ORDER BY dia DESC;

-- FP rate por regla
SELECT * FROM v_fp_rate_por_regla ORDER BY fp_rate DESC;
```

---

## Contacto soporte

Si el agente tiene un comportamiento inesperado o necesitas un ajuste de regla:
- **Canal Slack:** `#bia-opex-errors` — el agente publica errores técnicos automáticamente
- **Supabase:** tabla `opex_agent_log` para historial de ejecuciones
- **n8n:** accede al historial de ejecuciones del workflow correspondiente para ver el detalle del error
