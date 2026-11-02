"""Textures for the company's boxes and products (expansion group 18), drawn in code with Pillow, no generator and
no third-party art:

    python do-not-drop/assets/tools/build_label_textures.py decals    # D-1808
    python do-not-drop/assets/tools/build_label_textures.py brands    # D-1833

- decals (D-1808): the five seals of BoxSeals.KINDS (fragile, no_bend, cold, gift, heavy) plus "this side up", the
  shipping label and the express label, as pictograms with no words (nothing to translate), 256 x 256 RGBA on a
  transparent ground, a coloured round-cornered sticker with an ink border. assets/textures/decals/.
- brands (D-1833): thirty labels of made-up, silly brands (no real brand), 512 x 256 RGBA: a coloured band, the
  brand's name in the game's display face (Lilita One) and a small emblem. assets/textures/brands/.
Deterministic: the same files every run.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.abspath(os.path.join(HERE, ".."))
FONT = os.path.join(ASSETS, "fonts", "LilitaOne-Regular.ttf")
INK = (30, 34, 53, 255)
PAPER = (250, 243, 227, 255)

DECALS = {
    "seal_fragile": (232, 76, 61), "seal_no_bend": (240, 160, 40), "seal_cold": (80, 160, 230),
    "seal_gift": (220, 90, 170), "seal_heavy": (110, 110, 120), "seal_this_side_up": (70, 170, 110),
    "label_shipping": (250, 243, 227), "label_express": (255, 200, 60),
}

BRANDS = [
    ("Vaquita Feliz", (90, 160, 220), "circle"), ("Doña Gallina", (230, 140, 60), "egg"),
    ("Pan de Ayer", (200, 150, 90), "loaf"), ("Frágil y Feliz", (232, 76, 61), "star"),
    ("El Tano Lácteos", (240, 240, 240), "circle"), ("Galpón Gourmet", (60, 70, 90), "box"),
    ("Mate Mareado", (80, 140, 70), "leaf"), ("Torta Tembleque", (230, 120, 170), "star"),
    ("Pez Distraído", (60, 130, 200), "wave"), ("Helados Glaciar", (150, 210, 240), "flake"),
    ("Chispazo", (250, 200, 40), "bolt"), ("Tostadas Tío Rulo", (190, 110, 50), "loaf"),
    ("Burbujín", (150, 220, 230), "circle"), ("Cinta Pegote", (170, 120, 60), "box"),
    ("Mochila Andariega", (70, 90, 170), "leaf"), ("Zapatilla Veloz", (240, 80, 60), "bolt"),
    ("Libros Bostezo", (120, 90, 160), "box"), ("Tazón Gigante", (240, 200, 120), "circle"),
    ("Queso Agujerito", (250, 210, 80), "circle"), ("Miel de la Siesta", (240, 170, 30), "wave"),
    ("Coco Loco", (110, 80, 50), "circle"), ("Volcán Souvenir", (220, 70, 30), "star"),
    ("Esquí Patinazo", (90, 170, 230), "flake"), ("Ancla Marinera", (40, 70, 120), "wave"),
    ("Garrafa Tranquila", (240, 120, 40), "box"), ("Fuegos Chispita", (200, 40, 60), "star"),
    ("Cactus Abrazo", (90, 160, 80), "leaf"), ("Loro Charlatán", (60, 180, 90), "egg"),
    ("Química Ups", (150, 80, 180), "bolt"), ("Conejo Saltarín", (240, 240, 230), "egg"),
]


def sticker(color, size=256):
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((8, 8, size - 8, size - 8), radius=36, fill=(*color[:3], 255), outline=INK, width=10)
    return image, draw


def decal(name, color):
    image, d = sticker(color)
    c = 128
    if name == "seal_fragile":  # a wine glass with a crack
        d.polygon([(84, 60), (172, 60), (150, 130), (106, 130)], fill=PAPER, outline=INK, width=6)
        d.rectangle((122, 130, 134, 180), fill=INK)
        d.rectangle((96, 180, 160, 192), fill=INK)
        d.line([(128, 64), (118, 92), (136, 104), (124, 126)], fill=INK, width=6)
    elif name == "seal_no_bend":  # a sheet with a crossed bend
        d.rectangle((84, 60, 172, 196), fill=PAPER, outline=INK, width=6)
        d.line([(70, 128), (186, 128)], fill=INK, width=8)
        d.line([(80, 80), (176, 176)], fill=(200, 30, 30, 255), width=12)
    elif name == "seal_cold":  # a snowflake
        for angle in range(0, 180, 30):
            import math
            dx, dy = 70 * math.cos(math.radians(angle)), 70 * math.sin(math.radians(angle))
            d.line([(c - dx, c - dy), (c + dx, c + dy)], fill=PAPER, width=12)
        d.ellipse((c - 16, c - 16, c + 16, c + 16), fill=PAPER, outline=INK, width=4)
    elif name == "seal_gift":  # a present with a bow
        d.rectangle((70, 100, 186, 196), fill=PAPER, outline=INK, width=6)
        d.rectangle((120, 100, 136, 196), fill=INK)
        d.ellipse((84, 56, 128, 104), outline=INK, width=8)
        d.ellipse((128, 56, 172, 104), outline=INK, width=8)
    elif name == "seal_heavy":  # a weight
        d.polygon([(90, 100), (166, 100), (190, 196), (66, 196)], fill=INK)
        d.ellipse((108, 60, 148, 104), outline=INK, width=10)
    elif name == "seal_this_side_up":  # two arrows up over a bar
        for x in (96, 160):
            d.polygon([(x, 56), (x - 28, 100), (x + 28, 100)], fill=INK)
            d.rectangle((x - 9, 100, x + 9, 168), fill=INK)
        d.rectangle((60, 182, 196, 196), fill=INK)
    elif name == "label_shipping":  # address lines and a barcode
        for i, w in enumerate((150, 120, 140)):
            d.rectangle((40, 50 + 26 * i, 40 + w, 62 + 26 * i), fill=INK)
        for i in range(22):
            width = 3 if i % 3 else 6
            d.rectangle((44 + i * 8, 150, 44 + i * 8 + width, 206), fill=INK)
    elif name == "label_express":  # a lightning bolt
        d.polygon([(140, 40), (80, 140), (124, 140), (108, 216), (180, 104), (134, 104), (156, 40)], fill=INK)
    return image


def emblem(d, kind, box, color):
    x0, y0, x1, y1 = box
    cx, cy, r = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2
    fill = (*color[:3], 255)
    if kind == "circle":
        d.ellipse(box, fill=PAPER, outline=INK, width=5)
        d.ellipse((cx - r / 2, cy - r / 2, cx + r / 2, cy + r / 2), fill=fill)
    elif kind == "egg":
        d.ellipse((x0 + r * 0.2, y0, x1 - r * 0.2, y1), fill=PAPER, outline=INK, width=5)
    elif kind == "loaf":
        d.rounded_rectangle((x0, y0 + r * 0.4, x1, y1), radius=int(r * 0.5), fill=(214, 160, 90, 255), outline=INK, width=5)
    elif kind == "star":
        import math
        points = []
        for i in range(10):
            radius = r if i % 2 == 0 else r * 0.45
            angle = math.pi / 2 + i * math.pi / 5
            points.append((cx + radius * math.cos(angle), cy - radius * math.sin(angle)))
        d.polygon(points, fill=PAPER, outline=INK)
    elif kind == "box":
        d.rectangle((x0 + 6, y0 + 10, x1 - 6, y1 - 6), fill=(190, 140, 80, 255), outline=INK, width=5)
        d.line([(cx, y0 + 10), (cx, y1 - 6)], fill=INK, width=4)
    elif kind == "leaf":
        d.ellipse((x0, y0 + r * 0.3, x1, y1 - r * 0.3), fill=(90, 170, 80, 255), outline=INK, width=5)
        d.line([(x0 + 6, cy), (x1 - 6, cy)], fill=INK, width=4)
    elif kind == "wave":
        for i in range(3):
            d.arc((x0, y0 + i * r * 0.5, x1, y0 + r + i * r * 0.5), 200, 340, fill=INK, width=6)
    elif kind == "flake":
        for dx, dy in ((r, 0), (0, r), (r * 0.7, r * 0.7), (r * 0.7, -r * 0.7)):
            d.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=PAPER, width=8)
    elif kind == "bolt":
        d.polygon([(cx + r * 0.2, y0), (x0 + r * 0.3, cy + 6), (cx, cy + 6), (cx - r * 0.2, y1),
                   (x1 - r * 0.3, cy - 6), (cx, cy - 6)], fill=(255, 210, 50, 255), outline=INK)


def brand(name, color, kind):
    image = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    d.rounded_rectangle((6, 6, 506, 250), radius=28, fill=PAPER, outline=INK, width=8)
    d.rectangle((14, 150, 498, 212), fill=(*color[:3], 255))
    emblem(d, kind, (24, 24, 136, 136), color)
    size = 64
    font = ImageFont.truetype(FONT, size)
    while d.textlength(name, font=font) > 340 and size > 28:
        size -= 4
        font = ImageFont.truetype(FONT, size)
    d.text((150, 80), name, font=font, fill=INK, anchor="lm")
    return image


def slug(text):
    table = str.maketrans("áéíóúñÁÉÍÓÚÑ", "aeiounAEIOUN")
    return "".join(ch if ch.isalnum() else "_" for ch in text.translate(table).lower()).strip("_")


def main():
    which = sys.argv[1:] or ["decals", "brands"]
    if "decals" in which:
        out = os.path.join(ASSETS, "textures", "decals")
        os.makedirs(out, exist_ok=True)
        for name, color in DECALS.items():
            decal(name, color).save(os.path.join(out, "tx_decal_%s_256.png" % name))
            print("DECAL", name)
    if "brands" in which:
        out = os.path.join(ASSETS, "textures", "brands")
        os.makedirs(out, exist_ok=True)
        for name, color, kind in BRANDS:
            brand(name, color, kind).save(os.path.join(out, "tx_brand_%s_512.png" % slug(name)))
            print("BRAND", slug(name))


main()
