// Skandi Fit — el router del servidor: nutrición e integraciones deportivas.
//
// Caminos muy distintos viven en el mismo archivo por una razón de plataforma, no de diseño:
// el plan Hobby de Vercel admite 12 Serverless Functions por deployment, y el proyecto está
// en el tope. Un archivo = una función, así que las rutas se agrupan y se despachan por
// `action`. Si algún día esto crece a Pro, separarlas es mover cada rama a su archivo y
// cambiar los fetch del cliente. (Este archivo se llamaba `nutrition.js` hasta que Strava
// entró: el nombre viejo sobrevive como rewrite en vercel.json para los clientes con caché.)
//
//   { action: 'analyze', meal_id }  -> foto y/o texto -> Claude (vision). Gasta cuota.
//   { action: 'barcode', barcode }  -> Open Food Facts. Sin IA y sin cuota.
//   strava-connect / -callback / -webhook / -sync / -disconnect / -subscription
//   intervals-connect / -status / -sync / -disconnect
//
// Seguridad: la ANTHROPIC_API_KEY vive solo aquí. El cliente nunca habla con Anthropic, y la
// foto se descarga con service-role porque el bucket es privado (migración 073). Los tokens
// de Strava viven en una tabla con RLS que niega todo (migración 081) por lo mismo.

const { createClient } = require('@supabase/supabase-js');
const Anthropic = require('@anthropic-ai/sdk');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', 'https://habittraininghub.app');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function fail(res, status, reason, message) {
  return res.status(status).json({ ok: false, reason, message });
}

// Devuelve el uid, o null cuando la sesión no sirve — en cuyo caso ya respondió y quien
// llama solo tiene que regresar. Las tres ramas del router validan igual: un Bearer con el
// JWT de Supabase y nada más.
async function requireUser(req, res) {
  const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
  if (!token) { fail(res, 401, 'no_session', 'Sesión requerida'); return null; }
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) { fail(res, 401, 'bad_session', 'Sesión inválida'); return null; }
  return data.user.id;
}

// ── Análisis de comida con Claude ───────────────────────────────────────────


const BUCKET = 'skandi-meals';
const DEFAULT_DAILY_LIMIT = 25;
const DEFAULT_MODEL = 'claude-opus-5';
const MAX_IMAGE_BYTES = 4.5 * 1024 * 1024; // el límite de la API de vision es 5 MB por imagen
// Vercel mata esta función a los 60 s. El SDK reintenta 429/5xx por default dentro de la misma
// invocación, que es justo lo peor aquí: consume el reloj y el navegador recibe un 504. Es mejor
// devolver el fallo transitorio a tiempo y dejar que el cliente haga UN reintento visible como la
// misma operación. 2,000 tokens alcanzan holgadamente para el JSON de una comida normal.
const AI_TIMEOUT_MS = 48_000;
const AI_MAX_TOKENS = 2_000;
const CATALOG_SIZE = 50;

// La API de vision acepta jpeg/png/gif/webp. HEIC no, aunque el bucket lo permita: el
// cliente comprime a JPEG antes de subir, así que llegar aquí en HEIC es un bug del cliente
// y conviene que lo diga claro en vez de fallar dentro del SDK.
const MEDIA_TYPES = {
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png',
  gif: 'image/gif', webp: 'image/webp',
};

// El lugar es lo que decide cuánta grasa de cocción asumir, y si el renglón llega palomeado.
const VENUE_LABELS = {
  casa: 'en casa, cocinado por el usuario (que normalmente NO usa aceite)',
  restaurante: 'restaurante (el usuario no controla el aceite ni la mantequilla)',
  fonda: 'fonda o cocina económica (el usuario no controla el aceite)',
  otro: 'no especificado',
};


const SYSTEM_PROMPT = `Eres un nutriólogo estimando la ingesta de un atleta en Mazatlán, México, para su diario. Recibes una foto, una descripción escrita, o las dos.

Cómo estimar:
- Piensa en porciones de casa y de fonda mexicana, no en tazas ni onzas: tortillas, guisados, arroz, frijoles, tacos, tortas, mariscos, aguas frescas.
- Con foto, usa las referencias visibles para calcular el tamaño (un plato estándar mide ~26 cm, una tortilla de maíz ~15 cm y pesa ~30 g, una lata ~355 ml, un tenedor ~19 cm).
- Sin foto, estima la porción típica de lo que describe. Si dice una cantidad ("dos huevos", "un plato hondo"), respétala; si no la dice, usa la porción normal de una persona adulta y baja la confianza.
- Cuando hay foto Y descripción, la descripción manda sobre lo que creas ver: el usuario sabe qué se comió.
- Separa la comida en los alimentos que un humano corregiría por separado (proteína, guarnición, tortillas, salsa, bebida), no en un solo renglón "comida".
- No inventes precisión: cuando no se puede saber la cantidad, estima el rango típico y baja la confianza de ese renglón.

LA GRASA DE COCCIÓN VA SIEMPRE EN SU PROPIO RENGLÓN, con is_cooking_fat=true, y NUNCA sumada dentro de otro alimento. Es la única manera de que el usuario pueda quitarla con un toque, porque cocinando en casa muchas veces no usa nada de aceite. Reglas:
- Un solo renglón de grasa de cocción por comida, con toda la que estimes ("Aceite de cocción").
- Si el lugar es "casa", estima la que se ve o se describe y nada más; no la des por hecha.
- Si es restaurante o fonda, cuenta la que un cocinero usaría de verdad: un salteado trae 5-15 g, algo capeado o frito bastante más, y eso el usuario no lo controla.
- Los demás renglones llevan solo la grasa propia del alimento (la del aguacate, la de la carne), nunca la del sartén.
- Si de verdad no lleva grasa añadida (algo hervido, asado sin aceite, fruta, yogurt), no generes el renglón.

Confianza (campo confidence, 0 a 1):
- 0.8-1.0: alimento claramente identificable y con cantidad evidente.
- 0.5-0.8: se identifica bien pero la cantidad es dudosa.
- 0.0-0.5: identificación incierta, o hay ingredientes ocultos (salsas, aderezos, relleno).

Catálogo: si un alimento del catálogo del usuario coincide con lo que ves o lee, usa sus valores por 100 g escalados a los gramos que estimes y pon su id en catalog_id. Ese catálogo son correcciones que el usuario ya hizo a mano: vale más que tu estimación general. Si no coincide ninguno, deja catalog_id vacío.

Los macros de cada renglón van en gramos absolutos para la porción estimada, no por 100 g. Las kcal deben ser coherentes con los macros (proteína 4, carbohidratos 4, grasa 9 kcal/g).

sugar_g es la parte de carbs_g que son azúcares (los del refresco, el pan dulce, la salsa BBQ, la fruta), NO un macro aparte: ya va contado dentro de carbs_g y no debe sumarse otra vez a las kcal. En algo sin azúcar añadida ni fruta, es 0.

Si no hay comida que estimar (la foto no es comida, o el texto no describe alimentos), devuelve is_food=false con items vacío y di por qué en notes.`;

