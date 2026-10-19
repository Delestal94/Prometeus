"""Refined low-poly models for Take My Package (2026-09-23).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_lowpoly_refined.py [-- group ...]

Groups: houses, trees, plants, signs, props, yard (default: all); guardrail,
tall_fern, rock, rock_cluster and mushroom rebuild just that one model.

The source of truth for the houses and barn, the whole forest set, the
warning signs and the roadside furniture -- it overwrites the same GLB paths
the first two batches used, with the same palette material names, so the
game (and LowpolyMaterials' detail textures) pick the new shapes up with no
code change. What changed, per group:

  houses  closed gable roofs with eaves and a ridge cap (the old ones left the
          gable triangles open), stone plinth, corner boards, windows with
          frame, cross bars, sill and shutters, panelled doors, porch railings
          and roofs; the cabin is actually built from logs.
  trees   irregular, layered crowns instead of perfect balls, root flares,
          pines with drooping, ragged tiers, birches with bark marks.
  plants  bushes, rocks and ground cover as jittered clusters; ferns and
          grass from real fronds and blades.
  signs   symbols as clean extruded outlines (a proper arrow, a worker, a
          house), black borders, back plates, brackets and capped posts.
  props   guardrail with a real W-beam profile, and more shape for the bus
          stop, hydrant, milestone, hay bale, crate, pallet, cone, barrier,
          mailbox, street lamp and bench.
  yard    picket fence, flower pot, gnome and dog house.

Conventions unchanged: origin at the centre of the base, metres, fronts on
Blender +Y (Godot -Z). Porch decks stay 0.30 m tall and every house keeps
its old wall footprint, so colliders and doorbells still line up.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from lowpoly_kit import (PALETTE, ROOT, blob, circle_points, clear, cone, cube, cylinder, export,  # noqa: E402
                         flat_poly, gable_roof, jitter, mat, move_new, slab, squash_bottom,
                         triangle_count)

M = os.path.join(ROOT, "models")
ARCH = os.path.join(M, "architecture")
FOREST = os.path.join(M, "environment", "forest")
PROPS = os.path.join(M, "environment", "props")
SIGNS = os.path.join(M, "environment", "signs")
YARD = os.path.join(M, "environment", "yard")
REPORT = []
PORCH_TOP = 0.30


def done(path):
    REPORT.append((os.path.relpath(path, ROOT), triangle_count()))
    export(path)


# =============================================================================
# Houses
# =============================================================================

def along_wall(facing, sign, cx, cy, u, n, z, su, sn, sz, name, material, bevel=0.0):
    """Places a box on a wall: `facing` "y" is the front/back wall (normal
    along Y), "x" a side wall. u runs along the wall, n out of it."""
    if facing == "y":
        return cube(name, (cx + u, cy + sign * n, z), (su, sn, sz), material, bevel)
    return cube(name, (cx + sign * n, cy + u, z), (sn, su, sz), material, bevel)


def window(facing, sign, cx, cy, z, w=0.9, h=0.9, shutters=None):
    t = 0.07
    along_wall(facing, sign, cx, cy, 0, 0.0, z, w - 0.06, 0.05, h - 0.06, "WindowGlass", "window")
    for dz in (-h / 2, h / 2):
        along_wall(facing, sign, cx, cy, 0, 0.04, z + dz, w + t, 0.09, t, "WindowFrame", "trim")
    for du in (-w / 2, w / 2):
        along_wall(facing, sign, cx, cy, du, 0.04, z, t, 0.09, h + t, "WindowFrame", "trim")
    along_wall(facing, sign, cx, cy, 0, 0.04, z, 0.04, 0.06, h, "WindowBar", "trim")
    along_wall(facing, sign, cx, cy, 0, 0.04, z, w, 0.06, 0.04, "WindowBar", "trim")
    along_wall(facing, sign, cx, cy, 0, 0.1, z - h / 2 - 0.06, w + 0.24, 0.18, 0.07, "WindowSill", "trim", 0.01)
    if shutters:
        for du in (-(w / 2 + 0.24), w / 2 + 0.24):
            along_wall(facing, sign, cx, cy, du, 0.05, z, 0.34, 0.05, h + 0.04, "Shutter", shutters, 0.01)


def door(cy, x=0.0):
    cube("FrontDoor", (x, cy + 0.03, 0.36 + 1.02), (1.04, 0.07, 2.04), "wood", 0.01)
    for dz in (0.75, 1.5):
        cube("DoorPanel", (x, cy + 0.07, 0.36 + dz), (0.7, 0.03, 0.5), "wood", 0.01)
    cube("DoorFrameTop", (x, cy + 0.05, 0.36 + 2.1), (1.3, 0.1, 0.12), "trim")
    for dx in (-0.59, 0.59):
        cube("DoorFrameSide", (x + dx, cy + 0.05, 0.36 + 1.02), (0.1, 0.1, 2.1), "trim")
    cube("DoorKnob", (x + 0.36, cy + 0.1, 0.36 + 1.0), (0.06, 0.05, 0.06), "metal")
    cube("PorchLight", (x - 0.85, cy + 0.08, 0.36 + 1.95), (0.14, 0.12, 0.2), "lamp", 0.01)


def porch(front_y, width, depth=1.35, roof=True, roof_z=2.55, roof_material="roof"):
    cube("Porch", (0, front_y + depth / 2 - 0.02, PORCH_TOP / 2), (width, depth, PORCH_TOP), "wood", 0.02)
    for x in range(int(width / 0.3)):
        px = -width / 2 + 0.15 + x * 0.3
        cube("PorchBoard", (px, front_y + depth / 2 - 0.02, PORCH_TOP + 0.005), (0.02, depth - 0.04, 0.01), "trim")
    post_y = front_y + depth - 0.14
    for side in (-1.0, 1.0):
        cube("PorchPost", (side * (width / 2 - 0.1), post_y, PORCH_TOP + 1.1), (0.14, 0.14, 2.2), "trim")
        # Railings on the sides only: the front stays open to the steps.
        cube("PorchRail", (side * (width / 2 - 0.1), front_y + depth / 2, PORCH_TOP + 0.85), (0.08, depth - 0.2, 0.08), "trim")
        for k in range(3):
            cube("PorchBaluster", (side * (width / 2 - 0.1), front_y + 0.3 + k * (depth - 0.5) / 2, PORCH_TOP + 0.42), (0.05, 0.05, 0.8), "trim")
    # One step down, in front of the deck (not buried inside it).
    cube("PorchStep", (0, front_y + depth + 0.1, PORCH_TOP * 0.25), (1.3, 0.26, PORCH_TOP * 0.5), "stone", 0.01)
    if roof:
        cube("PorchRoof", (0, front_y + depth / 2, roof_z + 0.08), (width + 0.3, depth + 0.3, 0.12), roof_material, 0.02, rot=(0.12, 0, 0))


def chimney(x, y, top):
    cube("Chimney", (x, y, top - 0.9), (0.6, 0.6, 1.8), "chimney", 0.02)
    cube("ChimneyCap", (x, y, top + 0.04), (0.74, 0.74, 0.12), "stone", 0.02)


def plinth_and_walls(width, depth, height, wall):
    cube("Foundation", (0, 0, 0.18), (width + 0.2, depth + 0.2, 0.36), "stone", 0.03)
    cube("HouseWalls", (0, 0, 0.36 + (height - 0.36) / 2), (width, depth, height - 0.36), wall, 0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cube("CornerBoard", (sx * width / 2, sy * depth / 2, height / 2 + 0.18), (0.16, 0.16, height - 0.36), "trim")


def log_walls(width, depth, height):
    cube("Foundation", (0, 0, 0.18), (width + 0.3, depth + 0.3, 0.36), "stone", 0.03)
    cube("LogCore", (0, 0, 0.36 + (height - 0.36) / 2), (width - 0.1, depth - 0.1, height - 0.36), "wall")
    radius = 0.15
    z = 0.36 + radius
    course = 0
    while z < height - 0.05:
        shift = 0.12 if course % 2 == 0 else 0.0
        for sy in (-1, 1):
            cylinder("Log", (0, sy * depth / 2, z + shift * 0.2), radius, width + 0.5, "wall", 8, rot=(0, math.pi / 2, 0))
        for sx in (-1, 1):
            cylinder("Log", (sx * width / 2, 0, z + radius * 0.5), radius, depth + 0.5, "wall", 8, rot=(math.pi / 2, 0, 0))
        z += radius * 1.9
        course += 1
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylinder("LogEnd", (sx * (width / 2 + 0.26), sy * depth / 2, height / 2), 0.16, 0.04, "trim", 8, rot=(0, math.pi / 2, 0))


HOUSES = {
    # wall footprint (unchanged), wall height, pitch, materials, window rows
    "cottage": dict(width=5.5, depth=4.5, height=3.1, pitch=0.62, wall="plaster", roof="roof", shutters="shutter"),
    "cabin": dict(width=5.0, depth=4.1, height=3.1, pitch=0.55, wall="wall", roof="roof_blue", shutters=None),
    "bungalow": dict(width=6.2, depth=4.8, height=3.0, pitch=0.42, wall="plaster", roof="roof_blue", shutters="shutter_red"),
    "two_story": dict(width=6.0, depth=5.0, height=5.6, pitch=0.6, wall="plaster", roof="roof", shutters="shutter"),
    "farmhouse": dict(width=7.0, depth=4.6, height=3.2, pitch=0.55, wall="wall", roof="roof_blue", shutters="shutter"),
}


def house(variant):
    clear()
    c = HOUSES[variant]
    w, d, h = c["width"], c["depth"], c["height"]
    front = d / 2 + 0.02
    if variant == "cabin":
        log_walls(w, d, h)
        front = d / 2 + 0.16
    else:
        plinth_and_walls(w, d, h, c["wall"])
    gable_roof("Roof", h, w, d, c["pitch"], c["roof"], c["wall"] if variant != "cabin" else "wood")
    ridge = h + (w / 2) * math.tan(c["pitch"])
    chimney(w * 0.26, -d * 0.2, ridge + 0.4)
    door(front)
    rows = [1.95] if h < 4 else [1.75, 4.2]
    for z in rows:
        for x in (-w * 0.3, w * 0.3):
            window("y", 1, x, front, z, shutters=c["shutters"])
        window("y", -1, 0, -front, z, shutters=c["shutters"])
        for sx in (-1, 1):
            window("x", sx, sx * (w / 2 + (0.14 if variant == "cabin" else 0.0)), 0, z, 0.8, 0.8, c["shutters"])
    if h > 4:
        for sy in (-1, 1):
            cube("FloorBand", (0, sy * (d / 2 + 0.02), 2.95), (w + 0.04, 0.08, 0.14), "trim")
        for sx in (-1, 1):
            cube("FloorBand", (sx * (w / 2 + 0.02), 0, 2.95), (0.08, d + 0.04, 0.14), "trim")
        # First floor window over the porch, on the upper row centre.
        window("y", 1, 0, front, 4.2, shutters=c["shutters"])
    if variant == "farmhouse":
        porch(d / 2, w + 0.4, depth=1.8, roof=True, roof_z=2.6, roof_material=c["roof"])
        before = {o.name for o in bpy.context.scene.objects}
        plinth_and_walls(2.6, 3.4, 2.8, c["wall"])
        gable_roof("WingRoof", 2.8, 2.6, 3.4, 0.6, c["roof"], c["wall"])
        window("x", 1, 1.3, 0, 1.8, 0.7, 0.7, c["shutters"])
        move_new(before, dx=2.24, dy=-3.22)
    elif variant == "bungalow":
        porch(d / 2, 2.8, roof=True, roof_material=c["roof"])
        before = {o.name for o in bpy.context.scene.objects}
        plinth_and_walls(1.45, 1.55, 2.7, c["wall"])
        cone("BayRoof", (0, 0, 3.05), 1.25, 0.1, 0.7, c["roof"], 4, rot=(0, 0, math.pi / 4))
        window("x", -1, -0.73, 0, 1.8, 0.7, 0.8, None)
        move_new(before, dx=-w * 0.42 - 0.6, dy=d * 0.12)
    else:
        porch(d / 2 + (0.14 if variant == "cabin" else 0.0), 2.8, roof=variant != "cabin", roof_material=c["roof"])
    if variant == "cottage":
        for x in (-w * 0.3, w * 0.3):
            cube("FlowerBox", (x, front + 0.2, 1.38), (0.95, 0.22, 0.2), "wood", 0.01)
            for k in range(4):
                blob("FlowerBoxBloom", (x - 0.33 + k * 0.22, front + 0.2, 1.55), (0.09, 0.09, 0.08), "flower")
    done(os.path.join(ARCH, "sm_arch_delivery_house_%s.glb" % variant))


def barn():
    clear()
    w, d, h = 8.0, 12.0, 5.0
    cube("Foundation", (0, 0, 0.2), (w + 0.25, d + 0.25, 0.4), "stone", 0.03)
    cube("BarnWalls", (0, 0, 0.4 + (h - 0.4) / 2), (w, d, h - 0.4), "barn_red", 0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cube("CornerBoard", (sx * w / 2, sy * d / 2, h / 2 + 0.2), (0.2, 0.2, h - 0.4), "sign_white")
    # Gambrel: steep lower pitch, shallow upper one, closed pentagon ends.
    knee = (w * 0.31, h + 1.9)
    peak = (0.0, h + 2.8)
    eave = (w / 2 + 0.35, h - 0.25)
    for side in (-1.0, 1.0):
        # Drawn outward-to-ridge, so the right side's normal points down
        # unless flipped.
        slab("BarnRoofLower", (side * eave[0], eave[1]), (side * knee[0], knee[1]), d + 0.7, 0.18, "roof", outward=-side)
        slab("BarnRoofUpper", (side * knee[0], knee[1]), (0.0, peak[1]), d + 0.7, 0.18, "roof", outward=-side)
    pentagon = [(-w / 2, h), (w / 2, h), (knee[0], knee[1]), (0.0, peak[1]), (-knee[0], knee[1])]
    flat_poly("BarnGableFront", pentagon, d / 2 - 0.02, 0.06, "barn_red")
    flat_poly("BarnGableBack", pentagon, -d / 2 - 0.04, 0.06, "barn_red")
    cube("RidgeCap", (0, 0, peak[1] + 0.2), (0.3, d + 0.8, 0.16), "roof", 0.02)
    for sy, y in ((1, d / 2), (-1, -d / 2)):
        cube("BarnDoor", (0, y + sy * 0.05, 1.9), (3.4, 0.08, 3.0), "barn_red", 0.02)
        for rot in (0.72, -0.72):
            cube("DoorBrace", (0, y + sy * 0.1, 1.9), (4.3, 0.05, 0.16), "sign_white", rot=(0, rot, 0))
        for dx in (-1.72, 1.72):
            cube("DoorFrame", (dx, y + sy * 0.1, 1.9), (0.16, 0.06, 3.1), "sign_white")
        cube("DoorFrame", (0, y + sy * 0.1, 3.42), (3.6, 0.06, 0.16), "sign_white")
        cube("DoorRail", (0, y + sy * 0.12, 3.62), (7.0, 0.06, 0.1), "metal")
        cube("HayLoft", (0, y + sy * 0.05, 5.4), (1.5, 0.08, 1.2), "wood", 0.02)
        for dz in (-0.62, 0.62):
            cube("LoftFrame", (0, y + sy * 0.1, 5.4 + dz), (1.7, 0.06, 0.12), "sign_white")
    for sx in (-1, 1):
        for y in (-3.5, 0.0, 3.5):
            window("x", sx, sx * w / 2, y, 2.4, 0.9, 0.7, None)
    cube("Cupola", (0, 0, peak[1] + 0.7), (1.0, 1.0, 0.9), "sign_white", 0.02)
    cone("CupolaRoof", (0, 0, peak[1] + 1.4), 0.85, 0.05, 0.6, "roof", 4, rot=(0, 0, math.pi / 4))
    done(os.path.join(ARCH, "sm_arch_barn.glb"))


# =============================================================================
# Trees
# =============================================================================

def rod(name, start, end, r0, r1, material, verts=6):
    """A tapered cone from `start` (radius r0) to `end` (radius r1): branches,
    roots, twigs and canes that actually touch what they grow from."""
    a, b = Vector(start), Vector(end)
    axis = b - a
    o = cone(name, tuple((a + b) / 2), r0, r1, axis.length, material, verts)
    o.rotation_euler = axis.to_track_quat("Z", "Y").to_euler()
    return o


def outward(angle, lift):
    """A unit direction around the trunk (`angle`) rising by `lift` (0-1)."""
    flat = math.sqrt(max(0.0, 1.0 - lift * lift))
    return Vector((math.cos(angle) * flat, math.sin(angle) * flat, lift))


def crown(name, loc, size, material, seed, rough=0.14, flat=0.55):
    o = blob(name, loc, size, material)
    jitter(o, rough * max(size), seed)
    squash_bottom(o, -size[2] * flat)
    return o


def trunk(height, base, top, material="trunk", verts=7, seed=0, lean=0.0):
    t = cone("Trunk", (0, 0, height / 2), base, top, height, material, verts, rot=(lean, 0, 0))
    jitter(t, base * 0.08, seed, keep_bottom=-height / 2)
    # Each flare starts near the trunk's axis, high enough that its thick end
    # cap stays buried inside the trunk, and ends a little under the ground:
    # from outside it reads as one piece growing out of the bark and into the
    # soil, never as a fin stuck onto the side.
    for k in range(4):
        a = k * math.tau / 4 + 0.4
        root_top = Vector((math.cos(a) * base * 0.15, math.sin(a) * base * 0.15, base * 1.6))
        root_tip = Vector((math.cos(a) * base * 1.75, math.sin(a) * base * 1.75, -0.04))
        rod("RootFlare", tuple(root_top), tuple(root_tip), base * 0.42, 0.025, material, 5)
    return t


def branch(z, angle, length, radius, material="trunk", tilt=0.9, trunk_radius=0.2):
    """A branch starting on the trunk surface at height z, heading out at
    `angle` and rising (tilt 0 = straight up, ~1.2 = nearly flat)."""
    start = Vector((math.cos(angle) * trunk_radius * 0.6, math.sin(angle) * trunk_radius * 0.6, z))
    end = start + outward(angle, math.cos(tilt)) * length
    rod("Branch", tuple(start), tuple(end), radius, radius * 0.3, material, 5)
    return start, end


def tree_oak():
    clear()
    trunk(4.6, 0.42, 0.24, seed=1)
    branch(3.6, 0.5, 1.8, 0.14)
    branch(3.9, 2.8, 1.6, 0.12)
    rng = random.Random(11)
    for i, (x, y, z, s, m) in enumerate([(-1.1, 0.1, 4.6, 1.7, "leaf_dark"), (1.1, -0.2, 4.7, 1.6, "leaf_dark"),
                                         (0.0, 0.9, 5.0, 1.5, "leaf"), (0.2, -0.9, 5.2, 1.5, "leaf"),
                                         (-0.3, 0.1, 6.1, 1.5, "leaf_light"), (0.9, 0.5, 5.9, 1.1, "leaf_light")]):
        crown("OakCrown", (x, y, z), (s * rng.uniform(0.95, 1.15), s * rng.uniform(0.9, 1.1), s * 0.82), m, 100 + i)


def bark_bands(obj, height, seed):
    """Birch lenticels painted onto the trunk's own faces: the mesh is sliced
    into thin rings and a short arc of each ring switches to the dark
    material. Flush with the bark, so nothing sticks out like a button (the
    old version glued black cubes in a column on one side).
    The rings don't change the silhouette, so Godot's LOD step erases them:
    the birch's .import keeps meshes/generate_lods=false for that reason."""
    obj.data.materials.append(mat("rubber"))
    rng = random.Random(seed)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bands = []
    z = 0.55
    while z < height - 0.9:
        thick = rng.uniform(0.07, 0.13)
        # Golden-angle steps spread the arcs evenly around the trunk.
        bands.append((z, z + thick, len(bands) * 2.4 + rng.uniform(-0.3, 0.3), rng.uniform(1.4, 2.4)))
        z += rng.uniform(0.45, 0.8)
    # The cone is centred on its origin: local z = world z - height / 2.
    for z0, z1, _, _ in bands:
        for cut in (z0, z1):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, cut - height / 2), plane_no=(0, 0, 1))
    bm.normal_update()
    for f in bm.faces:
        if abs(f.normal.z) > 0.7:
            continue
        c = f.calc_center_median()
        cz = c.z + height / 2
        a = math.atan2(c.y, c.x)
        for z0, z1, start, arc in bands:
            if z0 < cz < z1 and (a - start) % math.tau < arc:
                f.material_index = 1
    bm.to_mesh(obj.data)
    bm.free()


