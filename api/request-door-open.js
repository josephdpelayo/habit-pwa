const { createClient } = require('@supabase/supabase-js');

const MAZ_UTC_OFFSET_H = 7;
const SLOT_DUR = 30;
const BEFORE_MIN = 10;
const DEFAULT_RADIUS_M = 120;
const DEFAULT_MAX_ACCURACY_M = 150;
const SHELLY_DEFAULT_TURN = 'off';
const SHELLY_DEFAULT_RELEASE_SECONDS = 5;
const LOCATION_EXEMPT_EMAILS = ['josephdpelayo@gmail.com'];

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function parseDS(ds) {
  const [y, m, d] = String(ds || '').split('-').map(Number);
  return { y, m, d };
}

function slotMs(ds, slotIdx) {
  const { y, m, d } = parseDS(ds);
  return Date.UTC(y, m - 1, d, MAZ_UTC_OFFSET_H, 0, 0) + Number(slotIdx || 0) * SLOT_DUR * 60000;
}

function fmtSlot(idx) {
  const totalMin = Number(idx || 0) * SLOT_DUR;
  const h = String(Math.floor(totalMin / 60)).padStart(2, '0');
  const m = String(totalMin % 60).padStart(2, '0');
  return `${h}:${m}`;
}

function slotLabel(booking) {
  const slotsUsed = Number(booking.slots_used || 3);
  return booking.time_str || `${fmtSlot(booking.start_idx)} - ${fmtSlot(Number(booking.start_idx) + slotsUsed)}`;
}

function accessWindow(booking) {
  const slotsUsed = Number(booking.slots_used || 3);
  const startMs = slotMs(booking.ds, booking.start_idx);
  return {
    opensMs: startMs - BEFORE_MIN * 60000,
    closesMs: startMs + slotsUsed * SLOT_DUR * 60000,
  };
}