const MEAL_SCHEMA = {
  type: 'object',
  properties: {
    is_food: { type: 'boolean' },
    dish_name: { type: 'string', description: 'Nombre corto del platillo en español, ej. "Chilaquiles con huevo"' },
    confidence: { type: 'number', description: 'Confianza global de 0 a 1' },
    notes: { type: 'string', description: 'Qué no se puede ver bien y conviene que el usuario corrija. Una o dos frases, o vacío.' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string' },
          grams: { type: 'number' },
          kcal: { type: 'number' },
          protein_g: { type: 'number' },
          carbs_g: { type: 'number' },
          fat_g: { type: 'number' },
          fiber_g: { type: 'number' },
          sugar_g: { type: 'number', description: 'azúcares del renglón, ya incluidos dentro de carbs_g' },
          confidence: { type: 'number' },
          catalog_id: { type: 'string', description: 'id del alimento del catálogo, o cadena vacía' },
          is_cooking_fat: { type: 'boolean', description: 'true solo para el renglón de aceite/grasa de cocción' },
        },
        required: ['label', 'grams', 'kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'sugar_g', 'confidence', 'catalog_id', 'is_cooking_fat'],
        additionalProperties: false,
      },
    },
  },
  required: ['is_food', 'dish_name', 'confidence', 'notes', 'items'],
  additionalProperties: false,
};

function dailyLimit() {
  const n = Number(process.env.MEAL_AI_DAILY_LIMIT || DEFAULT_DAILY_LIMIT);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : DEFAULT_DAILY_LIMIT;
}

function mediaTypeFor(path) {
  const ext = String(path).split('.').pop().toLowerCase();
  return MEDIA_TYPES[ext] || null;
}

// Redondeo a un decimal + recorte a los CHECK de skandi_meal_items: un número fuera de rango
// haría fallar el insert completo y perderíamos el análisis entero por un solo renglón raro.
function clamp(value, max) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(Math.min(n, max) * 10) / 10;
}

function catalogBlock(foods) {
  if (!foods.length) return 'El usuario todavía no tiene alimentos en su catálogo.';
  const lines = foods.map(f => {
    const name = f.brand ? `${f.name} (${f.brand})` : f.name;
    const serving = f.serving_label ? `, porción ${f.serving_label}${f.serving_grams ? ` = ${f.serving_grams} g` : ''}` : '';
    return `- ${f.id} | ${name} | por 100 g: ${f.kcal_100g} kcal, P ${f.protein_100g}, C ${f.carbs_100g}, G ${f.fat_100g}${serving}`;
  });
  return `Catálogo de alimentos del usuario (id | nombre | macros por 100 g):\n${lines.join('\n')}`;
}

async function markFailed(mealId, message) {
  await supabase.from('skandi_meals')
    .update({ analysis_status: 'failed', analysis_error: String(message).slice(0, 500) })
    .eq('id', mealId);
}

