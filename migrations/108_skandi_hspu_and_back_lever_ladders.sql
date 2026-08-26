-- Skandi Fit: escalera de HSPU (no existía ninguna) + escalera de Back Lever completa.
--
-- HSPU (Handstand Push-Up) es, junto con el handstand en sí, uno de los dos skills que Joseph
-- entrena activamente ahora mismo. El catálogo tenía dos ejercicios de HSPU sueltos, sin
-- progression_group, mientras Front Lever, Handstand, Planche, Muscle-Up y Nordic Curl ya tienen
-- escalera completa (progression_rank + progression_target + progression_criteria +
-- progression_target_sets + track_quality, migraciones 059/067/078/079). Esta migración cierra
-- ese hueco con 6 escalones: pike push-up -> pike elevado -> negativas en pared -> HSPU en pared
-- (rango completo) -> HSPU en pared con déficit -> HSPU freestanding.
--
-- Se revisaron también Planche, Muscle-Up y Back Lever, que ya tenían progression_group desde
-- las migraciones 059/067. Planche (5 escalones: lean/tuck/advanced-tuck/straddle/full) y
-- Muscle-Up (4: chest-to-bar/false-grip/negativo/bar) resultaron ser exactamente el
-- progression_criteria + progression_target_sets + track_quality=true que la migración 078 ya
-- les puso en su sección 7 -- no les falta nada, no se tocan.
--
-- Back Lever sí se quedó corto: 3 escalones (tuck/straddle/full) frente a los 6-8 que tienen las
-- demás líneas, sin escalón de entrada ni paso intermedio entre tuck y straddle -- el mismo
-- hueco que la 078 diagnosticó y cerró para front lever (que pasó de un orden confuso de 6 a 8
-- escalones bien puestos). Se resuelve igual: reutiliza el ya existente skin-the-cat (que hoy
-- vive suelto en el catálogo y es exactamente la entrada estándar al back lever) como rank 1, y
-- agrega advanced tuck + one-leg entre tuck y straddle.
--
-- Igual que en la migración 107: skandi_progression_state guarda exercise_id, no el número de
-- rank, así que renumerar back-lever-tuck/straddle/full no mueve a nadie de escalón, solo
-- reordena la escalera. El catálogo es compartido con toda la tripulación.

-- ---------------------------------------------------------------------------------------
-- 1. Ejercicios nuevos
-- ---------------------------------------------------------------------------------------

insert into public.skandi_exercises
  (slug, name, english_name, category, equipment, muscles, instructions, coach_tips, log_mode)
values
  ('elevated-pike-push-up','Elevated Pike Push-Up','Elevated Pike Push-Up','Calisthenics','{"Box","Bodyweight"}','{"Shoulders":58,"Triceps":27,"Core":15}'::jsonb,
   '{"Set up in a pike position with your feet on a box or bench, hands on the floor under your shoulders.","Walk your hands in until your hips are stacked high and your torso is close to vertical.","Bend your elbows to lower the crown of your head toward the floor between your hands.","Press back up to full lockout without letting your hips drop."}',
   '{"The higher the box, the closer this gets to a real handstand push-up angle.","If your hips sag on the way up you added too much height too soon, lower the box."}',
   'reps'),
  ('wall-hspu-negative','Wall HSPU Negative','Wall HSPU Negative','Calisthenics','{"Wall","Bodyweight"}','{"Shoulders":55,"Triceps":25,"Core":20}'::jsonb,
   '{"Kick up into a wall handstand, chest facing the wall.","Lower yourself as slowly as you can control, fighting the descent the whole way.","Let your head touch down lightly, then walk or roll out of the position instead of pressing back up.","Reset at the wall and repeat."}',
   '{"This is the descent alone, no press back up yet -- that is the next rank in the line.","A negative that free-falls the last third teaches nothing, slow the whole rep down before adding more."}',
   'reps'),
  ('deficit-wall-hspu','Deficit Wall HSPU','Deficit Wall HSPU','Calisthenics','{"Wall","Parallettes","Bodyweight"}','{"Shoulders":55,"Triceps":32,"Core":13}'::jsonb,
   '{"Set a pair of parallettes or blocks about shoulder-width apart against the wall.","Kick up into a handstand with your hands on the blocks, chest facing the wall.","Lower your head down past the level of your hands, going deeper than the floor would allow.","Press back up to full lockout."}',
   '{"Only add the deficit once bodyweight wall HSPU is 5+ clean reps, the extra range punishes a weak lockout.","Keep the blocks close enough together that your wrists stay stacked under your shoulders."}',
   'reps'),
  ('freestanding-hspu','Freestanding HSPU','Freestanding HSPU','Calisthenics','{"Bodyweight"}','{"Shoulders":50,"Triceps":30,"Core":20}'::jsonb,
   '{"Kick up into a freestanding handstand away from any wall.","Bend your elbows to lower your head toward the floor while balancing.","Press back up to full lockout, using your fingers and wrists to correct any drift.","Come down with control the moment the balance or the line breaks."}',
   '{"The balance disappears the moment you focus only on the press, keep drilling the freestanding hold until it is boring.","A wall spot nearby is fine while you build confidence, the point is not needing to use it."}',
   'reps'),
  ('back-lever-advanced-tuck','Back Lever Advanced Tuck','Back Lever Advanced Tuck','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":46,"Shoulders":25,"Core":21,"Forearms":8}'::jsonb,
   '{"Set up as in the tuck back lever, arms straight and shoulders rotated to face away from the bar.","Open the hips so your knees move away from your chest while staying bent.","Keep your lower back flat and hips level with the shoulders.","Hold, then rotate back up to the support position."}',
   '{"Opening the hips even a little from the tuck is a real jump, expect the hold time to drop.","Keep the knees bent and close together, this is not a straddle yet."}',
   'seconds'),
  ('one-leg-back-lever','One-Leg Back Lever','One-Leg Back Lever','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":47,"Shoulders":24,"Core":21,"Forearms":8}'::jsonb,
   '{"Set up as in the back lever, arms straight and shoulders rotated away from the bar.","Extend one leg fully straight while keeping the other tucked to the chest.","Keep both hips level and the extended leg in line with the torso.","Hold, then switch which leg is extended between sets."}',
   '{"Alternate which leg leads the set, most people have a clear weak side here.","The extended leg does the work, do not let the tucked knee drift up to compensate."}',
   'seconds')
