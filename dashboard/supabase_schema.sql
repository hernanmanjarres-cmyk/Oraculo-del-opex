-- ═══════════════════════════════════════════════════════════════
-- Dashboard OPEX Activación — schema de Supabase
-- Ejecutar EN SUPABASE (SQL Editor), proyecto del Oráculo del OPEX.
-- Crea tablas, políticas RLS y siembra el super_admin inicial.
-- ═══════════════════════════════════════════════════════════════


-- ── 1) USUARIOS Y ROLES ────────────────────────────────────────────────
-- Cada email autenticado tiene un rol. El email proviene de auth.users.
-- Roles: 'lector' (solo lee), 'usuario' (lee + edita adicionales),
--        'super_admin' (todo + administra roles)

CREATE TABLE IF NOT EXISTS public.dashboard_users (
  email          TEXT PRIMARY KEY,
  role           TEXT NOT NULL DEFAULT 'lector'
                 CHECK (role IN ('lector', 'usuario', 'super_admin')),
  display_name   TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_by     TEXT
);

-- Seed: super_admin inicial
INSERT INTO public.dashboard_users (email, role, display_name, updated_by)
VALUES ('hernan.manjarres@bia.app', 'super_admin', 'Hernán Manjarrés', 'system')
ON CONFLICT (email) DO UPDATE
  SET role = 'super_admin',
      updated_at = NOW(),
      updated_by = 'system';


-- ── 2) GASTOS ADICIONALES POR OT (GLOBALES) ────────────────────────────
-- Un registro por OT. El "monto" se suma al forecast/ejecutado.
-- Como es global, lo cargás vos y todos los demás lo ven.

CREATE TABLE IF NOT EXISTS public.dashboard_adicionales (
  ot_id          TEXT PRIMARY KEY,        -- codigo_ot
  monto          NUMERIC NOT NULL DEFAULT 0,
  notas          TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_by     TEXT
);

CREATE INDEX IF NOT EXISTS idx_dashboard_adicionales_updated
  ON public.dashboard_adicionales (updated_at DESC);


-- ── 3) ROW-LEVEL SECURITY (RLS) ────────────────────────────────────────
-- Activar RLS y definir quién puede hacer qué.

ALTER TABLE public.dashboard_users        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dashboard_adicionales  ENABLE ROW LEVEL SECURITY;

-- ── Helper: función inline para obtener el rol del usuario actual ──────
CREATE OR REPLACE FUNCTION public.dashboard_role()
RETURNS TEXT LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT role FROM public.dashboard_users
     WHERE email = (SELECT email FROM auth.users WHERE id = auth.uid())),
    'none'  -- usuarios autenticados sin registro en dashboard_users
  );
$$;


-- ── Políticas sobre dashboard_users ────────────────────────────────────

-- Todo autenticado puede ver la tabla de usuarios (para que el dashboard
-- pueda mostrar quién está y sus roles).
DROP POLICY IF EXISTS "users_select_authenticated" ON public.dashboard_users;
CREATE POLICY "users_select_authenticated"
  ON public.dashboard_users FOR SELECT
  TO authenticated
  USING (TRUE);

-- Solo super_admin puede INSERT/UPDATE/DELETE en dashboard_users.
DROP POLICY IF EXISTS "users_write_super_admin" ON public.dashboard_users;
CREATE POLICY "users_write_super_admin"
  ON public.dashboard_users FOR ALL
  TO authenticated
  USING (public.dashboard_role() = 'super_admin')
  WITH CHECK (public.dashboard_role() = 'super_admin');


-- ── Políticas sobre dashboard_adicionales ──────────────────────────────

-- Todo autenticado puede LEER los adicionales (lectores incluidos).
DROP POLICY IF EXISTS "adic_select_authenticated" ON public.dashboard_adicionales;
CREATE POLICY "adic_select_authenticated"
  ON public.dashboard_adicionales FOR SELECT
  TO authenticated
  USING (TRUE);

-- usuario y super_admin pueden INSERT/UPDATE/DELETE adicionales.
DROP POLICY IF EXISTS "adic_write_usuario_or_admin" ON public.dashboard_adicionales;
CREATE POLICY "adic_write_usuario_or_admin"
  ON public.dashboard_adicionales FOR ALL
  TO authenticated
  USING (public.dashboard_role() IN ('usuario', 'super_admin'))
  WITH CHECK (public.dashboard_role() IN ('usuario', 'super_admin'));


-- ── 4) TRIGGER: actualizar updated_at en cada UPDATE ───────────────────
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dashboard_users_updated ON public.dashboard_users;
CREATE TRIGGER trg_dashboard_users_updated
  BEFORE UPDATE ON public.dashboard_users
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS trg_dashboard_adicionales_updated ON public.dashboard_adicionales;
CREATE TRIGGER trg_dashboard_adicionales_updated
  BEFORE UPDATE ON public.dashboard_adicionales
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


-- ═══════════════════════════════════════════════════════════════
-- Verificación
-- ═══════════════════════════════════════════════════════════════
-- SELECT 'dashboard_users' AS tabla, COUNT(*) AS filas FROM public.dashboard_users
-- UNION ALL
-- SELECT 'dashboard_adicionales', COUNT(*) FROM public.dashboard_adicionales;
--
-- SELECT email, role FROM public.dashboard_users;
