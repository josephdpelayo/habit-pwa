-- Skandi Fit: separar un esfuerzo DECLARADO de un 5 que nadie tocó.
--
-- Contexto. La 081 agregó `intensity_source` con tres valores —'manual' (lo puso una
-- persona), 'heart_rate' (derivado del %FCmáx) y 'default' (nadie lo midió)— y lo dejó con
-- default 'manual'. Ese default es correcto para lo que se captura a mano, pero mintió sobre
-- todo lo ya capturado: el formulario de registro trae el campo de intensidad pre-llenado en
-- 5, así que miles de filas dicen "una persona declaró 5" cuando lo que pasó es que nadie lo
-- tocó.
--
-- Por qué importa ahora. `skandi-recovery.js` cambió la precedencia: un esfuerzo declarado le
-- gana al promedio de frecuencia cardiaca. La razón es que el promedio es el árbitro
-- equivocado justo en las sesiones que más hace el atleta — en un entrenamiento por
-- intervalos los descansos se comen el promedio, y 45 minutos con 15 de Z4 adentro puntúan
-- igual que una hora suave continua. Pero esa precedencia solo es segura si la declaración es
-- de verdad: dejar que un 5 de relleno le gane a un pulso medido sería peor que lo que había.
--
-- Qué hace esta migración. Marca como 'default' las filas capturadas a mano cuyo esfuerzo
-- quedó exactamente en el valor pre-llenado. Las que traen otro número sí son una decisión
-- de la persona y se quedan en 'manual'.
--
-- Alcance deliberado: solo toca `external_source is null` (lo capturado a mano). Lo importado
-- de Strava y de Intervals ya trae su procedencia bien puesta por el importador, y pisarla
-- borraría el RPE que el atleta escribió en su reloj.
--
-- Efecto medible: una actividad a mano con pulso y esfuerzo 5 deja de valer 5 y pasa a valer
-- lo que diga su frecuencia cardiaca. Es el único caso cuyo estímulo se mueve.

update public.skandi_external_activities
set intensity_source = 'default'
where external_source is null
  and intensity_source = 'manual'
  and intensity = 5;

-- Cuántas quedaron de cada tipo, para poder verificar de un vistazo después de correrla.
do $$
declare
  v_declared integer;
  v_default  integer;
begin
  select count(*) into v_declared from public.skandi_external_activities
   where external_source is null and intensity_source = 'manual';
  select count(*) into v_default from public.skandi_external_activities
   where external_source is null and intensity_source = 'default';
  raise notice 'Capturadas a mano: % con esfuerzo declarado, % sin declarar.', v_declared, v_default;
end;
$$;
