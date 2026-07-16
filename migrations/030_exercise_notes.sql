-- Notas de texto libre que el CLIENTE agrega a un ejercicio (a diferencia
-- de la nota que el admin escribe al crear el ejercicio en el pizarrón).
-- Una nota por usuario+ejercicio, editable en cualquier momento — no es
-- por sesión, es persistente ("me costó la última serie", etc).

create table if not exists public.exercise_notes (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  ex_key      text not null,
  note        text not null,
  updated_at  timestamptz not null default now(),
  unique(user_id, ex_key)
);

alter table public.exercise_notes enable row level security;

create policy "Users manage own exercise notes"
  on public.exercise_notes for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Admin view all exercise notes"
  on public.exercise_notes for select
  using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));
