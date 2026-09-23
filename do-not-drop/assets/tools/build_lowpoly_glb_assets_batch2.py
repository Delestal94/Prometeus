"""Batch 2 of the authored low-poly GLB library for Take My Package (2026-09-23).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_lowpoly_glb_assets_batch2.py

Fills the gaps listed in docs/inventario-assets.md: a warning sign per route
segment type, road furniture (guardrail, bridge railing), yard dressing for the
delivery houses, two more house shapes plus a barn, distant landmarks, sky and
horizon pieces, and the handheld phone and viewmodel gloves. The delivery van is
deliberately absent: Slatex is replacing it.

Conventions (same as batch 1): origin at the centre of the base, metres, flat
materials embedded in the GLB. Anything meant to face the road or the player
faces Blender +Y, which the glTF exporter turns into Godot's forward (-Z).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from lowpoly_kit import (ROOT, blob, clear, cone, cube, cylinder, export, roof,  # noqa: E402
                         triangle_count)

M = os.path.join(ROOT, "models")
SIGNS = os.path.join(M, "environment", "signs")
PROPS = os.path.join(M, "environment", "props")
YARD = os.path.join(M, "environment", "yard")
LANDMARKS = os.path.join(M, "environment", "landmarks")
SKY = os.path.join(M, "environment", "sky")
ARCH = os.path.join(M, "architecture")
HANDHELD = os.path.join(M, "props", "handheld")
CHARS = os.path.join(M, "characters")
FACE = 0.04  # symbols sit this far in front of a sign panel
# Signs are read from the front (+Y), where Blender's +X is on the viewer's
# LEFT. Symbol helpers take x/angles as the driver sees them and flip here.
VIEW_X = -1
REPORT = []


def done(path):
    REPORT.append((os.path.relpath(path, ROOT), triangle_count()))
    export(path)


# --- Road signs -------------------------------------------------------------

def sign_post(height=2.0):
    cylinder("SignPost", (0, 0, height / 2), 0.045, height, "metal", 8)


def diamond_panel(z=2.0, size=0.82):
    cube("SignBorder", (0, 0, z), (size + 0.08, 0.035, size + 0.08), "sign_ink", 0.01, rot=(0, math.pi / 4, 0))
    cube("SignPanel", (0, 0.012, z), (size, 0.035, size), "warning", 0.01, rot=(0, math.pi / 4, 0))


def ink(name, x, z, w, h, angle=0.0, material="sign_ink"):
    # Flat stroke on the sign face. A positive `angle` leans the top of the
    # stroke to the driver's right.
    cube(name, (x * VIEW_X, FACE, z), (w, 0.02, h), material, rot=(0, angle * VIEW_X, 0))


def dot(name, x, z, size, material="sign_ink"):
    blob(name, (x * VIEW_X, FACE, z), (size[0], 0.012, size[1]), material)


def flat_triangle(name, x, z, size, material, angle=0.0, y=FACE):
    # A 3-sided cone laid flat on the face; angle 0 points up, +pi/2 to the
    # driver's right.
    return cone(name, (x * VIEW_X, y, z), size, 0.0, 0.02, material, 3, rot=(math.pi / 2, angle * VIEW_X, 0))


def sign(kind):
    clear()
    sign_post()
    if kind == "curve":
        diamond_panel()
        ink("CurveStem", -0.08, 1.86, 0.09, 0.30)
        ink("CurveBend", 0.0, 2.08, 0.09, 0.24, angle=math.pi / 4)
        flat_triangle("ArrowHead", 0.1, 2.18, 0.13, "sign_ink", math.pi / 4)
    elif kind == "speed_bump":
        diamond_panel()
        ink("Road", 0, 1.84, 0.46, 0.05)
        for x in (-0.12, 0.12):
            dot("Bump", x, 1.88, (0.09, 0.07))
    elif kind == "narrow_bridge":
        diamond_panel()
        ink("SideLeft", -0.1, 2.0, 0.07, 0.46, angle=0.28)
        ink("SideRight", 0.1, 2.0, 0.07, 0.46, angle=-0.28)
    elif kind == "gravel":
        diamond_panel()
        ink("Road", 0, 1.84, 0.46, 0.05)
        for x, z in [(-0.14, 1.95), (0.02, 2.02), (0.15, 1.93), (-0.03, 2.12), (0.1, 2.14), (-0.12, 2.08)]:
            dot("Pebble", x, z, (0.035, 0.03))
    elif kind == "roadworks":
        cone("SignBorder", (0, 0, 2.0), 0.62, 0.0, 0.035, "danger", 3, rot=(math.pi / 2, 0, 0))
        cone("SignPanel", (0, 0.012, 1.98), 0.46, 0.0, 0.035, "sign_white", 3, rot=(math.pi / 2, 0, 0))
        ink("Worker", -0.02, 1.93, 0.06, 0.18, angle=0.3)
        dot("WorkerHead", -0.06, 2.06, (0.035, 0.035))
        dot("Pile", 0.1, 1.83, (0.1, 0.05))
    elif kind == "delivery_ahead":
        cube("SignBorder", (0, 0, 2.0), (0.9, 0.035, 0.62), "sign_white", 0.02)
        cube("SignPanel", (0, 0.012, 2.0), (0.82, 0.035, 0.54), "mint", 0.02)
        ink("HouseIcon", -0.18, 1.95, 0.2, 0.16, material="sign_white")
        flat_triangle("HouseRoof", -0.18, 2.08, 0.16, "sign_white")
        ink("ArrowShaft", 0.12, 2.0, 0.2, 0.06, material="sign_white")
        flat_triangle("ArrowHead", 0.25, 2.0, 0.09, "sign_white", math.pi / 2)
    done(os.path.join(SIGNS, "sm_env_sign_%s.glb" % kind))


# --- Road furniture ---------------------------------------------------------

def guardrail():
    clear()
    for x in (-1.9, 0.0, 1.9):
        cube("GuardrailPost", (x, 0, 0.4), (0.1, 0.1, 0.8), "metal")
    cube("GuardrailBeam", (0, 0.07, 0.62), (4.0, 0.06, 0.3), "guardrail", 0.015)
    cube("GuardrailReflector", (0, 0.105, 0.62), (0.12, 0.01, 0.08), "danger")
    done(os.path.join(PROPS, "sm_env_prop_guardrail.glb"))


def bridge_railing():
    clear()
    for x in (-2.8, -1.4, 0.0, 1.4, 2.8):
        cube("RailingPost", (x, 0, 0.5), (0.18, 0.18, 1.0), "concrete", 0.02)
    for z in (0.45, 0.95):
        cube("RailingBar", (0, 0, z), (6.0, 0.1, 0.1), "guardrail", 0.01)
    cube("RailingCurb", (0, 0, 0.08), (6.0, 0.35, 0.16), "concrete", 0.02)
    done(os.path.join(PROPS, "sm_env_prop_bridge_railing.glb"))


def roadside(kind):
    clear()
    if kind == "hay_bale":
        cylinder("HayBale", (0, 0, 0.6), 0.6, 1.2, "hay", 10, rot=(math.pi / 2, 0, 0))
        for y in (-0.3, 0.3):
            cylinder("BaleTwine", (0, y, 0.6), 0.61, 0.05, "trunk", 10, rot=(math.pi / 2, 0, 0))
    elif kind == "wooden_crate":
        cube("Crate", (0, 0, 0.45), (0.9, 0.9, 0.9), "wood", 0.02)
        for rot in (0.785, -0.785):
            cube("CrateBrace", (0, 0.46, 0.45), (1.1, 0.03, 0.1), "trim", rot=(0, rot, 0))
    elif kind == "pallet":
        for x in (-0.5, 0.0, 0.5):
            cube("PalletBlock", (x, 0, 0.05), (0.12, 0.8, 0.1), "wood")
        for y in (-0.32, -0.11, 0.11, 0.32):
            cube("PalletSlat", (0, y, 0.125), (1.2, 0.14, 0.03), "trim")
    elif kind == "fire_hydrant":
        cylinder("HydrantBody", (0, 0, 0.35), 0.13, 0.7, "danger", 10)
        blob("HydrantCap", (0, 0, 0.72), (0.14, 0.14, 0.08), "danger")
        cylinder("HydrantCollar", (0, 0, 0.62), 0.16, 0.06, "metal", 10)
        for x in (-0.16, 0.16):
            cylinder("HydrantNozzle", (x, 0, 0.45), 0.05, 0.12, "metal", 8, rot=(0, math.pi / 2, 0))
    elif kind == "bus_stop":
        for x in (-1.3, 1.3):
            cube("ShelterPost", (x, -0.5, 1.2), (0.08, 0.08, 2.4), "metal")
        cube("ShelterRoof", (0, 0, 2.45), (2.9, 1.4, 0.1), "metal", 0.02)
        cube("ShelterBack", (0, -0.55, 1.3), (2.6, 0.04, 1.6), "window")
        cube("ShelterBench", (0, -0.25, 0.48), (2.2, 0.4, 0.07), "wood")
        cylinder("BusSignPole", (1.7, 0.3, 1.3), 0.04, 2.6, "metal", 8)
        cylinder("BusSign", (1.7, 0.3, 2.5), 0.25, 0.04, "mint", 12, rot=(math.pi / 2, 0, 0))
    elif kind == "milestone":
        cube("Milestone", (0, 0, 0.4), (0.35, 0.18, 0.8), "plaster", 0.04)
        cube("MilestoneCap", (0, 0, 0.76), (0.37, 0.2, 0.1), "mint", 0.02)
    done(os.path.join(PROPS, "sm_env_prop_%s.glb" % kind))


# --- Yard dressing for delivery houses --------------------------------------

def yard(kind):
    clear()
    if kind == "picket_fence":
        for i in range(9):
            x = -0.88 + i * 0.22
            cube("Picket", (x, 0, 0.45), (0.1, 0.04, 0.9), "sign_white")
            cone("PicketTip", (x, 0, 0.95), 0.07, 0.0, 0.1, "sign_white", 4)
        for z in (0.25, 0.7):
            cube("FenceRail", (0, -0.03, z), (2.0, 0.04, 0.08), "sign_white")
    elif kind == "flower_pot":
        cone("Pot", (0, 0, 0.2), 0.16, 0.22, 0.4, "wall", 8)
        blob("Soil", (0, 0, 0.4), (0.2, 0.2, 0.04), "trunk")
        for i in range(5):
            a = i * math.tau / 5
            blob("Bloom", (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.5), (0.07, 0.07, 0.06), "flower")
        blob("Foliage", (0, 0, 0.45), (0.17, 0.17, 0.08), "leaf")
    elif kind == "garden_gnome":
        cone("GnomeBody", (0, 0, 0.14), 0.12, 0.08, 0.28, "window", 8)
        blob("GnomeFace", (0, 0.02, 0.33), (0.07, 0.07, 0.07), "skin_gnome")
        cone("GnomeBeard", (0, 0.05, 0.26), 0.07, 0.0, 0.14, "sign_white", 6, rot=(math.pi, 0, 0))
        cone("GnomeHat", (0, 0, 0.47), 0.08, 0.0, 0.22, "danger", 8)
    elif kind == "dog_house":
        cube("DogHouseWalls", (0, 0, 0.4), (0.9, 1.0, 0.8), "barn_red", 0.02)
        roof("DogHouseRoof", 0.95, 0.9, 1.0, "roof_blue", 0.6)
        cube("DogHouseDoor", (0, 0.48, 0.3), (0.38, 0.06, 0.5), "sign_ink")
    elif kind == "doormat":
        cube("Doormat", (0, 0, 0.01), (0.9, 0.55, 0.02), "cardboard", 0.005)
        cube("DoormatStripe", (0, 0, 0.021), (0.8, 0.08, 0.004), "mint")
    done(os.path.join(YARD, "sm_env_yard_%s.glb" % kind))


# --- Architecture -----------------------------------------------------------

def windows_row(z, width, depth, count, facing=1):
    for i in range(count):
        x = -width * 0.35 + i * (width * 0.7 / max(count - 1, 1))
        cube("Window", (x, facing * (depth / 2 + 0.04), z), (0.9, 0.09, 0.85), "window", 0.02)
        cube("WindowTrim", (x, facing * (depth / 2 + 0.075), z + 0.48), (1.06, 0.12, 0.08), "trim")


def house(variant):
    clear()
    if variant == "two_story":
        width, depth = 6.0, 5.0
        cube("HouseWalls", (0, 0, 2.8), (width, depth, 5.6), "plaster", 0.08)
        roof("PitchedRoof", 5.9, width, depth, "roof")
        windows_row(1.9, width, depth, 2)
        windows_row(4.4, width, depth, 3)
        cube("FrontDoor", (0, depth / 2 + 0.035, 1.05), (1.12, 0.1, 2.1), "wood", 0.03)
        cube("Porch", (0, depth / 2 + 0.65, 0.15), (2.4, 1.35, 0.3), "wood", 0.04)
        cube("PorchAwning", (0, depth / 2 + 0.7, 2.55), (2.6, 1.4, 0.12), "roof", 0.02)
        cube("Chimney", (-width * 0.3, 0, 6.6), (0.55, 0.55, 1.8), "chimney")
    elif variant == "farmhouse":
        width, depth = 7.0, 4.6
        cube("HouseWalls", (0, 0, 1.6), (width, depth, 3.2), "wall", 0.08)
        roof("PitchedRoof", 3.45, width, depth, "roof_blue")
        cube("Wing", (width * 0.32, -depth * 0.7, 1.4), (2.6, 3.4, 2.8), "wall", 0.06)
        windows_row(1.95, width, depth, 3)
        cube("FrontDoor", (-0.4, depth / 2 + 0.035, 1.05), (1.12, 0.1, 2.1), "wood", 0.03)
        cube("WrapPorch", (0, depth / 2 + 0.9, 0.15), (width + 0.4, 1.8, 0.3), "wood", 0.04)
        for x in (-3.2, -1.1, 1.1, 3.2):
            cube("PorchPost", (x, depth / 2 + 1.65, 1.3), (0.13, 0.13, 2.3), "wood")
        cube("PorchRoof", (0, depth / 2 + 0.95, 2.5), (width + 0.6, 1.95, 0.12), "roof_blue", 0.02)
    done(os.path.join(ARCH, "sm_arch_delivery_house_%s.glb" % variant))


def barn():
    clear()
    width, depth = 8.0, 12.0
    cube("BarnWalls", (0, 0, 2.5), (width, depth, 5.0), "barn_red", 0.08)
    # Gambrel roof: a steep lower pitch and a shallow upper one.
    for x, angle in [(-width * 0.36, -1.0), (width * 0.36, 1.0)]:
        cube("BarnRoofLower", (x, 0, 5.75), (width * 0.34, depth * 1.06, 0.2), "roof", 0.03, rot=(0, angle, 0))
    for x, angle in [(-width * 0.17, -0.35), (width * 0.17, 0.35)]:
        cube("BarnRoofUpper", (x, 0, 6.85), (width * 0.38, depth * 1.06, 0.2), "roof", 0.03, rot=(0, angle, 0))
    cube("BarnDoor", (0, depth / 2 + 0.04, 1.7), (3.2, 0.08, 3.4), "barn_red", 0.02)
    for rot in (0.82, -0.82):
        cube("BarnDoorBrace", (0, depth / 2 + 0.09, 1.7), (4.4, 0.05, 0.16), "sign_white", rot=(0, rot, 0))
    cube("BarnDoorFrame", (0, depth / 2 + 0.09, 3.45), (3.4, 0.06, 0.16), "sign_white")
    cube("HayLoft", (0, depth / 2 + 0.04, 5.3), (1.4, 0.08, 1.2), "sign_ink")
    done(os.path.join(ARCH, "sm_arch_barn.glb"))


# --- Distant landmarks ------------------------------------------------------

def water_tower():
    clear()
    for x, y in [(-1.6, -1.6), (1.6, -1.6), (-1.6, 1.6), (1.6, 1.6)]:
        cube("TowerLeg", (x * 0.8, y * 0.8, 5.0), (0.25, 0.25, 10.0), "metal")
    cube("TowerBraceX", (0, 0, 5.0), (2.8, 0.12, 0.12), "metal")
    cube("TowerBraceY", (0, 0, 5.0), (0.12, 2.8, 0.12), "metal")
    cylinder("Tank", (0, 0, 11.6), 2.6, 3.2, "water_tank", 12)
    cone("TankRoof", (0, 0, 13.8), 2.8, 0.2, 1.2, "water_tank", 12)
    cylinder("TankBand", (0, 0, 11.6), 2.62, 0.5, "mint", 12)
    done(os.path.join(LANDMARKS, "sm_env_landmark_water_tower.glb"))


def windmill():
    clear()
    cone("MillTower", (0, 0, 5.0), 2.0, 1.2, 10.0, "plaster", 8)
    cone("MillCap", (0, 0, 10.7), 1.6, 0.2, 1.6, "roof", 8)
    cube("MillDoor", (0, 1.62, 1.0), (1.0, 0.1, 2.0), "wood")
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 1.6, 9.2))
    rotor = bpy.context.object
    rotor.name = "WindmillRotor"  # spin this node around its local Z in Godot (Blender +Y)
    hub = cylinder("RotorHub", (0, 1.8, 9.2), 0.35, 0.5, "metal", 8, rot=(math.pi / 2, 0, 0))
    parts = [hub]
    for i in range(4):
        a = i * math.pi / 2
        c, s = math.cos(a), math.sin(a)
        parts.append(cube("Sail", (c * 2.6, 1.95, 9.2 + s * 2.6), (4.6, 0.06, 0.9), "sign_white", rot=(0, -a, 0)))
        parts.append(cube("SailArm", (c * 2.6, 1.9, 9.2 + s * 2.6), (5.0, 0.12, 0.12), "wood", rot=(0, -a, 0)))
    for p in parts:
        p.parent = rotor
        p.matrix_parent_inverse = rotor.matrix_world.inverted()
    done(os.path.join(LANDMARKS, "sm_env_landmark_windmill.glb"))


# --- Sky and horizon --------------------------------------------------------

def cloud(variant):
    clear()
    puffs = {
        "a": [((0, 0, 1.5), (6, 3.5, 2.2)), ((4, 0.5, 1.2), (4, 3, 1.8)), ((-4, -0.4, 1.1), (4, 3, 1.6)), ((1, 0, 3), (3.5, 2.6, 1.8))],
        "b": [((0, 0, 1.2), (9, 3, 1.5)), ((-5, 0, 1.0), (4, 2.5, 1.2)), ((5, 0.3, 1.3), (5, 2.8, 1.6))],
        "c": [((0, 0, 1.8), (4, 3.2, 2.6)), ((2.6, 0, 1.4), (3, 2.4, 1.8)), ((-2.4, 0.3, 1.3), (2.8, 2.2, 1.6))],
    }[variant]
    for loc, size in puffs:
        blob("CloudPuff", loc, size, "cloud")
    cube("CloudFlatBase", (0, 0, 0.3), (14 if variant == "b" else 10, 4, 0.6), "cloud", 0.2)
    done(os.path.join(SKY, "sm_env_sky_cloud_%s.glb" % variant))


def horizon():
    # A closed ring of low peaks, 450 m radius. Keep it centred on the camera in
    # Godot (x/z only) so the world never ends in a flat line.
    clear()
    count, radius = 56, 450.0
    for i in range(count):
        a = i * math.tau / count
        jitter = (math.sin(i * 12.9898) * 43758.5453) % 1.0
        height = 45 + jitter * 85
        width = 38 + ((i * 7) % 5) * 6
        cone("Peak", (math.cos(a) * radius, math.sin(a) * radius, height / 2), width, 0.0, height, "mountain_far", 5)
        if height > 110:
            cone("SnowCap", (math.cos(a) * radius, math.sin(a) * radius, height - 9), width * 0.2, 0.0, 18, "mountain_snow", 5)
    done(os.path.join(SKY, "sm_env_horizon_mountains.glb"))


# --- Handheld and viewmodel -------------------------------------------------

def phone():
    clear()
    cube("PhoneBody", (0, 0, 0.08), (0.075, 0.01, 0.16), "phone", 0.004)
    cube("PhoneScreen", (0, 0.0055, 0.082), (0.066, 0.002, 0.142), "screen")
    cylinder("CameraLens", (0.02, -0.006, 0.14), 0.007, 0.004, "sign_ink", 10, rot=(math.pi / 2, 0, 0))
    done(os.path.join(HANDHELD, "sm_prop_phone.glb"))


def glove(side):
    # Origin at the wrist, fingers pointing +Z, palm facing +Y. `PlayerTint` on
    # the sleeve cuff is recoloured per peer in Godot (docs/direccion-visual.md 8).
    clear()
    s = 1 if side == "right" else -1
    cylinder("Sleeve", (0, 0, -0.07), 0.05, 0.14, "PlayerTint", 10)
    cylinder("Cuff", (0, 0, 0.005), 0.052, 0.03, "glove", 10)
    cube("Palm", (0, 0, 0.065), (0.09, 0.035, 0.1), "glove", 0.008)
    for i, x in enumerate((-0.033, -0.011, 0.011, 0.033)):
        length = (0.045, 0.052, 0.05, 0.04)[i]
        cube("FingerBase", (x * s, 0.004, 0.115 + length / 2), (0.019, 0.026, length), "glove", 0.004, rot=(0.25, 0, 0))
        cube("FingerTip", (x * s, 0.018, 0.118 + length + 0.014), (0.017, 0.024, 0.03), "glove", 0.004, rot=(0.7, 0, 0))
    cube("Thumb", (0.052 * s, 0.012, 0.075), (0.022, 0.026, 0.055), "glove", 0.004, rot=(0.2, -0.6 * s, 0))
    done(os.path.join(CHARS, "sm_char_viewmodel_glove_%s.glb" % side))


# Signs, road furniture, yard pieces, the two extra houses and the barn moved
# to build_lowpoly_refined.py (2026-09-23). The 3D clouds were retired: the
# sky shader paints them now (shaders/stylized_sky.gdshader).
bridge_railing()
water_tower()
windmill()
horizon()
phone()
for side in ("left", "right"):
    glove(side)

print("BATCH2_REPORT")
for path, tris in REPORT:
    print("  %-70s %6d tris" % (path, tris))
print("BATCH2_COUNT", len(REPORT))
