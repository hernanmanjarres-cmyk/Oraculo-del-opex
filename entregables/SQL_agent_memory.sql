-- ═══════════════════════════════════════════════════════════════
-- Tablas de memoria conversacional del Oráculo del OPEX (WF-B)
-- Ejecutar en Supabase (esquema public, NO Oraculo_Opex)
-- ═══════════════════════════════════════════════════════════════

-- 1) Historial de preguntas/respuestas por usuario
--    Cada interacción del usuario con el Oráculo se guarda aquí.
--    El agente usa los últimos 5 registros como contexto.
CREATE TABLE IF NOT EXISTS public.agent_memory (
  id          SERIAL PRIMARY KEY,
  user_id     TEXT NOT NULL,
  session_id  TEXT,
  question    TEXT NOT NULL,
  answer      TEXT,
  channel_id  TEXT,
  thread_ts   TEXT,
  feedback    INT DEFAULT 0,          -- 1=👍 (útil), -1=👎 (mejorar), 0=sin feedback
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Índice para que la query de historial sea rápida
CREATE INDEX IF NOT EXISTS idx_agent_memory_user_date
  ON public.agent_memory (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_agent_memory_session
  ON public.agent_memory (session_id, created_at DESC);


-- 2) Preferencias del usuario (estilo de respuesta, notas)
--    Cada user_id tiene UNA fila (UNIQUE).
CREATE TABLE IF NOT EXISTS public.agent_user_prefs (
  user_id         TEXT PRIMARY KEY,
  response_style  TEXT DEFAULT 'balanced'
    CHECK (response_style IN ('balanced', 'concise', 'detailed', 'technical')),
  notes           TEXT DEFAULT '',
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);


-- ═══════════════════════════════════════════════════════════════
-- Verificación rápida
-- ═══════════════════════════════════════════════════════════════
-- SELECT 'agent_memory' AS tabla, COUNT(*) FROM public.agent_memory
-- UNION ALL
-- SELECT 'agent_user_prefs', COUNT(*) FROM public.agent_user_prefs;
