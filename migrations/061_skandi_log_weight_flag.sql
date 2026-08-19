-- log_mode (migration 059) already separates reps vs seconds. This adds the other axis:
-- whether logging weight makes sense at all. Pure plyometric/balance drills are essentially
-- never externally loaded, so showing a KG/LB field for them is just noise in the set-row UI.
-- Defaults to true (unchanged behavior) for every existing exercise; only the small set of
-- genuinely bodyweight-only drills below gets flipped off.

alter table public.skandi_exercises add column if not exists log_weight boolean not null default true;

update public.skandi_exercises set log_weight = false
where slug in ('pogo-jumps','cmj-vertical-jump','broad-jump','heel-pulls-toe-pulls','scapular-pull-up','jump-squat');
