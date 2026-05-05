const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

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
    if (adminProfile.role !== 'admin') return res.status(403).json({ error: 'Solo admin puede eliminar pagos' });

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
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: err.message || 'No se pudo eliminar el pago' });
  }
};
