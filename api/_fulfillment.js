const Stripe = require('stripe');
const { createClient } = require('@supabase/supabase-js');
const { getPlan } = require('./_plans');

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function mazEndOfDayIso(days) {
  if (!days) return null;
  const now = new Date();
  const maz = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Mazatlan',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const values = Object.fromEntries(maz.filter(p => p.type !== 'literal').map(p => [p.type, Number(p.value)]));
  const end = new Date(Date.UTC(values.year, values.month - 1, values.day + days, 23 + 7, 59, 59));
  return end.toISOString();
}

async function getLast4(session) {
  try {
    if (!session.payment_intent) return null;
    const pi = await stripe.paymentIntents.retrieve(session.payment_intent, { expand: ['latest_charge'] });
    return pi.latest_charge && pi.latest_charge.payment_method_details && pi.latest_charge.payment_method_details.card
      ? pi.latest_charge.payment_method_details.card.last4
      : null;
  } catch (err) {
    console.warn('Could not read card last4', err.message);
    return null;
  }
}

async function insertPayment(payload) {
  const { error } = await supabase.from('payments').insert(payload);
  if (!error) return;

  // If Supabase has not run stripe-payments.sql yet, keep activation working.
  const minimal = { ...payload };
  delete minimal.payment_method;
  delete minimal.notes;
  delete minimal.created_by;
  const { error: retryError } = await supabase.from('payments').insert(minimal);
  if (retryError) throw retryError;
}

async function activateMembership(session) {
  const plan = getPlan(session.metadata && session.metadata.plan_id);
  const userId = session.metadata && session.metadata.user_id;
  if (!plan || !userId) throw new Error('Missing payment metadata');
  if (session.payment_status && session.payment_status !== 'paid') throw new Error('Payment is not paid');

  const expiry = mazEndOfDayIso(plan.days);
  const { error: profileError } = await supabase
    .from('profiles')
    .update({
      plan_id: plan.id,
      plan_type: plan.type,
      credits: plan.credits,
      plan_expiry: expiry,
    })
    .eq('id', userId);
  if (profileError) throw profileError;

  const { data: existing } = await supabase
    .from('payments')
    .select('id')
    .eq('stripe_id', session.id)
    .maybeSingle();
  if (existing) return { activated: true, recorded: false, duplicate: true };

  const last4 = await getLast4(session);
  const paidAmount = typeof session.amount_total === 'number' ? session.amount_total / 100 : plan.price;
  const { data: profile } = await supabase
    .from('profiles')
    .select('name')
    .eq('id', userId)
    .maybeSingle();
  await insertPayment({
    user_id: userId,
    plan_id: plan.id,
    plan_name: plan.name,
    plan_type: plan.type,
    amount: paidAmount,
    currency: 'MXN',
    last4,
    stripe_id: session.id,
    payment_method: 'stripe',
    status: 'completed',
    notes: 'Pago con TDC registrado por Stripe',
  });
  await supabase.from('admin_notifs').insert({
    message: `Pago Stripe: ${profile && profile.name ? profile.name : 'Usuario'} · ${plan.name} · $${paidAmount.toLocaleString('es-MX')}`,
  });

  return { activated: true, recorded: true, duplicate: false };
}

module.exports = { stripe, supabase, activateMembership };
