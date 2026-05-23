const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function getToken(req) {
  return String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
}

module.exports = async function handler(req, res) {
  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const token = getToken(req);
    if (!token) return res.status(401).json({ error: 'Sesion requerida' });

    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return res.status(401).json({ error: 'Sesion invalida' });

    const guestId = authData.user.id;
    const yday = new Date(Date.now() - 36 * 60 * 60 * 1000).toISOString().slice(0, 10);

    const { data: passes, error: passError } = await supabase
      .from('booking_guest_passes')
      .select('booking_id,host_user_id,status')
      .eq('guest_user_id', guestId)
      .eq('status', 'active')
      .limit(30);
    if (passError) throw passError;

    const passRows = passes || [];
    const bookingIds = [...new Set(passRows.map(pass => pass.booking_id).filter(Boolean))];
    if (!bookingIds.length) return res.status(200).json({ bookings: [] });

    const hostIds = [...new Set(passRows.map(pass => pass.host_user_id).filter(Boolean))];
    const [{ data: bookings, error: bookingError }, { data: hosts, error: hostError }] = await Promise.all([
      supabase.from('bookings').select('*').in('id', bookingIds).eq('status', 'active').gte('ds', yday),
      hostIds.length ? supabase.from('profiles').select('id,name').in('id', hostIds) : Promise.resolve({ data: [], error: null }),
    ]);
    if (bookingError) throw bookingError;
    if (hostError) throw hostError;

    const passByBooking = new Map(passRows.map(pass => [pass.booking_id, pass]));
    const hostById = new Map((hosts || []).map(host => [host.id, host.name || 'Un socio']));
    const rows = (bookings || []).filter(booking => booking.is_group).map(booking => {
      const pass = passByBooking.get(booking.id) || {};
      return {
        id: booking.id,
        ds: booking.ds,
        start_idx: booking.start_idx,
        slots_used: booking.slots_used || 3,
        is_group: booking.is_group,
        grupal_spots: booking.grupal_spots,
        time_str: booking.time_str,
        dur_min: booking.dur_min || 90,
        host_user_id: pass.host_user_id,
        host_name: hostById.get(pass.host_user_id) || 'Un socio',
      };
    });

    return res.status(200).json({ bookings: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'No se pudo cargar pase de invitado' });
  }
};
