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
      .select('role')
      .eq('id', authData.user.id)
      .single();
    if (profileError) throw profileError;
    if (adminProfile.role !== 'admin') return res.status(403).json({ error: 'Solo admin puede ver correos' });

    const userId = String((req.body && req.body.user_id) || '').trim();
    if (!userId) return res.status(400).json({ error: 'Falta user_id' });

    const { data, error } = await supabase.auth.admin.getUserById(userId);
    if (error) throw error;

    return res.status(200).json({ email: data.user && data.user.email ? data.user.email : '' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'No se pudo obtener el correo' });
  }
};
