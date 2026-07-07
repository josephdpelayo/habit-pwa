-- Distingue a los socios con visitas regaladas (cortesía) de los que
-- realmente pagaron su membresía/visitas. Antes, una cortesía de 3 (o 1)
-- visitas les asignaba el mismo plan_id que un cliente que sí pagó
-- (ej. "Visita del día"), así que quedaban indistinguibles en la lista
-- de Socios. Ahora se marca explícitamente cuando el plan/créditos
-- vigentes vienen de un regalo, para poder filtrarlos aparte.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS plan_is_courtesy boolean NOT NULL DEFAULT false;
