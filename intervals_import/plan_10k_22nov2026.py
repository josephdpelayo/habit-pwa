#!/usr/bin/env python3
"""Bloque 10k (15 oct - 22 nov 2026), todo en cinta a bordo, con el metodo de Carlos Rojo Running.

    python3 plan_10k_22nov2026.py          # escribe plan_10k_22nov2026.json
    python3 intervals.py subir plan_10k_22nov2026.json [--commit]

Semana a bordo (prioridad: calistenia de Alge > carrera de Carlos Rojo > HYROX):
  lun HS + tiron + pierna para correr   | mar HS + empuje + HYROX
  mie HS + tiron + rodaje Z2 + rectas   | jue HS + empuje + HYROX
  vie HS + movilidad (+ bici Z2 suave)  | sab HS + umbral + 1/2 empuje y full body tranquilo
  dom rodaje largo Z2 de verdad
Los HYROX (TrainingPeaks) cargan pierna y empuje, por eso van detras del empuje del dia.
Pinceladas a ritmo 10k solo las 2 semanas antes de la carrera. Aqui solo va carrera y bici:
calistenia y HYROX viven en sus apps. Volver a generar y subir actualiza los mismos eventos.

Zonas de Carlos Rojo por % de FC maxima (FCmax 190 en Intervals.icu):
  Z1 <65% (<124)  Z2 65-80% (124-152)  Z3 80-85% "zona gris" (152-162, se evita)
  Z4 umbral 86-92% (163-175)  Z5 >92%
Umbral = ritmo de 10k + 15-20 s/km. Nada a tope: terminar "entero, con ganas de mas".
"""

import json
from pathlib import Path

# Se llena con el test del 17 oct: distancia de la cinta en km / 0.5 h = km/h medios.
# Ritmo 10k ~3% mas lento que ese promedio; umbral = ritmo 10k + 18 s/km.
TEST_30MIN_KMH = None

OUT = Path(__file__).with_name("plan_10k_22nov2026.json")
PREFIX = "joseph-10k-2026"

Z1, Z2, UMBRAL = "55-65% HR", "65-80% HR", "86-92% HR"
CINTA = "Cinta al 1% de inclinacion. Con mar movida: clip de seguridad y baja 0.5 km/h en lo rapido."


def velocidades():
    if not TEST_30MIN_KMH:
        return ("Velocidades: salen del test del 17 oct. Mientras, umbral = RPE 7-8 (frases cortas, "
                "sostenible ~1 h) y ritmo 10k un punto mas, sin llegar a tope.")
    v10 = TEST_30MIN_KMH / 1.03
    s10 = 3600 / v10
    su = s10 + 18
    pace = lambda s: f"{int(s) // 60}:{round(s) % 60:02d}/km"
    return (f"Umbral: {3600 / su:.1f} km/h ({pace(su)}). Ritmo 10k: {v10:.1f} km/h ({pace(s10)}). "
            "Si la FC del umbral pasa de 175, baja 0.2 km/h.")


def event(day, code, kind, name, prose, steps="", category="WORKOUT"):
    e = {"external_id": f"{PREFIX}-{day}-{code.lower()}", "category": category,
         "start_date_local": f"{day}T00:00:00", "name": f"{code} - {name}",
         "description": prose + ("\n\n" + steps if steps else "")}
    if kind:
        e["type"] = kind
    return e


RECTAS = f"Rectas 4x\n- Recta progresiva 20s\n- Trote suave 60s {Z1}"


def bici(day, code, minutes, extra=""):
    return event(day, code, "Ride", f"Bici Z2 muy suave {minutes} (opcional)",
                 "Opcional: soltar piernas antes del umbral de manana. Muy suave (65-75% FCmax, "
                 f"124-143), cadencia 85-95, sin resistencia. Si vienes cargado del HYROX, mejor descansa.{extra}",
                 f"- Suave 5m {Z1}\n- Rodar {minutes - 10}m 65-75% HR\n- Suelta 5m {Z1}")


def rodaje(day, code, minutes, rectas=True):
    steps = f"Rodaje\n- Trote {minutes}m {Z2}"
    if rectas:
        steps += "\n\n" + RECTAS
    return event(day, code, "Run", f"Rodaje Z2 {minutes}" + (" + rectas" if rectas else ""),
                 "Suave de verdad: tienes que poder conversar. Techo 152 ppm, lo ideal 135-148; si "
                 "subes, baja 0.3 km/h. Sin objetivo de ritmo. Ayer fue HYROX: si hay agujetas, las "
                 f"rectas suaves o fuera. Corre despues del tiron, no antes. {CINTA}",
                 steps)


def larga(day, code, minutes):
    return event(day, code, "Run", f"Rodaje largo Z2 {minutes}",
                 "Largo de verdad en Z2: nada de acelerar al final. La FC tiende a subir con el "
                 "tiempo (y con el calor del barco): si pasa de 152, baja la cinta, aunque el ritmo "
                 f"se vaya. Hidratate cada 20 min. {CINTA}",
                 f"Largo\n- Trote {minutes}m {Z2}")


def calidad(day, code, title, objetivo, main):
    warm = f"Calentamiento\n- Trote muy suave 15m {Z2}"
    cool = f"Enfriamiento\n- Trote muy suave 10m {Z1}"
    return event(day, code, "Run", title,
                 f"{objetivo}\n{velocidades()}\nNo es a tope: gestiona el ritmo y termina entero. "
                 "Llega 48 h despues del HYROX del jueves: si las piernas pesan, umbral en la parte "
                 f"baja (163-168) o un bloque menos. Handstand antes de correr, 1/2 empuje despues. {CINTA}",
                 "\n\n".join([warm, main, cool]))


