-- Permite que un cliente tenga más de un entreno programado el mismo día
-- (antes coaching_schedule solo aceptaba uno por unique(user_id, ds)).

do $$
declare c text;
begin
  select conname into c from pg_constraint
  where conrelid = 'public.coaching_schedule'::regclass and contype = 'u';
  if c is not null then
    execute 'alter table public.coaching_schedule drop constraint ' || quote_ident(c);
  end if;
end $$;

-- Ya no hace falta el intercambio con fecha temporal (no hay más unique por
-- día) — mover un entreno a otro día es un simple update, puede coexistir
-- con lo que ya haya ese día.
create or replace function public.reorganize_coaching_day(p_schedule_id uuid, p_new_ds date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.coaching_schedule%rowtype;
begin
  select * into v_row from public.coaching_schedule where id = p_schedule_id;
  if not found or v_row.user_id <> auth.uid() then
    raise exception 'not authorized';
  end if;
  if v_row.status <> 'scheduled' then
    raise exception 'solo se pueden mover entrenos programados (no completados)';
  end if;
  update public.coaching_schedule set ds = p_new_ds where id = p_schedule_id;
end;
$$;
