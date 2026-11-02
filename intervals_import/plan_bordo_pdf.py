#!/usr/bin/env python3
"""PDF de las tres semanas a bordo (19 oct - 8 nov 2026), dia por dia: entreno y comidas.

    python3 plan_bordo_pdf.py      # escribe Plan_a_Bordo_3_Semanas_Joseph.pdf

Semana final del 18 oct: los planes de Alge (M1) y de Carlos (Running Master) cada uno en sus dias,
sin HYROX fijo. La pierna de calistenia de Alge se hace en gym para correr, en dos mitades:
  lun HS + empuje + cadera + core        | mar HS + tiron + accesorios + Z1 + gemelo
  mie HS + empuje + hombro sano (o HYROX) | jue HS + Z1 + cuadriceps y pantorrilla
  vie HS + tiron + accesorios, sin pierna | sab HS + calidad + 1/2 empuje
  dom largo Z1
El HYROX cambia cada semana: va de preferencia el miercoles detras del empuje, mas tranquilo de lo
normal, y nunca de jueves a domingo. Prioridad del momento: velocidad y condicion, y calistenia.
Horario real: despierta 8:40 (preentreno: 2 datiles + 2 nueces + chocolate 95%), entrena 9:00-11:30,
come a las 11:30, 17:30 y 00:00 y duerme a la 1:00. El whey va en el yogur de las 00:00.
La regla de la manana son tres preguntas: en el barco el reloj no mide bien el sueno.
La carrera la sube a Intervals.icu plan_carlos_rm_oct2026.py; aqui va todo lo demas.
Carbohidratos en bloques de 25 g; las comidas usan las opciones del plan de Carlos y se repiten
cada semana, como pide Isma. Accesorios tomados del Plan Hibrido 4 Dias v3.
Correr sin `python3 -I`: reportlab esta en los paquetes del usuario.
"""

from datetime import date, timedelta
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer,
                                Table, TableStyle)

OUT = Path(__file__).with_name("Plan_a_Bordo_3_Semanas_Joseph.pdf")
WEEK1 = date(2026, 10, 19)

FONTS = "/System/Library/Fonts/Supplemental"
pdfmetrics.registerFont(TTFont("Arial", f"{FONTS}/Arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Bold", f"{FONTS}/Arial Bold.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Italic", f"{FONTS}/Arial Italic.ttf"))
pdfmetrics.registerFontFamily("Arial", normal="Arial", bold="Arial-Bold", italic="Arial-Italic")

NAVY = colors.HexColor("#14395a")
INK = colors.HexColor("#1f2933")
MUTED = colors.HexColor("#5b6670")
LINE = colors.HexColor("#d5dbe1")
SOFT = colors.HexColor("#f3f5f8")
CAL = "#5b43c9"     # calistenia
RUN = "#0a7a74"     # carrera y bici
HYR = "#c4460d"     # HYROX
LEG = "#2858c8"     # pierna en gym
REC = "#3a7a4e"     # core, movilidad
FOOD = "#94650f"    # comida
GREY = "#5b6670"
ALTO, MEDIO = HYR, RUN

W = A4[0] - 32 * mm

S = {
    "title": ParagraphStyle("title", fontName="Arial-Bold", fontSize=28, leading=32, textColor=NAVY),
    "sub": ParagraphStyle("sub", fontName="Arial", fontSize=12, leading=16, textColor=INK),
    "part": ParagraphStyle("part", fontName="Arial-Bold", fontSize=9, leading=12, textColor=MUTED),
    "h1": ParagraphStyle("h1", fontName="Arial-Bold", fontSize=16, leading=20, textColor=NAVY,
                         spaceBefore=4, spaceAfter=6),
    "h2": ParagraphStyle("h2", fontName="Arial-Bold", fontSize=11.5, leading=15, textColor=NAVY,
                         spaceBefore=9, spaceAfter=4),
    "body": ParagraphStyle("body", fontName="Arial", fontSize=9.5, leading=13.2, textColor=INK, spaceAfter=3),
    "small": ParagraphStyle("small", fontName="Arial", fontSize=8.6, leading=11.4, textColor=INK),
    "th": ParagraphStyle("th", fontName="Arial-Bold", fontSize=8.4, leading=11, textColor=colors.white),
    "muted": ParagraphStyle("muted", fontName="Arial", fontSize=8.2, leading=11, textColor=MUTED),
    "bullet": ParagraphStyle("bullet", fontName="Arial", fontSize=9.5, leading=13.2, textColor=INK,
                             leftIndent=11, bulletIndent=1, spaceAfter=2),
    "sbullet": ParagraphStyle("sbullet", fontName="Arial", fontSize=8.8, leading=12, textColor=INK,
                              leftIndent=11, bulletIndent=1, spaceAfter=1.5),
    "day": ParagraphStyle("day", fontName="Arial-Bold", fontSize=18, leading=22, textColor=colors.white),
    "dayr": ParagraphStyle("dayr", fontName="Arial", fontSize=9.3, leading=13.2, textColor=colors.white),
    "cell": ParagraphStyle("cell", fontName="Arial", fontSize=8.2, leading=10.6, textColor=INK, alignment=1),
}


def p(text, style="body"):
    return Paragraph(text, S[style])


def bullets(items, style="bullet"):
    return [Paragraph(t, S[style], bulletText="•") for t in items if t]


def chip(label, color):
    return f'<font backColor="{color}" color="white">&nbsp;{label}&nbsp;</font>'


def colored(text, color):
    return f'<font color="{color}"><b>{text}</b></font>'


def table(rows, widths, head_color=NAVY, font="small"):
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
    style += [("BACKGROUND", (0, r), (-1, r), SOFT) for r in range(2, len(rows), 2)]
    t.setStyle(TableStyle(style))
    return t


def hc(color):
    return colors.HexColor(color)


def box(title, items, color, bg="#ffffff"):
    inner = [Paragraph(f'<font color="{color}"><b>{title}</b></font>', S["body"])] + bullets(items)
    t = Table([[inner]], colWidths=[W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), hc(bg)),
        ("LINEBEFORE", (0, 0), (0, -1), 3, hc(color)),
        ("LEFTPADDING", (0, 0), (-1, -1), 9), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return KeepTogether([t, Spacer(1, 6)])


def day_header(name, right):
    t = Table([[p(name, "day"), p(right, "dayr")]], colWidths=[0.33 * W, 0.67 * W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), NAVY),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 10), ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return [t, Spacer(1, 5)]


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Arial", 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(16 * mm, 10 * mm, "Tres semanas a bordo · Joseph Pelayo · 19 de octubre al 8 de noviembre de 2026")
    canvas.drawRightString(A4[0] - 16 * mm, 10 * mm, f"{doc.page}")
    canvas.restoreState()


CALI = chip("Calistenia (Alge)", CAL)
CARRERA = chip("Carrera (Carlos)", RUN)
BICI = chip("Bici", RUN)
HYROX = chip("HYROX", HYR)
PIERNA = chip("Pierna en gym", LEG)
RECUP = chip("Core y movilidad", REC)

