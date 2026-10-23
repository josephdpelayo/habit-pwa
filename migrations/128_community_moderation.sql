-- Moderación de la comunidad: reportar, bloquear y la cola del admin (docs/HABIT_PARA_TODOS.md, D13).
--
-- Desde HABIT Crew la comunidad es una sola y la lee y usa cualquier cuenta, en las dos apps.
-- Apple (App Store Review Guideline 1.2, contenido generado por usuarios) pide tres cosas antes
-- de publicar una app así: que se pueda reportar lo ofensivo, que se pueda bloquear a quien
-- molesta, y que alguien atienda los reportes. Esta migración es lo que hace falta en la base:
--
--   1. community_reports: un reporte de una publicación o un comentario, con su motivo y su
--      estado (pendiente / resuelto / descartado). El socio inserta los suyos y no lee ninguno;
--      el admin lee y actualiza todos. Lo reportado se copia al reporte al insertarlo
--      (autor, texto, foto): si el autor lo borra, el admin sigue sabiendo qué se reportó, y el
--      cliente no puede mentir sobre a quién reporta porque esas columnas las llena el trigger.
--   2. community_blocks: quién bloqueó a quién. Privada: cada quien ve y quita solo los suyos.
--   3. El filtro del bloqueo, en políticas de la base (ver §3 sobre por qué ahí y no en el
--      cliente).
--
-- Borrar lo reportado sigue siendo api/delete-community-item.js (el admin, con service role);
-- ese endpoint ahora también marca resueltos los reportes pendientes de lo que borra.
--
-- Orden de despliegue: cualquiera. La app publicada no lee estas tablas; la app nueva sin esta
-- migración muestra el menú pero reportar y bloquear dan error ("falta la migración 128").
--
-- Requiere la 117 (is_habit_admin).

begin;

do $$
begin
  if to_regprocedure('public.is_habit_admin()') is null then
    raise exception 'Falta la migración 117 (public.is_habit_admin). Córrela antes que esta.';
  end if;
  if to_regclass('public.post_comments') is null or to_regclass('public.user_notifications') is null then
    raise exception 'Falta la migración 005 (post_comments, user_notifications). Córrela antes que esta.';
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Bloqueos
-- ─────────────────────────────────────────────────────────────────────────────
-- Si cualquiera de los dos borra su cuenta, el bloqueo ya no tiene a quién aplicarse.
create table if not exists public.community_blocks (
  blocker_id  uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  blocked_id  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint community_blocks_not_self check (blocker_id <> blocked_id)
);

-- La llave primaria cubre las dos preguntas del filtro (las dos columnas por igualdad); este
-- índice es para el on delete cascade cuando se borra la cuenta del bloqueado.
create index if not exists idx_community_blocks_blocked on public.community_blocks(blocked_id);

alter table public.community_blocks enable row level security;

drop policy if exists "Users manage own blocks" on public.community_blocks;
create policy "Users manage own blocks"
  on public.community_blocks for all
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

-- El admin los lee para saber, en la cola, cuánta gente bloqueó a quien están reportando.
-- Quien fue bloqueado nunca lo puede leer: no hay política para blocked_id.
drop policy if exists "Admin reads blocks" on public.community_blocks;
create policy "Admin reads blocks"
  on public.community_blocks for select
  using (public.is_habit_admin());

