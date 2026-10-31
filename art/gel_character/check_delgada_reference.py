"""Gate the shipped Delgada silhouette against the front reference, without Blender.

python art/gel_character/check_delgada_reference.py <render_mask.png> [--output report.json]

`do-not-drop/tests/render_gel_reference.gd -- --round=149 --output=...` renders the
approved S-311 reference set-up (LOD0 GLB, real `delgada` preset through
GelBodyShaper, approved pose and camera) and writes `<name>_mask.png`. This script
thresholds `referencia/referencia_frente.jpg` with the same masks as
`compare_reference.py` and fails when the silhouette IoU drops below the approved
0.92. CI runs it in the runtime captures job on every PR, so a body or preset change
cannot quietly move the character away from the reference.
"""
import argparse
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compare_reference as reference_masks  # noqa: E402

REFERENCE = HERE / "referencia/referencia_frente.jpg"


def load_rgb(path):
    """Same values as Blender's byte-image pixels: 8-bit sRGB divided by 255."""
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0


def silhouette_report(render_mask_rgb, reference_rgb):
    if render_mask_rgb.shape != reference_rgb.shape:
        raise ValueError(f"Image dimensions differ: {render_mask_rgb.shape} vs {reference_rgb.shape}")
    reference_mask = reference_masks.foreground_mask(reference_rgb)
    render_mask = reference_masks.largest_component(render_mask_rgb.min(axis=2) < 0.5)
    intersection = int((reference_mask & render_mask).sum())
    union = int((reference_mask | render_mask).sum())
    if union == 0:
        raise ValueError("Both silhouettes are empty")
    iou = intersection / union
    return {
        "reference": "art/gel_character/referencia/referencia_frente.jpg",
        "minimum_iou": reference_masks.MINIMUM_SILHOUETTE_IOU,
        "iou": round(iou, 6),
        "intersection_pixels": intersection,
        "union_pixels": union,
        "reference_pixels": int(reference_mask.sum()),
        "render_pixels": int(render_mask.sum()),
        "reference_box_px": reference_masks.mask_box(reference_mask),
        "render_box_px": reference_masks.mask_box(render_mask),
        "passed": iou >= reference_masks.MINIMUM_SILHOUETTE_IOU,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("render_mask", type=Path)
    parser.add_argument("--output", type=Path)
    options = parser.parse_args(argv)
    report = silhouette_report(load_rgb(options.render_mask), load_rgb(REFERENCE))
    text = json.dumps(report, indent=2) + "\n"
    if options.output is not None:
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(text, encoding="utf-8")
    print("DELGADA_REFERENCE", json.dumps(report))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
