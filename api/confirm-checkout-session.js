const { stripe, supabase, activateMembership } = require('../lib/_fulfillment');

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

    const { sessionId } = req.body || {};
    if (!sessionId) return res.status(400).json({ error: 'Falta session_id' });

    const session = await stripe.checkout.sessions.retrieve(sessionId);
    const ownerId = session.client_reference_id || (session.metadata && session.metadata.user_id);
    if (ownerId !== authData.user.id) return res.status(403).json({ error: 'Pago no pertenece a esta cuenta' });
    if (session.payment_status !== 'paid') return res.status(402).json({ error: 'Pago pendiente' });

    const result = await activateMembership(session);
    return res.status(200).json(result);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'No se pudo confirmar el pago' });
  }
};
