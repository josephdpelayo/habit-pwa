-- Permite que el cliente elimine de verdad sus propios entrenos.
-- Sin esta politica, Supabase puede devolver exito con 0 filas afectadas
-- bajo RLS y la app parecia borrar solo localmente.

drop policy if exists "Users delete own coaching schedule" on public.coaching_schedule;
create policy "Users delete own coaching schedule"
  on public.coaching_schedule for delete
  using (auth.uid() = user_id);
