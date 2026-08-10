-- Weekly base plan per coaching client. The template is Monday=0 ... Sunday=6
-- and materializes missing schedule rows when a client/admin opens a week.

create table if not exists public.coaching_week_templates (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  dow         integer not null check (dow between 0 and 6),
  board_id    uuid references public.boards(id) on delete set null,
  board_name  text not null,
  board_color text not null default '#2563eb',
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique(user_id, dow)
);

create index if not exists idx_coaching_week_templates_user
  on public.coaching_week_templates(user_id, dow);

alter table public.coaching_schedule
  add column if not exists generated_from_base boolean not null default false,
  add column if not exists base_template_dow integer check (base_template_dow is null or base_template_dow between 0 and 6);

create unique index if not exists idx_coaching_schedule_base_once
  on public.coaching_schedule(user_id, ds, base_template_dow)
  where base_template_dow is not null;

alter table public.coaching_week_templates enable row level security;

drop policy if exists "Users read own coaching week template" on public.coaching_week_templates;
create policy "Users read own coaching week template"
  on public.coaching_week_templates for select using (auth.uid() = user_id);

drop policy if exists "Admin manage coaching week templates" on public.coaching_week_templates;
create policy "Admin manage coaching week templates"
  on public.coaching_week_templates for all using (
    exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

create or replace function public.ensure_coaching_week_from_template(p_user_id uuid, p_week_start date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_is_admin boolean;
  v_tpl record;
  v_ds date;
begin
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
    into v_is_admin;

  if auth.uid() <> p_user_id and not v_is_admin then
    raise exception 'not authorized';
  end if;

  for v_tpl in
    select dow, board_id, board_name, board_color
    from public.coaching_week_templates
    where user_id = p_user_id
  loop
    v_ds := p_week_start + v_tpl.dow;

    insert into public.coaching_schedule (
      user_id, board_id, board_name, board_color, ds,
      status, created_by, generated_from_base, base_template_dow
    )
    select
      p_user_id, v_tpl.board_id, v_tpl.board_name, v_tpl.board_color, v_ds,
      'scheduled', auth.uid(), true, v_tpl.dow
    where not exists (
      select 1
      from public.coaching_schedule s
      where s.user_id = p_user_id
        and s.ds = v_ds
        and s.base_template_dow = v_tpl.dow
    )
    and not exists (
      select 1
      from public.coaching_schedule s
      where s.user_id = p_user_id
        and s.ds = v_ds
        and s.board_id = v_tpl.board_id
        and s.status in ('scheduled','in_progress','done')
    );
  end loop;
end;
$$;
