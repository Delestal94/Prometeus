"""tx_depot_cork_photos.png (512 x 340): cork board, 6 crooked polaroids of real game
captures with pins, and 2 papers. Drawn at 2x and reduced."""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

OUT = sys.argv[1]
SHOTS = "C:/Users/migue/AppData/Roaming/Godot/app_userdata/Take My Package/"
SS = 2
W, H = 512 * SS, 340 * SS
rng = np.random.default_rng(3190)

INK = (0x1e, 0x22, 0x35)
PAPER = (0xff, 0xf6, 0xe6)
WARNING = (0xe7, 0xbe, 0x51)


def value_noise(w, h, scale):
    g = Image.fromarray((rng.random((int(h / scale) + 2, int(w / scale) + 2)) * 255).astype(np.uint8))
    return np.asarray(g.resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0


# --- Cork: warm tan with flat grains of two tones, wooden frame -------------
base = np.array([0xc4, 0x8f, 0x58], np.float32)
dark = np.array([0x9a, 0x64, 0x37], np.float32)
light = np.array([0xdc, 0xae, 0x78], np.float32)
img = np.ones((H, W, 3), np.float32) * base
tone = value_noise(W, H, 90)
img += ((tone - 0.5) * 22)[..., None]
for scale, thr, col in ((3, 0.80, dark), (5, 0.84, dark), (3, 0.82, light), (6, 0.86, light)):
    m = value_noise(W, H, scale) > thr
    img[m] = col + (tone[m, None] - 0.5) * 20
FR = 14 * SS
frame = np.zeros((H, W), bool)
frame[:FR] = frame[-FR:] = True
frame[:, :FR] = frame[:, -FR:] = True
wood = np.array([0x7a, 0x4f, 0x2e], np.float32)
img[frame] = wood
grain = (np.sin(np.arange(W)[None, :] * 0.05 + value_noise(W, H, 30) * 6) > 0.7) & frame
img[grain] = wood * 0.85
inner = np.zeros((H, W), bool)
inner[FR - 3 * SS:FR] = True
inner[:, FR - 3 * SS:FR] = True
img[inner & frame] = wood * 0.7          # inner shadow line of the frame
img[(np.arange(H)[:, None] < 3 * SS) | (np.arange(W)[None, :] < 3 * SS)] = wood * 1.15
board = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def crop(path, cx, cy, width, aspect=100 / 86):
    im = Image.open(SHOTS + path).convert("RGB")
    w, h = width, width / aspect
    x0 = min(max(cx - w / 2, 0), im.width - w)
    y0 = min(max(cy - h / 2, 0), im.height - h)
    im = im.crop((int(x0), int(y0), int(x0 + w), int(y0 + h)))
    # Old print: a touch less saturated, warmer, slightly lifted blacks.
    im = ImageEnhance.Color(im).enhance(0.85)
    a = np.asarray(im).astype(np.float32)
    a = a * np.array([1.04, 1.0, 0.92]) * 0.92 + 14
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def polaroid(photo):
    pw, ph = 100 * SS, 86 * SS
    m, bottom = 7 * SS, 24 * SS
    card = Image.new("RGBA", (pw + 2 * m, ph + m + bottom), PAPER + (255,))
    card.paste(photo.resize((pw, ph), Image.LANCZOS), (m, m))
    return card


def note():
    """White sheet with ink scribble lines (no real text) and a box doodle."""
    w, h = 84 * SS, 112 * SS
    s = Image.new("RGBA", (w, h), (0xfb, 0xfb, 0xf4, 255))
    d = ImageDraw.Draw(s)
    d.rectangle((8 * SS, 9 * SS, w - 8 * SS, 17 * SS), fill=INK)     # heading bar
    y = 28 * SS
    while y < h - 34 * SS:
        x1 = w - (8 + rng.integers(0, 26)) * SS
        d.line((8 * SS, y, x1, y), fill=INK + (200,), width=2 * SS)
        y += 9 * SS
    # little parcel doodle + checkmark at the bottom
    bx, by = 10 * SS, h - 28 * SS
    d.rectangle((bx, by, bx + 18 * SS, by + 16 * SS), outline=INK, width=2 * SS)
    d.line((bx + 9 * SS, by, bx + 9 * SS, by + 6 * SS), fill=INK, width=2 * SS)
    d.line((w - 34 * SS, by + 8 * SS, w - 26 * SS, by + 16 * SS, w - 12 * SS, by - 2 * SS), fill=(0x2f, 0x9e, 0x5b), width=3 * SS)
    return s


def sticky():
    """WARNING-yellow sticky note with a scribbled star and three lines."""
    w = 66 * SS
    s = Image.new("RGBA", (w, w), WARNING + (255,))
    d = ImageDraw.Draw(s)
    d.rectangle((0, 0, w, 9 * SS), fill=(0xd6, 0xa9, 0x3c))
    import math
    cx, cy, r1, r2 = w * 0.5, w * 0.42, 15 * SS, 6.5 * SS
    pts = [(cx + (r1 if k % 2 == 0 else r2) * math.sin(k * math.pi / 5), cy - (r1 if k % 2 == 0 else r2) * math.cos(k * math.pi / 5)) for k in range(10)]
    d.polygon(pts, outline=INK, width=2 * SS)
    for i, x1 in enumerate((50, 42, 54)):
        y = w * 0.68 + i * 6 * SS
        d.line((9 * SS, y, x1 * SS, y), fill=INK + (210,), width=2 * SS)
    return s


def place(item, cx, cy, angle, pin_col, pin_dy=None):
    rot = item.rotate(angle, resample=Image.BICUBIC, expand=True)
    # soft drop shadow, offset down-right
    sh = Image.new("RGBA", rot.size, (0, 0, 0, 0))
    sh.putalpha(rot.getchannel("A").point(lambda v: int(v * 0.35)))
    sh = sh.filter(ImageFilter.GaussianBlur(3 * SS))
    x, y = int(cx - rot.width / 2), int(cy - rot.height / 2)
    board.alpha_composite(sh, (x + 3 * SS, y + 4 * SS))
    board.alpha_composite(rot, (x, y))
    # pin near the top centre of the (rotated) item
    import math
    a = math.radians(angle)          # PIL rotates counter-clockwise; y points down
    oy = -(item.height / 2 - 8 * SS) if pin_dy is None else pin_dy
    px, py = cx + oy * math.sin(a), cy + oy * math.cos(a)
    d = ImageDraw.Draw(board)
    r = 6 * SS
    d.ellipse((px - r + 2 * SS, py - r + 3 * SS, px + r + 2 * SS, py + r + 3 * SS), fill=(0, 0, 0, 70))
    d.ellipse((px - r, py - r, px + r, py + r), fill=pin_col, outline=INK, width=SS + 1)
    d.ellipse((px - r * 0.55, py - r * 0.55, px - r * 0.05, py - r * 0.05), fill=(255, 255, 255, 170))


photos = [
    crop("store_shots/curva_bosque.png", 900, 470, 980),       # truck on the forest road
    crop("store_shots/casa_noche.png", 1250, 560, 1000),       # night delivery at the door
    crop("packages_review.png", 1280, 800, 1500),              # the parcels
    crop("store_shots/puente_lluvia.png", 980, 520, 1000),     # unloading in the rain
    crop("player_character_standing_crew.png", 620, 520, 560),  # the crew
    crop("store_shots/cruce_tren.png", 960, 600, 1000),        # level crossing
]
RED, BLUE, GREEN, YEL = (0xd9, 0x4a, 0x3d), (0x3d, 0x7f, 0xd9), (0x2f, 0x9e, 0x5b), WARNING
layout = [(88, 92, -7, RED), (212, 86, 5, BLUE), (334, 96, -3, YEL),
          (96, 244, 4, GREEN), (220, 250, -6, YEL), (340, 242, 8, RED)]
# papers first so photos overlap them a little
place(note(), 445 * SS, 118 * SS, -4, BLUE)
place(sticky(), 440 * SS, 262 * SS, 6, RED)
for photo, (x, y, ang, pin) in zip(photos, layout):
    place(polaroid(photo), x * SS, y * SS, ang, pin)

board = board.resize((512, 340), Image.LANCZOS)
board.convert("RGB").save(OUT)
print("ok")
