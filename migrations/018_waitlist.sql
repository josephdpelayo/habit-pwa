-- Tabla persistente de lista de espera por slot
CREATE TABLE IF NOT EXISTS slot_waitlist (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  ds          text        NOT NULL,          -- 'YYYY-MM-DD'
  slot_idx    integer     NOT NULL,          -- 0-47
  user_id     uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name        text,
  phone       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE(ds, slot_idx, user_id)
);

ALTER TABLE slot_waitlist ENABLE ROW LEVEL SECURITY;

-- Admin gestiona todo
CREATE POLICY "Admin full access slot_waitlist"
  ON slot_waitlist FOR ALL TO authenticated
  USING ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin')
  WITH CHECK ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin');

-- Usuarios ven sus propias entradas
CREATE POLICY "Users select own slot_waitlist"
  ON slot_waitlist FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Usuarios se agregan a sí mismos
CREATE POLICY "Users insert own slot_waitlist"
  ON slot_waitlist FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Usuarios se eliminan a sí mismos
CREATE POLICY "Users delete own slot_waitlist"
  ON slot_waitlist FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Índice para consultas por fecha
CREATE INDEX IF NOT EXISTS slot_waitlist_ds_idx ON slot_waitlist(ds);
CREATE INDEX IF NOT EXISTS slot_waitlist_user_idx ON slot_waitlist(user_id);
