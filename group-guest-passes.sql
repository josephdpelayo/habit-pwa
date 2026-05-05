-- Grupo de invitados para membresias grupales
-- Corre este archivo en Supabase SQL Editor.

create extension if not exists "uuid-ossp";

create table if not exists public.group_guest_favorites (
  host_user_id  uuid references public.profiles(id) on delete cascade not null,
  guest_user_id uuid references public.profiles(id) on delete cascade not null,
  created_at    timestamptz not null default now(),
  primary key (host_user_id, guest_user_id),
  check (host_user_id <> guest_user_id)
);

create table if not exists public.booking_guest_passes (
  id            uuid primary key default uuid_generate_v4(),
  booking_id    uuid references public.bookings(id) on delete cascade not null,
  host_user_id  uuid references public.profiles(id) on delete cascade not null,
  guest_user_id uuid references public.profiles(id) on delete cascade not null,
  status        text not null default 'active' check (status in ('active','revoked')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (booking_id, guest_user_id),
  check (host_user_id <> guest_user_id)
);

create index if not exists idx_group_guest_favorites_guest
  on public.group_guest_favorites(guest_user_id);
create index if not exists idx_booking_guest_passes_guest
  on public.booking_guest_passes(guest_user_id, status);
create index if not exists idx_booking_guest_passes_booking
  on public.booking_guest_passes(booking_id, status);

alter table public.group_guest_favorites enable row level security;
alter table public.booking_guest_passes enable row level security;

drop policy if exists "Group hosts read own favorites" on public.group_guest_favorites;
drop policy if exists "Group hosts insert own favorites" on public.group_guest_favorites;
drop policy if exists "Group hosts delete own favorites" on public.group_guest_favorites;
drop policy if exists "Guests read favorite links" on public.group_guest_favorites;
drop policy if exists "Admin all group guest favorites" on public.group_guest_favorites;

create policy "Group hosts read own favorites"
  on public.group_guest_favorites for select
  using (auth.uid() = host_user_id);
create policy "Group hosts insert own favorites"
  on public.group_guest_favorites for insert
  with check (auth.uid() = host_user_id);
create policy "Group hosts delete own favorites"
  on public.group_guest_favorites for delete
  using (auth.uid() = host_user_id);
create policy "Guests read favorite links"
  on public.group_guest_favorites for select
  using (auth.uid() = guest_user_id);
create policy "Admin all group guest favorites"
  on public.group_guest_favorites for all
  using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'))
  with check (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));

drop policy if exists "Hosts and guests read booking passes" on public.booking_guest_passes;
drop policy if exists "Hosts insert booking passes" on public.booking_guest_passes;
drop policy if exists "Hosts update booking passes" on public.booking_guest_passes;
drop policy if exists "Hosts delete booking passes" on public.booking_guest_passes;
drop policy if exists "Admin all booking guest passes" on public.booking_guest_passes;

create policy "Hosts and guests read booking passes"
  on public.booking_guest_passes for select
  using (
    auth.uid() = host_user_id
    or auth.uid() = guest_user_id
    or exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
create policy "Hosts insert booking passes"
  on public.booking_guest_passes for insert
  with check (
    auth.uid() = host_user_id
    and exists(
      select 1 from public.bookings
      where id = booking_id
        and user_id = auth.uid()
        and is_group = true
        and status = 'active'
    )
  );
create policy "Hosts update booking passes"
  on public.booking_guest_passes for update
  using (auth.uid() = host_user_id)
  with check (auth.uid() = host_user_id);
create policy "Hosts delete booking passes"
  on public.booking_guest_passes for delete
  using (auth.uid() = host_user_id);
create policy "Admin all booking guest passes"
  on public.booking_guest_passes for all
  using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'))
  with check (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));

-- Permite que un invitado lea la reserva grupal del titular.
-- Sin esto el pase existe, pero la app del invitado no puede calcular su ventana de puerta.
drop policy if exists "Guests read invited group bookings" on public.bookings;
create policy "Guests read invited group bookings"
  on public.bookings for select
  using (
    exists(
      select 1
      from public.booking_guest_passes p
      where p.booking_id = public.bookings.id
        and p.guest_user_id = auth.uid()
        and p.status = 'active'
    )
  );
