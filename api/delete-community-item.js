const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function getToken(req) {
  return String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
}

// Reportes pendientes de lo que se va a borrar (migración 128). Se buscan antes del borrado:
// sus referencias son "on delete set null", así que después ya no habría cómo encontrarlos.
// Un reporte de comentario también guarda su post_id, así que borrar una publicación encuentra
// de una vez los de sus comentarios. Sin la 128 no hay reportes que resolver.
async function pendingReportIds(type, itemId) {
  const { data, error } = await supabase
    .from('community_reports')
    .select('id')
    .eq('status', 'pendiente')
    .eq(type === 'comment' ? 'comment_id' : 'post_id', itemId);
  if (error) {
    console.warn('community_reports:', error.message);
    return [];
  }
  return (data || []).map(r => r.id);
}

// Con service role no hay auth.uid(): el trigger de la 128 respeta el resolved_by que llega.
async function resolveReports(ids, adminId) {
  if (!ids.length) return;
  const { error } = await supabase
    .from('community_reports')
    .update({ status: 'resuelto', resolved_by: adminId, resolution_note: 'Contenido eliminado' })
    .in('id', ids);
  if (error) console.warn('community_reports resolve:', error.message);
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
      const reportIds = await pendingReportIds(type, itemId);
      const { error } = await supabase.from('post_comments').delete().eq('id', itemId);
      if (error) throw error;
      await resolveReports(reportIds, profile.id);
      return res.status(200).json({ ok: true, resolved: reportIds.length });
    }

    if (type === 'post') {
      const reportIds = await pendingReportIds(type, itemId);
      await supabase.from('post_comments').delete().eq('post_id', itemId);
      await supabase.from('post_reactions').delete().eq('post_id', itemId);
      await supabase.from('user_notifications').delete().eq('post_id', itemId);
      const { error } = await supabase.from('posts').delete().eq('id', itemId);
      if (error) throw error;
      await resolveReports(reportIds, profile.id);
      return res.status(200).json({ ok: true, resolved: reportIds.length });
    }

    return res.status(400).json({ error: 'Tipo no valido' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'No se pudo eliminar' });
  }
};
