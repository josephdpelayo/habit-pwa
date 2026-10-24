-- Retos: un usuario propone un reto y cualquier cuenta registra su marca (docs/RETOS.md, Fase 1).
--
-- Vive en la Comunidad, que es una sola en HABIT y en HABIT Crew (D13): la misma cuenta ve los
-- mismos retos en las dos apps. Esta migración es toda la Fase 1 en la base:
--
--   1. challenges: el reto (título, el WOD escrito, cómo se mide, fechas). Cualquier cuenta lo
--      crea y se publica directo (R2); el admin lo oculta o lo marca oficial (R6).
--   2. challenge_entries: una marca por persona y reto (R3), que se corrige mientras el reto
--      esté abierto. La valida un trigger contra el tipo del reto; el cliente no puede mandar
--      una marca imposible ni registrar fuera de fechas.
--   3. challenge_standings: el lugar de cada marca. El orden vive solo aquí (como
--      lift_competition_standings en la 126); la app lee `place`, no lo calcula.
--      challenge_cards: cada reto con su fase (próximo / abierto / terminado) y participantes.
--   4. Moderación: los retos y las marcas entran a la 128 — se reportan (community_reports gana
--      challenge_id / entry_id) y respetan los bloqueos en los dos sentidos.
--
-- Decisiones:
--   · Los nombres van copiados en la fila (created_by_name, user_name), como posts.user_name:
--     desde la 117 un socio solo lee su propio perfil, y una tabla de marcas sin nombres no
--     sirve. Los copia el trigger desde profiles, nunca el cliente.
--   · "Abierto" no se guarda: es status = 'activo' y hoy (Mazatlán) entre starts_on y ends_on,
--     en challenge_is_open(). Guardarlo pediría un cron que lo cierre.
--   · Empate: gana quien registró primero esa marca. scored_at solo se mueve cuando la marca
--     cambia (como best_at en la 126): corregir la nota no te quita el lugar.
--   · Con marcas registradas, el autor ya no cambia cómo se mide (tipo, límite, divisiones,
--     inicio) ni el WOD: cambiaría el reto debajo de quien ya lo hizo. Sí corrige el título y
--     mueve el cierre. Un reto terminado queda congelado para su autor. El admin puede todo.
--   · Registrar es INSERT y corregir es UPDATE por id. No upsert: PostgREST pone en el SET todas
--     las columnas del payload, challenge_id incluida, y esa columna no se puede actualizar.
--   · Los errores salen como códigos que la app traduce (como BOOKING_RPC_ERRORS):
--     CHALLENGE_NO_SESSION, CHALLENGE_CLOSED, CHALLENGE_BAD_SCORE, CHALLENGE_BAD_DATES,
--     CHALLENGE_LOCKED.
--
-- Orden de despliegue: después de la 128 (esta altera su community_reports). La app publicada
-- no lee estas tablas, así que la migración puede ir antes que la app.
--
-- Requiere la 117 (is_habit_admin) y la 128 (community_reports, community_visible_author).

begin;

