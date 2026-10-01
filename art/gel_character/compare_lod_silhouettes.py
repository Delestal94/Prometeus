"""Measure real Godot diagnostic captures; never substitutes for final Flaca/E.

python art/gel_character/compare_lod_silhouettes.py <capture-directory> --output <report.json>
Pixel difference is the symmetric difference divided by union; fail above 5%.
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def compare(directory):
    manifest = json.loads((directory / "capture_manifest.json").read_text(encoding="utf-8"))
    if manifest["resolution"] != [1920, 1080] or manifest["distance_m"] != 15.0 or manifest["fov_vertical_deg"] != 60.0:
        raise ValueError("Capture protocol must be 1920x1080 at 15m and 60-degree vertical FOV")
    expected = (manifest["resolution"][0], manifest["resolution"][1])
    entries = {(row["lod"], row["state"], row["view"]): row for row in manifest["captures"]}
    if len(entries) != len(manifest["captures"]):
        raise ValueError("Duplicate capture entries")
    states = {row["state"] for row in manifest["captures"] if row["lod"] == 0}
    required = {(lod, state, view) for lod in range(3) for state in states
                for view in ("front", "profile", "three_quarter")}
    if set(entries) != required or len(states) != 24:
        raise ValueError("Expected all three LODs/views for base, limb proxy and 22 extremes")
    results = []
    for (lod, state, view), row in entries.items():
        if lod == 0:
            continue
        images = []
        for key in ((0, state, view), (lod, state, view)):
            if entries[key]["weights"] != entries[(0, state, view)]["weights"]:
                raise ValueError("Compared captures have different morph weights")
            with Image.open(directory / entries[key]["file"]) as image:
                if image.size != expected:
                    raise ValueError("Capture dimensions disagree with protocol")
                images.append(np.asarray(image.convert("RGB")).min(axis=2) > 127)
        base, variant = images
        union = int(np.logical_or(base, variant).sum())
        if union == 0:
            raise ValueError(f"Empty silhouette for {state}/{view}")
        difference = int(np.logical_xor(base, variant).sum())
        results.append({"lod": lod, "state": state, "view": view,
                        "pixel_difference": difference / union,
                        "iou": 1 - difference / union, "union_pixels": union,
                        "pass": difference / union <= 0.05})
    if not results:
        raise ValueError("No LOD comparisons")
    return {"protocol": {key: manifest[key] for key in manifest if key != "captures"},
            "passed_diagnostic_samples": all(row["pass"] for row in results),
            "final_item_17_complete": False,
            "remaining": "Full Flaca bone-length preset must be checked after C; these are opaque B diagnostics.",
            "worst_pixel_difference": max(row["pixel_difference"] for row in results),
            "comparisons": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = compare(args.directory)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "comparisons"}, indent=2))
    return 0 if report["passed_diagnostic_samples"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