DIA = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
MES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]


def hm(minutes):
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def dur(minutes):
    if minutes < 60:
        return f"{minutes} min"
    return f"{minutes // 60} h {minutes % 60:02d}" if minutes % 60 else f"{minutes // 60} h"


# ── Lo que cambia de semana a semana ────────────────────────────────────────

WEEKS = [
    {"z1": 40, "long": 60, "rir": 3, "q_title": "3 × 2000 m en Z2", "q_min": 58,
     "q": "15 min en Z1 (10.0–10.3 km/h) · <b>3 × 2000 m en Z2</b> a 12.4–12.6 km/h (≈9:35 cada uno), "
          "pausa de 2 min caminando · 10 min en Z1"},
    {"z1": 45, "long": 65, "rir": 2, "q_title": "2 × 3000 m en Z2", "q_min": 56,
     "q": "15 min en Z1 (10.0–10.3 km/h) · <b>2 × 3000 m en Z2</b> a 12.4–12.6 km/h (≈14:20 cada uno), "
          "pausa de 2:30 caminando · 10 min en Z1"},
    {"z1": 45, "long": 70, "rir": 2, "q_title": "6000 m Z2 + 1000 m Z3", "q_min": 61,
     "q": "15 min en Z1 (10.0–10.3 km/h) · <b>6000 m en Z2</b> a 12.4–12.6 km/h (≈28:45) · pausa de 3 min "
          "caminando · <b>1000 m en Z3</b> a 13.3–13.6 km/h (≈4:28) · 10 min en Z1"},
]

# ── Sesiones fijas, en corto para las paginas de cada dia ───────────────────

HS = ("Entrada en calor 5 min (comba o bici) · movilidad 20 s por articulación · retracción-protracción en "
      "flexión 2×10 · handstand en pared empujando escápulas 10–15 s{extra}. <b>Handstand:</b> 3–4 aguantes "
      "de 30–45 s sólidos.")
HS_PULL = " · antes del tirón: 8 flexiones, retracciones escapulares colgado y alguna dominada"
HS_PUSH = " · antes del empuje: flexiones normales y de pica, y peso en las muñecas"
TIRON = ("Aguante de front lever 1 al 80% · front press + negativa + aguante 2 al fallo · half press + negativa "
         "2 al fallo · touch tuck advanced 2×6–8 (goma si hace falta) · dominadas tuck advanced de front 2×6. "
         "Descanso 3–4 min.")
EMPUJE = ("Pino libre 3–4 intentos · aguante de 90° 2 al fallo técnico · subida a pino por fuerza 2 al fallo · "
          "flexiones de pino profundas en pared, en paralelas, 2 a RIR 0 · lean planche 2×6. Descanso 3–4 min.")
MEDIO_EMPUJE = ("Pino libre 2 intentos y 1 serie de cada ejercicio del empuje (90°, subida a pino, pino profundas, "
                "lean planche 1×6). Descanso 3 min.")
CADERA = "<b>RIR {rir}</b>, descanso 2 min · hip thrust 3×8–10 · peso muerto rumano 2×6–8 · curl femoral 2×10–12."
CUADS = ("<b>RIR {rir}</b>, descanso 2 min · hack squat 3×5–6 (o sentadilla búlgara 3×8 por pierna) · extensión de "
         "cuádriceps 2×12–15 · abductores 2×15 por lado · gemelo de pie 2×12–15 · sóleo sentado 2×15–20.")
ACC_TIRON_MAR = "RIR 1 · remo con pecho apoyado o en máquina 2×8–12 · curl de bíceps 2×8–12 · face pull 2×12–15."
ACC_TIRON_VIE = "RIR 1 · jalón unilateral 2×8–12 · curl martillo 2×10–14 · Y en banda o face pull 2×12–20."
ACC_HOMBRO = ("RIR 1 · elevaciones laterales 3×12–15 · rotación externa con banda 2×15–20 · flexores y extensores "
              "de antebrazo 2×15–20.")
GEMELO = ("Elevación de talón a una pierna: 2×15 con la rodilla estirada y 2×15 con la rodilla flexionada. Sube "
          "en 1 s, baja en 3 s.")
CORE = "Rutina de core de la academia de Carlos (Skool)."
MOVILIDAD = ("Hombros 3×30–45 s, 3×10 con palo y 3×30–45 s · muñecas 3×30 s · cadera: balanceos 10 + 10, mariposa "
             "30–60 s, apertura 3×30 s · y la rutina de movilidad de Carlos.")
WAKE = ("Preentreno: tu combo de dátiles, nueces y chocolate{extra} (detalle en las comidas). Café si lo quieres; "
        "el último antes de las 17:00.")
HYROX_AQUI = ("Si esta semana hay HYROX, va aquí, en lugar de los accesorios: más tranquilo de lo normal, a "
              "esfuerzo 6–7 de 10 y como mucho 20–25 min. Ese día pasa a combustible alto.")


# ── Comidas: tres al dia y el preentreno, las mismas cada semana ────────────

MEALS_W = [0.09, 0.17, 0.12, 0.10, 0.52]
MEALS_HEAD = ["Hora", "Toma", "Carbos", "Proteína", "Qué comer"]
PRE_SEMANA = ["08:40", "Preentreno", 1.5, "—",
              "Tu combo de siempre: 2 dátiles medjool + 2 nueces + un poquito de chocolate 95%. Si los dátiles son "
              "chicos, 4 o 5. Café si lo quieres para entrenar."]
PRE_FINDE = ["08:40", "Preentreno", 2.5, "—",
             "Tu combo (2 dátiles medjool + 2 nueces + chocolate 95%) + 1 plátano. Café si lo quieres: antes de "
             "correr fuerte ayuda."]
WHEY_POST = " Al terminar de entrenar, 1 scoop de whey en agua: hoy lo de las 00:00 no lleva yogur."