async function analyzeMeal(req, res) {

  const apiKey = process.env.ANTHROPIC_API_KEY;
  // El detalle del redeploy no es adorno: una variable de entorno nueva solo existe para los
  // deployments creados DESPUÉS de guardarla, así que "ya la puse" y "no la ve" conviven.
  if (!apiKey) return fail(res, 500, 'missing_api_key',
    'Falta ANTHROPIC_API_KEY en Vercel, o el deployment es anterior a haberla guardado. Revisa que esté marcada para Production y haz Redeploy.');
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return fail(res, 500, 'missing_supabase_env', 'Falta configurar SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.');
  }

  let userId = null;
  let quotaSpent = false;
  let mealId = null;
  const startedAt = Date.now();
  let stage = 'auth';

  try {
    userId = await requireUser(req, res);
    if (!userId) return;

    mealId = String((req.body && req.body.meal_id) || '').trim();
    if (!mealId) return fail(res, 400, 'no_meal_id', 'Falta meal_id');

    stage = 'load_meal';
    const { data: meal, error: mealError } = await supabase
      .from('skandi_meals')
      .select('id,user_id,photo_path,meal_type,note,venue,input_kind,analysis_status')
      .eq('id', mealId)
      .maybeSingle();

    if (mealError) {
      if (/relation .* does not exist/i.test(mealError.message)) {
        return fail(res, 500, 'missing_migration', 'Falta correr la migración 073_skandi_nutrition.sql en Supabase.');
      }
      if (/column .*(venue|input_kind)/i.test(mealError.message)) {
        return fail(res, 500, 'missing_migration', 'Falta correr la migración 075_skandi_nutrition_inputs.sql en Supabase.');
      }
      throw mealError;
    }
    if (!meal) return fail(res, 404, 'meal_not_found', 'Esa comida no existe');
    if (meal.user_id !== userId) return fail(res, 403, 'not_your_meal', 'Esa comida no es tuya');

    // Foto, texto, o las dos. Lo único inaceptable es que no haya ninguna de las dos.
    const description = String(meal.note || '').trim().slice(0, 600);
    if (!meal.photo_path && !description) {
      return fail(res, 400, 'no_input', 'Necesito una foto o una descripción de lo que comiste.');
    }

    // Cuota antes de gastar un token. Atómica (migración 074) para que dos fotos casi
    // simultáneas no lean el mismo contador y rebasen el tope.
    const limit = dailyLimit();
    stage = 'reserve_quota';
    const { data: calls, error: quotaError } = await supabase
      .rpc('skandi_bump_ai_usage', { p_user: userId, p_limit: limit });
    if (quotaError) {
      if (/function .* does not exist/i.test(quotaError.message)) {
        return fail(res, 500, 'missing_migration', 'Falta correr la migración 074_skandi_ai_quota_rpc.sql en Supabase.');
      }
      throw quotaError;
    }
    if (calls === -1) {
      return fail(res, 429, 'quota_exceeded', `Llegaste al tope de ${limit} análisis por día. Puedes capturar la comida a mano.`);
    }
    quotaSpent = true;

    let imageBlock = null;
    if (meal.photo_path) {
      stage = 'download_photo';
      const mediaType = mediaTypeFor(meal.photo_path);
      if (!mediaType) {
        await markFailed(mealId, 'Formato de imagen no soportado');
        return fail(res, 400, 'bad_format', 'Formato de imagen no soportado. Sube JPEG o PNG.');
      }

      const { data: blob, error: downloadError } = await supabase.storage.from(BUCKET).download(meal.photo_path);
      if (downloadError || !blob) {
        await markFailed(mealId, downloadError ? downloadError.message : 'foto no encontrada');
        return fail(res, 404, 'photo_missing', 'No pudimos leer la foto del bucket.');
      }

      const bytes = Buffer.from(await blob.arrayBuffer());
      if (bytes.length > MAX_IMAGE_BYTES) {
        await markFailed(mealId, 'imagen demasiado grande');
        return fail(res, 413, 'photo_too_big', 'La foto pesa demasiado. Vuelve a tomarla.');
      }
      imageBlock = { type: 'image', source: { type: 'base64', media_type: mediaType, data: bytes.toString('base64') } };
    }

    stage = 'load_catalog';
    const { data: foods } = await supabase
      .from('skandi_foods')
      .select('id,name,brand,serving_label,serving_grams,kcal_100g,protein_100g,carbs_100g,fat_100g')
      .or(`user_id.eq.${userId},user_id.is.null`)
      .order('times_used', { ascending: false })
      .limit(CATALOG_SIZE);

    const hints = [`Comida registrada como: ${meal.meal_type}.`, `Lugar: ${VENUE_LABELS[meal.venue] || VENUE_LABELS.otro}.`];
    if (description) {
      hints.push(imageBlock
        ? `El usuario describió el plato así: "${description}". Esa descripción manda sobre lo que creas ver en la foto.`
        : `No hay foto. El usuario describió lo que comió así: "${description}".`);
    }
    hints.push(imageBlock ? 'Desglosa los alimentos.' : 'Desglosa los alimentos de esa descripción.');

    stage = 'anthropic';
    const anthropic = new Anthropic({ apiKey, timeout: AI_TIMEOUT_MS, maxRetries: 0 });
    const response = await anthropic.messages.create({
      model: process.env.MEAL_AI_MODEL || DEFAULT_MODEL,
      max_tokens: AI_MAX_TOKENS,
      // El prompt y el catálogo son el prefijo estable entre comidas del mismo usuario; la
      // foto va después. Marcar el último bloque estable cachea todo lo anterior.
      system: [
        { type: 'text', text: SYSTEM_PROMPT },
        { type: 'text', text: catalogBlock(foods || []), cache_control: { type: 'ephemeral' } },
      ],
      // effort bajo: estimar una porción no necesita razonamiento profundo y es la mitad del
      // costo. El thinking adaptativo se queda encendido (default de Opus 5).
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema: MEAL_SCHEMA },
      },
      messages: [{
        role: 'user',
        content: imageBlock
          ? [imageBlock, { type: 'text', text: hints.join(' ') }]
          : [{ type: 'text', text: hints.join(' ') }],
      }],
    });

    if (response.stop_reason === 'refusal') {
      await markFailed(mealId, 'el modelo declinó analizar la foto');
      return fail(res, 422, 'refused', 'El modelo no pudo analizar esta foto. Captúrala a mano.');
    }

    const textBlock = response.content.find(b => b.type === 'text');
    if (!textBlock) {
      await markFailed(mealId, 'respuesta sin texto');
      return fail(res, 502, 'empty_response', 'El análisis vino vacío. Intenta de nuevo.');
    }
    const parsed = JSON.parse(textBlock.text);

    if (!parsed.is_food || !Array.isArray(parsed.items) || !parsed.items.length) {
      await markFailed(mealId, parsed.notes || 'la foto no parece comida');
      return fail(res, 422, 'not_food', parsed.notes || 'La foto no parece comida. Captúrala a mano si te la comiste.');
    }

    const catalogIds = new Set((foods || []).map(f => f.id));
    // El aceite llega palomeado solo donde el usuario no lo controla. En casa cocina sin
    // aceite, así que el renglón se crea (para poder prenderlo si sí usó) pero apagado.
    const fatIncludedByDefault = meal.venue !== 'casa';
    const items = parsed.items.slice(0, 30).map((item, i) => ({
      label: String(item.label || 'Alimento').slice(0, 120),
      grams: clamp(item.grams, 5000),
      kcal: clamp(item.kcal, 10000),
      protein_g: clamp(item.protein_g, 1000),
      carbs_g: clamp(item.carbs_g, 1000),
      fat_g: clamp(item.fat_g, 1000),
      fiber_g: clamp(item.fiber_g, 1000),
      sugar_g: clamp(item.sugar_g, 1000),
      // Solo aceptamos un id que de verdad esté en el catálogo que le mandamos: un id
      // inventado rompería la llave foránea y tiraría el insert completo.
      food_id: catalogIds.has(item.catalog_id) ? item.catalog_id : '',
      source: 'ai',
      ai_confidence: Math.max(0, Math.min(1, Number(item.confidence) || 0)),
      sort_order: i + 1,
      is_cooking_fat: item.is_cooking_fat === true,
      included: item.is_cooking_fat === true ? fatIncludedByDefault : true,
    }));

    stage = 'save_items';
    const { error: saveError } = await supabase.rpc('skandi_save_meal_items', {
      p_meal_id: mealId,
      p_items: items,
      p_status: 'ready',
      p_confidence: Math.max(0, Math.min(1, Number(parsed.confidence) || 0)),
    });
    if (saveError) {
      await markFailed(mealId, saveError.message);
      throw saveError;
    }

    const usage = response.usage || {};
    console.log('[skandi/analyze] success', {
      mealId,
      inputKind: meal.input_kind,
      elapsedMs: Date.now() - startedAt,
      inputTokens: usage.input_tokens,
      outputTokens: usage.output_tokens,
    });
    return res.status(200).json({
      ok: true,
      dish_name: String(parsed.dish_name || '').slice(0, 120),
      notes: String(parsed.notes || '').slice(0, 500),
      confidence: Number(parsed.confidence) || 0,
      items,
      quota: { used: calls, limit },
      usage: {
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        cache_read_input_tokens: usage.cache_read_input_tokens,
      },
    });
  } catch (err) {
    const status = Number(err && err.status) || 0;
    const retryable = err instanceof Anthropic.RateLimitError
      || (err instanceof Anthropic.APIError && status >= 500)
      || ['APIConnectionError', 'APIConnectionTimeoutError'].includes(err && err.name);
    console.error('[skandi/analyze] failed', {
      mealId,
      stage,
      elapsedMs: Date.now() - startedAt,
      name: err && err.name,
      status,
      retryable,
      message: err && err.message,
    });
    // El error fue nuestro, no del usuario: devolvemos la llamada a su cuota del día.
    if (quotaSpent && userId) {
      try { await supabase.rpc('skandi_refund_ai_usage', { p_user: userId }); } catch { /* mejor esfuerzo */ }
    }
    if (mealId) {
      try { await markFailed(mealId, err.message); } catch { /* mejor esfuerzo */ }
    }
    if (err instanceof Anthropic.RateLimitError) {
      return res.status(429).json({ error: 'ai_rate_limited', message: 'La IA está saturada ahora mismo. Reintentaremos automáticamente.', retryable: true });
    }
    if (err instanceof Anthropic.AuthenticationError) {
      return fail(res, 500, 'bad_api_key', 'La ANTHROPIC_API_KEY de Vercel no es válida.');
    }
    if (err instanceof Anthropic.APIError) {
      return res.status(502).json({ error: 'ai_error', message: `La IA respondió con un error (${err.status}).`, retryable });
    }
    if (retryable) return res.status(502).json({ error: 'ai_connection', message: 'La conexión con la IA se interrumpió.', retryable: true });
    return fail(res, 500, 'server_error', 'No pudimos analizar la foto. Intenta de nuevo.');
  }
}


