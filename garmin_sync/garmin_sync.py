#!/usr/bin/env python3
"""Tu semana de fuerza de HABIT -> workouts de fuerza en Garmin Connect -> el reloj.

Por qué no va por Intervals.icu (que es como viajan correr y bici): Intervals manda al reloj
los entrenos planificados, pero en fuerza su exportador a Garmin ignora ejercicio, reps y peso
—los pasos sin duración se descartan— así que al reloj llegan bloques de tiempo ("Go 0:40")
sin nombre de ejercicio ni repeticiones. Para *seguir* el entreno en el Venu 4 (animación,
cuenta de reps, peso por serie) el workout tiene que nacer como workout de fuerza de Garmin
Connect. Eso es lo que hace este archivo, leyendo HABIT como fuente de la verdad: cambias la
rutina en la app, corres `sync` y el reloj se entera.

HABIT se lee **como tú**, con la llave anon pública que ya vive en app.html y tu propia sesión
(la RLS hace el resto): no hace falta la service-role aquí. La contraseña se pide oculta una
sola vez y no se guarda; lo que queda en el Llavero es el refresh token.

Uso:
  ./habit-garmin login-habit [--email ...]   # una vez: sesión de HABIT en el Llavero
  ./habit-garmin login-garmin --email ...    # una vez: tokens de Garmin en ~/.garminconnect
  ./habit-garmin semana [--dias 14]          # qué hay planeado y cómo se mapea cada ejercicio
  ./habit-garmin sync [--dias 14] [--commit] # vista previa; con --commit escribe en Garmin
  ./habit-garmin limpiar [--commit]          # borra de Garmin todo lo que subió este programa
"""

import argparse
import getpass
import hashlib
import json
import os
import re
import subprocess
import sys
import unicodedata
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
STATE_DIR = Path.home() / ".habit-garmin"
STATE_FILE = STATE_DIR / "state.json"
CONFIG_FILE = STATE_DIR / "config.json"
# Copia instalada: macOS protege ~/Downloads y a un agente de launchd le niega hasta ejecutar
# un archivo que viva ahí ("Operation not permitted"), por mucho que la Terminal sí pueda. Así
# que lo automático corre desde aquí, fuera de cualquier carpeta protegida, y de paso deja de
# depender de cómo se llame la carpeta del repo.
APP_DIR = STATE_DIR / "app"
AGENTE = "app.habittraininghub.garmin-sync"
PLIST = Path.home() / "Library" / "LaunchAgents" / f"{AGENTE}.plist"
GARMIN_TOKENS = str(Path.home() / ".garminconnect")
KEYCHAIN_SERVICE = "habit-supabase"
MAZ_UTC_OFFSET_H = 7           # America/Mazatlan, igual que la app
DEFAULT_REST_SEC = 90          # igual que DEFAULT_REST_SEC en app.html
MARCA = "habit-sync"           # firma en la descripción: así se reconoce lo subido desde aquí
# "Al fallo" no es un número de reps. Garmin sí sabe terminar un paso con el botón de vuelta,
# que es exactamente eso: haz hasta donde llegues y presiona. Si tu reloj lo rechazara, pon
# esto en False y se suben como un objetivo de reps (el de FALLO_REPS).
FALLO_LAP_BUTTON = True
FALLO_REPS = 8
# El mismo sportType que StrengthWorkout trae por omisión; el segmento también lo pide.
DEPORTE_FUERZA = {"sportTypeId": 5, "sportTypeKey": "strength_training", "displayOrder": 5}


# ── HABIT: configuración y sesión ────────────────────────────────────────────

def habit_config():
    """SUPABASE_URL y la llave anon (pública): de la copia instalada, o de app.html.

    Instalado fuera del repo no hay app.html que leer, así que `instalar` deja esos dos valores
    en config.json. Es la llave anon, la misma que cualquiera ve en el código de la app.
    """
    if CONFIG_FILE.exists():
        cfg = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        if cfg.get("supabase_url") and cfg.get("supabase_anon_key"):
            return cfg["supabase_url"], cfg["supabase_anon_key"]
    src = (REPO / "app.html").read_text(encoding="utf-8", errors="replace")
    url = re.search(r"const SUPABASE_URL='([^']+)'", src)
    key = re.search(r"const SUPABASE_KEY='([^']+)'", src)
    if not url or not key:
        raise SystemExit("No encontré SUPABASE_URL / SUPABASE_KEY en app.html.")
    return url.group(1), key.group(1)


def keychain_get():
    out = subprocess.run(["security", "find-generic-password", "-a", os.environ.get("USER", ""),
                          "-s", KEYCHAIN_SERVICE, "-w"], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def keychain_set(value):
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)
    subprocess.run(["security", "add-generic-password", "-U", "-a", os.environ.get("USER", ""),
                    "-s", KEYCHAIN_SERVICE, "-w", value], check=True, capture_output=True)


def http(url, body=None, headers=None, method=None):
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    req = Request(url, data=data, method=method or ("POST" if data else "GET"),
                  headers={"Content-Type": "application/json", "Accept": "application/json",
                           "User-Agent": "habit-garmin-sync/1.0", **(headers or {})})
    try:
        with urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:400]
        raise SystemExit(f"{url.split('?')[0]} respondió {exc.code}: {detail}")
    except URLError as exc:
        raise SystemExit(f"No pude conectar con {url.split('/')[2]}: {exc.reason}")
    return json.loads(raw) if raw else None


