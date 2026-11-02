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


def pose(fig, shoulder, axis, hip_deg=0, knee_deg=0, legs='together', split=0):
    """El cuerpo del hombro hacia abajo, ya en su posición.

    axis: hacia dónde apunta el torso (0 = abajo, -90 = horizontal a la derecha, -180 = arriba).
    hip_deg / knee_deg: cuánto se dobla cada articulación respecto al segmento anterior.
    legs: 'together' | 'split' (straddle) | 'one' (una estirada y otra doblada).
    """
    hip = limb(shoulder, axis, TORSO)
    # Cuello y cabeza van del lado contrario a la cadera: en un front lever la cabeza queda
    # junto a las manos, porque el cuerpo sale del hombro hacia los pies.
    neck = rot((shoulder[0], shoulder[1] - NECK), axis, shoulder)
    head = rot((shoulder[0], shoulder[1] - NECK - HEAD_R + 2), axis, shoulder)
    fig.line(shoulder, hip)
    fig.line(shoulder, neck, w=STROKE - 1)
    fig.circle(head, HEAD_R)

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


def swaying(fig_parts, about, values=None):
    """Envuelve la figura en el movimiento de encima. Los valores son relativos a la pose,
    que ya está dibujada en su sitio: 0 es la posición correcta."""
    vals = values or [-SWAY, SWAY, -SWAY]
    times = ';'.join(f'{i / (len(vals) - 1):.2f}' for i in range(len(vals)))
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
    pose(person, SHOULDER, axis, hip, knee, legs, split)

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
    pose(person, HS_SHOULDER, axis)

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
}


def main():
    OUT.mkdir(exist_ok=True)
    for slug, cfg in FRONT_LEVER.items():
        (OUT / f'{slug}.svg').write_text(front_lever(cfg, TITLES[slug]), encoding='utf8')
    for slug, cfg in HANDSTAND.items():
        (OUT / f'{slug}.svg').write_text(handstand(cfg, TITLES[slug]), encoding='utf8')
    print(f'{len(FRONT_LEVER) + len(HANDSTAND)} animaciones en {OUT}')


if __name__ == '__main__':
    main()
