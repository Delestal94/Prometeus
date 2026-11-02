"""Low-poly product models for the company mode (expansion group 18: D-1802 to D-1805, D-1821, D-1822).

Run in Blender's background mode, one lot at a time or all of them:

    blender --background --python do-not-drop/assets/tools/build_product_models.py -- 1
    blender --background --python do-not-drop/assets/tools/build_product_models.py -- all

Each product is a few primitives in the shared palette (lowpoly_kit), with its origin at the centre of its base and
its size in metres, plus a box named "<id>-colonly": Godot's importer turns that into the product's simple
collision (a StaticBody3D with a box shape) and drops its mesh. Exported to
assets/models/products/sm_product_<id>.glb. tests/test_product_models.gd checks every lot.

A part is (shape, centre (x, y, z with z up), size (x, y, z), colour) for "cube", "cyl" (size: radius, -, depth),
"cone" (size: bottom radius, top radius, depth), "ball" (size: radii); an optional fifth item is a rotation.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lowpoly_kit as kit  # noqa: E402

OUT = os.path.join(kit.ROOT, "models", "products")

kit.PALETTE.update({
    "glass": (0.55, 0.78, 0.80, 1), "bottle_green": (0.10, 0.36, 0.18, 1), "paper": (0.88, 0.85, 0.76, 1),
    "red": (0.70, 0.08, 0.06, 1), "blue": (0.08, 0.22, 0.60, 1), "yellow": (0.95, 0.72, 0.10, 1),
    "white": (0.90, 0.90, 0.88, 1), "black": (0.04, 0.04, 0.05, 1), "pink": (0.90, 0.45, 0.55, 1),
    "cream": (0.93, 0.85, 0.62, 1), "steel": (0.55, 0.58, 0.60, 1), "teal": (0.10, 0.45, 0.45, 1),
    "brown": (0.32, 0.18, 0.08, 1), "lava": (0.85, 0.25, 0.04, 1), "ice": (0.75, 0.90, 0.95, 1),
    "green": (0.18, 0.55, 0.20, 1), "purple": (0.40, 0.16, 0.50, 1), "sand": (0.80, 0.68, 0.45, 1),
})

LOTS = {
    # D-1802: the vertical slice's everyday goods.
    1: {
        "bottle": [("cyl", (0, 0, 0.12), (0.045, 0, 0.24), "bottle_green"), ("cyl", (0, 0, 0.27), (0.016, 0, 0.07), "bottle_green"),
                   ("cyl", (0, 0, 0.31), (0.018, 0, 0.012), "cream")],
        "book": [("cube", (0, 0, 0.025), (0.16, 0.24, 0.05), "red"), ("cube", (0.004, 0, 0.025), (0.15, 0.235, 0.042), "paper")],
        "mug": [("cyl", (0, 0, 0.05), (0.045, 0, 0.10), "white"), ("cyl", (0.06, 0, 0.05), (0.025, 0, 0.012), "white", (math.pi / 2, 0, 0))],
        "sneakers": [("cube", (0, -0.06, 0.03), (0.11, 0.28, 0.06), "white"), ("cube", (0, -0.06, 0.008), (0.115, 0.29, 0.016), "red"),
                     ("cube", (0, 0.06, 0.03), (0.11, 0.28, 0.06), "white")],
        "desk_lamp": [("cyl", (0, 0, 0.012), (0.08, 0, 0.024), "black"), ("cube", (0, 0, 0.16), (0.02, 0.02, 0.28), "steel"),
                      ("cone", (0.06, 0, 0.30), (0.07, 0.03, 0.09), "yellow", (0, math.pi / 3, 0))],
        "toaster": [("cube", (0, 0, 0.09), (0.26, 0.15, 0.18), "steel", ), ("cube", (0, 0, 0.18), (0.20, 0.03, 0.01), "black")],
        "backpack": [("cube", (0, 0, 0.21), (0.30, 0.16, 0.42), "blue"), ("cube", (0, 0.10, 0.14), (0.24, 0.05, 0.18), "teal")],
        "board_game": [("cube", (0, 0, 0.035), (0.40, 0.27, 0.07), "yellow"), ("cube", (0, 0, 0.071), (0.30, 0.18, 0.002), "red")],
        "headphones": [("cube", (0, 0, 0.17), (0.18, 0.04, 0.03), "black"), ("cyl", (-0.09, 0, 0.07), (0.045, 0, 0.04), "black", (0, math.pi / 2, 0)),
                       ("cyl", (0.09, 0, 0.07), (0.045, 0, 0.04), "black", (0, math.pi / 2, 0))],
        "teapot": [("ball", (0, 0, 0.08), (0.10, 0.10, 0.08), "teal"), ("cone", (0.11, 0, 0.10), (0.025, 0.012, 0.10), "teal", (0, 1.0, 0)),
                   ("cyl", (0, 0, 0.165), (0.03, 0, 0.02), "teal")],
    },
    # D-1803: fragile goods (glass, ceramics, screens, mirrors).
    2: {
        "wine_glasses": [("cyl", (-0.05, 0, 0.005), (0.03, 0, 0.01), "glass"), ("cyl", (-0.05, 0, 0.06), (0.005, 0, 0.10), "glass"),
                         ("cone", (-0.05, 0, 0.15), (0.02, 0.04, 0.08), "glass"), ("cyl", (0.05, 0, 0.005), (0.03, 0, 0.01), "glass"),
                         ("cyl", (0.05, 0, 0.06), (0.005, 0, 0.10), "glass"), ("cone", (0.05, 0, 0.15), (0.02, 0.04, 0.08), "glass")],
        "plate_stack": [("cyl", (0, 0, 0.04), (0.13, 0, 0.08), "white"), ("cyl", (0, 0, 0.081), (0.10, 0, 0.002), "blue")],
        "television": [("cube", (0, 0, 0.30), (0.70, 0.06, 0.42), "black"), ("cube", (0, -0.031, 0.31), (0.64, 0.002, 0.36), "teal"),
                       ("cube", (0, 0, 0.04), (0.22, 0.14, 0.08), "black")],
        "mirror": [("cube", (0, 0, 0.45), (0.50, 0.04, 0.90), "brown"), ("cube", (0, -0.021, 0.45), (0.42, 0.002, 0.82), "ice")],
        "glass_jar": [("cyl", (0, 0, 0.10), (0.07, 0, 0.20), "glass"), ("cyl", (0, 0, 0.21), (0.065, 0, 0.025), "red")],
        "tall_vase": [("cone", (0, 0, 0.12), (0.07, 0.11, 0.24), "pink"), ("cone", (0, 0, 0.32), (0.11, 0.05, 0.16), "pink")],
        "chandelier": [("cyl", (0, 0, 0.30), (0.012, 0, 0.20), "yellow"), ("cyl", (0, 0, 0.18), (0.18, 0, 0.03), "yellow"),
                       ("ball", (0.15, 0, 0.12), (0.035, 0.035, 0.05), "glass"), ("ball", (-0.15, 0, 0.12), (0.035, 0.035, 0.05), "glass"),
                       ("ball", (0, 0.15, 0.12), (0.035, 0.035, 0.05), "glass"), ("ball", (0, -0.15, 0.12), (0.035, 0.035, 0.05), "glass")],
        "ceramic_teapot": [("ball", (0, 0, 0.09), (0.11, 0.11, 0.09), "white"), ("cone", (0.12, 0, 0.11), (0.025, 0.012, 0.10), "white", (0, 1.0, 0)),
                           ("ball", (0, 0, 0.18), (0.03, 0.03, 0.025), "blue")],
        "picture_frame": [("cube", (0, 0, 0.20), (0.32, 0.03, 0.40), "yellow"), ("cube", (0, -0.016, 0.20), (0.26, 0.002, 0.34), "teal")],
        "snow_globe_glass": [("cyl", (0, 0, 0.025), (0.07, 0, 0.05), "brown"), ("ball", (0, 0, 0.11), (0.07, 0.07, 0.07), "glass")],
    },
    # D-1804: cold and perishable goods.
    3: {
        "ice_cream_tub": [("cone", (0, 0, 0.07), (0.07, 0.085, 0.14), "pink"), ("cyl", (0, 0, 0.145), (0.088, 0, 0.012), "white")],
        "fish": [("ball", (0, 0, 0.045), (0.18, 0.05, 0.045), "steel"), ("cone", (0.22, 0, 0.045), (0.0, 0.06, 0.08), "steel", (0, math.pi / 2, 0))],
        "flowers": [("cone", (0, 0, 0.10), (0.02, 0.06, 0.20), "paper"), ("ball", (0, 0, 0.24), (0.08, 0.08, 0.06), "pink"),
                    ("ball", (0.04, 0.03, 0.27), (0.04, 0.04, 0.04), "yellow")],
        "butter_block": [("cube", (0, 0, 0.03), (0.14, 0.07, 0.06), "cream"), ("cube", (0, 0, 0.061), (0.10, 0.05, 0.002), "blue")],
        "milk_bottle": [("cyl", (0, 0, 0.11), (0.045, 0, 0.22), "white"), ("cyl", (0, 0, 0.23), (0.025, 0, 0.03), "blue")],
        "egg_carton": [("cube", (0, 0, 0.035), (0.30, 0.12, 0.07), "paper")] + [
            ("ball", (-0.11 + 0.044 * i, 0, 0.075), (0.02, 0.02, 0.022), "cream") for i in range(6)],
        "frozen_peas": [("cube", (0, 0, 0.04), (0.18, 0.06, 0.08), "green"), ("ball", (0, -0.031, 0.04), (0.03, 0.002, 0.03), "ice")],
        "strawberries": [("cube", (0, 0, 0.04), (0.16, 0.12, 0.08), "glass")] + [
            ("ball", (-0.04 + 0.04 * i, 0, 0.07), (0.02, 0.02, 0.025), "red") for i in range(3)],
        "yogurt_pack": [("cyl", (-0.04, -0.04, 0.05), (0.035, 0, 0.10), "white"), ("cyl", (0.04, -0.04, 0.05), (0.035, 0, 0.10), "white"),
                        ("cyl", (-0.04, 0.04, 0.05), (0.035, 0, 0.10), "white"), ("cyl", (0.04, 0.04, 0.05), (0.035, 0, 0.10), "white")],
        "frozen_pizza": [("cube", (0, 0, 0.02), (0.32, 0.32, 0.04), "red"), ("cyl", (0, 0, 0.041), (0.12, 0, 0.002), "yellow")],
    },
    # D-1805: big and odd goods.
    4: {
        "bicycle": [("cyl", (-0.45, 0, 0.33), (0.33, 0, 0.04), "black", (math.pi / 2, 0, 0)), ("cyl", (0.45, 0, 0.33), (0.33, 0, 0.04), "black", (math.pi / 2, 0, 0)),
                    ("cube", (0, 0, 0.50), (0.90, 0.04, 0.04), "red"), ("cube", (-0.15, 0, 0.68), (0.20, 0.08, 0.04), "black"),
                    ("cube", (0.40, 0, 0.75), (0.04, 0.45, 0.03), "steel")],
        "rolled_mattress": [("cyl", (0, 0, 0.25), (0.25, 0, 1.0), "white", (0, math.pi / 2, 0)), ("cyl", (0, 0, 0.25), (0.255, 0, 0.12), "blue", (0, math.pi / 2, 0))],
        "potted_plant": [("cone", (0, 0, 0.13), (0.12, 0.16, 0.26), "terracotta"), ("ball", (0, 0, 0.50), (0.25, 0.25, 0.30), "leaf")],
        "fish_tank": [("cube", (0, 0, 0.18), (0.60, 0.30, 0.36), "glass"), ("cube", (0, 0, 0.02), (0.62, 0.32, 0.04), "black"),
                      ("cube", (0, 0, 0.36), (0.62, 0.32, 0.03), "black")],
        "guitar": [("ball", (0, 0, 0.25), (0.18, 0.06, 0.24), "brown"), ("cube", (0, 0, 0.70), (0.05, 0.03, 0.55), "brown"),
                   ("cube", (0, 0, 1.00), (0.08, 0.03, 0.10), "black")],
        "floor_lamp": [("cyl", (0, 0, 0.015), (0.16, 0, 0.03), "black"), ("cyl", (0, 0, 0.75), (0.015, 0, 1.45), "steel"),
                       ("cone", (0, 0, 1.50), (0.22, 0.12, 0.25), "cream")],
        "rolled_rug": [("cyl", (0, 0, 0.12), (0.12, 0, 1.6), "red", (0, math.pi / 2, 0)), ("cyl", (0.81, 0, 0.12), (0.12, 0, 0.02), "yellow", (0, math.pi / 2, 0))],
        "armchair": [("cube", (0, 0, 0.22), (0.80, 0.75, 0.44), "teal"), ("cube", (0, 0.30, 0.62), (0.80, 0.15, 0.40), "teal"),
                     ("cube", (-0.36, 0, 0.52), (0.10, 0.75, 0.20), "teal"), ("cube", (0.36, 0, 0.52), (0.10, 0.75, 0.20), "teal")],
        "surfboard": [("ball", (0, 0, 0.04), (0.28, 0.95, 0.04), "yellow"), ("cube", (0, 0, 0.081), (0.02, 1.6, 0.002), "red")],
        "drum": [("cyl", (0, 0, 0.18), (0.26, 0, 0.36), "red"), ("cyl", (0, 0, 0.365), (0.265, 0, 0.012), "white"),
                 ("cyl", (0, 0, -0.0), (0.265, 0, 0.012), "steel")],
    },
    # D-1821: district goods (coast, countryside, mountains, snow, volcano).
    5: {
        "coconuts": [("ball", (-0.07, 0, 0.07), (0.07, 0.07, 0.07), "brown"), ("ball", (0.07, 0, 0.07), (0.07, 0.07, 0.07), "brown"),
                     ("ball", (0, 0, 0.17), (0.07, 0.07, 0.07), "brown")],
        "cheese_wheel": [("cyl", (0, 0, 0.06), (0.18, 0, 0.12), "yellow"), ("cyl", (0, 0, 0.121), (0.17, 0, 0.002), "cream")],
        "volcanic_souvenir": [("cone", (0, 0, 0.08), (0.10, 0.03, 0.16), "black"), ("cyl", (0, 0, 0.165), (0.03, 0, 0.01), "lava")],
        "snow_globe": [("cyl", (0, 0, 0.03), (0.08, 0, 0.06), "blue"), ("ball", (0, 0, 0.13), (0.08, 0.08, 0.08), "ice"),
                       ("cone", (0, 0, 0.11), (0.03, 0.0, 0.07), "green")],
        "ski_pair": [("cube", (-0.04, 0, 0.85), (0.07, 0.02, 1.7), "red"), ("cube", (0.04, 0, 0.85), (0.07, 0.02, 1.7), "red")],
        "fishing_net": [("ball", (0, 0, 0.12), (0.30, 0.25, 0.12), "sand"), ("ball", (0.2, 0.1, 0.05), (0.05, 0.05, 0.05), "orange")],
        "honey_jar": [("cyl", (0, 0, 0.07), (0.055, 0, 0.14), "yellow"), ("cyl", (0, 0, 0.15), (0.058, 0, 0.02), "red")],
        "mountain_herbs": [("cube", (0, 0, 0.06), (0.16, 0.10, 0.12), "paper"), ("ball", (0, 0, 0.15), (0.08, 0.05, 0.06), "green")],
        "anchor_souvenir": [("cube", (0, 0, 0.15), (0.03, 0.03, 0.26), "steel"), ("cube", (0, 0, 0.05), (0.18, 0.03, 0.03), "steel"),
                            ("cyl", (0, 0, 0.29), (0.035, 0, 0.01), "steel", (math.pi / 2, 0, 0))],
        "wine_barrel": [("cyl", (0, 0, 0.25), (0.20, 0, 0.50), "brown"), ("cyl", (0, 0, 0.10), (0.205, 0, 0.03), "steel"),
                        ("cyl", (0, 0, 0.40), (0.205, 0, 0.03), "steel")],
    },
    # D-1822: dangerous and live goods.
    6: {
        "gas_cylinder": [("cyl", (0, 0, 0.30), (0.15, 0, 0.60), "orange"), ("cyl", (0, 0, 0.64), (0.04, 0, 0.08), "steel")],
        "fireworks_box": [("cube", (0, 0, 0.12), (0.40, 0.30, 0.24), "red"), ("cyl", (0.1, 0.08, 0.26), (0.02, 0, 0.06), "yellow"),
                          ("cyl", (-0.1, -0.08, 0.26), (0.02, 0, 0.06), "yellow")],
        "chicken_crate": [("cube", (0, 0, 0.18), (0.50, 0.35, 0.36), "wood"), ("ball", (0, 0, 0.24), (0.12, 0.09, 0.10), "white"),
                          ("cone", (0.13, 0, 0.26), (0.02, 0.0, 0.04), "yellow", (0, math.pi / 2, 0))],
        "cactus": [("cone", (0, 0, 0.07), (0.08, 0.10, 0.14), "terracotta"), ("cyl", (0, 0, 0.30), (0.05, 0, 0.32), "green"),
                   ("cyl", (0.07, 0, 0.32), (0.03, 0, 0.12), "green")],
        "beehive": [("cube", (0, 0, 0.20), (0.40, 0.40, 0.40), "yellow"), ("cube", (0, 0, 0.42), (0.44, 0.44, 0.04), "wood"),
                    ("cube", (0, -0.201, 0.05), (0.12, 0.002, 0.03), "black")],
        "parrot_cage": [("cyl", (0, 0, 0.02), (0.18, 0, 0.04), "steel"), ("cyl", (0, 0, 0.25), (0.17, 0, 0.42), "glass"),
                        ("ball", (0, 0, 0.22), (0.06, 0.05, 0.09), "green"), ("cone", (0, 0, 0.50), (0.17, 0.02, 0.10), "steel")],
        "turtle_tank": [("cube", (0, 0, 0.10), (0.40, 0.25, 0.20), "glass"), ("ball", (0, 0, 0.05), (0.08, 0.06, 0.03), "green")],
        "kerosene_lantern": [("cyl", (0, 0, 0.04), (0.07, 0, 0.08), "red"), ("cyl", (0, 0, 0.14), (0.05, 0, 0.12), "glass"),
                             ("cone", (0, 0, 0.23), (0.06, 0.02, 0.05), "red")],
        "chemistry_set": [("cube", (0, 0, 0.05), (0.36, 0.22, 0.10), "white"), ("cyl", (-0.1, 0, 0.14), (0.02, 0, 0.10), "glass"),
                          ("cyl", (0, 0, 0.14), (0.02, 0, 0.10), "purple"), ("cyl", (0.1, 0, 0.14), (0.02, 0, 0.10), "green")],
        "rabbit_hutch": [("cube", (0, 0, 0.20), (0.60, 0.40, 0.40), "wood"), ("cube", (0, -0.201, 0.20), (0.40, 0.002, 0.28), "steel"),
                         ("ball", (0.1, 0, 0.12), (0.07, 0.05, 0.06), "white")],
    },
}


def build(product_id, parts):
    kit.clear()
    for index, part in enumerate(parts):
        shape, centre, size, colour = part[:4]
        rot = part[4] if len(part) > 4 else (0, 0, 0)
        name = "%s_%d" % (product_id, index)
        if shape == "cube":
            kit.cube(name, centre, size, colour, rot=rot)
        elif shape == "cyl":
            kit.cylinder(name, centre, size[0], size[2], colour, verts=12, rot=rot)
        elif shape == "cone":
            kit.cone(name, centre, size[0], size[1], size[2], colour, verts=12, rot=rot)
        elif shape == "ball":
            kit.blob(name, centre, size, colour, subdivisions=2)
    # Rest the model on the floor (lowest point at z 0) and centre it on x/y, then add its box collision.
    import bpy
    from mathutils import Vector
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in bpy.context.scene.objects for c in o.bound_box]
    low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    shift = Vector((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z))
    for o in bpy.context.scene.objects:
        o.location += shift
    size = high - low
    kit.cube("%s-colonly" % product_id, (0, 0, size.z / 2), (size.x, size.y, size.z), "cardboard")
    kit.export(os.path.join(OUT, "sm_product_%s.glb" % product_id))
    print("PRODUCT", product_id, "size", tuple(round(v, 3) for v in size), "tris", kit.triangle_count())


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
    lots = sorted(LOTS) if not args or args[0] == "all" else [int(a) for a in args]
    for lot in lots:
        for product_id, parts in LOTS[lot].items():
            build(product_id, parts)


main()
