-- 151 — Los avisos de admin se quedan en el teléfono del admin aunque cambie de cuenta.
--
-- 23 nov 2026: Joseph no recibía ni un aviso de reserva ni de compra. send-push sí mandaba
-- (logs: `push: done … sent: 1`), pero a una sola fila con role = 'admin', del 10 nov, que no
-- es el teléfono que usa. Su iPhone tiene sesión con su cuenta de socio y la de admin solo la
-- abre a ratos. Desde la 137 la llave de push_subscriptions es el DISPOSITIVO: al entrar con la
-- cuenta de socio, la fila de ese teléfono pasa al socio con role = 'user' y deja de recibir lo
-- del admin. Además la pantalla de admin no guardaba la suscripción al entrar (solo al abrir
-- Admin → Notificaciones), así que ni siquiera entrando como admin el teléfono se volvía de admin.
--
-- `admin_alerts_for` dice qué admin pidió los avisos del gym en este teléfono. Lo pone
-- save_push_subscription cuando quien guarda es admin, y se CONSERVA cuando otra cuenta toma
-- el mismo teléfono: un admin que también entrena con su cuenta de socio sigue recibiendo las
-- reservas y las compras. send-push manda a target 'admin' a las filas cuyo user_id o
-- admin_alerts_for es hoy un admin (si alguien deja de ser admin, deja de recibirlos).
-- El cliente no puede escribir la columna: solo la toca esta función, desde profiles.role.

alter table public.push_subscriptions
  add column if not exists admin_alerts_for uuid references public.profiles(id) on delete set null;

-- Lo que ya era de un admin, queda marcado.
update public.push_subscriptions
   set admin_alerts_for = user_id
 where role = 'admin' and admin_alerts_for is null;

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
  v_role := coalesce(v_role, 'user');
  insert into public.push_subscriptions (user_id, role, subscription, updated_at, admin_alerts_for)
  values (v_uid, v_role, p_subscription, now(), case when v_role = 'admin' then v_uid end)
  on conflict (endpoint) do update
    set user_id = excluded.user_id,
        role = excluded.role,
        subscription = excluded.subscription,
        updated_at = now(),
        admin_alerts_for = case
          when excluded.role = 'admin' then excluded.user_id
          else coalesce(push_subscriptions.admin_alerts_for,
                        case when push_subscriptions.role = 'admin' then push_subscriptions.user_id end)
        end;
end;
$$;

revoke all on function public.save_push_subscription(jsonb) from public;
revoke all on function public.save_push_subscription(jsonb) from anon;
grant execute on function public.save_push_subscription(jsonb) to authenticated;
