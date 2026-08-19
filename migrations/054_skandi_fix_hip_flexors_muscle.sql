-- decline-sit-up (migration 043) used muscle key "Hip Flexors", which isn't in
-- skandi-recovery.js's MUSCLE_RECOVERY_HOURS taxonomy (11 keys, no hip flexors) or in the
-- Body tab's region lists — that 10% of stimulus was silently discarded forever
-- (buildStimulusEvents just skips any muscle key it doesn't recognize). Fold it into Core,
-- which is already carrying the other 90% of this exercise and is the closest recognized
-- muscle group for a weighted sit-up.

update public.skandi_exercises
set muscles = '{"Core":100}'::jsonb,
    updated_at = now()
where slug = 'decline-sit-up';
