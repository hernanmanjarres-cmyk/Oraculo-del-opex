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

### Paso 2 — Habilitar Magic Link en Supabase Auth

1. Supabase → **Authentication** → **Providers**.
2. Activar **Email**: ON. Magic link viene activado por defecto.
3. **Authentication** → **URL Configuration**:
   - **Site URL**: la URL donde vas a hostear el HTML (ej: GitHub Pages `https://hernanmanjarres-cmyk.github.io/Oraculo-del-opex/`).
     - Si querés probar local, ponete `http://localhost:8080` también.
   - **Redirect URLs**: agregá la misma URL al allowlist.

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
python3 -m http.server 8080
```

Abrí `http://localhost:8080` en el navegador.

> ⚠️ Magic link requiere **server real** (no doble click en `file://`). Para probar localmente, usá `python3 -m http.server`. Para abrir directo (doble click) usá modo offline (no pongas URL de Supabase).

1. Ingresá tu correo → recibís email con link.
2. Click en el link → te logueás automáticamente.
3. Como sos `super_admin`, vas a ver las 4 pestañas (incluida Admin).
4. Probá agregar otro usuario en la pestaña Admin con rol `lector` o `usuario`.

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