-- Supabase le da a anon todo sobre las tablas nuevas de public (la lección de la 124). Un
-- bloqueo no se edita: se crea o se quita.
revoke all on table public.community_blocks from anon, authenticated;
grant select, insert, delete on table public.community_blocks to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Reportes
-- ─────────────────────────────────────────────────────────────────────────────
-- Todas las referencias son "on delete set null", no cascade: un reporte es historia de la
-- moderación, y borrar lo reportado (o la cuenta de cualquiera de los dos) no lo debe borrar.
-- Por eso no hay un CHECK de "post_id o comment_id": el set null lo rompería y el borrado de la
-- publicación fallaría. Qué se reportó lo dice target_kind, y que tenga a qué apuntar lo
-- comprueba el trigger al insertar.
create table if not exists public.community_reports (
  id                uuid primary key default gen_random_uuid(),
  reporter_id       uuid default auth.uid() references public.profiles(id) on delete set null,
  target_kind       text not null check (target_kind in ('post', 'comment')),
  -- Un reporte de comentario también guarda su publicación: la cola la muestra como contexto, y
  -- borrar la publicación encuentra de una vez los reportes de sus comentarios.
  post_id           uuid references public.posts(id) on delete set null,
  comment_id        uuid references public.post_comments(id) on delete set null,
  reported_user_id  uuid references public.profiles(id) on delete set null,
  reason            text not null check (reason in ('spam', 'acoso', 'ofensivo', 'sexual', 'otro')),
  details           text check (details is null or char_length(details) <= 300),
  -- Copia de lo reportado al momento del reporte (la llena el trigger, nunca el cliente).
  author_name       text,
  content_snapshot  text,
  img_snapshot      text,
  status            text not null default 'pendiente'
                      check (status in ('pendiente', 'resuelto', 'descartado')),
  resolved_by       uuid references public.profiles(id) on delete set null,
  resolved_at       timestamptz,
  resolution_note   text check (resolution_note is null or char_length(resolution_note) <= 300),
  created_at        timestamptz not null default now()
);

create index if not exists idx_community_reports_queue on public.community_reports(status, created_at desc);
-- Para el on delete set null (sin índice, borrar un post recorre todos los reportes) y para
-- que api/delete-community-item.js encuentre los pendientes de lo que borra.
create index if not exists idx_community_reports_post on public.community_reports(post_id);
create index if not exists idx_community_reports_comment on public.community_reports(comment_id);

-- Un reporte pendiente por persona y por cosa: reportar dos veces no suma, y el cliente
-- traduce el 23505 a "ya lo habías reportado". Dos índices y no uno sobre
-- coalesce(comment_id, post_id): borrar el comentario deja su reporte apuntando solo a la
-- publicación, chocaría con un reporte de esa publicación y el borrado fallaría.
create unique index if not exists community_reports_one_pending_post
  on public.community_reports(reporter_id, post_id)
  where status = 'pendiente' and target_kind = 'post';
create unique index if not exists community_reports_one_pending_comment
  on public.community_reports(reporter_id, comment_id)
  where status = 'pendiente' and target_kind = 'comment';

-- Al insertar: quién reporta lo dice la sesión, y qué se reporta lo dice la base. El cliente
-- solo manda post_id o comment_id, el motivo y el detalle (es lo único que tiene permiso de
-- escribir, ver los grants abajo). Security definer para leer la publicación o el comentario
-- sin depender de lo que su RLS le deje ver a quien reporta.
create or replace function public.community_report_fill()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post    public.posts%rowtype;
  v_comment public.post_comments%rowtype;
begin
  -- Desde la app siempre es la sesión; sin sesión (SQL Editor) vale lo que se haya puesto.
  new.reporter_id := coalesce(auth.uid(), new.reporter_id);
  if new.reporter_id is null then
    raise exception 'REPORT_NO_SESSION';
  end if;

  if new.comment_id is not null then
    select * into v_comment from public.post_comments where id = new.comment_id;
    if not found then raise exception 'REPORT_TARGET_GONE'; end if;
    new.target_kind      := 'comment';
    new.post_id          := v_comment.post_id;
    new.reported_user_id := v_comment.user_id;
    new.author_name      := v_comment.user_name;
    new.content_snapshot := v_comment.text_content;
    new.img_snapshot     := null;
  elsif new.post_id is not null then
    select * into v_post from public.posts where id = new.post_id;
    if not found then raise exception 'REPORT_TARGET_GONE'; end if;
    new.target_kind      := 'post';
    new.reported_user_id := v_post.user_id;
    new.author_name      := v_post.user_name;
    new.content_snapshot := v_post.text_content;
    new.img_snapshot     := v_post.img_url;
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

