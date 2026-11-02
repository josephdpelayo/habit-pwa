-- 144 · Escaleras de skills sin coach: el alumno pone su propio escalón.
--
-- La 141 hizo coach_student_skills de solo lectura para el alumno, porque en el 1:1 el
-- escalón lo mueve quien ve el video. Pero en HABIT Crew casi nadie tiene coach (2 nov 2026:
-- cero filas en la tabla), y la escalera les decía «tu coach todavía no te ha puesto un
-- escalón» en las siete líneas: la pestaña Skills no llevaba a ningún lado.
--
-- La regla nueva no cambia la de la 141, la parte en dos según QUIÉN puso la fila:
--
--   · set_by = el propio alumno  → la fila es suya: la crea, la mueve y la borra.
--   · set_by = otra persona      → la puso su coach y sigue siendo solo del coach.
--
-- Una sola columna lo decide, la que ya existía (set_by), así que no hace falta otra para
-- distinguirlas. En cuanto el coach toma una línea (su upsert escribe set_by = él), el alumno
-- deja de poder moverla; si el coach borra la fila, el alumno vuelve a poder elegir.
-- Un coach cuya cuenta se borró deja set_by en null (on delete set null): esa fila queda como
-- estaba, de solo lectura, que es lo prudente cuando no se sabe quién la decidió.
--
-- El alumno no escribe coach_note: «De tu coach» tiene que ser del coach.
--
-- El historial (coach_skill_events) no cambia: su trigger es security definer e historia
-- también los movimientos propios, con set_by = el alumno.
--
-- Requiere la 141.

begin;

drop policy if exists "Students insert own self-set skills" on public.coach_student_skills;
create policy "Students insert own self-set skills"
  on public.coach_student_skills for insert
  to authenticated
  with check (auth.uid() = user_id and set_by = auth.uid() and coach_note is null);

-- USING mira la fila como estaba (tiene que ser suya y puesta por él); WITH CHECK, como queda.
-- Un upsert del cliente sobre una fila que puso el coach choca con el USING y falla: es el
-- candado que impide que el alumno pise lo que decidió su coach.
drop policy if exists "Students update own self-set skills" on public.coach_student_skills;
create policy "Students update own self-set skills"
  on public.coach_student_skills for update
  to authenticated
  using (auth.uid() = user_id and set_by = auth.uid())
  with check (auth.uid() = user_id and set_by = auth.uid() and coach_note is null);

drop policy if exists "Students delete own self-set skills" on public.coach_student_skills;
create policy "Students delete own self-set skills"
  on public.coach_student_skills for delete
  to authenticated
  using (auth.uid() = user_id and set_by = auth.uid());

comment on table public.coach_student_skills is
  'El escalón del alumno en una línea. set_by = el alumno: lo eligió él y lo mueve él (144). set_by = otra persona: lo puso su coach y solo el coach lo mueve (141).';

commit;
