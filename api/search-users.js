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

async function createUser(req, res, token) {
  const { adminProfile } = await requireAdmin(token);
  const name = clean(req.body && req.body.name);
  const email = clean(req.body && req.body.email).toLowerCase();
  const phone = clean(req.body && req.body.phone);
  const password = clean(req.body && req.body.password);

  if (!name || !email || !password) return res.status(400).json({ error: 'Completa nombre, correo y contrasena' });
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ error: 'Correo invalido' });
  if (password.length < 6) return res.status(400).json({ error: 'Contrasena minimo 6 caracteres' });

  const { data: created, error: createError } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name, phone, role: 'user' },
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
      .update({ name, phone, role: 'user' })
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
        role: 'user',
        access_code: accessCode,
      })
      .select('id,name,phone,access_code')
      .single();
    if (insertError) throw insertError;
    profile = insertedProfile;
  }

  await supabase.from('admin_notifs').insert({
    message: 'Socio creado por admin: ' + name + ' · ' + email + ' · Admin: ' + (adminProfile.name || 'Admin'),
  });

  return res.status(200).json({ ok: true, profile });
}

async function searchUsers(req, res, token) {
  const { authUser } = await requireAdmin(token);
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
    return searchUsers(req, res, token);
  } catch (err) {
    console.error(err);
    const msg = err.message || 'No se pudo completar la solicitud';
    if (/already|registered|exists|duplicate/i.test(msg)) return res.status(409).json({ error: 'Ese correo ya esta registrado' });
    return res.status(err.statusCode || 500).json({ error: msg });
  }
};
