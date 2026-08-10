-- Skandi Fit: crew workout app sharing the HABIT Supabase project.
-- Local, non-paid, all authenticated crew members can train and see shared progress.

create table if not exists public.skandi_exercises (
  id             uuid primary key default uuid_generate_v4(),
  slug           text not null unique,
  name           text not null,
  english_name   text,
  category       text not null default 'Strength',
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
  ('barbell-bench-press','Barbell Bench Press','Barbell Bench Press','Strength','{"Barbell","Bench"}','{"Chest":60,"Triceps":25,"Shoulders":15}'::jsonb,'https://gymvisual.com/animated-gifs/8340-barbell-weighted-bench-press.html',
   '{"Set your shoulder blades back and down.","Keep your feet planted.","Lower the bar under control to your chest.","Press without losing upper-back tension."}',
   '{"Do not bounce the bar.","Keep your wrists neutral."}'),
  ('dumbbell-bench-press','Dumbbell Bench Press','Dumbbell Bench Press','Strength','{"Dumbbells","Bench"}','{"Chest":55,"Triceps":25,"Shoulders":20}'::jsonb,'https://gymvisual.com/animated-gifs/1782-dumbbell-bench-press.html',
   '{"Start with the dumbbells over your chest.","Lower with elbows around 45 degrees.","Press up without crashing the dumbbells together."}',
   '{"Control the range.","Do not lose tension at the bottom."}'),
  ('barbell-squat','Barbell Squat','Barbell Squat','Strength','{"Barbell","Rack"}','{"Quads":45,"Glutes":30,"Hamstrings":15,"Core":10}'::jsonb,'https://gymvisual.com/animated-gifs/2267-squat-with-band.html',
   '{"Set the bar securely on your back.","Track knees in line with your feet.","Lower with control.","Drive the floor away to stand up."}',
   '{"Do not let your knees cave in.","Keep your torso braced."}'),
  ('romanian-deadlift','Romanian Deadlift','Romanian Deadlift','Strength','{"Barbell","Dumbbells"}','{"Hamstrings":45,"Glutes":35,"Back":10,"Core":10}'::jsonb,null,
   '{"Push your hips back.","Keep your spine neutral.","Keep the weight close to your body.","Stand tall by squeezing your glutes."}',
   '{"Do not turn it into a squat.","Feel the stretch in your hamstrings."}'),
  ('wide-grip-pull-ups','Wide Grip Pull Ups','Wide Grip Pull Ups','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":55,"Biceps":25,"Core":10,"Forearms":10}'::jsonb,null,
   '{"Hang under control.","Set your shoulder blades.","Pull your chest toward the bar.","Lower without dropping loose."}',
   '{"Avoid kicking.","Leave one rep in reserve if technique breaks."}'),
  ('supinated-pull-ups','Supinated Pull Ups','Supinated Pull Ups','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Biceps":40,"Back":40,"Core":10,"Forearms":10}'::jsonb,null,
   '{"Use palms facing you.","Keep shoulders down.","Pull until your chin clears the bar.","Lower with control."}',
   '{"If your elbow hurts, try neutral grip.","Do not over-arch your back to compensate."}'),
  ('t-bar-row','T-Bar Row','T-Bar Row','Strength','{"Barbell","Dumbbells"}','{"Back":55,"Biceps":20,"Core":15,"Shoulders":10}'::jsonb,null,
   '{"Set a stable torso angle.","Pull with your elbows.","Pause at the top.","Lower without rounding."}',
   '{"Do not turn the row into a hip swing."}'),
  ('shoulder-press','Shoulder Press','Shoulder Press','Strength','{"Barbell","Dumbbells"}','{"Shoulders":55,"Triceps":25,"Core":20}'::jsonb,null,
   '{"Keep ribs down.","Press vertically.","Lock out with control.","Lower to a safe depth."}',
   '{"Brace before each press."}'),
  ('dips','Dips','Dips','Calisthenics','{"Parallel bars","Bodyweight"}','{"Triceps":40,"Chest":35,"Shoulders":15,"Core":10}'::jsonb,null,
   '{"Keep shoulders away from your ears.","Lower with control.","Press until arms extend.","Keep your core tight."}',
   '{"Do not force depth if your shoulder feels off."}'),
  ('dumbbell-curl','Dumbbell Curl','Dumbbell Curl','Strength','{"Dumbbells"}','{"Biceps":75,"Forearms":25}'::jsonb,null,
   '{"Keep elbows close.","Curl without swinging.","Pause at the top.","Lower slowly."}',
   '{"Less ego, more control."}'),
  ('rope-triceps-extension','Rope Triceps Extension','Rope Triceps Extension','Strength','{"Cable","Rope"}','{"Triceps":85,"Forearms":15}'::jsonb,null,
   '{"Keep elbows fixed.","Extend down.","Open the rope at the bottom.","Return with control."}',
   '{"Avoid moving your shoulders to help."}'),
  ('plank','Plank','Plank','Core','{"Bodyweight"}','{"Core":70,"Shoulders":15,"Glutes":15}'::jsonb,null,
   '{"Elbows under shoulders.","Ribs down.","Glutes active.","Breathe without losing position."}',
   '{"Stop before your form breaks."}')
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
