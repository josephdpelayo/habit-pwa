// send-push — manda un aviso web push a 'admin', a 'user:<uuid>' o (sin target) a todos.
// Lo llaman la app (sendPush, con el JWT del socio) y el servidor (api/*, con la service-role).
// Desplegada en Supabase; esta copia es la fuente. Antes contestaba 200 aunque Apple/Google
// rechazaran el envío y no dejaba rastro: ahora cada envío y cada rechazo queda en los logs.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type" };

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  try {
    const { target, title, body, url, tag, icon } = await req.json();
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const vapid = { subject: Deno.env.get("VAPID_SUBJECT")!, publicKey: Deno.env.get("VAPID_PUBLIC_KEY")!, privateKey: Deno.env.get("VAPID_PRIVATE_KEY")! };
    let query = supabase.from("push_subscriptions").select("*");
    if (target === "admin") query = query.eq("role", "admin");
    else if (target && target.startsWith("user:")) query = query.eq("user_id", target.replace("user:", ""));
    const { data: subs, error } = await query;
    if (error) throw error;
    if (!subs || subs.length === 0) {
      console.log(JSON.stringify({ push: "no-subs", target, tag }));
      return new Response(JSON.stringify({ sent: 0 }), { headers: { "Content-Type": "application/json", ...CORS } });
    }
    const { default: webpush } = await import("https://esm.sh/web-push@3.6.7");
    webpush.setVapidDetails(vapid.subject, vapid.publicKey, vapid.privateKey);
    const payload = JSON.stringify({ title, body, url: url || "/", tag: tag || "habit", icon: icon || "/icons/logo-original.png" });
    const results = await Promise.allSettled(subs.map((s: any) =>
      webpush.sendNotification(s.subscription, payload).catch(async (err: any) => {
        const host = String(s.subscription?.endpoint || "").split("/")[2] || "";
        console.error(JSON.stringify({ push: "rejected", target, tag, sub: s.id, host, status: err?.statusCode, reason: String(err?.body || err?.message || err).slice(0, 300) }));
        if (err?.statusCode === 410 || err?.statusCode === 404) {
          await supabase.from("push_subscriptions").delete().eq("id", s.id);
        }
        throw err;
      })
    ));
    const sent = results.filter((r) => r.status === "fulfilled").length;
    const failed = results.filter((r) => r.status === "rejected").length;
    console.log(JSON.stringify({ push: "done", target, tag, subs: subs.length, sent, failed }));
    return new Response(JSON.stringify({ sent, failed }), { headers: { "Content-Type": "application/json", ...CORS } });
  } catch (e: any) {
    console.error(JSON.stringify({ push: "error", message: e?.message }));
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { "Content-Type": "application/json", ...CORS } });
  }
});
