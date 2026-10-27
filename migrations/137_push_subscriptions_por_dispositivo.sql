-- 137 — Avisos (web push): una suscripción por dispositivo, guardada por el servidor.
--
-- Desde el 18 may 2026 ningún socio guardaba su suscripción: un "hard revert" (60da6cc) quitó
-- las llamadas a registerPush() y en oct quedaban 3 filas (2 socios de mayo y el admin). La app
-- vuelve a guardarlas (ver ensurePushSubscription en app.html), y esta migración arregla la tabla
-- para que eso funcione bien:
--
-- 1. La llave era la persona (`push_subscriptions_user_id_idx`, un índice único sobre user_id
--    que no aparece en pg_constraint por ser solo índice): un dispositivo nuevo pisaba al
--    anterior, y el upsert del socio, sin on_conflict, chocaba con él desde la segunda vez. Ahora
--    la llave es el dispositivo (`endpoint`, la URL a la que se manda el aviso): quien tiene
--    iPhone y iPad recibe en los dos. Ese índice se quita; sin quitarlo, save_push_subscription
--    falla con 23505 para cualquiera que ya tenga una fila de otro dispositivo.
-- 2. Guardar pasa por save_push_subscription(), security definer. Un mismo teléfono que cambia
--    de cuenta (cerrar sesión y entrar con otra) trae el mismo endpoint: la fila tiene que pasar a
--    la cuenta nueva, y la RLS no deja al socio tocar la fila de otro. Sin esto, los avisos de la
--    cuenta anterior le seguían llegando a quien usa ese teléfono ahora. El `role` lo pone el
--    servidor desde profiles (send-push manda a target 'admin' por esta columna): el cliente no
--    puede declararse admin para recibir los avisos del gym.
-- 3. push_subscription_stats(): cuántos socios tienen avisos, para Admin → Notificaciones. La
--    política de lectura del admin que tiene la tabla mira virtus.auth_user_role(), que no es el
--    rol de HABIT, así que el admin no puede contarlas con una consulta normal.

alter table public.push_subscriptions
  add column if not exists endpoint text generated always as (subscription->>'endpoint') stored;

-- Si ya hay repetidas, se queda la más reciente de cada dispositivo.
delete from public.push_subscriptions ps
using (
  select id, row_number() over (partition by endpoint order by updated_at desc nulls last, created_at desc nulls last) as rn
  from public.push_subscriptions
  where endpoint is not null
) d
where ps.id = d.id and d.rn > 1;

create unique index if not exists push_subscriptions_endpoint_key on public.push_subscriptions (endpoint);
drop index if exists public.push_subscriptions_user_id_idx;

create or replace function public.save_push_subscription(p_subscription jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if jsonb_typeof(p_subscription) <> 'object' or coalesce(p_subscription->>'endpoint', '') = '' then
    raise exception 'subscription without endpoint';
  end if;
  select coalesce(p.role, 'user') into v_role from public.profiles p where p.id = v_uid;
  insert into public.push_subscriptions (user_id, role, subscription, updated_at)
  values (v_uid, coalesce(v_role, 'user'), p_subscription, now())
  on conflict (endpoint) do update
    set user_id = excluded.user_id,
        role = excluded.role,
        subscription = excluded.subscription,
        updated_at = now();
end;
$$;

create or replace function public.push_subscription_stats()
returns table (members integer, devices integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'not authorized';
  end if;
  return query
    select count(distinct ps.user_id)::integer, count(*)::integer
    from public.push_subscriptions ps
    join public.profiles p on p.id = ps.user_id
    where p.role = 'user';
end;
$$;

-- Supabase da EXECUTE a anon en toda función nueva de public (ver 124): se quita explícito.
revoke all on function public.save_push_subscription(jsonb) from public, anon;
revoke all on function public.push_subscription_stats() from public, anon;
grant execute on function public.save_push_subscription(jsonb) to authenticated;
grant execute on function public.push_subscription_stats() to authenticated;
