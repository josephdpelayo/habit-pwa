const Stripe = require('stripe');
const { createClient } = require('@supabase/supabase-js');
const { getPlan } = require('./_plans');

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function getBaseUrl(req) {
  if (process.env.PUBLIC_APP_URL) return process.env.PUBLIC_APP_URL.replace(/\/$/, '');
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const proto = req.headers['x-forwarded-proto'] || 'https';
  return `${proto}://${host}`;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (!token) return res.status(401).json({ error: 'Sesion requerida' });

    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return res.status(401).json({ error: 'Sesion invalida' });

    const { planId } = req.body || {};
    const plan = getPlan(planId);
    if (!plan) return res.status(400).json({ error: 'Plan no encontrado' });
    if (plan.allowedEmail && String(authData.user.email || '').toLowerCase() !== plan.allowedEmail) {
      return res.status(403).json({ error: 'Plan no disponible para esta cuenta' });
    }

    const baseUrl = getBaseUrl(req);
    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: ['card'],
      customer_email: authData.user.email || undefined,
      client_reference_id: authData.user.id,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: 'mxn',
            unit_amount: Math.round(plan.price * 100),
            product_data: {
              name: `HABIT - ${plan.name}`,
              description: `${plan.credits >= 999 ? 'Ilimitado' : `${plan.credits} visitas`}${plan.days ? ` · ${plan.days} dias` : ''}`,
            },
          },
        },
      ],
      metadata: {
        user_id: authData.user.id,
        plan_id: plan.id,
      },
      success_url: `${baseUrl}/app.html?stripe_success=1&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${baseUrl}/app.html?stripe_cancel=1`,
    });

    return res.status(200).json({ url: session.url });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'No se pudo crear el pago' });
  }
};
