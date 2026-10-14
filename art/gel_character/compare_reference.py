"""Compare the Godot gel render with the front reference for one iteration.

blender --background --factory-startup --python-exit-code 1 --python \
  art/gel_character/compare_reference.py -- --round=1

Both inputs remain at the source resolution. The script thresholds their white
backgrounds, reports silhouette IoU and CIE76 Delta E for four anatomical zones,
then writes a side-by-side image and a difference map for the requested round.
"""
import json
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
import sys

import bpy
import numpy as np


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEFAULT_REFERENCE = HERE / "referencia/referencia_frente.jpg"
DEFAULT_RENDER = HERE / "review_bloque_e/s311_38_godot_reference.png"
DEFAULT_OUTPUT = HERE / "review_bloque_e"
WHITE_DISTANCE_THRESHOLD = 8
BLUE_BIAS_THRESHOLD = 3
MAXIMUM_HIGHLIGHT_GAP_PX = 16
ZONE_ORDER = ("head", "torso", "arms", "legs")
MINIMUM_SILHOUETTE_IOU = 0.92
MAXIMUM_MEAN_DELTA_E = 8.0
VISUAL_CRITERIA = (
    ("silhouette", "Silueta"),
    ("smooth_spherical_head", "Cabeza esférica y lisa"),
    ("continuous_neck_shoulders", "Transición cuello-hombros continua"),
    ("head_window_reflections", "Reflejos tipo ventana en la cabeza"),
    ("dense_clear_rim", "Borde más denso y claro que el centro"),
    ("background_visible", "Fondo visible a través del gel"),
    ("fine_internal_bubbles", "Motas o burbujas internas finas"),
    ("mitten_hands", "Manos manopla con pulgar"),
    ("rounded_boot_feet", "Pies de bota redondeada"),
    ("soft_contact_shadow", "Sombra de contacto suave"),
    ("denser_torso", "Torso más opaco que las extremidades"),
    ("no_visible_facets", "Cero facetas o aristas visibles"),
)


def command_line_options():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    options = {"round": 1, "reference": DEFAULT_REFERENCE,
               "render": DEFAULT_RENDER, "output": DEFAULT_OUTPUT,
               "mask_render": None,
               "require_approval": False}
    for argument in arguments:
        if argument.startswith("--round="):
            options["round"] = int(argument.split("=", 1)[1])
        elif argument.startswith("--reference="):
            options["reference"] = Path(argument.split("=", 1)[1]).resolve()
        elif argument.startswith("--render="):
            options["render"] = Path(argument.split("=", 1)[1]).resolve()
        elif argument.startswith("--output="):
            options["output"] = Path(argument.split("=", 1)[1]).resolve()
        elif argument.startswith("--mask-render="):
            options["mask_render"] = Path(argument.split("=", 1)[1]).resolve()
        elif argument == "--require-approval":
            options["require_approval"] = True
        else:
            raise ValueError(f"Unknown option: {argument}")
    if options["round"] < 1:
        raise ValueError("--round must be at least 1")
    return options


