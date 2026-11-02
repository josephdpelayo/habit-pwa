-- Enlaza las animaciones de las escaleras de front lever y parada de manos.
--
-- Los archivos viven en el repo (`skill-anim/*.svg`, generados por
-- `scripts/make-skill-anim.py`) y Vercel los sirve como cualquier estático, así que aquí no
-- hay que subir nada a un bucket: la URL es una ruta del propio sitio. El bucket
-- `skill-media` de la 141 sigue siendo para lo que suba el coach desde Admin.
--
-- Son SVG animados, que dentro de un <img> corren solos, pesan unos kilobytes y se ven
-- nítidos lo mismo a 58 px en la escalera que a tamaño de hoja.
--
-- **No pisan nada.** Solo escriben donde `animation_url` está vacío, porque el día que el
-- coach suba el video real de un escalón esa URL es la buena y una segunda corrida de esta
-- migración no debe devolverle el dibujo.
--
-- Requiere la 141.

begin;

-- Que el bucket acepte también SVG: si el coach quiere subir un dibujo propio en vez de un
-- GIF, no hay razón para negárselo (la 141 solo listó mapas de bits y video).
update storage.buckets
   set allowed_mime_types = array['image/gif','image/webp','image/png','image/jpeg',
                                 'image/svg+xml','video/mp4','video/webm']
 where id = 'skill-media';

create temporary table _anim(slug text primary key) on commit drop;

insert into _anim values
  -- Front lever, los ocho escalones
  ('colgado-invertido'),
  ('front-lever-tuck'),
  ('front-lever-tuck-avanzado'),
  ('front-lever-a-una-pierna'),
  ('front-lever-straddle'),
  ('front-lever-half-lay'),
  ('front-lever-completo'),
  ('front-lever-a-un-brazo'),
  -- Parada de manos, los siete
  ('plancha-en-pared-45-grados'),
  ('parada-de-manos-en-pared'),
  ('parada-de-manos-de-frente-a-la-pared'),
  ('heel-pulls-toe-pulls'),
  ('parada-de-manos-libre'),
  ('traspaso-de-peso-en-parada-de-manos'),
  ('parada-de-manos-a-un-brazo');

update public.exercise_catalog c
   set animation_url = '/skill-anim/' || a.slug || '.svg',
       updated_at = now()
  from _anim a
 where c.slug = a.slug
   and c.animation_url is null;

-- La portada de cada línea es el escalón que la nombra: el front lever completo y la parada
-- de manos libre. Las otras cinco líneas se quedan sin portada hasta que haya dibujo o video.
update public.coach_skills
   set animation_url = '/skill-anim/front-lever-completo.svg', updated_at = now()
 where slug = 'front-lever' and animation_url is null;

update public.coach_skills
   set animation_url = '/skill-anim/parada-de-manos-libre.svg', updated_at = now()
 where slug = 'handstand' and animation_url is null;

do $$
declare
  con   integer;
  falta integer;
begin
  select count(*) into con
    from public.exercise_catalog c join _anim a on a.slug = c.slug
   where c.animation_url is not null;
  select count(*) into falta
    from _anim a
   where not exists (select 1 from public.exercise_catalog c where c.slug = a.slug);
  raise notice '% de 15 escalones con animación.', con;
  if falta > 0 then
    raise notice '% escalón(es) de la lista no existen en el catálogo: ¿se corrió la 141?', falta;
  end if;
end $$;

commit;