class Habit:
    """Lo mínimo de Supabase: iniciar sesión, refrescar y leer tus propias filas."""

    def __init__(self):
        self.url, self.anon = habit_config()
        self.token = None
        self.uid = None

    def _auth(self, grant, body):
        return http(f"{self.url}/auth/v1/token?grant_type={grant}", body,
                    {"apikey": self.anon})

    def login(self, email, password):
        res = self._auth("password", {"email": email, "password": password})
        keychain_set(res["refresh_token"])
        self.token, self.uid = res["access_token"], res["user"]["id"]
        return res["user"]

    def resume(self):
        refresh = keychain_get()
        if not refresh:
            raise SystemExit("No hay sesión de HABIT guardada. Corre primero: ./habit-garmin login-habit")
        res = self._auth("refresh_token", {"refresh_token": refresh})
        # Supabase rota el refresh token en cada uso: si no se guarda el nuevo, el siguiente
        # arranque se queda fuera y hay que volver a teclear la contraseña.
        keychain_set(res["refresh_token"])
        self.token, self.uid = res["access_token"], res["user"]["id"]
        return res["user"]

    def rest(self, path):
        return http(f"{self.url}/rest/v1/{path}",
                    headers={"apikey": self.anon, "Authorization": f"Bearer {self.token}"})

    def rpc(self, name, args):
        return http(f"{self.url}/rest/v1/rpc/{name}", args,
                    {"apikey": self.anon, "Authorization": f"Bearer {self.token}"})


# ── Fechas de Mazatlán ──────────────────────────────────────────────────────

def hoy_maz():
    return (datetime.now(timezone.utc) - timedelta(hours=MAZ_UTC_OFFSET_H)).date()


def lunes(d):
    return d - timedelta(days=d.weekday())


DIAS = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]


def etiqueta_dia(ds):
    d = date.fromisoformat(ds)
    return f"{DIAS[d.weekday()]} {d.day} {MESES[d.month - 1]}"


# ── La semana de HABIT ──────────────────────────────────────────────────────

def leer_semana(habit, desde, hasta, estampar=True):
    """Los días planeados con su rutina, tal como los ve la app."""
    if estampar:
        # ensure_coaching_week_from_template es lo que estampa el calendario desde el programa
        # o la plantilla; sin esto, una semana que nadie ha abierto en la app viene vacía.
        semana = lunes(desde)
        while semana <= hasta:
            try:
                habit.rpc("ensure_coaching_week_from_template",
                          {"p_user_id": habit.uid, "p_week_start": semana.isoformat()})
            except SystemExit as exc:
                print(f"  (no pude estampar la semana del {semana}: {exc})", file=sys.stderr)
            semana += timedelta(days=7)

    cols = "id,ds,status,board_id,session_exercises,program_id"
    filas = habit.rest(f"coaching_schedule?select={cols}&user_id=eq.{habit.uid}"
                       f"&ds=gte.{desde}&ds=lte.{hasta}&order=ds") or []
    ids = sorted({f["board_id"] for f in filas if f.get("board_id")})
    rutinas = {}
    if ids:
        lista = habit.rest("boards?select=id,name,exercises,owner_id,is_starter"
                           f"&id=in.({','.join(ids)})") or []
        rutinas = {b["id"]: b for b in lista}
    return filas, rutinas


def ejercicios_del_dia(fila, rutinas):
    """base de la rutina + lo cambiado en la sesión, con la misma regla que sessionExerciseList."""
    board = rutinas.get(fila.get("board_id")) or {}
    base = board.get("exercises") or []
    overlay = fila.get("session_exercises") or []
    if not isinstance(base, list):
        base = []
    if not isinstance(overlay, list):
        overlay = []
    reemplaza = {o["replaces"]: o for o in overlay if isinstance(o, dict) and o.get("replaces")}
    fuera = {o["replaces"] for o in overlay
             if isinstance(o, dict) and o.get("replaces") and (o.get("removed") or not o.get("ex_key"))}
    salida = []
    for i, ex in enumerate(base):
        if not isinstance(ex, dict):
            continue
        clave = ex.get("id") or f"{fila.get('board_id')}_idx_{i}"
        if clave in fuera:
            continue
        sub = reemplaza.get(clave)
        salida.append(sub if sub else ex)
    salida += [o for o in overlay if isinstance(o, dict)
               and not o.get("replaces") and not o.get("removed") and o.get("ex_key")]
    return salida


# ── Objetivos: reps, tiempo, pirámide, descanso ─────────────────────────────

def pyramid_steps(raw):
    """10-9-8-7… es un objetivo por serie. Dos escalones son un rango, no una pirámide."""
    partes = re.split(r"[-–/,]", str(raw or ""))
    nums = [int(p) for p in (x.strip() for x in partes) if p.isdigit()]
    return nums if len(nums) >= 3 and len(nums) == len(partes) else None


def target_type(ex):
    if ex.get("repsType"):
        return ex["repsType"]
    v = str(ex.get("reps") or "").strip().lower()
    if re.search(r"[:sm]", v) and not re.match(r"^\d+\s*(?:-|–|a)\s*\d+$", v):
        return "time"
    return "pyramid" if pyramid_steps(v) else "reps"


