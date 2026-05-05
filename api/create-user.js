const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function getToken(req) {
  return String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
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
      .select('role,name')
      .eq('id', authData.user.id)
      .single();
    if (profileError) throw profileError;
    if (adminProfile.role !== 'admin') return res.status(403).json({ error: 'Solo admin puede crear socios' });

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
  } catch (err) {
    console.error(err);
    const msg = err.message || 'No se pudo crear el socio';
    if (/already|registered|exists|duplicate/i.test(msg)) return res.status(409).json({ error: 'Ese correo ya esta registrado' });
    return res.status(500).json({ error: msg });
  }
};
