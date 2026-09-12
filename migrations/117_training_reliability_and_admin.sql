-- HABIT Entrenar: seguridad, sesiones confiables, historial inmutable y
-- operaciones administrativas atómicas.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Perfiles: nadie se otorga privilegios desde el cliente
-- ─────────────────────────────────────────────────────────────────────────────

-- Las tarjetas públicas contienen únicamente identidad visual. La vista corre
-- con los permisos de su dueño para poder mostrar nombres/avatar en comunidad
-- sin volver a exponer teléfonos, planes, créditos o roles de todos los socios.
drop view if exists public.profile_cards;
create view public.profile_cards with (security_barrier = true) as
select id, name, avatar_url, reception_title, reception_logo
from public.profiles;
grant select on public.profile_cards to authenticated;

create or replace function public.is_habit_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;
revoke all on function public.is_habit_admin() from public;
grant execute on function public.is_habit_admin() to authenticated;

create or replace function public.is_habit_staff()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','reception'));
$$;
revoke all on function public.is_habit_staff() from public;
grant execute on function public.is_habit_staff() to authenticated;

drop policy if exists "Authenticated users read profiles" on public.profiles;
drop policy if exists "Users read own profile" on public.profiles;
drop policy if exists "Admin reads all profiles" on public.profiles;

create policy "Users read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Admin reads all profiles"
  on public.profiles for select
  using (public.is_habit_staff());

drop policy if exists "Insert own profile" on public.profiles;
create policy "Insert own unprivileged profile"
  on public.profiles for insert
  with check (
    auth.uid()=id and role='user'
    and coalesce(is_instructor,false)=false
    and coalesce(coaching_beta,false)=false
  );

-- El rol enviado en raw_user_meta_data lo controla quien se registra. Nunca se
-- usa como fuente de autorización.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
    'user',
    v_code,
    case when new.raw_user_meta_data->>'app' = 'skandi' then 'skandi' else 'habit' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.guard_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_role text;
begin
  -- Procesos internos/service-role no tienen auth.uid() y conservan su acceso.
  if auth.uid() is null then return new; end if;
  select role into v_actor_role from public.profiles where id = auth.uid();

  if coalesce(v_actor_role,'user') <> 'admin' then
    if new.role is distinct from old.role
       or new.is_instructor is distinct from old.is_instructor
       or new.coaching_beta is distinct from old.coaching_beta then
      raise exception 'privileged profile fields can only be changed by an administrator';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_profile_privileges_before_update on public.profiles;
create trigger guard_profile_privileges_before_update
before update on public.profiles
for each row execute function public.guard_profile_privileges();

create or replace function public.ensure_habit_profile(p_name text,p_phone text default null)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_code text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if exists(select 1 from public.profiles where id=auth.uid()) then return; end if;
  loop
    v_code:=lpad(floor(random()*9000+1000)::text,4,'0');
    exit when not exists(select 1 from public.profiles where access_code=v_code);
  end loop;
  insert into public.profiles(id,name,phone,role,access_code,source)
  values(auth.uid(),coalesce(nullif(trim(p_name),''),'Socio'),nullif(trim(p_phone),''),'user',v_code,'habit')
  on conflict(id) do nothing;
