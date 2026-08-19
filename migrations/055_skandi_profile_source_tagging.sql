-- HABIT and Skandi Fit share one Supabase Auth + public.profiles table. Every signup —
-- regardless of which app it came from — ran through handle_new_user() (001_schema.sql) and
-- got a full HABIT membership shape: role='user', a real 4-digit door access_code, and no way
-- to tell it apart from an actual gym member. That meant every crew member who only ever
-- signed up for Skandi Fit showed up in HABIT's admin members list/search/dashboard counts.
--
-- This tags every profile with its signup origin so admin can filter Skandi-only accounts out.

alter table public.profiles add column if not exists source text not null default 'habit';
alter table public.profiles drop constraint if exists profiles_source_check;
alter table public.profiles add constraint profiles_source_check check (source in ('habit','skandi'));

-- Backfill: a profile that has Skandi Fit activity but has NEVER made a HABIT booking or
-- payment is almost certainly a Skandi-only signup, not a real gym member who also uses Skandi.
update public.profiles p
set source = 'skandi'
where source = 'habit'
  and not exists (select 1 from public.bookings b where b.user_id = p.id)
  and not exists (select 1 from public.payments pay where pay.user_id = p.id)
  and (
    exists (select 1 from public.skandi_sessions s where s.user_id = p.id)
    or exists (select 1 from public.skandi_templates t where t.user_id = p.id)
    or exists (select 1 from public.skandi_sets st where st.user_id = p.id)
    or exists (select 1 from public.skandi_external_activities ea where ea.user_id = p.id)
  );

-- Going forward: read the signup's own app-provided metadata (skandi.html's signUp() call
-- is updated to send {data:{app:'skandi', ...}}) instead of relying only on the backfill
-- heuristic above, which can't see a signup that hasn't touched Skandi yet.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  v_code text;
begin
  loop
    v_code := lpad(floor(random()*9000+1000)::text, 4, '0');
    exit when not exists(select 1 from public.profiles where access_code = v_code);
  end loop;

  insert into public.profiles (id, name, phone, role, access_code, source)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'phone',
    coalesce(new.raw_user_meta_data->>'role', 'user'),
    v_code,
    case when new.raw_user_meta_data->>'app' = 'skandi' then 'skandi' else 'habit' end
  );
  return new;
end;
$$;

-- ensure_own_profile (047) is Skandi's self-heal path for the trigger-failed-to-insert
-- case (e.g. an access_code collision race) — any call to it is inherently a Skandi signup.
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

  insert into public.profiles (id, name, access_code, source)
  values (auth.uid(), coalesce(nullif(trim(p_name), ''), 'Crew member'), v_code, 'skandi')
  on conflict (id) do nothing;
end;
$$;
