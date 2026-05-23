const { stripe, activateMembership, fulfillShopOrder } = require('../lib/_fulfillment');

function readRawBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(Buffer.from(chunk)));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).send('Method not allowed');
  }

  const signature = req.headers['stripe-signature'];
  const rawBody = await readRawBody(req);

  let event;
  try {
    event = stripe.webhooks.constructEvent(rawBody, signature, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('Webhook signature error:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  try {
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      if (!session || !session.id) throw new Error('Invalid session object in webhook');
      if (session.payment_status !== 'paid') return res.status(200).json({ received: true, skipped: 'payment_status not paid' });
      if (session.metadata && session.metadata.kind === 'shop_order') {
        await fulfillShopOrder(session);
      } else {
        await activateMembership(session);
      }
    }
    return res.status(200).json({ received: true });
  } catch (err) {
    console.error(err);
    return res.status(500).send('Webhook handler failed');
  }
};

module.exports.config = {
  api: {
    bodyParser: false,
  },
};
