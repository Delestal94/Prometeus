"""Generate the tileable detail textures used on terrain and low-poly models.

    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_detail_textures.py [name ...]
    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_detail_textures.py --from-raw [name ...]
    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_detail_textures.py --check [file-or-name ...]

Default mode generates each texture with ComfyUI + Z-Image Turbo (the raw
1024x1024 image is kept as art/concept/textures/tex_<name>_seed<N>.png).
--from-raw skips ComfyUI and rebuilds the maps from those raw files, so the
output is fully reproducible. Without names, all eleven are processed.

Each raw image is turned into a *detail map* (see to_detail): greyscale grain
only, normalised to the same strength around DETAIL_MEAN so it only modulates
brightness. Tiling, in three periodic steps (nothing ever cuts the inside of
the tile, so there is no cross at 256):
  1. periodic + smooth decomposition (Moisan 2011, FFT): keep the periodic
     component, which has no brightness jump at the wrap border;
  2. high-pass with a *circular* Gaussian blur (drops the big light patches
     that make a tile visible; wrapping keeps it periodic);
  3. hide_border: Moisan removes the jump in brightness but not the change of
     *content* across the border (it shows on fine noise such as plaster as a
     faint line every tile). A narrow band (SEAM_BAND px each side of the
     border) is cross-faded, variance-preserving, with the half-shifted copy;
     the weight is exactly 0 at the border and exactly 1 from SEAM_BAND on,
     so the copy's own border (the centre lines) is never visible. One 1-D
     pass per axis. Skipped (NO_BAND) for textures with real joints, where a
     cross-fade would ghost the joints: their border is a joint line anyway.
Boards and shingles (STAGGER) then have each row rolled sideways by its own
offset (stagger_rows), so their ends do not form one vertical line per tile.
Concrete (MARKED) gets its slab marks drawn by code on top (concrete_marks):
the AI grain has no joints that land exactly on the tile border, and the
joints must fall on the shed's metre grid, so they are drawn, seeded.

--check prints the seam metric (seam_ratio) plus mean and std of each map:
mean absolute gradient across the centre line (col/row 255|256) and across
the wrap border (511 -> 0), divided by the median gradient of the other
columns/rows. Values near 1 mean "no visible line". Without arguments it
checks the eleven files in OUT.

The colour always comes from the game's palette (material albedo or terrain
shader); the texture adds grain -- the subtle PEAK look rather than
photographic surfaces.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).parent))

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "art" / "concept" / "textures"
OUT = ROOT / "do-not-drop" / "assets" / "textures" / "detail"
SIZE = 512
DETAIL_MEAN = 0.86   # average brightness the map multiplies by
DETAIL_SPREAD = 0.28  # darkest-to-lightest range around that mean
BLUR_SIGMA = SIZE / 10  # high-pass cut: patches wider than this are removed
SEAM_BAND = SIZE // 16  # half-width of the cross-fade around the wrap border
NO_BAND = {"wood_planks", "roof_shingles"}  # drawn joints: a cross-fade ghosts them
STAGGER = {"wood_planks", "roof_shingles"}  # rows rolled apart so the joints do not line up
MARKED = {"concrete"}  # slab joints, wheel scuffs and stains drawn on top (concrete_marks)
JOINT_DEPTH = 0.30  # how much darker the saw-cut joint is than the mean (a clear line, not a gap)
STAGGER_GAP = 0.15  # minimum offset change between neighbouring rows (fraction of width)

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
    "concrete": ("Flat smooth grey concrete surface swatch filling the frame, very fine pores and tiny "
                 "speckles, faint soft blotches, uniform, no joints, no lines, no cracks, no horizon.", 21),
}


def periodic_component(u: np.ndarray) -> np.ndarray:
    """Periodic part of the periodic + smooth decomposition (Moisan 2011).

    The smooth part solves a Poisson equation whose source is the jump across
    the wrap border; subtracting it leaves an image that tiles with no border
    discontinuity and keeps all the interior detail.
    """
    h, w = u.shape
    u = u.astype(np.float64)
    v = np.zeros_like(u)
    dx = u[:, -1] - u[:, 0]  # jump across the wrap border
    dy = u[-1, :] - u[0, :]
    v[:, 0] += dx
    v[:, -1] -= dx
    v[0, :] += dy
    v[-1, :] -= dy
    cx = np.cos(2.0 * np.pi * np.arange(w) / w)
    cy = np.cos(2.0 * np.pi * np.arange(h) / h)
    denom = 2.0 * cx[None, :] + 2.0 * cy[:, None] - 4.0
    denom[0, 0] = 1.0
    s_hat = np.fft.fft2(v) / denom
    s_hat[0, 0] = 0.0
    return u - np.real(np.fft.ifft2(s_hat))


def circular_blur(u: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur with wrap-around borders (done in the frequency domain)."""
    h, w = u.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    gauss = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(u) * gauss))


