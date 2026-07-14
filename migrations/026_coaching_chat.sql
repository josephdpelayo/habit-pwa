-- ═══════════════════════════════════════════════════════════
-- Mensajes (chat 1-a-1) — beta oculta, mismo flag coaching_beta
-- Conversación siempre cliente <-> gym (un solo admin), nunca
-- cliente <-> cliente. user_id = dueño de la conversación (el cliente).
-- ═══════════════════════════════════════════════════════════

create table if not exists public.coaching_messages (
  id                  uuid primary key default uuid_generate_v4(),
  user_id             uuid references public.profiles(id) on delete cascade not null,
  sender_role         text not null check (sender_role in ('user','admin')),
  sender_id           uuid references public.profiles(id) on delete set null not null,
  body                text,
  media_url           text,
  media_type          text check (media_type in ('image','audio')),
  media_duration_sec  integer,
  created_at          timestamptz not null default now(),
  read_at             timestamptz,
  check (body is not null or media_url is not null)
);
create index if not exists idx_coaching_messages_user_created on public.coaching_messages(user_id, created_at);

alter table public.coaching_messages enable row level security;

-- ── POLÍTICAS: coaching_messages ──
create policy "Users read own conversation"
  on public.coaching_messages for select using (auth.uid() = user_id);

create policy "Users insert own conversation as themselves"
  on public.coaching_messages for insert
  with check (auth.uid() = user_id and sender_role = 'user' and sender_id = auth.uid());

create policy "Users update own conversation"
  on public.coaching_messages for update using (auth.uid() = user_id);

create policy "Admin manage all conversations"
  on public.coaching_messages for all
  using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'))
  with check (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));

-- ── STORAGE: bucket coaching-chat (fotos + notas de voz) ──
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('coaching-chat','coaching-chat', true, 5242880,
  array['image/jpeg','image/jpg','image/png','image/webp','audio/webm','audio/mp4','audio/mpeg','audio/ogg'])
on conflict (id) do nothing;

create policy "Client or admin can upload chat media"
on storage.objects for insert to authenticated
with check (bucket_id='coaching-chat' and (
  (storage.foldername(name))[1] = auth.uid()::text
  or exists(select 1 from public.profiles where id=auth.uid() and role='admin')
));

create policy "Chat media is public read"
on storage.objects for select to public using (bucket_id='coaching-chat');

create policy "Client or admin can delete own-conversation chat media"
on storage.objects for delete to authenticated
using (bucket_id='coaching-chat' and (
  (storage.foldername(name))[1] = auth.uid()::text
  or exists(select 1 from public.profiles where id=auth.uid() and role='admin')
));
