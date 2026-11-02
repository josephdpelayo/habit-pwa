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
}


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
    else:
        frame.line((HS_HANDS[0] - 9, HS_HANDS[1]), (HS_SHOULDER[0] - 4, HS_SHOULDER[1]))
        frame.line((HS_HANDS[0] + 9, HS_HANDS[1]), (HS_SHOULDER[0] + 4, HS_SHOULDER[1]), opacity=.5)
        frame.joint(HS_HANDS, 'hand')
    frame.circle(HS_HANDS, 6, DIM)
    frame.pts += person.pts

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
    total = sum(len(g) for g in (FRONT_LEVER, HANDSTAND, PLANCHE, BACK_LEVER, FL_RAISE,
                                 MUSCLE_UP, NORDIC))
    print(f'{total} animaciones en {OUT}')


if __name__ == '__main__':
    main()