do $$
begin
  if to_regprocedure('public.is_habit_admin()') is null then
    raise exception 'Falta la migración 117 (public.is_habit_admin). Córrela antes que esta.';
  end if;
  if to_regclass('public.community_reports') is null
     or to_regprocedure('public.community_visible_author(uuid)') is null then
    raise exception 'Falta la migración 128 (moderación de la comunidad). Córrela antes que esta.';
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tablas
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.challenges (
  id               uuid primary key default gen_random_uuid(),
  -- set null y no cascade: si el autor borra su cuenta, el reto y las marcas de los demás
  -- se quedan (las hicieron ellos).
  created_by       uuid default auth.uid() references public.profiles(id) on delete set null,
  created_by_name  text,
  title            text not null check (char_length(btrim(title)) between 1 and 80),
  description      text not null default '' check (char_length(description) <= 1000),
  score_type       text not null
                     check (score_type in ('amrap', 'for_time', 'max_reps', 'max_load', 'max_time')),
  -- Obligatorio en for_time: sin límite no hay cómo ordenar a quien no terminó. En los demás
  -- solo informa (un AMRAP de 12 min).
  time_cap_sec     int check (time_cap_sec between 60 and 7200),
  has_divisions    boolean not null default false,
  starts_on        date not null default ((now() at time zone 'America/Mazatlan')::date),
  ends_on          date not null default ((now() at time zone 'America/Mazatlan')::date + 7),
  is_official      boolean not null default false,
  status           text not null default 'activo' check (status in ('activo', 'oculto')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint challenges_cap_for_time check (score_type <> 'for_time' or time_cap_sec is not null),
  constraint challenges_dates check (ends_on >= starts_on and ends_on - starts_on <= 60)
);

create index if not exists idx_challenges_dates on public.challenges(status, ends_on desc);
create index if not exists idx_challenges_created_by on public.challenges(created_by);

create table if not exists public.challenge_entries (
  id            uuid primary key default gen_random_uuid(),
  challenge_id  uuid not null references public.challenges(id) on delete cascade,
  user_id       uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  user_name     text,
  division      text not null default 'rx' check (division in ('rx', 'scaled')),
  -- Qué columnas se usan lo decide el tipo del reto (ver challenge_entry_fill); las demás
  -- quedan en null.
  rounds        int check (rounds between 0 and 999),
  reps          int check (reps between 0 and 9999),
  time_sec      int check (time_sec between 1 and 86400),
  load_kg       numeric(6,2) check (load_kg > 0 and load_kg <= 1000),
  finished      boolean,
  note          text check (note is null or char_length(note) <= 300),
  proof_url     text check (proof_url is null or (char_length(proof_url) <= 500 and proof_url ~* '^https?://')),
  scored_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint challenge_entries_one_per_user unique (challenge_id, user_id)
);

-- La unique cubre "las marcas de este reto"; este es para "mis retos" y el cascade de la cuenta.
create index if not exists idx_challenge_entries_user on public.challenge_entries(user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Funciones de apoyo
-- ─────────────────────────────────────────────────────────────────────────────
-- Security definer: la política de borrado y el trigger preguntan por filas que la RLS de
-- quien pregunta puede esconder (las marcas de alguien bloqueado siguen existiendo).
create or replace function public.challenge_is_open(p_challenge uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select c.status = 'activo'
       and (now() at time zone 'America/Mazatlan')::date between c.starts_on and c.ends_on
    from public.challenges c
    where c.id = p_challenge
  ), false);
$$;

create or replace function public.challenge_has_other_entries(p_challenge uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.challenge_entries e
    where e.challenge_id = p_challenge
      and e.user_id is distinct from auth.uid()
  );
$$;

-- La marca como se lee: la usan la vista (score_label) y la copia del reporte.
create or replace function public.challenge_score_label(
  p_type text, p_rounds int, p_reps int, p_time_sec int, p_load_kg numeric, p_finished boolean
)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_type
    when 'amrap' then
      coalesce(p_rounds, 0) || case when coalesce(p_rounds, 0) = 1 then ' ronda' else ' rondas' end
      || case when coalesce(p_reps, 0) > 0 then ' + ' || p_reps || ' reps' else '' end
    when 'for_time' then
      case when p_finished
        then (p_time_sec / 60) || ':' || lpad((p_time_sec % 60)::text, 2, '0')
        else 'Límite · ' || coalesce(p_reps, 0) || ' reps'
      end
    when 'max_reps' then coalesce(p_reps, 0) || ' reps'
    when 'max_load' then trim_scale(p_load_kg)::text || ' kg'
    when 'max_time' then (p_time_sec / 60) || ':' || lpad((p_time_sec % 60)::text, 2, '0')
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Reglas del reto
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.challenge_fill()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'America/Mazatlan')::date;
  -- Sin sesión es el SQL Editor o el service role (anon no tiene permisos sobre la tabla):
  -- ahí manda quien escribe, como en la 128.
  v_admin boolean := auth.uid() is null or public.is_habit_admin();
