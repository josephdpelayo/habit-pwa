-- Calisthenics hold progressions (front lever, back lever, planche, handstand): lets a
-- routine slot stay fixed ("Front Lever Hold") while the actual variant performed advances
-- automatically as the user gets stronger, and lets static holds log seconds instead of reps.
--
-- progression_group + progression_rank chain the exercises already in the catalog (048) into
-- ordered skill lines. log_mode marks which exercises are timed holds rather than rep-based.
-- skandi_progression_state remembers, per user per skill line, which variant they're
-- currently working — read at workout-start time to resolve the template's exercise_id into
-- whatever the user is actually training right now.

alter table public.skandi_exercises add column if not exists progression_group text;
alter table public.skandi_exercises add column if not exists progression_rank integer;
alter table public.skandi_exercises add column if not exists log_mode text not null default 'reps' check (log_mode in ('reps','seconds'));

update public.skandi_exercises set progression_group='front-lever', progression_rank=1, log_mode='seconds' where slug='front-lever-tuck';
update public.skandi_exercises set progression_group='front-lever', progression_rank=2, log_mode='seconds' where slug='front-lever-advanced-tuck';
update public.skandi_exercises set progression_group='front-lever', progression_rank=3, log_mode='seconds' where slug='front-lever-straddle';
update public.skandi_exercises set progression_group='front-lever', progression_rank=4, log_mode='seconds' where slug='front-lever-full';
update public.skandi_exercises set progression_group='front-lever', progression_rank=5, log_mode='seconds' where slug='one-leg-front-lever';
update public.skandi_exercises set progression_group='front-lever', progression_rank=6, log_mode='seconds' where slug='one-arm-front-lever';

update public.skandi_exercises set progression_group='back-lever', progression_rank=1, log_mode='seconds' where slug='back-lever-tuck';
update public.skandi_exercises set progression_group='back-lever', progression_rank=2, log_mode='seconds' where slug='back-lever-straddle';
update public.skandi_exercises set progression_group='back-lever', progression_rank=3, log_mode='seconds' where slug='back-lever-full';

update public.skandi_exercises set progression_group='planche', progression_rank=1, log_mode='seconds' where slug='planche-lean';
update public.skandi_exercises set progression_group='planche', progression_rank=2, log_mode='seconds' where slug='tuck-planche';
update public.skandi_exercises set progression_group='planche', progression_rank=3, log_mode='seconds' where slug='advanced-tuck-planche';
update public.skandi_exercises set progression_group='planche', progression_rank=4, log_mode='seconds' where slug='straddle-planche';
update public.skandi_exercises set progression_group='planche', progression_rank=5, log_mode='seconds' where slug='full-planche';

update public.skandi_exercises set progression_group='handstand', progression_rank=1, log_mode='seconds' where slug='wall-handstand';
update public.skandi_exercises set progression_group='handstand', progression_rank=2, log_mode='seconds' where slug='freestanding-handstand';

-- Static holds that aren't part of a multi-step skill line still log seconds, not reps.
update public.skandi_exercises set log_mode='seconds' where slug in ('plank','l-sit','hollow-body-hold','frog-stand');

create table if not exists public.skandi_progression_state (
  user_id           uuid references public.profiles(id) on delete cascade not null,
  progression_group text not null,
  exercise_id       uuid references public.skandi_exercises(id) on delete cascade not null,
  updated_at        timestamptz not null default now(),
  primary key (user_id, progression_group)
);

create index if not exists idx_skandi_progression_state_user on public.skandi_progression_state(user_id);

alter table public.skandi_progression_state enable row level security;

drop policy if exists "Crew read skandi progression state" on public.skandi_progression_state;
create policy "Crew read skandi progression state"
  on public.skandi_progression_state for select using (auth.role() = 'authenticated');

drop policy if exists "Crew manage own skandi progression state" on public.skandi_progression_state;
create policy "Crew manage own skandi progression state"
  on public.skandi_progression_state for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
