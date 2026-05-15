-- Run this in Supabase SQL Editor
-- Creates the push_subscriptions table

create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  role text not null default 'user',   -- 'admin' | 'user'
  subscription jsonb not null,         -- Web Push subscription object
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- One subscription per user (upsert on user_id)
create unique index if not exists push_subscriptions_user_id_idx on push_subscriptions(user_id);

-- RLS: only the owner or service role can read/write
alter table push_subscriptions enable row level security;

create policy "Users can upsert own subscription"
  on push_subscriptions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