end;
$$;
grant execute on function public.ensure_habit_profile(text,text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Sesiones de entrenamiento: una activa, pausa persistente y snapshot
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.coaching_schedule
  add column if not exists exercise_snapshot jsonb not null default '[]'::jsonb,
  add column if not exists paused_seconds integer not null default 0 check (paused_seconds >= 0),
  add column if not exists paused_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists version integer not null default 1 check (version > 0);

alter table public.coaching_session_sets
  add column if not exists metric_type text not null default 'reps'
    check (metric_type in ('reps','time','distance')),
  add column if not exists actual_seconds integer check (actual_seconds is null or actual_seconds >= 0),
  add column if not exists actual_distance_m numeric check (actual_distance_m is null or actual_distance_m >= 0);

alter table public.user_scores
  add column if not exists schedule_id uuid references public.coaching_schedule(id) on delete set null,
  add column if not exists set_id uuid references public.coaching_session_sets(id) on delete set null;
create unique index if not exists idx_user_scores_one_per_set
  on public.user_scores(set_id);

create or replace function public.training_score_history(
  p_user_id uuid,
  p_limit_per_exercise integer default 40
)
returns table(
  id uuid,user_id uuid,board_id text,ex_idx integer,ex_key text,ex_name text,
  weight numeric,reps text,logged_at timestamptz,schedule_id uuid,set_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select q.id,q.user_id,q.board_id,q.ex_idx,q.ex_key,q.ex_name,q.weight,q.reps,
         q.logged_at,q.schedule_id,q.set_id
  from (
    select s.*,row_number() over(
      partition by coalesce(s.ex_key,s.board_id||'_idx_'||s.ex_idx::text)
      order by s.logged_at desc,s.id desc
    ) as rn
    from public.user_scores s
    where s.user_id=p_user_id
      and (p_user_id=auth.uid() or public.is_habit_admin())
  ) q
  where q.rn<=greatest(5,least(coalesce(p_limit_per_exercise,40),100))
  order by q.logged_at asc;
$$;
grant execute on function public.training_score_history(uuid,integer) to authenticated;

-- Mejor esfuerzo para el histórico existente. A partir de esta migración el
-- snapshot se toma al inicio; para lo anterior se conserva la versión actual
-- del board antes de que vuelva a editarse.
update public.coaching_schedule s
set exercise_snapshot = b.exercises
from public.boards b
where s.board_id = b.id
  and jsonb_array_length(s.exercise_snapshot) = 0
  and jsonb_typeof(b.exercises) = 'array';

-- Si una instalación antigua ya acumuló duplicados, conserva como activa la
-- sesión iniciada más recientemente y devuelve las demás a programada.
with ranked as (
  select id, row_number() over (
    partition by user_id order by started_at desc nulls last, created_at desc, id
  ) as rn
  from public.coaching_schedule
  where status = 'in_progress'
)
update public.coaching_schedule s
set status = 'scheduled', started_at = null, paused_at = null,
    paused_seconds = 0, updated_at = now(), version = version + 1
from ranked r
where s.id = r.id and r.rn > 1;

create unique index if not exists idx_coaching_schedule_one_active
  on public.coaching_schedule(user_id)
  where status = 'in_progress';

create or replace function public.guard_member_schedule_update()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or public.is_habit_admin() then return new; end if;
  if auth.uid() <> old.user_id then raise exception 'not authorized'; end if;
  if new.user_id is distinct from old.user_id
     or new.created_by is distinct from old.created_by
     or new.program_id is distinct from old.program_id
     or new.program_week_index is distinct from old.program_week_index
     or new.generated_from_base is distinct from old.generated_from_base
     or new.base_template_dow is distinct from old.base_template_dow then
    raise exception 'schedule provenance is immutable';
  end if;
  if old.created_by is distinct from auth.uid()
     and (new.board_id is distinct from old.board_id
       or new.board_name is distinct from old.board_name) then
    raise exception 'coach-authored plans require a change request';
  end if;
  if new.ds is distinct from old.ds
     and date_trunc('week',new.ds::timestamp) <> date_trunc('week',old.ds::timestamp) then
    raise exception 'a workout can only move within the same week';
  end if;
  return new;
end;
$$;
drop trigger if exists guard_member_schedule_before_update on public.coaching_schedule;
create trigger guard_member_schedule_before_update
before update on public.coaching_schedule
for each row execute function public.guard_member_schedule_update();

drop policy if exists "Users delete own coaching schedule" on public.coaching_schedule;
create policy "Users delete own self-created coaching schedule"
  on public.coaching_schedule for delete
  using (auth.uid()=user_id and created_by=auth.uid());

create or replace function public.start_training_session(
  p_schedule_id uuid,
  p_exercise_snapshot jsonb default '[]'::jsonb
)
returns public.coaching_schedule
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.coaching_schedule%rowtype;
  v_other public.coaching_schedule%rowtype;
begin
  -- Serializa inicios del mismo socio, incluso desde dos dispositivos.
  select * into v_row from public.coaching_schedule
  where id = p_schedule_id for update;
  if not found or v_row.user_id <> auth.uid() then
    raise exception 'not authorized';
  end if;

  select * into v_other from public.coaching_schedule
  where user_id = v_row.user_id and status = 'in_progress' and id <> v_row.id
  order by started_at desc nulls last limit 1 for update;
  if found then
    raise exception 'ACTIVE_SESSION:%', v_other.id;
  end if;

  if v_row.status = 'done' then
    raise exception 'completed sessions cannot be restarted';
  end if;

  if jsonb_typeof(coalesce(p_exercise_snapshot,'[]'::jsonb)) <> 'array' then
    raise exception 'exercise snapshot must be an array';
  end if;

  update public.coaching_schedule
  set status = 'in_progress',
      started_at = coalesce(started_at, now()),
      completed_at = null,
      paused_at = null,
      exercise_snapshot = case
        when jsonb_array_length(exercise_snapshot) = 0 then coalesce(p_exercise_snapshot,'[]'::jsonb)
        else exercise_snapshot
      end,
      updated_at = now(),
      version = version + 1
  where id = p_schedule_id
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.set_training_session_paused(
  p_schedule_id uuid,
  p_paused boolean
)
returns public.coaching_schedule
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.coaching_schedule%rowtype;
  v_now timestamptz := now();
begin
  select * into v_row from public.coaching_schedule
  where id = p_schedule_id for update;
  if not found or v_row.user_id <> auth.uid() or v_row.status <> 'in_progress' then
    raise exception 'not authorized';
  end if;

  update public.coaching_schedule
  set paused_seconds = paused_seconds + case
        when not p_paused and paused_at is not null
          then greatest(0, extract(epoch from (v_now - paused_at))::integer)
        else 0 end,
      paused_at = case when p_paused then coalesce(paused_at, v_now) else null end,
      updated_at = v_now,
      version = version + 1
  where id = p_schedule_id
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.finish_training_session(p_schedule_id uuid)
returns public.coaching_schedule
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.coaching_schedule%rowtype;
  v_now timestamptz := now();
  v_paused integer;
begin
  select * into v_row from public.coaching_schedule
  where id = p_schedule_id for update;
  if not found or v_row.user_id <> auth.uid() then
    raise exception 'not authorized';
  end if;
  if v_row.status = 'done' then return v_row; end if;
  if v_row.status <> 'in_progress' or v_row.started_at is null then
    raise exception 'session is not active';
  end if;

  v_paused := v_row.paused_seconds + case when v_row.paused_at is not null
    then greatest(0, extract(epoch from (v_now - v_row.paused_at))::integer) else 0 end;

  update public.coaching_schedule
  set status = 'done', completed_at = v_now,
      paused_seconds = v_paused, paused_at = null,
      duration_sec = greatest(0, extract(epoch from (v_now - started_at))::integer - v_paused),
      updated_at = v_now, version = version + 1
  where id = p_schedule_id
  returning * into v_row;
  return v_row;
end;
$$;

grant execute on function public.start_training_session(uuid,jsonb) to authenticated;
grant execute on function public.set_training_session_paused(uuid,boolean) to authenticated;
grant execute on function public.finish_training_session(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Guardado semanal transaccional + auditoría/versión
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.coaching_plan_revisions (
  user_id uuid references public.profiles(id) on delete cascade not null,
  week_start date not null,
  version integer not null default 1,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  summary jsonb not null default '{}'::jsonb,
  primary key (user_id, week_start)
);
alter table public.coaching_plan_revisions enable row level security;
drop policy if exists "Users read own plan revisions" on public.coaching_plan_revisions;
create policy "Users read own plan revisions" on public.coaching_plan_revisions
  for select using (auth.uid() = user_id);
drop policy if exists "Admin manage plan revisions" on public.coaching_plan_revisions;
create policy "Admin manage plan revisions" on public.coaching_plan_revisions
  for all using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'))
  with check (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));

create or replace function public.save_coaching_week(
  p_user_id uuid,
  p_week_start date,
  p_mode text,
  p_days jsonb,
  p_expected_version integer default 0
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
  v_version integer;
  v_day jsonb;
  v_dow integer;
  v_ds date;
  v_board uuid;
  v_name text;
  v_color text;
  v_existing public.coaching_schedule%rowtype;
begin
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin') into v_is_admin;
  if not v_is_admin then raise exception 'not authorized'; end if;
  if p_mode not in ('week','base') then raise exception 'invalid mode'; end if;
  if jsonb_typeof(coalesce(p_days,'[]'::jsonb)) <> 'array' then raise exception 'days must be an array'; end if;
  p_week_start := p_week_start - (extract(isodow from p_week_start)::int - 1);

  insert into public.coaching_plan_revisions(user_id,week_start,version,updated_by)
  values(p_user_id,p_week_start,1,auth.uid())
  on conflict (user_id,week_start) do nothing;
  select version into v_version from public.coaching_plan_revisions
  where user_id=p_user_id and week_start=p_week_start for update;
  if p_expected_version > 0 and p_expected_version <> v_version then
    raise exception 'PLAN_VERSION_CONFLICT:%', v_version;
  end if;

  for v_day in select value from jsonb_array_elements(p_days)
  loop
    v_dow := (v_day->>'dow')::integer;
    if v_dow < 0 or v_dow > 6 then raise exception 'invalid day'; end if;
    v_ds := p_week_start + v_dow;
    v_board := nullif(v_day->>'board_id','')::uuid;
    v_name := coalesce(nullif(v_day->>'board_name',''),'Descanso');
    v_color := coalesce(nullif(v_day->>'board_color',''),'#2563eb');

    -- Un día ya iniciado es historia: el editor nunca lo reescribe.
    if exists(select 1 from public.coaching_schedule where user_id=p_user_id and ds=v_ds
              and status in ('in_progress','done')) then
      continue;
    end if;

    if p_mode = 'base' then
      delete from public.coaching_week_templates where user_id=p_user_id and dow=v_dow;
      if v_board is not null then
        insert into public.coaching_week_templates(
          user_id,dow,board_id,board_name,board_color,created_by,updated_at
        ) values(p_user_id,v_dow,v_board,v_name,v_color,auth.uid(),now());
      end if;
    end if;

    select * into v_existing from public.coaching_schedule
    where user_id=p_user_id and ds=v_ds and status in ('scheduled','skipped')
    order by generated_from_base desc, created_at limit 1 for update;

    delete from public.coaching_schedule
    where user_id=p_user_id and ds=v_ds and status in ('scheduled','skipped')
      and (v_existing.id is null or id <> v_existing.id);

    if v_board is not null then
      if v_existing.id is null then
        insert into public.coaching_schedule(
          user_id,ds,board_id,board_name,board_color,status,created_by,
          generated_from_base,base_template_dow
        ) values(
          p_user_id,v_ds,v_board,v_name,v_color,'scheduled',auth.uid(),
          p_mode='base',v_dow
        );
      else
        update public.coaching_schedule
        set board_id=v_board,board_name=v_name,board_color=v_color,status='scheduled',
            generated_from_base=(p_mode='base'),base_template_dow=v_dow,
            updated_at=now(),version=version+1
        where id=v_existing.id;
      end if;
    elsif p_mode = 'week' then
      if v_existing.id is not null then
        update public.coaching_schedule set status='skipped',generated_from_base=false,
          base_template_dow=v_dow,updated_at=now(),version=version+1
        where id=v_existing.id;
      elsif exists(select 1 from public.coaching_week_templates where user_id=p_user_id and dow=v_dow) then
        insert into public.coaching_schedule(
          user_id,ds,board_id,board_name,board_color,status,created_by,
          generated_from_base,base_template_dow
        )
        select p_user_id,v_ds,board_id,board_name,board_color,'skipped',auth.uid(),false,v_dow
        from public.coaching_week_templates where user_id=p_user_id and dow=v_dow;
      end if;
    elsif v_existing.id is not null then
      delete from public.coaching_schedule where id=v_existing.id;
    end if;
  end loop;

  if p_mode = 'base' then
    delete from public.coaching_schedule
    where user_id=p_user_id and ds > p_week_start+6 and status='scheduled' and generated_from_base;
  end if;

  update public.coaching_plan_revisions
  set version=version+1,updated_by=auth.uid(),updated_at=now(),
      summary=jsonb_build_object('mode',p_mode,'days',p_days)
  where user_id=p_user_id and week_start=p_week_start
  returning version into v_version;
  return v_version;
end;
$$;
grant execute on function public.save_coaching_week(uuid,date,text,jsonb,integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Alertas accionables del coach
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.coaching_alert_actions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  signal_key text not null,
  status text not null default 'open' check (status in ('open','resolved','snoozed')),
  assigned_to uuid references public.profiles(id) on delete set null,
  snoozed_until timestamptz,
  resolved_at timestamptz,
  note text,
  updated_at timestamptz not null default now(),
  unique(user_id, signal_key)
);
alter table public.coaching_alert_actions enable row level security;
drop policy if exists "Admin manage coaching alert actions" on public.coaching_alert_actions;
create policy "Admin manage coaching alert actions" on public.coaching_alert_actions
  for all using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'))
  with check (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));

create table if not exists public.coaching_plan_change_requests (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  dow integer not null check (dow between 0 and 6),
  from_board_id uuid references public.boards(id) on delete set null,
  from_board_name text,
  to_board_id uuid references public.boards(id) on delete set null,
  to_board_name text,
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','declined','cancelled')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_coaching_plan_change_requests_pending
  on public.coaching_plan_change_requests(user_id,status,created_at desc);
alter table public.coaching_plan_change_requests enable row level security;
drop policy if exists "Users manage own plan change requests" on public.coaching_plan_change_requests;
create policy "Users manage own plan change requests" on public.coaching_plan_change_requests
  for all using (auth.uid()=user_id) with check (auth.uid()=user_id);
drop policy if exists "Admin manage plan change requests" on public.coaching_plan_change_requests;
create policy "Admin manage plan change requests" on public.coaching_plan_change_requests
  for all using (public.is_habit_admin()) with check (public.is_habit_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Biblioteca de rutinas con metadatos y versión
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.boards
  add column if not exists goal text,
  add column if not exists level text,
  add column if not exists duration_min integer check (duration_min is null or duration_min between 5 and 300),
  add column if not exists equipment text[] not null default '{}',
  add column if not exists tags text[] not null default '{}',
  add column if not exists version integer not null default 1 check (version > 0),
  add column if not exists published_at timestamptz,
  add column if not exists archived_at timestamptz,
  add column if not exists parent_version_id uuid references public.boards(id) on delete set null;

create index if not exists idx_boards_library_search
  on public.boards(owner_id, archived_at, name);

create table if not exists public.board_version_history (
  id uuid primary key default uuid_generate_v4(),
  board_id uuid not null,
  version integer not null,
  name text not null,
  color text not null,
  exercises jsonb not null,
  metadata jsonb not null default '{}'::jsonb,
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default now(),
  unique(board_id,version)
);
alter table public.board_version_history enable row level security;
drop policy if exists "Admin read board version history" on public.board_version_history;
create policy "Admin read board version history" on public.board_version_history
  for select using (public.is_habit_admin());

create or replace function public.version_board_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if row(old.name,old.color,old.exercises,old.goal,old.level,old.duration_min,old.equipment,old.tags)
     is distinct from
     row(new.name,new.color,new.exercises,new.goal,new.level,new.duration_min,new.equipment,new.tags) then
    insert into public.board_version_history(board_id,version,name,color,exercises,metadata,changed_by)
    values(old.id,old.version,old.name,old.color,old.exercises,
      jsonb_build_object('goal',old.goal,'level',old.level,'duration_min',old.duration_min,
                         'equipment',old.equipment,'tags',old.tags),auth.uid())
    on conflict (board_id,version) do nothing;
    new.version := greatest(old.version + 1, new.version);
    new.updated_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists version_board_before_update on public.boards;
create trigger version_board_before_update
before update on public.boards
for each row execute function public.version_board_update();

commit;
