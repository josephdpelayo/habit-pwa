const { createClient } = require('@supabase/supabase-js');
const { slotLabel, accessWindow } = require('../lib/_slots');

const DEFAULT_RADIUS_M = 500;
const DEFAULT_MAX_ACCURACY_M = 150;
const SHELLY_DEFAULT_TURN = 'off';
const SHELLY_DEFAULT_RELEASE_SECONDS = 5;
const DOOR_REQUEST_COOLDOWN_MS = 5 * 1000;
const SHELLY_RATE_LIMIT_WAIT_SECONDS = 60;
const LOCATION_EXEMPT_EMAILS = ['josephdpelayo@gmail.com', 'habit1@habit.com', 'zuritalejandro5@gmail.com'];

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

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', 'https://habittraininghub.app');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
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

function shellyDeviceIdVariants(deviceId) {
  const raw = String(deviceId || '').trim();
  const ids = [raw];
  const suffix = raw.includes('-') ? raw.split('-').pop() : '';
  if (suffix) ids.push(suffix);
  const hex = suffix || raw;
  if (/^[a-f0-9]+$/i.test(hex)) {
    ids.push(String(parseInt(hex, 16)));
  }
  return [...new Set(ids.filter(Boolean))];
}

function shellyCloudDeviceId(deviceId) {
  const raw = String(deviceId || '').trim();
  if (raw.includes('-')) return raw.split('-').pop();
  return raw;
}

function shouldUseShellyV2(deviceId) {
  const raw = String(deviceId || '').trim();
  return raw.includes('-') || /[a-f]/i.test(raw);
}

function shellyErrorMessage(payload, text, response) {
  if (payload && payload.errors) return JSON.stringify(payload.errors);
  if (payload && payload.error) return JSON.stringify(payload.error);
  return text || response.statusText;
}

function isWrongShellyDeviceId(message) {
  return /wrong_device_id/i.test(String(message || ''));
}

function isShellyRateLimited(message) {
  return /max_req|request limit/i.test(String(message || ''));
}

