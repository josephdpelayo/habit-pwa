-- Retos, Fase 2: los avisos (docs/RETOS.md).
--
--   · "X registró su marca en tu reto": al autor, la primera vez que alguien registra.
--   · "X te pasó en «…»": a quien una marca nueva o corregida deja atrás en la tabla.
--
-- Los escribe un trigger y no la app, por dos razones:
--   a. "Te pasaron" pide comparar la tabla de antes con la de después, y el orden ya vive en un
--      solo lugar (la base). Ahora vive en challenge_sort_key(), que usan la vista y el aviso:
--      si cambia la regla, cambia para los dos.
--   b. La app no puede fingir un aviso de reto: user_notifications ya deja que cualquier sesión
--      inserte un aviso para cualquiera (005), pero los de tipo challenge_* solo los escribe
--      este trigger (ver la política restrictiva de abajo).
--
-- El push (para quien tiene la app cerrada) lo sigue mandando la app después de guardar, como
-- en los comentarios: la base no llama a la función send-push.
--
-- Cuántos avisos: quien registra por primera vez puede dejar atrás a 40 personas. Se avisa a
-- las 10 más cercanas (las que estaban justo encima y quedaron debajo); a las demás un aviso de
-- alguien que nunca vieron cerca les dice poco.
--
-- Requiere la 129.

begin;

do $$
begin
  if to_regclass('public.challenge_entries') is null then
    raise exception 'Falta la migración 129 (retos). Córrela antes que esta.';
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. El orden, en una función
-- ─────────────────────────────────────────────────────────────────────────────
-- Dos llaves "más es mejor" (las de la 129, ahora en un solo lugar). Un arreglo se compara
-- elemento por elemento, así que key_a > key_b es "a va adelante de b" antes del desempate por
-- scored_at.
create or replace function public.challenge_sort_key(
  p_type text, p_rounds int, p_reps int, p_time_sec int, p_load_kg numeric, p_finished boolean
)
returns numeric[]
language sql
immutable
set search_path = public
as $$
  select case p_type
    when 'amrap'    then array[coalesce(p_rounds, 0), coalesce(p_reps, 0)]::numeric[]
    when 'for_time' then case when p_finished
                           then array[1, -p_time_sec]::numeric[]
                           else array[0, coalesce(p_reps, 0)]::numeric[] end
    when 'max_reps' then array[coalesce(p_reps, 0), 0]::numeric[]
    when 'max_load' then array[coalesce(p_load_kg, 0), 0]::numeric[]
    when 'max_time' then array[coalesce(p_time_sec, 0), 0]::numeric[]
  end;
$$;

-- Las mismas columnas que en la 129; solo cambia de dónde sale el orden.
create or replace view public.challenge_standings
with (security_invoker = true) as
select
  e.*,
  c.score_type,
  public.challenge_score_label(c.score_type, e.rounds, e.reps, e.time_sec, e.load_kg, e.finished) as score_label,
  rank() over (
    partition by e.challenge_id, e.division
    order by public.challenge_sort_key(c.score_type, e.rounds, e.reps, e.time_sec, e.load_kg, e.finished) desc,
             e.scored_at asc
  ) as place
from public.challenge_entries e
join public.challenges c on c.id = e.challenge_id;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. user_notifications sabe de retos
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.user_notifications
  add column if not exists challenge_id uuid references public.challenges(id) on delete cascade;

create index if not exists idx_user_notifications_challenge on public.user_notifications(challenge_id);

