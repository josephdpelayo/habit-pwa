const { createClient } = require('@supabase/supabase-js');
const { getPlan } = require('../lib/_plans');
const { stripe, recordPaidStripeSession } = require('../lib/_fulfillment');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function getToken(req) {
  return String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
}

async function requireAdmin(token, actionLabel) {
  if (!token) {
    const err = new Error('Sesion requerida');
    err.statusCode = 401;
    throw err;
  }

  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData.user) {
    const err = new Error('Sesion invalida');
    err.statusCode = 401;
    throw err;
  }

  const { data: adminProfile, error: profileError } = await supabase
    .from('profiles')
    .select('role,name')
    .eq('id', authData.user.id)
    .single();
  if (profileError) throw profileError;
  if (adminProfile.role !== 'admin') {
    const err = new Error(`Solo admin puede ${actionLabel}`);
    err.statusCode = 403;
    throw err;
  }
  return adminProfile;
}

async function deletePayment(req, res, token) {
  const adminProfile = await requireAdmin(token, 'eliminar pagos');
  const paymentId = String((req.body && req.body.payment_id) || '').trim();
  const reason = String((req.body && req.body.reason) || '').trim();
  if (!paymentId) return res.status(400).json({ error: 'Falta payment_id' });
  if (reason.length < 4) return res.status(400).json({ error: 'Agrega un motivo' });

  const { data: payment, error: payError } = await supabase
    .from('payments')
    .select('id,user_id,plan_name,amount,payment_method')
    .eq('id', paymentId)
    .single();
  if (payError) throw payError;

  let userName = 'Usuario';
  if (payment.user_id) {
    const { data: userProfile } = await supabase
      .from('profiles')
      .select('name')
      .eq('id', payment.user_id)
      .maybeSingle();
    if (userProfile && userProfile.name) userName = userProfile.name;
  }

  const { error: deleteError } = await supabase.from('payments').delete().eq('id', paymentId);
  if (deleteError) throw deleteError;

  await supabase.from('admin_notifs').insert({
    message: 'Pago eliminado: ' + userName
      + ' · ' + payment.plan_name + ' · $' + payment.amount
      + ' · Motivo: ' + reason + ' · Admin: ' + (adminProfile.name || 'Admin')
  });

  return res.status(200).json({ ok: true });
}

async function syncStripePayments(req, res, token) {
  const adminProfile = await requireAdmin(token, 'sincronizar Stripe');
  const limit = Math.max(1, Math.min(100, Number((req.body && req.body.limit) || 50)));
  const sessions = await stripe.checkout.sessions.list({ limit });
  const summary = { checked: 0, recorded: 0, duplicate: 0, skipped: 0, errors: 0 };

  for (const session of sessions.data || []) {
    summary.checked += 1;
    if (session.payment_status !== 'paid') {
      summary.skipped += 1;
      continue;
    }

    const plan = getPlan(session.metadata && session.metadata.plan_id);
    const userId = session.metadata && session.metadata.user_id;
    if (!plan || !userId || String(plan.id).startsWith('test_')) {
      summary.skipped += 1;
      continue;
    }

    try {
      const result = await recordPaidStripeSession(session);
      if (result.duplicate) summary.duplicate += 1;
      else if (result.recorded) summary.recorded += 1;
      else summary.skipped += 1;
    } catch (err) {
      summary.errors += 1;
      console.error('Could not sync Stripe session', session.id, err);
    }
  }

  if (summary.recorded) {
    await supabase.from('admin_notifs').insert({
      message: `Sincronizacion Stripe: ${summary.recorded} cobro(s) agregado(s) a ingresos · Admin: ${adminProfile.name || 'Admin'}`,
    });
  }

  return res.status(200).json({ ok: true, ...summary });
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const token = getToken(req);
    const action = String((req.body && req.body.action) || '').trim();
    if (action === 'delete') return deletePayment(req, res, token);
    return syncStripePayments(req, res, token);
  } catch (err) {
    console.error(err);
    return res.status(err.statusCode || 500).json({ error: err.message || 'No se pudo procesar pagos' });
  }
};