async function sendShellyRelay(cfg, turn, deviceId) {
  const body = new URLSearchParams({
    id: deviceId,
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
  let payload;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch (_) {
    payload = text;
  }

  if (!response.ok || (payload && payload.isok === false)) {
    const message = shellyErrorMessage(payload, text, response);
    throw new Error(`Shelly no abrio: ${message}`);
  }
  return payload;
}

async function sendShellySwitchV2(cfg, turn, deviceId) {
  const on = turn === 'on';
  const response = await fetch(`${cfg.server}/v2/devices/api/set/switch?auth_key=${encodeURIComponent(cfg.authKey)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      id: deviceId,
      channel: Number(cfg.channel || 0),
      on,
      toggle_after: cfg.releaseSeconds > 0 ? cfg.releaseSeconds : undefined,
    }),
  });
  const text = await response.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch (_) {
    payload = text;
  }

  if (!response.ok || (payload && payload.isok === false)) {
    const message = shellyErrorMessage(payload, text, response);
    throw new Error(`Shelly no abrio: ${message}`);
  }
  return payload;
}

async function sendShellyRelayWithFallback(cfg, turn) {
  const ids = shellyDeviceIdVariants(cfg.deviceId);
  let lastError = null;
  for (const id of ids) {
    try {
      const payload = await sendShellyRelay(cfg, turn, id);
      return { payload, deviceId: id };
    } catch (error) {
      lastError = error;
      if (!isWrongShellyDeviceId(error.message)) throw error;
    }
  }
  throw new Error(`${lastError ? lastError.message : 'Shelly no abrio'} · IDs probados: ${ids.join(', ')}`);
}

async function triggerShellyDoor() {
  const cfg = getShellyConfig();
  if (!cfg) throw new Error('Shelly no configurado en Vercel. Revisa SHELLY_SERVER_URL, SHELLY_AUTH_KEY y SHELLY_DEVICE_ID en Production.');

  if (shouldUseShellyV2(cfg.deviceId)) {
    const deviceId = shellyCloudDeviceId(cfg.deviceId);
    const payload = await sendShellySwitchV2(cfg, cfg.turn, deviceId);
    return { configured: true, opened: true, payload, device_id: deviceId, release_seconds: cfg.releaseSeconds, api: 'v2' };
  }

  const opened = await sendShellyRelayWithFallback(cfg, cfg.turn);
  if (cfg.releaseSeconds > 0) {
    await sleep(cfg.releaseSeconds * 1000);
    await sendShellyRelay(cfg, cfg.relockTurn, opened.deviceId);
  }

  return { configured: true, opened: true, payload: opened.payload, device_id: opened.deviceId, release_seconds: cfg.releaseSeconds };
}

module.exports = async function handler(req, res) {
  applyCors(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
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
      .select('id,user_id,ds,start_idx,slots_used,time_str,status,is_group,grupal_spots')
      .eq('user_id', profile.id)
      .eq('status', 'active')
      .order('ds', { ascending: true })
      .order('start_idx', { ascending: true })
      .limit(20);
    if (bookingError) throw bookingError;

    let accessBookings = bookings || [];
    const { data: passes, error: passError } = await supabase
      .from('booking_guest_passes')
      .select('booking_id,host_user_id,status')
      .eq('guest_user_id', profile.id)
      .eq('status', 'active')
      .limit(20);
    if (passError && !String(passError.message || '').includes('booking_guest_passes')) throw passError;
    const passRows = passError ? [] : (passes || []);
    const passBookingIds = [...new Set(passRows.map(pass => pass.booking_id).filter(Boolean))];
    if (passBookingIds.length) {
      const { data: passBookings, error: passBookingError } = await supabase
        .from('bookings')
        .select('id,user_id,ds,start_idx,slots_used,time_str,status,is_group,grupal_spots')
        .in('id', passBookingIds)
        .eq('status', 'active');
      if (passBookingError) throw passBookingError;
      const hostIds = [...new Set(passRows.map(pass => pass.host_user_id).filter(Boolean))];
      const { data: hosts, error: hostsError } = hostIds.length
        ? await supabase.from('profiles').select('id,name').in('id', hostIds)
        : { data: [], error: null };
      if (hostsError) throw hostsError;
      const passByBooking = new Map(passRows.map(pass => [pass.booking_id, pass]));
      const hostById = new Map((hosts || []).map(host => [host.id, host.name || 'Un socio']));
      accessBookings = accessBookings.concat((passBookings || []).filter(booking => booking.is_group).map(booking => {
        const pass = passByBooking.get(booking.id) || {};
        return {
          ...booking,
          guest_pass: true,
          host_user_id: pass.host_user_id,
          host_name: hostById.get(pass.host_user_id) || 'Un socio',
        };
      }));
    }

    const nowMs = Date.now();
    // 15-minute grace buffer to account for client clock skew and Android GPS delays.
    const CLOCK_GRACE_MS = 15 * 60 * 1000;
    let activeBooking = null;
    let activeWindow = null;
    let soonestWindow = null;
    let soonestOpensMs = Infinity;
    for (const booking of accessBookings || []) {
      const window = accessWindow(booking);
      if (nowMs >= window.opensMs - CLOCK_GRACE_MS && nowMs <= window.closesMs) {
        activeBooking = booking;
        activeWindow = window;
        break;
      }
      // Track the next upcoming window for a better error message.
      if (window.opensMs > nowMs && window.opensMs < soonestOpensMs) {
        soonestOpensMs = window.opensMs;
        soonestWindow = window;
      }
    }

    if (!activeBooking) {
      const debugInfo = {
        serverNow: new Date(nowMs).toISOString(),
        bookingCount: accessBookings.length,
        bookings: (accessBookings || []).map(b => {
          const w = accessWindow(b);
          return { ds: b.ds, start_idx: b.start_idx, slots_used: b.slots_used, opensIso: new Date(w.opensMs).toISOString(), closesIso: new Date(w.closesMs).toISOString() };
        }),
      };
      console.log('[door] no_active_access', JSON.stringify(debugInfo));
      if (soonestWindow) {
        const minsLeft = Math.ceil((soonestOpensMs - nowMs) / 60000);
        return deny(res, 403, 'no_active_access', `Tu acceso se activa en ${minsLeft} minuto${minsLeft !== 1 ? 's' : ''}.`, { debug: debugInfo });
      }
      return deny(res, 403, 'no_active_access', 'Tu acceso se activa 10 minutos antes de tu reserva.', { debug: debugInfo });
    }

    const label = slotLabel(activeBooking);
    const cooldownSince = new Date(nowMs - DOOR_REQUEST_COOLDOWN_MS).toISOString();
    const { data: recentCommand, error: recentError } = await supabase
      .from('door_commands')
      .select('id,status,requested_at')
      .eq('user_id', profile.id)
      .eq('booking_id', activeBooking.id)
      .gte('requested_at', cooldownSince)
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (recentError) throw recentError;
    if (recentCommand) {
      return deny(
        res,
        429,
        'door_request_cooldown',
        'Ya enviamos una solicitud de apertura. Espera unos segundos antes de intentar de nuevo.',
        { retry_after_seconds: Math.ceil(DOOR_REQUEST_COOLDOWN_MS / 1000) }
      );
    }

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
        message: `Error Shelly: ${profile.name}${activeBooking.guest_pass ? ` invitado de ${activeBooking.host_name}` : ''} · ${shellyError.message || 'No se pudo abrir'} · ${label}`,
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
    const guestSuffix = activeBooking.guest_pass ? ` invitado de ${activeBooking.host_name}` : '';
    await supabase.from('admin_notifs').insert({
      message: `${doorMsg}: ${profile.name}${guestSuffix} · ${locationExempt ? 'ubicacion omitida' : `${distance} m`} · ${label}`,
    });

    const pushEmoji = shellyResult.opened ? '🔓' : '⏳';
    const pushTitle = shellyResult.opened ? 'Puerta abierta' : 'Apertura en cola';
    sendAdminPush(`${pushEmoji} ${pushTitle}`, `${profile.name}${guestSuffix} · ${label}`, 'door-open').catch(() => {});

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
        ? `Puerta abierta. ${activeBooking.guest_pass ? `Entrena con ${activeBooking.host_name}.` : 'Entra con cuidado.'}`
        : 'Apertura solicitada. Espera unos segundos junto a la puerta.',
    });
  } catch (err) {
    console.error(err);
    const msg = err && err.message ? err.message : '';
    if (msg.includes('door_commands')) {
      return res.status(500).json({ error: 'Falta correr door-commands.sql en Supabase.' });
    }
    if (msg.includes('booking_guest_passes')) {
      return res.status(500).json({ error: 'Falta correr group-guest-passes.sql en Supabase.' });
    }
    if (isShellyRateLimited(msg)) {
      return res.status(429).json({
        ok: false,
        allow: false,
        reason: 'shelly_rate_limited',
        error: 'Shelly recibio demasiados intentos seguidos. Espera 60 segundos y vuelve a intentar.',
        retry_after_seconds: SHELLY_RATE_LIMIT_WAIT_SECONDS,
      });
    }
    if (msg.includes('Shelly')) {
      return res.status(500).json({ error: 'No se pudo conectar con el relay de la puerta. Intenta de nuevo.' });
    }
    return res.status(500).json({ error: 'No se pudo solicitar apertura.' });
  }
};
