const { createClient } = require('@supabase/supabase-js');
const { slotLabel, accessWindow } = require('../lib/_slots');

const LOG_THROTTLE_MS = 60 * 1000;

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function sendAdminPush(title, body, tag) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return;
  try {
    await fetch(`${url}/functions/v1/send-push`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}` },
      body: JSON.stringify({ target: 'admin', title, body, tag }),
    });
  } catch (e) {
    console.warn('sendAdminPush error:', e.message);
  }
}

// La puerta es la señal de que el socio ya llegó, y es cuando decide qué entrena:
// la primera vez que entra con su reserva le llega «¿Qué entrenas hoy?», que abre
// la app en Entrenar (?entrenar=1, ver doorTrainingPrompt en app.html). Solo si
// tiene notificaciones activadas y aún no entrenó hoy; cuesta una consulta en
// paralelo para quien no las tiene, porque el teclado espera esta respuesta.
const TRAINING_PUSH_TIMEOUT_MS = 1200;

async function sendTrainingPush(profile, booking) {
  const [subs, today, last] = await Promise.all([
    supabase.from('push_subscriptions').select('id').eq('user_id', profile.id).limit(1),
    supabase.from('coaching_schedule').select('board_name,status')
      .eq('user_id', profile.id).eq('ds', booking.ds).order('created_at', { ascending: true }).limit(10),
    supabase.from('coaching_schedule').select('board_name')
      .eq('user_id', profile.id).eq('status', 'done').order('completed_at', { ascending: false }).limit(1).maybeSingle(),
  ]);
  if (!subs.data || !subs.data.length) return;
  const rows = today.data || [];
  if (rows.some(r => r.status === 'done' || r.status === 'in_progress')) return;
  const next = rows.find(r => r.status === 'scheduled');
  const lastName = last.data && last.data.board_name;
  const body = next ? `Hoy toca ${next.board_name}. Toca para empezar.`
    : lastName ? `¿Repites ${lastName}? Toca para elegir.`
    : 'Toca para elegir tu rutina y registrar tu entreno.';
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return;
  await fetch(`${url}/functions/v1/send-push`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}` },
    body: JSON.stringify({ target: `user:${profile.id}`, title: '¿Qué entrenas hoy?', body, tag: 'door-train', url: '/app?entrenar=1' }),
  });
}

function withTimeout(promise, ms) {
  return Promise.race([promise, new Promise(resolve => setTimeout(resolve, ms))]);
}

function normalizeCode(value) {
  return String(value || '').replace(/\D/g, '');
}

function getAccessToken(req) {
  const bearer = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
  return bearer || String(req.headers['x-habit-access-key'] || '').trim();
}

async function maybeLogAccess(profile, booking, code, window) {
  const { data: lastLog } = await supabase
    .from('access_log')
    .select('accessed_at')
    .eq('user_id', profile.id)
    .order('accessed_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const lastMs = lastLog && lastLog.accessed_at ? new Date(lastLog.accessed_at).getTime() : 0;
  if (Date.now() - lastMs < LOG_THROTTLE_MS) return false;

  // Primera entrada de esta reserva: el último registro es de antes de que abriera.
  const training = window && lastMs < window.opensMs
    ? withTimeout(sendTrainingPush(profile, booking).catch(e => console.warn('sendTrainingPush error:', e.message)), TRAINING_PUSH_TIMEOUT_MS)
    : null;

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

  sendAdminPush('⌨️ Acceso teclado', `${profile.name} · ${code}# · ${label}`, 'door-keypad').catch(() => {});
  await training;

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

    // Una reserva sigue 'active' para siempre aunque ya haya pasado, y el orden
    // es ascendente: sin este filtro, a un socio con más de 20 reservas en su
    // historial solo le llegaban las 20 más viejas —todas terminadas— y el
    // teclado le decía "la reserva ya termino" teniendo una en curso. Es el
    // mismo arreglo que recibió request-door-open.js en junio (b84f5d3).
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const { data: bookings, error: bookingError } = await supabase
      .from('bookings')
      .select('id,ds,start_idx,slots_used,time_str,status')
      .eq('user_id', profile.id)
      .eq('status', 'active')
      .gte('ds', yesterday)
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
        const logged = await maybeLogAccess(profile, booking, code, window);
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