MEALS = {
    0: [  # lunes: empuje + cadera
        PRE_SEMANA,
        ["11:30", "Comida 1", 5, "45 g", "<b>Carlos opción 2 + 1 fruta:</b> 160 g de res magra + 330 g de papa cocida + "
         "verduras salteadas + 12 g de aceite + 60 g de tortillas + 1 fruta. Creatina."],
        ["17:30", "Comida 2", 4, "45 g", "<b>Carlos opción 1:</b> 180 g de salmón + 270 g de arroz cocido + espinacas + "
         "10 g de aceite + 150 g de piña. Omega-3."],
        ["00:00", "Comida 3", 3, "50 g", "250 g de yogur griego con 1 scoop de whey mezclado + 50 g de avena + 1 fruta + "
         "15 g de nueces. Magnesio."],
    ],
    1: [  # martes: tiron + Z1
        PRE_SEMANA,
        ["10:10", "Durante", 1, "—", "Isotónica casera en sorbos durante el Z1."],
        ["11:30", "Comida 1", 5, "45 g", "<b>Carlos opción 4 + 1 fruta:</b> 180 g de lomo de cerdo + 300 g de pasta cocida "
         "+ 120 g de salsa de tomate natural + 140 g de calabacín + 10 g de aceite + 1 fruta. Creatina." + WHEY_POST],
        ["17:30", "Comida 2", 4.5, "45 g", "<b>Carlos opción 2:</b> 180 g de pollo + 140 g de tortillas + 160 g de frijoles "
         "+ 60 g de aguacate + 150 g de tomate. Omega-3."],
        ["00:00", "Comida 3", 3, "30 g", "110 g de huevo + 120 g de claras + 4 tortillas + verdura + 170 g de papaya (su "
         "desayuno 1, sin frijoles ni aguacate). Magnesio."],
    ],
    2: [  # miercoles: empuje + accesorios (o HYROX)
        PRE_SEMANA[:4] + [PRE_SEMANA[4] + " Si hay HYROX, 2 dátiles más."],
        ["11:30", "Comida 1", 4.5, "45 g", "<b>Carlos opción 1:</b> 170 g de pollo + 300 g de arroz cocido + tomate y "
         "lechuga + 15 g de aceite + 160 g de fruta. Creatina. Si hubo HYROX, ½ taza más de arroz." + WHEY_POST],
        ["17:30", "Comida 2", 4, "45 g", "<b>Carlos opción 3:</b> 170 g de res magra + 330 g de camote + lechuga y tomate "
         "+ 15 g de aceite + 160 g de manzana. Omega-3."],
        ["00:00", "Comida 3", 3, "35 g", "100 g de pan de masa madre + 150 g de pollo + tomate + 1 mango chico (su "
         "desayuno 3, sin aguacate). Magnesio."],
    ],
    3: [  # jueves: Z1 + cuadriceps
        PRE_SEMANA[:4] + [PRE_SEMANA[4] + " Corres a las 9:20: alcanza."],
        ["11:30", "Comida 1", 5, "45 g", "<b>Carlos opción 5:</b> 170 g de atún al natural + 300 g de arroz cocido + 150 g "
         "de frijoles + 90 g de aguacate + tomate y lechuga. Creatina." + WHEY_POST],
        ["17:30", "Comida 2", 4, "45 g", "<b>Carlos opción 1:</b> 180 g de salmón + 270 g de arroz cocido + espinacas + "
         "10 g de aceite + 150 g de piña. Omega-3."],
        ["00:00", "Comida 3", 3, "40 g", "110 g de huevo + 100 g de pechuga de pavo + 200 g de papa asada + tomate + 1 "
         "fruta (su desayuno 4, sin pan). Magnesio."],
    ],
    4: [  # viernes: tiron, sin pierna; carga a las 00:00 para la calidad
        PRE_SEMANA,
        ["11:30", "Comida 1", 5, "45 g", "<b>Carlos opción 3:</b> 200 g de pescado blanco + 350 g de camote + 90 g de "
         "tortillas + 80 g de aguacate + ensalada verde. Creatina."],
        ["17:30", "Comida 2", 4.5, "45 g", "<b>Carlos opción 2:</b> 180 g de pollo + 140 g de tortillas + 160 g de frijoles "
         "+ 60 g de aguacate + 150 g de tomate. Omega-3."],
        ["00:00", "Comida 3 · carga", 4, "50 g", "70 g de avena + 250 g de yogur griego con 1 scoop de whey + 1 plátano + "
         "20 g de dátiles. Mañana es la calidad: nada nuevo ni grasoso. Magnesio."],
    ],
    5: [  # sabado: calidad + 1/2 empuje; carga a las 00:00 para el largo
        PRE_FINDE,
        ["09:20", "Durante", 1, "—", "500 ml de isotónica casera en sorbos: en el calentamiento y en las pausas."],
        ["11:30", "Comida 1", 5.5, "45 g", "<b>Carlos opción 1 + 2 tortillas:</b> 170 g de pollo + 300 g de arroz cocido + "
         "tomate y lechuga + 15 g de aceite + 160 g de fruta. Creatina."],
        ["17:30", "Comida 2", 4, "45 g", "<b>Carlos opción 3:</b> 170 g de res magra + 330 g de camote + lechuga y tomate "
         "+ 15 g de aceite + 160 g de manzana. Omega-3."],
        ["00:00", "Comida 3 · carga", 4, "50 g", "El bowl del viernes: 70 g de avena + 250 g de yogur griego con 1 scoop "
         "de whey + 1 plátano + 20 g de dátiles. Mañana es el largo. Magnesio."],
    ],
    6: [  # domingo: largo
        PRE_FINDE,
        ["09:55", "Durante", 1, "—", "A los 40 min del largo: 35 g de dátiles o 500 ml de isotónica casera, sin parar "
         "la cinta."],
        ["11:30", "Comida 1", 5, "45 g", "<b>Domingo flexible de Isma:</b> comida libre consciente, con proteína y unas 2 "
         "tazas de tu carbo favorito. Creatina." + WHEY_POST],
        ["17:30", "Comida 2", 4.5, "45 g", "<b>Carlos opción 4, con menos pasta:</b> 220 g de pescado blanco + 250 g de "
         "pasta cocida + 180 g de verduras + 15 g de aceite + 150 g de fruta. Omega-3."],
        ["00:00", "Comida 3", 3, "30 g", "110 g de huevo + 120 g de claras + 4 tortillas + verdura + 170 g de papaya. "
         "Magnesio. Mañana, empuje y cadera."],
    ],
}
FUEL_EXTRA = {2: "alto si hay HYROX", 4: "carga a las 00:00", 5: "carga a las 00:00"}


def bl(x):
    """1.5 -> '1½ bloques'; 1 -> '1 bloque'; 0 -> '0'."""
    if not x:
        return "0"
    whole, half = int(x), x - int(x) >= 0.5
    num = (str(whole) if whole else "") + ("½" if half else "")
    return f"{num} {'bloque' if x <= 1 else 'bloques'}"


def fuel_line(d):
    alto = d >= 5
    total = sum(m[2] for m in MEALS[d])
    color, label = (ALTO, "alto") if alto else (MEDIO, "medio")
    extra = FUEL_EXTRA.get(d, "")
    return p(f'{colored("Combustible " + label, color)} · ≈{round(total * 25)} g de carbohidratos ({bl(total)})'
             f' · ≈150 g de proteína' + (f" · {extra}" if extra else ""), "small")


def meals_table(d):
    return table([MEALS_HEAD] + [[t, toma, bl(b), prot, txt] for t, toma, b, prot, txt in MEALS[d]],
                 MEALS_W, head_color=hc(FOOD))


# ── Una pagina por dia ──────────────────────────────────────────────────────

