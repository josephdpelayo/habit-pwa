-- Metas de nutrición de la semana de descarga de Joseph, 24-30 de agosto de 2026, tal como las
-- dio su coach. NO es una migración de esquema (esa es la 094, que crea la tabla que esto usa):
-- es una carga de datos de una sola vez, igual que la 086 lo fue para las rutinas de esa misma
-- semana. Se corre igual en el SQL Editor y es idempotente (on conflict actualiza, no duplica).
--
-- Proteína (145 g) y grasa (~70 g) casi no se mueven día a día en la tabla del coach — lo que
-- cambia es la energía total y los carbohidratos, más altos en los días de más entrenamiento
-- (sábado, carrera + HIIT) y más bajos en descanso/desembarque. Por eso protein_g_target y
-- fat_g_target sí se fijan explícitos por día en vez de dejarlos caer a la meta base: son los
-- números exactos que dio el coach, no un promedio.

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
    (v_uid, v_mon + 1, 2400, 145, 300, 70, 'Descarga · Martes · Handstand + Push + Pierna'),
    (v_uid, v_mon + 2, 2200, 145, 245, 71, 'Descarga · Miércoles · Descanso / desembarque'),
    (v_uid, v_mon + 3, 2350, 145, 285, 70, 'Descarga · Jueves · Front Lever B + Muscle-Up'),
    (v_uid, v_mon + 4, 2350, 145, 285, 70, 'Descarga · Viernes · Full Body + Planche'),
    (v_uid, v_mon + 5, 2600, 145, 350, 69, 'Descarga · Sábado · Carrera + HIIT del convivio'),
    (v_uid, v_mon + 6, 2200, 145, 245, 71, 'Descarga · Domingo · Descanso completo')
  on conflict (user_id, target_date) do update set
    kcal_target      = excluded.kcal_target,
    protein_g_target = excluded.protein_g_target,
    carbs_g_target   = excluded.carbs_g_target,
    fat_g_target     = excluded.fat_g_target,
    note             = excluded.note;

  raise notice 'Listo: metas de descarga cargadas del % al %.', v_mon, v_mon + 6;
end;
$$;
