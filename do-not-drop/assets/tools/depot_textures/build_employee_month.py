"""tx_depot_employee_month.png (256 x 320): gold frame, portrait of a faceless crew bean
with a hard hat and a thumbs-up, star rosette, and the name plate. No title text
(language-neutral): the star says "of the month"."""
import math
import sys
from PIL import Image, ImageDraw, ImageFont

FONT, OUT = sys.argv[1], sys.argv[2]
NAME = ("PACO", "PAQUETE")
S = 4
W, H = 256 * S, 320 * S
INK = (0x1e, 0x22, 0x35)
PAPER = (0xff, 0xf6, 0xe6)
GOLD = (0xe7, 0xbe, 0x51)
GOLD_D = (0xb8, 0x8f, 0x2e)
SKIN, SKIN_D = (0xd9, 0x95, 0x63), (0xbf, 0x7c, 0x4d)
SHIRT, SHIRT_D = (0xe0, 0x65, 0x4a), (0xc2, 0x50, 0x3a)
VEST = (0xf2, 0x8c, 0x28)
BACK, BACK_D = (0x8c, 0xbf, 0xcf), (0x78, 0xab, 0xbd)

img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)


def p(*v):
    return [x * S for x in v]


# Frame: gold with a darker bevel and an ink outline, paper mat inside.
d.rounded_rectangle(p(0, 0, 255, 319), radius=10 * S, fill=INK)
d.rounded_rectangle(p(4, 4, 251, 315), radius=8 * S, fill=GOLD_D)
d.rounded_rectangle(p(8, 8, 247, 311), radius=6 * S, fill=GOLD)
d.rectangle(p(18, 18, 237, 301), fill=PAPER)

# Photo: studio backdrop with a soft vignette band.
px0, py0, px1, py1 = 30, 30, 225, 222
d.rectangle(p(px0, py0, px1, py1), fill=BACK)
photo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
q = ImageDraw.Draw(photo)
cx = 128
q.ellipse(p(px0 - 40, py0 + 120, px1 + 40, py1 + 140), fill=BACK_D)
# Body / shoulders: rounded blob shirt, safety-vest straps.
q.rounded_rectangle(p(cx - 78, 168, cx + 78, 260), radius=40 * S, fill=SHIRT)
q.rounded_rectangle(p(cx + 30, 172, cx + 78, 260), radius=34 * S, fill=SHIRT_D)
q.polygon(p(cx - 52, 178, cx - 30, 172, cx - 14, 230, cx - 36, 230), fill=VEST)
q.polygon(p(cx + 52, 178, cx + 30, 172, cx + 14, 230, cx + 36, 230), fill=VEST)
q.rectangle(p(cx - 44, 204, cx - 20, 210), fill=PAPER)
q.rectangle(p(cx + 20, 204, cx + 44, 210), fill=PAPER)
# Head: big faceless ball, flat shade crescent on the right.
hx, hy, hr = cx, 122, 52
q.ellipse(p(hx - hr, hy - hr, hx + hr, hy + hr), fill=SKIN_D)
q.ellipse(p(hx - hr, hy - hr, hx + hr - 12, hy + hr - 6), fill=SKIN)
q.ellipse(p(hx - 30, hy - 30, hx - 12, hy - 14), fill=(0xe6, 0xab, 0x7c))   # highlight
# Hard hat: dome + brim + ridge.
q.chord(p(hx - 50, hy - 76, hx + 50, hy + 4), 180, 360, fill=GOLD)
q.chord(p(hx - 50, hy - 76, hx + 50, hy + 4), 300, 360, fill=GOLD_D)
q.rounded_rectangle(p(hx - 62, hy - 40, hx + 62, hy - 28), radius=6 * S, fill=GOLD_D)
q.rounded_rectangle(p(hx - 62, hy - 42, hx + 58, hy - 32), radius=5 * S, fill=GOLD)
q.rectangle(p(hx - 6, hy - 74, hx + 6, hy - 42), fill=GOLD_D)
# Thumbs-up hand, lower right.
fx, fy = cx + 62, 196
q.rounded_rectangle(p(fx - 20, fy - 6, fx + 20, fy + 26), radius=10 * S, fill=SKIN)
q.rounded_rectangle(p(fx - 9, fy - 32, fx + 5, fy + 2), radius=7 * S, fill=SKIN)
for i in range(3):
    q.line(p(fx - 2, fy + 5 + i * 7, fx + 18, fy + 5 + i * 7), fill=SKIN_D, width=2 * S)
q.rounded_rectangle(p(fx - 30, fy + 14, fx - 12, fy + 30), radius=6 * S, fill=SHIRT_D)  # sleeve
# Clip the portrait to the photo window.
mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask).rectangle(p(px0, py0, px1, py1), fill=255)
img.alpha_composite(Image.composite(photo, Image.new("RGBA", (W, H), (0, 0, 0, 0)), mask))
d = ImageDraw.Draw(img)
d.rectangle(p(px0, py0, px1, py1), outline=INK, width=3 * S)

# Star rosette over the top-right corner of the photo.
sx, sy, r1, r2 = 214, 40, 26, 12
d.ellipse(p(sx - 30, sy - 30, sx + 30, sy + 30), fill=INK)
d.ellipse(p(sx - 27, sy - 27, sx + 27, sy + 27), fill=SHIRT)
pts = [(sx + (r1 if k % 2 == 0 else r2) * math.sin(k * math.pi / 5),
        sy - (r1 if k % 2 == 0 else r2) * math.cos(k * math.pi / 5)) for k in range(10)]
d.polygon([v * S for pt in pts for v in pt], fill=GOLD, outline=INK, width=2 * S)
for dx in (-12, 4):     # ribbon tails
    d.polygon(p(sx + dx, sy + 24, sx + dx + 10, sy + 24, sx + dx + 10 + (4 if dx > 0 else -2), sy + 50,
                sx + dx + 5, sy + 44, sx + dx + (0 if dx > 0 else -4), sy + 50), fill=SHIRT_D, outline=INK)

# Name plate.
d.rounded_rectangle(p(30, 232, 225, 294), radius=6 * S, fill=INK)
for line, (y0, y1) in zip(NAME, ((236, 262), (264, 290))):
    size = 40 * S
    while True:
        f = ImageFont.truetype(FONT, size)
        l, t, r, b = f.getbbox(line)
        if r - l <= 180 * S and b - t <= (y1 - y0) * S:
            break
        size -= S
    d.text(((128 * S) - (r - l) / 2 - l, (y0 + y1) / 2 * S - (b - t) / 2 - t), line, font=f,
           fill=GOLD if line == NAME[1] else PAPER)

img.resize((256, 320), Image.LANCZOS).save(OUT)
print("ok")