def make_seamless(image: Image.Image) -> Image.Image:
    """Colour preview: periodic component of every channel."""
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
    out = np.stack([periodic_component(rgb[..., c]) for c in range(3)], axis=-1)
    return Image.fromarray(np.clip(out, 0, 255).round().astype(np.uint8), "RGB")


def hide_border(grain: np.ndarray, band: int) -> np.ndarray:
    """Cross-fade a band around the wrap border with the half-shifted copy.

    `grain` must be periodic and zero-mean. Per axis, the original's weight m
    is 0 on the border line and 1 from `band` pixels away on (so it is 1 on
    the centre line, where the shifted copy has its own border); dividing by
    sqrt(m^2 + (1-m)^2) keeps the grain equally strong where both mix.
    """
    for axis in (1, 0):
        n = grain.shape[axis]
        d = np.minimum(np.arange(n), n - np.arange(n)).astype(np.float64)
        m = 0.5 - 0.5 * np.cos(np.pi * np.clip(d / band, 0.0, 1.0))
        m = m[None, :] if axis == 1 else m[:, None]
        shifted = np.roll(grain, n // 2, axis=axis)
        grain = (grain * m + shifted * (1.0 - m)) / np.sqrt(m * m + (1.0 - m) ** 2)
    return grain


def stagger_rows(grain: np.ndarray, seed: int) -> np.ndarray:
    """Roll each board/shingle row sideways by its own offset.

    The raw boards all end on the wrap border, so every tile showed one
    vertical joint crossing all of them. Rows are cut at the horizontal joints
    (local minima of the row mean, the wrap border included), so each cut lies
    on a joint and the tile stays periodic. The offsets are spread evenly over
    0.2-0.8 of the width (so no two board ends share a column) and shuffled
    until neighbouring rows differ by STAGGER_GAP. Only a permutation of
    pixels: mean and std do not change.
    """
    h, w = grain.shape
    r = circular_blur(grain, 1.0).mean(axis=1)
    win = max(2, h // 64)
    near = np.stack([np.roll(r, k) for k in range(-win, win + 1)])
    deep = r < np.median(r) - 0.5 * (np.median(r) - r.min())
    cuts = np.flatnonzero((r <= near.min(axis=0)) & deep)
    if len(cuts) < 2:
        return grain
    rng = np.random.default_rng(seed)
    n = len(cuts)
    offsets = 0.2 + 0.6 * (np.arange(n) + rng.uniform(0.25, 0.75, n)) / n
    for _ in range(1000):
        order = rng.permutation(offsets)
        if np.abs(order - np.roll(order, 1)).min() >= STAGGER_GAP:
            break
    out = grain.copy()
    for i, start in enumerate(cuts):
        rows = np.arange(start, cuts[(i + 1) % n] + (h if i + 1 == n else 0)) % h
        out[rows] = np.roll(grain[rows], round(order[i] * w), axis=1)
    return out


def to_detail(raw: Image.Image, band: int = SEAM_BAND, stagger: int = 0) -> Image.Image:
    """Greyscale, tileable grain from the raw (not yet seamless) generation."""
    grey = np.asarray(ImageOps.grayscale(raw), dtype=np.float64) / 255.0
    scale = grey.shape[0] / SIZE
    grey = periodic_component(grey)
    # High-pass: big soft light patches are what made a repeated tile read as
    # blocks; only the grain should survive. The blur wraps, so it stays periodic.
    grain = grey - circular_blur(grey, BLUR_SIGMA * scale)
    grain -= grain.mean()
    if band:
        grain = hide_border(grain, max(1, round(band * scale)))
    if stagger:
        grain = stagger_rows(grain, stagger)
    # Same amount of detail for every texture: normalise by its own spread.
    grain = grain / max(float(grain.std()), 1e-4)
    detail = np.clip(DETAIL_MEAN + grain * (DETAIL_SPREAD / 4.0), 0.0, 1.0)
    return Image.fromarray((detail * 255).round().astype(np.uint8), "L")


def seam_ratio(image: Image.Image | np.ndarray) -> dict[str, float]:
    """Seam metric of a square tile.

    For columns and rows separately: mean |gradient| across the centre line
    (n/2-1 | n/2) and across the wrap border (n-1 -> 0), divided by the
    median of the mean |gradient| of every other adjacent pair. "center" and
    "border" are the worse of the two axes; also returns mean/std in 0..1.
    """
    a = np.asarray(image, dtype=np.float64)
    if a.ndim == 3:
        a = a.mean(axis=2)
    n = a.shape[0]
    c = n // 2
    result: dict[str, float] = {}
    for axis, label in ((1, "col"), (0, "row")):
        wrapped = np.concatenate([a, a.take([0], axis=axis)], axis=axis)
        grad = np.abs(np.diff(wrapped, axis=axis)).mean(axis=1 - axis)  # index i: i -> i+1
        med = float(np.median(np.delete(grad, [c - 1, n - 1])))
        result[label + "_center"] = float(grad[c - 1]) / med
        result[label + "_border"] = float(grad[n - 1]) / med
    a01 = a / 255.0
    return {
        "center": max(result["col_center"], result["row_center"]),
        "border": max(result["col_border"], result["row_border"]),
        **result,
        "mean": float(a01.mean()),
        "std": float(a01.std()),
    }


def _wrapped_distance(a: np.ndarray, b: float, n: int) -> np.ndarray:
    d = np.abs(a - b) % n
    return np.minimum(d, n - d)


def concrete_marks(detail: Image.Image, seed: int) -> Image.Image:
    """Warehouse slab marks on the concrete grain, all periodic and seeded.

    - saw-cut joints on the wrap border, one per axis: with the map spanning
      a whole number of grid cells, every joint lands on a cell line (a soft
      2 px groove with a lighter lip, like a cut, so it reads at distance);
    - soft stains (periodic low-frequency noise, small amplitude);
    - pallet-jack wheel scuffs: long thin straight-ish streaks, mostly along
      one axis, a little darker, wrapping around the tile.
    The joints are what tell it apart from plaster and stone.
    """
    rng = np.random.default_rng(seed)
    a = np.asarray(detail, dtype=np.float64) / 255.0
    n = a.shape[0]
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    # Stains: wide blobs the high-pass removed from the AI grain, kept faint.
    stain = circular_blur(rng.standard_normal((n, n)), n / 24)
    a += stain / max(float(stain.std()), 1e-6) * 0.03
    # Wheel scuffs: pairs of parallel streaks (the two wheels), slight slope that wraps exactly.
    for _ in range(7):
        horizontal = rng.random() < 0.6
        pos = rng.uniform(0, n)
        slope = 0  # straight along one axis: any other slope must be whole tiles per tile to wrap
        gap = rng.uniform(10, 16)
        strength = rng.uniform(0.03, 0.05)
        along, across = (xx, yy) if horizontal else (yy, xx)
        line = pos + slope * along
        fade = 0.6 + 0.4 * np.sin(2 * np.pi * (along / n * int(rng.integers(1, 3)) + rng.random()))
        for offset in (0.0, gap):
            d = _wrapped_distance(across - line - offset, 0.0, n)
            a -= strength * fade * np.exp(-(d / 1.6) ** 2)
    # Saw-cut joints on the border (rows/cols 511|0): dark groove, light lip just beside it.
    for coord in (xx, yy):
        d = _wrapped_distance(coord + 0.5, 0.0, n)  # 0.5: the cut sits between pixel n-1 and 0
        groove = np.exp(-(d / 1.4) ** 2)
        lip = np.exp(-((d - 2.6) / 1.0) ** 2)
        a = a * (1.0 - JOINT_DEPTH * groove / DETAIL_MEAN) + 0.025 * lip
    return Image.fromarray((np.clip(a, 0.0, 1.0) * 255).round().astype(np.uint8), "L")


def raw_path(name: str) -> Path:
    return RAW / f"tex_{name}_seed{TEXTURES[name][1]}.png"


def build(name: str, raw_file: Path) -> None:
    image = Image.open(raw_file).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    make_seamless(image).save(RAW / f"tex_{name}_seamless.png")  # colour preview only
    stagger = TEXTURES[name][1] if name in STAGGER else 0
    detail = to_detail(image, 0 if name in NO_BAND else SEAM_BAND, stagger)
    if name in MARKED:
        detail = concrete_marks(detail, TEXTURES[name][1])
    detail.save(OUT / f"tx_detail_{name}_{SIZE}.png", optimize=True)
    print("detail", name, flush=True)


def check(targets: list[str]) -> None:
    files = []
    for t in targets or list(TEXTURES):
        p = Path(t)
        files.append(p if p.suffix else OUT / f"tx_detail_{t}_{SIZE}.png")
    print(f"{'texture':34s} center border  colC  rowC  colB  rowB   mean    std")
    for p in files:
        m = seam_ratio(Image.open(p).convert("L"))
        print(f"{p.name:34s} {m['center']:6.3f} {m['border']:6.3f} "
              f"{m['col_center']:5.2f} {m['row_center']:5.2f} {m['col_border']:5.2f} {m['row_border']:5.2f} "
              f"{m['mean']:6.4f} {m['std']:6.4f}", flush=True)


def main(args: list[str]) -> None:
    if args[:1] == ["--check"]:
        check(args[1:])
        return
    from_raw = args[:1] == ["--from-raw"]
    names = args[1:] if from_raw else args
    RAW.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for name in names or list(TEXTURES):
        if from_raw:
            build(name, raw_path(name))
            continue
        from comfy_generate import generate  # needs ComfyUI running
        subject, seed = TEXTURES[name]
        build(name, generate(subject + " " + STYLE, 1024, 1024, seed, "tex_" + name, RAW)[0])


if __name__ == "__main__":
    main(sys.argv[1:])
