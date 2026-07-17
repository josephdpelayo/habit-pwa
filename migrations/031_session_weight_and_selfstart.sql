-- (1) Peso por serie durante una sesión en vivo, con memoria del último
-- peso levantado en ese ejercicio (se precarga desde user_scores al
-- sembrar las series) y "carry forward" a la siguiente serie al completar.
alter table public.coaching_session_sets add column if not exists weight numeric(6,2);

-- (2) Permite al cliente iniciar un entreno directo desde "Tus rutinas"
-- (board_assignments) sin depender de que el admin haya programado el
-- día en coaching_schedule primero. Antes solo el admin podía insertar
-- filas en coaching_schedule ("Admin manage coaching schedule" es la
-- única política con insert); esta política nueva es estrictamente más
-- permisiva (agrega insert propio), no reemplaza ninguna existente.
drop policy if exists "Users insert own coaching schedule" on public.coaching_schedule;
create policy "Users insert own coaching schedule"
  on public.coaching_schedule for insert
  with check (auth.uid() = user_id);
