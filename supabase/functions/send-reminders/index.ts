// send-reminders — «Tu sesión es en 1 hora». La llama pg_cron cada 10 minutos (migración 150);
// cada corrida avisa las reservas que empiezan dentro de 50–80 min y les pone reminder_sent_at,
// así que una reserva cae en la ventana tres veces y se avisa una sola.
// Desplegada en Supabase con verify_jwt = false (el cron llama sin llave); esta copia es la fuente.
// Hasta nov 2026 nada la llamaba: no existía el cron y ninguna reserva tuvo su recordatorio.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAZ_OFFSET_H = 7; // Mazatlán UTC-7, sin horario de verano
const MIN = 60 * 1000;

// ds + slot (0–47, 30 min) → instante UTC
function slotToUtc(ds: string, slotIdx: number): Date {
  const [y, m, d] = ds.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d, MAZ_OFFSET_H, 0, 0, 0) + slotIdx * 30 * MIN);
}
// instante → fecha de Mazatlán (YYYY-MM-DD). Antes usaba la fecha UTC, que desde las 5 pm de
// Mazatlán ya es mañana y dejaba fuera las reservas de la noche.
function mazDs(t: Date): string {
  return new Date(t.getTime() - MAZ_OFFSET_H * 60 * MIN).toISOString().slice(0, 10);
}

serve(async (_req) => {
  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const now = new Date();
    const windowStart = new Date(now.getTime() + 50 * MIN);
    const windowEnd = new Date(now.getTime() + 80 * MIN);

    const { data: bookings, error } = await supabase
      .from("bookings")
      .select("id, user_id, ds, start_idx, time_str")
      .eq("status", "active")
      .is("reminder_sent_at", null)
      .gte("ds", mazDs(windowStart))
      .lte("ds", mazDs(windowEnd));
    if (error) throw error;

    const due = (bookings || []).filter((b) => {
      const t = slotToUtc(b.ds, b.start_idx);
      return t >= windowStart && t <= windowEnd;
    });
    if (!due.length) {
      return new Response(JSON.stringify({ checked: (bookings || []).length, sent: 0 }), { headers: { "Content-Type": "application/json" } });
    }

    const { default: webpush } = await import("https://esm.sh/web-push@3.6.7");
    webpush.setVapidDetails(Deno.env.get("VAPID_SUBJECT")!, Deno.env.get("VAPID_PUBLIC_KEY")!, Deno.env.get("VAPID_PRIVATE_KEY")!);

    let sent = 0;
    const reminded: string[] = [];
    for (const b of due) {
      const { data: subs } = await supabase.from("push_subscriptions").select("*").eq("user_id", b.user_id);
      if (subs && subs.length > 0) {
        const payload = JSON.stringify({
          title: "⏰ Tu sesión es en 1 hora",
          body: `Tienes entrenamiento a las ${b.time_str}. ¡Prepárate!`,
          tag: "reminder-" + b.id,
          icon: "/icons/logo-original.png",
        });
        const results = await Promise.allSettled(subs.map((s: any) =>
          webpush.sendNotification(s.subscription, payload).catch(async (err: any) => {
            console.error(JSON.stringify({ reminder: "rejected", booking: b.id, sub: s.id, status: err?.statusCode, reason: String(err?.body || err?.message || err).slice(0, 300) }));
            if (err?.statusCode === 410 || err?.statusCode === 404) {
              await supabase.from("push_subscriptions").delete().eq("id", s.id);
            }
            throw err;
          })
        ));
        if (results.some((r) => r.status === "fulfilled")) sent++;
      }
      // Se marca aunque no tenga suscripción, para no revisarla en cada corrida.
      reminded.push(b.id);
    }
    if (reminded.length) {
      await supabase.from("bookings").update({ reminder_sent_at: now.toISOString() }).in("id", reminded);
    }
    console.log(JSON.stringify({ reminder: "done", checked: (bookings || []).length, due: due.length, sent }));
    return new Response(JSON.stringify({ checked: (bookings || []).length, due: due.length, sent }), { headers: { "Content-Type": "application/json" } });
  } catch (e: any) {
    console.error(JSON.stringify({ reminder: "error", message: e?.message }));
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
