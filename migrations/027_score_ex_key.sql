-- Clave estable por ejercicio para historial de peso, independiente del
-- índice del array exercises[] (que puede reordenarse/eliminarse).
-- ex_idx se conserva tal cual (NOT NULL, informativo) para no romper nada
-- existente; ex_key es la clave real de agrupación para lecturas nuevas.
ALTER TABLE user_scores ADD COLUMN IF NOT EXISTS ex_key text;

CREATE INDEX IF NOT EXISTS user_scores_user_exkey
  ON user_scores(user_id, ex_key, logged_at DESC)
  WHERE ex_key IS NOT NULL;