def tree_birch():
    clear()
    t = trunk(6.8, 0.2, 0.1, "birch", 6, seed=2, lean=0.05)
    bark_bands(t, 6.8, 22)
    rng = random.Random(22)
    for i, (x, z, s) in enumerate([(-0.45, 3.9, 0.95), (0.4, 4.8, 1.05), (-0.25, 5.8, 1.0), (0.2, 6.7, 0.8), (0.55, 5.6, 0.7)]):
        crown("BirchLeaves", (x, rng.uniform(-0.2, 0.2), z), (s * 0.9, s * 0.8, s * 1.25), "leaf" if i % 2 else "leaf_light", 200 + i, 0.18)


def pine_tiers(base_z, tiers, radius, height, seed, sapling=False):
    rng = random.Random(seed)
    z = base_z
    for i in range(tiers):
        r = radius * (1.0 - i / (tiers + 0.6))
        tier_h = height * (1.0 - i * 0.08)
        material = "leaf_dark" if i < tiers // 2 else ("leaf" if i < tiers - 1 else "leaf_light")
        tier = cone("PineTier", (0, 0, z + tier_h / 2), r, 0.04, tier_h, material, 9, rot=(0, 0, rng.uniform(0, math.tau)))
        # Droop and fray the lower ring only; the tip stays clean.
        for v in tier.data.vertices:
            if v.co.z < 0:
                v.co.z -= rng.uniform(0.0, 0.28) * tier_h
                v.co.x *= rng.uniform(0.88, 1.12)
                v.co.y *= rng.uniform(0.88, 1.12)
        tier.data.update()
        z += tier_h * (0.52 if not sapling else 0.5)


