-- Skandi Fit: clean/broken tag for seconds-based skill holds (Front Lever, Handstand,
-- Planche), per Plan_Hibrido_Final_v3 — "mejor hold limpio", "calidad primer vs ultimo set",
-- and Handstand's "numero de intentos controlados" (= count of clean-tagged attempts).
-- Nullable/tri-state on purpose: null means never tagged (most historical sets), true means
-- clean, false means the position broke down before time ran out.

alter table public.skandi_sets
  add column if not exists hold_clean boolean;
