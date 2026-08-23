-- Skandi Fit: las zonas de frecuencia cardiaca del atleta, tal como las tiene en su reloj.
--
-- Hasta ahora el motor de fatiga deducía la zona como un porcentaje de la FC máxima, con
-- bandas fijas (58/68/79/89%). Es una aproximación razonable cuando no hay nada mejor, y es
-- mala justo donde más se usa: con FCmáx 193, un rodaje suave real a 140–150 ppm (Z2 en su
-- reloj) caía en la misma banda que 160 ppm y se puntuaba 6.5 sobre 10. Los días fáciles
-- contaban como medio duros, que es exactamente lo contrario de lo que una semana de descarga
-- tiene que registrar.
--
-- El reloj ya sabe las zonas buenas —vienen de una prueba de umbral, no de una fórmula— así
-- que se guardan y se usan. Sin ellas nada cambia: el motor sigue con sus bandas relativas.

alter table public.skandi_settings
  add column if not exists resting_hr integer
    check (resting_hr is null or resting_hr between 25 and 120),
  add column if not exists lthr integer
    check (lthr is null or lthr between 90 and 220),
  -- Cuatro números: el piso de Z2, Z3, Z4 y Z5. Z1 es todo lo que quede debajo del primero,
  -- así que no necesita su propio valor. Guardarlos como límites y no como rangos hace
  -- imposible que queden huecos o traslapes entre zonas contiguas.
  add column if not exists hr_zone_bounds integer[]
    check (
      hr_zone_bounds is null
      or (
        array_length(hr_zone_bounds, 1) = 4
        and hr_zone_bounds[1] between 60 and 220
        and hr_zone_bounds[1] < hr_zone_bounds[2]
        and hr_zone_bounds[2] < hr_zone_bounds[3]
        and hr_zone_bounds[3] < hr_zone_bounds[4]
        and hr_zone_bounds[4] <= 230
      )
    );

comment on column public.skandi_settings.hr_zone_bounds is
  'Pisos de Z2, Z3, Z4 y Z5 en ppm, copiados del reloj. Z1 es todo lo de abajo. Null = deducir por %FCmáx.';
comment on column public.skandi_settings.lthr is
  'Frecuencia cardiaca de umbral de lactato. Todavía no la consume el motor; queda para las zonas por deporte y el ritmo umbral.';
