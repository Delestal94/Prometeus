"""Generate the tileable detail textures used on terrain and low-poly models.

    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_detail_textures.py [name ...]

Each texture is generated with ComfyUI + Z-Image Turbo, then turned into a
*detail map* (see to_detail): greyscale grain only (a high-pass drops the big
light patches that make a tile visible), made seamless with a variance-
preserving cross-fade against a half-offset copy, and normalised to the same
strength around DETAIL_MEAN, so it only modulates brightness.

The colour always comes from the game's palette (material albedo or terrain
shader); the texture adds grain -- the subtle PEAK look rather than
photographic surfaces. Raw generations stay in art/concept/textures/.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageFilter, ImageOps

sys.path.insert(0, str(Path(__file__).parent))
from comfy_generate import generate  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "art" / "concept" / "textures"
OUT = ROOT / "do-not-drop" / "assets" / "textures" / "detail"
SIZE = 512
DETAIL_MEAN = 0.86   # average brightness the map multiplies by
DETAIL_SPREAD = 0.28  # darkest-to-lightest range around that mean

STYLE = ("Seamless tileable texture, perfectly flat top-down orthographic view, even flat lighting, "
         "no shadows, no perspective, no objects, no text. Stylized hand-painted game texture with "
         "soft simple shapes, low contrast, clean and readable, fills the whole frame edge to edge.")

TEXTURES = {
    "asphalt": ("Worn country road asphalt with fine grain, a few small hairline cracks and subtle patches.", 11),
    "grass": ("Short meadow grass seen from above, small soft clumps of blades, tiny variations in tone.", 12),
    "earth": ("Dry packed dirt path with small pebbles and fine soil grain.", 13),
    "gravel": ("Loose rounded gravel stones of mixed small sizes packed together.", 14),
    "wood_planks": ("Horizontal weathered wooden planks with gentle wood grain and thin gaps between boards.", 15),
    "roof_shingles": ("Rows of overlapping rectangular roof shingles, slightly irregular edges.", 16),
    "plaster": ("Smooth painted plaster wall with very subtle trowel marks and faint speckles.", 17),
    "bark": ("Vertical tree bark with long soft grooves and ridges.", 18),
    "foliage": ("Dense cluster of small soft leaves overlapping, seen from above.", 19),
    "stone": ("Rough natural stone surface with soft irregular facets and speckles.", 20),
}


def make_seamless(image: Image.Image) -> Image.Image:
    w, h = image.size
    shifted = _roll(image, w // 2, h // 2)
    # Mask: 1 in the middle (keep the original), 0 at the borders (take the
    # rolled copy, whose borders are the original's continuous interior).
    mask = Image.new("L", (w, h), 0)
    margin = w // 4
    inner = Image.new("L", (w - 2 * margin, h - 2 * margin), 255)
    mask.paste(inner, (margin, margin))
    mask = mask.filter(ImageFilter.GaussianBlur(margin * 0.6))
    return Image.composite(image, shifted, mask)


def _roll(image: Image.Image, dx: int, dy: int) -> Image.Image:
    w, h = image.size
    out = Image.new(image.mode, (w, h))
    for x0, y0 in ((0, 0), (-w, 0), (0, -h), (-w, -h)):
        out.paste(image, (x0 + dx, y0 + dy))
    return out


def to_detail(raw: Image.Image) -> Image.Image:
    """Greyscale grain from the *raw* (not yet seamless) generation."""
    import numpy as np
    grey = np.asarray(ImageOps.grayscale(raw), dtype=np.float32) / 255.0
    size = grey.shape[0]
    # High-pass: subtract a wide blur (mirror-padded so the borders behave).
    # Big soft light patches are what made a repeated tile read as blocks;
    # only the grain should survive.
    padded = np.pad(grey, size // 4, mode="reflect")
    blurred = Image.fromarray((padded * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(size / 10))
    low = np.asarray(blurred, dtype=np.float32)[size // 4:size // 4 + size, size // 4:size // 4 + size] / 255.0
    grain = grey - low
    grain -= grain.mean()
    # Seamless via a variance-preserving cross-fade with a half-offset copy:
    # a plain blend of two zero-mean grains loses contrast where they mix,
    # which is exactly the "cross" that showed when tiled. Dividing by
    # sqrt(m^2 + (1-m)^2) keeps the grain equally strong everywhere.
    rolled = np.roll(grain, (size // 2, size // 2), axis=(0, 1))
    mask_image = Image.new("L", (size, size), 0)
    margin = size // 4
    mask_image.paste(Image.new("L", (size - 2 * margin, size - 2 * margin), 255), (margin, margin))
    m = np.asarray(mask_image.filter(ImageFilter.GaussianBlur(margin * 0.6)), dtype=np.float32) / 255.0
    grain = (grain * m + rolled * (1.0 - m)) / np.sqrt(m * m + (1.0 - m) * (1.0 - m))
    # Same amount of detail for every texture: normalise by its own spread.
    grain = grain / max(float(grain.std()), 1e-4)
    detail = np.clip(DETAIL_MEAN + grain * (DETAIL_SPREAD / 4.0), 0.0, 1.0)
    return Image.fromarray((detail * 255).round().astype(np.uint8), "L")


def main(names: list[str]) -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for name in names or list(TEXTURES):
        subject, seed = TEXTURES[name]
        raw_path = generate(subject + " " + STYLE, 1024, 1024, seed, "tex_" + name, RAW)[0]
        image = Image.open(raw_path).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
        make_seamless(image).save(RAW / f"tex_{name}_seamless.png")  # colour preview only
        to_detail(image).save(OUT / f"tx_detail_{name}_{SIZE}.png", optimize=True)
        print("detail", name, flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
