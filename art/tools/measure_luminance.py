"""Measure how bright a region of a capture is, for before/after numbers.

Mean Rec. 709 luminance (0-1, sRGB values as stored) of a box given in
fractions of the image, plus how much of it is blown out (any channel >= 250)
or crushed (luminance < 0.04). Used for the night road of N-317 and the
signs of N-318:

    python art/tools/measure_luminance.py render_route_sign.png --box 0.3 0.7 0.7 1.0
    python art/tools/measure_luminance.py a.png b.png --box 0.0 0.0 1.0 0.5 --label road

`--box` is x0 y0 x1 y1 (0,0 top-left). Without it, the whole image. Needs
Pillow.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image


def measure(path: Path, box: tuple[float, float, float, float]) -> dict[str, float]:
    image = Image.open(path).convert("RGB")
    width, height = image.size
    x0, y0, x1, y1 = box
    region = image.crop((int(x0 * width), int(y0 * height), int(x1 * width), int(y1 * height)))
    pixels = list(region.getdata())
    if not pixels:
        raise ValueError(f"empty box on {path}")
    total = 0.0
    saturated = 0
    crushed = 0
    for r, g, b in pixels:
        lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
        total += lum
        if max(r, g, b) >= 250:
            saturated += 1
        if lum < 0.04:
            crushed += 1
    count = float(len(pixels))
    return {"mean": total / count, "saturated": saturated / count, "crushed": crushed / count}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument("--box", nargs=4, type=float, default=[0.0, 0.0, 1.0, 1.0], metavar=("X0", "Y0", "X1", "Y1"))
    parser.add_argument("--label", default="box")
    args = parser.parse_args()
    for path in args.images:
        stats = measure(path, tuple(args.box))
        print(f"{path.name} [{args.label} {' '.join(f'{v:g}' for v in args.box)}]: "
              f"mean {stats['mean']:.3f}  saturated {stats['saturated'] * 100:.1f}%  crushed {stats['crushed'] * 100:.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
