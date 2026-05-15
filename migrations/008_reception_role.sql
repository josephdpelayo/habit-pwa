-- HABIT reception display role
-- Run once in Supabase SQL editor before creating the reception account.

alter table public.profiles
  drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('user','admin','reception'));
