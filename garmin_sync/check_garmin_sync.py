#!/usr/bin/env python3
"""Prueba sin red de lo que se le manda a Garmin: el mapa y el armado del workout.

  ./.venv/bin/python check_garmin_sync.py

Revisa (1) que cada par category/exercise de exercise_map.json exista de verdad en el catálogo
de Garmin —un nombre inventado hace que el reloj muestre el ejercicio vacío—, (2) que un
ejercicio de HABIT de cada forma (rango, pirámide, aguante en segundos, al fallo, descanso en
minutos) se convierta en los pasos correctos, y (3) que todo stepOrder sea único, que es lo que
pide el editor de Garmin.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import garmin_sync as G  # noqa: E402
from garminconnect import exercises as X  # noqa: E402

fallos = []


def check(cond, msg):
    if not cond:
        fallos.append(msg)


# ── 1. el mapa apunta a ejercicios que existen ──────────────────────────────
mapa_json = json.loads((Path(__file__).parent / "exercise_map.json").read_text(encoding="utf-8"))
pares = {(e["category"], e["exercise"]) for e in X.EXERCISES}
categorias = {e["category"] for e in X.EXERCISES}
for clave, valor in mapa_json.items():
    if clave.startswith("_"):
        continue
    check(clave == G.plano(clave), f"la llave «{clave}» no está normalizada (usa plano())")
    cat, ejercicio = valor.get("category"), valor.get("exercise", "")
    check(cat in categorias, f"«{clave}»: la categoría {cat} no existe en Garmin")
    check(not ejercicio or (cat, ejercicio) in pares,
          f"«{clave}»: {ejercicio} no vive en la categoría {cat}")

# ── 2. cada forma de objetivo de HABIT se convierte bien ────────────────────
mapa = G.Mapa()
casos = [
    # (ejercicio de HABIT, cuántos bloques, qué revisar del primero)
    ({"name": "Hip thrust", "sets": "3", "reps": "8-10", "rest": "2 min"}, 1,
     {"reps": 8.0, "sets": 3, "descanso": 120, "categoria": "HIP_RAISE"}),
    ({"name": "Dominadas", "sets": "4", "reps": "10-9-8-7-6-5-4-3-2-1", "rest": "90s"}, 10,
     {"reps": 10.0, "sets": 1, "descanso": 90, "categoria": "PULL_UP"}),
    ({"name": "Aguante de front lever", "sets": "3", "reps": "20s", "rest": "3 min"}, 1,
     {"tiempo": 20.0, "sets": 3, "descanso": 180, "categoria": "CORE"}),
    ({"name": "Front press + negativa", "sets": "2", "reps": "al fallo", "rest": "3 min"}, 1,
     {"fallo": True, "sets": 2, "descanso": 180}),
    ({"name": "Movilidad de hombro (calentamiento)", "sets": "1", "reps": "10"}, 1,
     {"reps": 10.0, "sets": 1, "descanso": 0, "categoria": "WARM_UP"}),
    ({"name": "Press de banca", "sets": "4", "reps": "6", "rest": "150", "weight": "60"}, 1,
     {"reps": 6.0, "sets": 4, "descanso": 150, "kg": 60.0, "categoria": "BENCH_PRESS"}),
]
for ex, bloques_esperados, quiere in casos:
    bloques, _, info = G.pasos_de_ejercicio(ex, mapa, 1)
    nombre = ex["name"]
    check(len(bloques) == bloques_esperados,
          f"«{nombre}»: {len(bloques)} bloques, esperaba {bloques_esperados}")
    if not bloques:
        continue
    grupo = bloques[0]
    pasos = grupo.workoutSteps
    ejercicio, descanso = pasos[0], (pasos[1] if len(pasos) > 1 else None)
    if "sets" in quiere:
        check(grupo.numberOfIterations == quiere["sets"],
              f"«{nombre}»: {grupo.numberOfIterations} series, esperaba {quiere['sets']}")
    cond = (ejercicio.endCondition or {}).get("conditionTypeKey")
    if "reps" in quiere:
        check(cond == "reps" and ejercicio.endConditionValue == quiere["reps"],
              f"«{nombre}»: objetivo {cond} {ejercicio.endConditionValue}, esperaba reps {quiere['reps']}")
    if "tiempo" in quiere:
        check(cond == "time" and ejercicio.endConditionValue == quiere["tiempo"],
              f"«{nombre}»: objetivo {cond} {ejercicio.endConditionValue}, esperaba time {quiere['tiempo']}")
    if quiere.get("fallo"):
        check(cond == "lap.button", f"«{nombre}»: al fallo debería terminar con el botón, no {cond}")
    if "descanso" in quiere:
        real = descanso.endConditionValue if descanso else 0
        check(real == quiere["descanso"],
              f"«{nombre}»: descanso {real}s, esperaba {quiere['descanso']}s")
    if "categoria" in quiere:
        check(info["categoria"] == quiere["categoria"],
              f"«{nombre}»: categoría {info['categoria']}, esperaba {quiere['categoria']}")
    if "kg" in quiere:
        peso = getattr(ejercicio, "weightValue", None)
        check(peso == quiere["kg"] * 1000.0, f"«{nombre}»: peso {peso}, esperaba {quiere['kg']} kg en gramos")
    # El nombre de HABIT viaja en la nota del paso: en el reloj el ejercicio de Garmin puede
    # llamarse distinto, y lo que el socio reconoce es como lo escribió en la app.
    check(G.plano(nombre.split("(")[0]).split()[0] in G.plano(ejercicio.description or ""),
          f"«{nombre}»: la nota del paso no lleva el nombre de HABIT")

# ── 3. el workout completo: stepOrder único y nombre con fecha ──────────────
dia = "2026-11-03"
wk, mapeo = G.construir(dia, "Empuje y cadera", [c[0] for c in casos], mapa)
check(wk is not None, "construir() no armó el workout")
if wk:
    datos = wk["workout"].model_dump(exclude_none=True)
    pasos = datos["workoutSegments"][0]["workoutSteps"]

    def ordenes(lista):
        for p in lista:
            yield p["stepOrder"]
            for hijo in p.get("workoutSteps", []) or []:
                yield hijo["stepOrder"]

    todos = list(ordenes(pasos))
    check(len(todos) == len(set(todos)), f"hay stepOrder repetidos: {sorted(todos)}")
    check(datos["sportType"]["sportTypeKey"] == "strength_training", "el deporte no es fuerza")
    check(datos["workoutSegments"][0]["sportType"]["sportTypeKey"] == "strength_training",
          "el segmento no es de fuerza")
    check("3 nov" in wk["nombre"], f"el nombre no dice el día: {wk['nombre']}")
    check(G.MARCA in datos["description"] and dia in datos["description"],
          "la descripción no lleva la firma del sincronizador")
    check(len(mapeo) == len(casos), "el resumen del mapeo no cubre todos los ejercicios")

print(f"{len(mapa_json) - 1} entradas en el mapa, {len(casos)} formas de objetivo, "
      f"{len(todos) if wk else 0} pasos armados")
if fallos:
    print("\nFALLÓ:")
    for f in fallos:
        print("  -", f)
    sys.exit(1)
print("Todo bien.")
