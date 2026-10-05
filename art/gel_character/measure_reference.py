"""Reproduce S-311 block A image measurements; requires Pillow and NumPy.

Run from the repository root: python art/gel_character/measure_reference.py
The JPG cannot recover physical opacity, albedo or anteroposterior foot depth.
"""
from collections import deque
import json
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    source = Path(__file__).parent / "referencia/referencia_frente.jpg"
    pixels = np.asarray(Image.open(source).convert("RGB"), dtype=np.int16)
    mask = ((pixels[:, :, 2] - pixels[:, :, 0]) >= 3) & (
        (255 - pixels.min(axis=2)) >= 8
    )
    seen = np.zeros(mask.shape, dtype=bool)
    largest = []
    for y, x in zip(*np.where(mask)):
        if seen[y, x]:
            continue
        queue = deque([(int(y), int(x))])
        seen[y, x] = True
        component = []
        while queue:
            cy, cx = queue.popleft()
            component.append((cy, cx))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if (0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1]
                            and mask[ny, nx] and not seen[ny, nx]):
                        seen[ny, nx] = True
                        queue.append((ny, nx))
        if len(component) > len(largest):
            largest = component
    points = np.asarray(largest)
    top, left = points.min(axis=0)
    bottom, right = points.max(axis=0)
    height = int(bottom - top + 1)
    component = np.zeros(mask.shape, dtype=bool)
    component[points[:, 0], points[:, 1]] = True
    outside = np.zeros(mask.shape, dtype=bool)
    queue = deque()
    for x in range(mask.shape[1]):
        for y in (0, mask.shape[0]-1):
            if not component[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    for y in range(mask.shape[0]):
        for x in (0, mask.shape[1]-1):
            if not component[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y+dy, x+dx
            if (0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1]
                    and not component[ny, nx] and not outside[ny, nx]):
                outside[ny, nx] = True
                queue.append((ny, nx))
    silhouette = ~outside
    Image.fromarray((silhouette*255).astype(np.uint8)).save(
        source.with_name('silueta_mascara.png'))
    # Head diameter is the mean of manually identified 284 x 280 px landmarks.
    diameter = 282
    rois = {
        "head": (370, 225, 460, 300), "torso": (360, 455, 475, 680),
        "leg": (300, 815, 345, 980), "head_rim": (278, 205, 298, 285),
        "foot_rim": (225, 1050, 255, 1100), "arm": (210, 520, 238, 650),
        "leg_transmissive": (315, 820, 345, 970),
    }
    samples = {}
    for name, (x0, y0, x1, y1) in rois.items():
        rgb = np.median(pixels[y0:y1, x0:x1], axis=(0, 1)).astype(int)
        samples[name] = {"roi": list(rois[name]), "rgb": rgb.tolist(),
                         "hex": "#" + "".join(f"{v:02X}" for v in rgb)}
    result = {"source_size": [pixels.shape[1], pixels.shape[0]],
              "body_bbox_inclusive": [int(left), int(top), int(right), int(bottom)],
              "body_height_px": height, "head_diameter_px": diameter,
              "height_in_heads": round(height / diameter, 2),
              "silhouette_area_px": int(silhouette.sum()), "samples": samples}
    assert result["source_size"] == [832, 1248], "Reference dimensions changed"
    assert result["body_bbox_inclusive"] == [148, 98, 676, 1135], "Re-measure reference"
    assert result["silhouette_area_px"] == 299222, "Re-measure silhouette"
    expected_rgb = {
        "head": [222, 221, 226], "torso": [220, 219, 225],
        "leg": [230, 227, 233], "head_rim": [206, 207, 219],
        "foot_rim": [208, 209, 221], "arm": [229, 227, 232],
        "leg_transmissive": [231, 229, 234],
    }
    for name, expected in expected_rgb.items():
        assert samples[name]["rgb"] == expected, f"Re-measure material sample: {name}"
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
