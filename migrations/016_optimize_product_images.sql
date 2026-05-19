-- Actualiza rutas de imágenes de playeras de .PNG a .jpg optimizado
-- Las PNG originales eran 1.6-1.9 MB; los .jpg nuevos son ~100 KB (95% menos peso)

-- 1. Agrega columna image_urls si no existe
alter table public.shop_products
  add column if not exists image_urls jsonb not null default '[]';

-- 2. Actualiza image_url (texto simple)
update public.shop_products
set image_url = replace(image_url, '.PNG', '.jpg'),
    updated_at = now()
where image_url like '%.PNG';

-- 3. Actualiza image_urls (array JSON) si tiene valores .PNG
update public.shop_products
set image_urls = (
    select jsonb_agg(to_jsonb(replace(elem #>> '{}', '.PNG', '.jpg')))
    from jsonb_array_elements(image_urls) as elem
  ),
  updated_at = now()
where image_urls::text like '%PNG%';