begin
  new.title       := btrim(new.title);
  new.description := btrim(coalesce(new.description, ''));

  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    if new.created_by is null then
      raise exception 'CHALLENGE_NO_SESSION';
    end if;
    select p.name into new.created_by_name from public.profiles p where p.id = new.created_by;
    if not v_admin then
      new.is_official := false;
      new.status      := 'activo';
      -- Proponer para el lunes, sí; para el mes pasado o para dentro de medio año, no.
      if new.starts_on < v_today or new.starts_on > v_today + 30 then
        raise exception 'CHALLENGE_BAD_DATES';
      end if;
    end if;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  -- UPDATE. created_by, created_by_name y created_at no tienen permiso de columna (ver los
  -- grants), así que el único cambio posible de created_by es el on delete set null de la
  -- cuenta borrada: ese pasa sin más reglas, porque frenarlo haría fallar el borrado.
  if new.created_by is distinct from old.created_by then
    return new;
  end if;

  if not v_admin then
    if new.is_official is distinct from old.is_official or new.status is distinct from old.status then
      raise exception 'CHALLENGE_LOCKED';
    end if;
    -- Terminado queda como quedó: los resultados finales no se mueven.
    if old.ends_on < v_today then
      raise exception 'CHALLENGE_CLOSED';
    end if;
    -- Cerrar antes, sí (hasta hoy); cerrar en el pasado, no.
    if new.ends_on is distinct from old.ends_on and new.ends_on < v_today then
      raise exception 'CHALLENGE_BAD_DATES';
    end if;
    if new.starts_on is distinct from old.starts_on
       and (new.starts_on < v_today or new.starts_on > v_today + 30) then
      raise exception 'CHALLENGE_BAD_DATES';
    end if;
    if public.challenge_has_other_entries(old.id) and (
         new.score_type    is distinct from old.score_type
      or new.time_cap_sec  is distinct from old.time_cap_sec
      or new.has_divisions is distinct from old.has_divisions
      or new.starts_on     is distinct from old.starts_on
      or new.description   is distinct from old.description
    ) then
      raise exception 'CHALLENGE_LOCKED';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists challenge_fill on public.challenges;
create trigger challenge_fill
  before insert or update on public.challenges
  for each row execute function public.challenge_fill();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Reglas de la marca
