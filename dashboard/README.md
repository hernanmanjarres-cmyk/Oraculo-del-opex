# Dashboard OPEX Activación

Dashboard interactivo con login, roles y datos compartidos.

## ✨ Features

- **3 pestañas**: Resumen (KPIs), OTs abiertas (forecast), OTs ejecutadas (mes en curso)
- **Login con magic link** (sin contraseña, llega a tu correo)
- **3 roles**:
  - `lector` → ve todo, no edita
  - `usuario` → ve + edita gastos adicionales (compartidos entre todos)
  - `super_admin` → todo + pestaña Admin para gestionar usuarios
- **Adicionales globales**: el monto que cargás se ve igual para todos
- **Migración automática**: si una OT pasa de abierta a ejecutada, su adicional la sigue (clave por `ot_id`)
- **Modo offline**: si no configurás Supabase, funciona local (sin auth, adicionales en navegador)

## 🚀 Setup completo (paso a paso)

### Paso 1 — Crear las tablas en Supabase

1. Andá a tu proyecto Supabase del Oráculo del OPEX → **SQL Editor**.
2. Pegá el contenido de `dashboard/supabase_schema.sql` y ejecutalo.
3. Verificá con:
   ```sql
   SELECT email, role FROM public.dashboard_users;
   ```
   Deberías ver `hernan.manjarres@bia.app | super_admin`.

### Paso 2 — Habilitar Google OAuth en Supabase

El dashboard usa Google Sign-In + restricción de dominio `@bia.app`. Es más rápido que magic link y sin rate limit.

**A) Crear OAuth Client en Google Cloud**

1. Andá a https://console.cloud.google.com/apis/credentials (con tu cuenta @bia.app)
2. Crear proyecto si no hay uno: "Oraculo OPEX Dashboard"
3. **APIs & Services → OAuth consent screen**:
   - User Type: **Internal** (solo cuentas de tu organización pueden ver la app)
   - App name: "OPEX Activación BIA"
   - Email: tu correo
   - Save
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**:
   - Application type: **Web application**
   - Name: "Supabase Auth"
   - **Authorized redirect URIs**: pegá la URL callback de Supabase (la verás en el paso B):
     `https://cjxfibdtlhbazobthywm.supabase.co/auth/v1/callback`
   - Create → copiá **Client ID** y **Client Secret**.

**B) Activar Google provider en Supabase**

1. Supabase → **Authentication → Providers → Google**.
2. Toggle ON.
3. Pegá el **Client ID** y **Client Secret** de Google.
4. Save. Supabase te muestra el callback URL — confirmá que coincide con el que pusiste en Google.

**C) Configurar URLs en Supabase**

1. **Authentication → URL Configuration**:
   - **Site URL**: la URL donde vas a hostear el HTML (`http://localhost:3000` para probar local; `https://hernanmanjarres-cmyk.github.io/Oraculo-del-opex/` para GH Pages).
   - **Redirect URLs**: agregá `http://localhost:3000/**` y `https://hernanmanjarres-cmyk.github.io/Oraculo-del-opex/**`.

### Paso 3 — Configurar el HTML con tus credenciales Supabase

1. Andá a Supabase → **Settings** → **API**.
2. Copiá:
   - **Project URL** (algo como `https://xxxxx.supabase.co`)
   - **anon public key** (algo largo que empieza con `eyJ...`) — esta key es **pública y segura**, RLS protege los datos.
3. Abrí `dashboard/index.html` en un editor de texto.
4. Buscá el bloque `<!-- ▼▼▼ CONFIG ▼▼▼ -->` y reemplazá:
   ```json
   {
     "url": "https://xxxxx.supabase.co",
     "anonKey": "eyJ..."
   }
   ```
5. Guardá.

### Paso 4 — Probarlo en local

```bash
cd "/Users/hernanmanjarres/Documents/Automatizaciones/Analista Opex/dashboard"
python3 -m http.server 3000
```

Abrí `http://localhost:3000` en el navegador.

