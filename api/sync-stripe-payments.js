const { getPlan } = require('./_plans');
const { stripe, supabase, recordPaidStripeSession } = require('./_fulfillment');

function getToken(req) {
  return String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const token = getToken(req);
    if (!token) return res.status(401).json({ error: 'Sesion requerida' });

    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return res.status(401).json({ error: 'Sesion invalida' });

    const { data: adminProfile, error: profileError } = await supabase
      .from('profiles')
      .select('role,name')
      .eq('id', authData.user.id)
      .single();
    if (profileError) throw profileError;
    if (adminProfile.role !== 'admin') return res.status(403).json({ error: 'Solo admin puede sincronizar Stripe' });

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
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: err.message || 'No se pudo sincronizar Stripe' });
  }
};
