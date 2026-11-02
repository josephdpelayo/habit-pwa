#!/usr/bin/env python3
"""Garmin (via Intervals.icu) desde la terminal: leer lo entrenado y subir el plan al reloj.

Garmin Connect no tiene API publica para personas. Intervals.icu si: recibe del reloj las
actividades y el bienestar (sueno, HRV, pulso en reposo) y le manda al reloj los entrenamientos
planificados. Este archivo solo habla con Intervals.icu.

La clave se busca en este orden y nunca se imprime:
  1. variable de entorno INTERVALS_API_KEY
  2. Llavero de macOS, servicio "intervals-icu" (ver INSTRUCCIONES.md)

Uso:
  python3 intervals.py resumen [--dias 42]
  python3 intervals.py actividades [--dias 28]
  python3 intervals.py bienestar [--dias 14]
  python3 intervals.py calendario [--desde AAAA-MM-DD] [--hasta AAAA-MM-DD]
  python3 intervals.py subir plan.json [--commit] [--reemplazar PREFIJO]
Cualquier lectura acepta --json para ver la respuesta cruda.
"""

import argparse
import base64
import getpass
import json
import os
import subprocess
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


API = "https://intervals.icu/api/v1/athlete/0"
KEYCHAIN_SERVICE = "intervals-icu"
# Cloudflare (delante de Intervals.icu) responde 403 / error 1010 al User-Agent por defecto de
# urllib, con la clave correcta. Cualquier nombre propio pasa.
USER_AGENT = "habit-intervals-cli/1.0"


# ── Conexion ────────────────────────────────────────────────────────────────

def api_key(interactive=False):
    key = os.environ.get("INTERVALS_API_KEY")
    if key:
        return key.strip()
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-a", os.environ.get("USER", ""),
             "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    if interactive:
        key = getpass.getpass("Clave API personal de Intervals.icu: ")
        if key:
            return key.strip()
    raise SystemExit(
        "No encontre la clave de Intervals.icu.\n"
        "Guardala una vez en el Llavero (te la pide oculta):\n"
        f'  security add-generic-password -a "$USER" -s {KEYCHAIN_SERVICE} -w'
    )


