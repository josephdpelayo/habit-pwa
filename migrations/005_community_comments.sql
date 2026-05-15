-- HABIT community comments and user notifications
-- Run this once in Supabase SQL editor for an existing database.

create table if not exists public.post_comments (
  id            uuid primary key default uuid_generate_v4(),
  post_id       uuid references public.posts(id) on delete cascade not null,
  user_id       uuid references public.profiles(id) on delete cascade not null,
  user_name     text not null,
  text_content  text not null check (char_length(trim(text_content)) between 1 and 300),
  created_at    timestamptz not null default now()
);

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

create index if not exists idx_post_comments_post on public.post_comments(post_id, created_at asc);
create index if not exists idx_user_notifications_user on public.user_notifications(user_id, created_at desc);

alter table public.post_comments enable row level security;
alter table public.user_notifications enable row level security;

drop policy if exists "Auth read comments" on public.post_comments;
create policy "Auth read comments"
  on public.post_comments for select using (auth.uid() is not null);

drop policy if exists "Users insert own comments" on public.post_comments;
create policy "Users insert own comments"
  on public.post_comments for insert with check (auth.uid() = user_id);

drop policy if exists "Users delete own comments" on public.post_comments;
create policy "Users delete own comments"
  on public.post_comments for delete using (auth.uid() = user_id);

drop policy if exists "Admin delete comments" on public.post_comments;
create policy "Admin delete comments"
  on public.post_comments for delete using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

drop policy if exists "Users read own notifications" on public.user_notifications;
create policy "Users read own notifications"
  on public.user_notifications for select using (auth.uid() = user_id);

drop policy if exists "Auth create user notifications" on public.user_notifications;
create policy "Auth create user notifications"
  on public.user_notifications for insert with check (auth.uid() is not null);

drop policy if exists "Users update own notifications" on public.user_notifications;
create policy "Users update own notifications"
  on public.user_notifications for update using (auth.uid() = user_id);