def set_count(ex):
    pasos = pyramid_steps(ex.get("reps")) if target_type(ex) == "pyramid" else None
    if pasos:
        return len(pasos)
    try:
        return max(1, int(str(ex.get("sets") or "1").strip() or 1))
    except ValueError:
        return 1


def reps_from_target(target):
    """Igual que defaultRepsFromTarget: un rango vale su piso ("8-10" -> 8)."""
    t = str("" if target is None else target).strip()
    m = re.match(r"^(\d{1,3})$", t)
    if m:
        return int(m.group(1))
    m = re.match(r"^(\d{1,3})\s*(?:-|–|a)\s*(\d{1,3})$", t, re.I)
    return int(m.group(1)) if m else None


def seconds_from_target(target):
    v = str(target or "").strip().lower().replace(" ", "")
    m = re.match(r"^(\d{1,2}):([0-5]?\d)$", v)
    if m:
        return int(m.group(1)) * 60 + int(m.group(2))
    m = re.match(r"^(\d+)m(?:(\d{1,2})s?)?$", v)
    if m:
        return int(m.group(1)) * 60 + int(m.group(2) or 0)
    m = re.match(r"^(\d+)\s*(?:s|seg|segundos?)$", v)
    if m:
        return int(m.group(1))
    m = re.match(r"^(\d+)\s*(?:min|minutos?)$", v)
    return int(m.group(1)) * 60 if m else None


def rest_seconds(ex):
    m = re.search(r"(\d+)", str(ex.get("rest") or ""))
    if not m:
        return 0 if es_calentamiento(ex) else DEFAULT_REST_SEC
    n = int(m.group(1))
    return n * 60 if re.search(r"min", str(ex.get("rest")), re.I) else n


def es_calentamiento(ex):
    txt = " ".join(str(ex.get(k) or "") for k in ("name", "category", "type"))
    return bool(re.search(r"calentamiento|warm.?up|movilidad|mobility|estiramiento|stretch", txt, re.I))


def es_al_fallo(target):
    t = str(target or "").strip().lower()
    return bool(re.match(r"^(failure|al fallo|fallo|amrap|max|máx(imo)?|rondas?|rounds?)$", t))


def peso_kg(ex):
    for k in ("weight", "weight_kg", "kg", "peso"):
        v = ex.get(k)
        if v in (None, "", False):
            continue
        m = re.search(r"(\d+(?:[.,]\d+)?)", str(v))
        if m:
            return float(m.group(1).replace(",", "."))
    return None


# ── Mapa HABIT -> catálogo de Garmin ────────────────────────────────────────

def plano(s):
    s = unicodedata.normalize("NFD", str(s or "")).encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", s)).strip()


