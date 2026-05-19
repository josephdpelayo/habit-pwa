-- ============================================================
-- HABIT SHOP — Setup completo (tablas + productos + políticas)
-- Corre este script en Supabase SQL Editor de una sola vez
-- ============================================================

-- TABLAS ----------------------------------------------------

create table if not exists public.shop_products (
  id text primary key,
  name text not null,
  description text,
  price numeric(10,2) not null check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  track_inventory boolean not null default true,
  image_url text,
  image_urls jsonb not null default '[]',
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shop_orders (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id) on delete set null,
  customer_name text not null,
  customer_email text not null,
  customer_phone text,
  delivery_method text not null check (delivery_method in ('pickup','shipping')),
  shipping_address jsonb,
  subtotal numeric(10,2) not null,
  shipping_fee numeric(10,2) not null default 0,
  total numeric(10,2) not null,
  currency text not null default 'MXN',
  status text not null default 'solicitado'
    check (status in ('pago_pendiente','solicitado','listo_para_entrega','listo_para_enviar','enviado','recibido','cancelado')),
  stripe_id text unique,
  payment_status text not null default 'pending',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shop_order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references public.shop_orders(id) on delete cascade not null,
  product_id text not null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_amount numeric(10,2) not null,
  line_total numeric(10,2) not null
);

-- ÍNDICES ---------------------------------------------------

create index if not exists idx_shop_orders_user     on public.shop_orders(user_id, created_at desc);
create index if not exists idx_shop_orders_status   on public.shop_orders(status, created_at desc);
create index if not exists idx_shop_order_items_order on public.shop_order_items(order_id);
create index if not exists idx_shop_products_active on public.shop_products(active, sort_order);

-- RLS -------------------------------------------------------

alter table public.shop_products  enable row level security;
alter table public.shop_orders     enable row level security;
alter table public.shop_order_items enable row level security;

drop policy if exists "Anyone reads active shop products" on public.shop_products;
create policy "Anyone reads active shop products"
  on public.shop_products for select using (active = true);

drop policy if exists "Admin all shop products" on public.shop_products;
create policy "Admin all shop products"
  on public.shop_products for all
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

drop policy if exists "Users read own shop orders" on public.shop_orders;
create policy "Users read own shop orders"
  on public.shop_orders for select using (auth.uid() = user_id);

drop policy if exists "Admin all shop orders" on public.shop_orders;
create policy "Admin all shop orders"
  on public.shop_orders for all
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

drop policy if exists "Users read own shop order items" on public.shop_order_items;
create policy "Users read own shop order items"
  on public.shop_order_items for select
  using (exists(select 1 from public.shop_orders where id = order_id and user_id = auth.uid()));

drop policy if exists "Admin all shop order items" on public.shop_order_items;
create policy "Admin all shop order items"
  on public.shop_order_items for all
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- COLUMNAS FALTANTES (por si la tabla ya existía sin ellas) --

alter table public.shop_products
  add column if not exists stock           integer         not null default 0   check (stock >= 0),
  add column if not exists track_inventory boolean         not null default true,
  add column if not exists image_url       text,
  add column if not exists image_urls      jsonb           not null default '[]';

-- PRODUCTOS (con imágenes .jpg optimizadas) -----------------