def load_rgb(path):
    image = bpy.data.images.load(str(path), check_existing=False)
    try:
        width, height = image.size
        pixels = np.empty(width * height * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        rgba = pixels.reshape(height, width, 4)[::-1].copy()
        return rgba[:, :, :3], (width, height)
    finally:
        bpy.data.images.remove(image)


def largest_component(mask):
    """Keep the subject and reject disconnected dust/background artifacts."""
    height, width = mask.shape
    seen = np.zeros(mask.shape, dtype=bool)
    largest = []
    for y, x in zip(*np.nonzero(mask)):
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
                    if (0 <= ny < height and 0 <= nx < width
                            and mask[ny, nx] and not seen[ny, nx]):
                        seen[ny, nx] = True
                        queue.append((ny, nx))
        if len(component) > len(largest):
            largest = component
    result = np.zeros(mask.shape, dtype=bool)
    if largest:
        points = np.asarray(largest, dtype=np.int32)
        result[points[:, 0], points[:, 1]] = True
    return result


def fill_enclosed_holes(component):
    """Fill white highlights inside the subject without filling arm/body gaps."""
    height, width = component.shape
    outside = np.zeros(component.shape, dtype=bool)
    queue = deque()
    for x in range(width):
        for y in (0, height - 1):
            if not component[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    for y in range(height):
        for x in (0, width - 1):
            if not component[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    while queue:
        cy, cx = queue.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = cy + dy, cx + dx
            if (0 <= ny < height and 0 <= nx < width
                    and not component[ny, nx] and not outside[ny, nx]):
                outside[ny, nx] = True
                queue.append((ny, nx))
    return ~outside


def close_small_row_gaps(mask, maximum_gap=MAXIMUM_HIGHLIGHT_GAP_PX):
    """Reconnect narrow white specular cuts without bridging anatomical gaps."""
    result = mask.copy()
    for row in range(result.shape[0]):
        columns = np.flatnonzero(result[row])
        if columns.size < 2:
            continue
        for left, right in zip(columns[:-1], columns[1:]):
            gap = int(right-left-1)
            if 0 < gap <= maximum_gap:
                result[row, left:right+1] = True
    return result


def foreground_mask(rgb):
    srgb_255 = np.rint(np.clip(rgb, 0.0, 1.0) * 255.0)
    candidate = ((srgb_255[:, :, 2] - srgb_255[:, :, 0]) >= BLUE_BIAS_THRESHOLD
                 ) & ((255.0 - srgb_255.min(axis=2)) >= WHITE_DISTANCE_THRESHOLD)
    component = largest_component(candidate)
    return fill_enclosed_holes(close_small_row_gaps(component))


def mask_box(mask):
    rows, columns = np.nonzero(mask)
    if rows.size == 0:
        raise ValueError("White-background threshold produced an empty silhouette")
    return (int(columns.min()), int(rows.min()), int(columns.max()), int(rows.max()))


def row_runs(mask, row):
    columns = np.flatnonzero(mask[row])
    if not columns.size:
        return []
    breaks = np.flatnonzero(np.diff(columns) > 1) + 1
    groups = np.split(columns, breaks)
    return [[int(group[0]), int(group[-1])] for group in groups]


def srgb_to_lab(rgb):
    srgb = np.clip(rgb, 0.0, 1.0)
    rgb = np.where(srgb <= 0.04045, srgb / 12.92,
                   np.power((srgb + 0.055) / 1.055, 2.4))
    matrix = np.array([
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ], dtype=np.float32)
    xyz = np.clip(rgb, 0.0, 1.0) @ matrix.T
    xyz /= np.array([0.95047, 1.0, 1.08883], dtype=np.float32)
    epsilon = 216.0 / 24389.0
    kappa = 24389.0 / 27.0
    transformed = np.where(xyz > epsilon, np.cbrt(xyz), (kappa * xyz + 16.0) / 116.0)
    x, y, z = transformed[..., 0], transformed[..., 1], transformed[..., 2]
    return np.stack((116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z)), axis=2)


def anatomical_zones(shape, box):
    height, width = shape
    left, top, right, bottom = box
    xs = np.arange(width, dtype=np.float32)[None, :]
    ys = np.arange(height, dtype=np.float32)[:, None]
    nx = (xs - left) / max(right - left, 1)
    ny = (ys - top) / max(bottom - top, 1)
    within_box = (nx >= 0.0) & (nx <= 1.0) & (ny >= 0.0) & (ny <= 1.0)
    head = within_box & (ny < 0.29)
    legs = within_box & (ny >= 0.64)
    arms = within_box & (ny >= 0.27) & (ny < 0.70) & ((nx < 0.27) | (nx > 0.73))
    torso = within_box & ~(head | legs | arms)
    return {"head": head, "torso": torso, "arms": arms, "legs": legs}


def relative(path):
    try:
        return str(path.relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path).replace("\\", "/")


def load_visual_review(path, round_number):
    if not path.exists():
        review = {
            "schema_version": 1,
            "round": round_number,
            "instructions": "Set every result to 'yes' only after reviewing the round PNGs.",
            "criteria": [
                {"id": criterion_id, "label": label, "result": "pending", "notes": ""}
                for criterion_id, label in VISUAL_CRITERIA
            ],
        }
        path.write_text(json.dumps(review, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")
        return review

    review = json.loads(path.read_text(encoding="utf-8"))
    criteria = review.get("criteria", [])
    expected_ids = [criterion_id for criterion_id, _label in VISUAL_CRITERIA]
    actual_ids = [criterion.get("id") for criterion in criteria]
    if review.get("round") != round_number or actual_ids != expected_ids:
        raise ValueError(f"Visual review does not match round {round_number}: {path}")
    invalid = [criterion.get("result") for criterion in criteria
               if criterion.get("result") not in ("yes", "no", "pending")]
    if invalid:
        raise ValueError(f"Invalid visual review results {invalid}: {path}")
    return review


def approval_status(result, visual_review, visual_path):
    silhouette_passed = result["iou"] >= MINIMUM_SILHOUETTE_IOU
    color_zones = {
        name: {
            "value": result["zones"][name]["mean_delta_e"],
            "passed": (result["zones"][name]["mean_delta_e"] is not None
                       and result["zones"][name]["mean_delta_e"] <= MAXIMUM_MEAN_DELTA_E),
        }
        for name in ZONE_ORDER
    }
    automatic_passed = silhouette_passed and all(
        zone["passed"] for zone in color_zones.values())
    criteria = visual_review["criteria"]
    yes_count = sum(criterion["result"] == "yes" for criterion in criteria)
    visual_passed = yes_count == len(VISUAL_CRITERIA)
    return {
        "thresholds": {
            "minimum_silhouette_iou": MINIMUM_SILHOUETTE_IOU,
            "maximum_mean_delta_e_per_zone": MAXIMUM_MEAN_DELTA_E,
            "required_visual_yes": len(VISUAL_CRITERIA),
        },
        "automatic": {
            "silhouette": {"value": round(result["iou"], 6),
                           "passed": silhouette_passed},
            "color_zones": color_zones,
            "passed": automatic_passed,
        },
        "visual_review": {
            "path": relative(visual_path),
            "criteria_total": len(criteria),
            "criteria_yes": yes_count,
            "passed": visual_passed,
        },
        "passed": automatic_passed and visual_passed,
    }


def save_rgb(path, rgb, name):
    height, width, channels = rgb.shape
    if channels != 3:
        raise ValueError("save_rgb expects three channels")
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[:, :, :3] = np.clip(rgb, 0.0, 1.0)
    image = bpy.data.images.new(name, width, height, alpha=True, float_buffer=False)
    try:
        image.colorspace_settings.name = "Linear Rec.709"
        image.pixels.foreach_set(rgba[::-1].reshape(-1))
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
    finally:
        bpy.data.images.remove(image)


def compare(reference, render, render_mask_rgb=None):
    reference_mask = foreground_mask(reference)
    render_mask = (largest_component(render_mask_rgb.min(axis=2) < 0.5)
                   if render_mask_rgb is not None else foreground_mask(render))
    intersection = reference_mask & render_mask
    union = reference_mask | render_mask
    intersection_pixels = int(intersection.sum())
    union_pixels = int(union.sum())
    if union_pixels == 0:
        raise ValueError("Both thresholded silhouettes are empty")

    reference_lab = srgb_to_lab(reference)
    render_lab = srgb_to_lab(render)
    delta_e = np.linalg.norm(reference_lab - render_lab, axis=2)
    box = mask_box(reference_mask)
    zones = anatomical_zones(reference_mask.shape, box)
    zone_report = {}
    silhouette_zone_report = {}
    for name in ZONE_ORDER:
        samples = intersection & zones[name]
        values = delta_e[samples]
        zone_report[name] = {
            "mean_delta_e": round(float(values.mean()), 4) if values.size else None,
            "sample_pixels": int(values.size),
            "reference_mean_lab": [round(float(value), 4) for value in reference_lab[samples].mean(axis=0)] if values.size else None,
            "render_mean_lab": [round(float(value), 4) for value in render_lab[samples].mean(axis=0)] if values.size else None,
        }
        zone_intersection = int((intersection & zones[name]).sum())
        zone_union = int((union & zones[name]).sum())
        silhouette_zone_report[name] = {
            "iou": round(zone_intersection / zone_union, 6) if zone_union else None,
            "intersection_pixels": zone_intersection,
            "union_pixels": zone_union,
        }

    difference = np.ones_like(reference)
    reference_only = reference_mask & ~render_mask
    render_only = render_mask & ~reference_mask
    difference[reference_only] = (1.0, 0.0, 0.65)
    difference[render_only] = (0.0, 0.72, 1.0)
    heat = np.clip(delta_e / 20.0, 0.0, 1.0)
    difference[intersection, 0] = heat[intersection]
    difference[intersection, 1] = 0.55 * (1.0 - heat[intersection])
    difference[intersection, 2] = 0.08
    return {
        "reference_mask": reference_mask,
        "render_mask": render_mask,
        "intersection_pixels": intersection_pixels,
        "union_pixels": union_pixels,
        "iou": intersection_pixels / union_pixels,
        "reference_box_px": box,
        "render_box_px": mask_box(render_mask),
        "silhouette_zones": silhouette_zone_report,
        "row_runs": {
            str(row): {
                "reference": row_runs(reference_mask, row),
                "render": row_runs(render_mask, row),
            }
            for row in (
                100, 120, 150, 200, 250, 300, 350, 390,
                420, 460, 480, 500, 520, 540, 560, 600,
                700, 720, 740, 760, 780, 800, 850, 950, 1050, 1120,
            )
        },
        "zones": zone_report,
        "difference": difference,
    }


def main():
    options = command_line_options()
    reference_path = options["reference"]
    render_path = options["render"]
    reference, reference_size = load_rgb(reference_path)
    render, render_size = load_rgb(render_path)
    if reference_size != render_size:
        raise ValueError(f"Image dimensions differ: {reference_size} vs {render_size}")

    mask_render_path = options["mask_render"]
    mask_render = None
    if mask_render_path is not None:
        mask_render, mask_size = load_rgb(mask_render_path)
        if mask_size != reference_size:
            raise ValueError(f"Mask image dimensions differ: {mask_size} vs {reference_size}")
    result = compare(reference, render, mask_render)
    round_directory = options["output"] / f"round_{options['round']:02d}"
    round_directory.mkdir(parents=True, exist_ok=True)
    side_by_side = np.concatenate((reference, render), axis=1)
    side_path = round_directory / "side_by_side.png"
    difference_path = round_directory / "difference.png"
    report_path = round_directory / "report.json"
    visual_review_path = round_directory / "visual_review.json"
    visual_review = load_visual_review(visual_review_path, options["round"])
    save_rgb(side_path, side_by_side, f"GelReferenceRound{options['round']:02d}SideBySide")
    save_rgb(difference_path, result["difference"], f"GelReferenceRound{options['round']:02d}Difference")

    report = {
        "schema_version": 1,
        "round": options["round"],
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "reference": relative(reference_path),
        "render": relative(render_path),
        "mask_render": relative(mask_render_path) if mask_render_path is not None else None,
        "resolution": list(reference_size),
        "mask": {
            "method": "white-background threshold, largest component, <=16 px specular-gap close, enclosed-hole fill",
            "white_distance_threshold_srgb8": WHITE_DISTANCE_THRESHOLD,
            "blue_bias_threshold_srgb8": BLUE_BIAS_THRESHOLD,
        },
        "silhouette": {
            "iou": round(result["iou"], 6),
            "intersection_pixels": result["intersection_pixels"],
            "union_pixels": result["union_pixels"],
            "reference_pixels": int(result["reference_mask"].sum()),
            "render_pixels": int(result["render_mask"].sum()),
            "reference_box_px": list(result["reference_box_px"]),
            "render_box_px": list(result["render_box_px"]),
            "zones": result["silhouette_zones"],
            "row_runs": result["row_runs"],
        },
        "color": {
            "method": "CIE76 Delta E on intersecting foreground pixels",
            "zones": result["zones"],
        },
        "artifacts": {
            "side_by_side": relative(side_path),
            "difference": relative(difference_path),
        },
        "approval": approval_status(result, visual_review, visual_review_path),
    }
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("GEL_REFERENCE_COMPARE", json.dumps(report, separators=(",", ":")))
    if options["require_approval"] and not report["approval"]["passed"]:
        raise AssertionError(f"Round {options['round']} does not pass the approval gate")


if __name__ == "__main__":
    main()