function distanceMeters(aLat, aLng, bLat, bLng) {
  const toRad = deg => (deg * Math.PI) / 180;
  const r = 6371000;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const s1 = Math.sin(dLat / 2);
  const s2 = Math.sin(dLng / 2);
  const x = s1 * s1 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * s2 * s2;
  return 2 * r * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

function getGymLocation() {
  const lat = Number(process.env.GYM_LAT);
  const lng = Number(process.env.GYM_LNG);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const radius = Number(process.env.GYM_RADIUS_METERS || DEFAULT_RADIUS_M);
  const maxAccuracy = Number(process.env.GYM_MAX_ACCURACY_METERS || DEFAULT_MAX_ACCURACY_M);
  return {
    lat,
    lng,
    radius: Number.isFinite(radius) && radius > 0 ? radius : DEFAULT_RADIUS_M,
    maxAccuracy: Number.isFinite(maxAccuracy) && maxAccuracy > 0 ? maxAccuracy : DEFAULT_MAX_ACCURACY_M,
  };
}

function deny(res, status, reason, message, extra = {}) {
  return res.status(status).json({ ok: false, allow: false, reason, message, ...extra });
}

function getShellyConfig() {
  const server = String(process.env.SHELLY_SERVER_URL || '').replace(/\/$/, '');
  const authKey = String(process.env.SHELLY_AUTH_KEY || '');
  const deviceId = String(process.env.SHELLY_DEVICE_ID || '');
  const channel = String(process.env.SHELLY_CHANNEL || '0');
  const turn = String(process.env.SHELLY_TURN || SHELLY_DEFAULT_TURN).toLowerCase();
  // Keep the magnetic lock released for exactly 5 seconds before relocking.
  const releaseSeconds = SHELLY_DEFAULT_RELEASE_SECONDS;
  if (!server || !authKey || !deviceId) return null;
  const normalizedTurn = turn === 'on' ? 'on' : 'off';
  const relockTurn = String(process.env.SHELLY_RELOCK_TURN || (normalizedTurn === 'on' ? 'off' : 'on')).toLowerCase();
  return {
    server,
    authKey,
    deviceId,
    channel,
    turn: normalizedTurn,
    relockTurn: relockTurn === 'off' ? 'off' : 'on',
    releaseSeconds,
  };
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function sendShellyRelay(cfg, turn) {
  const body = new URLSearchParams({
    id: cfg.deviceId,
    auth_key: cfg.authKey,
    channel: cfg.channel,
    turn,
  });

  const response = await fetch(`${cfg.server}/device/relay/control`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const text = await response.text();
  let payload = null;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch (_) {
    payload = text;
  }

  if (!response.ok || (payload && payload.isok === false)) {
    const message = payload && payload.errors ? JSON.stringify(payload.errors) : text || response.statusText;
    throw new Error(`Shelly no abrio: ${message}`);
  }
  return payload;
}

async function triggerShellyDoor() {
  const cfg = getShellyConfig();
  if (!cfg) throw new Error('Shelly no configurado en Vercel. Revisa SHELLY_SERVER_URL, SHELLY_AUTH_KEY y SHELLY_DEVICE_ID en Production.');

  const payload = await sendShellyRelay(cfg, cfg.turn);
  if (cfg.releaseSeconds > 0) {
    await sleep(cfg.releaseSeconds * 1000);
    await sendShellyRelay(cfg, cfg.relockTurn);
  }

  return { configured: true, opened: true, payload, release_seconds: cfg.releaseSeconds };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
    if (!token) return res.status(401).json({ error: 'Sesion requerida' });

    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return res.status(401).json({ error: 'Sesion invalida' });
    const locationExempt = LOCATION_EXEMPT_EMAILS.includes(String(authData.user.email || '').toLowerCase());

    const gym = getGymLocation();
    if (!gym && !locationExempt) {
      return deny(res, 500, 'gym_location_missing', 'Falta configurar GYM_LAT y GYM_LNG en Vercel.');
    }

    const lat = Number(req.body && req.body.lat);
    const lng = Number(req.body && req.body.lng);
    const accuracy = Number(req.body && req.body.accuracy);
    if (!locationExempt && (!Number.isFinite(lat) || !Number.isFinite(lng))) {
      return deny(res, 400, 'location_missing', 'No pudimos leer tu ubicacion.');
    }
    if (!locationExempt && Number.isFinite(accuracy) && accuracy > gym.maxAccuracy) {
      return deny(res, 403, 'location_not_precise', 'Tu ubicacion no es suficientemente precisa. Acercate a la puerta e intenta de nuevo.', {
        accuracy_m: Math.round(accuracy),
        max_accuracy_m: gym.maxAccuracy,
      });
    }

    const distance = locationExempt ? null : Math.round(distanceMeters(lat, lng, gym.lat, gym.lng));
    if (!locationExempt && distance > gym.radius) {
      return deny(res, 403, 'too_far', `Estas a ${distance} m. Acercate a la puerta para abrir.`, {
        distance_m: distance,
        radius_m: gym.radius,
      });
    }

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('id,name,access_code')
      .eq('id', authData.user.id)
      .single();
    if (profileError) throw profileError;

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
    let activeBooking = null;
    let activeWindow = null;
    for (const booking of bookings || []) {
      const window = accessWindow(booking);
      if (nowMs >= window.opensMs && nowMs <= window.closesMs) {
        activeBooking = booking;
        activeWindow = window;
        break;
      }
    }

    if (!activeBooking) {
      return deny(res, 403, 'no_active_access', 'Tu acceso se activa 10 minutos antes de tu reserva.');
    }

    const label = slotLabel(activeBooking);
    const { data: command, error: commandError } = await supabase
      .from('door_commands')
      .insert({
        user_id: profile.id,
        user_name: profile.name,
        booking_id: activeBooking.id,
        access_code: profile.access_code,
        slot_str: label,
        status: 'pending',
        lat: Number.isFinite(lat) ? lat : null,
        lng: Number.isFinite(lng) ? lng : null,
        accuracy_m: Number.isFinite(accuracy) ? Math.round(accuracy) : null,
        distance_m: distance,
        requested_at: new Date().toISOString(),
      })
      .select('id')
      .single();

    if (commandError) throw commandError;

    let shellyResult = { configured: false, opened: false };
    try {
      shellyResult = await triggerShellyDoor();
      await supabase
        .from('door_commands')
        .update({
          status: shellyResult.opened ? 'opened' : 'pending',
          processed_at: shellyResult.opened ? new Date().toISOString() : null,
          processed_by: shellyResult.opened ? 'shelly_cloud' : null,
        })
        .eq('id', command.id);
    } catch (shellyError) {
      await supabase
        .from('door_commands')
        .update({
          status: 'failed',
          processed_at: new Date().toISOString(),
          processed_by: 'shelly_cloud',
          error_message: shellyError.message || 'Error Shelly',
        })
        .eq('id', command.id);
      await supabase.from('admin_notifs').insert({
        message: `Error Shelly: ${profile.name} · ${shellyError.message || 'No se pudo abrir'} · ${label}`,
      });
      throw shellyError;
    }

    await supabase.from('access_log').insert({
      user_id: profile.id,
      user_name: profile.name,
      access_code: profile.access_code,
      slot_str: label,
      accessed_at: new Date().toISOString(),
    });

    const doorMsg = shellyResult.opened ? 'Puerta abierta' : 'Solicitud de apertura en cola';
    await supabase.from('admin_notifs').insert({
      message: `${doorMsg}: ${profile.name} · ${locationExempt ? 'ubicacion omitida' : `${distance} m`} · ${label}`,
    });

    return res.status(200).json({
      ok: true,
      allow: true,
      command_id: command.id,
      user_name: profile.name,
      slot: label,
      distance_m: distance,
      radius_m: gym ? gym.radius : null,
      location_exempt: locationExempt,
      opened: shellyResult.opened,
      closes_at: new Date(activeWindow.closesMs).toISOString(),
      message: shellyResult.opened
        ? 'Puerta abierta. Entra con cuidado.'
        : 'Apertura solicitada. Espera unos segundos junto a la puerta.',
    });
  } catch (err) {
    console.error(err);
    const msg = err && err.message ? err.message : '';
    if (msg.includes('door_commands')) {
      return res.status(500).json({ error: 'Falta correr door-commands.sql en Supabase.' });
    }
    if (msg.includes('Shelly')) {
      return res.status(500).json({ error: msg });
    }
    return res.status(500).json({ error: 'No se pudo solicitar apertura.' });
  }
};
