"""Low-poly customers who open the door (expansion D-1819), six variants, built in Blender's background mode:

    blender --background --python do-not-drop/assets/tools/build_customer_models.py

Each is a standing figure in the game's chunky low-poly style (legs, body, arms, a round head, hair or a hat and one
detail of its own), origin at the centre of its feet, in metres, with a "<id>-colonly" box Godot imports as its
simple collision. No rig: they wave and react by code (door_reaction.gd moves the whole figure).
Exported to assets/models/characters/customers/sm_customer_<id>.glb.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lowpoly_kit as kit  # noqa: E402

OUT = os.path.join(kit.ROOT, "models", "characters", "customers")
kit.PALETTE.update({
    "skin_a": (0.88, 0.66, 0.52, 1), "skin_b": (0.62, 0.42, 0.30, 1), "skin_c": (0.40, 0.26, 0.18, 1),
    "grey_hair": (0.78, 0.78, 0.80, 1), "dark_hair": (0.10, 0.07, 0.05, 1), "red_hair": (0.60, 0.22, 0.08, 1),
    "purple": (0.40, 0.18, 0.50, 1), "teal": (0.10, 0.45, 0.45, 1), "yellow": (0.95, 0.72, 0.10, 1),
    "denim": (0.15, 0.25, 0.45, 1), "white": (0.92, 0.92, 0.90, 1), "green": (0.20, 0.50, 0.22, 1),
    "brown": (0.32, 0.18, 0.08, 1), "pink": (0.90, 0.45, 0.55, 1), "black": (0.04, 0.04, 0.05, 1),
})

# id -> (height scale, skin, shirt, trousers, hair, extras)
CUSTOMERS = {
    "grandma": (0.92, "skin_a", "purple", "brown", "grey_hair", ["bun", "glasses"]),
    "cap_neighbour": (1.0, "skin_b", "teal", "denim", "dark_hair", ["cap"]),
    "braids_girl": (0.95, "skin_c", "yellow", "denim", "dark_hair", ["braids"]),
    "moustache_man": (1.05, "skin_a", "green", "black", "red_hair", ["moustache"]),
    "kid": (0.70, "skin_b", "pink", "denim", "dark_hair", ["backpack"]),
    "cook": (1.0, "skin_c", "white", "black", "dark_hair", ["chef_hat", "apron"]),
}


def figure(cid, spec):
    h, skin, shirt, trousers, hair, extras = spec
    kit.clear()
    s = lambda v: v * h  # noqa: E731
    for side in (-1, 1):
        kit.cube("%s_leg" % cid, (side * s(0.09), 0, s(0.40)), (s(0.13), s(0.15), s(0.80)), trousers)
        kit.cube("%s_shoe" % cid, (side * s(0.09), -s(0.03), s(0.04)), (s(0.15), s(0.22), s(0.08)), "black")
        kit.cube("%s_arm" % cid, (side * s(0.26), 0, s(1.08)), (s(0.10), s(0.12), s(0.55)), shirt)
        kit.cube("%s_hand" % cid, (side * s(0.26), 0, s(0.78)), (s(0.09), s(0.09), s(0.09)), skin)
    kit.cube("%s_body" % cid, (0, 0, s(1.10)), (s(0.42), s(0.24), s(0.62)), shirt, bevel=s(0.03))
    kit.blob("%s_head" % cid, (0, 0, s(1.58)), (s(0.16), s(0.16), s(0.18)), skin, subdivisions=2)
    kit.blob("%s_hair" % cid, (0, s(0.02), s(1.66)), (s(0.17), s(0.17), s(0.11)), hair, subdivisions=2)
    for eye in (-1, 1):
        kit.cube("%s_eye" % cid, (eye * s(0.06), -s(0.15), s(1.60)), (s(0.03), s(0.01), s(0.04)), "black")
    if "bun" in extras:
        kit.blob("%s_bun" % cid, (0, s(0.08), s(1.80)), (s(0.08), s(0.08), s(0.07)), hair)
    if "glasses" in extras:
        kit.cube("%s_glasses" % cid, (0, -s(0.16), s(1.61)), (s(0.22), s(0.01), s(0.05)), "black")
    if "cap" in extras:
        kit.cylinder("%s_cap" % cid, (0, 0, s(1.74)), s(0.17), s(0.08), "teal", verts=12)
        kit.cube("%s_visor" % cid, (0, -s(0.17), s(1.71)), (s(0.22), s(0.14), s(0.02)), "teal")
    if "braids" in extras:
        for side in (-1, 1):
            kit.cube("%s_braid" % cid, (side * s(0.15), s(0.04), s(1.40)), (s(0.05), s(0.05), s(0.32)), hair)
    if "moustache" in extras:
        kit.cube("%s_moustache" % cid, (0, -s(0.16), s(1.52)), (s(0.14), s(0.02), s(0.03)), hair)
    if "backpack" in extras:
        kit.cube("%s_backpack" % cid, (0, s(0.18), s(1.12)), (s(0.34), s(0.14), s(0.40)), "yellow")
    if "chef_hat" in extras:
        kit.cylinder("%s_hat" % cid, (0, 0, s(1.86)), s(0.15), s(0.22), "white", verts=12)
    if "apron" in extras:
        kit.cube("%s_apron" % cid, (0, -s(0.125), s(0.90)), (s(0.36), s(0.01), s(0.70)), "white")
    kit.cube("%s-colonly" % cid, (0, 0, s(0.95)), (s(0.60), s(0.40), s(1.90)), "cardboard")
    kit.export(os.path.join(OUT, "sm_customer_%s.glb" % cid))
    print("CUSTOMER", cid, "tris", kit.triangle_count())


for customer_id, customer in CUSTOMERS.items():
    figure(customer_id, customer)
