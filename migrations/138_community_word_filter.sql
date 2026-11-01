-- 138 · Filtro de palabras de la comunidad (guideline 1.2 de Apple)
--
-- Apple pide a toda app con contenido de usuarios cuatro cosas: reportar, bloquear (las dos en la
-- 128), un contacto publicado (las Normas de la comunidad en la app) y "un método para filtrar
-- el contenido ofensivo antes de que se publique". Esto es lo último.
--
-- Un trigger rechaza el texto de un post, un comentario, un reto (título y descripción) o la nota
-- de una marca si trae una palabra de la lista. La app hace la misma revisión antes de mandar
-- (communityTextBlocked en app.html, misma lista) para avisar al instante; la que decide es esta.
-- Cambiar la lista es cambiarla en los dos lados — scripts/check-community-filter.js compara las
-- dos y falla si no son iguales.
--
-- Qué entra: insultos dirigidos a alguien, insultos homofóbicos y racistas, amenazas y llamados
-- al suicidio, y porno. Qué no: groserías de todos los días ("pinche", "verga", "mierda",
-- "cabrón"), que en Mazatlán son puntuación y bloquearlas solo enseña a escribirlas con
-- asteriscos. Para lo que se cuela están reportar y bloquear.
--
-- Cómo se compara: minúsculas, sin acentos, los números y símbolos que se usan para disfrazar
-- letras (0→o, 1→i, 3→e, 4→a, 5→s, 7→t, @→a, $→s) pasan a su letra, todo lo que no es letra pasa a
-- espacio y las letras repetidas se juntan ("pendejoooo" → "pendejo", "p.e.n.d.e.j.o" no: eso
-- son palabras de una letra). Se busca la palabra entera (\m … \M), para que "disputa" o
-- "computadora" no caigan. Por juntar repetidas, la lista se escribe ya juntada ("zora", no
-- "zorra").
--
-- Solo se revisa lo que cambió: un update que no toca el texto (las reacciones de un post, el
-- status de un reto que el admin oculta) pasa aunque el texto viejo tenga algo, porque ese texto
-- es de antes de la 138 y moderarlo es del admin, no del trigger.

create or replace function public.community_text_normalize(t text)
returns text
language sql
immutable
as $$
  select btrim(regexp_replace(
    regexp_replace(
      translate(lower(coalesce(t, '')), 'áàäâéèëêíìïîóòöôúùüûñ013457@$', 'aaaaeeeeiiiioooouuuunoieastas'),
      '[^a-z]+', ' ', 'g'),
    '(.)\1+', '\1', 'g'))
$$;

create or replace function public.community_blocked_terms()
returns text[]
language sql
immutable
as $$
  select array[
    -- insultos dirigidos a alguien
    'pendejo', 'pendeja', 'pendejos', 'pendejas', 'culero', 'culera', 'culeros', 'culeras',
    'puta', 'putas', 'puto', 'putos', 'putito', 'zora', 'zoras', 'hijo de puta', 'hdp',
    'chinga tu madre', 'chingatumadre', 'ctm', 'malparido', 'malparida',
    -- homofóbicos y racistas
    'maricon', 'maricones', 'marica', 'joto', 'jotos', 'mayate', 'sudaca',
    'fagot', 'fagots', 'fag', 'fags', 'niger', 'nigers', 'niga', 'nigas', 'retard', 'retards',
    -- en inglés, a alguien
    'bitch', 'bitches', 'cunt', 'cunts', 'fuck you', 'motherfucker',
    -- amenazas y suicidio
    'te voy a matar', 'te vamos a matar', 'matate', 'suicidate', 'ojala te mueras',
    'kil yourself', 'kil urself', 'kys',
    -- porno
    'porno', 'porn', 'xvideos', 'pornhub', 'onlyfans'
  ]
$$;

create or replace function public.community_text_blocked(t text)
returns boolean
language sql
immutable
as $$
  select exists (
    select 1
      from unnest(public.community_blocked_terms()) as w
     where public.community_text_normalize(t) ~ ('\m' || w || '\M')
  )
$$;

create or replace function public.community_text_guard()
returns trigger
language plpgsql
as $$
declare
  cols text[];
  c text;
  v text;
begin
  cols := case tg_table_name
    when 'posts'             then array['text_content']
    when 'post_comments'     then array['text_content']
    when 'challenges'        then array['title', 'description']
    when 'challenge_entries' then array['note']
    else array[]::text[]
  end;
  foreach c in array cols loop
    v := to_jsonb(new) ->> c;
    if tg_op = 'UPDATE' and v is not distinct from (to_jsonb(old) ->> c) then
      continue;
    end if;
    if v is not null and public.community_text_blocked(v) then
      raise exception 'COMMUNITY_TEXT_BLOCKED' using errcode = 'check_violation',
        hint = 'El texto tiene una palabra que no se permite en la comunidad.';
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists community_text_guard on public.posts;
create trigger community_text_guard before insert or update on public.posts
  for each row execute function public.community_text_guard();

drop trigger if exists community_text_guard on public.post_comments;
create trigger community_text_guard before insert or update on public.post_comments
  for each row execute function public.community_text_guard();

drop trigger if exists community_text_guard on public.challenges;
create trigger community_text_guard before insert or update on public.challenges
  for each row execute function public.community_text_guard();

drop trigger if exists community_text_guard on public.challenge_entries;
create trigger community_text_guard before insert or update on public.challenge_entries
  for each row execute function public.community_text_guard();

-- Las funciones de texto son inofensivas (no leen tablas), pero no hay por qué dárselas a anon.
revoke execute on function public.community_text_normalize(text) from public, anon;
revoke execute on function public.community_blocked_terms() from public, anon;
revoke execute on function public.community_text_blocked(text) from public, anon;
grant execute on function public.community_text_normalize(text) to authenticated, service_role;
grant execute on function public.community_blocked_terms() to authenticated, service_role;
grant execute on function public.community_text_blocked(text) to authenticated, service_role;
