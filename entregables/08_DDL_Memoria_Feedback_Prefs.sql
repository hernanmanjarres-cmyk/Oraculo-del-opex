-- =====================================================
-- Memoria larga, feedback y preferencias del Oráculo
-- =====================================================

-- Historial de conversaciones
CREATE TABLE IF NOT EXISTS agent_memory (
  id            SERIAL PRIMARY KEY,
  user_id       TEXT NOT NULL,
  session_id    TEXT,
  question      TEXT NOT NULL,
  answer        TEXT NOT NULL,
  channel_id    TEXT,
  thread_ts     TEXT,
  feedback      SMALLINT DEFAULT NULL CHECK (feedback IN (-1, 1)),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_agent_memory_user_id ON agent_memory(user_id, created_at DESC);

-- Preferencias por usuario
CREATE TABLE IF NOT EXISTS agent_user_prefs (
  user_id        TEXT PRIMARY KEY,
  display_name   TEXT,
  response_style TEXT DEFAULT 'balanced' CHECK (response_style IN ('concise','balanced','detailed')),
  notes          TEXT DEFAULT '',
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Nota de feedback para 👎 (qué debería mejorar el Oráculo)
ALTER TABLE agent_memory ADD COLUMN IF NOT EXISTS feedback_note TEXT;
