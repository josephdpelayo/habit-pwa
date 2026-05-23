const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function getToken(req) {
  return String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
}

async function tryDelete(table, column, userId) {
  const { error } = await supabase.from(table).delete().eq(column, userId);
  if (error && !/does not exist|schema cache|not found/i.test(error.message || '')) throw error;
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
      .select('id,role,name')
      .eq('id', authData.user.id)
      .single();
    if (profileError) throw profileError;
    if (adminProfile.role !== 'admin') return res.status(403).json({ error: 'Solo admin puede eliminar socios' });

    const userId = String((req.body && req.body.user_id) || '').trim();
    const reason = String((req.body && req.body.reason) || '').trim();
    if (!userId) return res.status(400).json({ error: 'Falta user_id' });
    if (userId === authData.user.id) return res.status(400).json({ error: 'No puedes eliminar tu propia cuenta admin' });
    if (reason.length < 4) return res.status(400).json({ error: 'Agrega un motivo de eliminacion' });

    const { data: userProfile, error: userError } = await supabase
      .from('profiles')
      .select('id,name,role')
      .eq('id', userId)
      .single();
    if (userError) throw userError;
    if (userProfile.role === 'admin') return res.status(403).json({ error: 'No se puede eliminar otro admin desde aqui' });

    await supabase.from('admin_notifs').insert({
      message: 'Socio eliminado: ' + (userProfile.name || 'Usuario') + ' · Motivo: ' + reason + ' · Admin: ' + (adminProfile.name || 'Admin')
    });

    await tryDelete('booking_guest_passes', 'guest_user_id', userId);
    await tryDelete('group_guest_favorites', 'guest_user_id', userId);
    await tryDelete('group_guest_favorites', 'host_user_id', userId);
    await tryDelete('board_assignments', 'user_id', userId);
    await tryDelete('post_reactions', 'user_id', userId);
    await tryDelete('post_comments', 'user_id', userId);
    await tryDelete('user_notifications', 'user_id', userId);
    await tryDelete('door_commands', 'user_id', userId);
    await tryDelete('access_log', 'user_id', userId);

    const { error: deleteError } = await supabase.auth.admin.deleteUser(userId);
    if (deleteError) throw deleteError;

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'No se pudo eliminar el socio' });
  }
};
