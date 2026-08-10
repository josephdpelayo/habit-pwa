-- Let authenticated Skandi Fit crew attach/update technique media on shared exercises
-- without granting broad write access to the exercise catalog.

create or replace function public.skandi_update_exercise_media(
  p_exercise_id uuid,
  p_media_url text,
  p_media_page_url text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  update public.skandi_exercises
  set
    media_url = nullif(trim(p_media_url), ''),
    media_page_url = nullif(trim(coalesce(p_media_page_url, '')), ''),
    updated_at = now()
  where id = p_exercise_id;
end;
$$;
