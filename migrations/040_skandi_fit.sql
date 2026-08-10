-- Skandi Fit: crew workout app sharing the HABIT Supabase project.
-- Local, non-paid, all authenticated crew members can train and see shared progress.

create table if not exists public.skandi_exercises (
  id             uuid primary key default uuid_generate_v4(),
  slug           text not null unique,
  name           text not null,
  english_name   text,
  category       text not null default 'Fuerza',
  equipment      text[] not null default '{}',
  muscles        jsonb not null default '{}'::jsonb,
  media_url      text,
  media_page_url text,
  instructions   text[] not null default '{}',
  coach_tips     text[] not null default '{}',
  created_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table if not exists public.skandi_templates (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  name        text not null,
  notes       text,
  weekday     integer check (weekday is null or weekday between 0 and 6),
  is_public   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.skandi_template_items (
  id             uuid primary key default uuid_generate_v4(),
  template_id    uuid references public.skandi_templates(id) on delete cascade not null,
  exercise_id    uuid references public.skandi_exercises(id) on delete restrict not null,
  sort_order     integer not null default 0,
  target_sets    integer not null default 3 check (target_sets between 1 and 12),
  target_reps    text not null default '8-12',
  target_rest_sec integer not null default 90 check (target_rest_sec between 0 and 900),
  note           text,
  unique(template_id, exercise_id, sort_order)
);

create table if not exists public.skandi_sessions (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid references public.profiles(id) on delete cascade not null,
  template_id        uuid references public.skandi_templates(id) on delete set null,
  title             text not null,
  started_at         timestamptz not null default now(),
  completed_at       timestamptz,
  duration_sec       integer,
  report_difficulty  text check (report_difficulty is null or report_difficulty in ('facil','normal','pesado')),
  report_energy      integer check (report_energy is null or report_energy between 1 and 5),
  report_soreness    boolean not null default false,
  report_soreness_area text,
  report_note        text,
  visibility         text not null default 'crew' check (visibility in ('private','crew')),
  created_at         timestamptz not null default now()
);

create table if not exists public.skandi_sets (
  id           uuid primary key default uuid_generate_v4(),
  session_id   uuid references public.skandi_sessions(id) on delete cascade not null,
  user_id      uuid references public.profiles(id) on delete cascade not null,
  exercise_id  uuid references public.skandi_exercises(id) on delete restrict not null,
  set_idx      integer not null check (set_idx between 1 and 30),
  target_reps  text,
  weight_kg    numeric(7,2),
  reps         integer check (reps is null or reps between 0 and 1000),
  seconds      integer check (seconds is null or seconds between 0 and 7200),
  done         boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique(session_id, exercise_id, set_idx)
);

create index if not exists idx_skandi_templates_user_weekday on public.skandi_templates(user_id, weekday);
create index if not exists idx_skandi_items_template on public.skandi_template_items(template_id, sort_order);
create index if not exists idx_skandi_sessions_user_completed on public.skandi_sessions(user_id, completed_at desc);
create index if not exists idx_skandi_sets_user_exercise on public.skandi_sets(user_id, exercise_id, created_at desc);

alter table public.skandi_exercises enable row level security;
alter table public.skandi_templates enable row level security;
alter table public.skandi_template_items enable row level security;
alter table public.skandi_sessions enable row level security;
alter table public.skandi_sets enable row level security;

drop policy if exists "Crew read skandi exercises" on public.skandi_exercises;
create policy "Crew read skandi exercises"
  on public.skandi_exercises for select using (auth.role() = 'authenticated');

drop policy if exists "Crew create skandi exercises" on public.skandi_exercises;
create policy "Crew create skandi exercises"
  on public.skandi_exercises for insert with check (auth.uid() = created_by);

drop policy if exists "Crew update own skandi exercises" on public.skandi_exercises;
create policy "Crew update own skandi exercises"
  on public.skandi_exercises for update using (auth.uid() = created_by) with check (auth.uid() = created_by);

drop policy if exists "Crew read shared skandi templates" on public.skandi_templates;
create policy "Crew read shared skandi templates"
  on public.skandi_templates for select using (auth.uid() = user_id or is_public = true);

drop policy if exists "Crew manage own skandi templates" on public.skandi_templates;
create policy "Crew manage own skandi templates"
  on public.skandi_templates for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Crew read shared skandi template items" on public.skandi_template_items;
create policy "Crew read shared skandi template items"
  on public.skandi_template_items for select using (
    exists (
      select 1 from public.skandi_templates t
      where t.id = template_id and (t.user_id = auth.uid() or t.is_public = true)
    )
  );

drop policy if exists "Crew manage own skandi template items" on public.skandi_template_items;
create policy "Crew manage own skandi template items"
  on public.skandi_template_items for all using (
    exists (select 1 from public.skandi_templates t where t.id = template_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.skandi_templates t where t.id = template_id and t.user_id = auth.uid())
  );

drop policy if exists "Crew read visible skandi sessions" on public.skandi_sessions;
create policy "Crew read visible skandi sessions"
  on public.skandi_sessions for select using (auth.uid() = user_id or visibility = 'crew');

drop policy if exists "Crew manage own skandi sessions" on public.skandi_sessions;
create policy "Crew manage own skandi sessions"
  on public.skandi_sessions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Crew read visible skandi sets" on public.skandi_sets;
create policy "Crew read visible skandi sets"
  on public.skandi_sets for select using (
    auth.uid() = user_id
    or exists (
      select 1 from public.skandi_sessions s
      where s.id = session_id and s.visibility = 'crew'
    )
  );

drop policy if exists "Crew manage own skandi sets" on public.skandi_sets;
create policy "Crew manage own skandi sets"
  on public.skandi_sets for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

insert into public.skandi_exercises
  (slug, name, english_name, category, equipment, muscles, media_page_url, instructions, coach_tips)
values
  ('bench-press-barra','Press banca barra','Barbell Bench Press','Fuerza','{"Barra","Banco"}','{"Pecho":60,"Triceps":25,"Hombros":15}'::jsonb,'https://gymvisual.com/animated-gifs/8340-barbell-weighted-bench-press.html',
   '{"Escapulas atras y abajo.","Pies firmes en el suelo.","Baja controlado al pecho.","Empuja sin perder la espalda fija."}',
   '{"No rebotes la barra.","Mantén muñecas neutras."}'),
  ('dumbbell-bench-press','Press banca mancuernas','Dumbbell Bench Press','Fuerza','{"Mancuernas","Banco"}','{"Pecho":55,"Triceps":25,"Hombros":20}'::jsonb,'https://gymvisual.com/animated-gifs/1782-dumbbell-bench-press.html',
   '{"Mancuernas sobre el pecho.","Baja con codos a 45 grados.","Empuja juntando sin chocar las mancuernas."}',
   '{"Controla el rango.","No pierdas tensión abajo."}'),
  ('sentadilla-barra','Sentadilla barra','Barbell Squat','Fuerza','{"Barra","Rack"}','{"Cuadriceps":45,"Gluteos":30,"Isquios":15,"Core":10}'::jsonb,'https://gymvisual.com/animated-gifs/2267-squat-with-band.html',
   '{"Barra estable sobre la espalda.","Rodillas siguen la linea de los pies.","Baja con control.","Sube empujando el suelo."}',
   '{"No colapses rodillas.","Mantén torso firme."}'),
  ('peso-muerto-rumano','Peso muerto rumano','Romanian Deadlift','Fuerza','{"Barra","Mancuernas"}','{"Isquios":45,"Gluteos":35,"Espalda":10,"Core":10}'::jsonb,null,
   '{"Cadera hacia atras.","Espalda neutra.","Barra pegada al cuerpo.","Sube apretando gluteos."}',
   '{"No conviertas el movimiento en sentadilla.","Siente el estiramiento en isquios."}'),
  ('dominadas-pronas','Dominadas pronas','Wide Grip Pull Ups','Calistenia','{"Barra fija","Peso corporal"}','{"Espalda":55,"Biceps":25,"Core":10,"Antebrazo":10}'::jsonb,null,
   '{"Cuelga con control.","Activa escapulas.","Sube pecho a la barra.","Baja sin soltarte."}',
   '{"Evita patalear.","Deja una repetición en reserva si la tecnica cae."}'),
  ('dominadas-supinas','Dominadas supinas','Supinated Pull Ups','Calistenia','{"Barra fija","Peso corporal"}','{"Biceps":40,"Espalda":40,"Core":10,"Antebrazo":10}'::jsonb,null,
   '{"Palmas hacia ti.","Hombros abajo.","Sube pasando la barbilla.","Baja controlado."}',
   '{"Si molesta el codo, prueba agarre neutro.","No arquees la espalda para compensar."}'),
  ('remo-en-t','Remo en T','T-Bar Row','Fuerza','{"Barra","Mancuernas"}','{"Espalda":55,"Biceps":20,"Core":15,"Hombros":10}'::jsonb,null,
   '{"Inclina torso estable.","Tira con codos.","Pausa atras.","Baja sin redondear."}',
   '{"No conviertas el remo en impulso de cadera."}'),
  ('press-militar','Press militar','Shoulder Press','Fuerza','{"Barra","Mancuernas"}','{"Hombros":55,"Triceps":25,"Core":20}'::jsonb,null,
   '{"Costillas abajo.","Empuja vertical.","Bloquea arriba con control.","Baja a la altura segura."}',
   '{"Aprieta abdomen antes de empujar."}'),
  ('fondos-paralelas','Fondos en paralelas','Dips','Calistenia','{"Paralelas","Peso corporal"}','{"Triceps":40,"Pecho":35,"Hombros":15,"Core":10}'::jsonb,null,
   '{"Hombros lejos de orejas.","Baja controlado.","Empuja hasta extender.","Mantén core firme."}',
   '{"No fuerces profundidad si molesta hombro."}'),
  ('curl-mancuernas','Curl con mancuernas','Dumbbell Curl','Fuerza','{"Mancuernas"}','{"Biceps":75,"Antebrazo":25}'::jsonb,null,
   '{"Codos pegados.","Sube sin balancearte.","Pausa arriba.","Baja lento."}',
   '{"Menos ego, mas control."}'),
  ('extension-triceps-cuerda','Extension triceps cuerda','Rope Triceps Extension','Fuerza','{"Polea","Cuerda"}','{"Triceps":85,"Antebrazo":15}'::jsonb,null,
   '{"Codos fijos.","Extiende hacia abajo.","Abre cuerda al final.","Regresa controlado."}',
   '{"Evita mover hombros para ayudar."}'),
  ('plank','Plancha','Plank','Core','{"Peso corporal"}','{"Core":70,"Hombros":15,"Gluteos":15}'::jsonb,null,
   '{"Codos bajo hombros.","Costillas abajo.","Gluteos activos.","Respira sin perder postura."}',
   '{"Termina antes de romper forma."}')
on conflict (slug) do update set
  name = excluded.name,
  english_name = excluded.english_name,
  category = excluded.category,
  equipment = excluded.equipment,
  muscles = excluded.muscles,
  media_page_url = excluded.media_page_url,
  instructions = excluded.instructions,
  coach_tips = excluded.coach_tips,
  updated_at = now();