> ⚠️ Google OAuth requiere **server real** (no doble click en `file://`). Para probar localmente, usá `python3 -m http.server`. Para abrir directo (doble click) usá modo offline (no pongas URL de Supabase).

1. Click en **"Continuar con Google"**.
2. El selector de Google solo te muestra cuentas `@bia.app` (gracias al hint `hd=bia.app`).
3. Si por accidente te logueás con otra cuenta, el dashboard te cierra sesión y muestra error.
4. Como sos `super_admin`, vas a ver las 4 pestañas (incluida Admin).
5. Probá agregar otro usuario en la pestaña Admin con rol `lector` o `usuario`.

### Paso 5 — Publicarlo (GitHub Pages)

1. GitHub repo → **Settings** → **Pages**.
2. **Source**: `feature/dashboard-opex-activacion`, folder `/dashboard`. Save.
3. En 1-2 min aparece la URL pública.
4. Volvé a Supabase → **Auth** → **URL Configuration** y agregá esa URL como Site URL + Redirect URL.
5. Cualquier persona que esté en `dashboard_users` con su email puede acceder y ver según su rol.

### Paso 6 — Refrescar datos (cuando quieras cifras actualizadas)

```bash
export METABASE_API_KEY="metabase_..."   # tu API key personal de Metabase
python3 dashboard/generate_data.py
```

Esto regenera:
- `dashboard/data.json` (sidecar)
- `dashboard/index.html` (data embebida)

Después hacés `git commit` + `git push` para que GitHub Pages tome la nueva versión.

## 📁 Estructura

```
dashboard/
├── index.html              # Dashboard (config Supabase + data embebida)
├── data.json               # Sidecar de datos
├── generate_data.py        # Refresca data desde Metabase
├── supabase_schema.sql     # SQL para crear tablas + RLS
└── README.md
```

## 🔐 Cómo funcionan los roles

| Acción | lector | usuario | super_admin |
|---|---|---|---|
| Ver Resumen, OTs abiertas, OTs ejecutadas | ✅ | ✅ | ✅ |
| Editar presupuesto (solo tu navegador) | ✅ | ✅ | ✅ |
| Editar gastos adicionales (globales) | ❌ | ✅ | ✅ |
| Ver pestaña Admin | ❌ | ❌ | ✅ |
| Agregar/borrar usuarios | ❌ | ❌ | ✅ |
| Cambiar rol de otros | ❌ | ❌ | ✅ |

**Importante**: las políticas RLS de Supabase imponen estas reglas a nivel base de datos. Aunque alguien manipule el HTML, no puede insertar/editar si su rol no lo permite. La UI solo refleja lo que el backend ya bloquea.

## ❓ Preguntas frecuentes

**P: Si abro `index.html` con doble click, ¿funciona?**
R: Sí, pero entra en **modo offline** (sin login, adicionales en localStorage del navegador). Para login + roles + datos compartidos necesitás servirlo por HTTP (local o GitHub Pages).

**P: ¿Qué pasa si una OT pasa de abierta a ejecutada?**
R: Nada que hacer. El adicional está keyed por `ot_id`. Al regenerar los datos (`generate_data.py`), la OT aparece en la pestaña ejecutadas con su adicional intacto.

**P: ¿Los lectores ven los adicionales que cargué?**
R: Sí. Los adicionales son globales — todos los ven igual.

**P: ¿Puedo dar acceso temporal a alguien externo?**
R: Sí. Pestaña Admin → Agregar `email@externo.com` con rol `lector`. Cuando quieras quitárselo: borralo desde la misma pestaña.

**P: ¿Datos en tiempo real?**
R: Por ahora hay que recargar la página para ver lo que cargó otro usuario. Si lo querés en vivo, hay que activar Supabase Realtime — siguiente iteración.

**P: ¿Y el screenshot a las 7am?**
R: TODO. Cuando confirmes que el dashboard funciona, armamos:
1. GitHub Action que corre `generate_data.py` lun-vie 7am Bogotá y commitea.
2. Servicio de screenshot (htmlcsstoimage.com) que toma foto del dashboard logueado.
3. Nodo en WF-G que postea la imagen en Slack con texto breve.
