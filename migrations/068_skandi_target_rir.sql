-- Skandi Fit: pre-load the routine's recommended RIR onto each set, editable per set.
--
-- RIR was already logged per set (migration 064) but had no target on the routine itself —
-- the app just carried forward whatever RIR was actually logged last session, which is a
-- history number, not an instruction. target_rir is the coach-set goal for that exercise
-- slot ("aim for RIR 1-2"); the app now seeds a new set's rir from it, and the member can
-- still edit that field per set exactly as before if that day actually went differently.
--
-- Denormalized onto skandi_sets too, same reasoning as target_rest_sec (migration 051): an
-- active workout's exercise list is derived entirely from the session's own sets, so a swap
-- mid-workout or a page reload must not require re-reading the (possibly now-stale)
-- template to know the target.

alter table public.skandi_template_items add column if not exists target_rir integer check (target_rir is null or target_rir between 0 and 10);
alter table public.skandi_sets add column if not exists target_rir integer check (target_rir is null or target_rir between 0 and 10);

-- Backfill: 2 is the middle of Plan_Hibrido_Final_v3's blanket "RIR 1-2 per compound" rule
-- (see migration 064) and a reasonable universal starting point for every existing rep-based
-- slot — seconds-based holds (front lever, planche, handstand, ...) don't use RIR at all, so
-- those are left null. Adjust per exercise afterward from the routine builder if a different
-- target fits better.
update public.skandi_template_items ti
set target_rir = 2
from public.skandi_exercises ex
where ex.id = ti.exercise_id
  and coalesce(ex.log_mode,'reps') <> 'seconds'
  and ti.target_rir is null;

update public.skandi_sets s
set target_rir = ti.target_rir
from public.skandi_sessions sess
join public.skandi_template_items ti
  on ti.template_id = sess.template_id
where s.session_id = sess.id
  and ti.exercise_id = s.exercise_id
  and s.target_rir is null;

-- save_template_items (migration 052) writes the routine builder's items in one transaction;
-- needs to carry target_rir through now that the builder can set it.
create or replace function public.save_template_items(p_template_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.skandi_templates t
    where t.id = p_template_id and t.user_id = auth.uid()
  ) then
    raise exception 'Not allowed to edit this template';
  end if;

  delete from public.skandi_template_items where template_id = p_template_id;

  insert into public.skandi_template_items
    (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir)
  select
    p_template_id,
    (item->>'exercise_id')::uuid,
    (item->>'sort_order')::int,
    (item->>'target_sets')::int,
    item->>'target_reps',
    (item->>'target_rest_sec')::int,
    (item->>'target_rir')::int
  from jsonb_array_elements(p_items) as item;
end;
$$;

grant execute on function public.save_template_items(uuid, jsonb) to authenticated;
