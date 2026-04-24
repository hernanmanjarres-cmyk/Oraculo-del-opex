# Guía: Configurar Credenciales en n8n Cloud

**Tiempo estimado:** 15–20 minutos  
**Requisito previo:** Tener las credenciales de Supabase, Slack, Google y APIs de IA listas.

> En n8n cloud todas las credenciales se configuran en **Settings → Credentials → New Credential**.  
> Los workflows las referencian por nombre — no por valor directo. Esto mantiene los secrets fuera del JSON exportable.

---

## Credencial 1 — Supabase (Postgres)

n8n conecta a Supabase directamente como Postgres.

**En n8n:** Credentials → New → busca **"Postgres"**

| Campo | Valor |
|-------|-------|
| Credential Name | `Supabase OPEX BIA` |
| Host | `db.XXXX.supabase.co` ← tu proyecto Supabase |
| Database | `postgres` |
| User | `postgres` |
| Password | La contraseña de tu proyecto Supabase |
| Port | `5432` |
| SSL | **Enabled (require)** |

**Cómo obtener los datos en Supabase:**
1. Ve a tu proyecto en supabase.com
2. Settings → Database → Connection string → selecciona **URI**
3. Copia: `postgresql://postgres:[password]@db.XXXX.supabase.co:5432/postgres`
4. Extrae cada parte y pégala en n8n

---

## Credencial 2 — Slack

**En n8n:** Credentials → New → busca **"Slack API"**

| Campo | Valor |
|-------|-------|
| Credential Name | `Slack OPEX BIA` |
| Authentication | **Access Token** |
| Access Token | `xoxb-xxxx-xxxx-xxxx` (del paso 3 de la guía Slack) |

> Para el Signing Secret (verificación de webhooks), se configura directamente en el nodo Webhook del workflow `wf_04` como variable de entorno o en el código de validación.

---

## Credencial 3 — Google Sheets (para sincronización de tarifario y budget)

**En n8n:** Credentials → New → busca **"Google Sheets"**

Recomendado: usar **Service Account** (más estable que OAuth personal).

### Crear Service Account en Google Cloud:
1. Ve a **console.cloud.google.com**
2. Proyecto → IAM & Admin → Service Accounts → Create Service Account
3. Nombre: `n8n-opex-bia`
4. Role: **Editor** (o solo **Viewer** si solo vas a leer los sheets)
5. Crea y descarga el archivo JSON de clave
6. Comparte el Google Sheet con el email del Service Account (termina en `@...iam.gserviceaccount.com`)

**En n8n:**

| Campo | Valor |
|-------|-------|
| Credential Name | `Google Sheets OPEX BIA` |
| Authentication | **Service Account** |
| Service Account Email | El email del SA (del JSON descargado) |
| Private Key | El valor `private_key` del JSON (copia el string completo) |

---

## Credencial 4 — Google Gemini (LLM primario)

**En n8n:** Credentials → New → busca **"Google Gemini(PaLM) Api"** o **"Google AI"**

| Campo | Valor |
|-------|-------|
| Credential Name | `Gemini API BIA` |
| API Key | Tu clave de Google AI Studio (aistudio.google.com → Get API key) |

> Gemini 2.0 Flash es el modelo recomendado: rápido, barato y con contexto amplio para narrativas largas.

---

## Credencial 5 — Anthropic / Claude (LLM fallback y cierre mensual)

**En n8n:** Credentials → New → busca **"Anthropic"**

| Campo | Valor |
|-------|-------|
| Credential Name | `Claude API BIA` |
| API Key | Tu clave de Anthropic (console.anthropic.com → API Keys) |

> Claude Sonnet 4.6 se usa para narrativa del cierre mensual y redacción de correos delicados donde la calidad es crítica.

---

## Variables de entorno globales (recomendado)

En n8n cloud puedes definir variables de entorno en **Settings → Variables** que se usan en todos los workflows. Esto facilita cambiar un canal o ID sin editar cada workflow.

Crea las siguientes variables:

| Variable | Valor |
|----------|-------|
| `OPEX_SLACK_CHANNEL_ALERTAS` | ID del canal `#opex-alertas` (ej: `C08XXXXXXX`) |
| `OPEX_SLACK_CHANNEL_APROBACION` | ID del canal `#opex-aprobacion` |
| `OPEX_SLACK_CHANNEL_CIERRE` | ID del canal `#opex-cierre` |
| `OPEX_SLACK_CHANNEL_ERRORES` | ID del canal `#bia-opex-errors` |
| `OPEX_SLACK_SIGNING_SECRET` | Signing Secret de la Slack App |
| `OPEX_SHEETS_ID_TARIFARIO` | ID del Google Sheet de tarifario (de la URL) |
| `OPEX_SHEETS_ID_BUDGET` | ID del Google Sheet de budget |
| `OPEX_EMAIL_REMITENTE` | `opex@bia.app` (o el email que uses) |
| `OPEX_DRY_RUN` | `false` (cambiar a `true` para pruebas) |

**Cómo obtener el ID de un Google Sheet:**  
De la URL `https://docs.google.com/spreadsheets/d/ESTE_ES_EL_ID/edit`, copia el string largo entre `/d/` y `/edit`.

---

## Verificación de credenciales

Antes de importar los workflows, verifica cada credencial:

1. **Supabase/Postgres:** crea un nodo Postgres en n8n → usa la credencial → ejecuta `SELECT NOW()` → debe retornar la fecha actual.
2. **Slack:** crea un nodo Slack → Send Message → canal `#opex-alertas` → mensaje de prueba → ejecuta → debe llegar al canal.
3. **Google Sheets:** crea un nodo Google Sheets → Read Sheet → selecciona el Sheet de tarifario → ejecuta → debe mostrar las filas.
4. **Gemini:** crea un nodo AI → Gemini → mensaje `"Responde con: ok"` → ejecuta → debe responder.
5. **Claude:** crea un nodo Anthropic → mensaje `"Responde con: ok"` → ejecuta → debe responder.

---

## Nombres exactos de credenciales esperados en los workflows

Los workflows JSON usan estos nombres exactos de credencial. Si usas nombres diferentes, deberás actualizar cada nodo al importar:

| Credencial en workflow | Tipo |
|------------------------|------|
| `Supabase OPEX BIA` | Postgres |
| `Slack OPEX BIA` | Slack API |
| `Google Sheets OPEX BIA` | Google Sheets |
| `Gemini API BIA` | Google Gemini |
| `Claude API BIA` | Anthropic |
