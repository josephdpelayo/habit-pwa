const Stripe = require('stripe');
const { createClient } = require('@supabase/supabase-js');
const { getPlan } = require('./_plans');

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function readRawBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(Buffer.from(chunk)));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
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

async function activateMembership(session) {
  const plan = getPlan(session.metadata && session.metadata.plan_id);
  const userId = session.metadata && session.metadata.user_id;
  if (!plan || !userId) throw new Error('Missing payment metadata');

  const { data: existing } = await supabase
    .from('payments')
    .select('id')
    .eq('stripe_id', session.id)
    .maybeSingle();
  if (existing) return;

  const expiry = mazEndOfDayIso(plan.days);
  const last4 = await getLast4(session);

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

  const { error: paymentError } = await supabase.from('payments').insert({
    user_id: userId,
    plan_id: plan.id,
    plan_name: plan.name,
    plan_type: plan.type,
    amount: plan.price,
    currency: 'MXN',
    last4,
    stripe_id: session.id,
    payment_method: 'stripe',
    status: 'completed',
  });
  if (paymentError) throw paymentError;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).send('Method not allowed');
  }

  const signature = req.headers['stripe-signature'];
  const rawBody = await readRawBody(req);

  let event;
  try {
    event = stripe.webhooks.constructEvent(rawBody, signature, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('Webhook signature error:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  try {
    if (event.type === 'checkout.session.completed') {
      await activateMembership(event.data.object);
    }
    return res.status(200).json({ received: true });
  } catch (err) {
    console.error(err);
    return res.status(500).send('Webhook handler failed');
  }
};

module.exports.config = {
  api: {
    bodyParser: false,
  },
};
