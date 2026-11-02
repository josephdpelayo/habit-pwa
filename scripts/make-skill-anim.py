#!/usr/bin/env python3
"""Dibuja la animación de cada escalón de las escaleras de calistenia.

Salida: skill-anim/<slug>.svg, uno por escalón. Son SVG animados —SMIL, sin JavaScript—
porque dentro de un <img> corren solos, pesan unos kilobytes y se ven igual de nítidos en
la miniatura de 58 px que en el encabezado de la hoja. La migración 142 los enlaza en
exercise_catalog.animation_url.

No pretenden ser el video: son el dibujo que hace legible la escalera desde el día uno, y
el día que haya video de cada escalón se sube desde Admin y pisa esta URL.

Decisiones que vale la pena no deshacer:

  · **La figura se dibuja ya en su posición**, en coordenadas absolutas. La animación es
    solo la oscilación de encima. Así el generador sabe exactamente dónde cae cada
    articulación, que es lo que permite encuadrar y poner la barra y el muro en su sitio.
  · **La pose está quieta.** Lo que se hace en una escalera es comparar ocho posiciones de
    un vistazo, y ocho figuras repitiendo la entrada las dejan todas a mitad de camino justo
    cuando hay que compararlas. Solo se mueven los escalones donde el movimiento ES el
    ejercicio: el jalón de talón y el traspaso de peso.
  · **El encuadre se calcula solo.** Un colgado invertido ocupa alto y un front lever ocupa
    ancho; cuadrar los quince a mano era perseguir recortes.
  · **Puntos de referencia en mano, hombro, cadera, rodilla y pie** (`data-j`), pequeños y
    del morado de la app. Lo que define un escalón es una alineación —en el tuck avanzado,
    hombro, cadera y pie a la misma altura; en una parada de manos, todo en una vertical—,
    y con los puntos esa alineación se ve sin tener que adivinar dónde termina cada palo.
    scripts/check-skills.js las comprueba leyendo esos puntos, así que una pose mal
    dibujada falla la prueba en vez de salir a la escalera.
  · **Una postura es la misma en todas las escaleras.** El tuck y el tuck avanzado salen de
    TUCK y ADV_TUCK tanto en front lever como en planche y back lever; lo único que cambia es
    de qué lado queda el pecho, y eso lo resuelve el eje del torso. Así se corrigieron los
    tucks de planche y back lever, que tenían las rodillas del lado de la espalda.

Correr:  python3 scripts/make-skill-anim.py
"""
import math
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / 'skill-anim'

INK = '#e8e9ee'                   # la figura
DIM = 'rgba(232,233,238,.3)'      # barra, piso y muro
JOINT = '#a78bfa'                 # los puntos de referencia: el morado de la app (--purple)
JOINT_R = 3.2                     # sutiles: en la miniatura de 58 px casi desaparecen
HEAD_R, STROKE, PAD = 11, 7, 16

# Largos del cuerpo. Proporciones de persona, no de palo.
ARM, TORSO, THIGH, SHIN, NECK = 52, 48, 40, 38, 16
CYCLE = '5s'
SWAY = 1.5                        # grados: lo justo para que no parezca un dibujo muerto
FACE_UP, FACE_DOWN = 180, 0       # hacia dónde mira la cara, en el marco sin rotar
FACE_RIGHT = -90                  # de pie, mirando al frente (el muscle-up arriba de la barra)

# Las posturas de piernas, en grados respecto al segmento anterior (0 = en línea). El signo
# negativo dobla hacia el lado del pecho cuando el torso apunta lejos de la cabeza, que es
# como lo dibujan las tres escaleras de lever y planche: por eso valen igual en todas.
#
# Tuck: muslos pegados al pecho y talones a los glúteos.
TUCK = (-140, 158)
# Tuck avanzado: rodilla a 90° y la cadera abierta lo justo para que el pie vuelva a la línea
# de hombro y cadera, que es el estándar de la posición. No es un número elegido a ojo: con
# la rodilla en ángulo recto, el pie cae en la línea cuando THIGH·sen θ = SHIN·cos θ.
ADV_TUCK = (-math.degrees(math.atan2(SHIN, THIGH)), 90)
# Straddle: las piernas se abren hacia los lados, así que de perfil siguen sobre la línea y
# solo se ven más cortas. La de atrás va tenue y apenas desviada, para que se lean dos. El
# dibujo anterior las abría arriba y abajo, que es una tijera y no un straddle.
STRADDLE_SCALE = 0.8              # escorzo de una pierna abierta unos 37° hacia el lado
STRADDLE_DEPTH = 7                # grados de la pierna de atrás: profundidad, no apertura


def rot(p, deg, about):
    """Rota un punto como lo hace SVG: ángulo positivo = horario en pantalla."""
    a = math.radians(deg)
    dx, dy = p[0] - about[0], p[1] - about[1]
    return (about[0] + dx * math.cos(a) - dy * math.sin(a),
            about[1] + dx * math.sin(a) + dy * math.cos(a))


def limb(frm, deg, length):
    """El extremo de un segmento que sale de `frm` con el ángulo dado (0 = hacia abajo)."""
    return rot((frm[0], frm[1] + length), deg, frm)


