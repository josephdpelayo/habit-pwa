#!/usr/bin/env python3
"""Dibuja la animación de cada escalón de las escaleras de calistenia.

Salida: skill-anim/<slug>.svg, uno por escalón. Son SVG animados —SMIL, sin JavaScript—
porque dentro de un <img> corren solos, pesan unos kilobytes y se ven igual de nítidos en
la miniatura de 58 px que en el encabezado de la hoja. La migración 142 los enlaza en
exercise_catalog.animation_url.

No pretenden ser el video: son el dibujo que hace legible la escalera desde el día uno, y
el día que haya video de cada escalón se sube desde Admin y pisa esta URL.

Tres decisiones que vale la pena no deshacer:

  · **La figura se dibuja ya en su posición**, en coordenadas absolutas. La animación es
    solo la oscilación de encima. Así el generador sabe exactamente dónde cae cada
    articulación, que es lo que permite encuadrar y poner la barra y el muro en su sitio.
  · **La pose está quieta.** Lo que se hace en una escalera es comparar ocho posiciones de
    un vistazo, y ocho figuras repitiendo la entrada las dejan todas a mitad de camino justo
    cuando hay que compararlas. Solo se mueven los escalones donde el movimiento ES el
    ejercicio: el jalón de talón y el traspaso de peso.
  · **El encuadre se calcula solo.** Un colgado invertido ocupa alto y un front lever ocupa
    ancho; cuadrar los quince a mano era perseguir recortes.

Correr:  python3 scripts/make-skill-anim.py
"""
import math
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / 'skill-anim'

INK = '#e8e9ee'                   # la figura
DIM = 'rgba(232,233,238,.3)'      # barra, piso y muro
HEAD_R, STROKE, PAD = 11, 7, 16

# Largos del cuerpo. Proporciones de persona, no de palo.
ARM, TORSO, THIGH, SHIN, NECK = 52, 48, 40, 38, 16
CYCLE = '5s'
SWAY = 1.5                        # grados: lo justo para que no parezca un dibujo muerto
FACE_UP, FACE_DOWN = 180, 0       # hacia dónde mira la cara, en el marco sin rotar


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
        self.parts, self.pts = [], []

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
        return (f'<svg xmlns="http://www.w3.org/2000/svg" '
                f'viewBox="{x0:.0f} {y0:.0f} {w:.0f} {h:.0f}" preserveAspectRatio="xMidYMid meet" '
                f'role="img" aria-label="{title}">\n  <title>{title}</title>\n  '
                + '\n  '.join(self.parts) + '\n' + groups + '</svg>\n')