// ── Código de barras (Open Food Facts) ──────────────────────────────────────


const OFF_BASE = 'https://world.openfoodfacts.org/api/v2/product';
const OFF_FIELDS = 'code,product_name,product_name_es,brands,quantity,serving_size,serving_quantity,nutriments';
// Open Food Facts pide identificarse en el User-Agent; sin esto pueden limitar o bloquear.
const OFF_UA = 'SkandiFit/1.0 (https://habittraininghub.app)';
const OFF_TIMEOUT_MS = 8000;


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

async function lookupBarcode(req, res) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return fail(res, 500, 'missing_supabase_env', 'Falta configurar SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.');
  }

  try {
    const userId = await requireUser(req, res);
    if (!userId) return;

    const barcode = String((req.body && req.body.barcode) || '').replace(/\D/g, '');
    if (barcode.length < 8 || barcode.length > 14) {
      return fail(res, 400, 'bad_barcode', 'Ese código de barras no parece válido.');
    }

    // 1. ¿Ya lo tenemos? El catálogo propio manda sobre el global.
    const { data: known, error: knownError } = await supabase
      .from('skandi_foods')
      .select('id,user_id,name,brand,barcode,serving_label,serving_grams,kcal_100g,protein_100g,carbs_100g,fat_100g,fiber_100g,sugar_100g,source')
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
      sugar_100g: Math.min(num(nutriments.sugars_100g) || 0, 100),
      source: 'off',
    };

    const { data: saved, error: saveError } = await supabase
      .from('skandi_foods')
      .insert(food)
      .select('id,user_id,name,brand,barcode,serving_label,serving_grams,kcal_100g,protein_100g,carbs_100g,fat_100g,fiber_100g,sugar_100g,source')
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
}

// ── Strava ──────────────────────────────────────────────────────────────────
//
// El reloj Garmin sincroniza solo a Strava; de Strava jalamos nosotros. Cinco acciones en
// este mismo archivo por la misma razón de plataforma que arriba: no sobran funciones.
//
//   POST { action:'strava-connect' }        -> URL de autorización (JWT)
//   GET  /api/strava/callback               -> Strava regresa aquí con el code (sin JWT)
//   GET  /api/strava/webhook                -> el reto hub.challenge de la suscripción
//   POST /api/strava/webhook                -> un evento de actividad (sin JWT)
//   POST { action:'strava-sync' }           -> jalón manual / respaldo del webhook (JWT)
//   POST { action:'strava-disconnect' }     -> revoca en Strava y borra los tokens (JWT)
//   POST { action:'strava-subscription' }   -> alta/baja/consulta del webhook (JWT + admin)
//
// Los tokens viven en `skandi_integrations`, cuya RLS niega todo: solo la service-role de
// este archivo los toca (migración 081). El cliente nunca ve un access_token.

const crypto = require('crypto');
const SkandiStrava = require('../skandi-strava.js');
const SkandiIntervals = require('../skandi-intervals.js');

const STRAVA_AUTH_URL = 'https://www.strava.com/oauth/authorize';
const STRAVA_TOKEN_URL = 'https://www.strava.com/oauth/token';
const STRAVA_DEAUTH_URL = 'https://www.strava.com/oauth/deauthorize';
const STRAVA_API = 'https://www.strava.com/api/v3';

// activity:read_all y no activity:read: sin el _all, las actividades marcadas como privadas
// en Strava no se ven, y un entrenamiento privado es justo el que uno no quiere perder.
const STRAVA_SCOPE = 'activity:read_all';

const STATE_TTL_MS = 15 * 60e3;   // el usuario tarda segundos; 15 min es holgura, no permiso
const TOKEN_SKEW_SEC = 300;       // renueva 5 min antes de que expire, no cuando ya expiró
const SYNC_DEFAULT_DAYS = 30;
const SYNC_MAX_DAYS = 730;
const SYNC_PAGE = 100;
const SYNC_MAX_PAGES = 10;        // 1000 actividades por jalón; más que eso es paginar a mano

function stravaEnvOk() {
  return Boolean(process.env.STRAVA_CLIENT_ID && process.env.STRAVA_CLIENT_SECRET);
}

function appUrl() {
  return String(process.env.PUBLIC_APP_URL || 'https://habittraininghub.app').replace(/\/+$/, '');
}

function redirectUri() {
  return `${appUrl()}/api/strava/callback`;
}

// El `state` de OAuth tiene que decirnos de quién es el code que Strava nos regresa, y el
// callback llega sin sesión: no hay JWT que consultar. Va firmado con HMAC para que nadie
// pueda pedir "conecta esta cuenta de Strava a ESTE otro usuario" fabricando un state.
function signState(userId) {
  const payload = `${userId}.${Date.now() + STATE_TTL_MS}`;
  const sig = crypto.createHmac('sha256', process.env.SUPABASE_SERVICE_ROLE_KEY)
    .update(payload).digest('hex').slice(0, 32);
  return `${payload}.${sig}`;
}

