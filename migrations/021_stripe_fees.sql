-- Trackea la comision real de Stripe por pago, para poder reportar ingreso neto.
alter table public.payments
  add column if not exists stripe_fee numeric,
  add column if not exists net_amount numeric;

comment on column public.payments.stripe_fee is 'Comision cobrada por Stripe en MXN, tomada de balance_transaction.fee (solo pagos stripe)';
comment on column public.payments.net_amount is 'amount - stripe_fee. Para pagos no-stripe (cash/courtesy/adjustment) es igual a amount.';