def pose(fig, shoulder, axis, hip_deg=0, knee_deg=0, legs='together', split=0, facing=None):
    """El cuerpo del hombro hacia abajo, ya en su posición.

    axis: hacia dónde apunta el torso (0 = abajo, -90 = horizontal a la derecha, -180 = arriba).
    hip_deg / knee_deg: cuánto se dobla cada articulación respecto al segmento anterior.
    legs: 'together' | 'split' (straddle) | 'one' (una estirada y otra doblada).
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

    if legs == 'one':
        pairs = [(0, 0), (hip_deg, knee_deg)]
    elif legs == 'split':
        pairs = [(split, knee_deg), (-split, knee_deg)]
    else:
        pairs = [(hip_deg, knee_deg), (hip_deg, knee_deg)]
    for i, (hd, kd) in enumerate(pairs):
        op = 1.0 if i == 0 else .5                     # la pierna de atrás, más tenue
        knee = limb(hip, axis + hd, THIGH)
        fig.line(hip, knee, opacity=op)
        fig.line(knee, limb(knee, axis + hd + kd, SHIN), opacity=op)


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


# ───────────────────────────── Front lever ─────────────────────────────

HANDS = (110, 40)
SHOULDER = (HANDS[0], HANDS[1] + ARM)

FRONT_LEVER = {
    # slug: (torso, cadera, rodilla, piernas, apertura, un brazo)
    'colgado-invertido':          (-180,    0,    0, 'together',  0, False),
    'front-lever-tuck':           ( -90, -140,  158, 'together',  0, False),
    'front-lever-tuck-avanzado':  ( -90,  -38,  100, 'together',  0, False),
    'front-lever-a-una-pierna':   ( -90, -120,  140, 'one',       0, False),
    'front-lever-straddle':       ( -90,    0,    0, 'split',    26, False),
    'front-lever-half-lay':       ( -90,    0,   95, 'together',  0, False),
    'front-lever-completo':       ( -90,    0,    0, 'together',  0, False),
    'front-lever-a-un-brazo':     ( -90,    0,    0, 'together',  0, True),
}


def front_lever(cfg, title):
    axis, hip, knee, legs, split, one_arm = cfg
    person = Fig()
    pose(person, SHOULDER, axis, hip, knee, legs, split, facing=FACE_UP)

    frame = Fig()
    # La barra abarca lo que ocupa la pose: una barra fija dejaba al colgado invertido con
    # media barra vacía y al lever completo con la barra cortada.
    xs = [p[0] for p in person.pts] + [HANDS[0]]
    frame.line((min(xs) - 14, HANDS[1]), (max(xs) + 14, HANDS[1]), w=5, color=DIM)
    if one_arm:
        frame.line(HANDS, SHOULDER)
    else:
        frame.line((HANDS[0] - 7, HANDS[1]), (SHOULDER[0] - 7, SHOULDER[1]))
        frame.line((HANDS[0] + 7, HANDS[1]), (SHOULDER[0] + 7, SHOULDER[1]), opacity=.5)
    frame.circle(HANDS, 6, DIM)
    frame.pts += person.pts
    return frame.svg(title, swaying(person.parts, SHOULDER))


# ───────────────────────────── Parada de manos ─────────────────────────────

HS_HANDS = (120, 210)
HS_SHOULDER = (HS_HANDS[0], HS_HANDS[1] - ARM)

HANDSTAND = {
    #                                        torso, muro, modo
    'plancha-en-pared-45-grados':            (-130, 'back',  'static'),
    'parada-de-manos-en-pared':              (-171, 'back',  'static'),
    'parada-de-manos-de-frente-a-la-pared':  (-180, 'front', 'static'),
    'heel-pulls-toe-pulls':                  (-180, 'front', 'pulls'),
    'parada-de-manos-libre':                 (-180, None,    'sway'),
    'traspaso-de-peso-en-parada-de-manos':   (-180, None,    'shift'),
    'parada-de-manos-a-un-brazo':            (-180, None,    'onearm'),
}


def handstand(cfg, title):
    axis, wall, mode = cfg
    person = Fig()
    pose(person, HS_SHOULDER, axis, facing=FACE_DOWN)

    frame = Fig()
    xs = [p[0] for p in person.pts]
    ys = [p[1] for p in person.pts]
    frame.line((min(xs) - 22, HS_HANDS[1]), (max(xs) + 22, HS_HANDS[1]), w=5, color=DIM)
    if wall:                       # el muro toca los pies por detrás, o el pecho por delante
        wx = max(xs) + 7 if wall == 'back' else min(xs) - 9
        frame.line((wx, HS_HANDS[1]), (wx, min(ys) - 12), w=5, color=DIM)

    if mode == 'onearm':
        frame.line(HS_HANDS, HS_SHOULDER)
    elif mode == 'shift':
        # Una mano se descarga hasta quedar en las puntas, y vuelve. Es el ejercicio.
        frame.line((HS_HANDS[0] - 9, HS_HANDS[1]), (HS_SHOULDER[0] - 4, HS_SHOULDER[1]))
        lifted = Fig()
        lifted.line((HS_HANDS[0] + 9, HS_HANDS[1]), (HS_SHOULDER[0] + 4, HS_SHOULDER[1]), opacity=.5)
        frame.pts += lifted.pts
        frame.parts.append(
            '<g><animateTransform attributeName="transform" type="translate" '
            f'values="0 0;0 -13;0 0" keyTimes="0;.5;1" dur="{CYCLE}" repeatCount="indefinite" '
            f'calcMode="spline" keySplines="0.4 0 0.2 1;0.4 0 0.2 1"/>{lifted.parts[0]}</g>')
    else:
        frame.line((HS_HANDS[0] - 9, HS_HANDS[1]), (HS_SHOULDER[0] - 4, HS_SHOULDER[1]))
        frame.line((HS_HANDS[0] + 9, HS_HANDS[1]), (HS_SHOULDER[0] + 4, HS_SHOULDER[1]), opacity=.5)
    frame.circle(HS_HANDS, 6, DIM)
    frame.pts += person.pts

    if mode == 'pulls':      # el jalón ES el ejercicio: el cuerpo se despega del muro y vuelve
        vals = [0, 8, 0, -2, 0]
    elif mode == 'sway':     # un hold libre nunca está quieto: corregir es la habilidad
        vals = [0, 3.5, 0, -3.5, 0]
    else:
        vals = None
    return frame.svg(title, swaying(person.parts, HS_SHOULDER, vals))



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
    # slug: (inclinación del brazo, torso, cadera, rodilla, piernas, apertura)
    'planche-lean':           (22,  68,    0,    0, 'together',  0),
    'plancha-tuck':           (34,  90,  140, -158, 'together',  0),
    'plancha-tuck-avanzada':  (34,  90,   38, -100, 'together',  0),
    'plancha-straddle':       (36,  90,    0,    0, 'split',    26),
    'plancha-completa':       (38,  90,    0,    0, 'together',  0),
}


def planche(cfg, title):
    arm_deg, axis, hip, knee, legs, split = cfg
    shoulder = rot((PL_HANDS[0], PL_HANDS[1] - ARM), arm_deg, PL_HANDS)
    person = Fig()
    pose(person, shoulder, axis, hip, knee, legs, split, facing=FACE_DOWN)

    frame = Fig()
    xs = [q[0] for q in person.pts] + [PL_HANDS[0]]
    frame.line((min(xs) - 20, PL_HANDS[1]), (max(xs) + 20, PL_HANDS[1]), w=5, color=DIM)
    frame.line((PL_HANDS[0] - 7, PL_HANDS[1]), (shoulder[0] - 7, shoulder[1]))
    frame.line((PL_HANDS[0] + 7, PL_HANDS[1]), (shoulder[0] + 7, shoulder[1]), opacity=.5)
    frame.circle(PL_HANDS, 6, DIM)
    frame.pts += person.pts
    return frame.svg(title, swaying(person.parts, shoulder))


# ───────────────────────────── Back lever ─────────────────────────────
# Mismo colgado que el front lever, pero de cara al piso y con el cuerpo del otro lado.
# Sin la marca de orientación los dos serían el mismo dibujo.

BACK_LEVER = {
    'back-lever-tuck':       (90, 140, -158, 'together',  0),
    'back-lever-straddle':   (90,   0,    0, 'split',    26),
    'back-lever-completo':   (90,   0,    0, 'together',  0),
}


def back_lever(cfg, title):
    axis, hip, knee, legs, split = cfg
    person = Fig()
    pose(person, SHOULDER, axis, hip, knee, legs, split, facing=FACE_DOWN)
    frame = Fig()
    xs = [q[0] for q in person.pts] + [HANDS[0]]
    frame.line((min(xs) - 14, HANDS[1]), (max(xs) + 14, HANDS[1]), w=5, color=DIM)
    frame.line((HANDS[0] - 7, HANDS[1]), (SHOULDER[0] - 7, SHOULDER[1]))
    frame.line((HANDS[0] + 7, HANDS[1]), (SHOULDER[0] + 7, SHOULDER[1]), opacity=.5)
    frame.circle(HANDS, 6, DIM)
    frame.pts += person.pts
    return frame.svg(title, swaying(person.parts, SHOULDER))


# ───────────────────────── Elevaciones a front lever ─────────────────────────
# Aquí el movimiento SÍ es el ejercicio: la repetición es jalar hasta la horizontal y bajar
# con los brazos bloqueados. Por eso estas cuatro no se quedan quietas como los aguantes.

FL_RAISE = {
    'elevacion-a-front-lever-tuck':           (-140,  158, 'together',  0),
    'elevacion-a-front-lever-tuck-avanzado':  ( -38,  100, 'together',  0),
    'elevacion-a-front-lever-straddle':       (   0,    0, 'split',    26),
    'elevaciones-a-front-lever':              (   0,    0, 'together',  0),
}


def fl_raise(cfg, title):
    hip, knee, legs, split = cfg
    person = Fig()
    pose(person, SHOULDER, -90, hip, knee, legs, split, facing=FACE_UP)
    frame = Fig()
    # La barra abarca la posición de arriba Y la de colgado, que ocupa alto pero poco ancho.
    xs = [q[0] for q in person.pts] + [HANDS[0]]
    frame.line((min(xs) - 14, HANDS[1]), (max(xs) + 14, HANDS[1]), w=5, color=DIM)
    frame.line((HANDS[0] - 7, HANDS[1]), (SHOULDER[0] - 7, SHOULDER[1]))
    frame.line((HANDS[0] + 7, HANDS[1]), (SHOULDER[0] + 7, SHOULDER[1]), opacity=.5)
    frame.circle(HANDS, 6, DIM)
    frame.pts += person.pts
    # El cuerpo está dibujado arriba; rotarlo +90 lo devuelve al colgado. La repetición es
    # subir, aguantar un segundo en la horizontal, bajar con control y esperar abajo.
    for q in person.pts:
        frame.pts.append(rot(q, 90, SHOULDER))
    vals = [90, 0, 0, 90, 90]
    return frame.svg(title, swaying(person.parts, SHOULDER, vals, times=[0, .30, .46, .78, 1]))


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


def muscle_up(where, title):
    if where == 'hang':        # colgado completo; lo que se marca es la muñeca sobre la barra
        shoulder, axis = (MU_HANDS[0], MU_BAR_Y + ARM), 0
    elif where == 'pull':      # arriba de la dominada: el pecho llega a la barra
        shoulder, axis = (MU_HANDS[0], MU_BAR_Y + 27), 0
    elif where == 'trans':     # la transición: hombro sobre la barra, cadera todavía abajo.
        # Estática a propósito: un negativo se baja doblando el brazo, y rotar el cuerpo
        # alrededor del hombro para «animarlo» dibujaba una marometa.
        shoulder, axis = (MU_HANDS[0] + 12, MU_BAR_Y - 9), 22
    else:                      # apoyo arriba de la barra, brazos bloqueados
        shoulder, axis = (MU_HANDS[0], MU_BAR_Y - ARM), -180

    person = Fig()
    pose(person, shoulder, axis, facing=FACE_UP if where in ('hang', 'pull') else FACE_DOWN)

    frame = Fig()
    frame.line((MU_HANDS[0] - MU_BAR_HALF, MU_BAR_Y), (MU_HANDS[0] + MU_BAR_HALF, MU_BAR_Y),
               w=5, color=DIM)
    # Los codos se abren a los lados: con los dos doblándose hacia el mismo lado se cruzaban.
    for side, bend, op in ((-9, -1, 1.0), (9, 1, .5)):
        bent_arm(frame, (MU_HANDS[0] + side, MU_BAR_Y), (shoulder[0] + side * .55, shoulder[1]),
                 bend, opacity=op)
    if where == 'hang':        # el agarre falso se ve en la muñeca por encima de la barra
        frame.circle((MU_HANDS[0] - 9, MU_BAR_Y - 6), 6, INK)
        frame.circle((MU_HANDS[0] + 9, MU_BAR_Y - 6), 6, INK)
    else:
        frame.circle(MU_HANDS, 6, DIM)
    frame.pts += person.pts
    return frame.svg(title, swaying(person.parts, shoulder))


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

    # Bajar despacio y volver: lo contrario de un aguante, aquí la lentitud es el estándar.
    # Baja despacio —4 o 5 segundos es el estándar del escalón 1— y vuelve más rápido. Que
    # la bajada ocupe más de la mitad del ciclo no es estética: es lo que hay que imitar.
    frame.pts += person.pts
    for q in person.pts:
        frame.pts.append(rot(q, -descent, NC_KNEE))
    return frame.svg(title, swaying(person.parts, NC_KNEE, [-10, -descent, -descent, -10],
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