def tree_pine():
    clear()
    trunk(6.2, 0.28, 0.12, seed=3)
    pine_tiers(2.0, 5, 1.8, 2.1, 33)


def tree_maple():
    clear()
    trunk(5.0, 0.36, 0.2, seed=4)
    branch(3.8, 1.2, 1.6, 0.12)
    branch(3.6, 4.0, 1.5, 0.12)
    rng = random.Random(44)
    for i in range(7):
        a = i * math.tau / 7
        crown("MapleCrown", (math.cos(a) * 1.0, math.sin(a) * 0.8, 5.0 + (i % 3) * 0.45), (1.25, 1.1, 1.0),
              "leaf_light" if i % 3 else "leaf", 400 + i, 0.16)
    crown("MapleCrown", (0, 0, 6.2), (1.4, 1.2, 1.0), "leaf_light", 499)


def tree_dead():
    clear()
    trunk(5.6, 0.34, 0.1, seed=5)
    for angle, z, length in [(0.4, 3.2, 2.2), (2.5, 3.8, 1.9), (4.3, 4.5, 1.6), (1.6, 2.4, 1.4)]:
        start, end = branch(z, angle, length, 0.11, tilt=0.85, trunk_radius=0.22)
        # Twigs fork off two thirds along, each from a point on the branch.
        fork = start + (end - start) * 0.65
        for turn in (-0.7, 0.6):
            rod("Twig", tuple(fork), tuple(fork + outward(angle + turn, 0.6) * 0.7), 0.04, 0.008, "trunk", 4)
    # A broken top instead of a neat point.
    rod("SnappedTop", (0, 0, 5.4), (0.25, 0.1, 6.1), 0.08, 0.03, "trunk", 5)


def tree_sapling():
    clear()
    trunk(2.8, 0.1, 0.05, seed=6)
    pine_tiers(0.9, 4, 0.8, 0.9, 66, sapling=True)


# =============================================================================
# Ground cover
# =============================================================================

def bush():
    clear()
    rng = random.Random(7)
    for i, (x, y, s) in enumerate([(0, 0, 0.8), (0.6, 0.15, 0.62), (-0.6, -0.05, 0.6), (0.1, 0.5, 0.55), (-0.2, -0.45, 0.5)]):
        crown("Bush", (x, y, s * 0.55), (s, s * 0.9, s * 0.75), "leaf" if i % 2 else "leaf_dark", 700 + i, 0.18, 0.7)


def frond(name, length, width, angle, tilt, material, z=0.02):
    pts = [(0.0, -width * 0.2)]
    steps = 5
    for k in range(1, steps + 1):
        t = k / steps
        pts.append((length * t, -width * math.sin(math.pi * t) * (0.6 + 0.4 * (k % 2))))
    for k in range(steps - 1, 0, -1):
        t = k / steps
        pts.append((length * t, width * math.sin(math.pi * t) * (0.6 + 0.4 * (k % 2))))
    pts.append((0.0, width * 0.2))
    o = flat_poly(name, pts, 0.0, 0.012, material, plane="xy")
    o.location.z = z
    o.rotation_euler = (0, -tilt, angle)
    return o


def fern(scale=1.0, count=9, seed=8):
    clear()
    rng = random.Random(seed)
    for i in range(count):
        frond("FernFrond", 0.75 * scale * rng.uniform(0.85, 1.15), 0.16 * scale, i * math.tau / count + rng.uniform(-0.2, 0.2),
              rng.uniform(0.35, 0.8), "fern" if i % 2 else "leaf")


def blades(count, height, spread, seed, material="grass"):
    rng = random.Random(seed)
    for i in range(count):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0, spread)
        h = height * rng.uniform(0.6, 1.1)
        w = 0.035
        o = flat_poly("GrassBlade", [(-w, 0.0), (w, 0.0), (w * 0.4, h * 0.6), (rng.uniform(-0.08, 0.08), h)], 0.0, 0.008, material)
        o.location = (math.cos(a) * r, math.sin(a) * r, 0)
        o.rotation_euler = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, math.tau))


def grass():
    clear()
    blades(16, 0.55, 0.22, 9)


def tall_grass():
    clear()
    blades(24, 1.0, 0.35, 10)
    blades(6, 0.9, 0.3, 11, "straw")


def flowers():
    clear()
    rng = random.Random(12)
    for s in range(3):
        a = s * 2.1
        ox, oy = math.cos(a) * 0.12, math.sin(a) * 0.12
        h = rng.uniform(0.45, 0.7)
        cylinder("FlowerStem", (ox, oy, h / 2), 0.012, h, "grass", 5)
        for p in range(6):
            pa = p * math.tau / 6
            blob("Petal", (ox + math.cos(pa) * 0.06, oy + math.sin(pa) * 0.06, h), (0.05, 0.03, 0.015), "flower")
        blob("FlowerCenter", (ox, oy, h + 0.01), (0.03, 0.03, 0.02), "trim")
        frond("FlowerLeaf", 0.18, 0.05, a + 1.2, 0.6, "grass", z=h * 0.3)


# Mushroom cluster (N-331.3): 21 meshes and 444 tris, 300 of them in 15
# icosphere spots nobody sees from 7 m, the caps icospheres too and the spots
# in the signs' "sign_white". Now one MushroomCluster mesh of 142 tris: the
# same three mushrooms (sizes and spacing as before, 0.52 m tall), each a
# 6-sided uncapped stem (12 tris) under an 8-segment, two-ring cap with a
# drooping rim (16 tris of band, 8 of dome) closed underneath by a pale
# gill fan (8 tris), and flat 4-sided spots (3 on the big cap, 2 on the
# middle one) lying 4 mm off the cap's band facets, so they never z-fight.
# "mushroom" and "plaster" (stem, gills, spots) single-sided; the footprint
# is centred on the origin (the old one sat 5 cm off in X) and the stems go
# 1.5 cm into the ground.
# (x, y, scale, spot facets on the cap band, spin of the cap)
MUSHROOMS = [(0.0, 0.0, 1.0, (0, 3, 5), 0.0), (0.18, 0.1, 0.6, (1, 5), 0.3), (-0.12, 0.14, 0.45, (), 0.15)]
# (radius, height) of the cap's rim and shoulder rings, and the apex and gill
# centre heights, all x scale.
CAP_RIM, CAP_SHOULDER, CAP_APEX, CAP_GILLS = (0.26, 0.335), (0.215, 0.455), 0.52, 0.372


def _mushroom_face(bm, verts, slot, outward):
    f = bm.faces.new(verts)
    f.normal_update()
    if f.normal.dot(outward) < 0.0:
        f.normal_flip()
    f.material_index = slot
    return f


