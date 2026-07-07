const Stripe = require('stripe');
const { createClient } = require('@supabase/supabase-js');
const { getPlan } = require('./_plans');

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function sendAdminPush(title, body, tag) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return;
  try {
    await fetch(`${url}/functions/v1/send-push`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}` },
      body: JSON.stringify({ target: 'admin', title, body, tag }),
    });
  } catch (e) {
    console.warn('sendAdminPush error:', e.message);
  }
}

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

// Comision publicada de Stripe MX para tarjetas nacionales, usada solo como
// respaldo si balance_transaction aun no esta disponible (poco despues del
// cobro). recalculateStripeFees() la reemplaza por el valor real despues.
const FALLBACK_FEE_RATE = 0.036;
const FALLBACK_FEE_FIXED = 3;

async function getChargeDetails(session) {
  const details = { last4: null, fee: null, net: null };
  try {
    if (!session.payment_intent) return details;
    const pi = await stripe.paymentIntents.retrieve(session.payment_intent, {
      expand: ['latest_charge.balance_transaction'],
    });
    const charge = pi.latest_charge;
    if (charge && charge.payment_method_details && charge.payment_method_details.card) {
      details.last4 = charge.payment_method_details.card.last4;
    }
    const bt = charge && charge.balance_transaction;
    if (bt && typeof bt.fee === 'number') {
      details.fee = bt.fee / 100;
      details.net = bt.net / 100;
    }
  } catch (err) {
    console.warn('Could not read charge details', err.message);
  }
  return details;
}

async function insertPayment(payload) {
  const strip = (source, keys) => {
    const copy = { ...source };
    keys.forEach(key => delete copy[key]);
    return copy;
  };
  const attempts = [
    payload,
    // If Supabase has not run 021_stripe_fees.sql yet, keep activation working.
    strip(payload, ['stripe_fee', 'net_amount']),
    // If Supabase has not run stripe-payments.sql yet, keep activation working.
    strip(payload, ['stripe_fee', 'net_amount', 'payment_method', 'notes', 'created_by']),
    strip(payload, ['stripe_fee', 'net_amount', 'payment_method', 'notes', 'created_by', 'last4']),
    strip(payload, ['stripe_fee', 'net_amount', 'payment_method', 'notes', 'created_by', 'last4', 'currency', 'status']),
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

  const { last4, fee, net } = await getChargeDetails(session);
  const paidAmount = typeof session.amount_total === 'number' ? session.amount_total / 100 : plan.price;
  // balance_transaction a veces no está listo todavía justo al completar el
  // checkout; mientras tanto se guarda un estimado con la tarifa publicada de
  // Stripe MX, y recalculateStripeFees() lo corrige con el valor real después.
  const stripeFee = fee != null ? fee : Math.round((paidAmount * FALLBACK_FEE_RATE + FALLBACK_FEE_FIXED) * 100) / 100;
  const netAmount = net != null ? net : Math.round((paidAmount - stripeFee) * 100) / 100;
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
    stripe_fee: stripeFee,
    net_amount: netAmount,
    stripe_id: session.id,
    payment_method: 'stripe',
    status: 'completed',
    notes: 'Pago con TDC registrado por Stripe',
  });
  await supabase.from('admin_notifs').insert({
    message: `Pago Stripe: ${profile && profile.name ? profile.name : 'Usuario'} · ${plan.name} · $${paidAmount.toLocaleString('es-MX')}`,
  });
  const buyerName = profile && profile.name ? profile.name : 'Usuario';
  sendAdminPush('💳 Compra de plan', `${buyerName} · ${plan.name} · $${paidAmount.toLocaleString('es-MX')}`, 'purchase-plan').catch(() => {});

  return { activated: false, recorded: true, duplicate: false };
}

async function activateMembership(session) {
  const plan = getPlan(session.metadata && session.metadata.plan_id);
  const userId = session.metadata && session.metadata.user_id;
  if (!plan || !userId) throw new Error('Missing payment metadata');
  if (session.payment_status && session.payment_status !== 'paid') throw new Error('Payment is not paid');

  // Record payment FIRST — unique constraint on stripe_id prevents double-activation.
  // If two webhook deliveries race, only one insert wins; the other gets a duplicate error
  // and we return early without touching the profile a second time.
  const recorded = await recordPaidStripeSession(session);
  if (recorded.duplicate) return { activated: true, recorded: false, duplicate: true };

  const expiry = mazEndOfDayIso(plan.days);
  const profileUpdate = {
    plan_id: plan.id,
    plan_type: plan.type,
    credits: plan.credits,
    plan_expiry: expiry,
    plan_is_courtesy: false,
  };
  let { error: profileError } = await supabase.from('profiles').update(profileUpdate).eq('id', userId);
  // 024_plan_courtesy_flag.sql may not be run yet — don't let that block a real purchase.
  if (profileError && /plan_is_courtesy/i.test(profileError.message || '')) {
    delete profileUpdate.plan_is_courtesy;
    ({ error: profileError } = await supabase.from('profiles').update(profileUpdate).eq('id', userId));
  }
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
  sendAdminPush('🛍️ Compra en tienda', `${order.customer_name || 'Cliente'} · $${paidAmount.toLocaleString('es-MX')}`, 'purchase-shop').catch(() => {});

  return { recorded: true, duplicate: false };
}

// Backfill de comisión real para pagos stripe registrados antes de
// 021_stripe_fees.sql (o guardados con el estimado porque balance_transaction
// no estaba listo todavía). Procesa los más viejos sin stripe_fee primero;
// se puede llamar varias veces si hay más de `limit` pendientes.
async function recalculateStripeFees({ limit = 50 } = {}) {
  const { data: rows, error } = await supabase
    .from('payments')
    .select('id,stripe_id,amount')
    .eq('payment_method', 'stripe')
    .not('stripe_id', 'is', null)
    .is('stripe_fee', null)
    .order('created_at', { ascending: true })
    .limit(limit);
  if (error) throw error;

  const summary = { checked: 0, updated: 0, unavailable: 0, errors: 0 };
  for (const row of rows || []) {
    summary.checked += 1;
    try {
      const session = await stripe.checkout.sessions.retrieve(row.stripe_id);
      const { fee, net } = await getChargeDetails(session);
      if (fee == null) { summary.unavailable += 1; continue; }
      const { error: updateError } = await supabase
        .from('payments')
        .update({ stripe_fee: fee, net_amount: net })
        .eq('id', row.id);
      if (updateError) throw updateError;
      summary.updated += 1;
    } catch (err) {
      summary.errors += 1;
      console.error('recalculateStripeFees failed for', row.stripe_id, err.message);
    }
  }

  const { count: remaining } = await supabase
    .from('payments')
    .select('id', { count: 'exact', head: true })
    .eq('payment_method', 'stripe')
    .not('stripe_id', 'is', null)
    .is('stripe_fee', null);

  return { ...summary, remaining: remaining || 0 };
}

module.exports = {
  stripe, supabase, activateMembership, recordPaidStripeSession, fulfillShopOrder,
  recalculateStripeFees,
};
