-- Assign beginner/default routines to each new HABIT member.
-- HABIT marks beginner routines with the blue board color.

create or replace function public.default_member_board_ids()
returns table(board_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select b.id
  from public.boards b
  where lower(coalesce(b.color,'')) = '#2563eb'
  order by b.created_at asc;
$$;

create or replace function public.assign_default_member_boards(p_user_id uuid default auth.uid())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_is_admin boolean := false;
  v_count integer := 0;
begin
  if p_user_id is null then
    return 0;
  end if;

  select * into v_profile
  from public.profiles
  where id = p_user_id;

  if not found or v_profile.role <> 'user' or coalesce(v_profile.source,'habit') <> 'habit' then
    return 0;
  end if;

  if auth.uid() is not null and auth.uid() <> p_user_id then
    select exists(
      select 1 from public.profiles
      where id = auth.uid() and role = 'admin'
    ) into v_is_admin;

    if not v_is_admin then
      raise exception 'No autorizado';
    end if;
  end if;

  insert into public.board_assignments (board_id, user_id)
  select board_id, p_user_id
  from public.default_member_board_ids()
  on conflict do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.assign_default_member_boards_on_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'user' and coalesce(new.source,'habit') = 'habit' then
    perform public.assign_default_member_boards(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists assign_default_member_boards_after_profile_insert on public.profiles;
create trigger assign_default_member_boards_after_profile_insert
after insert on public.profiles
for each row
execute function public.assign_default_member_boards_on_profile_insert();

grant execute on function public.default_member_board_ids() to authenticated, service_role;
grant execute on function public.assign_default_member_boards(uuid) to authenticated, service_role;
