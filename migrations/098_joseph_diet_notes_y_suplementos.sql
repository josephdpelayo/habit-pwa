-- Datos personales de Joseph: el plan de alimentación real de su coach (Isma Hybrid Coach,
-- "Plan de alimentación · Joseph", inicio 7 junio 2026) cargado en diet_notes (migración 097)
-- para que "¿Qué como?" deje de dar consejo genérico de comida mexicana y se base en SU plan.
-- Es una carga de datos de una sola vez, idempotente, igual que la 086/095/095 para su semana
-- de descarga: no toca el prompt compartido de api/skandi.js, solo su propia fila.
--
-- Condensado a lo accionable (foco, estructura, alimentos, timing, prioriza/evita) — se deja
-- fuera el texto motivacional del PDF, que no cambia ninguna sugerencia.
--
-- También siembra sus 5 suplementos (misma dosis que el plan) en skandi_supplements, "por si
-- aún no estuvieran": solo inserta los que no tenga ya con ese nombre, no duplica si ya los
-- agregó a mano desde los presets de la tarjeta de Comida.

do $$
declare
  v_uid uuid := (select id from auth.users where email = 'josephdpelayo@gmail.com');
begin
  if v_uid is null then raise exception 'Ajusta el correo: no encontré el usuario.'; end if;

  update public.skandi_nutrition_targets
  set diet_notes = 'Plan de Isma Hybrid Coach (asesoramiento, recomposición). Objetivo por prioridad: 1) skills de calistenia, 2) ganar masa, 3) mantener el running. Recomposición: peso estable, mejora la composición. No se cuentan calorías estrictas — cantidades a ojo, por mano: 1-1,5 palmas de proteína, 1 puño de batata (más en días de carrera), dos manos de verdura, el pulgar de aceite.

Estructura: 5 tomas al día (desayuno, media mañana, comida, merienda, cena), misma base cada semana con rotación dentro de ella (no cambia el plan entero cada lunes).
- Proteína: pollo, ternera, huevos, atún, sardinas, yogur griego/kéfir, batido de proteína.
- Carbo prioritario: batata asada (200-250 g cocida). También avena (50-60 g crudo), pan de masa madre (1-2 rebanadas), fruta.
- Grasas: aceite de oliva virgen extra (1-2 cucharadas/comida), aguacate, frutos secos (~30 g), omega-3 del pescado azul.
- Verdura/ensalada en cada comida principal, mínimo 200 g.

Timing:
- Café 1-1,5 h después de despertar (no nada más levantarse).
- Antes de entrenar: carbo + fruta 1-2 h antes; nunca ayunos largos. Truco pre-entreno: un dátil partido con chocolate negro 95% dentro.
- Durante: solo si aplica por duración/intensidad de la sesión.
- Después: proteína + carbo en la siguiente comida (sin prisa por los 30 min).
- Cena ligera: proteína para reparar + verdura.
- Domingo: comida libre consciente (proteína a gusto + batata u otro carbo + verdura), el resto del día normal.
- En el barco: misma estructura con lo disponible — pollo/atún/sardinas/huevos, batata o patata o pan de masa madre, ensalada, fruta y frutos secos, batido para cerrar huecos.

Prioriza: pescado azul (sardinas, atún), verduras de hoja verde y crucíferas, frutos rojos, cúrcuma + jengibre, aceite de oliva virgen extra, frutos secos y aguacate, miel cruda (no procesada).
Evita: ultraprocesados y bollería, azúcares y dulces, aceites de semillas refinados, alcohol, bebidas energéticas y refrescos.
Hidratación: 2,5-3 L de agua al día, más en días de carrera o calor.'
  where user_id = v_uid;
  if not found then
    raise exception 'No hay fila en skandi_nutrition_targets para %: pon una meta primero desde la app (Comida → tarjeta de metas → Guardar).', v_uid;
  end if;

  insert into public.skandi_supplements (user_id, name, dose, timing, sort_order)
  select v_uid, x.name, x.dose, x.timing, x.sort_order
  from (values
    ('Creatina', '5 g', 'diario, cualquier hora', 0),
    ('Omega-3', '2 g (EPA+DHA)', 'diario', 1),
    ('Magnesio', '300-400 mg', 'en la noche', 2),
    ('Proteína whey', '1-2 scoops', 'cuando falte proteína del día', 3),
    ('Cúrcuma + pimienta negra', '', 'puntual, si hay dolor muscular/articular', 4)
  ) as x(name, dose, timing, sort_order)
  where not exists (
    select 1 from public.skandi_supplements s
    where s.user_id = v_uid and lower(s.name) = lower(x.name));

  raise notice 'Listo: diet_notes y suplementos cargados para %.', v_uid;
end;
$$;