-- El CHECK de type lo crearon la 001 y la 005 sin nombre propio; se busca por lo que dice en vez
-- de suponer cómo se llama.
do $$
declare
  r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.user_notifications'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%type%'
  loop
    execute format('alter table public.user_notifications drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.user_notifications add constraint user_notifications_type_check
  check (type in ('reaction', 'comment', 'challenge_entry', 'challenge_passed'));

-- Desde la app se siguen insertando reacciones y comentarios (005); los de retos no. Restrictive:
-- se suma con AND a la política permisiva de la 005, sin tener que conocer su nombre.
drop policy if exists "Challenge notifications only from the trigger" on public.user_notifications;
create policy "Challenge notifications only from the trigger"
  on public.user_notifications as restrictive for insert to authenticated
  with check (type in ('reaction', 'comment') and challenge_id is null);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. El trigger
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.challenge_entry_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  c        public.challenges%rowtype;
  v_new    numeric[];
  v_old    numeric[];
  v_fresh  boolean;
  v_name   text := coalesce(nullif(new.user_name, ''), 'Alguien');
  v_label  text;
  v_passed uuid[] := '{}';
begin
  -- Corregir la nota o el video no mueve la marca (scored_at es de la 129): no hay aviso.
  if tg_op = 'UPDATE' and new.scored_at is not distinct from old.scored_at then
    return null;
  end if;

  begin
    select * into c from public.challenges where id = new.challenge_id;
    if not found then return null; end if;

    v_new   := public.challenge_sort_key(c.score_type, new.rounds, new.reps, new.time_sec, new.load_kg, new.finished);
    v_label := public.challenge_score_label(c.score_type, new.rounds, new.reps, new.time_sec, new.load_kg, new.finished);
    -- Cambiar de división es entrar a otra tabla: cuenta como la primera vez en esa.
    v_fresh := tg_op = 'INSERT' or new.division is distinct from old.division;
    if not v_fresh then
      v_old := public.challenge_sort_key(c.score_type, old.rounds, old.reps, old.time_sec, old.load_kg, old.finished);
    end if;

    -- A quién dejó atrás: estaba adelante (o empatado y había registrado antes) y ahora va
    -- detrás. Las 10 más cercanas.
    with passed as (
      select o.user_id
      from public.challenge_entries o
      where o.challenge_id = new.challenge_id
        and o.division = new.division
        and o.user_id <> new.user_id
        and public.challenge_sort_key(c.score_type, o.rounds, o.reps, o.time_sec, o.load_kg, o.finished) < v_new
        and (
          v_fresh
          or public.challenge_sort_key(c.score_type, o.rounds, o.reps, o.time_sec, o.load_kg, o.finished) > v_old
          or (public.challenge_sort_key(c.score_type, o.rounds, o.reps, o.time_sec, o.load_kg, o.finished) = v_old
              and o.scored_at < old.scored_at)
        )
      order by public.challenge_sort_key(c.score_type, o.rounds, o.reps, o.time_sec, o.load_kg, o.finished) desc,
               o.scored_at asc
      limit 10
    ), ins as (
      insert into public.user_notifications (user_id, actor_id, actor_name, challenge_id, type, message)
      select p.user_id, new.user_id, v_name, c.id, 'challenge_passed',
             v_name || ' te pasó en «' || c.title || '» con ' || v_label
      from passed p
      returning user_id
    )
    select coalesce(array_agg(user_id), '{}') into v_passed from ins;

    -- Al autor, la primera vez que alguien registra (no en cada corrección). Si además lo
    -- pasó, ya tiene ese aviso.
    if tg_op = 'INSERT'
       and c.created_by is not null
       and c.created_by <> new.user_id
       and not (c.created_by = any(v_passed)) then
      insert into public.user_notifications (user_id, actor_id, actor_name, challenge_id, type, message)
      values (c.created_by, new.user_id, v_name, c.id, 'challenge_entry',
              v_name || ' registró su marca en tu reto «' || c.title || '»: ' || v_label);
    end if;
  exception when others then
    -- Un aviso que falla nunca debe tumbar la marca.
    raise warning 'challenge_entry_notify: %', sqlerrm;
  end;
  return null;
end;
$$;

drop trigger if exists challenge_entry_notify on public.challenge_entries;
create trigger challenge_entry_notify
  after insert or update on public.challenge_entries
  for each row execute function public.challenge_entry_notify();

revoke all on function public.challenge_sort_key(text, int, int, int, numeric, boolean) from public, anon;
grant execute on function public.challenge_sort_key(text, int, int, int, numeric, boolean) to authenticated;
revoke all on function public.challenge_entry_notify() from public, anon, authenticated;

commit;