insert into public.shop_products (id, name, description, price, stock, image_url, image_urls, sort_order)
values
  ('whey-1kg', '100% Whey Protein', 'Bolsa 1 kg · proteina para recuperacion diaria', 650, 20,
   'fotosproductos/proteina1.jpeg',
   '["fotosproductos/proteina1.jpeg","fotosproductos/proteina2.jpeg","fotosproductos/proteina3.jpeg"]',
   10),

  ('protein-sachet-33g', 'Sobre personal proteina', 'Una toma de 33 g para salir del entrenamiento listo', 45, 40,
   'fotosproductos/proteina2.jpeg',
   '["fotosproductos/proteina2.jpeg","fotosproductos/proteina1.jpeg","fotosproductos/proteina3.jpeg"]',
   20),

  ('creatine-monohydrate', 'Creatina monohidratada', 'Monohidratada · fuerza, potencia y constancia', 420, 20,
   'fotosproductos/creatina1.jpeg',
   '["fotosproductos/creatina1.jpeg","fotosproductos/creatina2.jpeg","fotosproductos/creatina3.jpeg","fotosproductos/creatina%204.jpeg"]',
   30),

  ('habit-shirt-regular-men-xs', 'Playera HABIT regular fit hombre XS', 'Regular fit para hombre · talla XS', 350, 8,
   'fotosproductos/playera%20habit/regularh1.jpg',
   '["fotosproductos/playera%20habit/regularh1.jpg","fotosproductos/playera%20habit/regularh2.jpg","fotosproductos/playera%20habit/regularh3.jpg"]',
   400),

  ('habit-shirt-regular-men-s', 'Playera HABIT regular fit hombre S', 'Regular fit para hombre · talla S', 350, 8,
   'fotosproductos/playera%20habit/regularh1.jpg',
   '["fotosproductos/playera%20habit/regularh1.jpg","fotosproductos/playera%20habit/regularh2.jpg","fotosproductos/playera%20habit/regularh3.jpg"]',
   410),

  ('habit-shirt-regular-men-m', 'Playera HABIT regular fit hombre M', 'Regular fit para hombre · talla M', 350, 8,
   'fotosproductos/playera%20habit/regularh1.jpg',
   '["fotosproductos/playera%20habit/regularh1.jpg","fotosproductos/playera%20habit/regularh2.jpg","fotosproductos/playera%20habit/regularh3.jpg"]',
   420),

  ('habit-shirt-regular-men-l', 'Playera HABIT regular fit hombre L', 'Regular fit para hombre · talla L', 350, 8,
   'fotosproductos/playera%20habit/regularh1.jpg',
   '["fotosproductos/playera%20habit/regularh1.jpg","fotosproductos/playera%20habit/regularh2.jpg","fotosproductos/playera%20habit/regularh3.jpg"]',
   430),

  ('habit-shirt-regular-men-xl', 'Playera HABIT regular fit hombre XL', 'Regular fit para hombre · talla XL', 350, 8,
   'fotosproductos/playera%20habit/regularh1.jpg',
   '["fotosproductos/playera%20habit/regularh1.jpg","fotosproductos/playera%20habit/regularh2.jpg","fotosproductos/playera%20habit/regularh3.jpg"]',
   440),

  ('habit-shirt-regular-women-s', 'Playera HABIT regular fit mujer S', 'Regular fit para mujer · talla S', 350, 8,
   'fotosproductos/playera%20habit/regularm1.jpg',
   '["fotosproductos/playera%20habit/regularm1.jpg","fotosproductos/playera%20habit/regularm2.jpg"]',
   450),

  ('habit-shirt-regular-women-m', 'Playera HABIT regular fit mujer M', 'Regular fit para mujer · talla M', 350, 8,
   'fotosproductos/playera%20habit/regularm1.jpg',
   '["fotosproductos/playera%20habit/regularm1.jpg","fotosproductos/playera%20habit/regularm2.jpg"]',
   460),

  ('habit-shirt-regular-women-l', 'Playera HABIT regular fit mujer L', 'Regular fit para mujer · talla L', 350, 8,
   'fotosproductos/playera%20habit/regularm1.jpg',
   '["fotosproductos/playera%20habit/regularm1.jpg","fotosproductos/playera%20habit/regularm2.jpg"]',
   470),

  ('habit-shirt-oversize-unisex-xs', 'Playera HABIT oversize unisex XS', 'Oversize unisex · talla XS', 390, 8,
   'fotosproductos/playera%20habit/oversizeh1.jpg',
   '["fotosproductos/playera%20habit/oversizeh1.jpg","fotosproductos/playera%20habit/oversizeh2.jpg","fotosproductos/playera%20habit/oversizeh3.jpg","fotosproductos/playera%20habit/oversizem1.jpg","fotosproductos/playera%20habit/oversizem2.jpg"]',
   480),

  ('habit-shirt-oversize-unisex-s', 'Playera HABIT oversize unisex S', 'Oversize unisex · talla S', 390, 8,
   'fotosproductos/playera%20habit/oversizeh1.jpg',
   '["fotosproductos/playera%20habit/oversizeh1.jpg","fotosproductos/playera%20habit/oversizeh2.jpg","fotosproductos/playera%20habit/oversizeh3.jpg","fotosproductos/playera%20habit/oversizem1.jpg","fotosproductos/playera%20habit/oversizem2.jpg"]',
   490),

  ('habit-shirt-oversize-unisex-m', 'Playera HABIT oversize unisex M', 'Oversize unisex · talla M', 390, 8,
   'fotosproductos/playera%20habit/oversizeh1.jpg',
   '["fotosproductos/playera%20habit/oversizeh1.jpg","fotosproductos/playera%20habit/oversizeh2.jpg","fotosproductos/playera%20habit/oversizeh3.jpg","fotosproductos/playera%20habit/oversizem1.jpg","fotosproductos/playera%20habit/oversizem2.jpg"]',
   500),

  ('habit-shirt-oversize-unisex-l', 'Playera HABIT oversize unisex L', 'Oversize unisex · talla L', 390, 8,
   'fotosproductos/playera%20habit/oversizeh1.jpg',
   '["fotosproductos/playera%20habit/oversizeh1.jpg","fotosproductos/playera%20habit/oversizeh2.jpg","fotosproductos/playera%20habit/oversizeh3.jpg","fotosproductos/playera%20habit/oversizem1.jpg","fotosproductos/playera%20habit/oversizem2.jpg"]',
   510),

  ('habit-shirt-oversize-unisex-xl', 'Playera HABIT oversize unisex XL', 'Oversize unisex · talla XL', 390, 8,
   'fotosproductos/playera%20habit/oversizeh1.jpg',
   '["fotosproductos/playera%20habit/oversizeh1.jpg","fotosproductos/playera%20habit/oversizeh2.jpg","fotosproductos/playera%20habit/oversizeh3.jpg","fotosproductos/playera%20habit/oversizem1.jpg","fotosproductos/playera%20habit/oversizem2.jpg"]',
   520)

on conflict (id) do update set
  name         = excluded.name,
  description  = excluded.description,
  price        = excluded.price,
  image_url    = excluded.image_url,
  image_urls   = excluded.image_urls,
  stock        = greatest(public.shop_products.stock, excluded.stock),
  track_inventory = true,
  sort_order   = excluded.sort_order,
  updated_at   = now();
