-- Gastos operativos de HABIT (renta, nómina, mantenimiento, insumos, etc.),
-- registrados por cualquiera de los admins (Arturo, David, Joseph).

CREATE TABLE IF NOT EXISTS habit_gastos (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo            text        NOT NULL CHECK (tipo IN ('renta','nomina','mantenimiento','limpieza','marketing','servicios','insumos','otros')),
  descripcion     text,
  monto           numeric     NOT NULL CHECK (monto >= 0),
  admin_id        uuid        REFERENCES profiles(id) ON DELETE SET NULL,
  comprobante_url text,
  fecha           date        NOT NULL DEFAULT CURRENT_DATE,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_habit_gastos_fecha ON habit_gastos(fecha);

ALTER TABLE habit_gastos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin full access habit_gastos"
  ON habit_gastos FOR ALL TO authenticated
  USING ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin')
  WITH CHECK ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin');

-- Ejecutar además manualmente en el dashboard de Supabase:
-- Storage → New bucket → Name: "habit-gastos" → Public: ON
-- (para poder subir foto de comprobante de cada gasto)