drop trigger if exists community_report_fill on public.community_reports;
create trigger community_report_fill
  before insert on public.community_reports
  for each row execute function public.community_report_fill();

-- El admin se entera en Alertas (admin_notifs, que ya escucha por Realtime). Un aviso que
-- falla nunca debe tumbar el reporte: se degrada a WARNING.
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
      || ' · ' || case new.target_kind when 'comment' then 'comentario' else 'publicación' end
      || ' de ' || coalesce(nullif(new.author_name, ''), 'un usuario')
    );
  exception when others then
    raise warning 'community_report_notify: %', sqlerrm;
  end;
  return null;
end;
$$;

drop trigger if exists community_report_notify on public.community_reports;
create trigger community_report_notify
  after insert on public.community_reports
  for each row execute function public.community_report_notify();

-- Al resolver: quién y cuándo los pone la base. Desde la app es la sesión del admin; desde
-- api/delete-community-item.js (service role, sin auth.uid()) vale el resolved_by que manda.
-- No toca nada más a propósito: el on delete set null de las referencias también es un
-- UPDATE que pasa por aquí, y congelar esas columnas haría fallar el borrado.
create or replace function public.community_report_stamp()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'pendiente' then
      new.resolved_by := null;
      new.resolved_at := null;
    else
      new.resolved_by := coalesce(auth.uid(), new.resolved_by);
      new.resolved_at := now();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists community_report_stamp on public.community_reports;
create trigger community_report_stamp
  before update on public.community_reports
  for each row execute function public.community_report_stamp();

alter table public.community_reports enable row level security;

drop policy if exists "Users insert own reports" on public.community_reports;
create policy "Users insert own reports"
  on public.community_reports for insert to authenticated
  with check (reporter_id = auth.uid());

-- Sin política de lectura para el socio, ni de los suyos: el reporte lleva la nota del admin y
-- el estado de la revisión, que no son de quien reporta. El duplicado se detecta por el índice.
drop policy if exists "Admin reads reports" on public.community_reports;
create policy "Admin reads reports"
  on public.community_reports for select
  using (public.is_habit_admin());

drop policy if exists "Admin updates reports" on public.community_reports;
create policy "Admin updates reports"
  on public.community_reports for update
  using (public.is_habit_admin())
  with check (public.is_habit_admin());

