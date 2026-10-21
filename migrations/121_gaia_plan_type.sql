-- Permitir las membresías GAIA que ya ofrecen los formularios del administrador.
-- Ejecutar en el SQL Editor de Supabase. No cambia membresías, visitas ni pagos.
-- La transacción conserva la validación anterior si ocurre algún error.
begin;

alter table public.profiles
  drop constraint if exists profiles_plan_type_check;

alter table public.profiles
  add constraint profiles_plan_type_check
  check (plan_type in ('individual', 'grupal', 'gaia') or plan_type is null);

commit;
