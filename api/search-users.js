const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function getToken(req) {
  return String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
}

function norm(value) {
  return String(value || '').trim().toLowerCase();
}

module.exports = async function handler(req, res) {
  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const token = getToken(req);
    if (!token) return res.status(401).json({ error: 'Sesion requerida' });

    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return res.status(401).json({ error: 'Sesion invalida' });

    const q = norm(req.body && req.body.q);
    if (q.length < 2) return res.status(200).json({ users: [] });

    const { data: profiles, error: profileError } = await supabase
      .from('profiles')
      .select('id,name,role')
      .neq('role', 'admin')
      .limit(1000);
    if (profileError) throw profileError;

    const { data: usersData, error: usersError } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (usersError) throw usersError;

    const emailById = new Map((usersData.users || []).map(user => [user.id, user.email || '']));
    const users = (profiles || [])
      .filter(profile => profile.id !== authData.user.id)
      .map(profile => ({
        id: profile.id,
        name: profile.name || 'Usuario',
        email: emailById.get(profile.id) || '',
      }))
      .filter(user => norm(user.name).includes(q) || norm(user.email).includes(q))
      .slice(0, 12);

    return res.status(200).json({ users });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: err.message || 'No se pudo buscar usuarios' });
  }
};