# Mismas reglas (y el mismo orden: lo específico gana) que HabitTraining.exercisePattern,
# porque el nombre es lo único que traen muchos ejercicios escritos a mano.
PATTERN_RULES = [
    ("handstand", r"parada de manos|handstand|\bpino\b|hspu|wall walk|caminata en (la )?pared"),
    ("cardio", r"remadora|ergometr|concept ?2|\bbici|bike|assault|cinta|correr|carrera|\brun\b|running|trote|caminar|caminata|\bwalk|saltar (la )?cuerda|comba|jumping jack|burpee|climber|escalador|sprint|cardio|eliptic|ski ?erg|trineo|sled|shuttle"),
    ("lever", r"front lever|back lever|front (press|tuck)|half press|tuck advanced|touch tuck|skin the cat|dragon flag|human flag|bandera"),
    ("planche", r"planche|90 grados|90 degree|maltese"),
    ("pull", r"dominad|pull ?-?ups?\b|chin ?-?ups?\b|muscle ?-?ups?\b|jalon|lat ?pull|colgad|dead ?hang|\bhang\b"),
    ("row", r"\bremo\b|\brows?\b|face ?pull|australian|invertid|serrucho|pull ?over|pullover"),
    ("overhead", r"pike|\bpica\b|press militar|press (de )?hombros?|overhead|militar|arnold|elevacion(es)? (lateral|frontal)|lateral raise|front raise|push press|jerk|landmine press|z ?press"),
    ("dip", r"\bfondos?\b|\bdips?\b"),
    ("bench", r"press (de |en )?banca|bench|press (de )?pecho|press (inclinado|declinado)|aperturas?|\bfly\b|flyes|cruce de poleas|pec ?deck|chest press"),
    ("hinge", r"peso muerto|deadlift|\brdl\b|rumano|hip thrust|empuje de cadera|puente( de)? gluteo|glute bridge|good ?morning|buenos dias|swing|hiperextension|nordic|nordico|curl femoral|leg curl|patada de gluteo|kickback de gluteo"),
    ("calf", r"pantorrilla|gemelo|soleo|talones|calf"),
    ("squat", r"sentadilla|squat|zancada|lunge|estocada|split|bulgara|prensa|leg press|pistol|step ?-?up|subida al cajon|box jump|salto al cajon|sissy|extension de (cuadriceps|piernas)|leg extension|wall sit"),
    ("mobility", r"flexion de (cadera|rodilla|muneca|tobillo)|flexores de cadera"),
    ("pushup", r"flexion|lagartija|push ?-?ups?\b|pushup"),
    ("core", r"abdominal|crunch|plancha|plank|hollow|l-?sit|elevacion(es)? de (piernas|rodillas)|leg raise|knee raise|rueda|ab ?wheel|russian|rusa|oblicu|dead ?bug|bicho muerto|pallof|v-?ups?\b|toes to bar|sit ?-?ups?\b|\bcore\b|bird ?dog|superman"),
    ("arms", r"curl|bicep|tricep|rompecraneo|skull|press frances|patada de tricep|martillo|hammer|antebrazo|muneca|wrist|farmer|granjero"),
    ("mobility", r"calentamiento|movilidad|mobility|estiramiento|stretch|warm ?-?up|entrada en calor|rotacion|circulos|foam|rodillo|respiracion|escapular|scapular"),
]
MUSCLE_RULES = [
    ("squat", r"pierna|cuadricep|gluteo|isquio|femoral|leg|quad|glute|hamstring"),
    ("calf", r"pantorrilla|gemelo|calf"),
    ("row", r"espalda|dorsal|trapecio|back|lats?\b|trap"),
    ("bench", r"pecho|pectoral|chest"),
    ("overhead", r"hombro|deltoid|shoulder"),
    ("core", r"abdomen|abdominal|core|oblicu|\babs?\b"),
    ("arms", r"bicep|tricep|brazo|antebrazo|arm|forearm"),
]
# Cada patrón cae en una categoría de Garmin: es el piso cuando no hay un ejercicio exacto.
# El reloj enseña la categoría cuando el nombre va vacío, así que el piso sigue siendo útil.
PATTERN_CATEGORY = {
    "handstand": "PUSH_UP", "cardio": "CARDIO", "lever": "CORE", "planche": "CORE",
    "pull": "PULL_UP", "row": "ROW", "overhead": "SHOULDER_PRESS", "dip": "TRICEPS_EXTENSION",
    "bench": "BENCH_PRESS", "hinge": "DEADLIFT", "calf": "CALF_RAISE", "squat": "SQUAT",
    "pushup": "PUSH_UP", "core": "CORE", "arms": "CURL", "mobility": "WARM_UP",
    "strength": "TOTAL_BODY",
}
# Español -> inglés, palabra por palabra, para poder buscar en el catálogo de Garmin.
LEXICO = {
    "sentadilla": "squat", "sentadillas": "squat", "flexion": "push up", "flexiones": "push up",
    "lagartija": "push up", "lagartijas": "push up", "dominada": "pull up", "dominadas": "pull up",
    "jalon": "lat pull down", "remo": "row", "peso": "", "muerto": "deadlift",
    "pesomuerto": "deadlift", "rumano": "romanian", "banca": "bench", "press": "press",
    "militar": "overhead", "hombro": "shoulder", "hombros": "shoulder", "pecho": "chest",
    "espalda": "back", "pierna": "leg", "piernas": "leg", "cuadriceps": "leg",
    "femoral": "leg curl", "isquiotibiales": "hamstring", "gluteo": "glute", "gluteos": "glute",
    "pantorrilla": "calf", "pantorrillas": "calf", "gemelo": "calf", "gemelos": "calf",
    "tricep": "triceps", "triceps": "triceps", "bicep": "biceps", "biceps": "biceps",
    "curl": "curl", "mancuerna": "dumbbell", "mancuernas": "dumbbell", "barra": "barbell",
    "polea": "cable", "poleas": "cable", "cuerda": "rope", "maquina": "machine",
    "cable": "cable", "inclinado": "incline", "declinado": "decline", "plano": "flat",
    "lateral": "lateral", "frontal": "front", "elevacion": "raise", "elevaciones": "raise",
    "extension": "extension", "extensiones": "extension", "zancada": "lunge",
    "zancadas": "lunge", "desplante": "lunge", "desplantes": "lunge", "estocada": "lunge",
    "bulgara": "bulgarian split squat", "prensa": "leg press", "abdominal": "crunch",
    "abdominales": "crunch", "plancha": "plank", "puente": "bridge", "cadera": "hip",
    "empuje": "thrust", "fondos": "dip", "paralelas": "dip", "pino": "handstand",
    "pica": "pike", "apertura": "fly", "aperturas": "fly", "encogimiento": "shrug",
    "encogimientos": "shrug", "hiperextension": "hyperextension", "sueco": "swiss ball",
    "unilateral": "single", "pie": "standing", "sentado": "seated", "acostado": "lying",
    "tumbado": "lying", "agarre": "grip", "cerrado": "close", "abierto": "wide",
    "neutro": "neutral", "salto": "jump", "saltos": "jump", "lastre": "weighted",
    "lastrada": "weighted", "lastradas": "weighted", "negativa": "negative",
    "negativas": "negative", "aguante": "hold", "aguantes": "hold", "isometrico": "hold",
    "rodilla": "knee", "rodillas": "knee", "tobillo": "ankle", "muneca": "wrist",
    "escapular": "scapular", "retraccion": "retraction", "rotacion": "rotation",
    "externa": "external", "interna": "internal", "goblet": "goblet", "copa": "goblet",
    "paso": "step up", "cajon": "box", "caminata": "walk", "granjero": "farmers",
    "subida": "", "bajada": "", "con": "", "de": "", "del": "", "en": "", "el": "", "la": "",
    "los": "", "las": "", "al": "", "por": "", "para": "", "a": "", "y": "", "o": "",
    "cada": "", "lado": "", "pierna2": "",
}
# Palabras que no ayudan a encontrar el ejercicio en Garmin (son dosis, no movimiento).
RUIDO = {"serie", "series", "rep", "reps", "repeticiones", "min", "seg", "rir", "opcional",
         "superserie", "circuito", "bloque", "warmup"}


