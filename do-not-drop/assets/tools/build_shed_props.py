"""Low-poly props of the company shed (expansion group 18), built in Blender's background mode:

    blender --background --python do-not-drop/assets/tools/build_shed_props.py -- boxes supplies containers clipboard

- boxes (D-1806): the four box sizes, open and closed, at their packing-grid size (CompanyTuning.BOX_CELLS times
  GRID_CELL_M 0.2 m): S 0.4 cube, M 0.6 cube, L 0.8 x 0.6 x 0.6 (long side on X), XL 0.8 cube. Open: four walls, a
  floor and four flaps folded out; closed: the shut box with its tape strip. assets/models/props/boxes/.
- supplies (D-1807): tape roll, tape dispenser, bubble wrap roll, packing paper roll, foam block.
  assets/models/props/supplies/.
- containers (D-1809): cooler, thermal box, waterproof box. assets/models/props/containers/.
- clipboard (D-1816): the clipboard held in first person (board, clip, a sheet), no collision.
  assets/models/props/handheld/sm_prop_clipboard.glb.
Every model but the clipboard carries a "<id>-colonly" box that Godot imports as its simple collision. Origin at
the centre of the base, metres, Z up here (the glTF exporter turns it to Godot's Y up).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lowpoly_kit as kit  # noqa: E402

PROPS = os.path.join(kit.ROOT, "models", "props")
CELL = 0.2
WALL = 0.012
kit.PALETTE.update({
    "tape_brown": (0.62, 0.42, 0.18, 1), "bubble": (0.75, 0.88, 0.92, 1), "paper": (0.88, 0.85, 0.76, 1),
    "foam": (0.90, 0.88, 0.80, 1), "cooler_blue": (0.10, 0.35, 0.65, 1), "white": (0.90, 0.90, 0.88, 1),
    "thermal": (0.75, 0.75, 0.78, 1), "yellow_box": (0.95, 0.70, 0.10, 1), "board": (0.45, 0.28, 0.12, 1),
    "steel": (0.55, 0.58, 0.60, 1), "black": (0.04, 0.04, 0.05, 1),
})
# Box size id -> (x, y, z) in cells, Godot's X, Y (up), Z: here x, z (up), y.
BOXES = {"S": (2, 2, 2), "M": (3, 3, 3), "L": (4, 3, 3), "XL": (4, 4, 4)}


def collide(name, size):
    kit.cube("%s-colonly" % name, (0, 0, size[2] / 2), size, "cardboard")


def box(size_id, closed):
    cx, cy_up, cz = BOXES[size_id]
    x, y, z = cx * CELL, cz * CELL, cy_up * CELL
    name = "box_%s_%s" % (size_id.lower(), "closed" if closed else "open")
    kit.clear()
    if closed:
        kit.cube(name, (0, 0, z / 2), (x, y, z), "cardboard", bevel=0.006)
        kit.cube(name + "_tape", (0, 0, z + 0.001), (x * 0.18, y + 0.004, 0.004), "tape_brown")
        kit.cube(name + "_seam", (0, 0, z + 0.0005), (0.004, y, 0.002), "wood")
    else:
        kit.cube(name + "_floor", (0, 0, WALL / 2), (x, y, WALL), "cardboard")
        for sx in (-1, 1):
            kit.cube(name + "_wall_x", (sx * (x - WALL) / 2, 0, z / 2), (WALL, y, z), "cardboard")
            kit.cube(name + "_flap_x", (sx * (x / 2 + y * 0.18), 0, z + y * 0.12), (y * 0.42, y * 0.96, WALL), "cardboard",
                     rot=(0, sx * -0.6, 0))
        for sy in (-1, 1):
            kit.cube(name + "_wall_y", (0, sy * (y - WALL) / 2, z / 2), (x, WALL, z), "cardboard")
            kit.cube(name + "_flap_y", (0, sy * (y / 2 + x * 0.12), z + x * 0.08), (x * 0.96, x * 0.28, WALL), "cardboard",
                     rot=(sy * 0.6, 0, 0))
    collide(name, (x, y, z))
    kit.export(os.path.join(PROPS, "boxes", "sm_%s.glb" % name))


def supplies():
    items = {
        "tape_roll": lambda n: [kit.cylinder(n, (0, 0, 0.025), 0.05, 0.05, "tape_brown", verts=16),
                                kit.cylinder(n + "_core", (0, 0, 0.0255), 0.03, 0.051, "paper", verts=12)],
        "tape_dispenser": lambda n: [kit.cube(n, (0, 0, 0.03), (0.22, 0.08, 0.06), "black"),
                                     kit.cylinder(n + "_roll", (0, 0, 0.075), 0.05, 0.05, "tape_brown", verts=16,
                                                  rot=(math.pi / 2, 0, 0)),
                                     kit.cube(n + "_handle", (-0.10, 0, 0.09), (0.04, 0.04, 0.12), "steel")],
        "bubble_wrap_roll": lambda n: [kit.cylinder(n, (0, 0, 0.25), 0.12, 0.50, "bubble", verts=14)],
        "packing_paper_roll": lambda n: [kit.cylinder(n, (0, 0, 0.30), 0.08, 0.60, "paper", verts=14)],
        "foam_block": lambda n: [kit.cube(n, (0, 0, 0.05), (0.40, 0.30, 0.10), "foam", bevel=0.01)],
    }
    for item, make in items.items():
        kit.clear()
        make(item)
        _rest_and_collide(item)
        kit.export(os.path.join(PROPS, "supplies", "sm_supply_%s.glb" % item))


def containers():
    items = {
        "cooler": lambda n: [kit.cube(n, (0, 0, 0.18), (0.60, 0.38, 0.36), "cooler_blue", bevel=0.02),
                             kit.cube(n + "_lid", (0, 0, 0.37), (0.62, 0.40, 0.04), "white", bevel=0.01),
                             kit.cube(n + "_handle", (0, 0, 0.40), (0.30, 0.04, 0.03), "black")],
        "thermal_box": lambda n: [kit.cube(n, (0, 0, 0.20), (0.50, 0.40, 0.40), "thermal", bevel=0.01),
                                  kit.cube(n + "_band", (0, -0.201, 0.30), (0.50, 0.002, 0.06), "cooler_blue")],
        "waterproof_box": lambda n: [kit.cube(n, (0, 0, 0.15), (0.55, 0.40, 0.30), "yellow_box", bevel=0.02),
                                     kit.cube(n + "_lid", (0, 0, 0.31), (0.57, 0.42, 0.03), "black"),
                                     kit.cube(n + "_latch_a", (-0.15, -0.21, 0.27), (0.06, 0.02, 0.06), "black"),
                                     kit.cube(n + "_latch_b", (0.15, -0.21, 0.27), (0.06, 0.02, 0.06), "black")],
    }
    for item, make in items.items():
        kit.clear()
        make(item)
        _rest_and_collide(item)
        kit.export(os.path.join(PROPS, "containers", "sm_container_%s.glb" % item))


def clipboard():
    kit.clear()
    kit.cube("clipboard_board", (0, 0, 0.0035), (0.23, 0.32, 0.007), "board", bevel=0.003)
    kit.cube("clipboard_sheet", (0, -0.01, 0.0075), (0.21, 0.28, 0.001), "paper")
    kit.cube("clipboard_clip", (0, 0.145, 0.012), (0.10, 0.03, 0.012), "steel", bevel=0.002)
    kit.export(os.path.join(PROPS, "handheld", "sm_prop_clipboard.glb"))


def _rest_and_collide(name):
    import bpy
    from mathutils import Vector
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in bpy.context.scene.objects for c in o.bound_box]
    low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    shift = Vector((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z))
    for o in bpy.context.scene.objects:
        o.location += shift
    collide(name, tuple(high - low))


def main():
    groups = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    groups = groups or ["boxes", "supplies", "containers", "clipboard"]
    if "boxes" in groups:
        for size_id in BOXES:
            for closed in (False, True):
                box(size_id, closed)
    if "supplies" in groups:
        supplies()
    if "containers" in groups:
        containers()
    if "clipboard" in groups:
        clipboard()


main()
