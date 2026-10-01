"""tx_depot_mural_brand.png: TAKE MY PACKAGE in Lilita One, PAPER, old paint on sheet metal."""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = sys.argv[1]
OUT = sys.argv[2]
W, H, SS = 1024, 205, 2
rng = np.random.default_rng(319)

# Text mask, supersampled, fitted to ~94 % width / ~78 % height.
w, h = W * SS, H * SS
size = 400
while True:
    font = ImageFont.truetype(FONT, size)
    l, t, r, b = font.getbbox("TAKE MY PACKAGE")
    if r - l <= w * 0.94 and b - t <= h * 0.78:
        break
    size -= 4
mask = Image.new("L", (w, h), 0)
d = ImageDraw.Draw(mask)
d.text(((w - (r - l)) / 2 - l, (h - (b - t)) / 2 - t), "TAKE MY PACKAGE", font=font, fill=255)
text = np.asarray(mask).astype(np.float32) / 255.0


def noise(scale, octaves=3):
    """Value noise: upscaled random grids, summed."""
    out = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        gw, gh = max(2, int(w / scale) + 2), max(2, int(h / scale) + 2)
        g = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8))
        out += amp * np.asarray(g.resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0
        total += amp
        amp *= 0.5
        scale /= 2.2
    return out / total


# 1. Chipped patches: big blotches where the paint fell off.
chips = noise(70, 4)
holes = chips < 0.26
# 2. Edge erosion: distance into the letter (blurred mask) vs. noise, eats the borders.
inner = np.asarray(mask.filter(ImageFilter.GaussianBlur(5 * SS))).astype(np.float32) / 255.0
edge = noise(14, 3)
eaten = inner < 0.12 + 0.36 * edge
# 3. Fine speckle and a few horizontal streaks following the corrugated sheet.
speck = noise(4, 2) < 0.14
rows = np.arange(h)[:, None]
pitch = h / 6.0
streak = (np.abs(((rows % pitch) / pitch) - 0.5) < 0.025) & (noise(40, 2) < 0.38)

paint = text * (~holes) * (~eaten) * (~speck) * (~streak)
# Faded unevenly: 0.68 .. 0.84, ~0.75 over the painted area.
fade = 0.68 + 0.16 * noise(160, 2)
alpha = paint * fade
alpha = alpha.reshape(H, SS, W, SS).mean(axis=(1, 3))
rgb = np.array([0xff, 0xf6, 0xe6], np.float32) / 255.0
img = np.zeros((H, W, 4), np.float32)
img[..., :3] = rgb
img[..., 3] = alpha
Image.fromarray(np.round(img * 255).astype(np.uint8), "RGBA").save(OUT)
covered = alpha[alpha > 0.05]
print("font size", size // SS, "mean alpha on paint", covered.mean().round(3),
      "paint kept", (paint.sum() / text.sum()).round(3))
