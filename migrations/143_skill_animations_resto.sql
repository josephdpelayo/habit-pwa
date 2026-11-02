-- Las animaciones de las cinco líneas que faltaban: planche, elevaciones a front lever,
-- muscle-up, back lever y curl nórdico. Con esto las siete escaleras están dibujadas.
--
-- Mismo trato que la 142: los SVG viven en el repo (`skill-anim/`, generados por
-- `scripts/make-skill-anim.py`) y se sirven como estáticos, y la URL **solo se escribe donde
-- está vacía**, para que el video que suba el coach nunca se pierda al volver a correrla.
--
-- Va aparte de la 142 porque la 142 ya está publicada: una migración que ya se corrió no se
-- edita, se le añade la siguiente.
--
-- Requiere la 141.

begin;

create temporary table _anim2(slug text primary key) on commit drop;

insert into _anim2 values
  -- Planche
  ('planche-lean'),
  ('plancha-tuck'),
  ('plancha-tuck-avanzada'),
  ('plancha-straddle'),
  ('plancha-completa'),
  -- Elevaciones a front lever: las únicas, junto al nórdico, donde la figura se mueve de
  -- verdad, porque ahí el movimiento ES el ejercicio y no un aguante.
  ('elevacion-a-front-lever-tuck'),
  ('elevacion-a-front-lever-tuck-avanzado'),
  ('elevacion-a-front-lever-straddle'),
  ('elevaciones-a-front-lever'),
  -- Muscle-up
  ('dominada-al-pecho'),
  ('dominada-con-agarre-falso'),
  ('muscle-up-negativo'),
  ('muscle-up-en-barra'),
  -- Back lever
  ('back-lever-tuck'),
  ('back-lever-straddle'),
  ('back-lever-completo'),
  -- Curl nórdico
  ('curl-nordico-negativo'),
  ('curl-nordico-asistido'),
  ('curl-nordico'),
  ('curl-nordico-con-peso');

update public.exercise_catalog c
   set animation_url = '/skill-anim/' || a.slug || '.svg',
       updated_at = now()
  from _anim2 a
 where c.slug = a.slug
   and c.animation_url is null;

-- La portada de cada línea es el escalón que la nombra.
update public.coach_skills s
   set animation_url = '/skill-anim/' || v.slug || '.svg', updated_at = now()
  from (values
    ('planche',           'plancha-completa'),
    ('front-lever-raise', 'elevaciones-a-front-lever'),
    ('muscle-up',         'muscle-up-en-barra'),
    ('back-lever',        'back-lever-completo'),
    ('nordic-curl',       'curl-nordico')
  ) as v(skill, slug)
 where s.slug = v.skill
   and s.animation_url is null;

do $$
declare
  con   integer;
  lineas integer;
begin
  select count(*) into con
    from public.exercise_catalog c
   where c.progression_group is not null and c.animation_url is not null;
  select count(*) into lineas
    from public.coach_skills where animation_url is not null;
  raise notice '% de 35 escalones con animación; % de 7 líneas con portada.', con, lineas;
  if con < 35 then
    raise notice 'Si falta alguno: ¿se corrió la 142 antes que esta?';
  end if;
end $$;

commit;
