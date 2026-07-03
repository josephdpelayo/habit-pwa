-- Modelo de 4 cuentas: Gym (banco del negocio) + Joseph + Arturo + David.
-- Cada gasto ahora indica de qué cuenta salió el dinero real (no solo quién
-- lo registró en el sistema, que sigue siendo admin_id).
-- Los gastos pagados por un socio de su bolsillo se reparten 1/3 entre los
-- 3 socios; los pagados por "gym" no generan deuda entre socios (ya son del
-- negocio, que es 1/3 de cada quien).

ALTER TABLE habit_gastos
  ADD COLUMN IF NOT EXISTS cuenta text NOT NULL DEFAULT 'gym'
    CHECK (cuenta IN ('gym','joseph','arturo','david'));

-- Retiro: dinero que sale de la cuenta del gym hacia la cuenta personal de un socio.
CREATE TABLE IF NOT EXISTS habit_retiros (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  socio       text        NOT NULL CHECK (socio IN ('joseph','arturo','david')),
  monto       numeric     NOT NULL CHECK (monto >= 0),
  descripcion text,
  admin_id    uuid        REFERENCES profiles(id) ON DELETE SET NULL,
  fecha       date        NOT NULL DEFAULT CURRENT_DATE,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_habit_retiros_fecha ON habit_retiros(fecha);

-- Pago de deuda entre socios: liquidación directa (ej. "David le pagó a Joseph
-- $9,231 para saldar parte de lo que le debía"). No es un gasto del negocio,
-- solo ajusta el balance de deuda entre los 2 socios involucrados.
CREATE TABLE IF NOT EXISTS habit_deuda_pagos (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  de_socio    text        NOT NULL CHECK (de_socio IN ('joseph','arturo','david')),
  para_socio  text        NOT NULL CHECK (para_socio IN ('joseph','arturo','david')),
  monto       numeric     NOT NULL CHECK (monto >= 0),
  descripcion text,
  admin_id    uuid        REFERENCES profiles(id) ON DELETE SET NULL,
  fecha       date        NOT NULL DEFAULT CURRENT_DATE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (de_socio <> para_socio)
);
CREATE INDEX IF NOT EXISTS idx_habit_deuda_pagos_fecha ON habit_deuda_pagos(fecha);

ALTER TABLE habit_retiros ENABLE ROW LEVEL SECURITY;
ALTER TABLE habit_deuda_pagos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin full access habit_retiros"
  ON habit_retiros FOR ALL TO authenticated
  USING ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin')
  WITH CHECK ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin');

CREATE POLICY "Admin full access habit_deuda_pagos"
  ON habit_deuda_pagos FOR ALL TO authenticated
  USING ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin')
  WITH CHECK ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin');
