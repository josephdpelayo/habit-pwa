-- Skandi Fit: corrige el orden de dificultad de front-lever-straddle vs front-lever-half-lay.
--
-- La migración 078 puso straddle en rank 5 y half-lay en rank 6 (half-lay más difícil),
-- razonando que cerrar el straddle acorta la palanca y por eso "closing the straddle is a
-- bigger jump than it looks, expect the hold time to halve" (coach_tips de half-lay). Es el
-- consenso general de calistenia, pero Joseph entrena ambas variantes y, para él, straddle es
-- la más difícil de las dos -- probablemente por demanda de apertura de cadera, no por la
-- palanca. Esta migración invierte el rank (straddle=6, half-lay=5) y corrige el coach_tip que
-- quedaba contradictorio con el nuevo orden.
--
-- No hay riesgo para el progreso ya registrado: skandi_progression_state guarda exercise_id
-- (FK directo al ejercicio), no el número de rank, así que nadie que ya esté en straddle o
-- half-lay salta de escalón por este cambio -- solo cambia qué número de rank aparece en la
-- escalera y en qué orden se muestran. El catálogo es compartido con toda la tripulación, así
-- que esto reordena el front lever de todos, no solo el de Joseph.
--
-- progression_target (segundos para subir de rank) se queda en su ejercicio tal cual: cada
-- escalón conserva su propia meta, no la del rank vecino, así que no hay nada que reconciliar.

update public.skandi_exercises
   set progression_rank = 6
 where slug = 'front-lever-straddle';

update public.skandi_exercises
   set progression_rank = 5,
       coach_tips = array[
         'For some athletes this sits between straddle and full; for others, closing the legs together demands more than opening a wide straddle does. Go by your own hold time here, not the label.',
         'Bend at the knee, never at the hip, or this becomes an advanced tuck again.'
       ]
 where slug = 'front-lever-half-lay';
