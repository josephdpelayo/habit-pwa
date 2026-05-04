# HABIT Training Hub — PWA con Supabase

## PASO 1 — Configurar base de datos Supabase

1. Ve a supabase.com → tu proyecto → **SQL Editor**
2. Click "New query"
3. Copia y pega TODO el contenido del archivo `habit-supabase-setup.sql`
4. Click **Run** (▶)
5. Debe aparecer: "Schema creado correctamente ✓"
6. Copia y corre tambien `stripe-payments.sql` para evitar pagos duplicados de Stripe
7. Copia y corre tambien `door-commands.sql` para activar solicitudes de apertura de puerta

## PASO 2 — Publicar en Vercel

1. Ve a vercel.com → crea cuenta gratis
2. Importa el repo de GitHub `habit-pwa`
3. Vercel te da un link como: `https://habit-pwa.vercel.app`

## PASO 2.1 — Configurar Stripe

En Vercel → Project Settings → Environment Variables agrega en Production y Preview:

```txt
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
SUPABASE_URL=https://pmpjteuqjusbiduevbwq.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
PUBLIC_APP_URL=https://tu-dominio.com
```

En Stripe → Developers → Webhooks crea un endpoint:

```txt
https://tu-dominio.com/api/stripe-webhook
```

Selecciona el evento:

```txt
checkout.session.completed
```

Despues copia el `Signing secret` del webhook y ponlo en `STRIPE_WEBHOOK_SECRET`.

## PASO 2.2 — Activar validacion real del codigo de puerta

En Vercel → Project Settings → Environment Variables agrega:

```txt
ACCESS_API_SECRET=un_codigo_largo_privado
GYM_LAT=23.000000
GYM_LNG=-106.000000
GYM_RADIUS_METERS=120
GYM_MAX_ACCURACY_METERS=150
SHELLY_SERVER_URL=https://shelly-247-eu.shelly.cloud
SHELLY_AUTH_KEY=tu_shelly_auth_key
SHELLY_DEVICE_ID=tu_shelly_device_id
SHELLY_CHANNEL=0
SHELLY_TURN=off
```

Ese valor no se comparte con clientes. Es la llave privada que usara el teclado, controlador o relay para consultar si el codigo `1234#` puede abrir en ese momento.

`GYM_LAT` y `GYM_LNG` son la ubicacion exacta del gym. El boton "Abrir puerta" solo crea la solicitud si el usuario esta dentro del radio configurado en `GYM_RADIUS_METERS` y si la lectura del GPS es suficientemente precisa segun `GYM_MAX_ACCURACY_METERS`.

Las variables `SHELLY_*` conectan HABIT con Shelly Cloud. `SHELLY_TURN=off` debe quedarse igual si esa es la accion que libera el iman en la configuracion actual.

Endpoint para el controlador:

```txt
https://tu-dominio.com/api/validate-access-code
```

Ejemplo de prueba:

```bash
curl -X POST https://tu-dominio.com/api/validate-access-code \
  -H "Authorization: Bearer ACCESS_API_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"code":"1234#"}'
```

La puerta debe abrir solo cuando la respuesta traiga:

```json
{"allow":true}
```

Regla actual: el codigo se autoriza desde 10 minutos antes de la reserva hasta que termina la sesion. Cada acceso autorizado se guarda en `access_log` y en notificaciones del admin.

## PASO 3 — Crear tu cuenta de admin

1. Abre el link en tu celular
2. Regístrate con tu correo (el mismo que usas para todo)
3. Ve a Supabase → SQL Editor → Nueva query
4. Ejecuta esto (cambia tu_correo@gmail.com por tu correo real):
   ```sql
   UPDATE public.profiles 
   SET role = 'admin' 
   WHERE id = (SELECT id FROM auth.users WHERE email = 'tu_correo@gmail.com');
   ```
5. Cierra sesión y vuelve a entrar → ya eres admin

## PASO 4 — Compartir con clientes

Manda el link de Vercel o tu dominio por WhatsApp a tus clientes.

### iPhone:
Safari → botón compartir ↑ → "Agregar a pantalla de inicio"

### Android:
Chrome → banner automático "Instalar app"

---
## ¿Qué está conectado a Supabase?
✅ Registro y login de usuarios
✅ Reservas (persisten aunque cierren la app)
✅ Slots de horarios (todos ven disponibilidad en tiempo real)
✅ Cancelación de reservas
✅ Membresías y créditos
✅ Pagos reales con Stripe Checkout

## ¿Qué sigue? (próximas fases)
- Notificaciones push con OneSignal
- Control de puerta Shelly automático
