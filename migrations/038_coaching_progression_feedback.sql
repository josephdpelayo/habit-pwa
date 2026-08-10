-- Enrich post-workout feedback so the coach can adjust the next progression.
alter table coaching_schedule
  add column if not exists feedback_difficulty text
    check (feedback_difficulty is null or feedback_difficulty in ('facil','normal','pesado')),
  add column if not exists feedback_soreness_area text,
  add column if not exists feedback_soreness_level integer
    check (feedback_soreness_level is null or (feedback_soreness_level >= 0 and feedback_soreness_level <= 10)),
  add column if not exists feedback_soreness_trend text
    check (feedback_soreness_trend is null or feedback_soreness_trend in ('mejor','igual','peor')),
  add column if not exists progression_hint text;

-- Optional technique metadata for exercise cards. Existing routines continue
-- to work from the JSON stored in boards.exercises; this prepares the catalog.
do $$
begin
  if to_regclass('public.exercise_catalog') is not null then
    alter table public.exercise_catalog
      add column if not exists common_mistakes text,
      add column if not exists coach_tips text;
  end if;
end $$;
