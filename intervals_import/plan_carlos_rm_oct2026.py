#!/usr/bin/env python3
"""Plan de Carlos (Running Master, 19 oct - 29 nov 2026): las semanas a bordo, en cinta.

    python3 plan_carlos_rm_oct2026.py          # escribe plan_carlos_rm_oct2026.json
    python3 intervals.py subir plan_carlos_rm_oct2026.json --reemplazar joseph-rm-2026 [--commit]

Reemplaza a plan_10k_22nov2026.py, que nunca se subio. Semana final del 18 oct: los planes de Alge
y de Carlos tal cual, sin HYROX fijo (se acomoda cada semana, de preferencia el miercoles):
  lun HS + empuje + cadera            | mar HS + tiron + Z1
  mie HS + empuje + accesorios         | jue HS + Z1 + cuadriceps y pantorrilla
  vie HS + tiron, sin pierna           | sab HS + calidad + 1/2 empuje
  dom largo Z1
Los rodajes van en los dias de Carlos. --reemplazar borra las versiones de dias anteriores, que
llevan otra fecha en el external_id. Aqui solo va la carrera: lo demas vive en el PDF.

Zonas de Carlos por ritmo, convertidas a la cinta (1% de inclinacion):
  Z1 5:50-6:00 /km = 10.0-10.3 km/h   Z2 4:45-4:50 = 12.4-12.6   Z3 4:25-4:30 = 13.3-13.6
Carlos escribe las series en metros; aqui van en tiempo a la velocidad media de la zona,
porque en cinta el reloj de muneca mide la distancia corta y alargaria cada serie.
Solo se generan las semanas a bordo (ON_BOARD_WEEKS): las 4-6 se planean en tierra, con otro
horario y sin cinta. Volver a generar y subir actualiza los mismos eventos (external_id estables).
"""

import json
from datetime import date, timedelta
from pathlib import Path

OUT = Path(__file__).with_name("plan_carlos_rm_oct2026.json")
PREFIX = "joseph-rm-2026"
WEEK1 = date(2026, 10, 19)
ON_BOARD_WEEKS = 3  # 19 oct - 8 nov; luego baja del barco

ZONES = {  # ritmo min/km de Carlos, km/h en cinta, segundos por km a mitad de zona
    1: ("5:50-6:00/km Pace", "10.0-10.3kph", 355),
    2: ("4:45-4:50/km Pace", "12.4-12.6kph", 287.5),
    3: ("4:25-4:30/km Pace", "13.3-13.6kph", 267.5),
}
CUE = {1: "Suave", 2: "Sostenido", 3: "Exigente"}
CINTA = ("Cinta al 1% de inclinacion. Manda la velocidad de la cinta, no el ritmo del reloj: al guardar, "
         "corrige la distancia en Garmin para que se calibre. Con mar movida: clip de seguridad y "
         "0.3-0.5 km/h menos en lo rapido.")

# Por semana: minutos del Z1, minutos del largo, y la calidad como lista de
# (repeticiones, metros, zona, pausa en segundos despues de cada repeticion).
WEEKS = [
    {"z1": 40, "long": 60, "q": "3 x 2000 m en Z2, pausa 2'", "sets": [(3, 2000, 2, 120)]},
    {"z1": 45, "long": 65, "q": "2 x 3000 m en Z2, pausa 2'30", "sets": [(2, 3000, 2, 150)]},
    {"z1": 45, "long": 70, "q": "6000 m en Z2 + 1000 m en Z3, pausa 3'", "sets": [(1, 6000, 2, 180), (1, 1000, 3, 0)]},
    {"z1": 50, "long": 75, "q": "4 x 1000 m en Z3 + 4000 m en Z2, pausas 2'-3'", "sets": [(4, 1000, 3, 150), (1, 4000, 2, 0)]},
    {"z1": 50, "long": 80, "q": "2 x 4000 m en Z2, pausa 3'", "sets": [(2, 4000, 2, 180)]},
    {"z1": 50, "long": 80, "q": "4000 m en Z2 + 4 x 1000 m en Z3, pausas 3'-2'", "sets": [(1, 4000, 2, 180), (4, 1000, 3, 120)]},
]


def t(seconds):
    m, s = divmod(round(seconds), 60)
    return f"{m}m{s:02d}s" if s else f"{m}m"


def step(cue, seconds, zone=None, intensity="active"):
    target = f" {ZONES[zone][0]}" if zone else ""
    speed = f" {ZONES[zone][1]}" if zone else ""
    return f"- {cue}{speed} {t(seconds)}{target} intensity={intensity}"