def day_content(w, d):
    """Devuelve (enfoque, chips, filas del entreno, notas del dia) para la semana w (0-2) y el dia d (0-6)."""
    wk = WEEKS[w]
    n = w + 1
    rir = wk["rir"]
    z1 = wk["z1"]
    rows = [("08:40", "Despiertas", FOOD, WAKE.format(extra=" + 1 plátano" if d >= 5 else ""))]
    if d == 0:
        rows += [("09:00", "Calentamiento + handstand", CAL, HS.format(extra=HS_PUSH)),
                 ("09:20", "Empuje (Alge) · 45 min", CAL, EMPUJE),
                 ("10:05", "Cadera · 15 min", LEG, CADERA.format(rir=rir)),
                 ("10:20", "Core · 10 min", REC, CORE)]
        notes = ["Primera semana de pierna a RIR 3: el estímulo es nuevo." if w == 0 else
                 "RIR 2: te sobran 2 repeticiones en cada serie. Nada al fallo.",
                 "La cadera queda a 5 días de la calidad: es el mejor día para la parte pesada de la pierna.",
                 "Si el HYROX de esta semana es de motor (remo, bici, ski) y no cabe el miércoles, puede ir aquí, "
                 "después de la cadera, corto y tranquilo."]
        return "Handstand · empuje · cadera", [CALI, PIERNA, RECUP], rows, notes
    if d == 1:
        rows += [("09:00", "Calentamiento + handstand", CAL, HS.format(extra=HS_PULL)),
                 ("09:20", "Tirón (Alge) · 40 min", CAL, TIRON),
                 ("10:00", "Accesorios de tirón · 10 min", CAL, ACC_TIRON_MAR),
                 ("10:10", f"Rodaje Z1 (Carlos) · {z1} min", RUN,
                  f"Cinta al 1%, <b>10.0–10.3 km/h</b>. Tienes que poder conversar. En tu Garmin: <b>E{n}</b>."),
                 (hm(10 * 60 + 10 + z1), "Gemelo y sóleo · 6 min", LEG, GEMELO)]
        notes = ["Si la cadera de ayer se nota, quédate en 10.0 km/h.",
                 "Gemelo y sóleo siempre después de correr, nunca antes. Los pidió Carlos por tu pantorrilla izquierda.",
                 "Si vas justo de tiempo, los accesorios son lo primero que se va."]
        return f"Handstand · tirón · Z1 {z1} min", [CALI, CARRERA], rows, notes
    if d == 2:
        rows += [("09:00", "Calentamiento + handstand", CAL, HS.format(extra=HS_PUSH)),
                 ("09:20", "Empuje (Alge) · 45 min", CAL, EMPUJE),
                 ("10:05", "Hombro sano y brazos · 15 min", CAL, ACC_HOMBRO + " " + HYROX_AQUI),
                 ("10:20", "Movilidad · 20 min", REC, MOVILIDAD)]
        notes = ["Es el día de descanso de Carlos: sin carrera y sin pierna, salvo que toque HYROX.",
                 "El HYROX de la semana va aquí porque queda 72 h antes de la calidad y detrás del empuje: el "
                 "cansancio de hombro cae el mismo día. Antes, tus tres preguntas.",
                 "Accesorios a RIR 1, sin fallo."]
        return "Handstand · empuje · hombro sano · movilidad", [CALI, RECUP], rows, notes
    if d == 3:
        rows += [("09:00", "Calentamiento + handstand", CAL, HS.format(extra="")),
                 ("09:20", f"Rodaje Z1 (Carlos) · {z1} min", RUN,
                  f"Cinta al 1%, <b>10.0–10.3 km/h</b>. Tienes que poder conversar. En tu Garmin: <b>J{n}</b>."),
                 (hm(9 * 60 + 20 + z1), "Cuádriceps y pantorrilla · 20 min", LEG, CUADS.format(rir=rir))]
        notes = ["Es el día de pierna de Alge, hecho pierna en gym para correr. El Z1 va antes para que la "
                 "pantorrilla corra fresca.",
                 "Pierna corta y sin fallo: el sábado es la calidad, 48 h después. Mañana no hay pierna.",
                 "Si ayer hubo HYROX, la pierna de hoy con una serie menos."]
        return f"Handstand · Z1 {z1} min · cuádriceps y pantorrilla", [CALI, CARRERA, PIERNA], rows, notes
    if d == 4:
        rows += [("09:00", "Calentamiento + handstand", CAL, HS.format(extra=HS_PULL)),
                 ("09:20", "Tirón (Alge) · 40 min", CAL, TIRON),
                 ("10:00", "Accesorios de tirón · 10 min", CAL, ACC_TIRON_VIE),
                 ("10:10", "Core · 10 min", REC, CORE),
                 ("10:20", "Movilidad · 15 min", REC, MOVILIDAD)]
        notes = ["Nada de pierna: lo pidió Carlos para que llegues fresco a la calidad.",
                 "Carga a las 00:00: mañana es la calidad."]
        return "Handstand · tirón · core y movilidad", [CALI, RECUP], rows, notes
    if d == 5:
        rows += [("09:00", "Calentamiento + handstand", CAL, HS.format(extra=" · hoy el empuje va después de correr")),
                 ("09:20", f"Calidad (Carlos) · ≈{wk['q_min']} min", RUN, wk["q"] + f". En tu Garmin: <b>Q{n}</b>."),
                 (hm(9 * 60 + 20 + wk["q_min"]), "½ Empuje (Alge) · 25 min", CAL, MEDIO_EMPUJE)]
        notes = ["Isotónica casera en sorbos, en el calentamiento y en las pausas (1 bloque).",
                 "Es la sesión que más te hace ganar velocidad: respeta la zona aunque el cuerpo pida más. Con mar "
                 "movida, clip de seguridad y 0.3–0.5 km/h menos.",
                 "Primera vez en Z3: el kilómetro va a palabras sueltas, no a tope." if w == 2 else "",
                 "Carga a las 00:00: mañana es el largo."]
        return f"Handstand · calidad {wk['q_title']} · ½ empuje", [CALI, CARRERA], rows, notes
    long_ = wk["long"]
    rows = [("08:40", "Despiertas", FOOD, WAKE.format(extra=" + 1 plátano")),
            ("09:00", "Movilidad · 15 min", REC, "La rutina de movilidad de Carlos: antes de correr, para darle tiempo "
             "al preentreno."),
            ("09:15", f"Largo Z1 (Carlos) · {dur(long_)}", RUN,
             f"Cinta al 1%, <b>10.0–10.3 km/h</b>; los primeros 10 min en 10.0 y sin acelerar al final. Agua cada "
             f"15–20 min. En tu Garmin: <b>L{n}</b>."),
            ("09:55", "Carbos sin parar", FOOD, "El reloj te avisa: 1 bloque (35 g de dátiles o 500 ml de isotónica)."),
            (hm(9 * 60 + 15 + long_), "Handstand opcional · 10 min", CAL, "Domingo de Alge es descanso: 2–3 aguantes si "
             "te apetece; si no, caminar.")]
    notes = ["Movilidad primero y a correr a las 9:15: le das 35 min al preentreno.",
             "Pésate antes y después: cada kilo perdido son 1–1.5 L por reponer en el día.",
             "Último domingo a bordo: las semanas 4 a 6 de Carlos se arman en tierra." if w == 2 else ""]
    return f"Largo Z1 {dur(long_)} · movilidad", [CARRERA, RECUP], rows, notes


