-- Endurece las políticas UPDATE de Coaching que solo tenían USING, sin
-- WITH CHECK explícito. Postgres ya usa USING como fallback para el
-- chequeo de la fila nueva cuando WITH CHECK se omite, así que esto no
-- cambia el comportamiento real hoy — lo deja explícito para no depender
-- de ese comportamiento implícito, y sienta la base por si algún día
-- estas columnas (duration_sec, status) alimentan algo con valor real
-- (rankings, facturación).

ALTER POLICY "Users update own coaching schedule"
  ON public.coaching_schedule
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY "Users update own coaching tasks"
  ON public.coaching_tasks
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY "Users update own conversation"
  ON public.coaching_messages
  WITH CHECK (auth.uid() = user_id);
