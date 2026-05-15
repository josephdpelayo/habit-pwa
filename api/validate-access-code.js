const { createClient } = require('@supabase/supabase-js');
const { slotLabel, accessWindow } = require('./_slots');

const LOG_THROTTLE_MS = 60 * 1000;

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function normalizeCode(value) {
  return String(value || '').replace(/\D/g, '');
}

function getAccessToken(req) {
  const bearer = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
  return bearer || String(req.headers['x-habit-access-key'] || '').trim();
}

async function maybeLogAccess(profile, booking, code) {
  const { data: lastLog } = await supabase
    .from('access_log')
    .select('accessed_at')
    .eq('user_id', profile.id)
    .order('accessed_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const lastMs = lastLog && lastLog.accessed_at ? new Date(lastLog.accessed_at).getTime() : 0;
  if (Date.now() - lastMs < LOG_THROTTLE_MS) return false;

  const label = slotLabel(booking);
  await supabase.from('access_log').insert({
    user_id: profile.id,
    user_name: profile.name,
    access_code: code,
    slot_str: label,
    accessed_at: new Date().toISOString(),
  });

  await supabase.from('admin_notifs').insert({
    message: `Acceso por teclado: ${profile.name} · codigo ${code}# · ${label}`,
  });

  return true;
}

function deny(res, reason, message, extra = {}) {
  return res.status(200).json({ ok: true, allow: false, reason, message, ...extra });
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const expectedSecret = process.env.ACCESS_API_SECRET;
  if (!expectedSecret) return res.status(500).json({ error: 'ACCESS_API_SECRET no configurado' });
  if (getAccessToken(req) !== expectedSecret) return res.status(401).json({ error: 'No autorizado' });

  try {
    const code = normalizeCode(req.body && req.body.code);
    if (code.length !== 4) {
      return deny(res, 'invalid_format', 'Ingresa 4 digitos y despues #.');
    }

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('id,name,access_code')
      .eq('access_code', code)
      .maybeSingle();

    if (profileError) throw profileError;
    if (!profile) return deny(res, 'not_found', 'Codigo no encontrado.');

    const { data: bookings, error: bookingError } = await supabase
      .from('bookings')
      .select('id,ds,start_idx,slots_used,time_str,status')
      .eq('user_id', profile.id)
      .eq('status', 'active')
      .order('ds', { ascending: true })
      .order('start_idx', { ascending: true })
      .limit(20);

    if (bookingError) throw bookingError;

    const nowMs = Date.now();
    let nextBooking = null;
    let lastFinished = null;

    for (const booking of bookings || []) {
      const window = accessWindow(booking);
      if (nowMs >= window.opensMs && nowMs <= window.closesMs) {
        const logged = await maybeLogAccess(profile, booking, code);
        return res.status(200).json({
          ok: true,
          allow: true,
          user_id: profile.id,
          user_name: profile.name,
          code: `${code}#`,
          slot: slotLabel(booking),
          opens_at: new Date(window.opensMs).toISOString(),
          closes_at: new Date(window.closesMs).toISOString(),
          logged,
          message: 'Acceso autorizado.',
        });
      }
      if (nowMs < window.opensMs && (!nextBooking || window.opensMs < nextBooking.window.opensMs)) {
        nextBooking = { booking, window };
      }
      if (nowMs > window.closesMs) lastFinished = { booking, window };
    }

    if (nextBooking) {
      return deny(res, 'too_early', 'Codigo correcto, pero la puerta se activa 10 minutos antes de la reserva.', {
        user_name: profile.name,
        slot: slotLabel(nextBooking.booking),
        opens_at: new Date(nextBooking.window.opensMs).toISOString(),
      });
    }

    if (lastFinished) {
      return deny(res, 'expired', 'Codigo correcto, pero la reserva ya termino.', {
        user_name: profile.name,
        slot: slotLabel(lastFinished.booking),
        closed_at: new Date(lastFinished.window.closesMs).toISOString(),
      });
    }

    return deny(res, 'no_booking', 'Codigo correcto, pero no hay una reserva activa.');
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'No se pudo validar el codigo' });
  }
};