-- ─────────────────────────────────────────────────────────────────────────────
-- Cada tipo usa sus columnas y las demás se ponen en null (no se rechaza: el cliente puede
-- mandar el formulario entero). Lo que falta para el tipo sí se rechaza.
create or replace function public.challenge_entry_fill()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.challenges%rowtype;
begin
  if tg_op = 'INSERT' then
    new.user_id := coalesce(auth.uid(), new.user_id);
    if new.user_id is null then
      raise exception 'CHALLENGE_NO_SESSION';
    end if;
  else
    new.user_id      := old.user_id;
    new.challenge_id := old.challenge_id;
    new.created_at   := old.created_at;
  end if;

  select * into c from public.challenges where id = new.challenge_id;
  if not found then
    raise exception 'CHALLENGE_CLOSED';
  end if;
  if not public.challenge_is_open(c.id) then
    raise exception 'CHALLENGE_CLOSED';
  end if;

  if not c.has_divisions then
    new.division := 'rx';
  end if;

  if c.score_type = 'amrap' then
    if new.rounds is null and new.reps is null then raise exception 'CHALLENGE_BAD_SCORE'; end if;
    new.rounds := coalesce(new.rounds, 0);
    new.reps   := coalesce(new.reps, 0);
    if new.rounds + new.reps = 0 then raise exception 'CHALLENGE_BAD_SCORE'; end if;
    new.time_sec := null; new.load_kg := null; new.finished := null;

  elsif c.score_type = 'for_time' then
    if new.finished is null then raise exception 'CHALLENGE_BAD_SCORE'; end if;
    if new.finished then
      if new.time_sec is null or new.time_sec > c.time_cap_sec then
        raise exception 'CHALLENGE_BAD_SCORE';
      end if;
      new.reps := null;
    else
      if new.reps is null or new.reps = 0 then raise exception 'CHALLENGE_BAD_SCORE'; end if;
      new.time_sec := null;
    end if;
    new.rounds := null; new.load_kg := null;

  elsif c.score_type = 'max_reps' then
    if new.reps is null or new.reps = 0 then raise exception 'CHALLENGE_BAD_SCORE'; end if;
    new.rounds := null; new.time_sec := null; new.load_kg := null; new.finished := null;

  elsif c.score_type = 'max_load' then
    if new.load_kg is null then raise exception 'CHALLENGE_BAD_SCORE'; end if;
    new.rounds := null; new.reps := null; new.time_sec := null; new.finished := null;

  elsif c.score_type = 'max_time' then
    if new.time_sec is null then raise exception 'CHALLENGE_BAD_SCORE'; end if;
    new.rounds := null; new.reps := null; new.load_kg := null; new.finished := null;
  end if;

  new.note      := nullif(btrim(coalesce(new.note, '')), '');
  new.proof_url := nullif(btrim(coalesce(new.proof_url, '')), '');
  select p.name into new.user_name from public.profiles p where p.id = new.user_id;

  if tg_op = 'INSERT' or (
       new.division is distinct from old.division
    or new.rounds   is distinct from old.rounds
    or new.reps     is distinct from old.reps
    or new.time_sec is distinct from old.time_sec
    or new.load_kg  is distinct from old.load_kg
    or new.finished is distinct from old.finished
  ) then
    new.scored_at := now();
  else
    new.scored_at := old.scored_at;
  end if;
  if tg_op = 'INSERT' then
    new.created_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists challenge_entry_fill on public.challenge_entries;
create trigger challenge_entry_fill
  before insert or update on public.challenge_entries
  for each row execute function public.challenge_entry_fill();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. El orden y las tarjetas
-- ─────────────────────────────────────────────────────────────────────────────
-- Dos llaves "más es mejor" por tipo, y a igualdad, quien registró primero:
--   amrap     rondas, reps
--   for_time  terminó (1/0); si terminó, menos tiempo (−time_sec); si no, más reps
--   max_reps  reps     · max_load  kg     · max_time  segundos
-- Así quien no terminó un For Time va siempre detrás de todos los que terminaron.
-- security_invoker: respeta la RLS, así que las marcas de alguien bloqueado no aparecen y
-- los lugares se recorren (para quien bloqueó, ese lugar no existe).
create or replace view public.challenge_standings
with (security_invoker = true) as
select
  e.*,
  c.score_type,
  public.challenge_score_label(c.score_type, e.rounds, e.reps, e.time_sec, e.load_kg, e.finished) as score_label,
  rank() over (
    partition by e.challenge_id, e.division
    order by k.primary_key desc, k.secondary_key desc, e.scored_at asc
  ) as place
from public.challenge_entries e
join public.challenges c on c.id = e.challenge_id
cross join lateral (
  select
    case c.score_type
      when 'amrap'    then e.rounds::numeric
      when 'for_time' then case when e.finished then 1 else 0 end
      when 'max_reps' then e.reps::numeric
      when 'max_load' then e.load_kg
      when 'max_time' then e.time_sec::numeric
    end as primary_key,
    case c.score_type
      when 'amrap'    then e.reps::numeric
      when 'for_time' then case when e.finished then -e.time_sec else e.reps end::numeric
      else 0
    end as secondary_key
) k;

create or replace view public.challenge_cards
with (security_invoker = true) as
select
  c.*,
  case
    when (now() at time zone 'America/Mazatlan')::date < c.starts_on then 'proximo'
    when (now() at time zone 'America/Mazatlan')::date > c.ends_on then 'terminado'
    else 'abierto'
  end as phase,
  (select count(*) from public.challenge_entries e where e.challenge_id = c.id) as entries_count
