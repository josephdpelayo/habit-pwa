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

function clean(value) {
  return String(value || '').trim();
}

async function makeAccessCode() {
  for (let i = 0; i < 25; i += 1) {
    const code = String(Math.floor(Math.random() * 9000) + 1000);
    const { data, error } = await supabase
      .from('profiles')
      .select('id')
      .eq('access_code', code)
      .maybeSingle();
    if (error) throw error;
    if (!data) return code;
  }
  throw new Error('No se pudo generar codigo de acceso');
}

async function requireAdmin(token) {
  if (!token) {
    const err = new Error('Sesion requerida');
    err.statusCode = 401;
    throw err;
  }

  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData.user) {
    const err = new Error('Sesion invalida');
    err.statusCode = 401;
    throw err;
  }

  const { data: adminProfile, error: profileError } = await supabase
    .from('profiles')
    .select('role,name')
    .eq('id', authData.user.id)
    .single();
  if (profileError) throw profileError;
  if (adminProfile.role !== 'admin') {
    const err = new Error('Solo admin puede crear socios');
    err.statusCode = 403;
    throw err;
  }

  return { authUser: authData.user, adminProfile };
}

async function requireRole(token, roles) {
  if (!token) {
    const err = new Error('Sesion requerida');
    err.statusCode = 401;
    throw err;
  }

  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData.user) {
    const err = new Error('Sesion invalida');
    err.statusCode = 401;
    throw err;
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('role,name')
    .eq('id', authData.user.id)
    .single();
  if (profileError) throw profileError;
  if (!roles.includes(profile.role)) {
    const err = new Error('No autorizado');
    err.statusCode = 403;
    throw err;
  }

  return { authUser: authData.user, profile };
}

async function createUser(req, res, token) {
  const { adminProfile } = await requireAdmin(token);
  const name = clean(req.body && req.body.name);
  const email = clean(req.body && req.body.email).toLowerCase();
  const phone = clean(req.body && req.body.phone);
  const password = clean(req.body && req.body.password);
  const requestedRole = clean(req.body && req.body.role) === 'reception' ? 'reception' : 'user';
  const isReception = requestedRole === 'reception';

  if (!name || !email || !password) return res.status(400).json({ error: 'Completa nombre, correo y contrasena' });
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ error: 'Correo invalido' });
  if (password.length < 6) return res.status(400).json({ error: 'Contrasena minimo 6 caracteres' });

  const { data: created, error: createError } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name, phone, role: requestedRole },
  });
  if (createError) throw createError;

  const userId = created && created.user && created.user.id;
  if (!userId) throw new Error('No se pudo crear el usuario');

  let { data: profile, error: profileReadError } = await supabase
    .from('profiles')
    .select('id,name,phone,access_code')
    .eq('id', userId)
    .maybeSingle();
  if (profileReadError) throw profileReadError;

  if (profile) {
    const { data: updatedProfile, error: updateError } = await supabase
      .from('profiles')
      .update({ name, phone, role: requestedRole })
      .eq('id', userId)
      .select('id,name,phone,access_code')
      .single();
    if (updateError) throw updateError;
    profile = updatedProfile;
  } else {
    const accessCode = await makeAccessCode();
    const { data: insertedProfile, error: insertError } = await supabase
      .from('profiles')
      .insert({
        id: userId,
        name,
        phone,
        role: requestedRole,
        access_code: accessCode,
      })
      .select('id,name,phone,access_code')
      .single();
    if (insertError) throw insertError;
    profile = insertedProfile;
  }

  await supabase.from('admin_notifs').insert({
    message: (isReception ? 'Cuenta recepcion creada: ' : 'Socio creado por admin: ') + name + ' · ' + email + ' · Admin: ' + (adminProfile.name || 'Admin'),
  });

  return res.status(200).json({ ok: true, profile });
}

const MAZ_UTC_OFFSET_H = 7;
const SLOT_DUR = 30;
const TOTAL_SLOTS = 48;

function pad(n) {
  return String(n).padStart(2, '0');
}

