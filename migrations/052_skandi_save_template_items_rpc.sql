-- saveTemplate() used to delete a template's items then insert the new set as two
-- separate client requests. If the insert failed for any reason (a bad hand-typed
-- rest value tripping the target_rest_sec check constraint, a dropped connection),
-- the delete had already committed and the routine was left with zero exercises,
-- with no rollback. Wrapping both steps in a single plpgsql function makes them one
-- transaction: if the insert raises, the delete is rolled back too.

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
    (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec)
  select
    p_template_id,
    (item->>'exercise_id')::uuid,
    (item->>'sort_order')::int,
    (item->>'target_sets')::int,
    item->>'target_reps',
    (item->>'target_rest_sec')::int
  from jsonb_array_elements(p_items) as item;
end;
$$;

grant execute on function public.save_template_items(uuid, jsonb) to authenticated;
