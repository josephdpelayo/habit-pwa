// Skandi Fit — código de barras a alimento, vía Open Food Facts.
//
// Este camino NO gasta IA y no toca la cuota diaria: un producto empaquetado ya trae sus
// macros impresos, estimarlos con un modelo sería pagar por adivinar algo que es un dato.
//
// El resultado se guarda en skandi_foods con el barcode, así que escanear el mismo producto
// la segunda vez ni siquiera sale a internet. La porción NO se decide aquí: el endpoint
// devuelve los macros por 100 g y la porción sugerida del empaque, y el cliente pregunta
// cuánto se comió — que es justo lo que el escaneo por sí solo no puede saber.

const { createClient } = require('@supabase/supabase-js');

const OFF_BASE = 'https://world.openfoodfacts.org/api/v2/product';
const OFF_FIELDS = 'code,product_name,product_name_es,brands,quantity,serving_size,serving_quantity,nutriments';
// Open Food Facts pide identificarse en el User-Agent; sin esto pueden limitar o bloquear.
const OFF_UA = 'SkandiFit/1.0 (https://habittraininghub.app)';
const OFF_TIMEOUT_MS = 8000;

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', 'https://habittraininghub.app');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function fail(res, status, reason, message) {
  return res.status(status).json({ ok: false, reason, message });
}

function num(value) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

// OFF no siempre trae energy-kcal_100g; a veces solo el valor en kilojoules.
function kcalFrom(nutriments) {
  const direct = num(nutriments['energy-kcal_100g']);
  if (direct !== null) return direct;
  const kj = num(nutriments['energy-kj_100g']) ?? num(nutriments.energy_100g);
  return kj === null ? null : Math.round(kj / 4.184);
}

function servingGrams(product) {
  const q = num(product.serving_quantity);
  if (q) return Math.min(q, 5000);
  // serving_size viene como texto libre: "15 g", "1 taza (240 ml)", "30g".
  const match = String(product.serving_size || '').match(/([\d.,]+)\s*(g|ml)\b/i);
  if (!match) return null;
  const parsed = Number(match[1].replace(',', '.'));
  return Number.isFinite(parsed) && parsed > 0 ? Math.min(parsed, 5000) : null;
}

module.exports = async function handler(req, res) {
  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return fail(res, 405, 'method_not_allowed', 'Método no permitido');
  }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return fail(res, 500, 'missing_supabase_env', 'Falta configurar SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.');
  }

  try {
    const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
    if (!token) return fail(res, 401, 'no_session', 'Sesión requerida');

    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return fail(res, 401, 'bad_session', 'Sesión inválida');
    const userId = authData.user.id;

    const barcode = String((req.body && req.body.barcode) || '').replace(/\D/g, '');
    if (barcode.length < 8 || barcode.length > 14) {
      return fail(res, 400, 'bad_barcode', 'Ese código de barras no parece válido.');
    }

    // 1. ¿Ya lo tenemos? El catálogo propio manda sobre el global.
    const { data: known, error: knownError } = await supabase
      .from('skandi_foods')
      .select('id,user_id,name,brand,barcode,serving_label,serving_grams,kcal_100g,protein_100g,carbs_100g,fat_100g,fiber_100g,source')
      .eq('barcode', barcode)
      .or(`user_id.eq.${userId},user_id.is.null`)
      .order('user_id', { ascending: true, nullsFirst: false })
      .limit(1);

    if (knownError && /relation .* does not exist/i.test(knownError.message)) {
      return fail(res, 500, 'missing_migration', 'Falta correr la migración 073_skandi_nutrition.sql en Supabase.');
    }
    if (known && known.length) {
      return res.status(200).json({ ok: true, source: 'catalog', food: known[0] });
    }

    // 2. Open Food Facts. Con timeout: un producto no encontrado no debe colgar la pantalla.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), OFF_TIMEOUT_MS);
    let payload;
    try {
      const off = await fetch(`${OFF_BASE}/${barcode}.json?fields=${OFF_FIELDS}`, {
        headers: { 'User-Agent': OFF_UA, Accept: 'application/json' },
        signal: controller.signal,
      });
      if (!off.ok) {
        return fail(res, 502, 'off_error', 'La base de productos no respondió. Captúralo a mano.');
      }
      payload = await off.json();
    } catch (e) {
      const aborted = e && e.name === 'AbortError';
      return fail(res, aborted ? 504 : 502, 'off_unreachable',
        aborted ? 'La base de productos tardó demasiado. Captúralo a mano.' : 'No pudimos consultar la base de productos.');
    } finally {
      clearTimeout(timer);
    }

    const product = payload && payload.status === 1 ? payload.product : null;
    if (!product) {
      return fail(res, 404, 'not_found', 'Ese producto no está en la base. Captúralo a mano una vez y queda guardado.');
    }

    const nutriments = product.nutriments || {};
    const kcal = kcalFrom(nutriments);
    const name = String(product.product_name_es || product.product_name || '').trim();
    if (kcal === null || !name) {
      return fail(res, 422, 'no_nutrition',
        'Ese producto está en la base pero sin datos nutricionales completos. Captúralo a mano.');
    }

    const grams = servingGrams(product);
    const food = {
      user_id: userId,
      name: name.slice(0, 120),
      brand: String(product.brands || '').split(',')[0].trim().slice(0, 80) || null,
      barcode,
      serving_label: String(product.serving_size || '').trim().slice(0, 60) || null,
      serving_grams: grams,
      kcal_100g: Math.min(kcal, 1000),
      protein_100g: Math.min(num(nutriments.proteins_100g) || 0, 100),
      carbs_100g: Math.min(num(nutriments.carbohydrates_100g) || 0, 100),
      fat_100g: Math.min(num(nutriments.fat_100g) || 0, 100),
      fiber_100g: Math.min(num(nutriments.fiber_100g) || 0, 100),
      source: 'off',
    };

    const { data: saved, error: saveError } = await supabase
      .from('skandi_foods')
      .insert(food)
      .select('id,user_id,name,brand,barcode,serving_label,serving_grams,kcal_100g,protein_100g,carbs_100g,fat_100g,fiber_100g,source')
      .single();

    if (saveError) {
      // Guardar es una comodidad, no el objetivo: si el índice único lo rechaza por una
      // carrera, devolvemos igual los datos y que el cliente siga con su porción.
      console.warn('lookup-barcode: no se pudo guardar', saveError.message);
      return res.status(200).json({ ok: true, source: 'openfoodfacts', saved: false, food });
    }

    return res.status(200).json({ ok: true, source: 'openfoodfacts', saved: true, food: saved });
  } catch (err) {
    console.error('lookup-barcode error:', err);
    return fail(res, 500, 'server_error', 'No pudimos buscar ese código. Intenta de nuevo.');
  }
};