def umbral(reps, minutes, rest):
    return f"Umbral {reps}x\n- Umbral {minutes}m {UMBRAL}\n- Trote {rest} {Z1}"


def pinceladas(reps, length, rest):
    return f"Pinceladas a ritmo de carrera {reps}x\n- Ritmo carrera {length}\n- Trote {rest} {Z1}"


events = [
    # Semana 0 (15-18 oct): HYROX el jueves a 2 rondas (step-ups, no box jumps), y medir.
    bici("2026-10-16", "B0", 30, " Esta semana el HYROX va el jueves a 2 rondas, para llegar fresco al test."),
    event("2026-10-17", "T1", "Run", "Test 30 min",
          "El punto de partida: con esto se fijan las velocidades de umbral y de 10k. Corre 30 min "
          "lo mas fuerte que puedas sostener PAREJO (empieza conservador, ultimos 5 min a tope). "
          "Anota la distancia de la cinta y, al guardar en el reloj, calibra con esa distancia. La FC "
          f"media de los ultimos 20 min es tu umbral real. {CINTA}",
          f"Calentamiento\n- Trote muy suave 15m {Z2}\n\n{RECTAS}\n\nTest\n- Parejo 10m\n- Parejo 20m"
          f"\n\nEnfriamiento\n- Trote muy suave 10m {Z1}"),
    larga("2026-10-18", "L0", 60),

    # Semana 1 (19-25 oct): introducir el umbral, ~22 km.
    rodaje("2026-10-21", "E1", 40),
    bici("2026-10-23", "B1", 35),
    calidad("2026-10-24", "Q1", "Umbral 2x10",
            "20 min de umbral, el equivalente al primer 4000 de Carlos Rojo. Solo umbral: las pinceladas "
            "llegan cerca de la carrera.",
            umbral(2, 10, "2m")),
    larga("2026-10-25", "L1", 65),

    # Semana 2 (26 oct - 1 nov): mas umbral, ~24 km.
    rodaje("2026-10-28", "E2", 40),
    bici("2026-10-30", "B2", 35),
    calidad("2026-10-31", "Q2", "Umbral 3x8", "24 min de umbral.", umbral(3, 8, "2m")),
    larga("2026-11-01", "L2", 70),

    # Semana 3 (2-8 nov): pico, ~26 km.
    rodaje("2026-11-04", "E3", 45),
    bici("2026-11-06", "B3", 35),
    calidad("2026-11-07", "Q3", "Umbral 2x15 + pinceladas",
            "30 min de umbral en dos bloques largos (su 3x4000 adaptado a tu nivel) y 3 x 2 min a ritmo de 10k.",
            umbral(2, 15, "3m") + "\n\n" + pinceladas(3, "2m", "2m")),
    larga("2026-11-08", "L3", 80),

    # Semana 4 (9-15 nov): la sesion de Carlos Rojo para 10k, empieza a bajar, ~22 km.
    rodaje("2026-11-11", "E4", 40),
    bici("2026-11-13", "B4", 35),
    calidad("2026-11-14", "Q4", "Progresivo 12-9-6-3",
            "Su 4000-3000-2000-1000 en tiempo: los dos primeros a umbral, los dos ultimos a ritmo de 10k. "
            "La ultima sesion dura antes de la carrera.",
            f"Progresivo de umbral a ritmo de carrera\n- Umbral 12m {UMBRAL}\n- Trote 2m {Z1}\n"
            f"- Umbral 9m {UMBRAL}\n- Trote 2m {Z1}\n- Ritmo carrera 6m\n- Trote 2m {Z1}\n- Ritmo carrera 3m"),
    larga("2026-11-15", "L4", 65),

    # Semana 5 (16-22 nov): afinar y correr.
    event("2026-11-16", "N1", None, "Semana de carrera",
          "Lunes: pierna ligera (hack squat y extension suaves, sin fallo; gemelo y tibial normal). "
          "Martes: HYROX suave, 2 rondas y sin saltos. Miercoles: rodaje corto. Jueves: sin HYROX, "
          "activacion. Viernes: descanso. Sabado: soltar piernas, sin full body. Domingo: 10K.",
          category="NOTE"),
    rodaje("2026-11-18", "E5", 30, rectas=False),
    event("2026-11-19", "A1", "Run", "Activacion 20 + 3x2",
          f"Activacion, no entrenamiento: terminar con ganas. Hoy sin HYROX y el empuje a la mitad. {CINTA}",
          f"Rodaje\n- Trote 15m {Z2}\n\n" + pinceladas(3, "2m", "2m") + f"\n\nSoltar\n- Trote 5m {Z1}"),
    event("2026-11-21", "S1", "Run", "Soltar piernas 15",
          "Dia antes de la carrera: 15 min suaves y 3 rectas. Hoy sin full body; handstand si quieres. "
          "Cena normal, nada nuevo.",
          f"Soltar\n- Trote 15m {Z1}\n\nRectas 3x\n- Recta progresiva 20s\n- Trote suave 60s {Z1}"),
    event("2026-11-22", "C1", "Run", "10K carrera objetivo",
          "Calienta 15 min muy suave + 3 rectas. Km 1-2 un poco por debajo del ritmo objetivo, km 3-8 "
          "parejo, km 9-10 todo lo que quede. Nada nuevo el dia de la carrera (comida, tenis, ropa).",
          category="RACE_A"),
]


if __name__ == "__main__":
    OUT.write_text(json.dumps(events, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{OUT.name}: {len(events)} eventos")