class Fig:
    """Acumula el dibujo y, de paso, cada punto que toca, para encuadrar al final."""

    def __init__(self):
        self.parts, self.pts, self.dots = [], [], []

    def joint(self, p, name):
        """Un punto de referencia. Van aparte de los trazos para pintarse encima de todos."""
        self.dots.append(f'<circle cx="{p[0]:.1f}" cy="{p[1]:.1f}" r="{JOINT_R}" fill="{JOINT}" '
                         f'data-j="{name}"/>')

    def drawn(self):
        return self.parts + self.dots

    def line(self, a, b, w=STROKE, color=INK, opacity=1.0, measure=True):
        if measure:
            self.pts += [a, b]
        self.parts.append(
            f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" '
            f'stroke="{color}" stroke-width="{w}" stroke-linecap="round" opacity="{opacity}"/>')

    def circle(self, c, r, color=INK):
        self.pts += [(c[0] - r, c[1] - r), (c[0] + r, c[1] + r)]
        self.parts.append(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="{color}"/>')

    def svg(self, title, groups=''):
        xs = [p[0] for p in self.pts]
        ys = [p[1] for p in self.pts]
        x0, y0 = min(xs) - PAD, min(ys) - PAD
        w, h = max(xs) + PAD - x0, max(ys) + PAD - y0
        # Cuadrado a la fuerza: la miniatura de la escalera es 1:1 con object-fit cover, y
        # un lienzo alto —el colgado invertido— se quedaría sin piernas al recortar.
        side = max(w, h)
        x0 -= (side - w) / 2
        y0 -= (side - h) / 2
        w = h = side
        # Los puntos del marco (las manos) van al final, encima de la figura que se mueve.
        return (f'<svg xmlns="http://www.w3.org/2000/svg" '
                f'viewBox="{x0:.0f} {y0:.0f} {w:.0f} {h:.0f}" preserveAspectRatio="xMidYMid meet" '
                f'role="img" aria-label="{title}">\n  <title>{title}</title>\n  '
                + '\n  '.join(self.parts) + '\n' + groups
                + ''.join(f'  {d}\n' for d in self.dots) + '</svg>\n')


def pose(fig, shoulder, axis, hip_deg=0, knee_deg=0, legs='together', facing=None):
    """El cuerpo del hombro hacia abajo, ya en su posición. Marca hombro, cadera, rodilla y
    pie de la pierna de adelante, y devuelve esas articulaciones.

    axis: hacia dónde apunta el torso (0 = abajo, -90 = horizontal a la derecha, -180 = arriba).
    hip_deg / knee_deg: cuánto se dobla cada articulación respecto al segmento anterior.
    legs: 'together' | 'straddle' | 'one' (la de adelante estirada, la de atrás doblada).
    facing: hacia dónde mira la cara (0 = abajo, 180 = arriba), o None para no marcarla.
    """
    hip = limb(shoulder, axis, TORSO)
    # Cuello y cabeza van del lado contrario a la cadera: en un front lever la cabeza queda
    # junto a las manos, porque el cuerpo sale del hombro hacia los pies.
    neck = rot((shoulder[0], shoulder[1] - NECK), axis, shoulder)
    head = rot((shoulder[0], shoulder[1] - NECK - HEAD_R + 2), axis, shoulder)
    fig.line(shoulder, hip)
    fig.line(shoulder, neck, w=STROKE - 1)
    fig.circle(head, HEAD_R)
    # Hacia dónde mira. Un front lever y un back lever son la misma línea horizontal: lo que
    # los distingue es que en uno vas de cara al techo y en el otro al piso, y un palo no
    # tiene barriga. La nariz lo dice en un trazo.
    if facing is not None:
        tip = rot((head[0], head[1] + HEAD_R + 7), facing, head)
        fig.line(head, tip, w=STROKE - 2)

    # (dirección del muslo, doblez de rodilla, escala, opacidad). La pierna de atrás va primero
    # y tenue; la de adelante encima, y es la que lleva los puntos.
    if legs == 'straddle':
        # La de atrás se desvía hacia abajo en pantalla, sea cual sea el lado del torso.
        back = max((axis + STRADDLE_DEPTH, axis - STRADDLE_DEPTH), key=lambda a: limb(hip, a, 10)[1])
        specs = [(back, 0, STRADDLE_SCALE, .5), (axis, 0, STRADDLE_SCALE, 1.0)]
    elif legs == 'one':
        specs = [(axis + hip_deg, knee_deg, 1, .5), (axis, 0, 1, 1.0)]
    else:
        specs = [(axis + hip_deg, knee_deg, 1, .5), (axis + hip_deg, knee_deg, 1, 1.0)]
    for thigh_dir, kd, k, op in specs:
        knee = limb(hip, thigh_dir, THIGH * k)
        foot = limb(knee, thigh_dir + kd, SHIN * k)
        fig.line(hip, knee, opacity=op)
        fig.line(knee, foot, opacity=op)
    for p, name in ((shoulder, 'shoulder'), (hip, 'hip'), (knee, 'knee'), (foot, 'foot')):
        fig.joint(p, name)
    return {'shoulder': shoulder, 'hip': hip, 'knee': knee, 'foot': foot}


def swaying(fig_parts, about, values=None, times=None):
    """Envuelve la figura en el movimiento de encima. Los valores son relativos a la pose,
    que ya está dibujada en su sitio: 0 es la posición correcta."""
    vals = values or [-SWAY, SWAY, -SWAY]
    times = ';'.join(f'{t:.2f}' for t in times) if times \
        else ';'.join(f'{i / (len(vals) - 1):.2f}' for i in range(len(vals)))
    splines = ';'.join(['0.4 0 0.6 1'] * (len(vals) - 1))
    v = ';'.join(f'{x} {about[0]:.0f} {about[1]:.0f}' for x in vals)
    return ('  <g>\n    <animateTransform attributeName="transform" type="rotate" '
            f'values="{v}" keyTimes="{times}" dur="{CYCLE}" repeatCount="indefinite" '
            f'calcMode="spline" keySplines="{splines}"/>\n    '
            + '\n    '.join(fig_parts) + '\n  </g>\n')


def lever_arms(fig, shoulder, one_arm=False):
    if one_arm:
        fig.line(HANDS, shoulder)
    else:
        fig.line((HANDS[0] - 7, HANDS[1]), (shoulder[0] - 7, shoulder[1]))
        fig.line((HANDS[0] + 7, HANDS[1]), (shoulder[0] + 7, shoulder[1]), opacity=.5)


SPLINE = '0.4 0 0.6 1'


def timing(n, times=None):
    """keyTimes, duración y curva de una animación de n valores."""
    t = ';'.join(f'{x:.2f}' for x in times) if times else ';'.join(f'{i / (n - 1):.2f}' for i in range(n))
    return (f'keyTimes="{t}" dur="{CYCLE}" repeatCount="indefinite" calcMode="spline" '
            f'keySplines="{";".join([SPLINE] * (n - 1))}"')


def moving(fig_parts, offsets, times=None):
    """Como swaying, pero trasladando: cada valor es (dx, dy) respecto a la pose dibujada."""
    v = ';'.join(f'{dx:.1f} {dy:.1f}' for dx, dy in offsets)
    return ('  <g>\n    <animateTransform attributeName="transform" type="translate" '
            f'values="{v}" {timing(len(offsets), times)}/>\n    '
            + '\n    '.join(fig_parts) + '\n  </g>\n')


def stretching_line(a, b, offsets, times=None, w=STROKE, opacity=1.0):
    """Un segmento con un extremo quieto (la mano en el piso) y el otro que se va con la figura.
    Es lo que dibuja un encogimiento: el brazo sigue bloqueado y lo que se mueve es el hombro."""
    xs = ';'.join(f'{b[0] + dx:.1f}' for dx, _ in offsets)
    ys = ';'.join(f'{b[1] + dy:.1f}' for _, dy in offsets)
    t = timing(len(offsets), times)
    return (f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="{INK}" '
            f'stroke-width="{w}" stroke-linecap="round" opacity="{opacity}">'
            f'<animate attributeName="x2" values="{xs}" {t}/><animate attributeName="y2" values="{ys}" {t}/></line>')


def ang(v):
    """El ángulo de limb() que apunta en la dirección del vector v (0 = abajo, 90 = izquierda)."""
    return math.degrees(math.atan2(-v[0], v[1]))


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def hang_frame(person, shoulder, one_arm=False, arms=True):
    """La barra, los brazos y el punto de la mano para todo lo que cuelga con los brazos
    estirados: front lever, back lever y sus elevaciones. `arms=False` cuando los brazos se
    mueven y van dentro de la animación (las elevaciones)."""
    frame = Fig()
    # La barra abarca lo que ocupa la pose: una barra fija dejaba al colgado invertido con
    # media barra vacía y al lever completo con la barra cortada.
    xs = [p[0] for p in person.pts] + [HANDS[0]]
    frame.line((min(xs) - 14, HANDS[1]), (max(xs) + 14, HANDS[1]), w=5, color=DIM)
    if arms:
        lever_arms(frame, shoulder, one_arm)
    frame.circle(HANDS, 6, DIM)
    frame.joint(HANDS, 'hand')
    frame.pts += person.pts
    return frame


# ───────────────────────────── Front lever ─────────────────────────────

HANDS = (110, 40)
SHOULDER = (HANDS[0], HANDS[1] + ARM)     # colgado: el hombro justo bajo las manos

# En una palanca los brazos NO cuelgan en vertical: la palanca la sostiene la espalda (el
# dorsal lleva el brazo hacia la cadera), así que el brazo va en diagonal y la barra queda
# sobre el pecho, no sobre el hombro. Vale para front lever y back lever: en los dos la
# mano se adelanta hacia el lado de la cadera.
LEVER_ARM = 25


def lever_shoulder(axis):
    """Dónde queda el hombro en una palanca con el torso apuntando a `axis` (-90 = derecha,
    90 = izquierda): abajo de la barra y corrido hacia el lado de la cabeza."""
    toward_head = 1 if axis < 0 else -1     # rotar +: el hombro se corre a la izquierda
    return rot(SHOULDER, toward_head * LEVER_ARM, HANDS)

FRONT_LEVER = {
    # slug: (torso, (cadera, rodilla), piernas, un brazo)
    'colgado-invertido':          (-180, (0, 0),   'together', False),
    'front-lever-tuck':           ( -90, TUCK,     'together', False),
    'front-lever-tuck-avanzado':  ( -90, ADV_TUCK, 'together', False),
    # La de adelante estirada en la línea; la de atrás, en tuck.
    'front-lever-a-una-pierna':   ( -90, TUCK,     'one',      False),
    'front-lever-straddle':       ( -90, (0, 0),   'straddle', False),
    # Cadera abierta en la línea y rodillas en ángulo recto: la espinilla cuelga vertical.
    'front-lever-half-lay':       ( -90, (0, 90),  'together', False),
    'front-lever-completo':       ( -90, (0, 0),   'together', False),
    'front-lever-a-un-brazo':     ( -90, (0, 0),   'together', True),
}


def front_lever(cfg, title):
    axis, (hip, knee), legs, one_arm = cfg
    # El colgado invertido no es palanca: los brazos van pegados al cuerpo, en vertical.
    shoulder = SHOULDER if axis == -180 else lever_shoulder(axis)
    person = Fig()
    pose(person, shoulder, axis, hip, knee, legs, facing=FACE_UP)
    frame = hang_frame(person, shoulder, one_arm)
    return frame.svg(title, swaying(person.drawn(), shoulder))


# ───────────────────────────── Parada de manos ─────────────────────────────

HS_HANDS = (120, 210)
HS_SHOULDER = (HS_HANDS[0], HS_HANDS[1] - ARM)

HANDSTAND = {
    #                                        torso, muro, modo
    # Lo que pide el escalón: cuerpo a 45° del piso con los brazos verticales.
    'plancha-en-pared-45-grados':            (-135, 'back',  'static'),
    'parada-de-manos-en-pared':              (-171, 'back',  'static'),
    'parada-de-manos-de-frente-a-la-pared':  (-180, 'front', 'static'),
    'heel-pulls-toe-pulls':                  (-180, 'front', 'pulls'),
    'parada-de-manos-libre':                 (-180, None,    'sway'),
    'traspaso-de-peso-en-parada-de-manos':   (-180, None,    'shift'),
    'parada-de-manos-a-un-brazo':            (-180, None,    'onearm'),
    # Del programa de parada de manos (migración 145): las mismas figuras con su movimiento.
    # Los toques son el traspaso con la pared enfrente; el encogimiento sube el cuerpo entero
    # con los brazos bloqueados.
    'toques-de-hombro-en-pared':             (-180, 'front', 'shift'),
    'encogimientos-de-frente-a-la-pared':    (-180, 'front', 'shrug'),
}

SHRUG = 6                         # cuánto sube el hombro en un encogimiento


def handstand(cfg, title):
    axis, wall, mode = cfg
    # En el traspaso el estándar es el hombro apilado sobre la mano que carga: el cuerpo entero
    # se corre encima de ella y la otra queda en diagonal, descargándose.
    loaded = (HS_HANDS[0] - 9, HS_HANDS[1])
    shoulder = (loaded[0], HS_SHOULDER[1]) if mode == 'shift' else HS_SHOULDER
    person = Fig()
    pose(person, shoulder, axis, facing=FACE_DOWN)

    frame = Fig()
    xs = [p[0] for p in person.pts]
    ys = [p[1] for p in person.pts]
    frame.line((min(xs) - 22, HS_HANDS[1]), (max(xs) + 22, HS_HANDS[1]), w=5, color=DIM)
    if wall:                       # el muro toca los pies por detrás, o el pecho por delante
        wx = max(xs) + 7 if wall == 'back' else min(xs) - 9
        frame.line((wx, HS_HANDS[1]), (wx, min(ys) - 12), w=5, color=DIM)

    if mode == 'onearm':
        frame.line(HS_HANDS, HS_SHOULDER)
        frame.joint(HS_HANDS, 'hand')
    elif mode == 'shift':
        # Una mano se descarga hasta quedar en las puntas, y vuelve. Es el ejercicio. El punto
        # de referencia es la mano que carga, la que queda apilada bajo el hombro.
        frame.line(loaded, shoulder)
        frame.joint(loaded, 'hand')
        lifted = Fig()
        lifted.line((HS_HANDS[0] + 9, HS_HANDS[1]), (shoulder[0] + 4, shoulder[1]), opacity=.5)
        frame.pts += lifted.pts
        frame.parts.append(
            '<g><animateTransform attributeName="transform" type="translate" '
            f'values="0 0;0 -13;0 0" keyTimes="0;.5;1" dur="{CYCLE}" repeatCount="indefinite" '
            f'calcMode="spline" keySplines="0.4 0 0.2 1;0.4 0 0.2 1"/>{lifted.parts[0]}</g>')
    elif mode == 'shrug':
        # Empujar el piso: el cuerpo entero sube y los brazos, bloqueados, se van con él.
        lift = [(0, 0), (0, -SHRUG), (0, 0)]
        frame.parts.append(stretching_line((HS_HANDS[0] - 9, HS_HANDS[1]), (shoulder[0] - 4, shoulder[1]), lift))
        frame.parts.append(stretching_line((HS_HANDS[0] + 9, HS_HANDS[1]), (shoulder[0] + 4, shoulder[1]), lift,
                                           opacity=.5))
        frame.joint(HS_HANDS, 'hand')
    else:
        frame.line((HS_HANDS[0] - 9, HS_HANDS[1]), (HS_SHOULDER[0] - 4, HS_SHOULDER[1]))
        frame.line((HS_HANDS[0] + 9, HS_HANDS[1]), (HS_SHOULDER[0] + 4, HS_SHOULDER[1]), opacity=.5)
        frame.joint(HS_HANDS, 'hand')
    frame.circle(HS_HANDS, 6, DIM)
    frame.pts += person.pts

    if mode == 'shrug':
        return frame.svg(title, moving(person.drawn(), [(0, 0), (0, -SHRUG), (0, 0)]))
    if mode == 'pulls':      # el jalón ES el ejercicio: el cuerpo se despega del muro y vuelve
        vals = [0, 8, 0, -2, 0]
    elif mode == 'sway':     # un hold libre nunca está quieto: corregir es la habilidad
        vals = [0, 3.5, 0, -3.5, 0]
    else:
        vals = None
    return frame.svg(title, swaying(person.drawn(), shoulder, vals))



def bent_arm(fig, hand, shoulder, bend, opacity=1.0):
    """Un brazo que se dobla: codo resuelto con dos huesos iguales.

    Hace falta para el muscle-up, donde lo que distingue un escalón del siguiente es
    justamente cuánto y hacia dónde está el codo. `bend` es de qué lado sale el codo.
    """
    bone = ARM / 2
    dx, dy = shoulder[0] - hand[0], shoulder[1] - hand[1]
    d = math.hypot(dx, dy) or .01
    if d >= 2 * bone:                     # estirado: no hay codo que dibujar
        fig.line(hand, shoulder, opacity=opacity)
        return
    h = math.sqrt(max(0.0, bone ** 2 - (d / 2) ** 2))
    mx, my = hand[0] + dx / 2, hand[1] + dy / 2
    elbow = (mx - dy / d * h * bend, my + dx / d * h * bend)
    fig.line(hand, elbow, opacity=opacity)
    fig.line(elbow, shoulder, opacity=opacity)


# ───────────────────────────── Planche ─────────────────────────────
# Manos en el piso, brazos rectos hacia arriba y el cuerpo por detrás: lo que define la
# línea es cuánto se adelanta el hombro de la muñeca, así que el brazo va inclinado.

PL_HANDS = (150, 210)

PLANCHE = {
    # slug: (inclinación del brazo, torso, (cadera, rodilla), piernas)
    # El lean es una plancha de lagartija con los hombros por delante: los pies siguen en el
    # piso y el cuerpo es una sola recta de hombro a pie.
    'planche-lean':           (22,  68, (0, 0),   'together'),
    # Las mismas posturas que el front lever. Antes llevaban el signo al revés y las
    # rodillas salían del lado de la espalda, que en una planche es imposible.
    'plancha-tuck':           (34,  90, TUCK,     'together'),
    'plancha-tuck-avanzada':  (34,  90, ADV_TUCK, 'together'),
    'plancha-straddle':       (36,  90, (0, 0),   'straddle'),
    'plancha-completa':       (38,  90, (0, 0),   'together'),
}


def planche(cfg, title):
    arm_deg, axis, (hip, knee), legs = cfg
    shoulder = rot((PL_HANDS[0], PL_HANDS[1] - ARM), arm_deg, PL_HANDS)
    person = Fig()
    pose(person, shoulder, axis, hip, knee, legs, facing=FACE_DOWN)

    frame = Fig()
    xs = [q[0] for q in person.pts] + [PL_HANDS[0]]
    frame.line((min(xs) - 20, PL_HANDS[1]), (max(xs) + 20, PL_HANDS[1]), w=5, color=DIM)
    frame.line((PL_HANDS[0] - 7, PL_HANDS[1]), (shoulder[0] - 7, shoulder[1]))
    frame.line((PL_HANDS[0] + 7, PL_HANDS[1]), (shoulder[0] + 7, shoulder[1]), opacity=.5)
    frame.circle(PL_HANDS, 6, DIM)
    frame.joint(PL_HANDS, 'hand')
    frame.pts += person.pts
    return frame.svg(title, swaying(person.drawn(), shoulder))


# ───────────────────────────── Back lever ─────────────────────────────
# Mismo colgado que el front lever, pero de cara al piso y con el cuerpo del otro lado.
# Sin la marca de orientación los dos serían el mismo dibujo.

BACK_LEVER = {
    # De cara al piso: con TUCK las rodillas van hacia el piso, del lado del pecho.
    'back-lever-tuck':       (90, TUCK,   'together'),
    'back-lever-straddle':   (90, (0, 0), 'straddle'),
    'back-lever-completo':   (90, (0, 0), 'together'),
}


def back_lever(cfg, title):
    axis, (hip, knee), legs = cfg
    shoulder = lever_shoulder(axis)
    person = Fig()
    pose(person, shoulder, axis, hip, knee, legs, facing=FACE_DOWN)
    frame = hang_frame(person, shoulder)
    return frame.svg(title, swaying(person.drawn(), shoulder))


# ───────────────────────── Elevaciones a front lever ─────────────────────────
# Aquí el movimiento SÍ es el ejercicio: la repetición es jalar hasta la horizontal y bajar
# con los brazos bloqueados. Por eso estas cuatro no se quedan quietas como los aguantes.

FL_RAISE = {
    # La posición de arriba es la del aguante del mismo nombre.
    'elevacion-a-front-lever-tuck':           (TUCK,     'together'),
    'elevacion-a-front-lever-tuck-avanzado':  (ADV_TUCK, 'together'),
    'elevacion-a-front-lever-straddle':       ((0, 0),   'straddle'),
    'elevaciones-a-front-lever':              ((0, 0),   'together'),
}


def fl_raise(cfg, title):
    (hip, knee), legs = cfg
    shoulder = lever_shoulder(-90)
    person = Fig()
    pose(person, shoulder, -90, hip, knee, legs, facing=FACE_UP)
    # La barra abarca la posición de arriba Y la de colgado, que ocupa alto pero poco ancho.
    frame = hang_frame(person, shoulder, arms=False)
    arms = Fig()
    lever_arms(arms, shoulder)

    # Lo dibujado es la posición de arriba (brazos en diagonal, cuerpo horizontal). Abajo, en
    # el colgado, el brazo vuelve a la vertical —giro en la mano— y el cuerpo cuelga del
    # hombro —giro en el hombro, que va DENTRO del primero, así que gira con él—. La
    # repetición es subir, aguantar un segundo en la horizontal, bajar con control y esperar.
    arm_vals = [-LEVER_ARM, 0, 0, -LEVER_ARM, -LEVER_ARM]
    body_vals = [90 + LEVER_ARM, 0, 0, 90 + LEVER_ARM, 90 + LEVER_ARM]
    for q in person.pts + arms.pts:
        frame.pts.append(rot(rot(q, 90 + LEVER_ARM, shoulder), -LEVER_ARM, HANDS))
    times = [0, .30, .46, .78, 1]
    inner = swaying(person.drawn(), shoulder, body_vals, times=times)
    outer = swaying(arms.drawn() + [inner.strip()], HANDS, arm_vals, times=times)
    return frame.svg(title, outer)


# ───────────────────────────── Muscle-up ─────────────────────────────
# Cuatro posiciones distintas de la misma barra. Estáticas: lo que hay que ver es dónde
# queda el cuerpo respecto a la barra, no la velocidad.

MU_BAR_Y = 70
MU_HANDS = (118, MU_BAR_Y)
MU_BAR_HALF = 62                  # una barra tiene que verse como una barra

MUSCLE_UP = {
    # slug: dónde queda el cuerpo respecto a la barra
    'dominada-al-pecho':         'pull',
    'dominada-con-agarre-falso': 'hang',
    'muscle-up-negativo':        'trans',
    'muscle-up-en-barra':        'top',
}


# Arriba de la dominada el pecho toca la barra: el hombro queda detrás de ella (lo que mide el
# pecho de fondo) y un poco por encima, así que la barra cruza el torso a la altura del pecho.
MU_CHEST_BACK, MU_CHEST_UP = 14, 7


def muscle_up(where, title):
    if where == 'hang':        # colgado completo; lo que se marca es la muñeca sobre la barra
        shoulder, axis = (MU_HANDS[0], MU_BAR_Y + ARM), 0
    elif where == 'pull':      # arriba de la dominada: la barra toca el PECHO, no la barbilla.
        # Antes el hombro quedaba 27 abajo de la barra y la barra cruzaba la cara.
        shoulder, axis = (MU_HANDS[0] - MU_CHEST_BACK, MU_BAR_Y - MU_CHEST_UP), 0
    elif where == 'trans':     # la transición: hombro sobre la barra, cadera todavía abajo.
        # Estática a propósito: un negativo se baja doblando el brazo, y rotar el cuerpo
        # alrededor del hombro para «animarlo» dibujaba una marometa.
        shoulder, axis = (MU_HANDS[0] + 12, MU_BAR_Y - 9), 22
    else:                      # apoyo arriba de la barra: brazos bloqueados y la cadera en la
        # barra. Antes el torso apuntaba hacia arriba y era una parada de manos sobre la barra.
        shoulder, axis = (MU_HANDS[0], MU_BAR_Y - ARM), 0

    person = Fig()
    face = {'hang': FACE_UP, 'pull': FACE_UP, 'trans': FACE_DOWN}.get(where, FACE_RIGHT)
    pose(person, shoulder, axis, facing=face)

    frame = Fig()
    frame.line((MU_HANDS[0] - MU_BAR_HALF, MU_BAR_Y), (MU_HANDS[0] + MU_BAR_HALF, MU_BAR_Y),
               w=5, color=DIM)
    # Los dos codos van atrás, del lado de la espalda: abajo de la barra en la dominada y
    # arriba en la transición, como en el fondo de un dip. Antes se abrían uno a cada lado y
    # la dominada al pecho parecía una cruz. El brazo de atrás va tenue.
    for side, op in ((-9, 1.0), (9, .5)):
        bent_arm(frame, (MU_HANDS[0] + side, MU_BAR_Y), (shoulder[0] + side * .55, shoulder[1]),
                 -1, opacity=op)
    if where == 'hang':        # el agarre falso se ve en la muñeca por encima de la barra
        frame.circle((MU_HANDS[0] - 9, MU_BAR_Y - 6), 6, INK)
        frame.circle((MU_HANDS[0] + 9, MU_BAR_Y - 6), 6, INK)
    else:
        frame.circle(MU_HANDS, 6, DIM)
    frame.joint(MU_HANDS, 'hand')
    frame.pts += person.pts
    return frame.svg(title, swaying(person.drawn(), shoulder))


# ───────────────────────────── Curl nórdico ─────────────────────────────
# De rodillas con los tobillos anclados. La bajada ES el ejercicio, así que estas cuatro se
# mueven: lo que cambia entre escalones es hasta dónde baja y con qué ayuda.

NC_KNEE = (120, 210)

NORDIC = {
    # slug: (bajada máxima en grados, ayuda)
    'curl-nordico-negativo':  (72, None),
    'curl-nordico-asistido':  (66, 'band'),
    'curl-nordico':           (78, None),
    'curl-nordico-con-peso':  (74, 'plate'),
}


def nordic(cfg, title):
    descent, aid = cfg
    body_len = THIGH + TORSO
    frame = Fig()
    # Espinilla en el piso y el ancla del tobillo: sin eso esto es alguien cayéndose.
    ankle = (NC_KNEE[0] + SHIN, NC_KNEE[1])
    frame.line(NC_KNEE, ankle)
    frame.line((NC_KNEE[0] - 30, NC_KNEE[1]), (ankle[0] + 26, ankle[1]), w=5, color=DIM)
    frame.line((ankle[0] - 7, ankle[1] - 11), (ankle[0] + 7, ankle[1] - 11), w=6, color=DIM)

    # El cuerpo arranca vertical sobre la rodilla; la animación lo baja al frente.
    person = Fig()
    hip = (NC_KNEE[0], NC_KNEE[1] - THIGH)
    shoulder = (NC_KNEE[0], NC_KNEE[1] - body_len)
    neck_end = (NC_KNEE[0], shoulder[1] - NECK)
    person.line(NC_KNEE, hip)
    person.line(hip, shoulder)
    person.line(shoulder, neck_end, w=STROKE - 1)
    head = (NC_KNEE[0], shoulder[1] - NECK - HEAD_R + 2)
    person.circle(head, HEAD_R)
    person.line(head, (head[0] - HEAD_R - 7, head[1]), w=STROKE - 2)   # mira al frente
    if aid == 'plate':         # el disco contra el pecho
        person.parts.append(f'<rect x="{shoulder[0] - 20:.1f}" y="{shoulder[1] + 4:.1f}" '
                            f'width="15" height="22" rx="3" fill="{INK}" opacity=".75"/>')
        person.pts.append((shoulder[0] - 20, shoulder[1] + 4))
    if aid == 'band':          # la banda, del pecho a un anclaje detrás
        person.line(shoulder, (shoulder[0] + 46, shoulder[1] - 42), w=4, opacity=.45)
        person.pts.append((shoulder[0] + 46, shoulder[1] - 42))
    # El estándar es la cadera abierta: rodilla, cadera y hombro en una recta toda la bajada.
    # Rodilla y tobillo no se mueven; cadera y hombro bajan con el cuerpo.
    frame.joint(NC_KNEE, 'knee')
    frame.joint(ankle, 'foot')
    person.joint(hip, 'hip')
    person.joint(shoulder, 'shoulder')

    # Bajar despacio y volver: lo contrario de un aguante, aquí la lentitud es el estándar.
    # Baja despacio —4 o 5 segundos es el estándar del escalón 1— y vuelve más rápido. Que
    # la bajada ocupe más de la mitad del ciclo no es estética: es lo que hay que imitar.
    frame.pts += person.pts
    for q in person.pts:
        frame.pts.append(rot(q, -descent, NC_KNEE))
    return frame.svg(title, swaying(person.drawn(), NC_KNEE, [-10, -descent, -descent, -10],
                                    times=[0, .55, .70, 1]))


# ───────────────────────── Programa de parada de manos ─────────────────────────
# Los ejercicios del programa de 8 semanas (migración 145) que no son escalones. Mismas reglas:
# la pose se dibuja en su sitio, los puntos de referencia van en mano, hombro, cadera, rodilla y
# pie, y solo se mueve lo que es el ejercicio. Las figuras de movimiento llevan giros anidados
# (el de adentro gira con el de afuera) para que lo que tiene que quedar quieto —un pie en el
# piso, los pies en la pared— quede quieto.

FLOOR = 210


def floor_line(frame, pts, y=FLOOR, pad=20):
    xs = [p[0] for p in pts]
    frame.line((min(xs) - pad, y), (max(xs) + pad, y), w=5, color=DIM)


def head_on(fig, shoulder, hip, facing):
    """Cuello y cabeza del lado contrario a la cadera, como los pone pose()."""
    axis = ang(sub(hip, shoulder))
    neck = rot((shoulder[0], shoulder[1] - NECK), axis, shoulder)
    head = rot((shoulder[0], shoulder[1] - NECK - HEAD_R + 2), axis, shoulder)
    fig.line(shoulder, neck, w=STROKE - 1)
    fig.circle(head, HEAD_R)
    if facing is not None:
        fig.line(head, rot((head[0], head[1] + HEAD_R + 7), facing, head), w=STROKE - 2)


def floor_arms(fig, hand, shoulder, spread=9, top=4):
    """Los dos brazos apoyados en el piso; el de atrás, tenue."""
    fig.line((hand[0] - spread, hand[1]), (shoulder[0] - top, shoulder[1]))
    fig.line((hand[0] + spread, hand[1]), (shoulder[0] + top, shoulder[1]), opacity=.5)


def wrist_prep(title):
    """En cuadrupedia, el hombro pasa por delante de la muñeca y vuelve. La mano y la rodilla no
    se mueven: el brazo gira en la mano, el muslo en la rodilla y el torso se traslada."""
    hand = (150, FLOOR)
    shoulder = (hand[0], FLOOR - ARM)                 # brazo vertical: la posición de salida
    hip_y = FLOOR - THIGH                             # rodilla en el piso, muslo vertical
    hip = (shoulder[0] - math.sqrt(TORSO ** 2 - (hip_y - shoulder[1]) ** 2), hip_y)
    knee, foot = (hip[0], FLOOR), (hip[0] - SHIN, FLOOR)
    rock = 12                                         # cuánto pasa el hombro adelante
    arm_deg = math.degrees(math.asin(rock / ARM))
    thigh_deg = math.degrees(math.asin(rock / THIGH))
    shift = sub(rot(shoulder, arm_deg, hand), shoulder)

    upper = Fig()
    upper.line(shoulder, hip)
    head_on(upper, shoulder, hip, FACE_DOWN)
    upper.joint(shoulder, 'shoulder')
    upper.joint(hip, 'hip')
    arms = Fig()
    arms.line((hand[0] - 3, hand[1]), (shoulder[0] - 3, shoulder[1]))
    arms.line((hand[0] + 3, hand[1]), (shoulder[0] + 3, shoulder[1]), opacity=.5)
    thigh = Fig()
    thigh.line(hip, knee)

    frame = Fig()
    frame.line(knee, foot)                            # la espinilla, en el piso
    frame.joint(hand, 'hand')
    frame.joint(knee, 'knee')
    frame.joint(foot, 'foot')
    frame.pts += upper.pts + arms.pts + thigh.pts + [(p[0] + shift[0], p[1] + shift[1]) for p in upper.pts]
    floor_line(frame, frame.pts)
    return frame.svg(title, swaying(arms.drawn(), hand, [0, round(arm_deg, 1), 0])
                     + swaying(thigh.drawn(), knee, [0, round(thigh_deg, 1), 0])
                     + moving(upper.drawn(), [(0, 0), shift, (0, 0)]))


def shoulder_wall(title):
    """Manos en la pared, brazos y torso en una recta, cadera a 90°. Lo que se mueve es el
    pecho bajando hacia el piso: el torso gira en la cadera y los brazos se estiran con él."""
    foot = (100, FLOOR)
    knee = (foot[0], FLOOR - SHIN)
    hip = (foot[0], knee[1] - THIGH)
    shoulder = (hip[0] + TORSO, hip[1])
    hand = (shoulder[0] + ARM, hip[1])
    sink = 4                                          # grados que baja el pecho
    sunk = sub(rot(shoulder, sink, hip), shoulder)

    upper = Fig()
    upper.line(hip, shoulder)
    head_on(upper, shoulder, hip, FACE_DOWN)
    upper.joint(shoulder, 'shoulder')
    frame = Fig()
    frame.line(hip, knee)
    frame.line(knee, foot)
    frame.line((hand[0] + 6, FLOOR), (hand[0] + 6, hand[1] - 58), w=5, color=DIM)   # la pared
    frame.parts.append(stretching_line((hand[0], hand[1] - 3), (shoulder[0], shoulder[1] - 3),
                                       [(0, 0), sunk, (0, 0)], opacity=.5))
    frame.parts.append(stretching_line(hand, shoulder, [(0, 0), sunk, (0, 0)]))
    frame.pts += upper.pts + [hand, (hand[0] + 6, hand[1] - 58)]
    floor_line(frame, frame.pts)
    for p, name in ((hand, 'hand'), (hip, 'hip'), (knee, 'knee'), (foot, 'foot')):
        frame.joint(p, name)
    return frame.svg(title, swaying(upper.drawn(), hip, [0, sink, 0]))


def hollow(title):
    """Acostado boca arriba, la lumbar en el piso: hombros y brazos despegados en una recta, y
    las piernas juntas y estiradas, también despegadas."""
    floor = 200
    hip = (130, floor - 4)
    up, legs_up = math.radians(15), math.radians(22)
    shoulder = (hip[0] - TORSO * math.cos(up), hip[1] - TORSO * math.sin(up))
    hand = (shoulder[0] - ARM * math.cos(up), shoulder[1] - ARM * math.sin(up))
    axis = ang(sub(hip, shoulder))
    person = Fig()
    # Los brazos van con el cuerpo: junto a las orejas, en la misma recta que el torso.
    person.line((shoulder[0], shoulder[1] + 3), (hand[0], hand[1] + 3), opacity=.5)
    person.line(shoulder, hand)
    pose(person, shoulder, axis, ang((math.cos(legs_up), -math.sin(legs_up))) - axis, 0, facing=FACE_UP)
    person.joint(hand, 'hand')
    frame = Fig()
    frame.pts += person.pts
    floor_line(frame, frame.pts, y=floor, pad=14)
    return frame.svg(title, swaying(person.drawn(), hip, [-1, 1, -1]))


def pike_shrug(title):
    """En pica, brazos bloqueados en línea con el torso. El encogimiento sube el hombro alejándolo
    de la mano; los pies no se despegan, así que el cuerpo gira en los pies."""
    hand = (170, FLOOR)
    a = math.radians(45)                              # brazos y torso, una recta a 45°
    shoulder = (hand[0] - ARM * math.cos(a), hand[1] - ARM * math.sin(a))
    hip = (shoulder[0] - TORSO * math.cos(a), shoulder[1] - TORSO * math.sin(a))
    reach = THIGH + SHIN
    foot = (hip[0] - math.sqrt(reach ** 2 - (FLOOR - hip[1]) ** 2), FLOOR)
    axis = ang(sub(hip, shoulder))
    person = Fig()
    pose(person, shoulder, axis, ang(sub(foot, hip)) - axis, 0, facing=FACE_DOWN)

    # El giro en los pies que aleja el hombro SHRUG de la mano (con el signo que lo aleja).
    def gap(d):
        return math.hypot(*sub(rot(shoulder, d, foot), hand)) - ARM
    sign = 1 if gap(1) > gap(-1) else -1
    lo, hi = 0.0, 20.0
    for _ in range(40):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if gap(sign * mid) < SHRUG else (lo, mid)
    d = round(sign * lo, 2)
    up = sub(rot(shoulder, d, foot), shoulder)

    frame = Fig()
    frame.parts.append(stretching_line((hand[0] + 4, hand[1]), shoulder, [(0, 0), up, (0, 0)], opacity=.5))
    frame.parts.append(stretching_line(hand, shoulder, [(0, 0), up, (0, 0)]))
    frame.joint(hand, 'hand')
    frame.pts += person.pts + [hand]
    floor_line(frame, frame.pts)
    return frame.svg(title, swaying(person.drawn(), foot, [0, d, 0]))


def frog_stand(title):
    """Brazos doblados, las rodillas apoyadas en la parte de atrás del brazo y los pies
    despegados. Se balancea apenas sobre las manos: es el primer equilibrio del programa."""
    hand = (150, FLOOR)
    elbow = limb(hand, ang((-0.24, -0.97)), ARM / 2)   # antebrazo casi vertical, un poco atrás
    shoulder = limb(elbow, ang((0.6, -0.8)), ARM / 2)  # brazo hacia adelante y arriba
    knee = (elbow[0] + .3 * (shoulder[0] - elbow[0]), elbow[1] + .3 * (shoulder[1] - elbow[1]))
    # La cadera es el punto a TORSO del hombro y a THIGH de la rodilla: así la rodilla queda
    # justo sobre el brazo, que es lo que pide la posición. De las dos soluciones, la de atrás.
    d = math.hypot(*sub(knee, shoulder))
    a = (TORSO ** 2 - THIGH ** 2 + d ** 2) / (2 * d)
    h = math.sqrt(TORSO ** 2 - a ** 2)
    u = (sub(knee, shoulder)[0] / d, sub(knee, shoulder)[1] / d)
    base = (shoulder[0] + a * u[0], shoulder[1] + a * u[1])
    hip = min(((base[0] + h * u[1], base[1] - h * u[0]), (base[0] - h * u[1], base[1] + h * u[0])),
              key=lambda p: p[0])
    foot = limb(knee, ang((-0.98, -0.2)), SHIN)        # talones hacia atrás, despegados

    person = Fig()
    person.line((hand[0] + 5, hand[1]), (elbow[0] + 5, elbow[1]), opacity=.5)
    person.line((elbow[0] + 5, elbow[1]), (shoulder[0] + 5, shoulder[1]), opacity=.5)
    person.line(hip, knee, opacity=.5)
    person.line(hand, elbow)
    person.line(elbow, shoulder)
    person.line(shoulder, hip)
    head_on(person, shoulder, hip, ang((0.5, 0.87)))
    person.line(hip, knee)
    person.line(knee, foot)
    for p, name in ((shoulder, 'shoulder'), (hip, 'hip'), (knee, 'knee'), (foot, 'foot')):
        person.joint(p, name)
    frame = Fig()
    frame.joint(hand, 'hand')
    frame.pts += person.pts
    floor_line(frame, frame.pts)
    return frame.svg(title, swaying(person.drawn(), hand, [-1.2, 1.2, -1.2]))


def bunny_hops(title):
    """Las manos fijas, la cadera sube por encima de los hombros con las rodillas dobladas y
    vuelve a cuclillas. Dibujada arriba; el giro en el hombro la baja hasta apoyar los pies."""
    person = Fig()
    j = pose(person, HS_SHOULDER, -180, -100, 110, facing=FACE_DOWN)
    land = 0.0
    while land > -170 and rot(j['foot'], land, HS_SHOULDER)[1] < FLOOR - 4:
        land -= 0.5
    frame = Fig()
    floor_arms(frame, HS_HANDS, HS_SHOULDER)
    frame.circle(HS_HANDS, 6, DIM)
    frame.joint(HS_HANDS, 'hand')
    frame.pts += person.pts + [rot(p, land, HS_SHOULDER) for p in person.pts]
    floor_line(frame, frame.pts)
    return frame.svg(title, swaying(person.drawn(), HS_SHOULDER, [land, 0, 0, land, land],
                                    times=[0, .35, .5, .8, 1]))


def cartwheel_bail(title):
    """La salida en rueda, **de frente**: de perfil un giro de lado no se ve. Desde la parada,
    las piernas se abren, el cuerpo cae hacia el lado de la mano derecha y el pie de ese lado
    llega al piso mientras la otra mano se suelta."""
    hl, hr = (110, FLOOR), (134, FLOOR)
    sl, sr = (hl[0], FLOOR - ARM), (hr[0], FLOOR - ARM)
    mid = ((sl[0] + sr[0]) / 2, sl[1])
    hip = (mid[0], mid[1] - TORSO)
    hip_l, hip_r = (hip[0] - 6, hip[1]), (hip[0] + 6, hip[1])

    def leg(fig, top, op):
        knee = (top[0], top[1] - THIGH)
        foot = (top[0], knee[1] - SHIN)
        fig.line(top, knee, opacity=op)
        fig.line(knee, foot, opacity=op)
        return knee, foot

    trail, lead = Fig(), Fig()
    leg(trail, hip_l, .5)
    knee, foot = leg(lead, hip_r, 1.0)
    lead.joint(knee, 'knee')
    lead.joint(foot, 'foot')
    body = Fig()
    body.line(hl, sl, opacity=.5)                     # la mano que se suelta gira con el cuerpo
    body.line(hr, sr)
    body.line(sl, sr, w=STROKE - 2)
    body.line(mid, hip)
    body.line(hip_l, hip_r, w=STROKE - 2)
    body.line(mid, (mid[0], mid[1] + NECK), w=STROKE - 1)
    body.circle((mid[0], mid[1] + NECK + HEAD_R - 2), HEAD_R)
    body.joint(sr, 'shoulder')
    body.joint(hip, 'hip')

    tilt = 40                                         # cuánto cae el cuerpo hacia la derecha
    open_trail = 18                                   # la pierna de atrás se abre un poco
    step = 0.0
    while step < 175 and rot(rot(foot, step, hip_r), tilt, hr)[1] < FLOOR - 4:
        step += 0.5

    times = [0, .2, .55, .7, 1]
    inner = (swaying(trail.drawn(), hip_l, [0, 0, open_trail, open_trail, 0], times).strip()
             + '\n    ' + swaying(lead.drawn(), hip_r, [0, 0, step, step, 0], times).strip())
    frame = Fig()
    frame.circle(hr, 6, DIM)
    frame.joint(hr, 'hand')
    landed = [rot(rot(foot, step, hip_r), tilt, hr), rot(rot(knee, step, hip_r), tilt, hr)]
    frame.pts += body.pts + trail.pts + lead.pts + [rot(p, tilt, hr) for p in body.pts] + landed
    floor_line(frame, frame.pts)
    outer = swaying(body.parts + [inner] + body.dots, hr, [0, 0, tilt, tilt, 0], times)
    return frame.svg(title, outer)


def wall_walk(title):
    """De plancha con los pies en la pared a pecho contra la pared. Los brazos quedan
    verticales todo el camino (hombro sobre la muñeca), las manos se acercan a la pared y el
    cuerpo recto gira en el hombro; los pies suben por la pared sin despegarse."""
    wall = 236
    body = TORSO + THIGH + SHIN

    def shoulder_x(phi):
        return wall - body * math.cos(math.radians(phi))

    top = 84                                          # pecho casi tocando la pared
    path = [12, 12, 40, 64, top, top, 64, 40, 12]
    times = [0, .08, .22, .34, .45, .62, .74, .86, 1]
    shoulder = (shoulder_x(top), FLOOR - ARM)
    hand = (shoulder[0], FLOOR)
    person = Fig()
    pose(person, shoulder, ang((math.cos(math.radians(top)), -math.sin(math.radians(top)))),
         facing=FACE_RIGHT)
    arms = Fig()
    arms.line((hand[0] - 3, hand[1]), (shoulder[0] - 3, shoulder[1]))
    arms.line((hand[0] + 3, hand[1]), (shoulder[0] + 3, shoulder[1]), opacity=.5)
    arms.joint(hand, 'hand')
    inner = swaying(person.drawn(), shoulder, [top - phi for phi in path], times).strip()
    outer = moving(arms.parts + [inner] + arms.dots,
                   [(shoulder_x(phi) - shoulder[0], 0) for phi in path], times)

    frame = Fig()
    bottom = shoulder_x(path[0]) - shoulder[0]
    frame.pts += person.pts + arms.pts + [(rot(p, top - path[0], shoulder)[0] + bottom,
                                           rot(p, top - path[0], shoulder)[1]) for p in person.pts]
    floor_line(frame, frame.pts)
    frame.line((wall + 5, FLOOR), (wall + 5, min(p[1] for p in person.pts) - 12), w=5, color=DIM)
    return frame.svg(title, outer)


def kick_up(title, wall):
    """Desde la zancada con las manos abajo, la pierna de atrás patea y la otra la alcanza
    arriba. Dibujada arriba, con las piernas juntas; para bajarla, el cuerpo gira en el hombro
    y la pierna de apoyo gira en la cadera hasta quedar vertical con el pie en el piso."""
    axis = -171 if wall else -180                     # de espaldas a la pared, o libre
    shoulder = HS_SHOULDER
    hip = limb(shoulder, axis, TORSO)
    kick_knee = limb(hip, axis, THIGH)
    kick_foot = limb(kick_knee, axis, SHIN)

    person = Fig()
    person.line(shoulder, hip)
    head_on(person, shoulder, hip, FACE_DOWN)
    person.line(hip, kick_knee)
    person.line(kick_knee, kick_foot)
    for p, name in ((shoulder, 'shoulder'), (hip, 'hip'), (kick_knee, 'knee'), (kick_foot, 'foot')):
        person.joint(p, name)
    support = Fig()
    support.line(hip, kick_knee, opacity=.5)
    support.line(kick_knee, kick_foot, opacity=.5)

    # Abajo: el cuerpo inclinado lo justo para que la pierna de apoyo, vertical, llegue al piso.
    down = 0.0
    while down > -120 and rot(hip, down, shoulder)[1] + THIGH + SHIN < FLOOR - 3:
        down -= 0.5
    lean = ((axis + down) + 180) % 360 - 180          # hacia dónde apunta el torso abajo
    plant = -lean                                     # lo que gira la pierna de apoyo en la cadera
    times = [0, .38, .62, .9, 1]
    inner = swaying(support.drawn(), hip, [plant, 0, 0, plant, plant], times).strip()
    outer = swaying([inner] + person.parts + person.dots, shoulder, [down, 0, 0, down, down], times)

    frame = Fig()
    floor_arms(frame, HS_HANDS, shoulder)
    frame.circle(HS_HANDS, 6, DIM)
    frame.joint(HS_HANDS, 'hand')
    low_hip = rot(hip, down, shoulder)
    frame.pts += person.pts + [rot(p, down, shoulder) for p in person.pts] \
        + [low_hip, (low_hip[0], low_hip[1] + THIGH + SHIN)]
    floor_line(frame, frame.pts)
    if wall:
        wx = max(p[0] for p in person.pts) + 7
        frame.line((wx, FLOOR), (wx, min(p[1] for p in person.pts) - 12), w=5, color=DIM)
    return frame.svg(title, outer)


DRILLS = {
    'preparacion-de-munecas': wrist_prep,
    'apertura-de-hombros-en-pared': shoulder_wall,
    'hollow-hold': hollow,
    'encogimientos-en-pica': pike_shrug,
    'parada-de-rana': frog_stand,
    'patadas-de-conejo': bunny_hops,
    'salida-en-rueda': cartwheel_bail,
    'caminata-en-pared': wall_walk,
    'patada-a-la-pared': lambda title: kick_up(title, wall=True),
    'patada-al-equilibrio': lambda title: kick_up(title, wall=False),
}


TITLES = {
    'colgado-invertido': 'Colgado invertido',
    'front-lever-tuck': 'Front lever tuck',
    'front-lever-tuck-avanzado': 'Front lever tuck avanzado',
    'front-lever-a-una-pierna': 'Front lever a una pierna',
    'front-lever-straddle': 'Front lever straddle',
    'front-lever-half-lay': 'Front lever half lay',
    'front-lever-completo': 'Front lever completo',
    'front-lever-a-un-brazo': 'Front lever a un brazo',
    'plancha-en-pared-45-grados': 'Plancha en pared 45 grados',
    'parada-de-manos-en-pared': 'Parada de manos en pared',
    'parada-de-manos-de-frente-a-la-pared': 'Parada de manos de frente a la pared',
    'heel-pulls-toe-pulls': 'Heel pulls / toe pulls',
    'parada-de-manos-libre': 'Parada de manos libre',
    'traspaso-de-peso-en-parada-de-manos': 'Traspaso de peso en parada de manos',
    'parada-de-manos-a-un-brazo': 'Parada de manos a un brazo',
    'planche-lean': 'Planche lean',
    'plancha-tuck': 'Plancha tuck',
    'plancha-tuck-avanzada': 'Plancha tuck avanzada',
    'plancha-straddle': 'Plancha straddle',
    'plancha-completa': 'Plancha completa',
    'back-lever-tuck': 'Back lever tuck',
    'back-lever-straddle': 'Back lever straddle',
    'back-lever-completo': 'Back lever completo',
    'elevacion-a-front-lever-tuck': 'Elevación a front lever tuck',
    'elevacion-a-front-lever-tuck-avanzado': 'Elevación a front lever tuck avanzado',
    'elevacion-a-front-lever-straddle': 'Elevación a front lever straddle',
    'elevaciones-a-front-lever': 'Elevaciones a front lever',
    'dominada-al-pecho': 'Dominada al pecho',
    'dominada-con-agarre-falso': 'Dominada con agarre falso',
    'muscle-up-negativo': 'Muscle-up negativo',
    'muscle-up-en-barra': 'Muscle-up en barra',
    'curl-nordico-negativo': 'Curl nórdico negativo',
    'curl-nordico-asistido': 'Curl nórdico asistido',
    'curl-nordico': 'Curl nórdico',
    'curl-nordico-con-peso': 'Curl nórdico con peso',
    'toques-de-hombro-en-pared': 'Toques de hombro en pared',
    'encogimientos-de-frente-a-la-pared': 'Encogimientos de frente a la pared',
    'preparacion-de-munecas': 'Preparación de muñecas',
    'apertura-de-hombros-en-pared': 'Apertura de hombros en pared',
    'hollow-hold': 'Hollow body',
    'encogimientos-en-pica': 'Encogimientos en pica',
    'parada-de-rana': 'Parada de rana',
    'patadas-de-conejo': 'Patadas de conejo',
    'salida-en-rueda': 'Salida en rueda',
    'caminata-en-pared': 'Caminata en pared',
    'patada-a-la-pared': 'Patada a la pared',
    'patada-al-equilibrio': 'Patada al equilibrio',
}


def main():
    OUT.mkdir(exist_ok=True)
    for slug, cfg in FRONT_LEVER.items():
        (OUT / f'{slug}.svg').write_text(front_lever(cfg, TITLES[slug]), encoding='utf8')
    for slug, cfg in HANDSTAND.items():
        (OUT / f'{slug}.svg').write_text(handstand(cfg, TITLES[slug]), encoding='utf8')
    for group, fn in ((PLANCHE, planche), (BACK_LEVER, back_lever), (FL_RAISE, fl_raise),
                      (MUSCLE_UP, muscle_up), (NORDIC, nordic)):
        for slug, cfg in group.items():
            (OUT / f'{slug}.svg').write_text(fn(cfg, TITLES[slug]), encoding='utf8')
    for slug, fn in DRILLS.items():
        (OUT / f'{slug}.svg').write_text(fn(TITLES[slug]), encoding='utf8')
    total = sum(len(g) for g in (FRONT_LEVER, HANDSTAND, PLANCHE, BACK_LEVER, FL_RAISE,
                                 MUSCLE_UP, NORDIC, DRILLS))
    print(f'{total} animaciones en {OUT}')


if __name__ == '__main__':
    main()
