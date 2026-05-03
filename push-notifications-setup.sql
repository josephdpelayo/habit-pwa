-- HABIT push notification subscriptions
-- This creates the storage table. Sending pushes still needs VAPID keys
-- and an Edge Function/server endpoint that calls the Web Push API.

create table if not exists public.push_subscriptions (
  user_id       uuid references public.profiles(id) on delete cascade primary key,
  subscription  jsonb not null,
  user_agent    text,
  updated_at    timestamptz not null default now()
);

alter table public.push_subscriptions enable row level security;

drop policy if exists "Users manage own push subscription" on public.push_subscriptions;
create policy "Users manage own push subscription"
  on public.push_subscriptions for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Admin read push subscriptions" on public.push_subscriptions;
create policy "Admin read push subscriptions"
  on public.push_subscriptions for select using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