from public.challenges c;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.challenges enable row level security;
alter table public.challenge_entries enable row level security;

-- Un reto oculto lo siguen viendo su autor (para saber qué pasó) y el admin.
drop policy if exists "Read active challenges" on public.challenges;
create policy "Read active challenges"
  on public.challenges for select to authenticated
  using (status = 'activo' or created_by = auth.uid() or public.is_habit_admin());

drop policy if exists "Create own challenges" on public.challenges;
create policy "Create own challenges"
  on public.challenges for insert to authenticated
  with check (created_by = auth.uid());

-- Qué puede cambiar el autor lo limita challenge_fill.
drop policy if exists "Author or admin updates challenges" on public.challenges;
create policy "Author or admin updates challenges"
  on public.challenges for update to authenticated
  using (created_by = auth.uid() or public.is_habit_admin())
  with check (created_by = auth.uid() or public.is_habit_admin());

-- El autor lo borra mientras nadie más haya registrado (su propia marca se va en cascada);
-- con marcas de otros, el reto ya es de todos.
drop policy if exists "Author or admin deletes challenges" on public.challenges;
create policy "Author or admin deletes challenges"
  on public.challenges for delete to authenticated
  using (
    (created_by = auth.uid() and not public.challenge_has_other_entries(id))
    or public.is_habit_admin()
  );

-- Las marcas se ven si su reto se ve: la subconsulta pasa por la RLS de challenges (oculto y
-- bloqueado incluidos), así que no hay que repetir esas reglas aquí.
drop policy if exists "Read entries of visible challenges" on public.challenge_entries;
create policy "Read entries of visible challenges"
  on public.challenge_entries for select to authenticated
  using (exists (select 1 from public.challenges c where c.id = challenge_id));

-- Igual al registrar: no se participa en un reto que no se ve (el del que te bloqueó, uno
-- oculto). Que esté abierto lo dice el trigger, con un código que la app traduce.
drop policy if exists "Create own entry" on public.challenge_entries;
create policy "Create own entry"
  on public.challenge_entries for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.challenges c where c.id = challenge_id)
  );

drop policy if exists "Update own entry" on public.challenge_entries;
create policy "Update own entry"
  on public.challenge_entries for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Quitar tu marca, mientras el reto esté abierto: terminado, la tabla final no se mueve.
drop policy if exists "Delete own entry or admin" on public.challenge_entries;
create policy "Delete own entry or admin"
  on public.challenge_entries for delete to authenticated
  using (
    (user_id = auth.uid() and public.challenge_is_open(challenge_id))
    or public.is_habit_admin()
  );

-- Bloqueos, igual que posts en la 128: restrictive, se suman con AND a las de arriba.
drop policy if exists "Hide blocked authors" on public.challenges;
create policy "Hide blocked authors"
  on public.challenges as restrictive for select to authenticated
  using (public.community_visible_author(created_by));

drop policy if exists "Hide blocked authors" on public.challenge_entries;
create policy "Hide blocked authors"
  on public.challenge_entries as restrictive for select to authenticated
  using (public.community_visible_author(user_id));

-- Permisos por columna: lo demás lo ponen los triggers. Supabase le da todo a anon sobre las
-- tablas nuevas de public (la lección de la 124): se quita explícito.
revoke all on table public.challenges, public.challenge_entries from anon, authenticated;
grant select, delete on table public.challenges, public.challenge_entries to authenticated;
grant insert (title, description, score_type, time_cap_sec, has_divisions, starts_on, ends_on)
  on table public.challenges to authenticated;
grant update (title, description, score_type, time_cap_sec, has_divisions, starts_on, ends_on,
              is_official, status)
  on table public.challenges to authenticated;
grant insert (challenge_id, division, rounds, reps, time_sec, load_kg, finished, note, proof_url)
  on table public.challenge_entries to authenticated;
grant update (division, rounds, reps, time_sec, load_kg, finished, note, proof_url)
  on table public.challenge_entries to authenticated;

