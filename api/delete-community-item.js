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

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('id,role')
      .eq('id', authData.user.id)
      .single();
    if (profileError) throw profileError;
    if (profile.role !== 'admin') return res.status(403).json({ error: 'Solo admin puede eliminar comunidad' });

    const { type, id } = req.body || {};
    const itemId = String(id || '').trim();
    if (!itemId) return res.status(400).json({ error: 'Falta id' });

    if (type === 'comment') {
      const { error } = await supabase.from('post_comments').delete().eq('id', itemId);
      if (error) throw error;
      return res.status(200).json({ ok: true });
    }

    if (type === 'post') {
      await supabase.from('post_comments').delete().eq('post_id', itemId);
      await supabase.from('post_reactions').delete().eq('post_id', itemId);
      await supabase.from('user_notifications').delete().eq('post_id', itemId);
      const { error } = await supabase.from('posts').delete().eq('id', itemId);
      if (error) throw error;
      return res.status(200).json({ ok: true });
    }

    return res.status(400).json({ error: 'Tipo no valido' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'No se pudo eliminar' });
  }
};
