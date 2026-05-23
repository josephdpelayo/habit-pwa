-- Historial de scores/PRs por ejercicio por usuario
CREATE TABLE IF NOT EXISTS user_scores (
  id          uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid         NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  board_id    text         NOT NULL,
  ex_idx      integer      NOT NULL,
  ex_name     text         NOT NULL,
  weight      numeric(6,2) NOT NULL,
  reps        text,
  logged_at   timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE user_scores ENABLE ROW LEVEL SECURITY;

-- Usuarios gestionan sus propios registros
CREATE POLICY "Users manage own scores"
  ON user_scores FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Admin puede ver todos (para leaderboard)
CREATE POLICY "Admin view all scores"
  ON user_scores FOR SELECT TO authenticated
  USING ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin');

CREATE INDEX IF NOT EXISTS user_scores_user_ex
  ON user_scores(user_id, board_id, ex_idx, logged_at DESC);