revoke all on table public.challenge_standings, public.challenge_cards from anon, authenticated;
grant select on table public.challenge_standings, public.challenge_cards to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Reportes (amplía la 128)
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.community_reports
  add column if not exists challenge_id uuid references public.challenges(id) on delete set null,
  add column if not exists entry_id uuid references public.challenge_entries(id) on delete set null;

alter table public.community_reports drop constraint if exists community_reports_target_kind_check;
alter table public.community_reports add constraint community_reports_target_kind_check
  check (target_kind in ('post', 'comment', 'challenge', 'entry'));

create index if not exists idx_community_reports_challenge on public.community_reports(challenge_id);
create index if not exists idx_community_reports_entry on public.community_reports(entry_id);

create unique index if not exists community_reports_one_pending_challenge
  on public.community_reports(reporter_id, challenge_id)
  where status = 'pendiente' and target_kind = 'challenge';
create unique index if not exists community_reports_one_pending_entry
  on public.community_reports(reporter_id, entry_id)
  where status = 'pendiente' and target_kind = 'entry';

-- La de la 128 con dos ramas más. El orden es el mismo de siempre: comentario, publicación, y
-- después marca y reto. Un reporte de marca también guarda su reto (contexto en la cola, y
-- borrar el reto encuentra de una vez los reportes de sus marcas).
create or replace function public.community_report_fill()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post      public.posts%rowtype;
  v_comment   public.post_comments%rowtype;
  v_challenge public.challenges%rowtype;
  v_entry     public.challenge_entries%rowtype;
begin
  new.reporter_id := coalesce(auth.uid(), new.reporter_id);
  if new.reporter_id is null then
    raise exception 'REPORT_NO_SESSION';
  end if;

  if new.comment_id is not null then
    select * into v_comment from public.post_comments where id = new.comment_id;
    if not found then raise exception 'REPORT_TARGET_GONE'; end if;
    new.target_kind      := 'comment';
    new.post_id          := v_comment.post_id;
    new.challenge_id     := null;
    new.entry_id         := null;
    new.reported_user_id := v_comment.user_id;
    new.author_name      := v_comment.user_name;
    new.content_snapshot := v_comment.text_content;
    new.img_snapshot     := null;
  elsif new.post_id is not null then
    select * into v_post from public.posts where id = new.post_id;
    if not found then raise exception 'REPORT_TARGET_GONE'; end if;
    new.target_kind      := 'post';
    new.challenge_id     := null;
    new.entry_id         := null;
    new.reported_user_id := v_post.user_id;
    new.author_name      := v_post.user_name;
    new.content_snapshot := v_post.text_content;
    new.img_snapshot     := case when v_post.img_url like 'data:%' then null else v_post.img_url end;
  elsif new.entry_id is not null then
    select * into v_entry from public.challenge_entries where id = new.entry_id;
    if not found then raise exception 'REPORT_TARGET_GONE'; end if;
    select * into v_challenge from public.challenges where id = v_entry.challenge_id;
    new.target_kind      := 'entry';
    new.challenge_id     := v_entry.challenge_id;
    new.reported_user_id := v_entry.user_id;
    new.author_name      := v_entry.user_name;
    new.content_snapshot := 'Marca en «' || coalesce(v_challenge.title, 'reto') || '»: '
      || coalesce(public.challenge_score_label(v_challenge.score_type, v_entry.rounds, v_entry.reps,
                                               v_entry.time_sec, v_entry.load_kg, v_entry.finished), '')
      || case when v_entry.division = 'scaled' then ' (Scaled)' else '' end
      || coalesce(E'\n' || v_entry.note, '')
      || coalesce(E'\n' || v_entry.proof_url, '');
    new.img_snapshot     := null;
  elsif new.challenge_id is not null then
    select * into v_challenge from public.challenges where id = new.challenge_id;
    if not found then raise exception 'REPORT_TARGET_GONE'; end if;
    new.target_kind      := 'challenge';
    new.entry_id         := null;
    new.reported_user_id := v_challenge.created_by;
    new.author_name      := v_challenge.created_by_name;
    new.content_snapshot := v_challenge.title
      || case when v_challenge.description <> '' then E'\n' || v_challenge.description else '' end;
    new.img_snapshot     := null;
  else
    raise exception 'REPORT_NO_TARGET';
  end if;

  if new.reported_user_id = new.reporter_id then
    raise exception 'REPORT_OWN_CONTENT';
  end if;

  new.details         := nullif(trim(coalesce(new.details, '')), '');
  new.status          := 'pendiente';
  new.resolved_by     := null;
  new.resolved_at     := null;
  new.resolution_note := null;
  new.created_at      := now();
  return new;
