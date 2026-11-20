-- 150 · El recordatorio «Tu sesión es en 1 hora» por fin corre solo.
--
-- La función send-reminders existía desde mayo 2026, pero nada la llamaba: no había pg_cron
-- y ninguna reserva tuvo nunca reminder_sent_at (revisado el 20 nov 2026). Este cron la llama
-- cada 10 minutos; ella avisa lo que empieza en 50–80 min y marca la reserva, así que cada
-- reserva se avisa una vez. send-reminders tiene verify_jwt = false: la llamada no lleva
-- llave y no hay que guardar ningún secreto en la base.
--
-- Para apagarlo: select cron.unschedule('habit-send-reminders');

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'habit-send-reminders') then
    perform cron.unschedule('habit-send-reminders');
  end if;
end $$;

select cron.schedule(
  'habit-send-reminders',
  '*/10 * * * *',
  $cron$
    select net.http_post(
      url := 'https://pmpjteuqjusbiduevbwq.supabase.co/functions/v1/send-reminders',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := '{}'::jsonb,
      timeout_milliseconds := 20000
    );
  $cron$
);
