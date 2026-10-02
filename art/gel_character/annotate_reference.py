"""Draw the S-311.2 proportion sheet over the untouched reference photo.

Run from the repository root: python art/gel_character/annotate_reference.py
Writes art/gel_character/referencia/proporciones.png. Requires Pillow >= 10.1.

The photo is pasted pixel for pixel (no resampling) and every mark is drawn in
reference-pixel coordinates, so the sheet can be measured against the JPG.
The figures are the ones in the LEEME.md table; the landmarks below place them.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
SOURCE = HERE / "referencia/referencia_frente.jpg"
OUTPUT = HERE / "referencia/proporciones.png"

D = 282  # mean head diameter, px (measure_reference.py)
H = 1038  # body height, px: inclusive bbox y=98..1135
BBOX = (148, 98, 676, 1135)
# Landmarks in reference pixels, read off the photo and the body mask.
HEAD = (274, 98, 556, 378)  # 282 x 280 px circle box
NECK = (337, 378, 492, 409)  # 0,55 D x 0,11 D, centred on the head
SHOULDER_Y = 425
SHOULDERS = (260, 565)  # 305 px = 1,08 D
ARM = [(282, 438), (225, 600), (200, 700), (190, 790)]  # centreline; length from the table
HAND = (150, 680, 249, 790)  # 0,35 D x 0,39 D
CROTCH_Y = 743  # 1135 - 392: leg = 37,8 % H
FOOT = (214, 1008, 375, 1135)  # 0,57 D x 0,45 D, one boot

MARGIN_L, MARGIN_R, MARGIN_T, MARGIN_B = 330, 360, 40, 130
INK = (28, 32, 70, 255)
ACCENT = (200, 60, 40, 255)


FONTS = ("DejaVuSans.ttf", "arial.ttf", "LiberationSans-Regular.ttf")


def _font(size):
    # A real TTF has the × and accented glyphs; Pillow's bundled one does not.
    for name in FONTS:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def _label(draw, xy, text, anchor="lm"):
    font = _font(26)
    box = draw.textbbox(xy, text, font=font, anchor=anchor)
    draw.rounded_rectangle((box[0] - 8, box[1] - 5, box[2] + 8, box[3] + 5), 6, fill=(232, 233, 250, 255))
    draw.text(xy, text, font=font, fill=INK, anchor=anchor)


def _vbar(draw, x, y0, y1, color=INK):
    draw.line((x, y0, x, y1), fill=color, width=3)
    for y in (y0, y1):
        draw.line((x - 10, y, x + 10, y), fill=color, width=3)


def _hbar(draw, y, x0, x1, color=INK):
    draw.line((x0, y, x1, y), fill=color, width=3)
    for x in (x0, x1):
        draw.line((x, y - 10, x, y + 10), fill=color, width=3)


def main():
    photo = Image.open(SOURCE).convert("RGB")
    assert photo.size == (832, 1248), "Reference dimensions changed"
    sheet = Image.new("RGBA", (photo.width + MARGIN_L + MARGIN_R, photo.height + MARGIN_T + MARGIN_B),
                      (255, 255, 255, 255))
    sheet.paste(photo, (MARGIN_L, MARGIN_T))
    draw = ImageDraw.Draw(sheet)

    def p(x, y):
        return x + MARGIN_L, y + MARGIN_T

    def box(b):
        return (*p(b[0], b[1]), *p(b[2], b[3]))

    # Body box and total height.
    draw.rectangle(box(BBOX), outline=(120, 124, 170, 255), width=1)
    x, _ = p(BBOX[0] - 110, 0)
    _vbar(draw, x, p(0, BBOX[1])[1], p(0, BBOX[3])[1])
    _label(draw, (x - 20, p(0, 560)[1]), f"H = {H} px", anchor="rm")
    _label(draw, (x - 20, p(0, 610)[1]), f"= {H / D:.2f} D".replace(".", ","), anchor="rm")

    # Head, neck, shoulders.
    draw.ellipse(box(HEAD), outline=ACCENT, width=3)
    _vbar(draw, p(HEAD[2] + 150, 0)[0], p(0, HEAD[1])[1], p(0, HEAD[3])[1])
    _label(draw, (p(HEAD[2] + 170, 0)[0], p(0, 240)[1]), f"Cabeza D = {D} px")
    draw.rectangle(box(NECK), outline=ACCENT, width=2)
    _label(draw, (p(HEAD[2] + 170, 0)[0], p(0, 395)[1]), "Cuello 0,55 D × 0,11 D")
    _hbar(draw, p(0, SHOULDER_Y)[1], p(SHOULDERS[0], 0)[0], p(SHOULDERS[1], 0)[0], ACCENT)
    _label(draw, (p(HEAD[2] + 170, 0)[0], p(0, 455)[1]), "Hombros 305 px = 1,08 D")

    # Arm and hand (left of the image).
    draw.line([p(*point) for point in ARM], fill=ACCENT, width=3, joint="curve")
    _label(draw, (p(BBOX[0] - 130, 0)[0], p(0, 470)[1]), "Brazo 1,44 D = 39,1 % H", anchor="rm")
    draw.rectangle(box(HAND), outline=ACCENT, width=2)
    _label(draw, (p(BBOX[0] - 130, 0)[0], p(0, 735)[1]), "Mano 0,35 D × 0,39 D", anchor="rm")

    # Leg and boot.
    _vbar(draw, p(BBOX[2] + 40, 0)[0], p(0, CROTCH_Y)[1], p(0, BBOX[3])[1])
    draw.line((*p(430, CROTCH_Y), *p(BBOX[2] + 40, CROTCH_Y)), fill=INK, width=1)
    _label(draw, (p(BBOX[2] + 60, 0)[0], p(0, 940)[1]), "Pierna 1,39 D = 37,8 % H")
    draw.rectangle(box(FOOT), outline=ACCENT, width=2)
    _label(draw, (p(BBOX[0] - 130, 0)[0], p(0, 1070)[1]), "Bota 0,57 D × 0,45 D", anchor="rm")

    notes = (
        "Foto original 832 × 1248 px sin retoque; marcas en píxeles de la referencia.",
        "D = diámetro de cabeza, H = alto del cuerpo. La tabla de LEEME.md es la autoridad;",
        "el trazo del brazo es ilustrativo. Generado por annotate_reference.py.",
    )
    for line, text in enumerate(notes):
        _label(draw, (40, sheet.height - 100 + line * 34), text)
    sheet.convert("RGB").save(OUTPUT, optimize=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
