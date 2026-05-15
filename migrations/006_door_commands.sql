-- HABIT door opening queue
-- Ejecuta esto en Supabase -> SQL Editor -> New query -> Run

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

create index if not exists idx_door_commands_status on public.door_commands(status, requested_at);
create index if not exists idx_door_commands_user on public.door_commands(user_id, requested_at desc);

alter table public.door_commands enable row level security;

drop policy if exists "Users read own door commands" on public.door_commands;
create policy "Users read own door commands"
  on public.door_commands for select using (auth.uid() = user_id);

drop policy if exists "Admin all door commands" on public.door_commands;
create policy "Admin all door commands"
  on public.door_commands for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
