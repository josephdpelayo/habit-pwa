-- Bucket para videos/gifs de técnica subidos desde la galería del celular al editar un ejercicio
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'skandi-exercise-media',
  'skandi-exercise-media',
  true,
  52428800, -- 50MB máximo por video
  array['video/mp4','video/quicktime','video/webm','image/gif','image/jpeg','image/jpg','image/png','image/webp']
)
on conflict (id) do nothing;

-- Cualquier crew autenticado puede subir media de técnica (mismo criterio que skandi_update_exercise_media)
create policy "Skandi crew puede subir media de ejercicios"
on storage.objects for insert
to authenticated
with check (bucket_id = 'skandi-exercise-media');

-- Bucket público para que la app pueda reproducir el video/gif
create policy "Media de ejercicios Skandi es pública"
on storage.objects for select
to public
using (bucket_id = 'skandi-exercise-media');

-- Cualquier crew autenticado puede reemplazar/borrar media de técnica (catálogo compartido)
create policy "Skandi crew puede borrar media de ejercicios"
on storage.objects for delete
to authenticated
using (bucket_id = 'skandi-exercise-media');