function readState(state) {
  const parts = String(state || '').split('.');
  if (parts.length !== 3) return null;
  const [userId, expires, sig] = parts;
  const expected = crypto.createHmac('sha256', process.env.SUPABASE_SERVICE_ROLE_KEY)
    .update(`${userId}.${expires}`).digest('hex').slice(0, 32);
  // timingSafeEqual exige el mismo largo; con hex de largo fijo, comparar el largo primero
  // no filtra nada que el atacante no sepa ya.
  if (sig.length !== expected.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  if (Number(expires) < Date.now()) return null;
  return userId;
}

async function stravaToken(params) {
  const body = new URLSearchParams({
    client_id: process.env.STRAVA_CLIENT_ID,
    client_secret: process.env.STRAVA_CLIENT_SECRET,
    ...params,
  });
  const r = await fetch(STRAVA_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    const detail = (data && (data.message || data.error)) || `HTTP ${r.status}`;
    throw new Error(`Strava rechazó el token: ${detail}`);
  }
  return data;
}

// Un access_token de Strava dura 6 horas. Renovarlo es barato y silencioso; que caduque en
// medio de un webhook no lo es, así que se renueva por adelantado y se guarda de inmediato.
async function freshAccessToken(integration) {
  const expiresMs = new Date(integration.expires_at).getTime();
  if (expiresMs - Date.now() > TOKEN_SKEW_SEC * 1000) return integration.access_token;

  const data = await stravaToken({
    grant_type: 'refresh_token',
    refresh_token: integration.refresh_token,
  });
  await supabase.from('skandi_integrations').update({
    access_token: data.access_token,
    // Strava rota el refresh_token en cada renovación: guardar el nuevo no es opcional.
    refresh_token: data.refresh_token || integration.refresh_token,
    expires_at: new Date(data.expires_at * 1000).toISOString(),
    last_error: null,
  }).eq('user_id', integration.user_id).eq('provider', 'strava');

  return data.access_token;
}

async function stravaGet(token, path, params) {
  const url = new URL(STRAVA_API + path);
  Object.entries(params || {}).forEach(([k, v]) => url.searchParams.set(k, String(v)));
  const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (r.status === 429) throw new Error('Strava está limitando las peticiones. Intenta en unos minutos.');
  if (!r.ok) throw new Error(`Strava respondió ${r.status} en ${path}`);
  return r.json();
}

async function maxHeartRateOf(userId) {
  const { data } = await supabase
    .from('skandi_settings').select('max_heart_rate').eq('user_id', userId).maybeSingle();
  return (data && data.max_heart_rate) || null;
}

// Guarda un lote de actividades de Strava. Devuelve el conteo de lo que hizo con cada una.
//
// No es un upsert de una línea a propósito: una actividad que ya está aquí pudo haber sido
// corregida a mano (el miembro tocó el esfuerzo porque el reloj no traía pulso), y un upsert
// ciego borraría esa corrección cada vez que Strava reenvía la misma actividad. Lo que Strava
// sí sabe mejor —distancia, tiempo, desnivel, nombre— se actualiza siempre.
async function importStravaActivities(userId, activities) {
  const maxHeartRate = await maxHeartRateOf(userId);
  const rows = (activities || [])
    .map(a => SkandiStrava.toActivityRow(a, { userId, maxHeartRate }))
    .filter(Boolean);
  const result = { imported: 0, updated: 0, skipped: (activities || []).length - rows.length };
  if (!rows.length) return result;

  const { data: existing } = await supabase
    .from('skandi_external_activities')
    .select('id,external_id,intensity_source')
    .eq('user_id', userId)
    .eq('external_source', 'strava')
    .in('external_id', rows.map(r => r.external_id));

  const known = new Map((existing || []).map(r => [r.external_id, r]));
  const fresh = rows.filter(r => !known.has(r.external_id));

  if (fresh.length) {
    const { error } = await supabase.from('skandi_external_activities').insert(fresh);
    if (error) throw new Error(error.message);
    result.imported = fresh.length;
  }

  for (const row of rows) {
    const prev = known.get(row.external_id);
    if (!prev) continue;
    const patch = { ...row };
    delete patch.user_id;
    delete patch.external_source;
    delete patch.external_id;
    if (prev.intensity_source === 'manual') {
      // Lo puso una persona (aquí o en Strava). No se pisa.
      delete patch.intensity;
      delete patch.intensity_source;
    }
    const { error } = await supabase
      .from('skandi_external_activities').update(patch).eq('id', prev.id);
    if (error) throw new Error(error.message);
    result.updated += 1;
  }

  return result;
}

async function integrationFor(match) {
  const { data } = await supabase
    .from('skandi_integrations').select('*').eq('provider', 'strava').match(match).maybeSingle();
  return data || null;
}

// ---- Acciones ----

async function stravaConnect(req, res) {
  if (!stravaEnvOk()) {
    return fail(res, 500, 'missing_strava_env', 'Faltan STRAVA_CLIENT_ID / STRAVA_CLIENT_SECRET en el servidor.');
  }
  const userId = await requireUser(req, res);
  if (!userId) return;

  const url = new URL(STRAVA_AUTH_URL);
  url.searchParams.set('client_id', process.env.STRAVA_CLIENT_ID);
  url.searchParams.set('redirect_uri', redirectUri());
  url.searchParams.set('response_type', 'code');
  // force: si el usuario ya autorizó, Strava saltaría la pantalla y devolvería los mismos
  // permisos de antes. Reconectar suele ser justo porque algo quedó mal, así que se pregunta.
  url.searchParams.set('approval_prompt', 'force');
  url.searchParams.set('scope', STRAVA_SCOPE);
  url.searchParams.set('state', signState(userId));

  return res.status(200).json({ ok: true, url: url.toString() });
}

function backToApp(res, params) {
  const url = new URL(`${appUrl()}/skandi`);
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  res.setHeader('Location', url.toString());
  return res.status(302).end();
}

// Strava manda al navegador aquí. No hay sesión de Supabase en esta petición: quien dice de
// quién es el code es el `state` firmado, nada más.
async function stravaCallback(req, res) {
  const q = req.query || {};
  if (q.error) return backToApp(res, { strava: 'error', reason: String(q.error) });
  if (!stravaEnvOk()) return backToApp(res, { strava: 'error', reason: 'missing_env' });

  const userId = readState(q.state);
  if (!userId) return backToApp(res, { strava: 'error', reason: 'bad_state' });

  const granted = String(q.scope || '');
  if (!granted.includes('activity:read')) {
    return backToApp(res, { strava: 'error', reason: 'no_scope' });
  }

  try {
    const data = await stravaToken({ grant_type: 'authorization_code', code: String(q.code || '') });
    const athleteId = String((data.athlete && data.athlete.id) || '');
    if (!athleteId) return backToApp(res, { strava: 'error', reason: 'no_athlete' });

    const { error } = await supabase.from('skandi_integrations').upsert({
      user_id: userId,
      provider: 'strava',
      athlete_id: athleteId,
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      expires_at: new Date(data.expires_at * 1000).toISOString(),
      scope: granted,
      connected_at: new Date().toISOString(),
      last_error: null,
    }, { onConflict: 'user_id,provider' });

    if (error) {
      // El índice único de athlete_id: esa cuenta de Strava ya es de otro miembro.
      const reason = error.code === '23505' ? 'athlete_taken' : 'save_failed';
      console.error('strava-callback: no se pudo guardar', error.message);
      return backToApp(res, { strava: 'error', reason });
    }
    return backToApp(res, { strava: 'ok' });
  } catch (err) {
    console.error('strava-callback error:', err);
    return backToApp(res, { strava: 'error', reason: 'token_exchange' });
  }
}

async function stravaSync(req, res) {
  if (!stravaEnvOk()) {
    return fail(res, 500, 'missing_strava_env', 'Faltan STRAVA_CLIENT_ID / STRAVA_CLIENT_SECRET en el servidor.');
  }
  const userId = await requireUser(req, res);
  if (!userId) return;

  const integration = await integrationFor({ user_id: userId });
  if (!integration) return fail(res, 409, 'not_connected', 'Conecta Strava primero.');

  const requested = Number((req.body && req.body.days) || 0);
  const days = requested > 0 ? Math.min(requested, SYNC_MAX_DAYS) : SYNC_DEFAULT_DAYS;
  const after = Math.floor((Date.now() - days * 864e5) / 1000);

  try {
    const token = await freshAccessToken(integration);
    const totals = { imported: 0, updated: 0, skipped: 0 };

    for (let page = 1; page <= SYNC_MAX_PAGES; page++) {
      const batch = await stravaGet(token, '/athlete/activities',
        { after, per_page: SYNC_PAGE, page });
      if (!Array.isArray(batch) || !batch.length) break;
      const r = await importStravaActivities(userId, batch);
      totals.imported += r.imported;
      totals.updated += r.updated;
      totals.skipped += r.skipped;
      if (batch.length < SYNC_PAGE) break;
    }

    await supabase.from('skandi_integrations')
      .update({ last_sync_at: new Date().toISOString(), last_error: null })
      .eq('user_id', userId).eq('provider', 'strava');

    return res.status(200).json({ ok: true, days, ...totals });
  } catch (err) {
    console.error('strava-sync error:', err);
    await supabase.from('skandi_integrations')
      .update({ last_error: String(err.message).slice(0, 300) })
      .eq('user_id', userId).eq('provider', 'strava');
    return fail(res, 502, 'strava_failed', err.message);
  }
}

async function stravaDisconnect(req, res) {
  const userId = await requireUser(req, res);
  if (!userId) return;

  const integration = await integrationFor({ user_id: userId });
  if (integration) {
    // Revocar en Strava es lo correcto aunque falle: si no lo hacemos, la app se queda
    // autorizada en la cuenta del usuario para siempre. Si Strava no contesta, seguimos
    // borrando de nuestro lado — dejar los tokens aquí sería lo peor de los dos mundos.
    try {
      await fetch(STRAVA_DEAUTH_URL, {
        method: 'POST',
        headers: { Authorization: `Bearer ${integration.access_token}` },
      });
    } catch (err) {
      console.warn('strava-disconnect: deauthorize falló', err.message);
    }
  }
  const { error } = await supabase.from('skandi_integrations')
    .delete().eq('user_id', userId).eq('provider', 'strava');
  if (error) return fail(res, 500, 'delete_failed', error.message);

  // Las actividades ya importadas se quedan: son entrenamientos que sí ocurrieron, y el
  // historial de fatiga del miembro no tiene por qué reescribirse porque desconectó un reloj.
  return res.status(200).json({ ok: true });
}

// ---- Webhook ----

// Strava valida la suscripción con un GET y espera de vuelta el mismo hub.challenge.
function webhookChallenge(req, res) {
  const q = req.query || {};
  const token = process.env.STRAVA_WEBHOOK_VERIFY_TOKEN;
  if (q['hub.mode'] !== 'subscribe' || !token || q['hub.verify_token'] !== token) {
    return res.status(403).json({ ok: false, reason: 'bad_verify_token' });
  }
  return res.status(200).json({ 'hub.challenge': String(q['hub.challenge'] || '') });
}

async function applyWebhookEvent(event) {
  if (event.object_type !== 'activity') return;
  const externalId = String(event.object_id);

  const integration = await integrationFor({ athlete_id: String(event.owner_id) });
  if (!integration) return; // un atleta que ya se desconectó; no es un error

  if (event.aspect_type === 'delete') {
    await supabase.from('skandi_external_activities').delete()
      .eq('user_id', integration.user_id)
      .eq('external_source', 'strava')
      .eq('external_id', externalId);
    return;
  }

  // Strava manda avisos de deautorización por este mismo canal.
  if (event.updates && event.updates.authorized === 'false') {
    await supabase.from('skandi_integrations').delete()
      .eq('user_id', integration.user_id).eq('provider', 'strava');
    return;
  }

  const token = await freshAccessToken(integration);
  const activity = await stravaGet(token, `/activities/${externalId}`, {});
  await importStravaActivities(integration.user_id, [activity]);
}

async function stravaWebhook(req, res) {
  if (req.method === 'GET') return webhookChallenge(req, res);

  // Strava exige un 200 en menos de dos segundos y no reintenta con ganas. Se contesta
  // primero y se trabaja después: en el runtime Node de Vercel la invocación sigue viva
  // hasta que el handler resuelve, aunque la respuesta ya haya salido. Si aun así se cortara,
  // el jalón manual de `strava-sync` recoge lo que se haya perdido — por eso existe.
  res.status(200).json({ ok: true });

  try {
    await applyWebhookEvent(req.body || {});
  } catch (err) {
    console.error('strava-webhook error:', err, JSON.stringify(req.body || {}));
  }
}

// El alta de la suscripción es una sola vez en la vida de la app, no por usuario. Vive aquí y
// no en un curl para que no haga falta tener el client_secret en la laptop de nadie.
async function stravaSubscription(req, res) {
  if (!stravaEnvOk()) {
    return fail(res, 500, 'missing_strava_env', 'Faltan STRAVA_CLIENT_ID / STRAVA_CLIENT_SECRET en el servidor.');
  }
  if (!process.env.STRAVA_WEBHOOK_VERIFY_TOKEN) {
    return fail(res, 500, 'missing_verify_token', 'Falta STRAVA_WEBHOOK_VERIFY_TOKEN en el servidor.');
  }
  const userId = await requireUser(req, res);
  if (!userId) return;

  const { data: profile } = await supabase
    .from('profiles').select('role').eq('id', userId).maybeSingle();
  if (!profile || profile.role !== 'admin') {
    return fail(res, 403, 'not_admin', 'Solo un administrador puede tocar la suscripción del webhook.');
  }

  const op = String((req.body && req.body.op) || 'list');
  const creds = {
    client_id: process.env.STRAVA_CLIENT_ID,
    client_secret: process.env.STRAVA_CLIENT_SECRET,
  };
  const base = `${STRAVA_API}/push_subscriptions`;

  try {
    if (op === 'create') {
      const body = new URLSearchParams({
        ...creds,
        callback_url: `${appUrl()}/api/strava/webhook`,
        verify_token: process.env.STRAVA_WEBHOOK_VERIFY_TOKEN,
      });
      const r = await fetch(base, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) return fail(res, 502, 'subscribe_failed', JSON.stringify(data));
      return res.status(200).json({ ok: true, subscription: data });
    }

    if (op === 'delete') {
      const id = String((req.body && req.body.id) || '');
      if (!id) return fail(res, 400, 'no_id', 'Falta el id de la suscripción.');
      const url = new URL(`${base}/${encodeURIComponent(id)}`);
      Object.entries(creds).forEach(([k, v]) => url.searchParams.set(k, v));
      const r = await fetch(url, { method: 'DELETE' });
      if (!r.ok) return fail(res, 502, 'unsubscribe_failed', `HTTP ${r.status}`);
      return res.status(200).json({ ok: true });
    }

    const url = new URL(base);
    Object.entries(creds).forEach(([k, v]) => url.searchParams.set(k, v));
    const r = await fetch(url);
    const data = await r.json().catch(() => ([]));
    if (!r.ok) return fail(res, 502, 'list_failed', JSON.stringify(data));
    return res.status(200).json({ ok: true, subscriptions: data });
  } catch (err) {
    console.error('strava-subscription error:', err);
    return fail(res, 502, 'strava_failed', err.message);
  }
}


// ── Intervals.icu ───────────────────────────────────────────────────────────
// Garmin Connect sube al reloj a Intervals.icu y nosotros leemos únicamente esas actividades.
// La API key nunca vuelve al cliente: se cifra con AES-GCM y la tabla tiene RLS sin políticas.

const INTERVALS_API = 'https://intervals.icu/api/v1';
const INTERVALS_FIELDS = [
  'id','start_date','start_date_local','type','name','distance','moving_time','elapsed_time',
  'total_elevation_gain','average_heartrate','max_heartrate','calories','perceived_exertion',
  'icu_rpe','session_rpe','athlete_max_hr','device_name','source',
].join(',');

function intervalsKey() {
  return crypto.createHash('sha256')
    .update(String(process.env.SUPABASE_SERVICE_ROLE_KEY || ''))
    .digest();
}

function encryptIntervalsKey(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', intervalsKey(), iv);
  const encrypted = Buffer.concat([cipher.update(String(value), 'utf8'), cipher.final()]);
  return ['v1', iv.toString('hex'), cipher.getAuthTag().toString('hex'), encrypted.toString('hex')].join('.');
}

function decryptIntervalsKey(value) {
  const [version, ivHex, tagHex, encryptedHex] = String(value || '').split('.');
  if (version !== 'v1' || !ivHex || !tagHex || !encryptedHex) throw new Error('Credencial inválida; vuelve a conectar Intervals.icu.');
  const decipher = crypto.createDecipheriv('aes-256-gcm', intervalsKey(), Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  return Buffer.concat([decipher.update(Buffer.from(encryptedHex, 'hex')), decipher.final()]).toString('utf8');
}

async function intervalsGet(apiKey, path, params) {
  const url = new URL(INTERVALS_API + path);
  Object.entries(params || {}).forEach(([key, value]) => url.searchParams.set(key, String(value)));
  const auth = Buffer.from(`API_KEY:${apiKey}`).toString('base64');
  const response = await fetch(url, { headers: { Authorization: `Basic ${auth}` } });
  if (response.status === 401 || response.status === 403) throw new Error('Intervals.icu rechazó la API key. Revísala y vuelve a conectar.');
  if (response.status === 429) throw new Error('Intervals.icu está limitando las peticiones. Intenta en unos minutos.');
  const data = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`Intervals.icu respondió ${response.status}.`);
  return data;
}

async function intervalsCredential(userId) {
  const { data, error } = await supabase.from('skandi_intervals_credentials')
    .select('*').eq('user_id', userId).maybeSingle();
  if (error) throw new Error(error.message);
  return data || null;
}

async function importIntervalsActivities(userId, activities) {
  const maxHeartRate = await maxHeartRateOf(userId);
  const rows = (activities || [])
    .map(activity => SkandiIntervals.toActivityRow(activity, { userId, maxHeartRate }))
    .filter(Boolean);
  const result = { imported: 0, updated: 0, skipped: (activities || []).length - rows.length };
  if (!rows.length) return result;

  const { data: existing, error: readError } = await supabase
    .from('skandi_external_activities')
    .select('id,external_id,intensity_source')
    .eq('user_id', userId).eq('external_source', 'intervals')
    .in('external_id', rows.map(row => row.external_id));
  if (readError) throw new Error(readError.message);

  const known = new Map((existing || []).map(row => [row.external_id, row]));
  const fresh = rows.filter(row => !known.has(row.external_id));
  if (fresh.length) {
    const { error } = await supabase.from('skandi_external_activities').insert(fresh);
    if (error) throw new Error(error.message);
    result.imported = fresh.length;
  }

  for (const row of rows) {
    const previous = known.get(row.external_id);
    if (!previous) continue;
    const patch = { ...row };
    delete patch.user_id;
    delete patch.external_source;
    delete patch.external_id;
    if (previous.intensity_source === 'manual') {
      delete patch.intensity;
      delete patch.intensity_source;
    }
    const { error } = await supabase.from('skandi_external_activities')
      .update(patch).eq('id', previous.id);
    if (error) throw new Error(error.message);
    result.updated += 1;
  }
  return result;
}

async function linkIntervalsStrengthActivities(userId, activities) {
  const strength = (activities || []).filter(SkandiIntervals.isStrengthActivity);
  if (!strength.length) return { matched_strength: 0, unmatched_strength: 0 };
  const starts = strength.map(a => new Date(a.start_date || a.start_date_local).getTime()).filter(Number.isFinite);
  if (!starts.length) return { matched_strength: 0, unmatched_strength: strength.length };
  const from = new Date(Math.min(...starts) - 6 * 3600e3).toISOString();
  const to = new Date(Math.max(...starts) + 30 * 3600e3).toISOString();
  const { data: sessions, error } = await supabase.from('skandi_sessions')
    .select('id,started_at,completed_at,duration_sec,duration_source,garmin_external_id')
    .eq('user_id', userId).not('completed_at', 'is', null)
    .gte('started_at', from).lte('started_at', to);
  if (error) throw new Error(error.message);

  const maxHeartRate = await maxHeartRateOf(userId);
  const linked = SkandiIntervals.matchStrengthActivities(strength, sessions || [], { maxHeartRate });
  for (const { session, metric } of linked.matches) {
    const patch = {
      garmin_external_id: metric.externalId,
      garmin_started_at: metric.startedAt,
      garmin_duration_sec: metric.durationSec,
      garmin_avg_heart_rate: metric.avgHeartRate,
      garmin_max_heart_rate: metric.maxHeartRate,
      garmin_calories: metric.calories,
      garmin_intensity: metric.intensity,
      garmin_intensity_source: metric.intensitySource,
      garmin_device_name: metric.deviceName,
      garmin_activity_name: metric.activityName,
      garmin_synced_at: new Date().toISOString(),
    };
    // Una duración corregida por la persona manda. Si todavía viene del cronómetro de
    // Skandi (o de un Garmin anterior), el intervalo completo medido por el reloj es mejor.
    if (session.duration_source !== 'manual') {
      patch.started_at = metric.startedAt;
      patch.completed_at = new Date(new Date(metric.startedAt).getTime() + metric.durationSec * 1000).toISOString();
      patch.duration_sec = metric.durationSec;
      patch.duration_source = 'garmin';
    }
    const { error: updateError } = await supabase.from('skandi_sessions')
      .update(patch).eq('id', session.id).eq('user_id', userId);
    if (updateError) throw new Error(updateError.message);
  }
  return { matched_strength: linked.matches.length, unmatched_strength: linked.unmatched };
}

async function intervalsConnect(req, res) {
  const userId = await requireUser(req, res);
  if (!userId) return;
  const apiKey = String(req.body && req.body.api_key || '').trim();
  if (apiKey.length < 12 || apiKey.length > 300) return fail(res, 400, 'bad_api_key', 'Escribe una API key válida de Intervals.icu.');

  try {
    const athlete = await intervalsGet(apiKey, '/athlete/0');
    const athleteId = String(athlete && athlete.id || '').trim();
    if (!athleteId) return fail(res, 502, 'no_athlete', 'Intervals.icu no devolvió el atleta.');
    const { error } = await supabase.from('skandi_intervals_credentials').upsert({
      user_id: userId, athlete_id: athleteId,
      api_key_ciphertext: encryptIntervalsKey(apiKey),
      connected_at: new Date().toISOString(), last_error: null,
    }, { onConflict: 'user_id' });
    if (error) {
      const message = error.code === '23505'
        ? 'Esa cuenta de Intervals.icu ya está conectada a otro miembro.' : error.message;
      return fail(res, 409, 'save_failed', message);
    }
    return res.status(200).json({ ok: true, athlete_id: athleteId });
  } catch (err) {
    console.error('intervals-connect error:', err.message);
    return fail(res, 502, 'intervals_failed', err.message);
  }
}

async function intervalsStatus(req, res) {
  const userId = await requireUser(req, res);
  if (!userId) return;
  try {
    const credential = await intervalsCredential(userId);
    if (!credential) return res.status(200).json({ ok: true, connected: false });
    const { count, error } = await supabase.from('skandi_external_activities')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId).eq('external_source', 'intervals');
    if (error) throw new Error(error.message);
    const { count: strengthLinked } = await supabase.from('skandi_sessions')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId).not('garmin_external_id', 'is', null);
    return res.status(200).json({
      ok: true, connected: true, athlete_id: credential.athlete_id,
      connected_at: credential.connected_at, last_sync_at: credential.last_sync_at,
      last_error: credential.last_error, imported: count || 0, strength_linked: strengthLinked || 0,
    });
  } catch (err) {
    console.error('intervals-status error:', err.message);
    return fail(res, 500, 'status_failed', err.message);
  }
}