function dsFromIsoMaz(iso) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Mazatlan',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(iso));
  const values = Object.fromEntries(parts.filter(p => p.type !== 'literal').map(p => [p.type, p.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function parseDS(ds) {
  const p = String(ds || '').split('-').map(Number);
  return { y: p[0], m: p[1], d: p[2] };
}

function addDaysDS(ds, n) {
  const p = parseDS(ds);
  const d = new Date(Date.UTC(p.y, p.m - 1, p.d + n, 12, 0, 0));
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

function normSlotIdx(idx) {
  return ((Number(idx) || 0) % TOTAL_SLOTS + TOTAL_SLOTS) % TOTAL_SLOTS;
}

function fmtSlot(idx) {
  const totalMin = normSlotIdx(idx) * SLOT_DUR;
  return `${pad(Math.floor(totalMin / 60))}:${pad(totalMin % 60)}`;
}

function fmtTimeRange(startIdx, slotsUsed) {
  return `${fmtSlot(startIdx)} - ${fmtSlot(Number(startIdx) + Number(slotsUsed || 3))}`;
}

function mazDateMs(ds, slotIdx) {
  const p = parseDS(ds);
  return Date.UTC(p.y, p.m - 1, p.d, MAZ_UTC_OFFSET_H, 0, 0) + (Number(slotIdx) || 0) * SLOT_DUR * 60000;
}

async function receptionActive(req, res, token) {
  await requireRole(token, ['admin', 'reception']);
  const nowMs = Date.now();
  const today = dsFromIsoMaz(new Date().toISOString());
  const days = [addDaysDS(today, -1), today, addDaysDS(today, 1)];

  const { data: bookings, error: bookingError } = await supabase
    .from('bookings')
    .select('id,user_id,ds,start_idx,slots_used,time_str,dur_min,is_group,grupal_spots,status,guest_names')
    .eq('status', 'active')
    .in('ds', days)
    .order('ds')
    .order('start_idx');
  if (bookingError) throw bookingError;

  const activeBookings = (bookings || []).filter(booking => {
    const slotsUsed = Number(booking.slots_used || 3);
    const startMs = mazDateMs(booking.ds, booking.start_idx);
    const endMs = startMs + slotsUsed * SLOT_DUR * 60000;
    return startMs <= nowMs && nowMs < endMs;
  });
  if (!activeBookings.length) return res.status(200).json({ now: new Date().toISOString(), sessions: [] });

  const bookingIds = activeBookings.map(booking => booking.id);
  const hostIds = [...new Set(activeBookings.map(booking => booking.user_id).filter(Boolean))];

  let passRows = [];
  try {
    const { data, error } = await supabase
      .from('booking_guest_passes')
      .select('booking_id,guest_user_id,status')
      .in('booking_id', bookingIds)
      .eq('status', 'active');
    if (error && !String(error.message || '').includes('booking_guest_passes')) throw error;
    passRows = data || [];
  } catch (err) {
    if (!String(err.message || '').includes('booking_guest_passes')) throw err;
  }

  const guestIds = [...new Set(passRows.map(pass => pass.guest_user_id).filter(Boolean))];
  const profileIds = [...new Set([...hostIds, ...guestIds])];
  const { data: profiles, error: profileError } = profileIds.length
    ? await supabase.from('profiles').select('id,name,phone,is_instructor,reception_title,reception_logo,avatar_url').in('id', profileIds)
    : { data: [], error: null };
  if (profileError) throw profileError;
  const profileById = new Map((profiles || []).map(profile => [profile.id, profile]));
  const guestsByBooking = new Map();
  passRows.forEach(pass => {
    if (!guestsByBooking.has(pass.booking_id)) guestsByBooking.set(pass.booking_id, []);
    guestsByBooking.get(pass.booking_id).push(pass.guest_user_id);
  });

  const sessions = activeBookings.flatMap(booking => {
    const slotsUsed = Number(booking.slots_used || 3);
    const startMs = mazDateMs(booking.ds, booking.start_idx);
    const endMs = startMs + slotsUsed * SLOT_DUR * 60000;
    const base = {
      booking_id: booking.id,
      ds: booking.ds,
      start_idx: booking.start_idx,
      slots_used: slotsUsed,
      time_str: booking.time_str || fmtTimeRange(booking.start_idx, slotsUsed),
      dur_min: booking.dur_min || slotsUsed * SLOT_DUR,
      is_group: !!booking.is_group,
      minutes_left: Math.max(0, Math.ceil((endMs - nowMs) / 60000)),
      started_at: new Date(startMs).toISOString(),
      ends_at: new Date(endMs).toISOString(),
    };
    const ids = [booking.user_id, ...(guestsByBooking.get(booking.id) || [])].filter(Boolean);
    return ids.map((userId, idx) => {
      const profile = profileById.get(userId) || {};
      return {
        ...base,
        user_id: userId,
        name: profile.name || (idx === 0 ? 'Socio' : 'Invitado'),
        is_instructor: idx === 0 ? (profile.is_instructor || false) : false,
        guest_names: idx === 0 ? (booking.guest_names || '') : '',
        reception_title: idx === 0 ? (profile.reception_title || '') : '',
        reception_logo: idx === 0 ? (profile.reception_logo || profile.avatar_url || '') : '',
        phone: profile.phone || '',
        kind: idx === 0 ? 'host' : 'guest',
      };
    });
  }).sort((a, b) => a.minutes_left - b.minutes_left || a.name.localeCompare(b.name));

  return res.status(200).json({ now: new Date().toISOString(), sessions });
}

async function searchUsers(req, res, token) {
  const { authUser } = await requireAdmin(token);
  const q = norm(req.body && req.body.q);
  if (q.length < 2) return res.status(200).json({ users: [] });

  const { data: profiles, error: profileError } = await supabase
    .from('profiles')
    .select('id,name,role')
    .neq('role', 'admin')
    .neq('role', 'reception')
    .limit(1000);
  if (profileError) throw profileError;

  const { data: usersData, error: usersError } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (usersError) throw usersError;

  const emailById = new Map((usersData.users || []).map(user => [user.id, user.email || '']));
  const users = (profiles || [])
    .filter(profile => profile.id !== authUser.id)
    .map(profile => ({
      id: profile.id,
      name: profile.name || 'Usuario',
      email: emailById.get(profile.id) || '',
    }))
    .filter(user => norm(user.name).includes(q) || norm(user.email).includes(q))
    .slice(0, 12);

  return res.status(200).json({ users });
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
    if ((req.body && req.body.action) === 'create') return createUser(req, res, token);
    if ((req.body && req.body.action) === 'reception-active') return receptionActive(req, res, token);
    return searchUsers(req, res, token);
  } catch (err) {
    console.error(err);
    const msg = err.message || 'No se pudo completar la solicitud';
    if (/already|registered|exists|duplicate/i.test(msg)) return res.status(409).json({ error: 'Ese correo ya esta registrado' });
    return res.status(err.statusCode || 500).json({ error: msg });
  }
};