-- Permisos por columna: el socio solo escribe qué reporta y por qué; el admin solo cambia el
-- estado y su nota. Lo demás lo ponen los triggers. Nadie borra reportes desde la app.
revoke all on table public.community_reports from anon, authenticated;
grant select on table public.community_reports to authenticated;
grant insert (post_id, comment_id, reason, details) on table public.community_reports to authenticated;
grant update (status, resolution_note) on table public.community_reports to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lo bloqueado deja de verse
-- ─────────────────────────────────────────────────────────────────────────────
-- El filtro va en la base y no en renderFeedSb, por cuatro razones:
--   a. Una regla, un lugar. HABIT y HABIT Crew son el mismo app.html, pero la app nativa de
--      la App Store y cualquier pantalla nueva que lea posts (notificaciones, un perfil, el
--      Inicio) tendrían que repetir el filtro, y la que lo olvide enseña lo bloqueado.
--   b. PostgREST aplica la RLS también a lo embebido: el feed pide
--      posts?select=*,post_comments(...), y con la política los comentarios de alguien
--      bloqueado desaparecen dentro de las publicaciones de otros sin que el cliente lo sepa.
--   c. Lo bloqueado no llega al teléfono, y el limit(50) del feed cuenta publicaciones que
--      sí se ven (filtrar después dejaba páginas más cortas).
--   d. Cuesta dos búsquedas por la llave primaria de community_blocks por fila.
--
-- Políticas RESTRICTIVE, no cambios a las permisivas: se suman con AND a las que ya existen.
-- Las de lectura de posts y comentarios las han recreado la 001, la 005 y la 007 con nombres
-- distintos, y una permisiva más que no conozcamos anularía un filtro escrito como permisiva.
--
-- El bloqueo corre en los dos sentidos: quien bloquea deja de ver al bloqueado, y el
-- bloqueado deja de ver (y de poder comentar o reaccionar a) lo de quien lo bloqueó. Si no,
-- el bloqueado seguiría comentando debajo de sus publicaciones: quien bloqueó no lo vería,
-- pero todos los demás sí, y ese es justo el acoso que el bloqueo debe parar.
-- El admin queda fuera del segundo sentido: si bloquearlo lo dejara ciego, bloquear al admin
-- sería la forma de esconderse de la moderación. Lo que el admin bloquea, él tampoco lo ve.
--
-- Security definer porque el segundo sentido lee filas de community_blocks que la RLS no le
-- deja ver a quien pregunta (las de blocked_id = él).
--
-- Las políticas son "to authenticated": anon no puede ejecutar estas funciones, y una
-- política suya que las llamara convertiría su lectura de posts (hoy vacía, porque ninguna
-- permisiva lo deja pasar sin auth.uid()) en un error de permisos.
create or replace function public.community_visible_author(p_author uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_author is null
      or auth.uid() is null
      or p_author = auth.uid()
      or (
        not exists (
          select 1 from public.community_blocks
          where blocker_id = auth.uid() and blocked_id = p_author
        )
        and (
          not exists (
            select 1 from public.community_blocks
            where blocker_id = p_author and blocked_id = auth.uid()
          )
          or public.is_habit_admin()
        )
      );
$$;

-- ¿Puede la sesión comentar o reaccionar en esta publicación? Lee al autor con permisos de
-- dueño: desde la sesión del bloqueado la publicación ya no se ve, y un select normal
-- devolvería null y lo dejaría pasar. Si la publicación no existe decide la llave foránea.
create or replace function public.community_can_interact(p_post uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select public.community_visible_author(p.user_id) from public.posts p where p.id = p_post),
    true
  );
$$;

revoke all on function public.community_visible_author(uuid) from public, anon;
revoke all on function public.community_can_interact(uuid) from public, anon;
grant execute on function public.community_visible_author(uuid) to authenticated;
grant execute on function public.community_can_interact(uuid) to authenticated;
-- Las funciones de trigger no se llaman directo, pero Supabase igual le da EXECUTE a anon.
revoke all on function public.community_report_fill() from public, anon, authenticated;
revoke all on function public.community_report_notify() from public, anon, authenticated;
revoke all on function public.community_report_stamp() from public, anon, authenticated;

drop policy if exists "Hide blocked authors" on public.posts;
create policy "Hide blocked authors"
  on public.posts as restrictive for select to authenticated
  using (public.community_visible_author(user_id));

drop policy if exists "Hide blocked authors" on public.post_comments;
create policy "Hide blocked authors"
  on public.post_comments as restrictive for select to authenticated
  using (public.community_visible_author(user_id));

-- Las notificaciones de "X comentó / reaccionó" de alguien bloqueado tampoco se ven (las de
-- antes del bloqueo, y cualquiera que entre por otro camino).
drop policy if exists "Hide blocked actors" on public.user_notifications;
create policy "Hide blocked actors"
  on public.user_notifications as restrictive for select to authenticated
  using (public.community_visible_author(actor_id));

drop policy if exists "No interaction across blocks" on public.post_comments;
create policy "No interaction across blocks"
  on public.post_comments as restrictive for insert to authenticated
  with check (public.community_can_interact(post_id));

drop policy if exists "No interaction across blocks" on public.post_reactions;
create policy "No interaction across blocks"
  on public.post_reactions as restrictive for insert to authenticated
  with check (public.community_can_interact(post_id));

commit;
