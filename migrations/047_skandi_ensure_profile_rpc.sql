-- Some Skandi Fit signups ended up with an auth.users row but no matching
-- public.profiles row (the on_auth_user_created trigger in 001_schema.sql can
-- fail, e.g. on an access_code collision race between two concurrent signups,
-- which rolls back its own insert). Every Skandi Fit write is FK'd to
-- profiles(id), so an affected user could never save anything (create a
-- routine, log a set, etc) and had no way to self-heal.
--
-- RLS already allows a user to insert their own profile row ("Service inserts
-- own profile" in 001_schema.sql), but nothing in the client ever attempted
-- it. This RPC does that insert safely (same access_code-uniqueness loop as
-- the trigger) and is a no-op if the profile already exists.

create or replace function public.ensure_own_profile(p_name text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if exists (select 1 from public.profiles where id = auth.uid()) then
    return;
  end if;

  loop
    v_code := lpad(floor(random()*9000+1000)::text, 4, '0');
    exit when not exists (select 1 from public.profiles where access_code = v_code);
  end loop;

  insert into public.profiles (id, name, access_code)
  values (auth.uid(), coalesce(nullif(trim(p_name), ''), 'Crew member'), v_code)
  on conflict (id) do nothing;
end;
$$;

grant execute on function public.ensure_own_profile(text) to authenticated;
