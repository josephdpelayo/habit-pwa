-- HABIT admin user and manual slot blocking
-- Run this once in Supabase SQL editor for the existing database.

update public.profiles
set role = 'admin'
where id = (
  select id
  from auth.users
  where lower(email) = 'habit.mzt@gmail.com'
  limit 1
);

create table if not exists public.slot_blocks (
  ds            date not null,
  slot_idx      integer not null check (slot_idx >= 0 and slot_idx < 48),
  spots         integer not null default 1 check (spots between 1 and 4),
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  primary key (ds, slot_idx)
);

create index if not exists idx_slot_blocks_ds on public.slot_blocks(ds, slot_idx);

alter table public.slot_blocks enable row level security;

drop policy if exists "All users read slot blocks" on public.slot_blocks;
create policy "All users read slot blocks"
  on public.slot_blocks for select using (auth.uid() is not null);

drop policy if exists "Admin manage slot blocks" on public.slot_blocks;
create policy "Admin manage slot blocks"
  on public.slot_blocks for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