def event(day, code, kind, name, prose, steps):
    return {"external_id": f"{PREFIX}-{day.isoformat()}-{code.lower()}", "category": "WORKOUT",
            "start_date_local": f"{day.isoformat()}T00:00:00", "type": kind,
            "name": f"{code} - {name}", "description": prose + "\n\n" + steps}


def z1_martes(day, w, minutes):
    return event(day, f"E{w}", "Run", f"Rodaje Z1 {minutes}",
                 "Suave de verdad: tienes que poder conversar. Va despues del tiron de Alge. Si la cadera "
                 f"de ayer se nota, quedate en 10.0 km/h. Despues, gemelo y soleo. {CINTA}",
                 step(CUE[1], minutes * 60, 1))


def z1_jueves(day, w, minutes):
    return event(day, f"J{w}", "Run", f"Rodaje Z1 {minutes}",
                 "Suave de verdad. Va despues del handstand y antes de la pierna, para que la pantorrilla "
                 f"corra fresca. La pierna de hoy es corta y sin fallo: el sabado es la calidad. {CINTA}",
                 step(CUE[1], minutes * 60, 1))


def calidad(day, w, spec):
    blocks = [step("Calentamiento " + CUE[1], 15 * 60, 1, "warmup")]
    total = 25 * 60
    for reps, meters, zone, rest in spec["sets"]:
        work = meters / 1000 * ZONES[zone][2]
        lines = [step(CUE[zone], work, zone, "interval")]
        if rest:
            lines.append(f"- Pausa {t(rest)} intensity=recovery")
        total += reps * (work + rest)
        blocks.append((f"{reps}x\n" if reps > 1 else "") + "\n".join(lines))
    blocks.append(step("Enfriamiento " + CUE[1], 10 * 60, 1, "cooldown"))
    return event(day, f"Q{w}", "Run", f"Calidad: {spec['q']}",
                 f"Carlos: 15' de calentamiento + {spec['q']} + 10' de enfriamiento (unos {round(total / 60)} min). "
                 "Las series van en tiempo a la velocidad media de la zona; en la cinta salen los metros de "
                 "Carlos. Handstand antes de correr, 1/2 empuje despues. Ayer sin pierna; la del jueves fue corta. "
                 "Sorbos de isotonica casera (1 bloque) "
                 f"en el calentamiento y en las pausas. Respeta la zona aunque el cuerpo pida mas. {CINTA}",
                 "\n\n".join(blocks))


def largo(day, w, minutes):
    fuel = "1 1/2 bloques" if minutes > 70 else "1 bloque"
    return event(day, f"L{w}", "Run", f"Largo Z1 {minutes}",
                 "Largo en Z1 de verdad: nada de acelerar al final. Agua cada 15-20 min. A los 40 min el "
                 f"reloj te avisa: {fuel} de carbos (35 g de datiles o isotonica casera) sin parar la cinta. "
                 f"Pesate antes y despues: cada kilo perdido son 1-1.5 L por reponer. {CINTA}",
                 "\n".join([step(CUE[1], 40 * 60, 1),
                            step("Toma carbos y sigue " + CUE[1].lower(), (minutes - 40) * 60, 1)]))


events = [{
    "external_id": f"{PREFIX}-semana", "category": "NOTE", "start_date_local": f"{WEEK1.isoformat()}T00:00:00",
    "name": "Semana a bordo (Running Master)",
    "description": ("Semanas 1-3 de Carlos a bordo, 19 oct - 8 nov. Lun: HS + empuje + cadera. Mar: HS + tiron + "
                    "Z1. Mie: HS + empuje + accesorios (aqui va el HYROX si esa semana hay). Jue: HS + Z1 + "
                    "cuadriceps y pantorrilla. Vie: HS + tiron, sin pierna. Sab: HS + calidad + 1/2 empuje. Dom: "
                    "largo. Si pierdes una sesion de Carlos, no la recuperes al dia siguiente: escribele."),
}]
for w, spec in enumerate(WEEKS[:ON_BOARD_WEEKS], start=1):
    monday = WEEK1 + timedelta(weeks=w - 1)
    events += [
        z1_martes(monday + timedelta(days=1), w, spec["z1"]),
        z1_jueves(monday + timedelta(days=3), w, spec["z1"]),
        calidad(monday + timedelta(days=5), w, spec),
        largo(monday + timedelta(days=6), w, spec["long"]),
    ]


if __name__ == "__main__":
    OUT.write_text(json.dumps(events, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{OUT.name}: {len(events)} eventos")