def day_page(w, d):
    day = WEEK1 + timedelta(days=7 * w + d)
    focus, chips, rows, notes = day_content(w, d)
    story = day_header(f"{DIA[d]} {day.day} {MES[day.month - 1]}",
                       f"Semana {w + 1} · día {7 * w + d + 1} de 21<br/>{focus}<br/>" + " ".join(chips))
    story += [fuel_line(d), p("Entreno · 9:00 a 11:30", "h2"),
              table([["Hora", "Sesión", "Qué hacer"]] + [[t, colored(what, c), detail] for t, what, c, detail in rows],
                    [0.09, 0.25, 0.66])]
    story += [p("Lo de hoy", "h2")] + bullets(notes, "sbullet")
    story.append(KeepTogether([p(f"Comidas del {DIA[d].lower()}", "h2"), meals_table(d)]))
    story.append(PageBreak())
    return story


# ── Primeras paginas ────────────────────────────────────────────────────────

def intro():
    story = [
        p("Tres semanas a bordo", "title"), Spacer(1, 4),
        p("19 de octubre al 8 de noviembre de 2026 · Skandi Nomad · entreno 9:00–11:30 · guardia 12:00–24:00", "sub"),
        Spacer(1, 10),
        p("Ahora mismo lo que más importa es <b>velocidad y condición</b> y <b>seguir mejorando en calistenia</b>. "
          f"Cuando dos cosas chocan, cede la de menor prioridad: {chip('1 Calistenia de Alge', CAL)} "
          f"{chip('2 Carrera de Carlos', RUN)} {chip('3 HYROX', HYR)}"),
        Spacer(1, 4),
        p("<b>Cómo usar este PDF.</b> Primero las reglas: la semana, el HYROX, la mañana y el combustible. Después las "
          "sesiones fijas con todas sus series. Al final, un día por página con el horario, lo que cambia esa semana y "
          "las comidas. La carrera ya está en Intervals.icu y llega sola al Garmin: E (martes), J (jueves), Q (sábado) "
          "y L (domingo), con el número de semana."),
        p("La semana tipo", "h1"),
        p("Los planes de Alge y de Carlos, cada uno en sus días. La pierna de calistenia de Alge se hace en gym, para "
          "correr, en dos mitades: cadera el lunes y cuádriceps el jueves.", "small"),
        Spacer(1, 3),
        table([
            ["Día", "Alge", "Carlos", "Además", "Combustible"],
            ["<b>Lun</b>", "HS + empuje", "—", "Cadera + core", colored("Medio", MEDIO)],
            ["<b>Mar</b>", "HS + tirón", "Z1", "Accesorios + gemelo y sóleo", colored("Medio", MEDIO)],
            ["<b>Mié</b>", "HS + empuje", "Descanso", "Hombro sano + movilidad (o el HYROX)", colored("Medio", MEDIO)],
            ["<b>Jue</b>", "HS (su día de pierna)", "Z1", "Cuádriceps y pantorrilla", colored("Medio", MEDIO)],
            ["<b>Vie</b>", "HS + tirón", "Sin pierna", "Accesorios + core + movilidad", colored("Medio", MEDIO) + ", carga a las 00:00"],
            ["<b>Sáb</b>", "HS + ½ empuje", "Calidad", "Isotónica en sorbos", colored("Alto", ALTO) + ", carga a las 00:00"],
            ["<b>Dom</b>", "Descanso", "Largo", "Movilidad", colored("Alto", ALTO)],
        ], [0.08, 0.22, 0.13, 0.35, 0.22]),
        p("Dónde cae el cansancio", "h2"),
    ]
    levels = {0: "#ffffff", 1: "#e8eef6", 2: "#aec3dc", 3: "#14395a"}
    load_rows = [
        ("Hombro y tríceps", [3, 1, 3, 1, 1, 2, 0], ["empuje", "HS", "empuje", "HS", "HS", "½ empuje", "descansa"]),
        ("Espalda y bíceps", [0, 3, 0, 0, 3, 0, 0], ["descansa", "tirón", "descansa", "descansa", "tirón", "descansa", "descansa"]),
        ("Piernas", [2, 1, 0, 2, 0, 3, 2], ["cadera", "Z1", "descansa", "Z1 + cuádriceps", "descansa", "calidad", "largo"]),
    ]
    data = [[Paragraph(h, S["th"]) for h in ["", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]]]
    style = [("BACKGROUND", (0, 0), (-1, 0), NAVY), ("GRID", (0, 0), (-1, -1), 0.4, LINE),
             ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
             ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]
    for r, (name, lv, labels) in enumerate(load_rows, start=1):
        row = [p(f"<b>{name}</b>", "small")]
        for c, (level, label) in enumerate(zip(lv, labels), start=1):
            row.append(Paragraph(f'<font color="{"#ffffff" if level == 3 else "#1f2933"}">{label}</font>', S["cell"]))
            style.append(("BACKGROUND", (c, r), (c, r), hc(levels[level])))
        data.append(row)
    t = Table(data, colWidths=[0.2 * W] + [0.8 * W / 7] * 7)
    t.setStyle(TableStyle(style))
    story += [t, Spacer(1, 3),
              p("Claro: suave. Medio: carga media. Oscuro: fuerte. La pierna descansa miércoles y viernes, y ningún "
                "día junta más de dos cosas exigentes.", "muted")]
    story += [p("Por qué así", "h2")] + bullets([
        "<b>Cada coach en sus días.</b> Alge: empuje lunes, miércoles y medio el sábado; tirón martes y viernes; "
        "handstand diario. Carlos: Z1 martes y jueves, calidad sábado, largo domingo, y el viernes sin pierna.",
        "<b>Velocidad y condición.</b> La calidad del sábado es la sesión que más te hace ganar: llega con el "
        "viernes sin pierna y la pierna del jueves corta. Los Z1 construyen la base que la sostiene.",
        "<b>La pierna en dos mitades.</b> La cadera, que es lo pesado, el lunes, a 5 días de la calidad. "
        "Cuádriceps y pantorrilla el jueves, después del Z1, corto y sin fallo.",
        "<b>Accesorios del plan v3</b> en el tiempo libre: masa (lo que pide Isma) y hombro y codo protegidos, que es "
        "donde más carga acumula tu calistenia. Son lo primero que se recorta.",
    ])
    story.append(PageBreak())

    story += [p("El HYROX de la semana", "h1"),
              p("Tus sesiones de HYROX cambian cada semana, así que no tienen día fijo. Esta es la regla para "
                "acomodarlas sin que interfieran nunca con la calistenia ni con la carrera.")]
    story.append(table([
        ["", "Cuándo", "Por qué"],
        ["<b>Primera opción</b>", "Miércoles, después del empuje, en lugar de los accesorios",
         "Es el descanso de Carlos y queda 72 h antes de la calidad. Detrás del empuje, el cansancio de hombro cae "
         "el mismo día y el siguiente empuje llega 72 h después."],
        ["<b>Segunda opción</b>", "Lunes, después de la cadera, solo si la sesión es de motor (remo, bici, ski)",
         "Para cuando hay dos en la semana, o el miércoles no se puede. Si trae desplantes, saltos o sentadillas, "
         "no va aquí: va el miércoles."],
        ["<b>Nunca</b>", "Jueves, viernes, sábado ni domingo",
         "Son las piernas de la calidad y del largo. El martes tampoco: queda 24 h antes del empuje."],
    ], [0.18, 0.32, 0.50], head_color=hc(HYR)))
    story += [Spacer(1, 4)] + bullets([
        "<b>Siempre más tranquilo de lo normal:</b> esfuerzo 6–7 de 10, como mucho 20–25 min, dos tercios del "
        "volumen si la sesión es larga. Para cuando la técnica empiece a caer.",
        "<b>Box jumps:</b> step-ups, o sube saltando y baja caminando. <b>Desplantes:</b> sin salto. "
        "<b>Thrusters:</b> ligeros; los hombros vienen del empuje.",
        "<b>Ese día pasa a combustible alto:</b> 2 dátiles más al despertar y ½ taza más de arroz a las 11:30.",
        "<b>El jueves siguiente,</b> la pierna con una serie menos.",
    ])
    story += [p("Cada mañana: tres preguntas", "h2"),
              p("En el barco el reloj no distingue bien el sueño, porque mide el movimiento y el barco se mueve. "
                "Cuenta tú las horas, de que apagas la luz a que suena la alarma, y contesta esto al despertar.", "small"),
              Spacer(1, 3)]
    story.append(table([
        ["Pregunta", "Bien", "Normal", "Mal"],
        ["¿Cómo dormí?", "Descansado", "Lo de siempre", "Cortado o corto"],
        ["¿Cómo están las piernas?", "Ligeras", "Algo cargadas", "Pesadas o adoloridas"],
        ["¿Con qué ganas entreno?", "Con ganas", "Normal", "Me cuesta arrancar"],
    ], [0.34, 0.22, 0.22, 0.22]))
    story += [Spacer(1, 4)] + bullets([
        "<b>Todo bien o normal:</b> día normal.",
        "<b>Una «mal»:</b> fuera los accesorios; el HYROX, si toca, a la mitad.",
        "<b>Dos «mal», o menos de 6 h en la cama:</b> sin accesorios ni HYROX; si es sábado, la calidad en la parte "
        "baja de cada zona. La calistenia y la carrera se hacen igual.",
    ])
    story += [p("Cuando algo no cuadra", "h2")] + bullets([
        "<b>Vas justo de tiempo:</b> se van primero los accesorios, después el HYROX. La calistenia y la carrera se quedan.",
        "<b>Hombro o muñeca avisan:</b> fuera los accesorios de empuje; en el HYROX, thrusters por sentadilla frontal y "
        "burpees sin flexión. El empuje de Alge manda.",
        "<b>Pantorrilla izquierda:</b> al primer aviso, para y avisa a Carlos.",
        "<b>Si pierdes una sesión de Carlos,</b> no la recuperes al día siguiente: escríbele y la reordena.",
        "<b>Mar movida:</b> aguantes de handstand contra la pared; en la cinta, clip y 0.3–0.5 km/h menos en lo rápido.",
    ])
    story += [p("Las tres semanas", "h2"),
              table([
                  ["", "Semana 1 · 19–25 oct", "Semana 2 · 26 oct–1 nov", "Semana 3 · 2–8 nov"],
                  ["Cadera y cuádriceps (lun, jue)", "RIR 3", "RIR 2", "RIR 2"],
                  ["Z1 (mar y jue)", "40 min", "45 min", "45 min"],
                  ["Calidad (sáb)", "3 × 2000 m Z2", "2 × 3000 m Z2", "6000 m Z2 + 1000 m Z3"],
                  ["Largo (dom)", "1 h", "1 h 05", "1 h 10"],
              ], [0.28, 0.24, 0.24, 0.24])]
    story.append(PageBreak())

    story += [
        p("Combustible", "h1"),
        p("Comes tres veces, como en el plan de Carlos: la comida grande a las 11:30, la cena a las 17:30 y algo "
          "ligero a las 00:00. Antes de entrenar, tu combo de dátiles. De lunes a viernes es el plan de Carlos "
          "(2,700 kcal); el fin de semana suma lo que piden la calidad y el largo (≈2,900–3,100 kcal). La proteína es "
          "la misma todos los días: ≈150 g (unos 2.2 g por kilo). Las comidas se repiten cada semana, como pide Isma: "
          "así sabes qué comes y la báscula dice algo."),
        p("Tu día", "h2"),
        table([
            ["Hora", "Qué"],
            ["8:40", "Despiertas y preentreno"],
            ["9:00–11:30", "Entreno"],
            ["11:30", "Comida 1, la grande · creatina"],
            ["17:30", "Comida 2 · omega-3"],
            ["00:00", "Comida 3, ligera · magnesio · la carga del viernes y del sábado"],
            ["00:50–1:00", "Dormir: 7 h 40 hasta las 8:40"],
        ], [0.2, 0.8]),
        p("Un bloque = 25 g de carbohidratos", "h2"),
        table([
            ["Alimento", "1 bloque", "Alimento", "1 bloque"],
            ["Arroz blanco", "90 g cocido (½ taza)", "Plátano", "1 mediano"],
            ["Pasta", "80 g cocida (½ taza)", "Fruta: mango, manzana", "1 pieza mediana"],
            ["Papa", "130 g cocida o asada (1 mediana)", "Piña o papaya", "1½ taza picada"],
            ["Camote", "120 g asado", "Dátiles", "35 g (1½ medjool o 5 chicos)"],
            ["Tortillas de maíz", "2 (55 g)", "Miel", "1½ cucharadas"],
            ["Pan de masa madre", "50 g (1 rebanada gruesa)", "Galletas de arroz", "3"],
            ["Avena", "40 g en crudo (½ taza)", "Isotónica casera", "500 ml"],
            ["Frijoles", "110 g cocidos: mucha fibra, no a las 00:00 antes de la calidad", "", ""],
        ], [0.18, 0.32, 0.22, 0.28]),
        p("Reparto del día", "h2"),
        table([
            ["Toma", "Hora", "Lunes a viernes", "Sábado y domingo", "Proteína"],
            ["Preentreno", "8:40", "≈1½ bloques", "≈2½ bloques", "—"],
            ["Durante el entreno", "9:00–11:30", "Isotónica en el Z1 del martes", "1 bloque", "—"],
            ["Comida 1", "11:30", "4½–5 bloques", "5–5½ bloques", "45 g"],
            ["Comida 2", "17:30", "4–4½ bloques", "4–4½ bloques", "45 g"],
            ["Comida 3", "00:00", "3 (4 el viernes)", "3 (4 el sábado)", "30–50 g"],
            ["<b>Total</b>", "", "<b>13–15 · ≈325–375 g</b>", "<b>16–17 · ≈400–425 g</b>", "<b>≈150 g</b>"],
        ], [0.26, 0.13, 0.23, 0.22, 0.16]),
        p("El día que haya HYROX: 2 dátiles más al despertar y ½ taza más de arroz a las 11:30.", "muted"),
        p("Antes, durante y después", "h2"),
    ]
    story += bullets([
        "<b>Antes:</b> tu combo de siempre al despertar, 2 dátiles medjool + 2 nueces + un poquito de chocolate 95% "
        "(≈1½ bloques). Es el truco de Isma. Entre semana alcanza, porque la calistenia aguanta bien. Sábado y "
        "domingo súmale 1 plátano: la calidad y el largo piden más después de 9 h sin comer. No hace falta "
        "proteína antes de entrenar.",
        "<b>Durante:</b> 500–750 ml de agua por hora, con sal o electrolitos. Isotónica en el Z1 del martes, en la "
        "calidad y en el largo.",
        "<b>Después:</b> la comida de las 11:30 es tu recuperación: 4½–5½ bloques, 45 g de proteína y la creatina.",
        "<b>Whey:</b> 1 scoop al día. Va en el yogur de las 00:00 (lunes, viernes y sábado); los otros días, en agua "
        "al terminar de entrenar. Así llegas a ≈150 g y no pasas 11 h sin proteína.",
        "<b>A las 00:00:</b> ligera de grasa y de fibra, porque te duermes una hora después. Sus carbohidratos "
        "llenan el depósito que usas en la mañana para entrenar sin desayunar; por eso la carga del viernes y del "
        "sábado va aquí.",
        "<b>Isotónica casera:</b> 500 ml de agua + 1½ cucharadas de miel + ¼ de cucharadita de sal + jugo de ½ limón: "
        "unos 25 g de carbohidratos y 550 mg de sodio. Es combustible para entrenar; la regla de Carlos de no tomar "
        "bebidas azucaradas sigue para el resto del día.",
        "<b>Café:</b> con el preentreno si lo quieres para entrenar (sobre todo el sábado), o a las 11:30. La regla "
        "de Isma de esperar 1–1.5 h no cabe en tus 20 minutos. El último antes de las 17:00: duermes a la 1.",
        "<b>Suplementos de Isma:</b> creatina 5 g a las 11:30 · omega-3 2 g a las 17:30 · magnesio a las 00:00 · "
        "whey como arriba · cúrcuma con pimienta solo con molestias.",
        "<b>Hambre a media guardia:</b> un yogur con fruta, opcional.",
    ])
    story += [p("En el barco", "h2")] + bullets([
        "<b>Kit de camarote:</b> dátiles, nueces, chocolate 95%, plátanos, avena, miel, whey, galletas de arroz, sal o "
        "electrolitos, shaker y botella de 1 L.",
        "<b>Si el comedor no tiene lo de Carlos:</b> a las 11:30, 2 tazas de arroz, pasta o papa + 1 fruta; a las "
        "17:30, 1½ tazas + 1 fruta; a las 00:00, 1 taza o 4 tortillas + 1 fruta. Siempre con 1–1½ palmas de "
        "proteína, dos manos de verdura y un pulgar de aceite.",
        "<b>El arroz de Carlos:</b> sus 300 g solo cuadran con 2,700 kcal si son en cocido, como la papa y la pasta "
        "que él ya marca cocidas. Carne, pescado y avena, en crudo.",
        "<b>Sueño:</b> de 1:00 a 8:40 son 7 h 40. Cabina oscura, tapones y pantallas fuera.",
        "<b>Báscula (Isma):</b> pésate casi a diario al levantarte. Si la media semanal baja más de 0.5 kg en dos "
        "semanas, suma un bloque a las 17:30; si sube sin que mejore la cintura, quita uno de las 00:00.",
    ])
    story.append(PageBreak())
    return story


