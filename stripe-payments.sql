create unique index if not exists idx_payments_stripe_id
  on public.payments(stripe_id)
  where stripe_id is not null;

alter table public.payments
  add column if not exists payment_method text not null default 'stripe',
  add column if not exists notes text,
  add column if not exists created_by uuid references public.profiles(id);
