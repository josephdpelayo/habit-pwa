-- Skandi Fit P3: periodización y adherencia por ciclo.
--
-- week_index (102) ya contiene el plan; esta tabla NO crea otra jerarquía de temporadas.
-- Solo describe cada semana del mismo programa (fase/nota), mientras planned_sessions guarda
-- el vínculo histórico que permite medir la adherencia aunque después se active otro programa.

begin;

-- ---------------------------------------------------------------------------------------
-- 1. Metadatos de la semana del programa.
-- ---------------------------------------------------------------------------------------
create table if not exists public.skandi_program_weeks (
  id          uuid primary key default uuid_generate_v4(),
  program_id  uuid references public.skandi_programs(id) on delete cascade not null,
  week_index  integer not null check (week_index between 1 and 17),
  phase       text not null default 'build'
                check (phase in ('build','peak','taper','race','recovery')),
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique(program_id, week_index)
);

create index if not exists idx_skandi_program_weeks_program
  on public.skandi_program_weeks(program_id, week_index);

alter table public.skandi_program_weeks enable row level security;

create or replace function public.skandi_program_week_touch()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_skandi_program_week_touch on public.skandi_program_weeks;
create trigger trg_skandi_program_week_touch
  before update on public.skandi_program_weeks
  for each row execute function public.skandi_program_week_touch();

drop policy if exists "Crew manage own skandi program weeks" on public.skandi_program_weeks;
create policy "Crew manage own skandi program weeks"
  on public.skandi_program_weeks for all
  using (exists (select 1 from public.skandi_programs p
                  where p.id = program_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.skandi_programs p
                       where p.id = program_id and p.user_id = auth.uid()));

-- ---------------------------------------------------------------------------------------
-- 2. El calendario conserva de qué ciclo y semana salió cada prescripción.
-- ---------------------------------------------------------------------------------------
alter table public.skandi_planned_sessions
  add column if not exists program_id uuid references public.skandi_programs(id) on delete set null,
  add column if not exists program_week_index integer
    check (program_week_index is null or program_week_index between 0 and 17);

create index if not exists idx_skandi_planned_program_cycle
  on public.skandi_planned_sessions(program_id, program_week_index, day)
  where program_id is not null;

-- El RPC de la 102 ya firma source='program'. Este trigger completa el vínculo en los inserts
-- y en las filas que el RPC cambia de template → program, sin copiar sus ~150 líneas de
-- reconciliación en cada migración futura. Un programa cargado a mano para una sola semana
-- puede mandar program_week_index=0 y el trigger lo conserva.
create or replace function public.skandi_planned_link_program()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_program public.skandi_programs%rowtype;
  v_start   date;
  v_index   integer;
  v_length  integer;
begin
  if new.source <> 'program' then
    new.program_id := null;
    new.program_week_index := null;
    return new;
  end if;

  -- ON DELETE SET NULL de un programa no debe atribuir sus filas históricas al programa que
  -- casualmente esté activo después. Conserva source='program' como dato legible, pero suelta
  -- el vínculo y el índice igual que pidió la FK.
  if tg_op = 'UPDATE' and old.program_id is not null and new.program_id is null then
    new.program_week_index := null;
    return new;
  end if;

  if new.program_id is not null then
    select * into v_program
    from public.skandi_programs p
    where p.id = new.program_id and p.user_id = new.user_id;
    if not found then
      raise exception 'Program does not belong to planned session owner';
    end if;
  else
    select * into v_program
    from public.skandi_programs p
    where p.user_id = new.user_id and p.is_active and p.start_date is not null
    limit 1;
  end if;

  -- source='program' también se usa para una carga puntual. Sin programa activo fechable no
  -- inventamos un ciclo; el cliente de P3 manda explícitamente (program_id, 0) en ese camino.
  if v_program.id is null then
    return new;
  end if;

  new.program_id := v_program.id;
  if new.program_week_index is not null then
    return new;
  end if;

  v_start := v_program.start_date;
  if v_start is null then
    new.program_week_index := 0;
    return new;
  end if;
  v_start := v_start - (extract(isodow from v_start)::int - 1);
  v_index := ((new.day - v_start) / 7) + 1;
  v_length := greatest(1, coalesce(v_program.weeks, 4) +
    case when coalesce(v_program.deload_week, true) then 1 else 0 end);
  new.program_week_index := case when v_index between 1 and v_length then v_index else 0 end;
  return new;
end;
$$;

drop trigger if exists trg_skandi_planned_link_program on public.skandi_planned_sessions;
create trigger trg_skandi_planned_link_program
  before insert or update of source, user_id, day, program_id, program_week_index
  on public.skandi_planned_sessions
  for each row execute function public.skandi_planned_link_program();

-- ---------------------------------------------------------------------------------------
-- 3. Backfill seguro de ciclos que ya están fechados.
-- ---------------------------------------------------------------------------------------
-- Solo source='program', solo el programa activo del mismo dueño y solo fechas dentro de su
-- ciclo. No se adivina el origen de filas manuales ni se enlaza una semana posterior al fin.
update public.skandi_planned_sessions s
set program_id = p.id,
    program_week_index = ((s.day -
      (p.start_date - (extract(isodow from p.start_date)::int - 1))) / 7) + 1
from public.skandi_programs p
where s.user_id = p.user_id
  and s.source = 'program'
  and s.program_id is null
  and p.is_active
  and p.start_date is not null
  and s.day >= p.start_date - (extract(isodow from p.start_date)::int - 1)
  and s.day < p.start_date - (extract(isodow from p.start_date)::int - 1)
    + (greatest(1, coalesce(p.weeks, 4) +
       case when coalesce(p.deload_week, true) then 1 else 0 end) * 7);

commit;
