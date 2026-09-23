"""Paint the printed cardboard atlases for the delivery boxes.

    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_cargo_textures.py

Everything is drawn with PIL (no generation), so a box's print is exact and
repeatable: the same brand (docs/direccion-visual.md section 3: INK #1e2235,
YELLOW #ffc93c tape, CARDBOARD #e0a867, Lilita One + Nunito), real handling
symbols (this way up, fragile, keep dry), a barcode and the corrugated
board's certificate stamp on the bottom -- what a real parcel box carries.

One 2048 atlas per box variant, split into a 3x3 grid of cells. Each printed
face (front/back/right/left/bottom) gets drawn at its true aspect ratio,
centred in its cell; plain kraft (outside and inside), the flap print and the
brand tape fill the last cells. The UV rectangle of every region goes to
do-not-drop/assets/tools/cargo_layout.json, which
do-not-drop/assets/tools/build_cargo_packages.py (Blender) reads to map each
face -- this script is the single source of box sizes and layout.

Outputs:
    art/cargo/tx_cargo_box_<variant>_2048.png  (embedded into the GLBs, so
                                                kept outside the Godot project)
    do-not-drop/assets/textures/cargo/tx_cargo_shipping_label_512.png
    do-not-drop/assets/tools/cargo_layout.json
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ATLAS_DIR = ROOT / "art" / "cargo"
GAME = ROOT / "do-not-drop"
LABEL_OUT = GAME / "assets" / "textures" / "cargo" / "tx_cargo_shipping_label_512.png"
LAYOUT_OUT = GAME / "assets" / "tools" / "cargo_layout.json"
FONT_TITLE = GAME / "assets" / "fonts" / "LilitaOne-Regular.ttf"
FONT_TEXT = GAME / "assets" / "fonts" / "Nunito-Variable.ttf"

SIZE = 2048
GRID = 3
CELL = SIZE // GRID
PAD = 14

KRAFT = (214, 160, 98)       # CARDBOARD #e0a867, a touch darker once printed on
KRAFT_INNER = (206, 170, 120)
INK = (30, 34, 53)           # INK #1e2235
RED = (206, 60, 56)          # RED #ff5e5b as a printable flexo red
TAPE = (255, 201, 60)        # YELLOW #ffc93c

# Godot sizes from package_feedback.gd (x, height, z) -> width W, depth D,
# height H. Every variant is square in plan, so all four flaps are W x W/2.
VARIANTS = {
    "cube": {"dims": (0.65, 0.65, 0.65), "trap": "fragile"},
    "vented": {"dims": (0.65, 0.65, 0.65), "trap": "noisy"},
    "tall": {"dims": (0.42, 0.42, 0.98), "trap": "balance"},
    "flat": {"dims": (0.95, 0.95, 0.42), "trap": "growing_weight"},
}
CELLS = {
    "front": (0, 0), "back": (1, 0), "right": (2, 0),
    "left": (0, 1), "bottom": (1, 1), "flap": (2, 1),
    "outer": (0, 2), "inner": (1, 2), "tape": (2, 2),
}


def font(path: Path, size: int, weight: int | None = None) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(path), size)
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except (OSError, ValueError):
            pass
    return f


# --- Surfaces ---------------------------------------------------------------

def kraft(width: int, height: int, color: tuple, seed: int, flutes: bool = True) -> Image.Image:
    """Corrugated board: fibre noise, faint flute lines and a few scuffs."""
    rng = np.random.default_rng(seed)
    base = np.ones((height, width, 3), np.float32) * np.array(color, np.float32)
    fine = rng.normal(0.0, 1.0, (height, width)).astype(np.float32)
    blotch = np.array(Image.fromarray(((rng.random((max(height // 48, 2), max(width // 48, 2))) * 255).astype(np.uint8)))
                      .resize((width, height), Image.BICUBIC), np.float32) / 255.0 - 0.5
    shade = 1.0 + fine * 0.035 + blotch * 0.10
    if flutes:
        x = np.arange(width, dtype=np.float32)
        shade *= 1.0 + 0.025 * np.sin(x / 7.5 * math.tau)[None, :]
    img = np.clip(base * shade[..., None], 0, 255).astype(np.uint8)
    out = Image.fromarray(img, "RGB")
    # Fibres: short darker strokes.
    draw = ImageDraw.Draw(out, "RGBA")
    r = random.Random(seed)
    for _ in range(width * height // 3500):
        x0, y0 = r.uniform(0, width), r.uniform(0, height)
        a = r.uniform(0, math.pi)
        length = r.uniform(4, 16)
        draw.line([(x0, y0), (x0 + math.cos(a) * length, y0 + math.sin(a) * length)], fill=(90, 60, 30, r.randint(18, 40)), width=1)
    for _ in range(max(1, width * height // 400000)):
        cx, cy = r.uniform(0, width), r.uniform(0, height)
        rad = r.uniform(20, 60)
        draw.ellipse([cx - rad, cy - rad * 0.4, cx + rad, cy + rad * 0.4], fill=(70, 45, 20, 14))
    return out


def edge_wear(img: Image.Image, strength: float = 0.22) -> Image.Image:
    """Darkens the edges a little: handled corners get grubby first."""
    w, h = img.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy])
    falloff = np.clip(d / (min(w, h) * 0.08), 0, 1)
    shade = 1.0 - strength * (1.0 - falloff) ** 2
    arr = np.asarray(img).astype(np.float32) * shade[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def print_ink(base: Image.Image, ink: Image.Image, seed: int) -> Image.Image:
    """Flexo print: multiply the ink layer onto the board with a little
    dropout, so the print reads as ink on cardboard, not a sticker."""
    rng = np.random.default_rng(seed)
    b = np.asarray(base).astype(np.float32) / 255.0
    i = np.asarray(ink).astype(np.float32) / 255.0
    alpha = i[..., 3:4] * 0.92
    noise = rng.random(alpha.shape[:2]).astype(np.float32)[..., None]
    alpha = alpha * np.where(noise < 0.04, 0.35, 1.0) * (0.9 + 0.1 * noise)
    printed = b * i[..., :3]
    out = b * (1.0 - alpha) + printed * alpha
    return Image.fromarray(np.clip(out * 255.0, 0, 255).astype(np.uint8))


# --- Symbols (drawn on the RGBA ink layer) ------------------------------------

def text_center(draw, cx, cy, text, f, fill):
    box = draw.textbbox((0, 0), text, font=f)
    draw.text((cx - (box[2] - box[0]) / 2 - box[0], cy - (box[3] - box[1]) / 2 - box[1]), text, font=f, fill=fill)


def fit_font(draw, text, path, max_width, start, weight=None):
    size = start
    while size > 8:
        f = font(path, size, weight)
        box = draw.textbbox((0, 0), text, font=f)
        if box[2] - box[0] <= max_width:
            return f
        size -= 2
    return font(path, 8, weight)


def arrows_up(draw, cx, cy, s, fill):
    """ISO 780 "this way up": two arrows standing on a bar."""
    for dx in (-0.28, 0.28):
        x = cx + dx * s
        draw.rectangle([x - 0.07 * s, cy - 0.15 * s, x + 0.07 * s, cy + 0.36 * s], fill=fill)
        draw.polygon([(x - 0.2 * s, cy - 0.12 * s), (x + 0.2 * s, cy - 0.12 * s), (x, cy - 0.46 * s)], fill=fill)
    draw.rectangle([cx - 0.5 * s, cy + 0.4 * s, cx + 0.5 * s, cy + 0.5 * s], fill=fill)


def goblet(draw, cx, cy, s, fill, crack=True):
    """ISO 7000-0621 fragile: a wine glass, broken."""
    bowl = [(cx - 0.3 * s, cy - 0.5 * s), (cx + 0.3 * s, cy - 0.5 * s), (cx + 0.26 * s, cy - 0.12 * s),
            (cx + 0.12 * s, cy + 0.02 * s), (cx - 0.12 * s, cy + 0.02 * s), (cx - 0.26 * s, cy - 0.12 * s)]
    draw.polygon(bowl, fill=fill)
    draw.rectangle([cx - 0.035 * s, cy, cx + 0.035 * s, cy + 0.36 * s], fill=fill)
    draw.ellipse([cx - 0.22 * s, cy + 0.32 * s, cx + 0.22 * s, cy + 0.44 * s], fill=fill)
    if crack:
        pts = [(cx - 0.3 * s, cy - 0.34 * s), (cx - 0.1 * s, cy - 0.3 * s), (cx - 0.02 * s, cy - 0.18 * s),
               (cx + 0.1 * s, cy - 0.24 * s), (cx + 0.3 * s, cy - 0.2 * s)]
        draw.line(pts, fill=(0, 0, 0, 0), width=max(2, int(0.045 * s)))


def umbrella(draw, cx, cy, s, fill):
    """ISO 7000-0626 keep dry."""
    draw.pieslice([cx - 0.45 * s, cy - 0.42 * s, cx + 0.45 * s, cy + 0.28 * s], 180, 360, fill=fill)
    draw.rectangle([cx - 0.03 * s, cy - 0.08 * s, cx + 0.03 * s, cy + 0.36 * s], fill=fill)
    draw.arc([cx - 0.02 * s, cy + 0.26 * s, cx + 0.18 * s, cy + 0.46 * s], 0, 180, fill=fill, width=max(2, int(0.05 * s)))
    for dx, dy in ((-0.34, -0.5), (0.0, -0.58), (0.34, -0.5)):
        x, y = cx + dx * s, cy + dy * s
        draw.polygon([(x, y - 0.08 * s), (x - 0.04 * s, y), (x + 0.04 * s, y)], fill=fill)


def hen(draw, cx, cy, s, fill):
    """A hen in profile, for the live-content box."""
    draw.ellipse([cx - 0.36 * s, cy - 0.12 * s, cx + 0.26 * s, cy + 0.34 * s], fill=fill)          # body
    draw.polygon([(cx - 0.3 * s, cy + 0.02 * s), (cx - 0.52 * s, cy - 0.3 * s), (cx - 0.2 * s, cy - 0.02 * s)], fill=fill)  # tail
    draw.ellipse([cx + 0.1 * s, cy - 0.36 * s, cx + 0.34 * s, cy - 0.1 * s], fill=fill)           # head
    draw.rectangle([cx + 0.12 * s, cy - 0.2 * s, cx + 0.28 * s, cy + 0.05 * s], fill=fill)        # neck
    draw.polygon([(cx + 0.33 * s, cy - 0.26 * s), (cx + 0.46 * s, cy - 0.22 * s), (cx + 0.33 * s, cy - 0.18 * s)], fill=fill)  # beak
    for dx in (0.14, 0.2, 0.26):
        draw.ellipse([cx + (dx - 0.04) * s, cy - 0.44 * s, cx + (dx + 0.04) * s, cy - 0.34 * s], fill=fill)  # comb
    for dx in (-0.08, 0.06):
        draw.line([(cx + dx * s, cy + 0.32 * s), (cx + dx * s, cy + 0.48 * s)], fill=fill, width=max(2, int(0.04 * s)))
        draw.line([(cx + (dx - 0.06) * s, cy + 0.48 * s), (cx + (dx + 0.08) * s, cy + 0.48 * s)], fill=fill, width=max(2, int(0.035 * s)))


def weight_block(draw, cx, cy, s, fill, label="? KG"):
    draw.polygon([(cx - 0.32 * s, cy + 0.42 * s), (cx + 0.32 * s, cy + 0.42 * s), (cx + 0.2 * s, cy - 0.22 * s), (cx - 0.2 * s, cy - 0.22 * s)], fill=fill)
    draw.arc([cx - 0.16 * s, cy - 0.46 * s, cx + 0.16 * s, cy - 0.06 * s], 180, 360, fill=fill, width=max(3, int(0.07 * s)))
    text_center(draw, cx, cy + 0.12 * s, label, font(FONT_TITLE, max(10, int(0.24 * s))), (255, 255, 255, 0))


def spirit_level(draw, cx, cy, s, fill):
    draw.rounded_rectangle([cx - 0.5 * s, cy - 0.14 * s, cx + 0.5 * s, cy + 0.14 * s], radius=int(0.08 * s), fill=fill)
    draw.rounded_rectangle([cx - 0.18 * s, cy - 0.08 * s, cx + 0.18 * s, cy + 0.08 * s], radius=int(0.06 * s), fill=(0, 0, 0, 0))
    draw.ellipse([cx - 0.06 * s, cy - 0.06 * s, cx + 0.06 * s, cy + 0.06 * s], fill=fill)
    for dx in (-0.1, 0.1):
        draw.line([(cx + dx * s, cy - 0.1 * s), (cx + dx * s, cy + 0.1 * s)], fill=fill, width=max(2, int(0.02 * s)))


def barcode(draw, x, y, w, h, seed, fill):
    r = random.Random(seed)
    pos = x
    while pos < x + w:
        bar = r.choice((1, 1, 2, 3)) * max(1, w / 95)
        if r.random() < 0.55:
            draw.rectangle([pos, y, pos + bar, y + h], fill=fill)
        pos += bar + max(1, w / 95) * r.choice((1, 1, 2))


def logo(draw, cx, cy, width, fill):
    """Brand lockup in one ink: "TAKE MY" over a solid bar with PACKAGE
    knocked out of it -- the menu logo, flattened for flexo print."""
    f_small = fit_font(draw, "TAKE MY", FONT_TITLE, width * 0.55, int(width * 0.2))
    f_big = fit_font(draw, "PACKAGE", FONT_TITLE, width * 0.84, int(width * 0.3))
    top_box = draw.textbbox((0, 0), "TAKE MY", font=f_small)
    big_box = draw.textbbox((0, 0), "PACKAGE", font=f_big)
    th = top_box[3] - top_box[1]
    bh = big_box[3] - big_box[1]
    bar_h = bh * 1.45
    total = th + bar_h * 1.08
    y0 = cy - total / 2
    text_center(draw, cx - width * 0.12, y0 + th / 2, "TAKE MY", f_small, fill)
    bar_top = y0 + th * 1.15
    draw.rounded_rectangle([cx - width / 2, bar_top, cx + width / 2, bar_top + bar_h], radius=int(bar_h * 0.18), fill=fill)
    text_center(draw, cx, bar_top + bar_h / 2, "PACKAGE", f_big, (0, 0, 0, 0))
    return bar_top + bar_h


# --- Faces ----------------------------------------------------------------------

def face(variant: str, name: str, w: int, h: int, px_per_m: float, seed: int) -> Image.Image:
    base = edge_wear(kraft(w, h, KRAFT, seed))
    ink = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)
    m = px_per_m  # pixels per metre, so symbols keep a real-world size
    trap = VARIANTS[variant]["trap"]
    cx = w / 2
    body = font(FONT_TEXT, int(0.026 * m), 800)

    if name == "front":
        logo_w = min(w * 0.78, 0.36 * m)
        # ImageDraw writes RGBA straight through, so (0,0,0,0) knocks the
        # word out of the bar instead of drawing nothing.
        logo(d, cx, h * 0.2, logo_w, INK + (255,))
        if trap == "fragile":
            y = h * 0.62
            d.rounded_rectangle([cx - 0.24 * m, y - 0.14 * m, cx + 0.24 * m, y + 0.14 * m], radius=int(0.02 * m), outline=RED + (255,), width=int(0.012 * m))
            goblet(d, cx - 0.14 * m, y, 0.2 * m, RED + (255,))
            f = font(FONT_TITLE, int(0.075 * m))
            d.text((cx - 0.05 * m, y - 0.07 * m), "FRÁGIL", font=f, fill=RED + (255,))
            d.text((cx - 0.05 * m, y + 0.02 * m), "MANIPULAR CON CUIDADO", font=font(FONT_TEXT, int(0.018 * m), 900), fill=RED + (255,))
        elif trap == "noisy":
            y = h * 0.64
            hen(d, cx - 0.15 * m, y, 0.22 * m, RED + (255,))
            f = font(FONT_TITLE, int(0.06 * m))
            d.text((cx - 0.02 * m, y - 0.09 * m), "CONTENIDO", font=f, fill=RED + (255,))
            d.text((cx - 0.02 * m, y - 0.025 * m), "VIVO", font=font(FONT_TITLE, int(0.08 * m)), fill=RED + (255,))
            d.text((cx - 0.02 * m, y + 0.07 * m), "NO AGITAR · NO TAPAR", font=font(FONT_TEXT, int(0.017 * m), 900), fill=INK + (255,))
        elif trap == "balance":
            y = h * 0.55
            arrows_up(d, cx, y, 0.2 * m, RED + (255,))
            f = fit_font(d, "MANTENER", FONT_TITLE, w * 0.8, int(0.07 * m))
            text_center(d, cx, y + 0.17 * m, "MANTENER", f, RED + (255,))
            text_center(d, cx, y + 0.24 * m, "VERTICAL", f, RED + (255,))
            spirit_level(d, cx, h * 0.87, 0.24 * m, INK + (255,))
        else:  # growing_weight
            y = h * 0.62
            weight_block(d, cx - 0.22 * m, y, 0.18 * m, RED + (255,))
            f = font(FONT_TITLE, int(0.07 * m))
            d.text((cx - 0.1 * m, y - 0.08 * m), "PESADO", font=f, fill=RED + (255,))
            d.text((cx - 0.1 * m, y + 0.0 * m), "LEVANTAR ENTRE DOS", font=font(FONT_TEXT, int(0.022 * m), 900), fill=INK + (255,))
            d.text((cx - 0.1 * m, y + 0.035 * m), "El peso puede variar durante el viaje", font=font(FONT_TEXT, int(0.015 * m), 700), fill=INK + (255,))
        return print_ink(base, ink, seed)

    wide = w > h * 1.6
    if name == "back" and wide:
        # Low, wide face: symbols | brand + barcode | recycling, side by side.
        sym = 0.08 * m
        for i, draw_symbol in enumerate((arrows_up, goblet, umbrella)):
            sx = w * 0.08 + sym * 0.7 + i * sym * 1.25
            draw_symbol(d, sx, h * 0.45, sym, INK + (255,))
            d.rectangle([sx - sym * 0.58, h * 0.45 - sym * 0.62, sx + sym * 0.58, h * 0.45 + sym * 0.62], outline=INK + (255,), width=max(2, int(0.004 * m)))
        mid = w * 0.6
        text_center(d, mid, h * 0.2, "ENVÍOS · TAKE MY PACKAGE", fit_font(d, "ENVÍOS · TAKE MY PACKAGE", FONT_TITLE, w * 0.4, int(0.04 * m)), INK + (255,))
        text_center(d, mid, h * 0.32, "Si llega roto, no fue el conductor.", body, INK + (255,))
        bw = w * 0.28
        barcode(d, mid - bw / 2, h * 0.44, bw, 0.07 * m, seed, INK + (255,))
        text_center(d, mid, h * 0.44 + 0.09 * m, "TMP %04d %04d" % (seed * 37 % 10000, seed * 91 % 10000), font(FONT_TEXT, int(0.022 * m), 900), INK + (255,))
        text_center(d, w * 0.88, h * 0.5, "RECICLABLE", font(FONT_TEXT, int(0.016 * m), 800), INK + (255,))
        return print_ink(base, ink, seed)

    if name in ("right", "left") and wide:
        arrows_up(d, w * 0.25, h * 0.4, 0.13 * m, INK + (255,))
        text_center(d, w * 0.25, h * 0.4 + 0.11 * m, "ESTE LADO ARRIBA", font(FONT_TITLE, int(0.03 * m)), INK + (255,))
        hx, hy = w * 0.68, h * 0.42
        d.rounded_rectangle([hx - 0.07 * m, hy - 0.022 * m, hx + 0.07 * m, hy + 0.022 * m], radius=int(0.022 * m), fill=(24, 16, 10, 255))
        d.arc([hx - 0.07 * m, hy - 0.03 * m, hx + 0.07 * m, hy + 0.03 * m], 20, 160, fill=(60, 42, 26, 255), width=int(0.006 * m))
        text_center(d, hx, hy + 0.07 * m, "AGARRAR ACÁ", font(FONT_TEXT, int(0.02 * m), 900), INK + (255,))
        return print_ink(base, ink, seed)

    if name == "back":
        y = h * 0.28
        sym = 0.09 * m
        gap = sym * 1.25
        start = cx - gap
        arrows_up(d, start, y, sym, INK + (255,))
        goblet(d, start + gap, y, sym, INK + (255,))
        umbrella(d, start + gap * 2, y + sym * 0.08, sym, INK + (255,))
        for i in range(3):
            d.rectangle([start + gap * i - sym * 0.58, y - sym * 0.62, start + gap * i + sym * 0.58, y + sym * 0.62], outline=INK + (255,), width=max(2, int(0.004 * m)))
        text_center(d, cx, h * 0.48, "ENVÍOS · TAKE MY PACKAGE", fit_font(d, "ENVÍOS · TAKE MY PACKAGE", FONT_TITLE, w * 0.86, int(0.045 * m)), INK + (255,))
        text_center(d, cx, h * 0.55, "Si llega roto, no fue el conductor.", body, INK + (255,))
        bw = min(w * 0.6, 0.26 * m)
        barcode(d, cx - bw / 2, h * 0.64, bw, 0.07 * m, seed, INK + (255,))
        code = "TMP %04d %04d" % (seed * 37 % 10000, seed * 91 % 10000)
        text_center(d, cx, h * 0.64 + 0.09 * m, code, font(FONT_TEXT, int(0.022 * m), 900), INK + (255,))
        # Recycling mark: a ring of three chevrons.
        rcx, rcy, rr = cx, h * 0.86, 0.035 * m
        d.ellipse([rcx - rr, rcy - rr, rcx + rr, rcy + rr], outline=INK + (255,), width=max(2, int(0.006 * m)))
        for k in range(3):
            a = -math.pi / 2 + k * math.tau / 3
            px, py = rcx + math.cos(a) * rr, rcy + math.sin(a) * rr
            d.polygon([(px + math.cos(a + 1.9) * rr * 0.45, py + math.sin(a + 1.9) * rr * 0.45),
                       (px + math.cos(a - 1.9) * rr * 0.45, py + math.sin(a - 1.9) * rr * 0.45),
                       (px + math.cos(a + math.pi / 2) * rr * 0.55, py + math.sin(a + math.pi / 2) * rr * 0.55)], fill=INK + (255,))
        text_center(d, cx, h * 0.86 + 0.06 * m, "CARTÓN 100% RECICLABLE", font(FONT_TEXT, int(0.016 * m), 800), INK + (255,))
        return print_ink(base, ink, seed)

    if name in ("right", "left"):
        arrows_up(d, cx, h * 0.26, 0.14 * m, INK + (255,))
        label = "ESTE LADO ARRIBA"
        text_center(d, cx, h * 0.26 + 0.12 * m, label, fit_font(d, label, FONT_TITLE, w * 0.86, int(0.04 * m)), INK + (255,))
        if trap == "noisy":
            # Printed-and-scored breathing holes: dark punch-outs with a torn rim.
            for i, (fx, fy) in enumerate(((0.3, 0.6), (0.7, 0.6), (0.5, 0.8))):
                hx, hy, hr = w * fx, h * fy, 0.045 * m
                d.ellipse([hx - hr * 1.12, hy - hr * 1.12, hx + hr * 1.12, hy + hr * 1.12], fill=(150, 110, 70, 120))
                d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(24, 16, 10, 255))
                d.chord([hx - hr, hy - hr, hx + hr, hy + hr], 200, 340, fill=(60, 42, 26, 255))
            text_center(d, cx, h * 0.93, "RESPIRADEROS", font(FONT_TEXT, int(0.02 * m), 900), INK + (255,))
        elif trap == "growing_weight":
            # Hand holds.
            d.rounded_rectangle([cx - 0.07 * m, h * 0.5 - 0.022 * m, cx + 0.07 * m, h * 0.5 + 0.022 * m], radius=int(0.022 * m), fill=(24, 16, 10, 255))
            d.arc([cx - 0.07 * m, h * 0.5 - 0.03 * m, cx + 0.07 * m, h * 0.5 + 0.03 * m], 20, 160, fill=(60, 42, 26, 255), width=int(0.006 * m))
        elif trap == "fragile":
            goblet(d, cx, h * 0.68, 0.16 * m, RED + (255,))
            text_center(d, cx, h * 0.84, "FRÁGIL", font(FONT_TITLE, int(0.05 * m)), RED + (255,))
        else:
            spirit_level(d, cx, h * 0.62, min(w * 0.7, 0.24 * m), INK + (255,))
            text_center(d, cx, h * 0.72, "NO INCLINAR", font(FONT_TITLE, int(0.04 * m)), RED + (255,))
        return print_ink(base, ink, seed)

    if name == "bottom":
        # Box maker's certificate, the round stamp every real carton has.
        r = min(w, h) * 0.22
        d.ellipse([cx - r, h / 2 - r, cx + r, h / 2 + r], outline=INK + (255,), width=max(3, int(r * 0.04)))
        d.ellipse([cx - r * 0.86, h / 2 - r * 0.86, cx + r * 0.86, h / 2 + r * 0.86], outline=INK + (255,), width=max(2, int(r * 0.02)))
        lines = ["CARTÓN CORRUGADO", "DOBLE ONDA", "ECT 44", "CAJAS TMP S.A.", "LÍMITE 30 KG"]
        f = font(FONT_TEXT, max(10, int(r * 0.1)), 900)
        for i, line in enumerate(lines):
            text_center(d, cx, h / 2 - r * 0.44 + i * r * 0.22, line, f, INK + (255,))
        return print_ink(base, ink, seed)

    raise ValueError(name)


def flap_print(w: int, h: int, seed: int) -> Image.Image:
    base = edge_wear(kraft(w, h, KRAFT, seed), 0.15)
    ink = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)
    # The flap's free edge (where the tape and the cut go) is the top of the cell.
    for x in range(int(w * 0.06), int(w * 0.94), 28):
        d.line([(x, h * 0.16), (x + 14, h * 0.16)], fill=INK + (255,), width=4)
    text_center(d, w / 2, h * 0.28, "ABRIR POR ACÁ", font(FONT_TITLE, int(h * 0.075)), INK + (255,))
    text_center(d, w / 2, h * 0.37, "Revisá el contenido y volvé a cerrar antes de entregar",
                fit_font(d, "Revisá el contenido y volvé a cerrar antes de entregar", FONT_TEXT, w * 0.86, int(h * 0.04), 800), INK + (255,))
    logo(d, w / 2, h * 0.66, w * 0.42, INK + (255,))
    return print_ink(base, ink, seed)


TAPE_ROW = 44  # px: one strip of tape across the cell, text readable at 5 cm wide


def tape(w: int, h: int) -> Image.Image:
    """Brand packing tape: yellow, glossy streaks, the logo repeating along
    rows of TAPE_ROW px. A tape piece maps onto a single row (see the
    "tape_row" region), at its own length, so the lettering never stretches."""
    img = Image.new("RGB", (w, h), TAPE)
    d = ImageDraw.Draw(img, "RGBA")
    f = font(FONT_TITLE, int(TAPE_ROW * 0.58))
    word = "TAKE MY PACKAGE"
    step = d.textbbox((0, 0), word, font=f)[2] + TAPE_ROW * 1.2
    for row in range(h // TAPE_ROW):
        y0 = row * TAPE_ROW
        d.line([(0, y0 + TAPE_ROW * 0.2), (w, y0 + TAPE_ROW * 0.2)], fill=(255, 255, 255, 60), width=2)
        d.line([(0, y0 + 1), (w, y0 + 1)], fill=(150, 100, 0, 90), width=2)
        x = -(row % 3) * step / 3
        while x < w:
            d.text((x, y0 + TAPE_ROW * 0.18), word, font=f, fill=INK + (230,))
            dot = x + step - TAPE_ROW * 0.6
            d.ellipse([dot - 3, y0 + TAPE_ROW * 0.5 - 3, dot + 3, y0 + TAPE_ROW * 0.5 + 3], fill=INK + (230,))
            x += step
    return img.filter(ImageFilter.GaussianBlur(0.5))


def shipping_label() -> Image.Image:
    w, h = 512, 320
    img = Image.new("RGB", (w, h), (252, 246, 232))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, 54], fill=INK)
    d.text((18, 8), "TAKE MY PACKAGE", font=font(FONT_TITLE, 34), fill=TAPE)
    d.text((w - 150, 16), "EXPRESS 24H", font=font(FONT_TEXT, 22, 900), fill=(252, 246, 232))
    small = font(FONT_TEXT, 17, 900)
    d.text((18, 66), "PARA:", font=small, fill=INK)
    d.text((18, 158), "CONTENIDO DECLARADO:", font=small, fill=INK)
    for y in (98, 124):
        d.line([(80, y), (w - 170, y)], fill=(150, 140, 125), width=2)
    # Route/zone box, the big letter a sorter reads from across the depot.
    d.rectangle([w - 150, 66, w - 18, 150], outline=INK, width=4)
    text_center(d, w - 84, 96, "RUTA", font(FONT_TEXT, 16, 900), INK)
    text_center(d, w - 84, 128, "R-7", font(FONT_TITLE, 36), INK)
    d.line([(0, 234), (w, 234)], fill=INK, width=3)
    barcode(d, 18, 246, 300, 52, 7, INK)
    d.text((18, 298), "TMP 0417 2291 AR", font=font(FONT_TEXT, 15, 800), fill=INK)
    d.rectangle([w - 150, 246, w - 18, 306], fill=(214, 70, 62))
    text_center(d, w - 84, 276, "PRIORIDAD", font(FONT_TITLE, 24), (252, 246, 232))
    return img


# --- Atlas ----------------------------------------------------------------------

def fit_rect(cell, aspect):
    """Largest rect of this aspect (w/h) inside the padded cell, centred."""
    cx, cy = cell
    x0, y0 = cx * CELL + PAD, cy * CELL + PAD
    size = CELL - PAD * 2
    if aspect >= 1.0:
        w, h = size, size / aspect
    else:
        w, h = size * aspect, size
    x = x0 + (size - w) / 2
    y = y0 + (size - h) / 2
    return int(round(x)), int(round(y)), int(round(w)), int(round(h))


def to_uv(rect):
    x, y, w, h = rect
    return [x / SIZE, 1.0 - (y + h) / SIZE, (x + w) / SIZE, 1.0 - y / SIZE]


def build_variant(variant: str, index: int) -> dict:
    W, D, H = VARIANTS[variant]["dims"]
    atlas = Image.new("RGB", (SIZE, SIZE), KRAFT)
    face_sizes = {"front": (W, H), "back": (W, H), "right": (D, H), "left": (D, H), "bottom": (W, D)}
    regions = {}
    biggest = max(max(s) for s in face_sizes.values())
    px_per_m = (CELL - PAD * 2) / biggest
    for i, (name, (fw, fh)) in enumerate(face_sizes.items()):
        rect = fit_rect(CELLS[name], fw / fh)
        # Same scale on every face of a box, so a symbol is the same size
        # on its front and its side.
        img = face(variant, name, rect[2], rect[3], px_per_m, seed=index * 10 + i + 1)
        atlas.paste(img, rect[:2])
        regions[name] = to_uv(rect)
    # Plain surfaces fill the whole cell (minus padding): stretching noise is harmless.
    for name, maker in (("flap", lambda w, h: flap_print(w, h, index * 10 + 7)),
                        ("outer", lambda w, h: edge_wear(kraft(w, h, KRAFT, index * 10 + 8), 0.12)),
                        ("inner", lambda w, h: kraft(w, h, KRAFT_INNER, index * 10 + 9)),
                        ("tape", tape)):
        rect = fit_rect(CELLS[name], 1.0)
        atlas.paste(maker(rect[2], rect[3]), rect[:2])
        regions[name] = to_uv(rect)
    x, y, w, _h = fit_rect(CELLS["tape"], 1.0)
    regions["tape_row"] = to_uv((x, y + TAPE_ROW, w, TAPE_ROW))
    ATLAS_DIR.mkdir(parents=True, exist_ok=True)
    out = ATLAS_DIR / ("tx_cargo_box_%s_2048.png" % variant)
    atlas.save(out, optimize=True)
    print("wrote", out.relative_to(ROOT))
    return {"dims": [W, D, H], "trap": VARIANTS[variant]["trap"], "texture": str(out.relative_to(ROOT)).replace("\\", "/"), "regions": regions}


def main() -> None:
    layout = {name: build_variant(name, i) for i, name in enumerate(VARIANTS)}
    LAYOUT_OUT.write_text(json.dumps(layout, indent=2), encoding="utf-8")
    print("wrote", LAYOUT_OUT.relative_to(ROOT))
    LABEL_OUT.parent.mkdir(parents=True, exist_ok=True)
    shipping_label().save(LABEL_OUT, optimize=True)
    print("wrote", LABEL_OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
