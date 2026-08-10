-- Track when a crew member adds someone else's shared routine to their own week,
-- so the copy can still show "Adapted from <name>" after the original is edited or removed.

alter table public.skandi_templates
  add column if not exists forked_from uuid references public.skandi_templates(id) on delete set null,
  add column if not exists forked_from_name text;
