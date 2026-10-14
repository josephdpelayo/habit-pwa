-- Competencia de levantamiento: un marcador en vivo para la pantalla del gym.
--
-- El admin da de alta a cada competidor (Admin → Competencia) y le va
-- capturando su primer y segundo intento; /competencia los muestra en la
-- pantalla ordenados por el mejor intento válido, y se reordena sola cada vez
-- que alguien levanta.
--
-- Decisiones:
--   · El mejor intento (best_kg) lo calcula un trigger, no la app: un intento
--     nulo no cuenta, y así ni el admin ni la pantalla pueden discrepar.
--   · Empate en kilos: gana quien lo levantó primero. best_at guarda cuándo se
--     alcanzó el mejor intento actual y solo cambia cuando cambia best_kg —
--     repetir el mismo peso en el segundo intento no te quita el lugar.
--   · El orden vive en un solo sitio: la vista lift_competition_standings
--     (security_invoker, así que respeta el RLS de las tablas). El admin y la
--     pantalla leen el lugar de ahí, no lo calculan cada uno.
--   · La pantalla funciona sin iniciar sesión (una tele en el gym): anon puede
--     leer solo la competencia marcada on_screen y sus competidores. Son nombres
--     y kilos que de todos modos se proyectan en el gym. Escribir es solo admin.
--   · Una sola competencia en pantalla a la vez (índice único parcial): es la
--     que /competencia muestra cuando no le pasan ?id=.

begin;

create table if not exists public.lift_competitions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  lift_name text not null default 'Bench press' check (char_length(btrim(lift_name)) between 1 and 60),
  event_date date not null default ((now() at time zone 'America/Mazatlan')::date),
  on_screen boolean not null default false,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists lift_competitions_one_on_screen
  on public.lift_competitions ((true)) where on_screen;

create table if not exists public.lift_competitors (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.lift_competitions(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  attempt1_kg numeric(6,2) check (attempt1_kg > 0 and attempt1_kg <= 1000),
  attempt1_valid boolean not null default true,
  attempt2_kg numeric(6,2) check (attempt2_kg > 0 and attempt2_kg <= 1000),
  attempt2_valid boolean not null default true,
  best_kg numeric(6,2),
  best_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists lift_competitors_competition_idx
  on public.lift_competitors (competition_id, created_at);

-- Lo que manda el cliente en best_kg / best_at se ignora: siempre se recalcula.
create or replace function public.lift_competitor_best()
returns trigger
language plpgsql
as $$
declare
  v_best numeric(6,2);
begin
  v_best := greatest(
    case when new.attempt1_valid then new.attempt1_kg end,
    case when new.attempt2_valid then new.attempt2_kg end
  );
  if tg_op = 'INSERT' or v_best is distinct from old.best_kg then
    new.best_at := case when v_best is null then null else now() end;
  else
    new.best_at := old.best_at;
  end if;
  new.best_kg := v_best;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists lift_competitor_best on public.lift_competitors;
create trigger lift_competitor_best
  before insert or update on public.lift_competitors
  for each row execute function public.lift_competitor_best();

-- place es null para quien todavía no tiene un intento válido: va al final y
-- sin número, no empatado en el último lugar.
create or replace view public.lift_competition_standings
with (security_invoker = true) as
select
  c.*,
  case when c.best_kg is null then null
       else rank() over (partition by c.competition_id order by c.best_kg desc nulls last, c.best_at asc)
  end as place
from public.lift_competitors c;

alter table public.lift_competitions enable row level security;
alter table public.lift_competitors enable row level security;

drop policy if exists "Public read on-screen competition" on public.lift_competitions;
create policy "Public read on-screen competition"
  on public.lift_competitions for select
  to anon, authenticated
  using (on_screen);

drop policy if exists "Admin manage competitions" on public.lift_competitions;
create policy "Admin manage competitions"
  on public.lift_competitions for all
  to authenticated
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

drop policy if exists "Public read on-screen competitors" on public.lift_competitors;
create policy "Public read on-screen competitors"
  on public.lift_competitors for select
  to anon, authenticated
  using (exists(
    select 1 from public.lift_competitions k
    where k.id = competition_id and k.on_screen
  ));

drop policy if exists "Admin manage competitors" on public.lift_competitors;
create policy "Admin manage competitors"
  on public.lift_competitors for all
  to authenticated
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

grant select on public.lift_competitions, public.lift_competitors, public.lift_competition_standings to anon;
grant select, insert, update, delete on public.lift_competitions, public.lift_competitors to authenticated;
grant select on public.lift_competition_standings to authenticated;

-- La pantalla escucha los cambios en vivo; sin esto solo se entera por el
-- sondeo de respaldo (cada 15 s).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'lift_competitors') then
      alter publication supabase_realtime add table public.lift_competitors;
    end if;
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'lift_competitions') then
      alter publication supabase_realtime add table public.lift_competitions;
    end if;
  end if;
end $$;

commit;
