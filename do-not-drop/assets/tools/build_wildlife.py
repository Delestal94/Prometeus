"""Low-poly wildlife for Take My Package (2026-09-24).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_wildlife.py

Animals: rabbit, frog and bird, plus the yellow "animal crossing" warning
sign that goes up before a deer crossing. (The deer itself is Quaternius'
rigged "Stag", CC0 -- sm_env_animal_stag_rigged.glb; the deer() builder
below is kept as reference but no longer exported.)

They're animated in Godot by code (scripts/presentation/wildlife_animal.gd),
not by an armature: each moving part is its own node hanging from a pivot
empty placed at the joint -- a leg from its hip, the neck from the
shoulders, a wing from its root -- so turning the pivot swings the part the
way the real joint would. Pivot names are the contract with that script:

  deer    Leg_FL Leg_FR Leg_BL Leg_BR (each > Leg_XX_Lower)  Neck > Head  Tail
  rabbit  Legs_Front Legs_Back  Ears  Tail
  frog    Legs_Front Legs_Back  Throat
  bird    Wing_L Wing_R  Head  Tail

Conventions as the rest of the kit: metres, origin at the centre of the
base (between the feet), front on Blender +Y (Godot -Z).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from lowpoly_kit import (PALETTE, ROOT, blob, circle_points, clear, cone, cube, cylinder,  # noqa: E402
                         export, flat_poly, jitter, mat, triangle_count)

PALETTE.update({
    # Linear values, like the rest of the kit (an sRGB-looking number here
    # comes out washed out and pale in the game).
    "deer_fur": (0.16, 0.065, 0.02, 1), "deer_belly": (0.45, 0.30, 0.16, 1),
    "deer_dark": (0.02, 0.012, 0.01, 1), "antler": (0.36, 0.27, 0.15, 1),
    "rabbit_fur": (0.17, 0.12, 0.075, 1), "rabbit_light": (0.70, 0.66, 0.58, 1),
    "rabbit_ear": (0.50, 0.20, 0.16, 1),
    "frog_green": (0.05, 0.21, 0.03, 1), "frog_belly": (0.42, 0.47, 0.16, 1),
    "frog_spot": (0.015, 0.06, 0.01, 1),
    "bird_back": (0.08, 0.045, 0.025, 1), "bird_breast": (0.78, 0.16, 0.03, 1),
    "beak": (0.85, 0.45, 0.03, 1), "eye_white": (0.9, 0.9, 0.85, 1),
})

M = os.path.join(ROOT, "models", "environment")
WILDLIFE = os.path.join(M, "wildlife")
SIGNS = os.path.join(M, "signs")
REPORT = []


def done(path):
    REPORT.append((os.path.relpath(path, ROOT), triangle_count()))
    export(path)


def pivot(name, loc, parent=None):
    """An empty at a joint; everything parented to it turns around it."""
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.location = loc
    if parent is not None:
        attach(empty, parent)
    return empty


def attach(obj, parent):
    # matrix_world is only refreshed on a view-layer update: read it stale
    # and a freshly placed pivot snaps to the origin, so every joint turned
    # around the animal's feet instead of its hip or shoulder.
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world
    return obj


def limb(name, start, end, r0, r1, material, verts=6):
    """A tapered cylinder from `start` to `end`."""
    a, b = Vector(start), Vector(end)
    mid = (a + b) / 2
    o = cone(name, mid, r0, r1, (b - a).length, material, verts)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, -1)).rotation_difference(b - a)
    bpy.context.view_layer.update()
    return o


def eye(name, loc, radius, parent, pupil=True):
    white = attach(blob(name, loc, (radius, radius, radius), "eye_white"), parent)
    if pupil:
        attach(blob(name + "Pupil", (loc[0] * 1.08, loc[1] + radius * 0.55, loc[2]), (radius * 0.55,) * 3, "deer_dark"), parent)
    return white


# =============================================================================
# Deer: about 1.2 m at the shoulder, deep chest, a small rack of antlers.
# Legs bend at the knee (front) and hock (hind): Leg_XX turns at the
# shoulder/hip, Leg_XX_Lower at the knee/hock.
# =============================================================================

def deer():
    clear()
    root = pivot("Deer", (0, 0, 0))
    # Torso from three overlapping masses -- chest, barrel, haunches -- so the
    # silhouette dips behind the shoulders instead of reading as one egg.
    attach(jitter(blob("Barrel", (0, 0.0, 1.04), (0.24, 0.5, 0.25), "deer_fur", 2), 0.018, 3), root)
    attach(jitter(blob("Chest", (0, 0.36, 1.0), (0.23, 0.24, 0.3), "deer_fur", 2), 0.015, 5), root)
    attach(jitter(blob("Haunch", (0, -0.4, 1.07), (0.235, 0.26, 0.27), "deer_fur", 2), 0.015, 6), root)
    attach(blob("Belly", (0, 0.02, 0.88), (0.18, 0.42, 0.11), "deer_belly", 1), root)
    attach(blob("RumpPatch", (0, -0.61, 1.1), (0.15, 0.05, 0.16), "rabbit_light", 1), root)
    attach(blob("ChestPatch", (0, 0.55, 1.02), (0.12, 0.06, 0.16), "deer_belly", 1), root)
    legs = [
        # name, x, hip (y, z), joint (y, z), hoof y, upper radii, front?
        ("Leg_FL", -0.12, (0.4, 1.02), (0.44, 0.52), 0.46, (0.085, 0.05), True),
        ("Leg_FR", 0.12, (0.4, 1.02), (0.44, 0.52), 0.46, (0.085, 0.05), True),
        ("Leg_BL", -0.13, (-0.42, 1.06), (-0.54, 0.5), -0.48, (0.11, 0.055), False),
        ("Leg_BR", 0.13, (-0.42, 1.06), (-0.54, 0.5), -0.48, (0.11, 0.055), False),
    ]
    for name, x, hip, joint, hoof_y, radii, front in legs:
        upper = pivot(name, (x, hip[0], hip[1]), root)
        # Starts inside the body so the top of the leg never shows a seam.
        attach(limb(name + "Upper", (x, hip[0], hip[1] + 0.1), (x, joint[0], joint[1]), radii[0], radii[1], "deer_fur", 7), upper)
        if not front:
            # A rounded thigh, riding with the leg so it never pulls away.
            attach(jitter(blob(name + "Thigh", (x * 1.15, hip[0] - 0.03, hip[1] - 0.2), (0.075, 0.12, 0.2), "deer_fur", 1), 0.01, 9), upper)
        lower = pivot(name + "_Lower", (x, joint[0], joint[1]), upper)
        attach(blob(name + "Joint", (x, joint[0], joint[1]), (0.045, 0.05, 0.05), "deer_fur", 1), lower)
        attach(limb(name + "Lower", (x, joint[0], joint[1]), (x, hoof_y, 0.09), 0.04, 0.03, "deer_fur", 6), lower)
        attach(cube(name + "Hoof", (x, hoof_y + 0.02, 0.045), (0.065, 0.09, 0.09), "deer_dark", 0.012), lower)
    # Neck rising from the chest; the head at its tip.
    neck = pivot("Neck", (0, 0.42, 1.16), root)
    attach(jitter(blob("NeckBase", (0, 0.47, 1.22), (0.15, 0.14, 0.17), "deer_fur", 1), 0.01, 12), neck)
    attach(limb("NeckMesh", (0, 0.38, 1.08), (0, 0.62, 1.6), 0.15, 0.085, "deer_fur", 8), neck)
    attach(limb("Throat", (0, 0.46, 1.02), (0, 0.66, 1.5), 0.1, 0.06, "deer_belly", 7), neck)
    head = pivot("Head", (0, 0.63, 1.62), neck)
    attach(jitter(blob("Skull", (0, 0.69, 1.67), (0.115, 0.15, 0.115), "deer_fur", 2), 0.008, 5), head)
    attach(limb("Snout", (0, 0.76, 1.65), (0, 0.93, 1.585), 0.075, 0.048, "deer_fur", 7), head)
    attach(blob("Muzzle", (0, 0.9, 1.57), (0.05, 0.05, 0.035), "deer_belly", 1), head)
    attach(blob("Nose", (0, 0.945, 1.595), (0.035, 0.028, 0.028), "deer_dark", 1), head)
    for side in (-1, 1):
        eye("Eye", (side * 0.085, 0.76, 1.7), 0.024, head)
        ear = attach(blob("Ear", (side * 0.17, 0.66, 1.74), (0.13, 0.035, 0.07), "deer_fur", 1), head)
        ear.rotation_euler = (0.1, side * 0.25, side * 0.15)
        inner = attach(blob("EarInner", (side * 0.17, 0.678, 1.74), (0.095, 0.014, 0.048), "deer_belly", 1), head)
        inner.rotation_euler = (0.1, side * 0.25, side * 0.15)
        # Antlers: a beam curving up and back, with two forward tines.
        base = Vector((side * 0.06, 0.64, 1.76))
        beam_top = Vector((side * 0.22, 0.56, 2.1))
        attach(limb("AntlerBeam", base, beam_top, 0.024, 0.013, "antler", 6), head)
        attach(limb("AntlerTine", base.lerp(beam_top, 0.4), (side * 0.18, 0.76, 1.99), 0.014, 0.008, "antler", 5), head)
        attach(limb("AntlerTine", base.lerp(beam_top, 0.72), (side * 0.29, 0.66, 2.12), 0.012, 0.007, "antler", 5), head)
    tail = pivot("Tail", (0, -0.62, 1.18), root)
    attach(blob("TailMesh", (0, -0.65, 1.15), (0.045, 0.035, 0.075), "rabbit_light", 1), tail)
    done(os.path.join(WILDLIFE, "sm_env_animal_deer.glb"))


# =============================================================================
# Rabbit: 0.3 m tall with ears up
# =============================================================================

def rabbit():
    clear()
    root = pivot("Rabbit", (0, 0, 0))
    attach(jitter(blob("Body", (0, -0.02, 0.13), (0.1, 0.15, 0.11), "rabbit_fur", 2), 0.008, 7), root)
    attach(blob("Chest", (0, 0.07, 0.11), (0.07, 0.06, 0.07), "rabbit_light", 1), root)
    attach(blob("Head", (0, 0.12, 0.2), (0.07, 0.08, 0.065), "rabbit_fur", 1), root)
    attach(blob("Muzzle", (0, 0.19, 0.19), (0.035, 0.025, 0.025), "rabbit_light", 1), root)
    attach(blob("Nose", (0, 0.214, 0.198), (0.012, 0.01, 0.01), "rabbit_ear", 1), root)
    for side in (-1, 1):
        eye("Eye", (side * 0.045, 0.16, 0.225), 0.014, root)
    ears = pivot("Ears", (0, 0.1, 0.25), root)
    for side in (-1, 1):
        ear = attach(blob("Ear", (side * 0.03, 0.08, 0.34), (0.025, 0.012, 0.08), "rabbit_fur", 1), ears)
        ear.rotation_euler = (-0.25, side * 0.2, 0)
        inner = attach(blob("EarInner", (side * 0.03, 0.089, 0.34), (0.015, 0.006, 0.06), "rabbit_ear", 1), ears)
        inner.rotation_euler = (-0.25, side * 0.2, 0)
    front = pivot("Legs_Front", (0, 0.08, 0.08), root)
    back = pivot("Legs_Back", (0, -0.07, 0.08), root)
    for side in (-1, 1):
        attach(limb("FrontLeg", (side * 0.04, 0.08, 0.09), (side * 0.04, 0.1, 0.01), 0.018, 0.014, "rabbit_fur", 5), front)
        attach(blob("BackThigh", (side * 0.07, -0.08, 0.07), (0.035, 0.07, 0.06), "rabbit_fur", 1), back)
        attach(blob("BackFoot", (side * 0.07, -0.02, 0.015), (0.025, 0.07, 0.015), "rabbit_light", 1), back)
    tail = pivot("Tail", (0, -0.16, 0.14), root)
    attach(blob("TailMesh", (0, -0.17, 0.14), (0.035, 0.035, 0.035), "rabbit_light", 1), tail)
    done(os.path.join(WILDLIFE, "sm_env_animal_rabbit.glb"))


# =============================================================================
# Frog: a squat 0.22 m frog, bigger than life so it reads from the cab
# =============================================================================

def frog():
    clear()
    root = pivot("Frog", (0, 0, 0))
    attach(jitter(blob("Body", (0, -0.01, 0.06), (0.09, 0.1, 0.055), "frog_green", 2), 0.006, 11), root)
    attach(blob("Belly", (0, 0.0, 0.035), (0.075, 0.085, 0.03), "frog_belly", 1), root)
    attach(blob("Head", (0, 0.07, 0.075), (0.075, 0.055, 0.04), "frog_green", 1), root)
    rng = random.Random(4)
    for k in range(5):
        attach(blob("Spot", (rng.uniform(-0.05, 0.05), rng.uniform(-0.07, 0.03), 0.108), (0.014, 0.014, 0.006), "frog_spot", 1), root)
    for side in (-1, 1):
        attach(blob("EyeBump", (side * 0.04, 0.075, 0.105), (0.024, 0.024, 0.022), "frog_green", 1), root)
        eye("Eye", (side * 0.045, 0.086, 0.113), 0.015, root)
    throat = pivot("Throat", (0, 0.08, 0.04), root)
    attach(blob("ThroatSac", (0, 0.09, 0.04), (0.04, 0.025, 0.02), "frog_belly", 1), throat)
    front = pivot("Legs_Front", (0, 0.05, 0.04), root)
    back = pivot("Legs_Back", (0, -0.06, 0.04), root)
    for side in (-1, 1):
        attach(limb("FrontLeg", (side * 0.05, 0.05, 0.04), (side * 0.07, 0.09, 0.005), 0.012, 0.01, "frog_green", 5), front)
        attach(blob("FrontFoot", (side * 0.075, 0.1, 0.005), (0.02, 0.018, 0.005), "frog_belly", 1), front)
        attach(blob("BackThigh", (side * 0.08, -0.05, 0.04), (0.03, 0.055, 0.028), "frog_green", 1), back)
        attach(blob("BackShin", (side * 0.095, -0.01, 0.02), (0.015, 0.05, 0.015), "frog_green", 1), back)
        attach(blob("BackFoot", (side * 0.1, 0.03, 0.006), (0.03, 0.03, 0.005), "frog_belly", 1), back)
    done(os.path.join(WILDLIFE, "sm_env_animal_frog.glb"))


# =============================================================================
# Bird: a robin-like songbird, 0.2 m, stands on the ground or a post
# =============================================================================

def bird():
    clear()
    root = pivot("Bird", (0, 0, 0))
    attach(jitter(blob("Body", (0, 0, 0.1), (0.05, 0.075, 0.05), "bird_back", 2), 0.004, 13), root)
    attach(blob("Breast", (0, 0.03, 0.09), (0.042, 0.045, 0.045), "bird_breast", 1), root)
    for side in (-1, 1):
        attach(limb("Leg", (side * 0.015, 0.0, 0.06), (side * 0.015, 0.01, 0.0), 0.004, 0.003, "beak", 4), root)
        attach(cube("Foot", (side * 0.015, 0.02, 0.002), (0.012, 0.03, 0.004), "beak"), root)
    head = pivot("Head", (0, 0.05, 0.13), root)
    attach(blob("HeadMesh", (0, 0.06, 0.15), (0.035, 0.035, 0.034), "bird_back", 1), head)
    attach(cone("Beak", (0, 0.105, 0.148), 0.012, 0.0, 0.035, "beak", 6, rot=(-math.pi / 2, 0, 0)), head)
    for side in (-1, 1):
        eye("Eye", (side * 0.025, 0.08, 0.16), 0.008, head, pupil=False)
    for name, side in (("Wing_L", -1), ("Wing_R", 1)):
        root_joint = pivot(name, (side * 0.04, 0.02, 0.12), root)
        wing = attach(blob(name + "Mesh", (side * 0.05, -0.02, 0.11), (0.012, 0.065, 0.035), "bird_back", 1), root_joint)
        wing.rotation_euler = (0.25, 0, 0)
    tail = pivot("Tail", (0, -0.07, 0.1), root)
    attach(cube("TailMesh", (0, -0.11, 0.1), (0.04, 0.07, 0.008), "bird_back", rot=(0.35, 0, 0)), tail)
    done(os.path.join(WILDLIFE, "sm_env_animal_bird.glb"))


# =============================================================================
# The warning sign: yellow diamond with a leaping deer, same build as the
# other warning signs (build_lowpoly_refined.py: sign_post / diamond / symbol)
# =============================================================================

VIEW_X = -1.0
FACE = 0.032


def crossing_sign():
    clear()
    cylinder("SignPost", (0, -0.06, 1.0), 0.045, 2.2, "metal", 8)
    cylinder("PostCap", (0, -0.06, 2.12), 0.055, 0.04, "metal", 8)
    cylinder("PostBase", (0, -0.06, 0.05), 0.12, 0.1, "concrete", 8)
    for dz in (-0.25, 0.25):
        cube("SignBracket", (0, -0.03, 2.0 + dz), (0.12, 0.06, 0.05), "metal")
    z, size = 2.0, 0.84
    half = size / math.sqrt(2)
    cube("SignBack", (0, -0.018, z), (size + 0.02, 0.02, size + 0.02), "metal", 0.01, rot=(0, math.pi / 4, 0))
    flat_poly("SignBorder", [(0, z + half + 0.05), (half + 0.05, z), (0, z - half - 0.05), (-half - 0.05, z)], -0.008, 0.02, "sign_ink")
    flat_poly("SignPanel", [(0, z + half - 0.02), (half - 0.02, z), (0, z - half + 0.02), (-half + 0.02, z)], 0.008, 0.024, "warning")
    # A leaping deer, drawn as the driver sees it (x right, z up).
    leaping_deer = [(-0.26, 1.96), (-0.2, 2.02), (0.06, 2.03), (0.12, 2.11), (0.11, 2.19), (0.15, 2.26), (0.17, 2.2),
                    (0.2, 2.25), (0.21, 2.18), (0.26, 2.14), (0.23, 2.1), (0.19, 2.1), (0.19, 1.98), (0.15, 1.93),
                    (0.25, 1.81), (0.21, 1.78), (0.1, 1.9), (-0.06, 1.9), (-0.19, 1.78), (-0.23, 1.8), (-0.14, 1.93),
                    (-0.27, 1.91)]
    flat_poly("Deer", [(x * VIEW_X, zz) for x, zz in reversed(leaping_deer)], FACE, 0.012, "sign_ink")
    # Antlers: what makes the silhouette a deer and not a dog.
    for name, antler in (("AntlerBack", [(0.13, 2.2), (0.07, 2.33), (0.02, 2.36), (0.03, 2.33), (0.07, 2.3), (0.05, 2.26), (0.08, 2.26), (0.11, 2.18)]),
                         ("AntlerFront", [(0.18, 2.21), (0.21, 2.34), (0.26, 2.38), (0.26, 2.35), (0.23, 2.31), (0.27, 2.29), (0.26, 2.27), (0.22, 2.28), (0.2, 2.2)])):
        flat_poly(name, [(x * VIEW_X, zz) for x, zz in reversed(antler)], FACE, 0.012, "sign_ink")
    done(os.path.join(SIGNS, "sm_env_sign_animal_crossing.glb"))


rabbit()
frog()
bird()
crossing_sign()

print("WILDLIFE_REPORT")
for path, tris in REPORT:
    print("  %-62s %6d tris" % (path, tris))
