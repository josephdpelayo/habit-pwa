-- Bucket público para imágenes de posts de la comunidad
-- Las imágenes ya no se guardan como base64 en la tabla posts
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community-images',
  'community-images',
  true,
  5242880, -- 5MB máximo por imagen
  array['image/jpeg','image/jpg','image/png','image/webp']
)
on conflict (id) do nothing;

-- Cualquier usuario autenticado puede subir a su propia carpeta
create policy "Usuarios pueden subir sus fotos"
on storage.objects for insert
to authenticated
with check (bucket_id = 'community-images' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Cualquiera puede leer (bucket público)
create policy "Fotos de comunidad son públicas"
on storage.objects for select
to public
using (bucket_id = 'community-images');

-- Solo el dueño puede borrar sus fotos
create policy "Usuarios pueden borrar sus fotos"
on storage.objects for delete
to authenticated
using (bucket_id = 'community-images' AND (storage.foldername(name))[1] = auth.uid()::text);