async function intervalsSync(req, res) {
  const userId = await requireUser(req, res);
  if (!userId) return;
  let credential;
  try { credential = await intervalsCredential(userId); }
  catch (err) { return fail(res, 500, 'read_failed', err.message); }
  if (!credential) return fail(res, 409, 'not_connected', 'Conecta Intervals.icu primero.');

  const requested = Number(req.body && req.body.days || 0);
  const days = requested > 0 ? Math.min(Math.round(requested), SYNC_MAX_DAYS) : SYNC_DEFAULT_DAYS;
  const newest = new Date();
  const oldest = new Date(newest.getTime() - days * 864e5);
  const date = value => value.toISOString().slice(0, 10);
  try {
    const apiKey = decryptIntervalsKey(credential.api_key_ciphertext);
    const activities = await intervalsGet(apiKey,
      `/athlete/${encodeURIComponent(credential.athlete_id)}/activities`, {
        oldest: date(oldest), newest: date(newest), limit: 1000, fields: INTERVALS_FIELDS,
      });
    if (!Array.isArray(activities)) throw new Error('Intervals.icu devolvió una respuesta inesperada.');
    const totals = await importIntervalsActivities(userId, activities);
    const strengthTotals = await linkIntervalsStrengthActivities(userId, activities);
    await supabase.from('skandi_intervals_credentials')
      .update({ last_sync_at: new Date().toISOString(), last_error: null }).eq('user_id', userId);
    return res.status(200).json({ ok: true, days, ...totals, ...strengthTotals });
  } catch (err) {
    console.error('intervals-sync error:', err.message);
    await supabase.from('skandi_intervals_credentials')
      .update({ last_error: String(err.message).slice(0, 300) }).eq('user_id', userId);
    return fail(res, 502, 'intervals_failed', err.message);
  }
}