end;
$$;

create or replace function public.community_report_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    insert into public.admin_notifs(message)
    values (
      'Reporte en la comunidad: '
      || case new.reason
           when 'spam' then 'spam'
           when 'acoso' then 'acoso'
           when 'ofensivo' then 'ofensivo'
           when 'sexual' then 'contenido sexual'
           else 'otro motivo'
         end
      || ' · ' || case new.target_kind
                    when 'comment' then 'comentario'
                    when 'challenge' then 'reto'
                    when 'entry' then 'marca de un reto'
                    else 'publicación'
                  end
      || ' de ' || coalesce(nullif(new.author_name, ''), 'un usuario')
    );
  exception when others then
    raise warning 'community_report_notify: %', sqlerrm;
  end;
  return null;
end;
$$;

grant insert (challenge_id, entry_id) on table public.community_reports to authenticated;

-- Cuando el admin borra un reto o una marca, sus reportes pendientes quedan resueltos (lo que
-- api/delete-community-item.js hace para posts). Antes del borrado: después, el set null ya
-- no deja encontrarlos. Si lo borra su autor, se quedan pendientes: la cola los muestra como
-- "ya no existe" y el admin decide, como con un post que su autor borró.
create or replace function public.challenge_resolve_reports()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.is_habit_admin() then
    update public.community_reports
       set status = 'resuelto',
           resolution_note = coalesce(resolution_note, 'Borrado desde la moderación')
     where status = 'pendiente'
       and case when tg_table_name = 'challenges'
                then challenge_id = old.id
                else entry_id = old.id
           end;
  end if;
  return old;
end;
$$;

drop trigger if exists challenge_resolve_reports on public.challenges;
create trigger challenge_resolve_reports
  before delete on public.challenges
  for each row execute function public.challenge_resolve_reports();

drop trigger if exists challenge_resolve_reports on public.challenge_entries;
create trigger challenge_resolve_reports
  before delete on public.challenge_entries
  for each row execute function public.challenge_resolve_reports();

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Permisos de funciones
-- ─────────────────────────────────────────────────────────────────────────────
-- Supabase le da EXECUTE a anon en cada función nueva de public (la 124): se quita explícito.
revoke all on function public.challenge_is_open(uuid) from public, anon;
revoke all on function public.challenge_has_other_entries(uuid) from public, anon;
revoke all on function public.challenge_score_label(text, int, int, int, numeric, boolean) from public, anon;
grant execute on function public.challenge_is_open(uuid) to authenticated;
grant execute on function public.challenge_has_other_entries(uuid) to authenticated;
grant execute on function public.challenge_score_label(text, int, int, int, numeric, boolean) to authenticated;
revoke all on function public.challenge_fill() from public, anon, authenticated;
revoke all on function public.challenge_entry_fill() from public, anon, authenticated;
revoke all on function public.challenge_resolve_reports() from public, anon, authenticated;
revoke all on function public.community_report_fill() from public, anon, authenticated;
revoke all on function public.community_report_notify() from public, anon, authenticated;

-- La tabla del reto se reordena en vivo cuando alguien registra (Realtime respeta la RLS).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'challenge_entries') then
      alter publication supabase_realtime add table public.challenge_entries;
    end if;
  end if;
end $$;

commit;