def traducir(nombre):
    fuera = []
    for tok in plano(nombre).split():
        t = LEXICO.get(tok, tok)
        if not t or t in RUIDO:
            continue
        fuera.extend(t.split())
    # "peso muerto" se traduce palabra por palabra y "peso" se borra: queda "deadlift".
    return [t for t in fuera if t]


def patron(ex):
    nombre = plano(ex.get("name"))
    for clave, regex in PATTERN_RULES:
        if re.search(regex, nombre):
            return clave
    musculos = plano(" ".join(str(ex.get(k) or "") for k in
                              ("muscles", "primary_muscle", "primaryMuscle", "category")))
    for clave, regex in MUSCLE_RULES:
        if re.search(regex, musculos):
            return clave
    return "strength"


class Mapa:
    """Nombre en español de HABIT -> (category, exerciseName) del catálogo de Garmin."""

    def __init__(self):
        from garminconnect import exercises as X
        self.catalogo = [{**e, "_norm": plano(e["name"]), "_toks": set(plano(e["name"]).split())}
                         for e in X.EXERCISES]
        self.por_norm = {}
        for e in self.catalogo:
            self.por_norm.setdefault(e["_norm"], e)
        ruta = HERE / "exercise_map.json"
        self.overrides = json.loads(ruta.read_text(encoding="utf-8")) if ruta.exists() else {}
        # En HABIT los ejercicios se llaman como se hablan: "Flexiones de pino profundas en
        # pared en paralelas". Fijar el nombre completo de cada uno sería interminable, así que
        # una llave de dos palabras o más vale también dentro de un nombre más largo, de la más
        # específica a la más general. Las de una sola palabra, no: "flexiones" dentro de
        # "flexiones de pino libre" apuntaría a la lagartija y no al pino.
        self.parciales = sorted(
            ((k, v) for k, v in self.overrides.items()
             if not k.startswith("_") and len(k.split()) >= 2),
            key=lambda kv: (-len(kv[0].split()), -len(kv[0])))

    def resolver(self, ex):
        """Devuelve (category, exerciseName, cómo se resolvió)."""
        firma = plano(ex.get("name"))
        o = self.overrides.get(firma)
        if not o:
            for clave, valor in self.parciales:
                if re.search(r"\b" + re.escape(clave) + r"\b", firma):
                    o = valor
                    break
        if o:
            return o.get("category") or PATTERN_CATEGORY[patron(ex)], o.get("exercise", ""), "mapa"

        pat = patron(ex)
        categoria_piso = PATTERN_CATEGORY.get(pat, "TOTAL_BODY")
        toks = traducir(ex.get("name"))
        if toks:
            consulta = " ".join(toks)
            exacto = self.por_norm.get(consulta)
            if exacto:
                return exacto["category"], exacto["exercise"], "exacto"
            pedido = set(toks)
            # Todos los tokens dentro del nombre del catálogo: se prefiere el nombre más corto,
            # que es el más genérico ("Leg Curl" antes que "Single-leg Sliding Leg Curl").
            dentro = [e for e in self.catalogo if pedido <= e["_toks"]]
            if dentro:
                mejor = sorted(dentro, key=lambda e: (e["category"] != categoria_piso, len(e["_toks"])))[0]
                return mejor["category"], mejor["exercise"], "contiene"
            # Parcial: al menos dos tokens y 60% de lo pedido, con la categoría del patrón
            # desempatando, para no acabar en "Battle Rope" por la palabra "rope".
            puntuados = []
            for e in self.catalogo:
                comunes = pedido & e["_toks"]
                if len(comunes) >= 2 and len(comunes) / len(pedido) >= 0.6:
                    puntuados.append((e["category"] != categoria_piso,
                                      -len(comunes) / len(e["_toks"]), len(e["_toks"]), e))
            if puntuados:
                e = sorted(puntuados, key=lambda x: x[:3])[0][3]
                return e["category"], e["exercise"], "parecido"
        return categoria_piso, "", "categoría"


# ── Construir el workout de Garmin ──────────────────────────────────────────

