# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HABIT Training Hub — a PWA for a gym in Mazatlán, Mexico. Members book training slots, pay via Stripe, and open the gym door from their phone. The app is deployed on Vercel with Supabase as the backend.

## Commands

```bash
# Check syntax of all API files and sw.js
npm run check

# Deploy: push to git → Vercel auto-deploys
```

There is no build step, no bundler, no test suite. `npm run check` runs `node --check` on each API file — it validates syntax only, not runtime behavior.

## Architecture

### Frontend (`app.html`)
A single ~5500-line file containing all HTML, CSS, and JavaScript. There is no framework, no bundler, no imports — it's vanilla JS loaded as inline `<script>`. The Supabase JS client is loaded from CDN.

The app has four screens (`#s-auth`, `#s-main`, `#s-admin`, `#s-reception`), toggled by adding/removing the `.active` CSS class. Within `#s-main`, tabs are toggled via `.view.active`. Admin has its own tab system via `admTab()`.

- `index.html` — just redirects to `app.html` with a version query string for cache busting
- `sw.js` — service worker for push notifications only; intentionally has **no** fetch handler (no caching/offline support)
- `manifest.json` — PWA manifest

**Version / cache busting**: `APP_VERSION` is defined in `app.html` (e.g. `'20260505-20'`). When making changes that clients need to pick up, update this constant and the matching `?v=` strings in `index.html` and the `<link>` tags at the top of `app.html`. Also update `CACHE_VERSION` in `sw.js` to the same value — this invalidates the old shell cache and forces clients to download the new version.

### Backend (`api/*.js`)
Vercel serverless functions. Files prefixed with `_` (`_plans.js`, `_fulfillment.js`) are shared modules, not routes.

Key routes:
- `stripe-webhook.js` — receives `checkout.session.completed` from Stripe; calls `activateMembership()` from `_fulfillment.js`
- `create-checkout-session.js` / `confirm-checkout-session.js` — Stripe Checkout flow
- `validate-access-code.js` — physical keypad validation; authenticated with `ACCESS_API_SECRET` bearer token
- `request-door-open.js` — in-app door open button; authenticated with Supabase JWT + GPS proximity check, then triggers Shelly Cloud relay API
- `search-users.js` — admin user search (service-role Supabase query)
- `sync-stripe-payments.js` — admin-triggered payment sync

Plans (prices, credits, expiry days) are defined centrally in `api/_plans.js` and shared by `_fulfillment.js`, `create-checkout-session.js`, and `confirm-checkout-session.js`.

### Database (Supabase)
Schema is in `habit-supabase-setup.sql`. Additional migrations are separate `.sql` files that must be run manually in the Supabase SQL Editor.

Core tables:
- `profiles` — extends `auth.users`; has `role` (`user`/`admin`/`reception`), 4-digit `access_code`, `credits`, `plan_id`, `plan_expiry`
- `bookings` — reservations; `ds` = date (`YYYY-MM-DD`), `start_idx` = slot index 0–47 (each slot = 30 min), `slots_used` = 2 or 3
- `slot_occupancy` — one row per booked slot per user per day
- `slot_blocks` — admin-created manual blocks
- `payments` — payment records (Stripe and manual)
- `door_commands` — queue of door open requests with Shelly execution status
- `access_log` — history of door access events
- `boards` / `board_assignments` / `scores` — workout boards feature
- `posts` / `post_reactions` / `post_comments` — community feed
- `booking_guest_passes` — group session guest passes (from `group-guest-passes.sql`)
- `admin_notifs` — in-app notifications for admin

### Time & Slots
All time logic uses **America/Mazatlan (UTC−7)**. The constant `MAZ_UTC_OFFSET_H = 7` converts UTC midnight to Mazatlán midnight. A day has 48 slots of 30 minutes. A typical booking is `slots_used = 3` (90 min). Access windows open 10 minutes before a booking's `start_idx`.

### Door Access: Two Paths
1. **Physical keypad** → `POST /api/validate-access-code` with `Authorization: Bearer ACCESS_API_SECRET`
2. **In-app button** → `POST /api/request-door-open` with Supabase JWT + GPS coords → Shelly Cloud API

### Native (Capacitor)
`capacitor.config.json` targets `app.habittraininghub.app`. The `ios/` and `www/` directories contain the Capacitor build output. The `www/` dir is generated from `app.html` — do not edit it directly.

### Environment Variables (Vercel)
```
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
STRIPE_SECRET_KEY
STRIPE_WEBHOOK_SECRET
ACCESS_API_SECRET        # shared secret for keypad controller
GYM_LAT / GYM_LNG       # GPS coordinates of gym
GYM_RADIUS_METERS        # default 120
GYM_MAX_ACCURACY_METERS  # default 150
SHELLY_SERVER_URL        # e.g. https://shelly-247-eu.shelly.cloud
SHELLY_AUTH_KEY
SHELLY_DEVICE_ID
SHELLY_CHANNEL           # default 0
SHELLY_TURN              # 'off' releases the magnetic lock
PUBLIC_APP_URL
```

`LOCATION_EXEMPT_EMAILS` in `request-door-open.js` lists emails that bypass GPS checks.

### SQL Migrations
All migrations live in `migrations/` with numeric prefixes (`001_schema.sql` … `014_add_guest_names.sql`). Run them in order in the Supabase SQL Editor. New migrations follow the same naming convention. The API handlers detect missing tables and return descriptive error messages pointing to the required migration.
