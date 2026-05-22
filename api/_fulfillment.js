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
  const strip = (source, keys) => {
    const copy = { ...source };
    keys.forEach(key => delete copy[key]);
    return copy;
  };
  const attempts = [
    payload,
    // If Supabase has not run stripe-payments.sql yet, keep activation working.
    strip(payload, ['payment_method', 'notes', 'created_by']),
    strip(payload, ['payment_method', 'notes', 'created_by', 'last4']),
    strip(payload, ['payment_method', 'notes', 'created_by', 'last4', 'currency', 'status']),
  ];

  let lastError = null;
  for (const attempt of attempts) {
    const { error } = await supabase.from('payments').insert(attempt);
    if (!error) return { inserted: true };
    lastError = error;
    if (/duplicate|unique|stripe_id/i.test(error.message || '')) {
      return { inserted: false, duplicate: true };
    }
  }
  throw lastError;
}

async function recordPaidStripeSession(session) {
  const plan = getPlan(session.metadata && session.metadata.plan_id);
  const userId = session.metadata && session.metadata.user_id;
  if (!plan || !userId) throw new Error('Missing payment metadata');
  if (session.payment_status && session.payment_status !== 'paid') throw new Error('Payment is not paid');

  const { data: existing, error: existingError } = await supabase
    .from('payments')
    .select('id')
    .eq('stripe_id', session.id)
    .maybeSingle();
  if (existingError && !/stripe_id/i.test(existingError.message || '')) throw existingError;
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

  return { activated: false, recorded: true, duplicate: false };
}

async function activateMembership(session) {
  const plan = getPlan(session.metadata && session.metadata.plan_id);
  const userId = session.metadata && session.metadata.user_id;
  if (!plan || !userId) throw new Error('Missing payment metadata');
  if (session.payment_status && session.payment_status !== 'paid') throw new Error('Payment is not paid');

  const recorded = await recordPaidStripeSession(session);
  if (recorded.duplicate) return { activated: true, recorded: false, duplicate: true };

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

  return { activated: true, recorded: true, duplicate: false };
}

async function fulfillShopOrder(session) {
  const orderId = session.metadata && session.metadata.order_id;
  if (!orderId) throw new Error('Missing shop order metadata');
  if (session.payment_status && session.payment_status !== 'paid') throw new Error('Payment is not paid');

  const { data: order, error: orderError } = await supabase
    .from('shop_orders')
    .select('id,customer_name,total,payment_status')
    .eq('id', orderId)
    .maybeSingle();
  if (orderError) throw orderError;
  if (!order) throw new Error('Shop order not found');
  if (order.payment_status === 'paid') return { recorded: false, duplicate: true };

  const paidAmount = typeof session.amount_total === 'number' ? session.amount_total / 100 : order.total;
  const nextStatus = 'solicitado';
  const { error: updateError } = await supabase
    .from('shop_orders')
    .update({
      stripe_id: session.id,
      payment_status: 'paid',
      status: nextStatus,
      total: paidAmount,
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId);
  if (updateError) throw updateError;

  const { data: items, error: itemsError } = await supabase
    .from('shop_order_items')
    .select('product_id,quantity')
    .eq('order_id', orderId);
  if (itemsError) throw itemsError;
  for (const item of items || []) {
    const { data: product } = await supabase
      .from('shop_products')
      .select('stock,track_inventory')
      .eq('id', item.product_id)
      .maybeSingle();
    if (product && product.track_inventory !== false) {
      const nextStock = Math.max(0, Number(product.stock || 0) - Number(item.quantity || 0));
      await supabase.from('shop_products').update({
        stock: nextStock,
        updated_at: new Date().toISOString(),
      }).eq('id', item.product_id);
    }
  }

  await supabase.from('admin_notifs').insert({
    message: `Nueva compra tienda: ${order.customer_name || 'Cliente'} · $${paidAmount.toLocaleString('es-MX')} · Pedido solicitado`,
  });

  return { recorded: true, duplicate: false };
}

module.exports = { stripe, supabase, activateMembership, recordPaidStripeSession, fulfillShopOrder };