def sessions():
    ex_w = [0.40, 0.19, 0.27, 0.14]
    acc_w = [0.42, 0.20, 0.38]
    story = [p("Sesiones fijas", "h1"),
             p("Las páginas de cada día las resumen en una línea; aquí están completas."),
             p("Calentamiento + handstand (Alge) · 20 min, todos los días con calistenia", "h2"),
             p("<b>Calentamiento:</b> entrada en calor 5 min (correr, comba o bici) · movilidad articular 20 s por "
               "articulación · retracción-protracción en posición de flexión 2×10 · handstand en pared empujando "
               "escápulas y hombros 10–15 s. Antes del empuje, algunas flexiones normales y de pica y peso en las "
               "muñecas; antes del tirón, 8 flexiones, retracciones escapulares colgado y alguna dominada.", "small"),
             Spacer(1, 2),
             p("<b>Handstand:</b> 3–4 aguantes de 30–45 s sólidos y con buena forma. En tierra, 5–6. Con mar movida, "
               "contra la pared.", "small"),
             p("Empuje (Alge) · lunes y miércoles · 45 min", "h2"),
             table([["Ejercicio", "Series × reps", "Intensidad", "Descanso"],
                    ["Flexiones de pino libre", "3–4 intentos", "Calidad", "3–4 min"],
                    ["Aguante de 90 grados", "2 series", "Al fallo técnico", "3–4 min"],
                    ["Subida a pino por fuerza", "2 series", "Al fallo", "3–4 min"],
                    ["Flexiones de pino profundas en pared, en paralelas", "2 series", "RIR 0", "3–4 min"],
                    ["Flexiones lean planche", "2 × 6", "Técnica estricta", "3–4 min"]],
                   ex_w, head_color=hc(CAL)),
             p("Tirón (Alge) · martes y viernes · 40 min", "h2"),
             table([["Ejercicio", "Series × reps", "Intensidad", "Descanso"],
                    ["Aguante de front lever", "1", "80% de tu máximo", "3–4 min"],
                    ["Front press + negativa + aguante", "2 series", "Al fallo", "3–4 min"],
                    ["Half press + negativa", "2 series", "Al fallo", "3–4 min"],
                    ["Touch tuck advanced", "2 × 6–8", "Con goma si hace falta", "3–4 min"],
                    ["Dominadas tuck advanced de front", "2 × 6", "Técnica estricta", "3–4 min"]],
                   ex_w, head_color=hc(CAL)),
             p("½ Empuje (Alge) · sábado, después de correr · 25 min", "h2"),
             table([["Ejercicio", "Series × reps", "Intensidad", "Descanso"],
                    ["Flexiones de pino libre", "2 intentos", "Calidad", "3 min"],
                    ["Aguante de 90 grados", "1 serie", "Al fallo técnico", "3 min"],
                    ["Subida a pino por fuerza", "1 serie", "Al fallo", "3 min"],
                    ["Flexiones de pino profundas en pared, en paralelas", "1 serie", "RIR 0", "3 min"],
                    ["Flexiones lean planche", "1 × 6", "Técnica estricta", "—"]],
                   ex_w, head_color=hc(CAL)),
             PageBreak(),
             p("La pierna, en dos mitades", "h2"),
             p("Es el día de pierna de Alge, hecho en gym para correr. Semana 1 a RIR 3 (te sobran 3 repeticiones); "
               "semanas 2 y 3 a RIR 2. Nada al fallo y sin saltos. Descanso de 2 min en lo pesado, 60–90 s en lo "
               "demás.", "small"), Spacer(1, 3),
             table([["Lunes · cadera · 15 min", "Series × reps", "Para qué"],
                    ["Hip thrust", "3 × 8–10", "Glúteo: el empuje de cada zancada"],
                    ["Peso muerto rumano", "2 × 6–8", "Femoral y cadena posterior; el de Alge, sin fallo"],
                    ["Curl femoral", "2 × 10–12", "Isquios, rodilla protegida"]],
                   acc_w, head_color=hc(LEG)),
             Spacer(1, 4),
             table([["Jueves · cuádriceps y pantorrilla · 20 min, después del Z1", "Series × reps", "Para qué"],
                    ["Hack squat (o sentadilla búlgara 3 × 8 por pierna)", "3 × 5–6", "Fuerza de cuádriceps: economía de carrera"],
                    ["Extensión de cuádriceps", "2 × 12–15", "Rodilla y tendón rotuliano"],
                    ["Abductores en polea o máquina", "2 × 15 por lado", "Cadera estable al apoyar"],
                    ["Gemelo de pie, rodilla estirada", "2 × 12–15", "Pantorrilla izquierda (Carlos)"],
                    ["Sóleo sentado, rodilla flexionada", "2 × 15–20", "Pantorrilla izquierda (Carlos)"]],
                   acc_w, head_color=hc(LEG)),
             p("Gemelo y sóleo · martes, después del Z1 · 6 min", "h2"),
             table([["Ejercicio", "Series × reps", "Cómo", "Descanso"],
                    ["Elevación de talón a una pierna, rodilla estirada", "2 × 15 por pierna", "Sube en 1 s, baja en 3 s", "45 s"],
                    ["Elevación de talón a una pierna, rodilla flexionada", "2 × 15 por pierna", "Sube en 1 s, baja en 3 s", "45 s"]],
                   ex_w, head_color=hc(LEG)),
             p("Accesorios (del plan v3) y prevención", "h2"),
             p("Para masa y para cuidar hombro y codo. A RIR 1, sin fallo. Son lo primero que se recorta.", "small"),
             Spacer(1, 3),
             table([["Cuándo", "Qué", "Series × reps"],
                    ["Martes, después del tirón · 10 min", "Remo con pecho apoyado o en máquina · curl de bíceps · face pull",
                     "2 × 8–12 · 2 × 8–12 · 2 × 12–15"],
                    ["Miércoles, después del empuje · 15 min (o el HYROX)",
                     "Elevaciones laterales · rotación externa con banda · flexores y extensores de antebrazo",
                     "3 × 12–15 · 2 × 15–20 · 2 × 15–20"],
                    ["Viernes, después del tirón · 10 min", "Jalón unilateral · curl martillo · Y en banda o face pull",
                     "2 × 8–12 · 2 × 10–14 · 2 × 12–20"]],
                   [0.27, 0.48, 0.25], head_color=hc(REC)),
             PageBreak(),
             p("Movilidad · miércoles 20 min, viernes y domingo 15 min", "h2"),
             table([["Zona", "Qué", "Dosis"],
                    ["Hombros (Alge)", "Estiramiento en espaldera · dislocaciones con palo · apertura de pecho en el suelo",
                     "3 × 30–45 s · 3 × 10 · 3 × 30–45 s"],
                    ["Muñecas (Alge)", "Apoyos en cuadrupedia con los dedos en las cuatro direcciones", "3 × 30 s"],
                    ["Cadera (Alge)", "Balanceos frontales y laterales · mariposa · apertura y pinza",
                     "10 + 10 · 30–60 s · 3 × 30 s"],
                    ["Carrera (Carlos)", "Rutina de movilidad de la academia, en Skool", "La que marque"]],
                   [0.20, 0.52, 0.28], head_color=hc(REC)),
             p("Core · lunes y viernes, 10 min", "h2"),
             p("La rutina de core de la academia de Carlos (Skool).", "small"),
             p("Carrera en cinta", "h2"),
             table([["Zona", "Ritmo de Carlos", "Cinta (1% de inclinación)", "Cómo se siente"],
                    ["Z1", "5:50–6:00 min/km", "10.0–10.3 km/h", "Conversas sin quedarte sin aire"],
                    ["Z2", "4:45–4:50 min/km", "12.4–12.6 km/h", "Hablas con frases cortas"],
                    ["Z3", "4:25–4:30 min/km", "13.3–13.6 km/h", "Solo palabras sueltas"]],
                   [0.12, 0.24, 0.26, 0.38], head_color=hc(RUN)),
             Spacer(1, 3)]
    story += bullets([
        "Manda la velocidad de la cinta, no el ritmo del reloj. Al guardar, corrige la distancia en Garmin para que se "
        "calibre. El domingo tu reloj marcó 8.0 km en 59 min (≈8.1 km/h): si de verdad ibas a 8 km/h, díselo a "
        "Carlos, porque su Z1 es a 10.",
        "En el reloj las series van en tiempo, a la velocidad media de la zona: en la cinta salen los metros de Carlos.",
        "Respeta la zona aunque el cuerpo pida más. Con mar movida: clip de seguridad y 0.3–0.5 km/h menos en lo rápido.",
    ], "sbullet")
    story += [Spacer(1, 6), p("Pendiente con tus coaches", "h2")] + bullets([
        "<b>Velocidad (Carlos):</b> pregúntale si quiere que agregues rectas (4–6 × 20 s progresivas) al final de un Z1. "
        "Son lo más barato para ganar velocidad, pero su plan no las trae y él pidió respetar las zonas.",
        "<b>¿Sigue el 10K del 22 de noviembre?</b> Carlos escribió que no tienes carrera a la vista, y ese domingo su "
        "plan pone 1 h 20 de Z1. Si sigue en pie, díselo: él pidió planificar en torno a la carrera.",
        "<b>HYROX (Carlos e Isma):</b> cuéntales que haces una sesión tranquila a la semana, de preferencia el miércoles.",
        "<b>Alge:</b> pregúntale si le parece su día de pierna hecho en gym y en dos mitades, y los accesorios del v3 "
        "después de sus sesiones.",
    ], "sbullet")
    story += [Spacer(1, 8),
              p("Hecho a partir de la planificación M1 de Alge, el plan de entrenamiento y el plan nutricional de Carlos "
                "(Running Master, octubre de 2026), el plan de alimentación de Isma (junio de 2026) y el Plan Híbrido "
                "4 Días v3 (agosto de 2026).", "muted"),
              PageBreak()]
    return story


def build():
    story = intro() + sessions()
    for w in range(len(WEEKS)):
        for d in range(7):
            story += day_page(w, d)
    story.pop()  # sin pagina en blanco al final
    return story


if __name__ == "__main__":
    doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm,
                            topMargin=14 * mm, bottomMargin=16 * mm,
                            title="Tres semanas a bordo · Joseph Pelayo", author="Joseph Pelayo")
    doc.build(build(), onFirstPage=footer, onLaterPages=footer)
    print(OUT.name)
