#!/usr/bin/env python3
"""Genera el PDF de la semana a bordo (calistenia de Alge + carrera de Carlos Rojo + HYROX).

    python3 plan_semanal_pdf.py      # escribe Plan_Semanal_Joseph_10K.pdf

Las velocidades de umbral y de 10K salen de plan_10k_22nov2026.py: despues del test del 17 oct,
llenar TEST_30MIN_KMH alli y volver a generar este PDF.
"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer,
                                Table, TableStyle)

from plan_10k_22nov2026 import TEST_30MIN_KMH, velocidades

OUT = Path(__file__).with_name("Plan_Semanal_Joseph_10K.pdf")
VEL = (velocidades() if TEST_30MIN_KMH else
       "Las velocidades exactas en km/h salen del test del 17 de octubre; mientras, guíate por "
       "la FC y el esfuerzo.")

FONTS = "/System/Library/Fonts/Supplemental"
pdfmetrics.registerFont(TTFont("Arial", f"{FONTS}/Arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Bold", f"{FONTS}/Arial Bold.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Italic", f"{FONTS}/Arial Italic.ttf"))
pdfmetrics.registerFontFamily("Arial", normal="Arial", bold="Arial-Bold", italic="Arial-Italic")

NAVY = colors.HexColor("#0f2742")
INK = colors.HexColor("#1f2933")
MUTED = colors.HexColor("#5b6670")
LINE = colors.HexColor("#d5dbe1")
SOFT = colors.HexColor("#f3f5f8")
CAL = "#6941c6"     # calistenia
RUN = "#0e7c86"     # carrera
HYR = "#c4320a"     # HYROX
LEG = "#1d5fd1"     # pierna para correr
REC = "#2f8a4c"     # recuperacion
WARN = colors.HexColor("#b54708")
ALARM = colors.HexColor("#b42318")

W = A4[0] - 32 * mm

S = {
    "title": ParagraphStyle("title", fontName="Arial-Bold", fontSize=26, leading=30, textColor=NAVY),
    "sub": ParagraphStyle("sub", fontName="Arial", fontSize=12, leading=16, textColor=INK),
    "h1": ParagraphStyle("h1", fontName="Arial-Bold", fontSize=16, leading=20, textColor=NAVY,
                         spaceBefore=4, spaceAfter=6),
    "h2": ParagraphStyle("h2", fontName="Arial-Bold", fontSize=11.5, leading=15, textColor=NAVY,
                         spaceBefore=8, spaceAfter=3),
    "body": ParagraphStyle("body", fontName="Arial", fontSize=9.5, leading=13.2, textColor=INK,
                           alignment=TA_LEFT, spaceAfter=3),
    "small": ParagraphStyle("small", fontName="Arial", fontSize=8.5, leading=11.3, textColor=INK),
    "smallb": ParagraphStyle("smallb", fontName="Arial-Bold", fontSize=8.5, leading=11.3, textColor=INK),
    "th": ParagraphStyle("th", fontName="Arial-Bold", fontSize=8.5, leading=11, textColor=colors.white),
    "muted": ParagraphStyle("muted", fontName="Arial", fontSize=8, leading=10.5, textColor=MUTED),
    "bullet": ParagraphStyle("bullet", fontName="Arial", fontSize=9.5, leading=13.2, textColor=INK,
                             leftIndent=11, bulletIndent=1, spaceAfter=2),
    "day": ParagraphStyle("day", fontName="Arial-Bold", fontSize=17, leading=21, textColor=colors.white),
    "dayr": ParagraphStyle("dayr", fontName="Arial", fontSize=9.5, leading=13, textColor=colors.white),
}


def p(text, style="body"):
    return Paragraph(text, S[style])


def bullets(items, style="bullet"):
    return [Paragraph(t, S[style], bulletText="•") for t in items]


def chip(label, color):
    return f'<font backColor="{color}" color="white">&nbsp;{label}&nbsp;</font>'


def table(rows, widths, head_color=NAVY, zebra=True, font="small"):
    data = [[c if not isinstance(c, str) else Paragraph(c, S["th"] if i == 0 else S[font])
             for c in row] for i, row in enumerate(rows)]
    t = Table(data, colWidths=[w * W for w in widths], repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), head_color),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE),
        ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
    ]
    if zebra:
        style += [("BACKGROUND", (0, r), (-1, r), SOFT) for r in range(2, len(rows), 2)]
    t.setStyle(TableStyle(style))
    return t


def box(title, items, color, bg="#ffffff"):
    """Recuadro con borde de color a la izquierda: titulo + vinetas."""
    inner = [Paragraph(f'<font color="{color}"><b>{title}</b></font>', S["body"])]
    inner += bullets(items)
    t = Table([[inner]], colWidths=[W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(bg)),
        ("LINEBEFORE", (0, 0), (0, -1), 3, colors.HexColor(color)),
        ("LEFTPADDING", (0, 0), (-1, -1), 9), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return KeepTogether([t, Spacer(1, 6)])


def day_header(name, focus, chips):
    t = Table([[p(name, "day"), p(focus + "<br/>" + " ".join(chips), "dayr")]],
              colWidths=[0.27 * W, 0.73 * W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), NAVY),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 10), ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return [t, Spacer(1, 6)]


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Arial", 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(16 * mm, 10 * mm, "Plan semanal a bordo · Joseph Pelayo · bloque 10K (15 oct – 22 nov 2026)")
    canvas.drawRightString(A4[0] - 16 * mm, 10 * mm, f"{doc.page}")
    canvas.restoreState()


CALISTENIA = chip("Calistenia (Alge)", CAL)
CARRERA = chip("Carrera (Carlos Rojo)", RUN)
HYROX = chip("HYROX", HYR)
PIERNA = chip("Pierna para correr", LEG)
RECUP = chip("Recuperación", REC)

# ── Bloques reutilizados ────────────────────────────────────────────────────

TIRON_CAL = ("<b>Calentamiento (Alge):</b> entrada en calor (correr o comba) · movilidad articular 20 s por "
             "articulación · 8 flexiones (antagonistas) · retracciones escapulares colgado · alguna dominada.")
TIRON_ROWS = [
    ["Ejercicio", "Series × reps", "Intensidad", "Descanso"],
    ["Aguante front lever", "1 × 80% de tu máximo", "Submáximo, forma limpia", "3–4 min"],
    ["Front press + negativa + aguante", "2 series", "Al fallo técnico", "3–4 min"],
    ["Half press + negativa", "2 series", "Al fallo técnico", "3–4 min"],
    ["Touch tuck advanced", "2 × 6–8", "Con goma si hace falta", "3–4 min"],
    ["Dominadas tuck advanced de front", "2 × 6", "Técnica estricta", "3–4 min"],
]
EMPUJE_CAL = ("<b>Calentamiento (Alge):</b> entrada en calor · movilidad articular 20 s por articulación · "
              "retracción-protracción en posición de flexión 2×10 · algunas flexiones normales y de pica · "
              "poner peso en las muñecas.")
EMPUJE_ROWS = [
    ["Ejercicio", "Series × reps", "Intensidad", "Descanso"],
    ["Aguante de 90 grados", "2 series", "Al fallo técnico", "3–4 min"],
    ["Subida a pino por fuerza", "2 series", "Al fallo (técnico)", "3–4 min"],
    ["Flexiones de pino profundas en pared, en paralelas", "2 series", "RIR 0, bajada 2–4 s sin rebote", "3–4 min"],
    ["Flexiones lean planche", "2 × 6", "Técnica estricta", "3–4 min"],
]
CALI_W = [0.38, 0.2, 0.28, 0.14]

PREVENCION_R16 = [
    ["Ejercicio", "Series × reps", "Para qué"],
    ["Rotación externa con banda", "2 × 15–25", "Manguito rotador: hombro estable en handstand y thrusters"],
    ["Face pull o Y en banda", "2 × 12–20", "Escápula y parte posterior del hombro"],
    ["Flexores de antebrazo (muñeca hacia arriba)", "2 × 12–20", "Codo por dentro: aguanta la dosis de agarre"],
    ["Extensores de antebrazo (muñeca hacia abajo)", "2 × 12–20", "Codo por fuera"],
]


def build():
    story = []

    # ── Portada y semana de un vistazo ──────────────────────────────────────
    story += [
        p("Plan semanal a bordo", "title"), Spacer(1, 4),
        p("Joseph Pelayo · Bloque 10K · 15 de octubre – 22 de noviembre de 2026", "sub"),
        p("Calistenia: Algecalistenia (M1) · Carrera: método Carlos Rojo Running · HYROX: TrainingPeaks · "
          "Datos: Garmin vía Intervals.icu", "muted"),
        Spacer(1, 10),
        box("Prioridades: cuando dos cosas chocan, cede la de abajo", [
            "<b>1. Calistenia de Alge.</b> Empuje y tirón no se limitan: se hacen frescos y completos.",
            "<b>2. Carrera con el método de Carlos Rojo.</b> Preparar el 10K del 22 de noviembre.",
            "<b>3. HYROX dos veces por semana.</b> Progresando despacio y sin estorbar a lo anterior.",
        ], CAL, "#f7f5fd"),
        p("La semana de un vistazo", "h1"),
        table([
            ["Día", "Sesión (en este orden)", "Piernas", "Por qué ese día"],
            ["<b>Lun</b>", "Handstand → Tirón → Pierna para correr", "Duro",
             "La pierna queda a 5 días del umbral y a 6 del largo. El tirón no compite con la pierna."],
            ["<b>Mar</b>", "Handstand → Empuje → HYROX (tarde)", "Duro",
             "Tu HYROX carga pierna y empuje: va detrás del empuje, que ya hiciste fresco."],
            ["<b>Mié</b>", "Handstand → Tirón → Rodaje Z2 + rectas", "Suave",
             "El rodaje suave recupera del HYROX. El tirón llega fresco: el HYROX casi no tira."],
            ["<b>Jue</b>", "Handstand → Empuje → HYROX (tarde)", "Medio",
             "48 h después del empuje del martes. Queda a 48 h del umbral: saltos sustituidos."],
            ["<b>Vie</b>", "Descanso activo: handstand técnico, movilidad, prevención (+ bici suave)", "Descanso",
             "Llegar fresco al sábado y avanzar en movilidad."],
            ["<b>Sáb</b>", "Handstand → Umbral → ½ empuje + core + prevención + movilidad", "Clave",
             "El umbral es la sesión estrella de Carlos Rojo."],
            ["<b>Dom</b>", "Rodaje largo Z2 (handstand opcional o caminar)", "Suave, largo",
             "Base aeróbica a baja intensidad: el lunes llegas bien a la pierna."],
        ], [0.08, 0.4, 0.12, 0.4]),
        Spacer(1, 8),
        box("Reglas de oro", [
            "<b>El handstand siempre va primero</b>: es lo que más frescura necesita.",
            "<b>La calistenia va antes que la carrera y el HYROX</b> el mismo día. Si los turnos lo permiten, "
            "el HYROX por la tarde, 4–6 h después.",
            "<b>80/20</b>: casi todo lo que corres es Z2 suave; la intensidad vive en el umbral del sábado. "
            "La Z3 (\"zona gris\") se evita.",
            "<b>En la carrera nada es a tope</b>: se termina \"entero, con ganas de más\". En calistenia, "
            "<b>fallo = fallo técnico</b>: la serie termina cuando la forma se rompe.",
            "<b>Si algo va mal, se recorta en este orden</b>: HYROX del jueves → HYROX del martes. "
            "La calistenia y la carrera no se tocan primero.",
        ], NAVY.hexval().replace("0x", "#"), "#f5f7fa"),
        box("Handstand: todos los días, siempre primero (Alge)", [
            "<b>Calentamiento:</b> entrada en calor (correr o comba) · movilidad articular 20 s por articulación · "
            "retracción-protracción en posición de flexión 2×10 · handstand en pared empujando escápulas y "
            "hombros 10–15 s.",
            "<b>Parte principal:</b> 3–4 aguantes buscando 30–45 s sólidos con buena forma (en tierra, 5–6).",
            "<b>Prevención:</b> bloque de muñecas del PDF siempre. Empuja el suelo, no te hundas. Si vienes "
            "cargado de thrusters o flexiones de pino, menos aguantes y técnica perfecta. En días de carrera, "
            "antes de correr.",
        ], CAL, "#f7f5fd"),
        PageBreak(),
    ]

    # ── Conceptos clave ─────────────────────────────────────────────────────
    story += [
        p("Conceptos clave", "h1"),
        p("Zonas de frecuencia cardiaca (Carlos Rojo, con tu FC máxima de 190)", "h2"),
        table([
            ["Zona", "% FC máx.", "Tus pulsaciones", "Esfuerzo (1–10)", "Para qué en este plan"],
            ["Z1 Recuperación", "menos de 65%", "menos de 124", "1–2", "Calentar, enfriar, trotes entre series"],
            ["<b>Z2 Base aeróbica</b>", "65–80%", "<b>124–152</b> (ideal 135–148)", "3–4",
             "Rodaje del miércoles, largo del domingo, bici"],
            ["Z3 \"Zona gris\"", "80–85%", "152–162", "5–6", "Se evita: cansa sin dar un beneficio claro"],
            ["<b>Z4 Umbral</b>", "86–92%", "<b>163–175</b>", "7–8", "El sábado"],
            ["Z5 VO2 máx.", "más de 92%", "más de 175", "9–10", "No se usa en este bloque"],
        ], [0.2, 0.13, 0.22, 0.13, 0.32]),
        Spacer(1, 4),
        p("El umbral de Carlos Rojo es tu ritmo de 10K más 15–20 s por km: duro pero sostenible cerca de una "
          "hora, solo frases cortas.", "small"),

        p("Qué es el HRV (variabilidad de la frecuencia cardiaca)", "h2"),
        p("El corazón no late como un metrónomo: entre un latido y el siguiente hay pequeñas diferencias de "
          "milisegundos. El HRV mide esa variación. Cuando estás recuperado manda el sistema nervioso del "
          "descanso y la variación es alta. Con estrés, mal sueño, alcohol, una enfermedad que empieza o "
          "entrenamiento que todavía no asimilaste, el cuerpo se pone en modo alerta y la variación baja. "
          "Tu Garmin lo mide cada noche mientras duermes (\"Estado de VFC\") y llega a Intervals.icu."),
        *bullets([
            "<b>Se compara contigo mismo</b>, nunca con otra persona. Tu rango habitual ronda 41–56 ms; "
            "después del HYROX del 13 de octubre bajó a 33–37.",
            "<b>Importa la tendencia</b> (la media de 7 días), no un día suelto.",
        ]),
        table([
            ["Señal en la mañana", "Qué hacer ese día"],
            ["HRV en tu rango, buen sueño", "Entrenas lo planeado."],
            ["Una noche baja, te sientes bien", "Nada: un día suelto no significa nada."],
            ["2–3 días por debajo de tu rango, o FC en reposo +5 ppm, o mal sueño",
             "Umbral del sábado en la parte baja (163–168) o un bloque menos; HYROX ligero."],
            ["Bajo varios días + molestias que cambian de sitio + poca motivación",
             "Semana de descarga: HYROX fuera, calistenia sin fallo, solo carrera en Z2. Avísame."],
        ], [0.45, 0.55]),

        p("RIR, fallo y fallo técnico", "h2"),
        *bullets([
            "<b>RIR (repeticiones en reserva)</b>: cuántas te quedaban. RIR 2 = podrías hacer 2 más con buena "
            "técnica. RIR 0 = no sale otra limpia.",
            "<b>Fallo técnico</b>: la serie termina cuando la forma se rompe (codos que se abren, cadera que "
            "cae, balanceo). No se pelea la repetición con mala técnica: ahí es donde se lesionan codo y hombro.",
            "<b>Esfuerzo percibido (1–10)</b>: 3–4 conversas sin problema; 7–8 solo frases cortas; 10 es todo.",
        ]),

        p("La cinta en el barco", "h2"),
        *bullets([
            "Inclinación al <b>1%</b>: simula la resistencia del aire en la calle.",
            "<b>Clip de seguridad</b> siempre. Con mar movida, baja 0.5 km/h en lo rápido y quita las rectas.",
            "Al guardar la actividad en el reloj, <b>calibra con la distancia que marca la cinta</b>.",
        ]),
        PageBreak(),
    ]

    # ── Lunes ───────────────────────────────────────────────────────────────
    story += day_header("LUNES", "Handstand → Tirón → Pierna para correr", [CALISTENIA, PIERNA])
    story += [
        p("<b>Por qué este día.</b> La fuerza de pierna queda lo más lejos posible de las dos sesiones clave de "
          "carrera: 5 días antes del umbral y 6 antes del largo. El tirón no comparte músculos con la pierna, "
          "así que se pueden hacer el mismo día sin estorbarse. El HYROX no va el lunes: sumado a la pierna, "
          "sería demasiado."),
        p("Tirón (Alge)", "h2"), p(TIRON_CAL, "small"), Spacer(1, 3),
        table(TIRON_ROWS, CALI_W, head_color=colors.HexColor(CAL)),
        p("Pierna para correr", "h2"),
        p("Los cuatro primeros son los que recomienda Carlos Rojo para transferir a la carrera (según el reel "
          "que compartiste). El resto cubre lo que la carrera y el HYROX más castigan.", "small"),
        Spacer(1, 3),
        table([
            ["Ejercicio", "Series × reps", "Intensidad", "Descanso", "Para qué"],
            ["Hack squat", "3 × 8", "RIR 2–3, bajada en 3 s", "2 min", "Cuádriceps: absorber el impacto"],
            ["Hip thrust", "3 × 10", "RIR 2", "2 min", "Glúteo mayor: el impulso"],
            ["Extensión de cuádriceps", "3 × 12 (la última con pausa de 2 s arriba)", "RIR 2", "90 s",
             "Tendón rotuliano"],
            ["Abductores en polea", "3 × 12–15 por pierna", "RIR 2", "60–90 s",
             "Glúteo medio: rodilla alineada, cintilla iliotibial"],
            ["Curl femoral o peso muerto rumano a una pierna", "3 × 8–10", "RIR 2", "90 s",
             "Isquiotibiales: los que se lesionan en las rectas"],
            ["Gemelo de pie + sóleo sentado", "3 × 15 cada uno", "RIR 1–2", "60 s", "Tendón de Aquiles"],
            ["Elevación de tibial", "2 × 15", "Controlado", "45 s", "Espinillas"],
            ["Pallof press o plancha lateral", "2 × 10 / 2 × 30 s por lado", "Controlado", "45 s", "Core"],
        ], [0.24, 0.2, 0.17, 0.1, 0.29], head_color=colors.HexColor(LEG)),
        Spacer(1, 6),
        box("Prevención de lesiones", [
            "<b>Rodilla</b>: nada de fallo en el hack squat. Mañana el HYROX trae 180+ sentadillas y desplantes. "
            "Si una mañana amaneces con molestia bajo la rótula, cambia la extensión por "
            "<b>isométricos de 4–5 × 30–45 s</b>: es lo que se usa en fisioterapia para calmar el tendón.",
            "<b>Codo por dentro</b>: el tirón es la mayor dosis de agarre de la semana. Fallo técnico, sin "
            "pelear repeticiones y sin colgados largos con lastre.",
            "<b>Sin saltos</b> este día: los box jumps del HYROX ya cubren esa parte.",
        ], ALARM.hexval().replace("0x", "#"), "#fef6f5"),
        p("<b>A considerar.</b> Si el largo del domingo te dejó cargado, el hack squat a 2 series.", "small"),
        PageBreak(),
    ]

    # ── Martes ──────────────────────────────────────────────────────────────
    story += day_header("MARTES", "Handstand → Empuje → HYROX (por la tarde si se puede)", [CALISTENIA, HYROX])
    story += [
        p("<b>Por qué este día.</b> Tu HYROX carga sobre todo <b>pierna y empuje</b> (thrusters por encima de la "
          "cabeza, burpees) y casi nada de tirón. Por eso va <b>detrás del empuje</b>: haces la sesión de Alge "
          "fresca, el HYROX suma ese mismo día y la siguiente sesión de empuje llega 48 h después. Si fuera "
          "antes de un día de empuje, llegarías a tus flexiones de pino con los hombros cansados."),
        p("Empuje (Alge)", "h2"), p(EMPUJE_CAL, "small"), Spacer(1, 3),
        table(EMPUJE_ROWS, CALI_W, head_color=colors.HexColor(CAL)),
        p("HYROX (TrainingPeaks)", "h2"),
        p("<b>Ejemplo de la semana (13 oct):</b> Bloque 1, 3 rondas: 200 m de carrera, 20 thrusters, 20 "
          "desplantes alternos; 1 min de descanso. Bloque 2, 3 rondas: 250 m de remo, 20 burpees, 20 "
          "sentadillas con mancuerna. Suma: 60 thrusters, 60 desplantes, 60 sentadillas y 60 burpees.", "small"),
        Spacer(1, 3),
        table([
            ["Qué", "Cómo"],
            ["Progresión", "Semanas 1–2: unos 2/3 del volumen (2 rondas en vez de 3). Después, como mucho "
                           "+1 ronda o +10–15% por semana."],
            ["Ritmo", "Sostenible, no a muerte. Si la técnica se rompe, pausa de 20–30 s antes de seguir."],
            ["Thrusters", "Rodillas en dirección de la punta del pie, codos altos en la sentadilla, bloquear "
                          "arriba sin arquear la zona lumbar."],
            ["Desplantes", "Paso largo, rodilla de adelante sobre el pie, sin golpear el suelo con la de atrás."],
            ["Burpees", "Manos bajo los hombros, bajar controlado; no caer de golpe sobre las muñecas."],
            ["Sentadilla con mancuerna", "Talones apoyados, pecho arriba."],
        ], [0.22, 0.78], head_color=colors.HexColor(HYR)),
        Spacer(1, 6),
        box("Prevención de lesiones", [
            "<b>Rodilla (tendón rotuliano), riesgo número uno</b>: 180+ repeticiones de sentadilla y desplante, "
            "24 h después de la pierna.",
            "<b>Hombro</b>: hoy suma flexiones de pino + 60 thrusters + 60 burpees. Si el hombro avisa (dolor "
            "de más de 3/10, o peor al día siguiente), <b>primero se aligeran los thrusters</b>, no la calistenia.",
            "<b>Codo por detrás</b>: en las flexiones de pino profundas, bajada controlada de 2–4 s, sin rebote "
            "y con bloqueo suave.",
            "<b>Muñecas</b>: burpees después de una sesión de empuje; calentamiento de muñecas sin saltárselo.",
        ], ALARM.hexval().replace("0x", "#"), "#fef6f5"),
        p("<b>A considerar.</b> Come con carbohidratos 2–3 h antes del HYROX. Si los turnos lo permiten, deja "
          "4–6 h entre la calistenia y el HYROX.", "small"),
        PageBreak(),
    ]

    # ── Miercoles ───────────────────────────────────────────────────────────
    story += day_header("MIÉRCOLES", "Handstand → Tirón → Rodaje Z2 + rectas", [CALISTENIA, CARRERA])
    story += [
        p("<b>Por qué este día.</b> Para Carlos Rojo el rodaje suave es el protagonista de la semana: construye "
          "la base aeróbica y, 24 h después del HYROX, funciona como recuperación activa. El tirón llega "
          "fresco porque tu HYROX casi no tira. La carrera va después del tirón: la calistenia es la prioridad."),
        p("Tirón (Alge): igual que el lunes", "h2"),
        table(TIRON_ROWS, CALI_W, head_color=colors.HexColor(CAL)),
        p("Rodaje Z2 + rectas", "h2"),
        table([
            ["Bloque", "Duración", "Intensidad"],
            ["Rodaje", "40–45 min (ver calendario)",
             "Z2: 124–152 ppm, ideal 135–148. Tienes que poder conversar. Sin objetivo de ritmo: si la FC "
             "sube, baja 0.3 km/h."],
            ["Rectas", "4 × 20 s, con 60 s de trote suave", "Progresivas, cuidando la técnica; nunca a tope."],
        ], [0.15, 0.3, 0.55], head_color=colors.HexColor(RUN)),
        Spacer(1, 6),
        box("Prevención de lesiones", [
            "<b>Aquiles y espinillas</b>: son kilómetros nuevos. Rigidez en el Aquiles al levantarte o dolor "
            "difuso en la cara interna de la tibia → aplica el semáforo de dolor.",
            "<b>Isquiotibiales</b>: rectas progresivas, nunca a máxima velocidad.",
            "Si tienes agujetas del HYROX, rectas suaves o fuera.",
        ], ALARM.hexval().replace("0x", "#"), "#fef6f5"),
        Spacer(1, 4),
    ]

    # ── Jueves ──────────────────────────────────────────────────────────────
    story += day_header("JUEVES", "Handstand → Empuje → HYROX (por la tarde si se puede)", [CALISTENIA, HYROX])
    story += [
        p("<b>Por qué este día.</b> Mismo razonamiento que el martes: el HYROX detrás del empuje, y la siguiente "
          "sesión de empuje (el ½ empuje del sábado) llega 48 h después. Es el segundo HYROX de la semana y "
          "queda a 48 h del umbral: por eso se adapta lo que más castiga las piernas."),
        p("<b>Empuje (Alge):</b> igual que el martes.", "body"),
        p("<b>HYROX, ejemplo de la semana (15 oct):</b> 3 rondas de 400 m de remo, 20 burpees, 20 thrusters, "
          "20 box jumps y 20 desplantes.", "body"),
        box("Adaptaciones del jueves", [
            "<b>Box jumps → subidas al cajón (step-ups)</b>, o bajar del cajón caminando. El rebote es lo que más "
            "carga el tendón de Aquiles y lo que más agujetas deja para el sábado.",
            "Desplantes controlados, sin prisa.",
            "<b>Esta semana (15 oct): 2 rondas</b>, para llegar fresco al test del sábado 17.",
            "Si dos sábados seguidos el umbral sale mal, el jueves pasa a ligero (2 rondas, sin saltos) hasta "
            "la carrera.",
        ], HYR, "#fff6f2"),
        p("<b>Prevención:</b> la misma del martes (rodilla, hombro, codo por detrás, muñecas).", "small"),
        PageBreak(),
    ]

    # ── Viernes ─────────────────────────────────────────────────────────────
    story += day_header("VIERNES", "Descanso activo (~50–60 min)", [RECUP])
    story += [
        p("<b>Por qué este día.</b> Recuperar del HYROX del jueves, llegar fresco al umbral del sábado y avanzar "
          "en lo que más necesita tu calistenia: movilidad. Regla: <b>nada que te canse</b>. Si al terminar "
          "estás más fresco que al empezar, lo hiciste bien."),
        table([
            ["Bloque", "Tiempo", "Qué", "Por qué"],
            ["1. Handstand técnico", "10–15 min", "3–4 aguantes buscando la línea, sin llegar al fallo",
             "Práctica de calidad, sin nada que compita"],
            ["2. Cardio muy suave (opcional)", "30–35 min",
             "Bici con FC por debajo de ~140, o caminar en la cinta con algo de inclinación",
             "Recuperar del HYROX sin impacto. Si vienes cargado, sáltatelo"],
            ["3. Movilidad dirigida", "20 min",
             "Tobillo: rodilla a la pared 2×10 por lado · Cadera: 90/90 y estiramiento de flexor (couch stretch) "
             "2×45 s · Torácica: open books y extensión sobre rodillo · Hombro: dislocaciones con banda 2×10 · "
             "Muñecas: bloque del PDF",
             "Lo que acortan la cinta y la sentadilla, y lo que abre tu línea de handstand"],
            ["4. Prevención hombro y codo", "10 min", "La rutina de abajo",
             "Protocolo mínimo del libro de lesiones (2–3 días por semana)"],
            ["5. Pie y equilibrio", "5–10 min",
             "Short foot (encoger el arco) · equilibrio a una pierna 3×30 s, luego con ojos cerrados",
             "Propiocepción: el barco en movimiento lo hace más difícil gratis"],
            ["6. Soltar", "5–10 min",
             "Foam roller en cuádriceps, gemelo, glúteo y dorsal · respiración: inhalar 4 s, exhalar 6–8 s",
             "Bajar revoluciones para dormir mejor; se nota en el HRV"],
        ], [0.2, 0.11, 0.4, 0.29], head_color=colors.HexColor(REC)),
        p("Rutina de prevención de hombro y codo", "h2"),
        table(PREVENCION_R16, [0.4, 0.15, 0.45], head_color=colors.HexColor(REC)),
        Spacer(1, 6),
        box("También el viernes", [
            "<b>Revisa tu HRV en la mañana</b> (ver Conceptos clave): decide cómo será el umbral del sábado.",
            "<b>Cena con buenos carbohidratos</b> (arroz, pasta, papa), sin pasarte: mañana es tu día de calidad.",
            "<b>Duerme 7–9 h.</b>",
            "<b>Qué no hacer:</b> fuerza al fallo, HYROX, intervalos ni estiramientos forzados.",
        ], REC, "#f3faf5"),
        PageBreak(),
    ]

    # ── Sabado ──────────────────────────────────────────────────────────────
    story += day_header("SÁBADO", "Handstand → Umbral → ½ empuje + core + prevención + movilidad",
                        [CALISTENIA, CARRERA])
    story += [
        p("<b>Por qué este día.</b> El umbral es el entrenamiento estrella de Carlos Rojo: es lo que te deja "
          "sostener un ritmo alto durante más tiempo, que es justo lo que pide un 10K. Llega 5 días después de "
          "la pierna y 48 h después del HYROX. Lo que va después no cansa las piernas: mañana es el largo."),
        p("Umbral: la sesión de cada semana", "h2"),
        table([
            ["Fecha", "Sesión principal", "A umbral", "Pinceladas a ritmo 10K"],
            ["17 oct", "<b>Test de 30 min</b> (ver abajo)", "—", "—"],
            ["24 oct", "2 × 10 min, 2 min de trote entre bloques", "20 min", "—"],
            ["31 oct", "3 × 8 min, 2 min de trote", "24 min", "—"],
            ["7 nov", "2 × 15 min, 3 min de trote", "30 min", "3 × 2 min, 2 min de trote"],
            ["14 nov", "Progresivo 12-9-6-3 min (2 min de trote): 12 y 9 a umbral, 6 y 3 a ritmo de 10K",
             "21 min", "9 min"],
            ["21 nov", "Soltar piernas: 15 min suave + 3 rectas", "—", "—"],
        ], [0.11, 0.53, 0.12, 0.24], head_color=colors.HexColor(RUN)),
        Spacer(1, 4),
        p("Toda sesión de calidad: <b>15 min de calentamiento muy suave</b> antes y <b>10 min de enfriamiento</b> "
          f"después. Intensidad: 86–92% de la FC máxima (163–175 ppm), esfuerzo 7–8. {VEL}", "small"),
        Spacer(1, 4),
        box("El test del 17 de octubre", [
            "30 min lo más fuerte que puedas sostener <b>parejo</b>: empieza conservador, los últimos 5 min a tope.",
            "Anota la distancia que marca la cinta y calibra el reloj con ella al guardar.",
            "La FC media de los últimos 20 min es tu umbral real. Con la distancia calculo tus velocidades de "
            "umbral y de 10K para todo el bloque.",
        ], RUN, "#f1f9fa"),
        p("Después de correr", "h2"),
        table([
            ["Bloque", "Qué", "Detalle"],
            ["½ empuje (Alge)", "1 serie de cada ejercicio de la sesión de empuje",
             "Tranquilo: deja 1–2 repeticiones en reserva. (Así interpreto \"½ empuje\"; confírmalo con Alge.)"],
            ["Core de calistenia", "Hollow body 3×20–30 s · arch hold 3×20–30 s · compresión o L-sit 3×10–15 s",
             "Ayuda directa al handstand y a los presses; no cansa para el domingo"],
            ["Prevención hombro y codo", "La rutina del viernes", "Segundo día de la semana"],
            ["Movilidad (Alge)", "Hombros: estiramiento en espaldera de rodillas 3×30–45 s, dislocaciones con "
             "banda 3×10, estiramiento sentado con manos atrás 3×30–45 s · Muñecas: 3×30 s en 4 posiciones · "
             "Cadera: balanceos frontales y laterales ×10, mariposa 30–60 s, 3×30 s en 4 posiciones de apertura",
             "Ya estás caliente después de correr"],
            ["½ tirón técnico (opcional)", "Retracciones escapulares colgado y aguantes de front lever al 50–60%",
             "Solo si Alge está de acuerdo. Queda 72 h después del tirón del miércoles y 48 h antes del lunes"],
        ], [0.2, 0.45, 0.35], head_color=colors.HexColor(CAL)),
        Spacer(1, 6),
        box("Prevención de lesiones", [
            "Si las piernas pesan por el HYROX del jueves: umbral en la parte baja (163–168) o un bloque menos.",
            "<b>Isquiotibiales</b>: las pinceladas a ritmo de 10K no son sprints.",
            "<b>Nada de pierna, HYROX ni series al fallo</b>: mañana es el largo.",
        ], ALARM.hexval().replace("0x", "#"), "#fef6f5"),
        PageBreak(),
    ]

    # ── Domingo ─────────────────────────────────────────────────────────────
    story += day_header("DOMINGO", "Rodaje largo Z2 (handstand opcional, o caminar)", [CARRERA])
    story += [
        p("<b>Por qué este día.</b> Carlos Rojo pide un \"rodaje largo verdadero\": 60–90 min suaves que "
          "construyen la base aeróbica. Como es de baja intensidad, el lunes llegas bien a la pierna. Era tu "
          "día de descanso en el plan de Alge (handstand o caminar): el largo en Z2 es recuperación activa."),
        table([
            ["Fecha", "18 oct", "25 oct", "1 nov", "8 nov", "15 nov", "22 nov"],
            ["Duración", "60 min", "65 min", "70 min", "80 min", "65 min", "<b>10K</b>"],
        ], [0.16] + [0.14] * 6, head_color=colors.HexColor(RUN), zebra=False),
        Spacer(1, 6),
        *bullets([
            "<b>Z2 de verdad</b>: nada de acelerar al final.",
            "La FC tiende a subir con el tiempo y con el calor del barco: <b>si pasa de 152, baja la cinta</b>, "
            "aunque el ritmo se vaya.",
            "Hidratación cada 20 min; con más de 60 min o calor, agua con electrolitos.",
        ]),
        Spacer(1, 10),
    ]

    # ── Bloque completo ─────────────────────────────────────────────────────
    story += [
        p("El bloque de carrera completo", "h1"),
        table([
            ["Semana", "Mié: rodaje", "Vie: bici (opc.)", "Sáb: calidad", "Dom: largo", "km aprox."],
            ["15–18 oct", "— (HYROX del jue a 2 rondas)", "30 min", "Test 30 min", "60 min", "—"],
            ["19–25 oct", "40 min + rectas", "35 min", "Umbral 2×10", "65 min", "~22"],
            ["26 oct – 1 nov", "40 min + rectas", "35 min", "Umbral 3×8", "70 min", "~24"],
            ["2–8 nov", "45 min + rectas", "35 min", "Umbral 2×15 + 3×2", "80 min", "~26"],
            ["9–15 nov", "40 min + rectas", "35 min", "Progresivo 12-9-6-3", "65 min", "~22"],
            ["16–22 nov", "30 min (+ activación el jueves)", "—", "Soltar 15 min", "<b>10K</b>", "—"],
        ], [0.15, 0.24, 0.14, 0.19, 0.13, 0.15], head_color=colors.HexColor(RUN)),
        p("Semana de carrera (16–22 nov)", "h2"),
        table([
            ["Día", "Qué cambia"],
            ["Lun 16", "Pierna ligera: hack squat y extensión suaves, sin fallo; gemelo y tibial normal."],
            ["Mar 17", "HYROX suave: 2 rondas y sin saltos."],
            ["Mié 18", "Rodaje de 30 min en Z2, sin rectas."],
            ["Jue 19", "Sin HYROX. Activación: 15 min Z2 + 3 × 2 min a ritmo de carrera + 5 min suave. "
                       "Empuje a la mitad."],
            ["Vie 20", "Descanso."],
            ["Sáb 21", "Soltar piernas: 15 min suave + 3 rectas. Sin full body; handstand si quieres."],
            ["Dom 22", "<b>10K.</b> Calienta 15 min muy suave + 3 rectas. Km 1–2 un poco por debajo del ritmo "
                       "objetivo, km 3–8 parejo, km 9–10 todo lo que quede. Nada nuevo ese día: comida, "
                       "tenis ni ropa."],
        ], [0.12, 0.88], head_color=colors.HexColor(RUN)),
        PageBreak(),
    ]

    # ── Prevencion de lesiones ──────────────────────────────────────────────
    story += [
        p("Prevención de lesiones", "h1"),
        p("El riesgo más alto está en las <b>primeras 2–3 semanas</b>, porque entran tres cargas nuevas a la vez: "
          "el HYROX, la pierna para correr y más kilómetros (de ~19 a ~26 por semana). Los tendones se adaptan "
          "más despacio que el músculo y el corazón, así que pueden avisar tarde."),
        table([
            ["Zona", "De dónde vendría", "Primera señal", "Cómo la cuidamos"],
            ["<b>Rodilla (tendón rotuliano)</b>: riesgo número uno",
             "180–240 sentadillas y desplantes por HYROX, pegados al lunes",
             "Molestia bajo la rótula al bajar escaleras o al empezar a correr",
             "Lunes sin fallo en hack squat; extensión de cuádriceps (o isométricos si molesta); desplantes "
             "controlados"],
            ["<b>Aquiles / gemelo-sóleo</b>", "Box jumps, burpees, kilómetros nuevos",
             "Rigidez en el Aquiles al levantarte", "Gemelo y sóleo el lunes; subidas al cajón los jueves"],
            ["<b>Tibia</b> (periostitis, fractura por estrés)", "Subir km rápido, saltos sobre acero",
             "Dolor difuso en la cara interna de la tibia. <b>Dolor en un punto = alarma</b>",
             "Los km suben poco cada semana; saltos sobre colchoneta"],
            ["<b>Isquiotibiales</b>", "Rectas y pinceladas con piernas cansadas", "Tirón detrás del muslo",
             "Rectas progresivas, nunca a tope; curl femoral los lunes"],
            ["<b>Zona lumbar</b>", "Thrusters, desplantes y remo con mala técnica por fatiga",
             "Dolor lumbar al día siguiente", "Si la técnica se rompe en el HYROX, pausa"],
            ["<b>Hombro</b>", "Handstand diario + flexiones de pino + thrusters + burpees",
             "Dolor en el handstand o al empujar por encima de la cabeza",
             "Primero se aligeran los thrusters; prevención 2–3 días por semana"],
            ["<b>Codo por dentro</b>", "Dosis de agarre: tirón + colgados + series al fallo",
             "Dolor en la cara interna del codo al traccionar",
             "Fallo técnico sin pelear repeticiones; sin colgados largos con lastre; flexores de antebrazo"],
            ["<b>Codo por detrás</b>", "Flexiones profundas con bajada rápida o rebote",
             "Dolor detrás del codo", "Bajada de 2–4 s, sin rebote, bloqueo suave"],
            ["<b>Muñecas</b>", "Handstand, lean planche, burpees", "Dolor al cargar con la muñeca doblada",
             "Calentamiento de muñecas del PDF, siempre"],
        ], [0.19, 0.25, 0.25, 0.31], head_color=ALARM),
        Spacer(1, 8),
        p("Semáforo de dolor", "h2"),
        table([
            ["Color", "Cuándo", "Qué hacer"],
            ['<font color="#2f8a4c"><b>Verde</b></font>',
             "Dolor de 0–3/10 durante, la técnica no empeora y al día siguiente estás igual o mejor",
             "Sigues normal."],
            ['<font color="#b54708"><b>Amarillo</b></font>', "Dolor de 4–5/10, o peor a la mañana siguiente",
             "Bajas la carga de esa zona esa semana y repites."],
            ['<font color="#b42318"><b>Rojo</b></font>',
             "Dolor de 6/10 o más, dolor que sube durante la sesión, o la técnica empeora",
             "Paras esa zona."],
        ], [0.13, 0.55, 0.32]),
        Spacer(1, 4),
        p("<b>Orden del ajuste</b> cuando algo molesta: 1) recortar el rango más agresivo → 2) bajar el volumen → "
          "3) bajar la intensidad. <b>Qué se recorta primero en la semana:</b> HYROX del jueves → HYROX del "
          "martes. La calistenia y la carrera, nunca primero.", "small"),
        Spacer(1, 6),
        box("Señales de alarma: para y ve con un médico o fisio", [
            "Dolor de noche que te despierta.",
            "Dolor en un punto concreto de un hueso (tibia, pie) que duele al apretarlo.",
            "Pérdida brusca de rango o de fuerza, o sensación de inestabilidad.",
            "Hormigueo o entumecimiento; un chasquido doloroso; hinchazón marcada.",
            "Dolor que sigue subiendo aunque bajes la carga.",
        ], ALARM.hexval().replace("0x", "#"), "#fef6f5"),
        PageBreak(),
    ]

    # ── Recuperacion y fuentes ──────────────────────────────────────────────
    story += [
        p("Recuperación", "h1"),
        *bullets([
            "<b>Sueño de 7–9 h.</b> Carlos Rojo lo pone entre lo primero para bajar la frecuencia cardiaca.",
            "<b>Comer suficiente.</b> Con esta carga, comer en déficit sube mucho el riesgo de fracturas por "
            "estrés y de lesiones de tendón. Carbohidratos los días duros y en la cena del viernes. "
            "Regístralo en Skandi.",
            "<b>Hidratación</b>, sobre todo con el calor del barco: agua con electrolitos en los largos y en el HYROX.",
            "<b>El HRV como guía</b>: la tabla de la página de Conceptos clave decide cuándo bajar.",
        ]),
        Spacer(1, 6),
        box("En el barco", [
            "Cinta: clip de seguridad y sin rectas con mucho oleaje.",
            "HYROX con el piso en movimiento: más cuidado en desplantes y thrusters; es fácil torcerse un tobillo.",
            "Los saltos sobre acero impactan más: colchoneta.",
            "Calor: hidratación y electrolitos.",
        ], WARN.hexval().replace("0x", "#"), "#fffaf2"),
        Spacer(1, 10),
        p("Fuentes", "h1"),
        *bullets([
            "Algecalistenia, <i>Joseph Planificación (M1)</i>: calistenia, handstand y movilidad.",
            "Carlos Rojo Running: carlosrojorunning.com (zona 2, resistencia, frecuencia cardiaca, técnica de "
            "carrera) y @carlosrojo_running (umbral láctico, sesiones de 10K, ejercicios de pierna para corredores).",
            "Torino y Carrillo (2026), <i>Lesiones de hombro y codo en streetlifting</i>: semáforo de dolor, "
            "señales de alarma, orden del ajuste y rutina mínima de prevención.",
            "HYROX: tu programación de TrainingPeaks.",
            "Tus datos de Garmin en Intervals.icu: FC máxima 190, umbral 172, HRV.",
        ], "bullet"),
        Spacer(1, 10),
        p("Este plan es orientación de entrenamiento, no un diagnóstico médico. Si una molestia no mejora en una "
          "semana bajando la carga, consulta con un fisioterapeuta.", "muted"),
    ]

    doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm,
                            topMargin=15 * mm, bottomMargin=17 * mm,
                            title="Plan semanal a bordo", author="Joseph Pelayo")
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print(f"{OUT.name}")


if __name__ == "__main__":
    build()
