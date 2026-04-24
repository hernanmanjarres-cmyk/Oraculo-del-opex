# Guía: Crear la Slack App del Analista OPEX

**Tiempo estimado:** 20–30 minutos  
**Requisito previo:** Ser administrador del workspace de Slack de BIA Energy.

---

## Paso 1 — Crear la aplicación en Slack

1. Ve a **https://api.slack.com/apps**
2. Haz clic en **"Create New App"**
3. Selecciona **"From scratch"**
4. Nombre de la app: `Analista OPEX BIA`
5. Workspace: selecciona el workspace de BIA Energy
6. Haz clic en **"Create App"**

---

## Paso 2 — Configurar OAuth Scopes (permisos del bot)

1. En el menú lateral, ve a **OAuth & Permissions**
2. Desplázate hasta la sección **Bot Token Scopes**
3. Haz clic en **"Add an OAuth Scope"** y agrega los siguientes scopes uno por uno:

| Scope | Para qué sirve |
|-------|---------------|
| `chat:write` | Enviar mensajes a canales |
| `chat:write.public` | Enviar mensajes a canales públicos sin ser miembro |
| `channels:read` | Listar canales disponibles |
| `channels:join` | Unirse a canales automáticamente |
| `groups:write` | Enviar mensajes a canales privados |
| `im:write` | Enviar mensajes directos |
| `users:read` | Leer perfiles de usuarios (para menciones) |
| `files:write` | Subir archivos/CSVs al canal de cierre |
| `reactions:write` | Añadir reacciones de confirmación a mensajes |

---

## Paso 3 — Instalar la app en el workspace

1. En la misma página **OAuth & Permissions**, desplázate arriba
2. Haz clic en **"Install to Workspace"**
3. Autoriza los permisos solicitados
4. Copia el **Bot User OAuth Token** — empieza con `xoxb-`

> **Guárdalo ahora:** este token se necesita en n8n. Trátalo como una contraseña.

---

## Paso 4 — Habilitar Interactivity (para botones de aprobación)

1. En el menú lateral, ve a **Interactivity & Shortcuts**
2. Activa el toggle **"Interactivity"**
3. En el campo **Request URL**, pega la URL del webhook de n8n (la obtienes del nodo Webhook en n8n):
   ```
   https://TU_INSTANCIA.app.n8n.cloud/webhook/opex-slack-actions
   ```
   > Nota: configura primero el workflow `wf_04` en n8n para obtener esta URL.
4. Haz clic en **"Save Changes"**

---

## Paso 5 — Obtener el Signing Secret

El Signing Secret permite que n8n verifique que los mensajes vienen realmente de Slack.

1. En el menú lateral, ve a **Basic Information**
2. Desplázate hasta **App Credentials**
3. Copia el **Signing Secret**

> **Guárdalo:** se necesita en n8n junto con el Bot Token.

---

## Paso 6 — Crear los canales de Slack necesarios

Crea los siguientes canales en tu workspace de Slack:

| Canal | Tipo | Propósito |
|-------|------|-----------|
| `#opex-alertas` | Privado (recomendado) | Alertas medias y altas del agente |
| `#opex-aprobacion` | Privado | Cola de aprobación de comunicaciones |
| `#opex-cierre` | Privado | Reporte mensual de cierre |
| `#bia-opex-errors` | Privado | Errores técnicos del agente |

---

## Paso 7 — Agregar el bot a los canales

En cada canal creado:
1. Abre el canal
2. Escribe: `/invite @Analista OPEX BIA`
3. Confirma la invitación

---

## Paso 8 — Obtener los IDs de canal (para n8n)

n8n necesita el **Channel ID** (no el nombre) para enviar mensajes. Para obtenerlo:

1. Abre el canal en Slack (versión web o desktop)
2. Haz clic en el nombre del canal en la parte superior
3. Desplázate hasta el final del modal → verás el **Channel ID** (formato: `C0XXXXXXXX`)

Anota los IDs de los 4 canales:

```
#opex-alertas       → C___________
#opex-aprobacion    → C___________
#opex-cierre        → C___________
#bia-opex-errors    → C___________
```

---

## Resumen de credenciales para n8n

Al final de este proceso deberás tener:

| Dato | Formato | Dónde se usa |
|------|---------|-------------|
| Bot User OAuth Token | `xoxb-xxxx-xxxx-xxxx` | Credencial Slack en n8n |
| Signing Secret | String de 32 chars | Verificación en wf_04 webhook |
| Channel ID alertas | `C0XXXXXXXX` | Variable en todos los workflows |
| Channel ID aprobación | `C0XXXXXXXX` | wf_02, wf_04, wf_05 |
| Channel ID cierre | `C0XXXXXXXX` | wf_07 |
| Channel ID errores | `C0XXXXXXXX` | Error handler global |

Pasa estos valores al documento `02_n8n_credentials_setup.md` para configurar n8n.

---

## Verificación

Para verificar que todo funciona, en n8n puedes hacer un test rápido:
1. Crea un nodo **Slack → Send a Message**
2. Usa el Bot Token configurado
3. Pon el Channel ID de `#opex-alertas`
4. Mensaje: `Test del bot Analista OPEX BIA ✅`
5. Ejecuta → si llega el mensaje al canal, está todo correcto.