def pasos_de_ejercicio(ex, mapa, orden):
    """Un ejercicio de HABIT -> uno o más bloques de series de Garmin."""
    from garminconnect import workout as W

    categoria, nombre_g, origen = mapa.resolver(ex)
    descanso = rest_seconds(ex)
    kg = peso_kg(ex)
    tipo = target_type(ex)
    nota = " · ".join(x for x in [str(ex.get("name") or "").strip(),
                                  str(ex.get("note") or ex.get("notes") or "").strip()] if x)[:255]
    bloques, detalle = [], []

    def exacto(sets, target):
        nonlocal orden
        if tipo == "time" or (isinstance(target, str) and seconds_from_target(target)):
            segs = seconds_from_target(target) or 30
            bloques.append(W.create_strength_timed_set(categoria, orden, sets, segs, descanso,
                                                       exercise_name=nombre_g, weight_kg=kg,
                                                       description=nota))
            detalle.append(f"{sets}×{segs}s")
        elif es_al_fallo(target) and FALLO_LAP_BUTTON:
            # Al fallo: el paso termina con el botón de vuelta, no con una cuenta inventada.
            paso = W._strength_exercise_step(
                categoria, orden + 1,
                {"conditionTypeId": W.ConditionType.LAP_BUTTON, "conditionTypeKey": "lap.button",
                 "displayOrder": 15, "displayable": True},
                1.0, nombre_g, kg, (nota + " · al fallo")[:255])
            pasos = [paso]
            if descanso:
                pasos.append(W.create_strength_rest_step(descanso, orden + 2))
            bloques.append(W.create_repeat_group(sets, pasos, orden))
            detalle.append(f"{sets}× al fallo")
        else:
            reps = reps_from_target(target) or (FALLO_REPS if es_al_fallo(target) else 10)
            bloques.append(W.create_strength_set(categoria, orden, sets, reps, descanso,
                                                 exercise_name=nombre_g, weight_kg=kg,
                                                 description=nota))
            detalle.append(f"{sets}×{reps}")
        orden += 3

    pasos_piramide = pyramid_steps(ex.get("reps")) if tipo == "pyramid" else None
    if pasos_piramide:
        # Una pirámide es un objetivo distinto por serie: un bloque de una serie por escalón.
        for escalon in pasos_piramide:
            exacto(1, escalon)
    else:
        exacto(set_count(ex), ex.get("reps"))

    return bloques, orden, {"categoria": categoria, "garmin": nombre_g or "(categoría)",
                            "origen": origen, "detalle": "+".join(detalle),
                            "descanso": descanso, "kg": kg}


def construir(ds, board_name, ejercicios, mapa):
    from garminconnect import workout as W

    pasos, orden, mapeo = [], 1, []
    for ex in ejercicios:
        if not isinstance(ex, dict) or not str(ex.get("name") or "").strip():
            continue
        bloques, orden, info = pasos_de_ejercicio(ex, mapa, orden)
        pasos.extend(bloques)
        info["habit"] = str(ex.get("name")).strip()
        info["objetivo"] = str(ex.get("reps") or "").strip()
        mapeo.append(info)
    if not pasos:
        return None, []

    nombre = f"{(board_name or 'Entreno').strip()} · {etiqueta_dia(ds)}"[:80]
    duracion = 0
    for b in pasos:
        iteraciones = getattr(b, "numberOfIterations", 1) or 1
        for p in getattr(b, "workoutSteps", [b]):
            cond = (getattr(p, "endCondition", {}) or {}).get("conditionTypeKey")
            valor = getattr(p, "endConditionValue", 0) or 0
            duracion += iteraciones * (valor if cond == "time" else valor * 4)
    firma = hashlib.sha1(json.dumps([m for m in mapeo], ensure_ascii=False,
                                    sort_keys=True).encode()).hexdigest()[:8]
    descripcion = (f"Desde HABIT · {board_name or ''} · {ds}\n"
                   f"Cambia la rutina en la app y vuelve a sincronizar.\n[{MARCA} {ds} #{firma}]")
    wk = W.StrengthWorkout(
        workoutName=nombre,
        estimatedDurationInSecs=int(duracion) or 1800,
        description=descripcion[:1024],
        workoutSegments=[W.WorkoutSegment(segmentOrder=1, sportType=dict(DEPORTE_FUERZA),
                                          workoutSteps=pasos)],
    )
    return {"workout": wk, "nombre": nombre, "firma": firma}, mapeo


# ── Estado local ────────────────────────────────────────────────────────────

def estado_leer():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            pass
    return {}


def estado_guardar(estado):
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)
    STATE_FILE.write_text(json.dumps(estado, ensure_ascii=False, indent=1), encoding="utf-8")


# ── Garmin ──────────────────────────────────────────────────────────────────

def garmin(interactivo=False, email=None):
    from garminconnect import Garmin
    if interactivo:
        email = email or input("Correo de Garmin Connect: ").strip()
        g = Garmin(email=email, password=getpass.getpass("Contraseña de Garmin Connect: "),
                   prompt_mfa=lambda: input("Código de verificación que te llegó: ").strip())
        # Con tokenstore, login() guarda los tokens ahí al entrar con contraseña (0600),
        # y de ahí en adelante ya no se necesita la contraseña.
        g.login(GARMIN_TOKENS)
        return g
    g = Garmin()
    try:
        g.login(GARMIN_TOKENS)
    except Exception as exc:
        raise SystemExit(f"No hay sesión de Garmin usable ({exc}).\n"
                         "Corre: ./habit-garmin login-garmin --email tucorreo@ejemplo.com")
    return g


# ── Comandos ────────────────────────────────────────────────────────────────

def cmd_login_habit(args):
    h = Habit()
    email = args.email or input("Correo de HABIT: ").strip()
    user = h.login(email, getpass.getpass("Contraseña de HABIT: "))
    print(f"Listo: sesión de {user.get('email')} guardada en el Llavero ({KEYCHAIN_SERVICE}).")
    print("La contraseña no se guardó; lo que queda es el refresh token.")