on conflict (slug) do update set
  name = excluded.name,
  english_name = excluded.english_name,
  category = excluded.category,
  equipment = excluded.equipment,
  muscles = excluded.muscles,
  instructions = excluded.instructions,
  coach_tips = excluded.coach_tips,
  log_mode = excluded.log_mode,
  updated_at = now();

-- ---------------------------------------------------------------------------------------
-- 2. HSPU: 6 escalones, pike en el suelo hasta freestanding
-- ---------------------------------------------------------------------------------------

update public.skandi_exercises set
  progression_group='hspu', progression_rank=1, log_mode='reps', track_quality=true,
  progression_target=12, progression_target_sets=2,
  progression_criteria='Hips stay high the whole rep, head lightly grazes the floor between your hands, no forward drift into a shoulder press.'
where slug='pike-push-up';

update public.skandi_exercises set
  progression_group='hspu', progression_rank=2, log_mode='reps', track_quality=true,
  progression_target=10, progression_target_sets=2,
  progression_criteria='Feet on a box roughly knee height, hips stay stacked over the shoulders, full lockout at the top every rep.'
where slug='elevated-pike-push-up';

update public.skandi_exercises set
  progression_group='hspu', progression_rank=3, log_mode='reps', track_quality=true,
  progression_target=5, progression_target_sets=2,
  progression_criteria='Each descent takes 3+ seconds under control, chest and thighs stay against the wall, no free-falling the last third.'
where slug='wall-hspu-negative';

update public.skandi_exercises set
  progression_group='hspu', progression_rank=4, log_mode='reps', track_quality=true,
  progression_target=5, progression_target_sets=2,
  progression_criteria='Chest and thighs stay against the wall the whole rep, head taps the floor, full lockout at the top, no banana back.'
where slug='handstand-push-up-wall';

update public.skandi_exercises set
  progression_group='hspu', progression_rank=5, log_mode='reps', track_quality=true,
  progression_target=5, progression_target_sets=2,
  progression_criteria='Hands on blocks with head dropping below hand level, chest stays against the wall, full lockout at the top.'
where slug='deficit-wall-hspu';

update public.skandi_exercises set
  progression_group='hspu', progression_rank=6, log_mode='reps', track_quality=true,
  progression_target=null, progression_target_sets=1,
  progression_criteria='Final rank of the line. No wall for balance or support, full lockout at the top, line stays hollow throughout.'
where slug='freestanding-hspu';

-- ---------------------------------------------------------------------------------------
-- 3. Back Lever: 3 escalones -> 6. skin-the-cat entra como rank 1 (ya existía suelto),
--    advanced-tuck y one-leg llenan el hueco entre tuck y straddle.
-- ---------------------------------------------------------------------------------------

update public.skandi_exercises set
  progression_group='back-lever', progression_rank=1, track_quality=true,
  progression_target=5, progression_target_sets=2,
  progression_criteria='Straight arms through the whole rotation, controlled tempo down and back up, no swinging or bent elbows.'
where slug='skin-the-cat';

update public.skandi_exercises set progression_rank=2
where slug='back-lever-tuck';

update public.skandi_exercises set
  progression_group='back-lever', progression_rank=3, log_mode='seconds', track_quality=true,
  progression_target=17, progression_target_sets=2,
  progression_criteria='Hips open further than the tuck with knees still bent, lower back flat, hips level with the shoulders.'
where slug='back-lever-advanced-tuck';

update public.skandi_exercises set
  progression_group='back-lever', progression_rank=4, log_mode='seconds', track_quality=true,
  progression_target=15, progression_target_sets=2,
  progression_criteria='One leg fully straight and in line with the torso, hips level with the shoulders. Alternate the working leg between sets.'
where slug='one-leg-back-lever';

update public.skandi_exercises set progression_rank=5
where slug='back-lever-straddle';

update public.skandi_exercises set progression_rank=6
where slug='back-lever-full';
