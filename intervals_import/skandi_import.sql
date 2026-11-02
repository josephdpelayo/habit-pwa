-- Importa el bloque de resistencia 31 ago - 5 oct 2026 (intervals_import/) a Skandi Fit
-- como sesiones planeadas manuales (source='manual'), una por fecha. No toca skandi_templates
-- ni ninguna plantilla recurrente: es calendario fechado, igual que copyPlannedTo() en
-- skandi.html. Correrlo dos veces no duplica: el anti-join descarta filas que ya existan para
-- ese usuario, dia y titulo.
--
-- Pegar completo en Supabase SQL Editor. Ajustar el correo si esta cuenta no es la tuya.

with plan (day, discipline, title, duration_min, distance_km, zone, sort_order, notes) as (
  values

    (date '2026-09-01', 'swim', $plan$N1 - Natacion tecnica base$plan$, 35, 0.35, null, 1, $plan$Objetivo: primera evaluacion tecnica y comodidad en el agua. 35 min, 350 m orientativos. Exhalar dentro del agua, mirada hacia abajo y posicion horizontal.

Calentamiento 4x
- Facil 25mtr intensity=warmup
- Descanso 20s intensity=rest

Tecnica 6x
- Drill instructor 25mtr intensity=active
- Descanso 30s intensity=rest

Nado completo 4x
- Crol facil 25mtr intensity=active
- Descanso 30s intensity=recovery$plan$),
    (date '2026-09-02', 'swim', $plan$N2 - Natacion tecnica y respiracion$plan$, 40, 0.5, null, 1, $plan$Objetivo: coordinar respiracion con posicion. 40 min, 500 m orientativos.

Calentamiento 4x
- Facil 25mtr intensity=warmup
- Descanso 20s intensity=rest

Tecnica 6x
- Drill instructor 25mtr intensity=active
- Descanso 30s intensity=rest

Crol facil 6x
- Crol relajado 25mtr intensity=active
- Descanso 30s intensity=recovery

Final 2x
- Crol facil 50mtr intensity=active
- Descanso 40s intensity=recovery$plan$),
    (date '2026-09-03', 'bike', $plan$B1 - Bici facil 40$plan$, 40, null, 2, 1, $plan$Objetivo: mantener el patron actual sin fatigar piernas antes del vuelo. RPE 3-4.

- Calentamiento RPE2 8m freeride intensity=warmup
- Z2 conversacional RPE3-4 27m freeride 85-95rpm intensity=active
- Enfriamiento 5m freeride intensity=cooldown$plan$),
    (date '2026-09-06', 'run', $plan$R1 - Carrera Z2 40$plan$, 40, null, 2, 1, $plan$Objetivo: carrera facil tras el vuelo. Objetivo real 140-148 bpm; techo practico 150. Si el sueno fue malo, hacer 5 + 20 + 5.

- Calentamiento 5m Z1 HR intensity=warmup
- Z2 ideal 140-148 techo150 30m Z2 HR intensity=active
- Enfriamiento 5m Z1 HR intensity=cooldown$plan$),
    (date '2026-09-07', 'bike', $plan$B2 - Bici de adaptacion 45$plan$, 45, null, 2, 1, $plan$Objetivo: actividad aerobica ligera durante el jet lag.

- Calentamiento RPE2 10m freeride intensity=warmup
- Z2 conversacional RPE3 30m freeride 85-95rpm intensity=active
- Enfriamiento 5m freeride intensity=cooldown$plan$),
    (date '2026-09-08', 'run', $plan$R2 - Carrera Z2 40$plan$, 40, null, 2, 1, $plan$Objetivo: carrera facil, sin calidad por jet lag. 140-148 bpm, RPE 3-4.

- Calentamiento 5m Z1 HR intensity=warmup
- Z2 ideal 140-148 techo150 30m Z2 HR intensity=active
- Enfriamiento 5m Z1 HR intensity=cooldown$plan$),
    (date '2026-09-12', 'other', $plan$S1 - Clase de surf 45-60 min$plan$, null, null, null, 1, $plan$Solo con instructor y condiciones vigiladas. Registrar como Surf, no como natacion. No anadir bici o carrera este dia.$plan$),
    (date '2026-09-13', 'bike', $plan$B3 - Bici larga facil 65$plan$, 65, null, 2, 1, $plan$Objetivo: mantener el fondo de bici. RPE 3-4.

- Calentamiento RPE2 10m freeride intensity=warmup
- Fondo Z2 conversacional 50m freeride 85-95rpm intensity=active
- Enfriamiento 5m freeride intensity=cooldown$plan$),
    (date '2026-09-15', 'bike', $plan$B4 - Bici facil 40 o surf$plan$, 40, null, 2, 1, $plan$Si hay clase de surf y condiciones seguras, hacer surf 45-60 min y omitir esta bici.

- Calentamiento RPE2 8m freeride intensity=warmup
- Z2 conversacional RPE3 27m freeride 85-95rpm intensity=active
- Enfriamiento 5m freeride intensity=cooldown$plan$),
    (date '2026-09-17', 'run', $plan$Q1 - Carrera 6x1 min$plan$, 36, null, null, 1, $plan$Separar al menos 6 h de F3. En cinta usar 14.5-15.0 km/h, RPE 7-8; no es sprint maximo. Si hay fatiga de viaje o dolor, sustituir por 35 min faciles.

- Calentamiento progresivo 10m Z1-Z2 HR intensity=warmup

Rapido controlado 6x
- Cinta 14.5-15kph RPE7-8 1m intensity=interval
- Trote o caminata 2m Z1 HR intensity=recovery

- Enfriamiento completo 8m Z1 HR intensity=cooldown$plan$),
    (date '2026-09-19', 'bike', $plan$B5 - Bici larga 70-75$plan$, 75, null, 2, 1, $plan$Objetivo: progresar sin anadir carrera. Si hay fatiga de F4, reducir el bloque central 5 min.

- Calentamiento RPE2 10m freeride intensity=warmup
- Fondo Z2 conversacional 60m freeride 85-95rpm intensity=active
- Enfriamiento 5m freeride intensity=cooldown$plan$),
    (date '2026-09-20', 'run', $plan$R3 - Carrera Z2 40$plan$, 40, null, 2, 1, $plan$Objetivo: correr facil sobre fatiga ligera de bici.

- Calentamiento 5m Z1 HR intensity=warmup
- Z2 ideal 140-148 techo150 30m Z2 HR intensity=active
- Enfriamiento 5m Z1 HR intensity=cooldown$plan$),
    (date '2026-09-23', 'swim', $plan$N3 - Natacion de reentrada$plan$, 40, 0.5, null, 1, $plan$Objetivo: recuperar sensaciones. 40 min, 500 m orientativos.

Calentamiento 4x
- Facil 25mtr intensity=warmup
- Descanso 20s intensity=rest

Tecnica 4x
- Drill instructor 25mtr intensity=active
- Descanso 30s intensity=rest

Crol facil 8x
- Crol relajado 25mtr intensity=active
- Descanso 30s intensity=recovery

Vuelta calma 4x
- Muy facil 25mtr intensity=cooldown
- Descanso 20s intensity=rest$plan$),
    (date '2026-09-23', 'run', $plan$R4 - Carrera Z2 corta 30$plan$, 30, null, 2, 2, $plan$Realizar 4-6 h despues de nadar. Omitir si la natacion genero mucha fatiga.

- Calentamiento 5m Z1 HR intensity=warmup
- Z2 ideal 140-148 techo150 20m Z2 HR intensity=active
- Enfriamiento 5m Z1 HR intensity=cooldown$plan$),
    (date '2026-09-24', 'bike', $plan$B6 - Bici con cadencia 45$plan$, 45, null, 2, 1, $plan$Objetivo: economia de pedaleo. Cadencia rapida con resistencia ligera, sin rebotar.

- Calentamiento RPE2 8m freeride 80-90rpm intensity=warmup

Cadencia 6x
- Cadencia agil RPE4 1m freeride 95-105rpm intensity=interval
- Pedaleo facil 2m freeride 80-90rpm intensity=recovery

- Z2 estable 14m freeride 85-95rpm intensity=active
- Enfriamiento 5m freeride intensity=cooldown$plan$),
    (date '2026-09-25', 'swim', $plan$N4 - Natacion tecnica 600 m$plan$, null, 0.6, null, 1, $plan$Separar 6 h de F4. Si 50 m deteriora la tecnica, cambiar cada uno por 2 x 25 m.

Calentamiento 4x
- Facil 25mtr intensity=warmup
- Descanso 20s intensity=rest

Tecnica 6x
- Drill instructor 25mtr intensity=active
- Descanso 30s intensity=rest

Principal 6x
- Crol facil 50mtr intensity=active
- Descanso 35s intensity=recovery

Vuelta calma 2x
- Muy facil 25mtr intensity=cooldown$plan$),
    (date '2026-09-26', 'bike', $plan$B7 - Bici larga 75$plan$, 75, null, 2, 1, $plan$- Calentamiento RPE2 10m freeride intensity=warmup
- Fondo Z2 conversacional 60m freeride 85-95rpm intensity=active
- Preparar transicion 5m freeride intensity=cooldown$plan$),
    (date '2026-09-26', 'run', $plan$BR1 - Brick 10$plan$, 10, null, 2, 2, $plan$Comenzar en menos de 5 min despues de B7. No perseguir ritmo.

- Adaptacion piernas 3m Z1 HR intensity=warmup
- Trote Z2 controlado 7m Z2 HR intensity=active$plan$),
    (date '2026-09-29', 'swim', $plan$N5 - Natacion con 50 m$plan$, 45, 0.65, null, 1, $plan$Objetivo: acumular nado relajado. 45 min, 650 m aproximados.

Calentamiento 4x
- Facil 25mtr intensity=warmup
- Descanso 20s intensity=rest

Tecnica 4x
- Drill instructor 25mtr intensity=active
- Descanso 30s intensity=rest

Principal 8x
- Crol facil 50mtr intensity=active
- Descanso 35s intensity=recovery

Vuelta calma 2x
- Muy facil 25mtr intensity=cooldown$plan$),
    (date '2026-09-30', 'run', $plan$Q2 - Carrera 6x1 min$plan$, 36, null, null, 1, $plan$Objetivo: repetir con mejor control, sin septima repeticion. Cinta 14.5-15.0 km/h y RPE 7-8.

- Calentamiento progresivo 10m Z1-Z2 HR intensity=warmup

Rapido controlado 6x
- Cinta 14.5-15kph RPE7-8 1m intensity=interval
- Trote o caminata 2m Z1 HR intensity=recovery

- Enfriamiento completo 8m Z1 HR intensity=cooldown$plan$),
    (date '2026-10-01', 'bike', $plan$B8 - Bici facil 45$plan$, 45, null, 2, 1, $plan$Objetivo: recuperacion aerobica despues de Q2 y F3.

- Calentamiento RPE2 10m freeride intensity=warmup
- Z2 baja conversacional 30m freeride 85-95rpm intensity=active
- Enfriamiento 5m freeride intensity=cooldown$plan$),
    (date '2026-10-02', 'swim', $plan$N6 - Natacion de repeticiones largas$plan$, null, null, null, 1, $plan$Objetivo: sostener 75 m solo si la tecnica permanece estable. Alternativa: 12 x 25 m con 25-30 s.

Calentamiento 4x
- Facil 25mtr intensity=warmup
- Descanso 20s intensity=rest

Tecnica 4x
- Drill instructor 25mtr intensity=active
- Descanso 30s intensity=rest

Principal 4x
- Crol relajado 75mtr intensity=active
- Descanso 45s intensity=recovery

Vuelta calma 2x
- Muy facil 50mtr intensity=cooldown$plan$),
    (date '2026-10-03', 'bike', $plan$B9 - Bici larga 80$plan$, 80, null, 2, 1, $plan$Objetivo: mayor duracion de bici del bloque, completamente aerobica.

- Calentamiento RPE2 10m freeride intensity=warmup
- Fondo Z2 conversacional 65m freeride 85-95rpm intensity=active
- Preparar transicion 5m freeride intensity=cooldown$plan$),
    (date '2026-10-03', 'run', $plan$BR2 - Brick 15$plan$, 15, null, 2, 2, $plan$Comenzar en menos de 5 min despues de B9.

- Adaptacion piernas 3m Z1 HR intensity=warmup
- Trote Z2 controlado 10m Z2 HR intensity=active
- Soltar 2m Z1 HR intensity=cooldown$plan$)
),
me as (
  select id as user_id from auth.users where email = 'josephdpelayo@gmail.com'
)
insert into public.skandi_planned_sessions
  (user_id, day, discipline, source, title, target_duration_min, target_distance_km,
   target_zone, sort_order, notes, is_edited)
select me.user_id, p.day, p.discipline, 'manual', p.title, p.duration_min, p.distance_km,
       p.zone, p.sort_order, p.notes, true
from plan p cross join me
where me.user_id is not null
  and not exists (
    select 1 from public.skandi_planned_sessions x
    where x.user_id = me.user_id and x.day = p.day and x.title = p.title
  );
