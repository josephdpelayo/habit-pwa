-- Corrige las metas de nutrición de la semana de descarga de Joseph, 24-30 de agosto de 2026,
-- cargadas en la migración 095: el coach había mandado martes, viernes y sábado con menos
-- calorías/carbohidratos de los que en realidad tocaban para esos días de mayor entrenamiento.
-- Mismo patrón que la 095 (upsert idempotente sobre skandi_nutrition_target_overrides, migración
-- 094): se corre igual en el SQL Editor y no duplica nada. Lunes, miércoles, jueves y domingo no
-- cambian — se repiten aquí para dejar la semana completa en un solo lugar consultable.

do $$
declare
  v_uid uuid := (select id from auth.users where email = 'josephdpelayo@gmail.com');
  v_mon date := date '2026-08-24';
begin
  if v_uid is null then raise exception 'Ajusta el correo: no encontré el usuario.'; end if;

  insert into public.skandi_nutrition_target_overrides
    (user_id, target_date, kcal_target, protein_g_target, carbs_g_target, fat_g_target, note)
  values
    (v_uid, v_mon,     2400, 145, 300, 70, 'Descarga · Lunes · Front Lever A + Pull'),
    (v_uid, v_mon + 1, 2500, 145, 325, 69, 'Descarga · Martes · Handstand + Push + Pierna + Z2'),
    (v_uid, v_mon + 2, 2200, 145, 245, 71, 'Descarga · Miércoles · Descanso / desembarque'),
    (v_uid, v_mon + 3, 2350, 145, 285, 70, 'Descarga · Jueves · Front Lever B + Muscle-Up'),
    (v_uid, v_mon + 4, 2400, 145, 300, 70, 'Descarga · Viernes · Full Body + Planche'),
    (v_uid, v_mon + 5, 2650, 145, 365, 68, 'Descarga · Sábado · Carrera + HIIT del convivio'),
    (v_uid, v_mon + 6, 2200, 145, 245, 71, 'Descarga · Domingo · Descanso completo')
  on conflict (user_id, target_date) do update set
    kcal_target      = excluded.kcal_target,
    protein_g_target = excluded.protein_g_target,
    carbs_g_target   = excluded.carbs_g_target,
    fat_g_target     = excluded.fat_g_target,
    note             = excluded.note;

  raise notice 'Listo: metas de descarga corregidas del % al %.', v_mon, v_mon + 6;
end;
$$;