async function intervalsDisconnect(req, res) {
  const userId = await requireUser(req, res);
  if (!userId) return;
  const { error } = await supabase.from('skandi_intervals_credentials').delete().eq('user_id', userId);
  if (error) return fail(res, 500, 'delete_failed', error.message);
  return res.status(200).json({ ok: true });
}


// ── Despachador ─────────────────────────────────────────────────────────────

module.exports = async function handler(req, res) {
  // La acción llega por el body (lo normal, desde la app) o por el query string, que es como
  // la ponen los rewrites de vercel.json para las dos rutas que llama Strava y no nosotros.
  const action = String(
    (req.query && req.query.action) || (req.body && req.body.action) || 'analyze'
  );

  // Estas dos las abre Strava, no la app: llegan por GET, sin JWT y sin origen nuestro, así
  // que se atienden antes de las guardas de CORS y de POST.
  if (action === 'strava-callback') {
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET');
      return fail(res, 405, 'method_not_allowed', 'Método no permitido');
    }
    return stravaCallback(req, res);
  }
  if (action === 'strava-webhook') {
    if (req.method !== 'GET' && req.method !== 'POST') {
      res.setHeader('Allow', 'GET, POST');
      return fail(res, 405, 'method_not_allowed', 'Método no permitido');
    }
    return stravaWebhook(req, res);
  }

  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return fail(res, 405, 'method_not_allowed', 'Método no permitido');
  }

  if (action === 'barcode') return lookupBarcode(req, res);
  if (action === 'analyze') return analyzeMeal(req, res);
  if (action === 'strava-connect') return stravaConnect(req, res);
  if (action === 'strava-sync') return stravaSync(req, res);
  if (action === 'strava-disconnect') return stravaDisconnect(req, res);
  if (action === 'strava-subscription') return stravaSubscription(req, res);
  if (action === 'intervals-connect') return intervalsConnect(req, res);
  if (action === 'intervals-status') return intervalsStatus(req, res);
  if (action === 'intervals-sync') return intervalsSync(req, res);
  if (action === 'intervals-disconnect') return intervalsDisconnect(req, res);
  return fail(res, 400, 'bad_action', `Acción desconocida: ${action}`);
};
