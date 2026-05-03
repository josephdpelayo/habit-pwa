# HABIT Training Hub — PWA con Supabase

## PASO 1 — Configurar base de datos Supabase

1. Ve a supabase.com → tu proyecto → **SQL Editor**
2. Click "New query"
3. Copia y pega TODO el contenido del archivo `habit-supabase-setup.sql`
4. Click **Run** (▶)
5. Debe aparecer: "Schema creado correctamente ✓"

## PASO 2 — Publicar en Netlify

1. Ve a netlify.com → crea cuenta gratis
2. Dashboard → arrastra la carpeta `habit-pwa-v2` completa
3. Netlify te da un link como: `https://habit-xxx.netlify.app`

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

Manda el link de Netlify por WhatsApp a tus clientes.

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

## ¿Qué sigue? (próximas fases)
- Pagos reales con Stripe
- Notificaciones push con OneSignal
- Control de puerta Shelly automático
