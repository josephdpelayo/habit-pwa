-- ═══════════════════════════════════════════════════════════
-- HABIT Training Hub — Supabase Schema
-- Ejecuta esto en: Supabase → SQL Editor → New query → Run
-- ═══════════════════════════════════════════════════════════

-- ── EXTENSIONES ──
create extension if not exists "uuid-ossp";

-- ── TABLA: profiles (extiende auth.users de Supabase) ──
create table if not exists public.profiles (
  id            uuid references auth.users(id) on delete cascade primary key,
  name          text not null,
  phone         text,
  role          text not null default 'user' check (role in ('user','admin')),
  access_code   text unique not null,
  plan_id       text,
  plan_type     text check (plan_type in ('individual','grupal') or plan_type is null),
  credits       integer not null default 0,
  plan_expiry   timestamptz,
  avatar_url    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ── TABLA: bookings (reservas) ──
create table if not exists public.bookings (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  ds            date not null,
  start_idx     integer not null check (start_idx >= 0 and start_idx < 48),
  slots_used    integer not null default 3 check (slots_used in (2,3)),
  is_group      boolean not null default false,
  grupal_spots  integer,
  time_str      text not null,
  dur_min       integer not null default 90,
  status        text not null default 'active' check (status in ('active','cancelled','completed')),
  created_at    timestamptz not null default now()
);

-- ── TABLA: slot_occupancy (estado de cada slot de 30min) ──
create table if not exists public.slot_occupancy (
  id            uuid primary key default uuid_generate_v4(),
  ds            date not null,
  slot_idx      integer not null check (slot_idx >= 0 and slot_idx < 48),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  booking_id    uuid references public.bookings(id) on delete cascade not null,
  is_group      boolean not null default false,
  spot          integer,
  unique(ds, slot_idx, user_id)
);

-- ── TABLA: slot_blocks (bloqueos manuales admin) ──
create table if not exists public.slot_blocks (
  ds            date not null,
  slot_idx      integer not null check (slot_idx >= 0 and slot_idx < 48),
  spots         integer not null default 1 check (spots between 1 and 4),
  reason        text not null default 'Sin motivo registrado',
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  primary key (ds, slot_idx)
);

-- ── TABLA: waitlists ──
create table if not exists public.waitlists (
  id            uuid primary key default uuid_generate_v4(),
  ds            date not null,
  slot_idx      integer not null,
  user_id       uuid references public.profiles(id) on delete cascade not null,
  created_at    timestamptz not null default now(),
  unique(ds, slot_idx, user_id)
);

-- ── TABLA: payments ──
create table if not exists public.payments (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  plan_id       text not null,
  plan_name     text not null,
  plan_type     text not null,
  amount        numeric(10,2) not null,
  currency      text not null default 'MXN',
  last4         text,
  stripe_id     text,
  payment_method text not null default 'stripe',
  notes         text,
  created_by    uuid references public.profiles(id),
  status        text not null default 'completed',
  created_at    timestamptz not null default now()
);

-- ── TABLA: access_log ──
create table if not exists public.access_log (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  user_name     text not null,
  access_code   text not null,
  slot_str      text,
  accessed_at   timestamptz not null default now()
);

-- ── TABLA: door_commands (cola para abrir puerta) ──
create table if not exists public.door_commands (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  user_name     text not null,
  booking_id    uuid references public.bookings(id) on delete set null,
  access_code   text not null,
  slot_str      text,
  status        text not null default 'pending' check (status in ('pending','processing','opened','failed','expired')),
  lat           double precision,
  lng           double precision,
  accuracy_m    integer,
  distance_m    integer,
  requested_at  timestamptz not null default now(),
  processed_at  timestamptz,
  processed_by  text,
  error_message text
);

-- ── TABLA: boards (pizarrones de rutinas) ──
create table if not exists public.boards (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null,
  color         text not null default '#2563eb',
  exercises     jsonb not null default '[]',
  created_at    timestamptz not null default now()
);

-- ── TABLA: board_assignments ──
create table if not exists public.board_assignments (
  board_id      uuid references public.boards(id) on delete cascade,
  user_id       uuid references public.profiles(id) on delete cascade,
  primary key (board_id, user_id)
);

-- ── TABLA: scores ──
create table if not exists public.scores (
  id            uuid primary key default uuid_generate_v4(),
  board_id      uuid references public.boards(id) on delete cascade not null,
  exercise_idx  integer not null,
  exercise_name text not null,
  user_id       uuid references public.profiles(id) on delete cascade not null,
  user_name     text not null,
  weight_kg     numeric(6,2) not null,
  reps          text,
  logged_at     timestamptz not null default now(),
  unique(board_id, exercise_idx, user_id)
);

-- ── TABLA: posts (comunidad) ──
create table if not exists public.posts (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  user_name     text not null,
  text_content  text,
  img_url       text,
  reactions     jsonb not null default '{"fire":0,"clap":0,"heart":0}',
  created_at    timestamptz not null default now()
);

-- ── TABLA: post_reactions ──
create table if not exists public.post_reactions (
  post_id       uuid references public.posts(id) on delete cascade,
  user_id       uuid references public.profiles(id) on delete cascade,
  reaction_type text not null check (reaction_type in ('fire','clap','heart')),
  primary key (post_id, user_id, reaction_type)
);

-- ── TABLA: post_comments ──
create table if not exists public.post_comments (
  id            uuid primary key default uuid_generate_v4(),
  post_id       uuid references public.posts(id) on delete cascade not null,
  user_id       uuid references public.profiles(id) on delete cascade not null,
  user_name     text not null,
  text_content  text not null check (char_length(trim(text_content)) between 1 and 300),
  created_at    timestamptz not null default now()
);

-- ── TABLA: user_notifications ──
create table if not exists public.user_notifications (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  actor_id      uuid references public.profiles(id) on delete set null,
  actor_name    text not null,
  post_id       uuid references public.posts(id) on delete cascade,
  type          text not null check (type in ('reaction','comment')),
  message       text not null,
  is_read       boolean not null default false,
  created_at    timestamptz not null default now()
);

-- ── TABLA: admin_notifs ──
create table if not exists public.admin_notifs (
  id            uuid primary key default uuid_generate_v4(),
  message       text not null,
  is_read       boolean not null default false,
  created_at    timestamptz not null default now()
);

-- ═══════════════════════════════════
-- ÍNDICES para performance
-- ═══════════════════════════════════
create index if not exists idx_bookings_user on public.bookings(user_id);
create index if not exists idx_bookings_ds on public.bookings(ds);
create index if not exists idx_slot_occ_ds on public.slot_occupancy(ds, slot_idx);
create index if not exists idx_slot_blocks_ds on public.slot_blocks(ds, slot_idx);
create index if not exists idx_payments_user on public.payments(user_id);
create index if not exists idx_scores_board on public.scores(board_id, exercise_idx);
create index if not exists idx_posts_created on public.posts(created_at desc);
create index if not exists idx_post_comments_post on public.post_comments(post_id, created_at asc);
create index if not exists idx_user_notifications_user on public.user_notifications(user_id, created_at desc);
create index if not exists idx_access_log_user on public.access_log(user_id);
create index if not exists idx_door_commands_status on public.door_commands(status, requested_at);
create index if not exists idx_door_commands_user on public.door_commands(user_id, requested_at desc);

-- ═══════════════════════════════════
-- ROW LEVEL SECURITY (RLS)
-- ═══════════════════════════════════
alter table public.profiles enable row level security;
alter table public.bookings enable row level security;
alter table public.slot_occupancy enable row level security;
alter table public.slot_blocks enable row level security;
alter table public.waitlists enable row level security;
alter table public.payments enable row level security;
alter table public.access_log enable row level security;
alter table public.door_commands enable row level security;
alter table public.boards enable row level security;
alter table public.board_assignments enable row level security;
alter table public.scores enable row level security;
alter table public.posts enable row level security;
alter table public.post_reactions enable row level security;
alter table public.post_comments enable row level security;
alter table public.user_notifications enable row level security;
alter table public.admin_notifs enable row level security;

-- ── POLÍTICAS: profiles ──
create policy "Users read own profile"
  on public.profiles for select using (auth.uid() = id);
create policy "Users update own profile"
  on public.profiles for update using (auth.uid() = id);
create policy "Admin reads all profiles"
  on public.profiles for select using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "Admin updates all profiles"
  on public.profiles for update using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "Admin inserts profiles"
  on public.profiles for insert with check (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "Service inserts own profile"
  on public.profiles for insert with check (auth.uid() = id);

-- ── POLÍTICAS: bookings ──
create policy "Users read own bookings"
  on public.bookings for select using (auth.uid() = user_id);
create policy "Users insert own bookings"
  on public.bookings for insert with check (auth.uid() = user_id);
create policy "Users update own bookings"
  on public.bookings for update using (auth.uid() = user_id);
create policy "Admin all bookings"
  on public.bookings for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

-- ── POLÍTICAS: slot_occupancy (todos leen para ver disponibilidad) ──
create policy "All users read slots"
  on public.slot_occupancy for select using (auth.uid() is not null);
create policy "Users insert own slots"
  on public.slot_occupancy for insert with check (auth.uid() = user_id);
create policy "Users delete own slots"
  on public.slot_occupancy for delete using (auth.uid() = user_id);
create policy "Admin all slots"
  on public.slot_occupancy for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "All users read slot blocks"
  on public.slot_blocks for select using (auth.uid() is not null);
create policy "Admin manage slot blocks"
  on public.slot_blocks for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

-- ── POLÍTICAS: waitlists ──
create policy "All read waitlists"
  on public.waitlists for select using (auth.uid() is not null);
create policy "Users manage own waitlist"
  on public.waitlists for all using (auth.uid() = user_id);
create policy "Admin all waitlists"
  on public.waitlists for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

-- ── POLÍTICAS: payments ──
create policy "Users read own payments"
  on public.payments for select using (auth.uid() = user_id);
create policy "Users insert own payments"
  on public.payments for insert with check (auth.uid() = user_id);
create policy "Admin all payments"
  on public.payments for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

-- ── POLÍTICAS: boards y scores (todos los autenticados leen) ──
create policy "Auth users read boards"
  on public.boards for select using (auth.uid() is not null);
create policy "Admin manage boards"
  on public.boards for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "Auth users read assignments"
  on public.board_assignments for select using (auth.uid() is not null);
create policy "Admin manage assignments"
  on public.board_assignments for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "Auth users read scores"
  on public.scores for select using (auth.uid() is not null);
create policy "Users manage own scores"
  on public.scores for all using (auth.uid() = user_id);

-- ── POLÍTICAS: posts ──
create policy "Auth read posts"
  on public.posts for select using (auth.uid() is not null);
create policy "Users insert posts"
  on public.posts for insert with check (auth.uid() = user_id);
create policy "Admin manage posts"
  on public.posts for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "Auth read reactions"
  on public.post_reactions for select using (auth.uid() is not null);
create policy "Users manage own reactions"
  on public.post_reactions for all using (auth.uid() = user_id);
create policy "Auth read comments"
  on public.post_comments for select using (auth.uid() is not null);
create policy "Users insert own comments"
  on public.post_comments for insert with check (auth.uid() = user_id);
create policy "Users delete own comments"
  on public.post_comments for delete using (auth.uid() = user_id);
create policy "Admin delete comments"
  on public.post_comments for delete using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "Users read own notifications"
  on public.user_notifications for select using (auth.uid() = user_id);
create policy "Auth create user notifications"
  on public.user_notifications for insert with check (auth.uid() is not null);
create policy "Users update own notifications"
  on public.user_notifications for update using (auth.uid() = user_id);

-- ── POLÍTICAS: access_log ──
create policy "Users read own log"
  on public.access_log for select using (auth.uid() = user_id);
create policy "Users insert log"
  on public.access_log for insert with check (auth.uid() = user_id);
create policy "Admin all log"
  on public.access_log for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

-- ── POLÍTICAS: door_commands ──
create policy "Users read own door commands"
  on public.door_commands for select using (auth.uid() = user_id);
create policy "Admin all door commands"
  on public.door_commands for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

-- ── POLÍTICAS: admin_notifs ──
create policy "Admin all notifs"
  on public.admin_notifs for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

-- ═══════════════════════════════════
-- FUNCIÓN: auto-crear profile al registrarse
-- ═══════════════════════════════════
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  v_code text;
begin
  -- Generate unique 4-digit access code
  loop
    v_code := lpad(floor(random()*9000+1000)::text, 4, '0');
    exit when not exists(select 1 from public.profiles where access_code = v_code);
  end loop;
  
  insert into public.profiles (id, name, phone, role, access_code)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'phone',
    coalesce(new.raw_user_meta_data->>'role', 'user'),
    v_code
  );
  return new;
end;
$$;

-- Trigger: se ejecuta cuando alguien se registra
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ═══════════════════════════════════
-- ADMIN INICIAL — cambia el email si es diferente
-- ═══════════════════════════════════
-- Después de crear tu cuenta de admin en la app,
-- ejecuta esto para darle permisos:
-- UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid();

select 'Schema creado correctamente ✓' as resultado;
