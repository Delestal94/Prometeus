"""Generate the tileable detail textures used on terrain and low-poly models.

    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_detail_textures.py [name ...]
    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_detail_textures.py --from-raw [name ...]
    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_detail_textures.py --check [file-or-name ...]

Default mode generates each texture with ComfyUI + Z-Image Turbo (the raw
1024x1024 image is kept as art/concept/textures/tex_<name>_seed<N>.png).
--from-raw skips ComfyUI and rebuilds the maps from those raw files, so the
output is fully reproducible. Without names, all ten are processed.

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

--check prints the seam metric (seam_ratio) plus mean and std of each map:
mean absolute gradient across the centre line (col/row 255|256) and across
the wrap border (511 -> 0), divided by the median gradient of the other
columns/rows. Values near 1 mean "no visible line". Without arguments it
checks the ten files in OUT.

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


def to_detail(raw: Image.Image, band: int = SEAM_BAND) -> Image.Image:
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


def raw_path(name: str) -> Path:
    return RAW / f"tex_{name}_seed{TEXTURES[name][1]}.png"


def build(name: str, raw_file: Path) -> None:
    image = Image.open(raw_file).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    make_seamless(image).save(RAW / f"tex_{name}_seamless.png")  # colour preview only
    to_detail(image, 0 if name in NO_BAND else SEAM_BAND).save(OUT / f"tx_detail_{name}_{SIZE}.png", optimize=True)
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
