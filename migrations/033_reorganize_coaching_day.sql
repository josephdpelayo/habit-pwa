-- Permite al cliente mover un entreno programado (no completado) a otro día
-- de la misma semana — ej. le tocaba lunes pero lo hará hasta el martes.
-- Si el día destino ya tiene un entreno programado, los intercambia.

create or replace function public.reorganize_coaching_day(p_schedule_id uuid, p_new_ds date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.coaching_schedule%rowtype;
  v_other public.coaching_schedule%rowtype;
begin
  select * into v_row from public.coaching_schedule where id = p_schedule_id;
  if not found or v_row.user_id <> auth.uid() then
    raise exception 'not authorized';
  end if;
  if v_row.status <> 'scheduled' then
    raise exception 'solo se pueden mover entrenos programados (no completados)';
  end if;
  if v_row.ds = p_new_ds then
    return;
  end if;

  select * into v_other from public.coaching_schedule where user_id = v_row.user_id and ds = p_new_ds;

  if found then
    if v_other.status <> 'scheduled' then
      raise exception 'no se puede mover a un día ya completado';
    end if;
    -- Fecha temporal fuera de rango para esquivar el unique(user_id, ds)
    -- mientras se hace el intercambio.
    update public.coaching_schedule set ds = '9999-12-31' where id = v_row.id;
    update public.coaching_schedule set ds = v_row.ds where id = v_other.id;
    update public.coaching_schedule set ds = p_new_ds where id = v_row.id;
  else
    update public.coaching_schedule set ds = p_new_ds where id = v_row.id;
  end if;
end;
$$;

grant execute on function public.reorganize_coaching_day(uuid, date) to authenticated;