def cmd_login_garmin(args):
    g = garmin(interactivo=True, email=args.email)
    nombre = ""
    for attr in ("get_full_name", "display_name", "full_name"):
        valor = getattr(g, attr, None)
        try:
            nombre = str(valor() if callable(valor) else valor or "").strip()
        except Exception:
            nombre = ""
        if nombre:
            break
    print(f"Listo: sesión de Garmin de {nombre or 'tu cuenta'}; tokens en {GARMIN_TOKENS}.")


def _ventana(args):
    desde = hoy_maz()
    return desde, desde + timedelta(days=args.dias - 1)


def _plan(habit, args, mapa):
    desde, hasta = _ventana(args)
    filas, rutinas = leer_semana(habit, desde, hasta, estampar=not args.sin_estampar)
    plan = []
    for fila in filas:
        ds, estado = fila["ds"], (fila.get("status") or "")
        if estado in ("done", "skipped"):
            continue
        if not fila.get("board_id"):
            continue
        board = rutinas.get(fila["board_id"]) or {}
        exs = ejercicios_del_dia(fila, rutinas)
        wk, mapeo = construir(ds, board.get("name"), exs, mapa)
        if wk:
            plan.append({"ds": ds, "board": board.get("name") or "", "wk": wk, "mapeo": mapeo,
                         "estado": estado})
    return desde, hasta, plan


def cmd_semana(args):
    habit = Habit(); habit.resume()
    mapa = Mapa()
    desde, hasta, plan = _plan(habit, args, mapa)
    print(f"HABIT, {desde} a {hasta}: {len(plan)} entrenos de fuerza planeados\n")
    sin_resolver = []
    for d in plan:
        print(f"── {etiqueta_dia(d['ds'])} · {d['board']} → «{d['wk']['nombre']}»")
        for m in d["mapeo"]:
            marca = {"mapa": "·", "exacto": "✓", "contiene": "✓", "parecido": "~", "categoría": "?"}[m["origen"]]
            print(f"   {marca} {m['habit'][:34]:34} {m['detalle']:>9}  d{m['descanso']:>3}s  "
                  f"→ {m['categoria']}/{m['garmin']}")
            if m["origen"] in ("parecido", "categoría"):
                sin_resolver.append((m["habit"], m["categoria"], m["garmin"], m["origen"]))
        print()
    if sin_resolver:
        print("Ejercicios que Garmin no reconoció igual (se pueden fijar en exercise_map.json):")
        for nombre, cat, g, origen in sorted(set(sin_resolver)):
            print(f'  "{plano(nombre)}": {{"category": "{cat}", "exercise": "{g if g != "(categoría)" else ""}"}},'
                  f'   # {nombre} ({origen})')


def cmd_sync(args):
    habit = Habit(); habit.resume()
    mapa = Mapa()
    desde, hasta, plan = _plan(habit, args, mapa)
    estado = estado_leer()
    nuevos = [d for d in plan if estado.get(d["ds"], {}).get("firma") != d["wk"]["firma"]]
    iguales = [d for d in plan if d not in nuevos]
    sobran = [ds for ds in list(estado)
              if desde.isoformat() <= ds <= hasta.isoformat() and ds not in {d["ds"] for d in plan}]

    print(f"HABIT {desde} → {hasta}")
    for d in nuevos:
        print(f"  sube   {etiqueta_dia(d['ds'])}  «{d['wk']['nombre']}»  "
              f"({len(d['mapeo'])} ejercicios)")
    for d in iguales:
        print(f"  igual  {etiqueta_dia(d['ds'])}  «{d['wk']['nombre']}»")
    for ds in sobran:
        print(f"  borra  {etiqueta_dia(ds)}  «{estado[ds].get('nombre','')}» (ya no está en HABIT)")
    if not nuevos and not sobran:
        print("  nada que cambiar en Garmin.")
        return
    if not args.commit:
        print("\nVista previa. Usa --commit para escribirlo en Garmin Connect.")
        return

    g = garmin()
    for ds in sobran:
        try:
            g.delete_workout(estado[ds]["workout_id"])
        except Exception as exc:
            print(f"  (no pude borrar {ds}: {exc})", file=sys.stderr)
        estado.pop(ds, None)
        estado_guardar(estado)
    for d in nuevos:
        viejo = estado.get(d["ds"], {}).get("workout_id")
        if viejo:
            # Borrar y volver a subir en vez de actualizar: un PUT exige reenviar los ids de
            # cada paso y un desajuste deja el workout a medias. Borrarlo también lo quita
            # del calendario, así que no quedan dos el mismo día.
            try:
                g.delete_workout(viejo)
            except Exception as exc:
                print(f"  (no pude borrar el anterior de {d['ds']}: {exc})", file=sys.stderr)
        res = g.upload_strength_workout(d["wk"]["workout"])
        wid = res.get("workoutId") or res.get("workoutid")
        g.schedule_workout(wid, d["ds"])
        estado[d["ds"]] = {"workout_id": wid, "firma": d["wk"]["firma"], "nombre": d["wk"]["nombre"],
                           "board": d["board"], "subido": datetime.now(timezone.utc).isoformat()}
        estado_guardar(estado)
        print(f"  ✓ {etiqueta_dia(d['ds'])}  {d['wk']['nombre']}  (workout {wid})")
    try:
        g.send_scheduled_workouts_to_devices()
        print("\nPedido el envío a tus dispositivos. El Venu los recibe en la siguiente "
              "sincronización con Garmin Connect en el teléfono.")
    except Exception as exc:
        print(f"\n(no pude pedir el envío al reloj: {exc}; sincroniza el reloj a mano)", file=sys.stderr)


