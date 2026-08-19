-- weight_kg had no bounds (unlike reps, which is checked 0-1000). A negative value gets
-- silently reinterpreted as a bodyweight-proxy load by the recovery engine instead of being
-- rejected, and an absurdly large one produces a pathological stimulus that jumps straight
-- to "fully fresh" once it ages past the engine's 10-day lookback window instead of decaying
-- smoothly. Clamp any existing bad rows, then constrain going forward.

update public.skandi_sets set weight_kg = null where weight_kg < 0;
update public.skandi_sets set weight_kg = 500 where weight_kg > 500;

alter table public.skandi_sets
  add constraint skandi_sets_weight_kg_range check (weight_kg is null or (weight_kg >= 0 and weight_kg <= 500));