def mushroom():
    clear()
    mesh = bpy.data.meshes.new("MushroomCluster")
    obj = bpy.data.objects.new("MushroomCluster", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(_single_sided("mushroom"))
    mesh.materials.append(_single_sided("plaster"))
    bm = bmesh.new()
    for x, y, s, spots, spin in MUSHROOMS:
        c = Vector((x, y, 0.0))
        up = Vector((0, 0, 1))
        # Stem: 6 sides, no caps, its top hidden inside the cap.
        ring = lambda r, z, n, a0=0.0: [bm.verts.new(c + Vector((math.cos(a0 + i * math.tau / n) * r,
                                                                 math.sin(a0 + i * math.tau / n) * r, z)))
                                        for i in range(n)]
        low, high = ring(0.07 * s, -0.015, 6), ring(0.05 * s, (CAP_GILLS + 0.006) * s, 6)
        for i in range(6):
            j = (i + 1) % 6
            mid = (low[i].co + low[j].co + high[i].co + high[j].co) / 4
            _mushroom_face(bm, (low[i], low[j], high[j], high[i]), 1, mid - Vector((c.x, c.y, mid.z)))
        # Cap: rim and shoulder rings, apex, gill fan underneath.
        rim = ring(CAP_RIM[0] * s, CAP_RIM[1] * s, 8, spin)
        shoulder = ring(CAP_SHOULDER[0] * s, CAP_SHOULDER[1] * s, 8, spin)
        apex = bm.verts.new(c + Vector((0, 0, CAP_APEX * s)))
        gills = bm.verts.new(c + Vector((0, 0, CAP_GILLS * s)))
        band = []
        for i in range(8):
            j = (i + 1) % 8
            mid = (rim[i].co + rim[j].co + shoulder[i].co + shoulder[j].co) / 4
            band.append(_mushroom_face(bm, (rim[i], rim[j], shoulder[j], shoulder[i]), 0,
                                       mid - Vector((c.x, c.y, CAP_GILLS * s))))
            _mushroom_face(bm, (shoulder[i], shoulder[j], apex), 0, up)
            _mushroom_face(bm, (rim[i], gills, rim[j]), 1, -up)
        # Spots: flat squares on band facets, 4 mm out, turned a little.
        for k, facet in enumerate(spots):
            f = band[facet]
            n = f.normal.copy()
            centre = f.calc_center_median() + n * 0.004
            t = (f.verts[1].co - f.verts[0].co).normalized()
            b = n.cross(t)
            turn = 0.35 + 0.5 * k
            t, b = t * math.cos(turn) + b * math.sin(turn), b * math.cos(turn) - t * math.sin(turn)
            h = 0.042 * s
            corners = [bm.verts.new(centre + (t * dx + b * dy) * h) for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            _mushroom_face(bm, corners, 1, n)
    # Centre the footprint on the origin.
    for i in range(2):
        mid = (min(v.co[i] for v in bm.verts) + max(v.co[i] for v in bm.verts)) / 2
        for v in bm.verts:
            v.co[i] -= mid
    bm.to_mesh(mesh)
    bm.free()


def log():
    clear()
    o = cylinder("FallenLog", (0, 0, 0.3), 0.3, 2.8, "trunk", 10, rot=(0, math.pi / 2, 0))
    jitter(o, 0.03, 14)
    for x in (-1.41, 1.41):
        cylinder("LogEnd", (x, 0, 0.3), 0.27, 0.03, "trim", 10, rot=(0, math.pi / 2, 0))
    cone("LogStub", (-0.5, 0.2, 0.55), 0.08, 0.03, 0.5, "trunk", 5, rot=(0.7, 0, 0))
    cone("LogStub", (0.7, -0.15, 0.5), 0.07, 0.03, 0.4, "trunk", 5, rot=(-0.8, 0.3, 0))
    for i, x in enumerate((-0.9, 0.2, 1.0)):
        crown("Moss", (x, 0.05, 0.56), (0.35, 0.25, 0.08), "moss", 1400 + i, 0.2)


def rock(seed=15, size=(0.8, 0.6, 0.5), material="stone", name="ForestRock", at=(0, 0)):
    o = blob(name, (at[0], at[1], size[2] * 0.55), size, material, subdivisions=2)
    jitter(o, 0.1 * max(size), seed)
    squash_bottom(o, -size[2] * 0.55)
    return o


# Forest rock (N-331): the dented-ball rock() read as a blue-grey lump with no
# silhouette at 8-15 m, so the standalone rock is cut instead -- a convex hull
# sliced by a tilted top, a side cut and a back chip (big flat facets), ridges
# chamfered, a moss patch on the top facet and the base 5 cm underground.
# rock() itself stays as it was (mossy_rock_cluster used it until N-331.9).
# Warm stone: halfway between the palette's "stone" and "chimney", so it
# stops reading cold next to the moss. Named "stone.forest" so
# LowpolyMaterials keys it as "stone" (it cuts the name at the first dot)
# and keeps this albedo under the detail map.
# N-331.7: 0.33/0.30/0.25 read almost white by day and blue under the
# moonlight -- the game multiplies the (sRGB) albedo by DETAIL_GAIN 1.16. Now
# the colour the falls' wet rocks had (old albedo x WET_TINT 0.74 in sRGB,
# route_river_falls.gd), so a dry rock in the forest reads like those.
STONE_FOREST = (0.17, 0.16, 0.14, 1)


def stone_forest(name="stone.forest"):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        principled = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        principled.inputs["Base Color"].default_value = STONE_FOREST
        principled.inputs["Roughness"].default_value = 0.88
        m.diffuse_color = STONE_FOREST
        m.roughness = 0.88
        # A closed solid: back faces culled, so glTF doubleSided stays off
        # (a new Blender material defaults to no culling, i.e. doubleSided).
        m.use_backface_culling = True
    return m


def _single_sided(name):
    """A copy of palette material `name` that culls back faces (glTF
    doubleSided off), for closed solids. "moss.singlesided" still keys as
    "moss" in LowpolyMaterials. The shared mat(name) is left as it was, so
    the other models of a run export the same as before."""
    m = bpy.data.materials.get(name + ".singlesided")
    if m is None:
        m = mat(name).copy()
        m.name = name + ".singlesided"
        m.use_backface_culling = True
    return m


def _rock_cut(bm, co, no):
    """Slices the convex rock with a plane and caps the cut: one big flat facet."""
    res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co,
                                 plane_no=Vector(no).normalized(), clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.edgeloop_fill(bm, edges=edges)


FACETED_RINGS = [(0.0, 1.0, 7), (0.45, 0.95, 7), (0.85, 0.6, 5)]


def faceted_rock(name="ForestRock", size=(0.8, 0.6, 0.5), sink=0.05, seed=331, rings=FACETED_RINGS,
                 bevel=0.025, moss=0.62, stone=None):
    """`rings` (height, radius, points) shape the hull, `bevel` chamfers the
    ridges (0: none, the cheap version), `moss` is how much of the top facet
    the moss patch covers and `stone` the stone material (stone.forest by
    default). The defaults are the standalone forest rock."""
    rng = random.Random(seed)
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2]
    pts = []
    for ring, (zf, rf, n) in enumerate(rings):
        for i in range(n):
            a = (i + rng.uniform(-0.25, 0.25) + ring * 0.5) * math.tau / n
            r = rf * rng.uniform(0.85, 1.05)
            pts.append(Vector((math.cos(a) * sx * r, math.sin(a) * sy * r, zf * sz + rng.uniform(-0.04, 0.04) - sink)))
    pts.append(Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), sz * 1.05 - sink)))
    bm = bmesh.new()
    bmesh.ops.convex_hull(bm, input=[bm.verts.new(p) for p in pts])
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    _rock_cut(bm, (0.05, 0.0, sz * 0.74 - sink), (0.42, -0.3, 1.0))   # tilted top
    _rock_cut(bm, (sx * 0.72, 0.0, 0.0), (1.0, 0.35, 0.25))           # side cut
    _rock_cut(bm, (-sx * 0.2, sy * 0.78, 0.0), (-0.3, 1.0, 0.45))     # back chip
    _rock_cut(bm, (0, 0, -sink), (0, 0, -1))                          # buried base
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(18), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ridges = [e for e in bm.edges if not all(v.co.z < -sink + 1e-3 for v in e.verts)
              and e.calc_face_angle(0) > math.radians(25)]
    if bevel:
        bmesh.ops.bevel(bm, geom=ridges, offset=bevel, segments=1, affect="EDGES", profile=0.5, clamp_overlap=True)
    # Moss: the top facet split off, shrunk toward its centre, raised 1.5 cm.
    bm.normal_update()
    top = max((f for f in bm.faces if f.normal.z > 0.7), key=lambda f: f.calc_area())
    bmesh.ops.inset_region(bm, faces=[top], thickness=0.0, depth=0.0)
    centre, lift = top.calc_center_median(), top.normal * 0.015
    for v in top.verts:
        v.co = centre + (v.co - centre) * (moss + rng.uniform(-0.08, 0.08)) + lift
    top.material_index = 1
    # Fit the bounding box to `size`, the base `sink` below the origin.
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    for v in bm.verts:
        v.co.x = (v.co.x - (lo[0] + hi[0]) / 2) * size[0] / (hi[0] - lo[0])
        v.co.y = (v.co.y - (lo[1] + hi[1]) / 2) * size[1] / (hi[1] - lo[1])
        v.co.z = (v.co.z - lo[2]) * size[2] / (hi[2] - lo[2]) - sink
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(stone or stone_forest())
    obj.data.materials.append(_single_sided("moss"))
    return obj


def forest_rock():
    clear()
    faceted_rock()


# Mossy rock cluster (N-331.9): three dented rock() balls in the palette's
# cold "stone" (0.30/0.36/0.32) read pale blue-white by day and blue at night
# next to the faceted rock, and their 0.12 m moss crowns sank into the rock.
# Now three cheap faceted rocks (no ridge bevel, smaller hulls) that speak the
# forest rock's language, in their own "stone.cluster" -- the same albedo as
# stone.forest; LowpolyMaterials keys it as "stone" (cut at the first dot),
# so the palette's "stone" the depot uses stays as it was -- with a broad
# moss patch on each top facet, single-sided. Same footprint (about
# 2.3 x 1.4 m, 0.71 m tall) as before, base 4 cm underground.
CLUSTER_RINGS = [(0.0, 1.0, 6), (0.5, 0.92, 6), (0.88, 0.55, 4)]
# (centre x, y, size x, y, z, turn about Z, seed); the footprint is centred
# on the origin (the old cluster sat 0.11 m off in X).
CLUSTER_ROCKS = [(-0.11, 0.0, 1.40, 1.20, 0.74, 0.35, 3391),
                 (0.75, 0.18, 0.95, 0.74, 0.50, 2.6, 3392),
                 (-0.81, -0.27, 0.86, 0.66, 0.44, -1.2, 3393)]