def call(method, path, params=None, body=None, interactive=False):
    url = API + path + ("?" + urlencode(params) if params else "")
    token = base64.b64encode(f"API_KEY:{api_key(interactive)}".encode()).decode()
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    request = Request(url, data=data, method=method, headers={
        "Authorization": f"Basic {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    })
    try:
        with urlopen(request, timeout=60) as response:
            raw = response.read().decode("utf-8")
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        if exc.code == 403 and "cloudflare" in detail.lower():
            raise SystemExit(f"Cloudflare bloqueo la peticion antes de llegar a Intervals.icu: {detail}")
        if exc.code in (401, 403):
            raise SystemExit("Intervals.icu rechazo la clave. Revisala en Settings > Developer Settings.")
        if exc.code == 429:
            raise SystemExit("Intervals.icu esta limitando peticiones. Intenta en unos minutos.")
        raise SystemExit(f"Intervals.icu respondio {exc.code}: {detail}")
    except URLError as exc:
        raise SystemExit(f"No fue posible conectar con Intervals.icu: {exc.reason}")
    return json.loads(raw) if raw else None


# ── Formato ─────────────────────────────────────────────────────────────────

def hm(seconds):
    if not seconds:
        return "—"
    minutes = round(seconds / 60)
    return f"{minutes // 60}h{minutes % 60:02d}" if minutes >= 60 else f"{minutes} min"


def km(meters):
    return f"{meters / 1000:.1f} km" if meters else "—"


def val(x, fmt="{}"):
    return fmt.format(x) if x is not None else "—"


def table(rows, headers):
    widths = [max(len(str(h)), *(len(str(r[i])) for r in rows)) for i, h in enumerate(headers)] if rows else [len(h) for h in headers]
    line = lambda cells: "  ".join(str(c).ljust(w) for c, w in zip(cells, widths)).rstrip()
    print(line(headers))
    print(line(["-" * w for w in widths]))
    for r in rows:
        print(line(r))


def window(days):
    today = date.today()
    return (today - timedelta(days=days - 1)).isoformat(), today.isoformat()


# ── Lecturas ────────────────────────────────────────────────────────────────

def fetch_activities(days):
    oldest, newest = window(days)
    acts = call("GET", "/activities", {"oldest": oldest, "newest": newest}) or []
    return sorted(acts, key=lambda a: a.get("start_date_local") or "")


def fetch_wellness(days):
    oldest, newest = window(days)
    return sorted(call("GET", "/wellness", {"oldest": oldest, "newest": newest}) or [],
                  key=lambda w: w.get("id") or "")


def activity_rows(acts):
    rows = []
    for a in acts:
        rows.append([
            (a.get("start_date_local") or "")[:10],
            a.get("type") or "—",
            (a.get("name") or "")[:38],
            hm(a.get("moving_time") or a.get("elapsed_time")),
            km(a.get("distance")),
            val(a.get("average_heartrate"), "{:.0f}"),
            val(a.get("icu_training_load"), "{:.0f}"),
            val(a.get("icu_rpe") or a.get("perceived_exertion")),
        ])
    return rows


def wellness_rows(entries):
    rows = []
    for w in entries:
        ctl, atl = w.get("ctl"), w.get("atl")
        form = ctl - atl if ctl is not None and atl is not None else None
        rows.append([
            (w.get("id") or "")[:10],
            val(ctl, "{:.0f}"), val(atl, "{:.0f}"), val(form, "{:+.0f}"),
            val(w.get("restingHR")), val(w.get("hrv"), "{:.0f}"),
            hm(w.get("sleepSecs")), val(w.get("sleepScore")),
            val(w.get("weight"), "{:.1f}"),
        ])
    return rows


def cmd_actividades(args):
    acts = fetch_activities(args.dias)
    if args.json:
        return print(json.dumps(acts, ensure_ascii=False, indent=1))
    print(f"Actividades de los ultimos {args.dias} dias: {len(acts)}\n")
    table(activity_rows(acts), ["fecha", "tipo", "nombre", "tiempo", "dist", "FC", "carga", "RPE"])


def cmd_bienestar(args):
    entries = fetch_wellness(args.dias)
    if args.json:
        return print(json.dumps(entries, ensure_ascii=False, indent=1))
    print("CTL = forma cronica (42 d), ATL = fatiga (7 d), forma = CTL - ATL\n")
    table(wellness_rows(entries), ["fecha", "CTL", "ATL", "forma", "FCr", "HRV", "sueno", "pts", "peso"])


def cmd_calendario(args):
    today = date.today()
    oldest = args.desde or today.isoformat()
    newest = args.hasta or (today + timedelta(days=27)).isoformat()
    events = sorted(call("GET", "/events", {"oldest": oldest, "newest": newest}) or [],
                    key=lambda e: e.get("start_date_local") or "")
    if args.json:
        return print(json.dumps(events, ensure_ascii=False, indent=1))
    print(f"Calendario {oldest} a {newest}: {len(events)} eventos\n")
    table([[
        (e.get("start_date_local") or "")[:10], e.get("category") or "—", e.get("type") or "—",
        (e.get("name") or "")[:44], hm(e.get("moving_time")), val(e.get("icu_training_load"), "{:.0f}"),
        e.get("external_id") or "",
    ] for e in events], ["fecha", "categoria", "tipo", "nombre", "tiempo", "carga", "external_id"])


def cmd_resumen(args):
    acts = fetch_activities(args.dias)
    entries = fetch_wellness(args.dias)
    if args.json:
        return print(json.dumps({"activities": acts, "wellness": entries}, ensure_ascii=False, indent=1))

    # Semana ISO por deporte: horas, distancia y carga.
    weeks = defaultdict(lambda: defaultdict(lambda: [0, 0.0, 0.0, 0]))
    for a in acts:
        day = (a.get("start_date_local") or "")[:10]
        if not day:
            continue
        y, w, _ = date.fromisoformat(day).isocalendar()
        cell = weeks[f"{y}-S{w:02d}"][a.get("type") or "Otro"]
        cell[0] += 1
        cell[1] += (a.get("moving_time") or a.get("elapsed_time") or 0) / 3600
        cell[2] += (a.get("distance") or 0) / 1000
        cell[3] += a.get("icu_training_load") or 0

    print(f"Volumen por semana y deporte (ultimos {args.dias} dias)\n")
    rows = []
    for week in sorted(weeks):
        for sport, (n, hours, dist, load) in sorted(weeks[week].items()):
            rows.append([week, sport, n, f"{hours:.1f} h", f"{dist:.1f} km" if dist else "—", f"{load:.0f}"])
    table(rows, ["semana", "deporte", "n", "horas", "dist", "carga"])

    with_load = [w for w in entries if w.get("ctl") is not None]
    if with_load:
        first, last = with_load[0], with_load[-1]
        print(f"\nCTL {first['ctl']:.0f} -> {last['ctl']:.0f}   ATL hoy {last['atl']:.0f}   "
              f"forma hoy {last['ctl'] - last['atl']:+.0f}")
    recent = entries[-7:]
    def avg(field):
        xs = [w[field] for w in recent if w.get(field) is not None]
        return sum(xs) / len(xs) if xs else None
    print(f"Ultimos 7 dias: FC reposo {val(avg('restingHR'), '{:.0f}')}  HRV {val(avg('hrv'), '{:.0f}')}  "
          f"sueno {hm(avg('sleepSecs'))}")

    print("\nUltimas 10 actividades\n")
    table(activity_rows(acts[-10:]), ["fecha", "tipo", "nombre", "tiempo", "dist", "FC", "carga", "RPE"])


# ── Escritura ───────────────────────────────────────────────────────────────

def cmd_subir(args):
    events = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    missing = [e.get("name") for e in events if not e.get("external_id")]
    if missing:
        raise SystemExit(f"Cada evento necesita external_id para poder repetir la carga sin duplicar: {missing}")
    workouts = sum(1 for e in events if e.get("category") == "WORKOUT")
    dates = [e["start_date_local"][:10] for e in events]
    print(f"Plan valido: {len(events)} eventos ({workouts} entrenamientos, {len(events) - workouts} otros).")
    print(f"Rango: {min(dates)} a {max(dates)}")
    # Mover una sesion de dia cambia su external_id (lleva la fecha): sin esto, la version vieja
    # se queda en el calendario y llega al reloj junto con la nueva.
    stale = []
    if args.reemplazar:
        keep = {e["external_id"] for e in events}
        current = call("GET", "/events", {"oldest": min(dates), "newest": max(dates)}) or []
        stale = [e for e in current if (e.get("external_id") or "").startswith(args.reemplazar)
                 and e["external_id"] not in keep]
        for e in stale:
            print(f"  sobra: {(e.get('start_date_local') or '')[:10]}  {e.get('name')}  ({e['external_id']})")
        print(f"{len(stale)} eventos viejos de '{args.reemplazar}' que ya no estan en el plan.")
    if not args.commit:
        print("Vista previa solamente. Usa --commit para cargarlo" + (" y borrar los viejos." if stale else "."))
        return
    result = call("POST", "/events/bulk", {"upsert": "true"}, body=events, interactive=True)
    print(f"Carga completada: {len(result or [])} eventos creados o actualizados.")
    for e in stale:
        call("DELETE", f"/events/{e['id']}")
    if stale:
        print(f"Borrados: {len(stale)} eventos viejos.")


def main():
    parser = argparse.ArgumentParser(description="Garmin via Intervals.icu")
    sub = parser.add_subparsers(dest="cmd", required=True)

    for name, fn, days in (("resumen", cmd_resumen, 42), ("actividades", cmd_actividades, 28),
                           ("bienestar", cmd_bienestar, 14)):
        p = sub.add_parser(name)
        p.add_argument("--dias", type=int, default=days)
        p.add_argument("--json", action="store_true")
        p.set_defaults(fn=fn)

    p = sub.add_parser("calendario")
    p.add_argument("--desde")
    p.add_argument("--hasta")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_calendario)

    p = sub.add_parser("subir")
    p.add_argument("plan")
    p.add_argument("--commit", action="store_true")
    p.add_argument("--reemplazar", metavar="PREFIJO",
                   help="borra los eventos con este prefijo de external_id, en el rango del plan, que no esten en el")
    p.set_defaults(fn=cmd_subir)

    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
