const { stripe, supabase } = require('./_fulfillment');
const { buildShopOrder } = require('./_shop');

const SHOP_ALLOWED_EMAILS = ['josephdpelayo@gmail.com'];
const ALLOWED_STATUSES = new Set([
  'solicitado',
  'listo_para_entrega',
  'listo_para_enviar',
  'enviado',
  'recibido',
  'cancelado',
]);

function getBaseUrl(req) {
  if (process.env.PUBLIC_APP_URL) return process.env.PUBLIC_APP_URL.replace(/\/$/, '');
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const proto = req.headers['x-forwarded-proto'] || 'https';
  return `${proto}://${host}`;
}

function getToken(req) {
  return String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
}

async function getOptionalUser(token) {
  if (!token) return null;
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
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
  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id,name,role')
    .eq('id', authData.user.id)
    .single();
  if (profileError || !profile || profile.role !== 'admin') {
    const err = new Error('Solo admin puede actualizar pedidos');
    err.statusCode = 403;
    throw err;
  }
  return profile;
}

async function createCheckout(req, res, token) {
  const user = await getOptionalUser(token);
  const body = req.body || {};
  const customer = body.customer || {};
  const deliveryMethod = body.delivery_method === 'shipping' ? 'shipping' : 'pickup';
  const name = String(customer.name || '').trim();
  const email = String(customer.email || (user && user.email) || '').trim().toLowerCase();
  const phone = String(customer.phone || '').trim();
  const shippingAddress = body.shipping_address || {};

  if (!name) return res.status(400).json({ error: 'Falta nombre' });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return res.status(400).json({ error: 'Correo no valido' });
  if (!SHOP_ALLOWED_EMAILS.includes(String((user && user.email) || email).toLowerCase())) {
    return res.status(403).json({ error: 'Tienda disponible solo para la cuenta autorizada' });
  }
  if (!phone) return res.status(400).json({ error: 'Falta telefono' });
  if (deliveryMethod === 'shipping') {
    const required = ['line1', 'city', 'state', 'postal_code'];
    if (required.some(key => !String(shippingAddress[key] || '').trim())) {
      return res.status(400).json({ error: 'Completa el domicilio de envio' });
    }
  }

  const order = await buildShopOrder(body.items, deliveryMethod, supabase);
  const { data: created, error: orderError } = await supabase
    .from('shop_orders')
    .insert({
      user_id: user ? user.id : null,
      customer_name: name,
      customer_email: email,
      customer_phone: phone,
      delivery_method: deliveryMethod,
      shipping_address: deliveryMethod === 'shipping' ? shippingAddress : null,
      subtotal: order.subtotal,
      shipping_fee: order.shipping_fee,
      total: order.total,
      status: 'pago_pendiente',
      payment_status: 'pending',
      notes: body.notes ? String(body.notes).slice(0, 500) : null,
    })
    .select('id')
    .single();
  if (orderError) throw orderError;

  const itemPayload = order.items.map(item => ({ order_id: created.id, ...item }));
  const { error: itemError } = await supabase.from('shop_order_items').insert(itemPayload);
  if (itemError) throw itemError;

  const lineItems = order.items.map(item => ({
    quantity: item.quantity,
    price_data: {
      currency: 'mxn',
      unit_amount: Math.round(item.unit_amount * 100),
      product_data: {
        name: `HABIT - ${item.product_name}`,
        description: item.description,
      },
    },
  }));

  if (order.shipping_fee > 0) {
    lineItems.push({
      quantity: 1,
      price_data: {
        currency: 'mxn',
        unit_amount: Math.round(order.shipping_fee * 100),
        product_data: { name: 'HABIT - Envio a domicilio' },
      },
    });
  }

  const baseUrl = getBaseUrl(req);
  const session = await stripe.checkout.sessions.create({
    mode: 'payment',
    customer_email: email,
    client_reference_id: user ? user.id : created.id,
    line_items: lineItems,
    metadata: {
      kind: 'shop_order',
      order_id: created.id,
      user_id: user ? user.id : '',
    },
    success_url: `${baseUrl}/app.html?shop=1&shop_success=1&order_id=${created.id}&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${baseUrl}/app.html?shop=1&shop_cancel=1&order_id=${created.id}`,
  });

  await supabase.from('shop_orders').update({ stripe_id: session.id }).eq('id', created.id);
  return res.status(200).json({ url: session.url, order_id: created.id });
}

async function updateOrder(req, res, token) {
  const admin = await requireAdmin(token);
  const orderId = String((req.body && req.body.order_id) || '').trim();
  const status = String((req.body && req.body.status) || '').trim();
  if (!orderId) return res.status(400).json({ error: 'Falta order_id' });
  if (!ALLOWED_STATUSES.has(status)) return res.status(400).json({ error: 'Estado no valido' });

  const { data: order, error: orderError } = await supabase
    .from('shop_orders')
    .select('id,customer_name,total')
    .eq('id', orderId)
    .single();
  if (orderError) throw orderError;

  const { error: updateError } = await supabase
    .from('shop_orders')
    .update({ status, updated_at: new Date().toISOString() })
    .eq('id', orderId);
  if (updateError) throw updateError;

  await supabase.from('admin_notifs').insert({
    message: `Pedido tienda actualizado: ${order.customer_name} · ${status.replace(/_/g, ' ')} · Admin: ${admin.name || 'Admin'}`,
  });

  return res.status(200).json({ ok: true });
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const token = getToken(req);
    const action = String((req.body && req.body.action) || '').trim();
    if (action === 'update_order') return updateOrder(req, res, token);
    return createCheckout(req, res, token);
  } catch (err) {
    console.error(err);
    return res.status(err.statusCode || 500).json({ error: 'No se pudo procesar la tienda' });
  }
};