def mossy_rock_cluster():
    clear()
    stone = stone_forest("stone.cluster")
    parts = []
    for x, y, sx, sy, sz, turn, seed in CLUSTER_ROCKS:
        o = faceted_rock("MossyRock", (sx, sy, sz), sink=0.04, seed=seed, rings=CLUSTER_RINGS,
                         bevel=0.0, moss=0.8, stone=stone)
        o.rotation_euler = (0.0, 0.0, turn)
        o.location = (x, y, 0.0)
        parts.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = o.data.name = "MossyRockCluster"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def mossy_stump():
    clear()
    s = cone("Stump", (0, 0, 0.35), 0.42, 0.36, 0.7, "trunk", 9)
    jitter(s, 0.03, 18, keep_bottom=-0.35)
    cylinder("StumpTop", (0, 0, 0.71), 0.35, 0.03, "trim", 9)
    for k in range(4):
        a = k * math.tau / 4 + 0.3
        cone("StumpRoot", (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.1), 0.18, 0.02, 0.45, "trunk", 5,
             rot=(math.sin(a) * 1.1, -math.cos(a) * 1.1, 0))
    crown("StumpMoss", (0.1, 0.12, 0.72), (0.25, 0.2, 0.06), "moss", 181, 0.2)
    crown("StumpMoss", (-0.35, 0.1, 0.35), (0.12, 0.2, 0.18), "moss", 182, 0.2)


def bramble():
    clear()
    rng = random.Random(19)
    for i in range(14):
        a = rng.uniform(0, math.tau)
        base = Vector((math.cos(a) * 0.15, math.sin(a) * 0.15, 0.0))
        # Canes arch up and out from the crown of the plant, never into the ground.
        rod("BrambleCane", tuple(base), tuple(base + outward(a, rng.uniform(0.45, 0.8)) * rng.uniform(0.8, 1.2)), 0.03, 0.01, "trunk", 4)
    for i in range(6):
        a = rng.uniform(0, math.tau)
        crown("BrambleLeaves", (math.cos(a) * 0.4, math.sin(a) * 0.4, rng.uniform(0.4, 0.8)), (0.35, 0.3, 0.22), "leaf_dark", 190 + i, 0.2)
    for i in range(8):
        a = rng.uniform(0, math.tau)
        blob("Berry", (math.cos(a) * 0.5, math.sin(a) * 0.5, rng.uniform(0.3, 0.8)), (0.04, 0.04, 0.04), "danger")


# Tall fern cluster (N-331.2): 24 flat, straight fronds were 960 tris for a
# prop that ground_plant scatters by the dozen (cap 250, N-331.6), so the
# fronds went one-sided, folded into a shallow V along the midrib (volume
# without closing the mesh) and drawn double-sided.
# N-331.8 (director-arte, 2026-10-12): those 20 smooth diamond blades in mint
# green read as an agave. Now 17 pinnate fronds of 14 tris: the midrib runs
# over seven spans and each span carries one triangular leaflet per side,
# swept toward the tip, with the notch between leaflets cut down to the
# midrib -- a saw-toothed, fishbone edge that reads as a fern from the cab.
# The midrib still rides above the leaflet tips (the V fold). Leaflets are
# short at the stipe, widest at a third and shrink to the tip, each a little
# jittered so no two fronds match. Upright and spreading fronds alternate in
# three rosettes (6 + 6 + 5): 238 tris, 2.62 x 2.12 m, 0.82 m tall (was
# 2.66 x 1.90 x 0.91).
# Colour: its own "fern.tall" (spreading, older fronds) and "fern.tall_young"
# (upright ones), yellow olive: more red and almost no blue, so the clump
# stands off the forest lawn (route_terrain.gdshader 0.285/0.43/0.205 ..
# 0.41/0.54/0.27) by hue, not by value. Passes (2026-10-18): 0.15/0.31/0.08
# read pale, lighter than the lawn; 0.085/0.18/0.04 went tone on tone with it
# (lost at night and at 10 m); now olive, its value between the two. The
# palette's cyan-ish "fern" (0.08/0.34/0.13, the small fern) is left alone. LowpolyMaterials keys
# both as "fern" (it cuts at the first dot): foliage detail and the autumn
# tint still apply, and the albedo gets x1.16 there (DETAIL_GAIN).
FERN_TALL = (0.13, 0.20, 0.03, 1)
FERN_TALL_YOUNG = (0.17, 0.25, 0.04, 1)
# Leaflet half-width along the frond (one per span, stipe to tip).
PINNA_WIDTHS = (0.3, 0.8, 1.0, 0.95, 0.78, 0.55, 0.3)


def _double_sided(name, suffix="doublesided", color=None):
    """A copy of palette material `name` that never culls back faces (glTF
    doubleSided), named "<name>.<suffix>" so LowpolyMaterials still keys it
    as `name` (it cuts the name at the first dot). `color` replaces the
    palette albedo in the copy only; the shared mat(name) is left alone."""
    m = bpy.data.materials.get(name + "." + suffix)
    if m is None:
        m = mat(name).copy()
        m.name = name + "." + suffix
        m.use_backface_culling = False
        if color is not None:
            principled = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            principled.inputs["Base Color"].default_value = color
            m.diffuse_color = color
    return m


def _pinnate_frond(bm, slot, root, heading, length, half_width, lift, droop, rng, fold=0.3):
    """One open fern frond: a midrib arcing out of `root` over len(PINNA_WIDTHS)
    spans (rising at `lift`, bending down by `droop` per quarter) and one
    triangular leaflet per span and side, 2 tris a span."""
    ch, sh = math.cos(heading), math.sin(heading)
    side = Vector((-sh, ch, 0.0))
    spans = len(PINNA_WIDTHS)
    seg = [0.1] + [0.9 / (spans - 1)] * (spans - 1)
    angles = [lift - droop * 3.0 * j / (spans - 1) for j in range(spans)]
    spine = [Vector(root)]
    for s, a in zip(seg, angles):
        spine.append(spine[-1] + Vector((ch * math.cos(a), sh * math.cos(a), math.sin(a))) * length * s)
    ups = [Vector((-ch * math.sin(a), -sh * math.sin(a), math.cos(a))) for a in angles]
    # Midrib raised by the fold (not the root at the ground, nor the tip).
    mid = [bm.verts.new(spine[0])]
    for j in range(1, spans):
        w = (PINNA_WIDTHS[j - 1] + PINNA_WIDTHS[j]) * 0.5 * half_width
        mid.append(bm.verts.new(spine[j] + (ups[j - 1] + ups[j]).normalized() * (w * fold)))
    mid.append(bm.verts.new(spine[-1]))
    for j in range(spans):
        for s in (-1.0, 1.0):
            w = PINNA_WIDTHS[j] * half_width * rng.uniform(0.85, 1.12)
            # Tip swept forward to about the next station (a serrated edge),
            # hanging a little below the midrib.
            reach = rng.uniform(0.95, 1.15)
            tooth = bm.verts.new(spine[j].lerp(spine[j + 1], reach) + side * (s * w) - ups[j] * (w * 0.15))
            f = bm.faces.new((mid[j], mid[j + 1], tooth))
            f.normal_update()
            if f.normal.dot(ups[j]) < 0.0:
                f.normal_flip()
            f.material_index = slot