def cmd_limpiar(args):
    estado = estado_leer()
    if not estado:
        print("No hay nada registrado como subido desde aquí.")
        return
    for ds, info in sorted(estado.items()):
        print(f"  borra {ds}  «{info.get('nombre','')}»  (workout {info.get('workout_id')})")
    if not args.commit:
        print("\nVista previa. Usa --commit para borrarlos de Garmin.")
        return
    g = garmin()
    for ds, info in sorted(estado.items()):
        try:
            g.delete_workout(info["workout_id"])
        except Exception as exc:
            print(f"  (no pude borrar {ds}: {exc})", file=sys.stderr)
    estado_guardar({})
    print("Listo.")


PLIST_XML = """<?xml version="1.0" encoding="UTF-8"?>
<!-- Lo escribe `habit-garmin instalar`; se edita ahí, no a mano. -->
<plist version="1.0">
<dict>
  <key>Label</key><string>{agente}</string>
  <key>ProgramArguments</key>
  <array>
    <string>{wrapper}</string>
    <string>sync</string>
    <string>--commit</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>{hora}</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>{log}</string>
  <key>StandardErrorPath</key><string>{log}</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
"""


def cmd_instalar(args):
    """Deja una copia que sí puede correr sola, fuera de las carpetas protegidas."""
    import shutil
    url, anon = habit_config()
    APP_DIR.mkdir(parents=True, exist_ok=True)
    for nombre in ("garmin_sync.py", "exercise_map.json"):
        shutil.copy2(HERE / nombre, APP_DIR / nombre)
    CONFIG_FILE.write_text(json.dumps(
        {"supabase_url": url, "supabase_anon_key": anon, "origen": str(HERE),
         "instalado": datetime.now(timezone.utc).isoformat()}, ensure_ascii=False, indent=1),
        encoding="utf-8")

    venv = APP_DIR / ".venv"
    if not (venv / "bin" / "python").exists():
        base = Path(sys.base_prefix) / "bin" / f"python{sys.version_info.major}.{sys.version_info.minor}"
        print(f"creando el entorno con {base}…")
        subprocess.run([str(base), "-m", "venv", str(venv)], check=True)
        subprocess.run([str(venv / "bin" / "pip"), "install", "-q", "garminconnect[workout]"], check=True)

    wrapper = APP_DIR / "habit-garmin"
    wrapper.write_text('#!/bin/sh\nexec "$HOME/.habit-garmin/app/.venv/bin/python" '
                       '"$HOME/.habit-garmin/app/garmin_sync.py" "$@"\n', encoding="utf-8")
    wrapper.chmod(0o755)

    log = STATE_DIR / "sync.log"
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    PLIST.write_text(PLIST_XML.format(agente=AGENTE, wrapper=wrapper, hora=args.hora, log=log),
                     encoding="utf-8")
    print(f"instalado en {APP_DIR}")
    print(f"agente a las {args.hora}:00 → {PLIST}")

    uid = os.getuid()
    subprocess.run(["launchctl", "bootout", f"gui/{uid}/{AGENTE}"], capture_output=True)
    alta = subprocess.run(["launchctl", "bootstrap", f"gui/{uid}", str(PLIST)], capture_output=True, text=True)
    if alta.returncode == 0:
        print(f"agente cargado. Pruébalo con: launchctl kickstart gui/{uid}/{AGENTE}")
    else:
        print(f"(no pude cargarlo desde aquí: {alta.stderr.strip()})\n"
              f"Cárgalo tú:\n  launchctl bootstrap gui/{uid} {PLIST}")
    print(f"lo que imprima queda en {log}")


def main():
    p = argparse.ArgumentParser(description="HABIT → Garmin Connect (fuerza)")
    sub = p.add_subparsers(dest="cmd", required=True)

    q = sub.add_parser("login-habit"); q.add_argument("--email"); q.set_defaults(fn=cmd_login_habit)
    q = sub.add_parser("login-garmin"); q.add_argument("--email"); q.set_defaults(fn=cmd_login_garmin)
    for nombre, fn in (("semana", cmd_semana), ("sync", cmd_sync)):
        q = sub.add_parser(nombre)
        q.add_argument("--dias", type=int, default=14)
        q.add_argument("--sin-estampar", action="store_true",
                       help="no llamar ensure_coaching_week_from_template")
        if nombre == "sync":
            q.add_argument("--commit", action="store_true")
        q.set_defaults(fn=fn)
    q = sub.add_parser("limpiar"); q.add_argument("--commit", action="store_true")
    q.set_defaults(fn=cmd_limpiar)
    q = sub.add_parser("instalar"); q.add_argument("--hora", type=int, default=6)
    q.set_defaults(fn=cmd_instalar)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
