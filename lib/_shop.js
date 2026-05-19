const SHOP_PRODUCTS = [
  { id: 'whey-1kg', name: '100% Whey Protein', unit_amount: 650, description: 'Bolsa 1 kg' },
  { id: 'protein-sachet-33g', name: 'Sobre personal proteina', unit_amount: 45, description: 'Una toma 33 g' },
  { id: 'creatine-monohydrate', name: 'Creatina monohidratada', unit_amount: 420, description: 'Monohidratada' },
  { id: 'habit-shirt-regular-men-xs', name: 'Playera HABIT regular fit hombre XS', unit_amount: 350, description: 'Regular fit hombre talla XS' },
  { id: 'habit-shirt-regular-men-s', name: 'Playera HABIT regular fit hombre S', unit_amount: 350, description: 'Regular fit hombre talla S' },
  { id: 'habit-shirt-regular-men-m', name: 'Playera HABIT regular fit hombre M', unit_amount: 350, description: 'Regular fit hombre talla M' },
  { id: 'habit-shirt-regular-men-l', name: 'Playera HABIT regular fit hombre L', unit_amount: 350, description: 'Regular fit hombre talla L' },
  { id: 'habit-shirt-regular-men-xl', name: 'Playera HABIT regular fit hombre XL', unit_amount: 350, description: 'Regular fit hombre talla XL' },
  { id: 'habit-shirt-regular-women-s', name: 'Playera HABIT regular fit mujer S', unit_amount: 350, description: 'Regular fit mujer talla S' },
  { id: 'habit-shirt-regular-women-m', name: 'Playera HABIT regular fit mujer M', unit_amount: 350, description: 'Regular fit mujer talla M' },
  { id: 'habit-shirt-regular-women-l', name: 'Playera HABIT regular fit mujer L', unit_amount: 350, description: 'Regular fit mujer talla L' },
  { id: 'habit-shirt-oversize-unisex-xs', name: 'Playera HABIT oversize unisex XS', unit_amount: 390, description: 'Oversize unisex talla XS' },
  { id: 'habit-shirt-oversize-unisex-s', name: 'Playera HABIT oversize unisex S', unit_amount: 390, description: 'Oversize unisex talla S' },
  { id: 'habit-shirt-oversize-unisex-m', name: 'Playera HABIT oversize unisex M', unit_amount: 390, description: 'Oversize unisex talla M' },
  { id: 'habit-shirt-oversize-unisex-l', name: 'Playera HABIT oversize unisex L', unit_amount: 390, description: 'Oversize unisex talla L' },
  { id: 'habit-shirt-oversize-unisex-xl', name: 'Playera HABIT oversize unisex XL', unit_amount: 390, description: 'Oversize unisex talla XL' },
];

const SHIPPING_FEE = 69;
const FREE_SHIPPING_MIN = 1000;

async function getActiveShopProducts(supabase) {
  if (!supabase) return SHOP_PRODUCTS;
  const { data, error } = await supabase
    .from('shop_products')
    .select('id,name,description,price,stock,track_inventory,active,sort_order')
    .eq('active', true)
    .order('sort_order', { ascending: true });
  if (error || !data || !data.length) {
    if (error) console.warn('Using fallback shop products:', error.message);
    return SHOP_PRODUCTS;
  }
  return data.map(product => ({
    id: product.id,
    name: product.name,
    unit_amount: Number(product.price) || 0,
    description: product.description || '',
    stock: Number(product.stock) || 0,
    track_inventory: product.track_inventory !== false,
  }));
}

function money(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

async function buildShopOrder(rawItems, deliveryMethod, supabase) {
  const products = await getActiveShopProducts(supabase);
  const items = Array.isArray(rawItems) ? rawItems : [];
  const normalized = [];

  for (const item of items) {
    const product = products.find(row => row.id === (item && item.product_id)) || null;
    const quantity = Math.max(0, Math.min(20, parseInt(item && item.quantity, 10) || 0));
    if (!product || !quantity) continue;
    if (product.track_inventory && quantity > product.stock) {
      const err = new Error(`Stock insuficiente: ${product.name}`);
      err.statusCode = 400;
      throw err;
    }
    normalized.push({
      product_id: product.id,
      product_name: product.name,
      quantity,
      unit_amount: product.unit_amount,
      line_total: money(product.unit_amount * quantity),
      description: product.description,
    });
  }

  if (!normalized.length) {
    const err = new Error('Carrito vacio');
    err.statusCode = 400;
    throw err;
  }

  const subtotal = money(normalized.reduce((sum, item) => sum + item.line_total, 0));
  const shipping_fee = deliveryMethod === 'shipping' && subtotal < FREE_SHIPPING_MIN ? SHIPPING_FEE : 0;
  const total = money(subtotal + shipping_fee);

  return { items: normalized, subtotal, shipping_fee, total };
}

module.exports = { SHOP_PRODUCTS, SHIPPING_FEE, FREE_SHIPPING_MIN, getActiveShopProducts, buildShopOrder };
