-- Skandi Fit: catch skandi_progression_state up to what's actually been trained.
--
-- 078's seed step (section 10) only ever ran once, and only INSERTed — "on conflict do
-- nothing" — so a group that already had a saved rank was left untouched forever. Any session
-- that assigns a specific progression variant directly (a coach-authored day like 086's deload
-- week, or a manual data load) never went through the app's ◀▶ stepper or swap panel, which are
-- the only two places that write to this table. The result: a member can complete real sets on
-- a harder rank (Front Lever Half Lay) while the routine's "current" slot keeps resolving back
-- to whatever was saved before — a straddle they've already moved past.
--
-- This is a one-time reconciliation; going forward, skandi.html's toggleSet() calls
-- advanceProgressionIfAhead() so a completed set at a higher rank than the saved one advances
-- the state immediately. Advance-only, same as that function: this never lowers a saved rank,
-- only raises it to match a rank the member has proven with a completed set.
--
-- Idempotent: safe to run again.

with best as (
  select distinct on (s.user_id, e.progression_group)
    s.user_id, e.progression_group, e.id as exercise_id, e.progression_rank
  from public.skandi_sets s
  join public.skandi_sessions ss on ss.id = s.session_id
  join public.skandi_exercises e on e.id = s.exercise_id
  where e.progression_group is not null
    and s.done
    and ss.completed_at is not null
  order by s.user_id, e.progression_group, e.progression_rank desc
)
update public.skandi_progression_state ps
set exercise_id = best.exercise_id, updated_at = now()
from best, public.skandi_exercises cur
where ps.user_id = best.user_id
  and ps.progression_group = best.progression_group
  and cur.id = ps.exercise_id
  and best.progression_rank > cur.progression_rank;

-- Groups with completed sets but no saved state at all yet (same seed 078 already does, kept
-- here so this migration is a complete fix on its own).
insert into public.skandi_progression_state (user_id, progression_group, exercise_id)
select distinct on (s.user_id, e.progression_group)
  s.user_id, e.progression_group, e.id
from public.skandi_sets s
join public.skandi_sessions ss on ss.id = s.session_id
join public.skandi_exercises e on e.id = s.exercise_id
where e.progression_group is not null
  and s.done
  and ss.completed_at is not null
order by s.user_id, e.progression_group, e.progression_rank desc
on conflict (user_id, progression_group) do nothing;