def tall_fern_cluster():
    clear()
    mesh = bpy.data.meshes.new("TallFernCluster")
    obj = bpy.data.objects.new("TallFernCluster", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(_double_sided("fern", "tall", FERN_TALL))
    mesh.materials.append(_double_sided("fern", "tall_young", FERN_TALL_YOUNG))
    bm = bmesh.new()
    # Clump centres around the origin.
    for k, (x, y, count) in enumerate([(-0.03, -0.22, 6), (0.52, 0.08, 6), (-0.48, 0.13, 5)]):
        rng = random.Random(210 + k)
        start = rng.uniform(0.0, math.tau)
        for i in range(count):
            heading = start + i * math.tau / count + rng.uniform(-0.2, 0.2)
            if i % 2:   # spreading: rises ~45 deg, shorter, tip ends ~0.2 m up
                lift, droop, length, slot = rng.uniform(0.75, 0.9), rng.uniform(0.28, 0.34), 0.85, 0
            else:       # upright: rises ~65 deg and arches over, gives the clump its height
                lift, droop, length, slot = rng.uniform(1.12, 1.25), rng.uniform(0.3, 0.34), 1.27, 1
            _pinnate_frond(bm, slot, (x, y, 0.0), heading, length * rng.uniform(0.9, 1.08), 0.24, lift, droop, rng)
    bm.to_mesh(mesh)
    bm.free()


def deadfall_branch():
    clear()
    point = Vector((-1.3, 0.0, 0.1))
    heading = 0.0
    for i, (length, bend) in enumerate([(1.0, 0.25), (0.9, -0.35), (0.8, 0.3)]):
        heading += bend
        end = point + Vector((math.cos(heading) * length, math.sin(heading) * length, -0.01))
        rod("Deadfall", tuple(point), tuple(end), 0.09 - i * 0.018, 0.07 - i * 0.018, "trunk", 6)
        mid = point + (end - point) * 0.55
        rod("Twig", tuple(mid), tuple(mid + outward(heading + 1.2 * (1 if i % 2 else -1), 0.45) * 0.45), 0.03, 0.006, "trunk", 4)
        point = end


# =============================================================================
# Road signs
# =============================================================================

VIEW_X = -1.0  # symbols read from the front (+Y), where +X is the viewer's left
FACE = 0.032


def sign_post(height=2.0):
    cylinder("SignPost", (0, -0.06, height / 2), 0.045, height + 0.2, "metal", 8)
    cylinder("PostCap", (0, -0.06, height + 0.12), 0.055, 0.04, "metal", 8)
    cylinder("PostBase", (0, -0.06, 0.05), 0.12, 0.1, "concrete", 8)
    for dz in (-0.25, 0.25):
        cube("SignBracket", (0, -0.03, 2.0 + dz), (0.12, 0.06, 0.05), "metal")


def symbol(name, pts, material="sign_ink", depth=0.012):
    """An outline drawn as the driver sees it (x right, z up)."""
    return flat_poly(name, [(x * VIEW_X, z) for x, z in reversed(pts)], FACE, depth, material)


def diamond(z=2.0, size=0.84):
    half = size / math.sqrt(2)
    cube("SignBack", (0, -0.018, z), (size + 0.02, 0.02, size + 0.02), "metal", 0.01, rot=(0, math.pi / 4, 0))
    flat_poly("SignBorder", [(0, z + half + 0.05), (half + 0.05, z), (0, z - half - 0.05), (-half - 0.05, z)], -0.008, 0.02, "sign_ink")
    flat_poly("SignPanel", [(0, z + half - 0.02), (half - 0.02, z), (0, z - half + 0.02), (-half + 0.02, z)], 0.008, 0.024, "warning")


def scaled(pts, s, cx=0.0, cz=2.0):
    return [(cx + (x - cx) * s, cz + (z - cz) * s) for x, z in pts]


def sign(kind):
    clear()
    sign_post()
    if kind == "curve":
        diamond()
        arrow = [(-0.145, 1.72), (-0.055, 1.72), (-0.055, 1.971), (0.032, 2.057), (0.078, 2.011), (0.099, 2.188),
                 (-0.078, 2.167), (-0.032, 2.121), (-0.145, 2.009)]
        symbol("CurveArrow", scaled(arrow, 1.35, 0.0, 1.96))
    elif kind == "speed_bump":
        diamond()
        symbol("Road", [(-0.28, 1.8), (0.28, 1.8), (0.28, 1.84), (-0.28, 1.84)])
        for cx in (-0.12, 0.12):
            arc = [(cx + math.cos(math.pi * k / 8) * 0.09, 1.84 + math.sin(math.pi * k / 8) * 0.09) for k in range(9)]
            symbol("Bump", arc)
    elif kind == "narrow_bridge":
        diamond()
        symbol("SideLeft", [(-0.24, 1.72), (-0.15, 1.72), (-0.05, 2.28), (-0.12, 2.28)])
        symbol("SideRight", [(0.15, 1.72), (0.24, 1.72), (0.12, 2.28), (0.05, 2.28)])
    elif kind == "gravel":
        diamond()
        symbol("Road", [(-0.28, 1.8), (0.28, 1.8), (0.28, 1.84), (-0.28, 1.84)])
        rng = random.Random(31)
        for k in range(9):
            symbol("Pebble", circle_points(rng.uniform(-0.2, 0.2), rng.uniform(1.9, 2.2), rng.uniform(0.02, 0.035), 7))
    elif kind == "roadworks":
        flat_poly("SignBack", [(-0.66, 1.6), (0.66, 1.6), (0.0, 2.72)], -0.02, 0.02, "metal")
        flat_poly("SignBorder", [(-0.62, 1.62), (0.62, 1.62), (0.0, 2.68)], -0.004, 0.02, "danger")
        flat_poly("SignPanel", [(-0.46, 1.72), (0.46, 1.72), (0.0, 2.5)], 0.012, 0.02, "sign_white")
        symbol("WorkerBody", [(-0.08, 1.82), (-0.02, 1.82), (0.02, 1.98), (0.06, 2.1), (0.0, 2.12), (-0.06, 1.98)])
        symbol("WorkerHead", circle_points(0.05, 2.19, 0.04, 10))
        symbol("Shovel", [(0.02, 2.02), (0.2, 1.9), (0.22, 1.92), (0.04, 2.05)])
        symbol("Pile", [(0.12, 1.8), (0.34, 1.8), (0.28, 1.88), (0.2, 1.91), (0.15, 1.87)])
    elif kind == "delivery_ahead":
        cube("SignBack", (0, -0.02, 2.0), (0.94, 0.02, 0.66), "metal", 0.01)
        cube("SignBorder", (0, -0.004, 2.0), (0.9, 0.02, 0.62), "sign_white", 0.02)
        cube("SignPanel", (0, 0.012, 2.0), (0.82, 0.024, 0.54), "mint", 0.02)
        symbol("House", [(-0.34, 1.82), (-0.08, 1.82), (-0.08, 2.02), (-0.21, 2.14), (-0.34, 2.02)], "sign_white")
        symbol("HouseDoor", [(-0.24, 1.82), (-0.18, 1.82), (-0.18, 1.92), (-0.24, 1.92)], "mint", 0.016)
        symbol("Arrow", [(0.0, 1.96), (0.16, 1.96), (0.16, 1.9), (0.3, 2.0), (0.16, 2.1), (0.16, 2.04), (0.0, 2.04)], "sign_white")
    done(os.path.join(SIGNS, "sm_env_sign_%s.glb" % kind))


# =============================================================================
# Roadside furniture
# =============================================================================

def half_disc(cx, cz, radius, sides=10):
    """A rounded top in the XZ plane: flat edge down, dome up."""
    return [(cx + math.cos(math.pi * k / sides) * radius, cz + math.sin(math.pi * k / sides) * radius) for k in range(sides + 1)]


# The guardrail (N-332): 4 m along X (-2..+2), origin at the centre of its
# base, the road side (reflectors, beam face) on Blender +Y = Godot -Z.
# route_signage.gd lays one every 4 m a quarter turn round, so posts at
# x +-1 keep a 2 m spacing along a whole run and the splice (bolts) sits on
# the +X end, where the next section starts. Runs are cut every 0.8 m so
# bake_vertex_ao.py's 1 m subdivision has nothing left to cut. Rebuild and
# bake (from the repo root):
#
#   blender --background --factory-startup --python do-not-drop/assets/tools/build_lowpoly_refined.py -- guardrail
#   blender --background --factory-startup --python do-not-drop/assets/tools/bake_vertex_ao.py -- \
#       do-not-drop/assets/models/environment/props/sm_env_prop_guardrail.glb
def _srgb(hex_code):
    out = []
    for i in (0, 2, 4):
        c = int(hex_code[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


# Galvanised steel, mid grey: the kit's "guardrail" (linear 0.55) read as
# pale plastic next to the road. Dotted names keep LowpolyMaterials' key
# ("guardrail") and leave the shared palette entry -- the bridge railing,
# the vehicles' bumpers -- as it was.
PALETTE.update({
    "guardrail.galvanized": _srgb("9aa29e"),
    "guardrail.post": _srgb("6c7471"),
    "guardrail.bolt": _srgb("3b403f"),
})

GUARDRAIL_RINGS = 5
# W-beam centre line (y, z), bottom lip to top lip: two rounded crests
# toward the road, the bolting valley between them, lips curled back.
W_BEAM = [(0.004, 0.462), (0.020, 0.452), (0.046, 0.470), (0.070, 0.500), (0.080, 0.522),
          (0.076, 0.548), (0.048, 0.572), (0.022, 0.580), (0.022, 0.620), (0.048, 0.628),
          (0.076, 0.652), (0.080, 0.678), (0.070, 0.700), (0.046, 0.730), (0.020, 0.748), (0.004, 0.738)]
W_THICK = 0.014
VALLEY_FRONT = 0.022 + W_THICK / 2.0


def _shell(line, thickness):
    """A centre line (y, z) as a closed outline `thickness` thick."""
    front, back = [], []
    count = len(line)
    for i, (y, z) in enumerate(line):
        a = line[max(i - 1, 0)]
        b = line[min(i + 1, count - 1)]
        dy, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dy, dz)
        ny, nz = dz / length, -dy / length  # right of the walk up = toward +Y
        front.append((y + ny * thickness / 2.0, z + nz * thickness / 2.0))
        back.append((y - ny * thickness / 2.0, z - nz * thickness / 2.0))
    return front + list(reversed(back))


def _sweep(name, outline, axis, start, end, material, rings=1, caps=(True, True)):
    """A 2D outline swept along `axis` ("x": outline is (y, z); "y": (x, z);
    "z": (x, y)) from start to end, cut into `rings` runs."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()

    def place(a, b, t):
        if axis == "x":
            return (t, a, b)
        if axis == "y":
            return (a, t, b)
        return (a, b, t)

    loops = []
    for i in range(rings + 1):
        t = start + (end - start) * i / rings
        loops.append([bm.verts.new(place(a, b, t)) for a, b in outline])
    n = len(outline)
    for i in range(rings):
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new([loops[i][j], loops[i][k], loops[i + 1][k], loops[i + 1][j]])
    if caps[0]:
        bm.faces.new(list(reversed(loops[0])))
    if caps[1]:
        bm.faces.new(loops[-1])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def _chamfered(cx, cy, half_x, half_y, chamfer):
    return [(cx - half_x + chamfer, cy - half_y), (cx + half_x - chamfer, cy - half_y),
            (cx + half_x, cy - half_y + chamfer), (cx + half_x, cy + half_y - chamfer),
            (cx + half_x - chamfer, cy + half_y), (cx - half_x + chamfer, cy + half_y),
            (cx - half_x, cy + half_y - chamfer), (cx - half_x, cy - half_y + chamfer)]


def _frustum(name, bottom, top, z0, z1, material):
    """Two outlines of the same count (x, y) at z0 and z1: a cap with a chamfered top."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    low = [bm.verts.new((x, y, z0)) for x, y in bottom]
    high = [bm.verts.new((x, y, z1)) for x, y in top]
    n = len(low)
    for j in range(n):
        k = (j + 1) % n
        bm.faces.new([low[j], low[k], high[k], high[j]])
    bm.faces.new(list(reversed(low)))
    bm.faces.new(high)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def _bolt(x, z, y=VALLEY_FRONT):
    # Hex head on the beam face; its back is inside the steel, so no back cap.
    head = [(x + math.cos(i * math.tau / 6) * 0.014, z + math.sin(i * math.tau / 6) * 0.014) for i in range(6)]
    _sweep("SpliceBolt", head, "y", y - 0.004, y + 0.01, "guardrail.bolt", caps=(False, True))


def guardrail():
    clear()
    _sweep("WBeam", _shell(W_BEAM, W_THICK), "x", -2.0, 2.0, "guardrail.galvanized", rings=GUARDRAIL_RINGS)
    post_y, post_top = -0.13, 0.78
    hw, hd, ft, wt = 0.05, 0.075, 0.018, 0.012
    # I-section post: flanges facing the road and the field, web across.
    section = [(-hw, -hd), (hw, -hd), (hw, -hd + ft), (wt, -hd + ft), (wt, hd - ft), (hw, hd - ft),
               (hw, hd), (-hw, hd), (-hw, hd - ft), (-wt, hd - ft), (-wt, -hd + ft), (-hw, -hd + ft)]
    for x in (-1.0, 1.0):
        _sweep("GuardrailPost", [(x + a, post_y + b) for a, b in section], "z", 0.0, post_top,
               "guardrail.post", caps=(False, True))
        # Cap plate, chamfered round its top edge.
        _frustum("PostCap", _chamfered(x, post_y, 0.062, 0.088, 0.018), _chamfered(x, post_y, 0.05, 0.076, 0.014),
                 post_top, post_top + 0.026, "guardrail.post")
        # Blockout from the post's front flange to the back of the beam's valley.
        _sweep("Spacer", _chamfered(x, 0.6, 0.05, 0.1, 0.016), "y", post_y + hd, VALLEY_FRONT - W_THICK + 0.002,
               "guardrail.post")
        # Reflector on the post bolt, standing proud of both crests.
        cube("ReflectorBracket", (x, 0.057, 0.6), (0.03, 0.07, 0.03), "guardrail.bolt")
        cube("Reflector", (x, 0.098, 0.6), (0.1, 0.014, 0.07), "reflector")
    # Splice on the +X end: the next section's beam laps over this one here.
    for x in (1.73, 1.81, 1.89, 1.97):
        _bolt(x, 0.6)
    done(os.path.join(PROPS, "sm_env_prop_guardrail.glb"))


def roadside(kind):
    clear()
    if kind == "hay_bale":
        o = cylinder("HayBale", (0, 0, 0.62), 0.62, 1.2, "hay", 14, rot=(math.pi / 2, 0, 0))
        jitter(o, 0.02, 41)
        for y in (-0.6, 0.6):
            cylinder("BaleFace", (0, y, 0.62), 0.56, 0.02, "straw", 14, rot=(math.pi / 2, 0, 0))
        for y in (-0.32, 0.32):
            cylinder("BaleTwine", (0, y, 0.62), 0.635, 0.04, "trunk", 14, rot=(math.pi / 2, 0, 0))
        rng = random.Random(42)
        for k in range(6):
            a = rng.uniform(0, math.tau)
            cube("Straw", (math.cos(a) * 0.6, rng.uniform(-0.5, 0.5), 0.62 + math.sin(a) * 0.6), (0.2, 0.02, 0.02), "straw", rot=(0, a, 0))
    elif kind == "wooden_crate":
        cube("Crate", (0, 0, 0.45), (0.84, 0.84, 0.84), "wood")
        for sx in (-1, 1):
            for sy in (-1, 1):
                cube("CrateCorner", (sx * 0.42, sy * 0.42, 0.45), (0.1, 0.1, 0.9), "trim")
        for z in (0.06, 0.84):
            cube("CrateBand", (0, 0, z), (0.92, 0.92, 0.1), "trim")
        for sy in (-1, 1):
            cube("CrateBrace", (0, sy * 0.44, 0.45), (1.05, 0.03, 0.09), "trim", rot=(0, 0.79 * sy, 0))
        cube("CrateStencil", (0, 0.43, 0.6), (0.3, 0.01, 0.12), "sign_ink")
    elif kind == "pallet":
        for x in (-0.52, 0.0, 0.52):
            for y in (-0.33, 0.0, 0.33):
                cube("PalletBlock", (x, y, 0.05), (0.12, 0.12, 0.1), "wood")
        for y in (-0.33, 0.0, 0.33):
            cube("PalletStringer", (0, y, 0.115), (1.2, 0.12, 0.03), "wood")
        for k in range(5):
            cube("PalletSlat", (-0.5 + k * 0.25, 0, 0.145), (0.13, 0.8, 0.025), "trim", 0.004)
    elif kind == "fire_hydrant":
        cylinder("HydrantFlange", (0, 0, 0.04), 0.17, 0.08, "danger", 10)
        cylinder("HydrantBody", (0, 0, 0.36), 0.12, 0.56, "danger", 10)
        cylinder("HydrantCollar", (0, 0, 0.66), 0.15, 0.06, "danger", 10)
        dome = blob("HydrantBonnet", (0, 0, 0.7), (0.13, 0.13, 0.12), "danger")
        squash_bottom(dome, 0.0)
        cylinder("HydrantNut", (0, 0, 0.84), 0.04, 0.06, "metal", 5)
        for x in (-0.17, 0.17):
            cylinder("HydrantNozzle", (x, 0, 0.46), 0.05, 0.1, "danger", 8, rot=(0, math.pi / 2, 0))
            cylinder("NozzleCap", (x * 1.3, 0, 0.46), 0.055, 0.03, "metal", 8, rot=(0, math.pi / 2, 0))
        cylinder("HydrantPumper", (0, 0.17, 0.48), 0.07, 0.1, "danger", 8, rot=(math.pi / 2, 0, 0))
        for z in (0.2, 0.58):
            cylinder("HydrantRing", (0, 0, z), 0.13, 0.025, "sign_white", 10)
    elif kind == "bus_stop":
        cube("ShelterBase", (0, 0, 0.04), (3.0, 1.5, 0.08), "concrete", 0.01)
        for x in (-1.35, 1.35):
            for y in (-0.6, 0.55):
                cube("ShelterPost", (x, y, 1.25), (0.08, 0.08, 2.4), "metal")
        cube("ShelterRoof", (0, 0, 2.5), (3.1, 1.6, 0.1), "metal", 0.02, rot=(-0.08, 0, 0))
        cube("RoofTrim", (0, 0.78, 2.46), (3.1, 0.06, 0.16), "mint")
        cube("ShelterBack", (0, -0.6, 1.3), (2.62, 0.03, 1.7), "window")
        for x in (-1.35, 1.35):
            cube("ShelterSide", (x, -0.05, 1.3), (0.03, 1.1, 1.7), "window")
        cube("ShelterBench", (0, -0.3, 0.48), (2.2, 0.38, 0.06), "wood")
        for x in (-0.9, 0.9):
            cube("BenchLeg", (x, -0.3, 0.24), (0.06, 0.3, 0.48), "metal")
        cube("Timetable", (0.9, -0.57, 1.45), (0.55, 0.03, 0.7), "sign_white")
        cylinder("BusSignPole", (1.8, 0.4, 1.35), 0.04, 2.7, "metal", 8)
        cylinder("BusSign", (1.8, 0.4, 2.55), 0.26, 0.04, "mint", 14, rot=(math.pi / 2, 0, 0))
        cylinder("BusSignRing", (1.8, 0.39, 2.55), 0.28, 0.03, "sign_white", 14, rot=(math.pi / 2, 0, 0))
    elif kind == "milestone":
        cube("Milestone", (0, 0, 0.36), (0.36, 0.2, 0.72), "plaster", 0.02)
        flat_poly("MilestoneTop", half_disc(0.0, 0.72, 0.18), -0.1, 0.2, "plaster")
        cube("MilestoneBand", (0, 0, 0.62), (0.37, 0.21, 0.12), "mint")
        cube("MilestonePlate", (0, 0.105, 0.4), (0.22, 0.01, 0.16), "sign_white")
        cube("MilestoneNumber", (0, 0.112, 0.4), (0.1, 0.005, 0.1), "sign_ink")
        cube("MilestoneBase", (0, 0, 0.03), (0.44, 0.28, 0.06), "concrete")
    elif kind == "traffic_cone":
        cube("ConeBase", (0, 0, 0.03), (0.5, 0.5, 0.06), "rubber", 0.03)
        cone("Cone", (0, 0, 0.42), 0.22, 0.04, 0.72, "orange", 12)
        for z, r in ((0.38, 0.13), (0.56, 0.09)):
            cone("ConeBand", (0, 0, z), r + 0.012, r - 0.012, 0.08, "reflector", 12)
    elif kind == "road_barrier":
        cube("BarrierBoard", (0, 0, 0.85), (2.2, 0.06, 0.3), "sign_white", 0.01)
        # Diagonal chevron stripes painted on the board, both faces.
        for k in range(5):
            x0 = -0.98 + k * 0.44
            stripe = [(x0, 0.7), (x0 + 0.2, 0.7), (x0 + 0.34, 1.0), (x0 + 0.14, 1.0)]
            flat_poly("BarrierStripe", stripe, 0.03, 0.006, "danger")
            flat_poly("BarrierStripe", stripe, -0.036, 0.006, "danger")
        for x in (-0.85, 0.85):
            for y in (-0.22, 0.22):
                cube("BarrierLeg", (x, y * 0.5, 0.45), (0.07, 0.07, 0.95), "orange", rot=(y * 1.1, 0, 0))
            cube("BarrierFoot", (x, 0, 0.04), (0.12, 0.55, 0.08), "rubber")
        # Sits into the board's top edge (z 1.0) instead of hovering over it.
        cube("BarrierLight", (0.9, 0.0, 1.05), (0.12, 0.08, 0.12), "lamp", 0.02)
    elif kind == "mailbox":
        cube("PostBase", (0, 0, 0.05), (0.26, 0.26, 0.1), "concrete")
        cube("Post", (0, 0, 0.6), (0.1, 0.1, 1.1), "wood")
        cube("MailboxShelf", (0, 0, 1.15), (0.3, 0.55, 0.04), "wood")
        cube("Mailbox", (0, 0, 1.28), (0.3, 0.5, 0.22), "car_blue", 0.01)
        flat_poly("MailboxTop", half_disc(0.0, 1.39, 0.15), -0.25, 0.5, "car_blue")
        cube("MailboxDoor", (0, 0.255, 1.33), (0.28, 0.02, 0.3), "car_blue")
        cube("Flag", (0.17, -0.05, 1.45), (0.02, 0.04, 0.3), "danger")
        cube("FlagTip", (0.17, 0.02, 1.57), (0.02, 0.16, 0.08), "danger")
    elif kind == "street_lamp":
        cylinder("LampBase", (0, 0, 0.25), 0.16, 0.5, "metal", 10)
        cone("LampPost", (0, 0, 2.8), 0.08, 0.05, 4.8, "metal", 10)
        for i, (x, z, a) in enumerate([(0.25, 5.2, 0.6), (0.62, 5.36, 0.15), (0.95, 5.32, -0.35)]):
            cube("LampArm", (x, 0, z), (0.42, 0.06, 0.06), "metal", rot=(0, -a, 0))
        cone("LampHead", (1.1, 0, 5.12), 0.26, 0.12, 0.2, "metal", 4, rot=(0, 0, math.pi / 4))
        cube("LampGlass", (1.1, 0, 5.0), (0.26, 0.26, 0.05), "lamp")
    elif kind == "bench":
        for k in range(3):
            cube("SeatSlat", (0, -0.12 + k * 0.13, 0.48), (1.9, 0.11, 0.05), "wood", 0.01)
        for k in range(2):
            cube("BackSlat", (0, -0.24, 0.72 + k * 0.16), (1.9, 0.05, 0.12), "wood", 0.01, rot=(-0.2, 0, 0))
        for x in (-0.8, 0.8):
            flat_poly("BenchFrame", [(-0.25, 0.0), (-0.17, 0.0), (-0.13, 0.44), (0.18, 0.44), (0.22, 0.0), (0.3, 0.0), (0.25, 0.52), (-0.2, 0.52), (-0.26, 0.95), (-0.32, 0.95)],
                      x - 0.03, 0.06, "metal", plane="yz")
            cube("Armrest", (x, 0.0, 0.66), (0.07, 0.5, 0.05), "wood")
    done(os.path.join(PROPS, "sm_env_prop_%s.glb" % kind))


# =============================================================================
# Yard
# =============================================================================

def yard(kind):
    clear()
    if kind == "picket_fence":
        for x in (-0.98, 0.98):
            cube("FencePost", (x, 0, 0.5), (0.1, 0.1, 1.0), "sign_white")
            cone("PostCap", (x, 0, 1.05), 0.08, 0.02, 0.1, "sign_white", 4, rot=(0, 0, math.pi / 4))
        for k in range(8):
            x = -0.77 + k * 0.22
            flat_poly("Picket", [(x - 0.045, 0.06), (x + 0.045, 0.06), (x + 0.045, 0.82), (x, 0.9), (x - 0.045, 0.82)], -0.015, 0.03, "sign_white")
        for z in (0.28, 0.66):
            cube("FenceRail", (0, -0.04, z), (1.96, 0.04, 0.08), "sign_white")
    elif kind == "flower_pot":
        cone("Pot", (0, 0, 0.17), 0.14, 0.19, 0.34, "terracotta", 10)
        cylinder("PotRim", (0, 0, 0.35), 0.21, 0.05, "terracotta", 10)
        cylinder("Soil", (0, 0, 0.37), 0.18, 0.02, "trunk", 10)
        for k in range(5):
            a = k * math.tau / 5
            frond("PotLeaf", 0.2, 0.05, a, 0.5, "leaf", z=0.38)
            blob("Bloom", (math.cos(a + 0.6) * 0.08, math.sin(a + 0.6) * 0.08, 0.5), (0.05, 0.05, 0.04), "flower")
        blob("Bloom", (0, 0, 0.55), (0.06, 0.06, 0.05), "danger")
    elif kind == "garden_gnome":
        cube("GnomeBase", (0, 0, 0.02), (0.2, 0.2, 0.04), "moss")
        cone("GnomeBody", (0, 0, 0.16), 0.1, 0.07, 0.24, "window", 8)
        cylinder("GnomeBelt", (0, 0, 0.2), 0.085, 0.03, "rubber", 8)
        for sx in (-1, 1):
            cone("GnomeArm", (sx * 0.08, 0.02, 0.2), 0.025, 0.02, 0.14, "window", 5, rot=(0.3, sx * 0.5, 0))
        blob("GnomeFace", (0, 0.01, 0.32), (0.06, 0.06, 0.06), "skin_gnome")
        blob("GnomeNose", (0, 0.065, 0.32), (0.02, 0.02, 0.02), "skin_gnome")
        cone("GnomeBeard", (0, 0.04, 0.26), 0.06, 0.0, 0.14, "sign_white", 6, rot=(math.pi, 0, 0))
        cone("GnomeHat", (0, -0.01, 0.46), 0.075, 0.0, 0.24, "danger", 8, rot=(-0.15, 0, 0))
    elif kind == "dog_house":
        cube("DogHouseFloor", (0, 0, 0.05), (0.95, 1.05, 0.1), "wood")
        cube("DogHouseWalls", (0, 0, 0.42), (0.85, 0.95, 0.64), "barn_red", 0.02)
        gable_roof("DogHouseRoof", 0.74, 0.85, 0.95, 0.6, "roof_blue", "barn_red", overhang=0.1, thickness=0.06)
        arch = [(-0.17, 0.1), (0.17, 0.1), (0.17, 0.4)] + [(math.cos(math.pi * k / 6) * 0.17, 0.4 + math.sin(math.pi * k / 6) * 0.17) for k in range(1, 6)] + [(-0.17, 0.4)]
        flat_poly("DogHouseDoor", arch, 0.476, 0.01, "sign_ink")
        cube("NamePlate", (0, 0.48, 0.72), (0.3, 0.01, 0.08), "trim")
        cylinder("Bowl", (0.35, 0.65, 0.04), 0.1, 0.08, "danger", 10)
    elif kind == "doormat":
        cube("Doormat", (0, 0, 0.01), (0.9, 0.55, 0.02), "cardboard", 0.005)
        cube("DoormatBorder", (0, 0, 0.021), (0.82, 0.47, 0.004), "trunk")
        cube("DoormatStripe", (0, 0, 0.024), (0.7, 0.08, 0.004), "mint")
    done(os.path.join(YARD, "sm_env_yard_%s.glb" % kind))


GROUPS = {
    "houses": lambda: ([house(v) for v in HOUSES], barn()),
    "trees": lambda: [fn() or export_forest(name) for name, fn in TREES.items()],
    "plants": lambda: [fn() or export_forest(name) for name, fn in PLANTS.items()],
    "signs": lambda: [sign(k) for k in ("curve", "speed_bump", "narrow_bridge", "gravel", "roadworks", "delivery_ahead")],
    # Crate, milestone, cone, mailbox, street lamp, gnome and doormat moved to
    # build_street_props.py (N-140, 2026-09-27); their functions here stay as reference.
    "props": lambda: (guardrail(), [roadside(k) for k in ("hay_bale", "pallet", "fire_hydrant", "bus_stop",
                                                        "road_barrier", "bench")]),
    # Only the guardrail (N-332), without rewriting the other props.
    "guardrail": guardrail,
    # Only the tall fern cluster (N-331.2, N-331.8), without rewriting the other plants.
    "tall_fern": lambda: (tall_fern_cluster(), export_forest("tall_fern_cluster")),
    # Only the forest rock (N-331.7), without rewriting the other plants.
    "rock": lambda: (forest_rock(), export_forest("rock")),
    # Only the mossy rock cluster (N-331.9), without rewriting the other plants.
    "rock_cluster": lambda: (mossy_rock_cluster(), export_forest("mossy_rock_cluster")),
    # Only the mushroom cluster (N-331.3), without rewriting the other plants.
    "mushroom": lambda: (mushroom(), export_forest("mushroom")),
    "yard": lambda: [yard(k) for k in ("picket_fence", "flower_pot", "dog_house")],
}
TREES = {"oak": tree_oak, "birch": tree_birch, "pine_tall": tree_pine, "maple": tree_maple, "dead": tree_dead, "pine_sapling": tree_sapling}
PLANTS = {"bush_round": bush, "fern": fern, "grass_clump": grass, "wildflower": flowers, "mushroom": mushroom, "fallen_log": log,
          "rock": forest_rock, "bramble_thicket": bramble, "tall_fern_cluster": tall_fern_cluster, "mossy_stump": mossy_stump,
          "mossy_rock_cluster": mossy_rock_cluster, "deadfall_branch": deadfall_branch, "tall_grass_clump": tall_grass}


def export_forest(name):
    done(os.path.join(FOREST, "sm_env_forest_%s.glb" % name))


requested = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(GROUPS)
for group in requested:
    GROUPS[group]()

print("REFINED_REPORT")
for path, tris in REPORT:
    print("  %-62s %6d tris" % (path, tris))
print("REFINED_COUNT", len(REPORT))
