// Skandi Fit — análisis de comida con Claude (vision + texto).
//
// Tres maneras de entrar, una sola ruta: foto, descripción escrita ("dos huevos con frijoles
// y una tortilla"), o las dos juntas — la foto con contexto es la que mejor acierta, porque
// el texto resuelve justo lo que la cámara no ve: el aceite, el relleno, si el agua era de
// sabor. El cuarto camino, código de barras, no pasa por aquí: es /api/lookup-barcode y no
// gasta IA.
//
// Contrato: el cliente ya creó la fila en skandi_meals con analysis_status='pending' (y, si
// hay foto, ya la subió al bucket privado skandi-meals). Aquí solo recibimos { meal_id }. Ese
// orden es deliberado: si el modelo tarda o falla, la comida YA quedó registrada. Un diario
// que pierde entradas por un timeout no se usa dos semanas.
//
// Seguridad: la ANTHROPIC_API_KEY vive solo aquí. El cliente nunca habla con Anthropic, y la
// foto se descarga con service-role porque el bucket es privado (migración 073).

const { createClient } = require('@supabase/supabase-js');
const Anthropic = require('@anthropic-ai/sdk');

const BUCKET = 'skandi-meals';
const DEFAULT_DAILY_LIMIT = 25;
const DEFAULT_MODEL = 'claude-opus-5';
const MAX_IMAGE_BYTES = 4.5 * 1024 * 1024; // el límite de la API de vision es 5 MB por imagen
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

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

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
          confidence: { type: 'number' },
          catalog_id: { type: 'string', description: 'id del alimento del catálogo, o cadena vacía' },
          is_cooking_fat: { type: 'boolean', description: 'true solo para el renglón de aceite/grasa de cocción' },
        },
        required: ['label', 'grams', 'kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'confidence', 'catalog_id', 'is_cooking_fat'],
        additionalProperties: false,
      },
    },
  },
  required: ['is_food', 'dish_name', 'confidence', 'notes', 'items'],
  additionalProperties: false,
};

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', 'https://habittraininghub.app');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function fail(res, status, reason, message) {
  return res.status(status).json({ ok: false, reason, message });
}

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

module.exports = async function handler(req, res) {
  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return fail(res, 405, 'method_not_allowed', 'Método no permitido');
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return fail(res, 500, 'missing_api_key', 'Falta configurar ANTHROPIC_API_KEY en Vercel.');
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return fail(res, 500, 'missing_supabase_env', 'Falta configurar SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.');
  }

  let userId = null;
  let quotaSpent = false;
  let mealId = null;

  try {
    const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
    if (!token) return fail(res, 401, 'no_session', 'Sesión requerida');

    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return fail(res, 401, 'bad_session', 'Sesión inválida');
    userId = authData.user.id;

    mealId = String((req.body && req.body.meal_id) || '').trim();
    if (!mealId) return fail(res, 400, 'no_meal_id', 'Falta meal_id');

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

    const anthropic = new Anthropic({ apiKey });
    const response = await anthropic.messages.create({
      model: process.env.MEAL_AI_MODEL || DEFAULT_MODEL,
      max_tokens: 4000,
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
      // Solo aceptamos un id que de verdad esté en el catálogo que le mandamos: un id
      // inventado rompería la llave foránea y tiraría el insert completo.
      food_id: catalogIds.has(item.catalog_id) ? item.catalog_id : '',
      source: 'ai',
      ai_confidence: Math.max(0, Math.min(1, Number(item.confidence) || 0)),
      sort_order: i + 1,
      is_cooking_fat: item.is_cooking_fat === true,
      included: item.is_cooking_fat === true ? fatIncludedByDefault : true,
    }));

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
    console.error('analyze-meal error:', err);
    // El error fue nuestro, no del usuario: devolvemos la llamada a su cuota del día.
    if (quotaSpent && userId) {
      try { await supabase.rpc('skandi_refund_ai_usage', { p_user: userId }); } catch { /* mejor esfuerzo */ }
    }
    if (mealId) {
      try { await markFailed(mealId, err.message); } catch { /* mejor esfuerzo */ }
    }
    if (err instanceof Anthropic.RateLimitError) {
      return fail(res, 429, 'ai_rate_limited', 'La IA está saturada ahora mismo. Intenta en un minuto.');
    }
    if (err instanceof Anthropic.AuthenticationError) {
      return fail(res, 500, 'bad_api_key', 'La ANTHROPIC_API_KEY de Vercel no es válida.');
    }
    if (err instanceof Anthropic.APIError) {
      return fail(res, 502, 'ai_error', `La IA respondió con un error (${err.status}). Intenta de nuevo.`);
    }
    return fail(res, 500, 'server_error', 'No pudimos analizar la foto. Intenta de nuevo.');
  }
};
