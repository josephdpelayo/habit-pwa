#!/usr/bin/env python3
"""Importa o actualiza el bloque en el calendario personal de Intervals.icu."""

import argparse
import base64
import getpass
import json
import os
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


API_URL = "https://intervals.icu/api/v1/athlete/0/events/bulk?upsert=true"
DEFAULT_PLAN = Path(__file__).with_name("plan_intervals_31ago_05oct2026.json")


def main():
    parser = argparse.ArgumentParser(description="Carga el plan en Intervals.icu")
    parser.add_argument("--commit", action="store_true", help="Realiza la carga. Sin esta opcion solo valida y muestra el resumen.")
    parser.add_argument("--plan", type=Path, default=DEFAULT_PLAN)
    args = parser.parse_args()

    events = json.loads(args.plan.read_text(encoding="utf-8"))
    workouts = sum(1 for event in events if event.get("category") == "WORKOUT")
    notes = len(events) - workouts
    dates = [event["start_date_local"][:10] for event in events]
    print(f"Plan valido: {len(events)} eventos ({workouts} entrenamientos y {notes} nota).")
    print(f"Rango: {min(dates)} a {max(dates)}")

    if not args.commit:
        print("Vista previa solamente. Usa --commit para cargarlo.")
        return

    api_key = os.environ.get("INTERVALS_API_KEY") or getpass.getpass("Clave API personal de Intervals.icu: ")
    if not api_key:
        raise SystemExit("No se proporciono una clave API.")

    token = base64.b64encode(f"API_KEY:{api_key}".encode()).decode()
    request = Request(
        API_URL,
        data=json.dumps(events, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Basic {token}", "Content-Type": "application/json",
                 "User-Agent": "habit-intervals-cli/1.0"},
        method="POST",
    )

    try:
        with urlopen(request, timeout=60) as response:
            result = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Intervals.icu respondio {exc.code}: {detail}") from exc
    except URLError as exc:
        raise SystemExit(f"No fue posible conectar con Intervals.icu: {exc.reason}") from exc

    print(f"Carga completada: {len(result)} eventos creados o actualizados.")
    print("Los external_id estables permiten ejecutar de nuevo el archivo sin crear duplicados.")


if __name__ == "__main__":
    main()
