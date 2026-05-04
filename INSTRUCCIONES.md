# HABIT Training Hub — PWA con Supabase

## PASO 1 — Configurar base de datos Supabase

1. Ve a supabase.com → tu proyecto → **SQL Editor**
2. Click "New query"
3. Copia y pega TODO el contenido del archivo `habit-supabase-setup.sql`
4. Click **Run** (▶)
5. Debe aparecer: "Schema creado correctamente ✓"
6. Copia y corre tambien `stripe-payments.sql` para evitar pagos duplicados de Stripe

## PASO 2 — Publicar en Vercel

1. Ve a vercel.com → crea cuenta gratis
2. Importa el repo de GitHub `habit-pwa`
3. Vercel te da un link como: `https://habit-pwa.vercel.app`

## PASO 2.1 — Configurar Stripe

En Vercel → Project Settings → Environment Variables agrega:

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
