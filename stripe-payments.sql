create unique index if not exists idx_payments_stripe_id
  on public.payments(stripe_id)
  where stripe_id is not null;
