"""Openable delivery boxes and what's inside them (Blender 5.2, background).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
        --python do-not-drop/assets/tools/build_cargo_packages.py [-- boxes contents]

Run art/tools/make_cargo_textures.py first: it paints the printed cardboard
atlases and writes cargo_layout.json (box sizes + the UV rect of every
printed region), which this script only reads.

Boxes -> models/cargo/sm_cargo_box_<variant>.glb, origin at the centre of the
base, sized exactly like the collider package_feedback.gd gives each trap:

    Body       open-top shell: printed outside, plain kraft inside, board
               thickness on the rim, the cut ends of the tape down each side
    FlapFront  the four top flaps, each with its origin ON ITS HINGE so Godot
    FlapBack   only rotates them (package_contents_view.gd). Front/back are
    FlapRight  the outer flaps and carry one half of the brand tape each,
    FlapLeft   so opening splits the tape where a knife would.

Blender -Y becomes Godot +Z, so FlapFront/front print face the same way as
the shipping label.

Contents -> models/cargo/contents/sm_cargo_content_<id>.glb, origin at the
centre of the base (sits on the box floor):

    Filler     packing (paper shreds, straw nest, tea towel); may be absent
    Intact     the item, one mesh
    Damage     extra bits shown on top of Intact once the package is AT_RISK
    Ruined     empty whose children are the loose pieces of the wrecked item;
               each child becomes its own rigid body if the box spills
"""
import bpy
import bmesh
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lowpoly_kit import PALETTE, ROOT, blob, clear, cone, cube, cylinder, export, jitter, mat, triangle_count  # noqa: E402

PROJECT = os.path.abspath(os.path.join(ROOT, "..", ".."))
LAYOUT = json.load(open(os.path.join(os.path.dirname(__file__), "cargo_layout.json"), encoding="utf-8"))
CARGO = os.path.join(ROOT, "models", "cargo")
CONTENTS = os.path.join(CARGO, "contents")

BOARD = 0.012        # corrugated board thickness
FLAP_GAP = 0.003     # keeps closed flaps from z-fighting each other
TAPE_WIDTH = 0.05
TAPE_LIFT = 0.0015
TAPE_TAB = 0.08      # how far the tape runs down each side

PALETTE.update({
    "porcelain": (0.86, 0.87, 0.84, 1), "cobalt": (0.02, 0.07, 0.36, 1),
    "crack": (0.05, 0.04, 0.04, 1), "shreds": (0.86, 0.83, 0.72, 1),
    "shreds_light": (0.55, 0.36, 0.16, 1), "hen": (0.90, 0.86, 0.78, 1),
    "comb": (0.70, 0.05, 0.04, 1), "beak": (0.95, 0.52, 0.06, 1),
    "eye": (0.01, 0.01, 0.01, 1), "egg": (0.82, 0.62, 0.42, 1),
    "yolk": (0.95, 0.55, 0.02, 1), "cake": (0.93, 0.84, 0.66, 1),
    "frosting": (0.95, 0.50, 0.56, 1), "cherry": (0.60, 0.02, 0.05, 1),
    "cake_board": (0.75, 0.72, 0.62, 1), "sponge": (0.85, 0.60, 0.30, 1),
    "suit": (0.03, 0.03, 0.05, 1), "dress": (0.95, 0.95, 0.93, 1),
    "dough": (0.80, 0.58, 0.30, 1), "bowl": (0.12, 0.40, 0.42, 1),
    "bowl_inner": (0.80, 0.78, 0.70, 1), "towel": (0.72, 0.10, 0.08, 1),
    "towel_light": (0.90, 0.88, 0.82, 1), "card": (0.95, 0.92, 0.84, 1),
})


# --- Mesh building ------------------------------------------------------------

class Builder:
    """Collects quads with explicit UVs into one mesh object."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def quad(self, pts, uvs):
        verts = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(verts)
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def face(self, c, r, u, rect):
        """A rectangle centred at c spanning +-r and +-u. Normal is r x u;
        the UV rect maps r to U and u to V, so print reads upright."""
        pts = [tuple(c[i] - r[i] - u[i] for i in range(3)), tuple(c[i] + r[i] - u[i] for i in range(3)),
               tuple(c[i] + r[i] + u[i] for i in range(3)), tuple(c[i] - r[i] + u[i] for i in range(3))]
        u0, v0, u1, v1 = rect
        return self.quad(pts, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])

    def slab(self, lo, hi, top, bottom, side):
        """Axis-aligned box from lo to hi (six faces, outward normals)."""
        cx, cy, cz = [(lo[i] + hi[i]) / 2 for i in range(3)]
        hx, hy, hz = [(hi[i] - lo[i]) / 2 for i in range(3)]
        self.face((cx, cy, hi[2]), (hx, 0, 0), (0, hy, 0), top)
        self.face((cx, cy, lo[2]), (hx, 0, 0), (0, -hy, 0), bottom)
        self.face((cx, lo[1], cz), (hx, 0, 0), (0, 0, hz), side)
        self.face((cx, hi[1], cz), (-hx, 0, 0), (0, 0, hz), side)
        self.face((hi[0], cy, cz), (0, hy, 0), (0, 0, hz), side)
        self.face((lo[0], cy, cz), (0, -hy, 0), (0, 0, hz), side)

    def to_object(self, name, material, location=(0, 0, 0)):
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(name, mesh)
        obj.location = location
        bpy.context.collection.objects.link(obj)
        mesh.materials.append(material)
        return obj


def sub_rect(rect, a0, a1, b0=0.0, b1=1.0):
    """Part of a UV rect: U from a0..a1 and V from b0..b1 (fractions)."""
    u0, v0, u1, v1 = rect
    return (u0 + (u1 - u0) * a0, v0 + (v1 - v0) * b0, u0 + (u1 - u0) * a1, v0 + (v1 - v0) * b1)


def box_material(variant, texture_path):
    m = bpy.data.materials.new("cargo_box_%s" % variant)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    principled = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    principled.inputs["Roughness"].default_value = 0.86
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(texture_path)
    m.node_tree.links.new(tex.outputs["Color"], principled.inputs["Base Color"])
    return m


# --- Boxes ----------------------------------------------------------------------

def build_box(variant):
    clear()
    spec = LAYOUT[variant]
    W, D, H = spec["dims"]
    R = spec["regions"]
    material = box_material(variant, os.path.join(PROJECT, spec["texture"]))
    t = BOARD
    wall_h = H - 2 * t  # two flap layers finish the box at exactly H

    # The tape row is painted for a 5 cm strip; how long a stretch of it the
    # row holds decides how much of it each piece of tape takes.
    row = R["tape_row"]
    row_len = TAPE_WIDTH * (row[2] - row[0]) / (row[3] - row[1])

    def tape_u(length):
        return min(1.0, length / row_len)

    body = Builder()
    hz = wall_h / 2
    body.face((0, -D / 2, hz), (W / 2, 0, 0), (0, 0, hz), R["front"])
    body.face((0, D / 2, hz), (-W / 2, 0, 0), (0, 0, hz), R["back"])
    body.face((W / 2, 0, hz), (0, D / 2, 0), (0, 0, hz), R["right"])
    body.face((-W / 2, 0, hz), (0, -D / 2, 0), (0, 0, hz), R["left"])
    body.face((0, 0, 0), (W / 2, 0, 0), (0, -D / 2, 0), R["bottom"])
    iw, idp, ih = W / 2 - t, D / 2 - t, (wall_h - t) / 2
    ic = t + ih
    body.face((0, -D / 2 + t, ic), (-iw, 0, 0), (0, 0, ih), R["inner"])
    body.face((0, D / 2 - t, ic), (iw, 0, 0), (0, 0, ih), R["inner"])
    body.face((W / 2 - t, 0, ic), (0, -idp, 0), (0, 0, ih), R["inner"])
    body.face((-W / 2 + t, 0, ic), (0, idp, 0), (0, 0, ih), R["inner"])
    body.face((0, 0, t), (iw, 0, 0), (0, idp, 0), R["inner"])
    for y in (-D / 2 + t / 2, D / 2 - t / 2):
        body.face((0, y, wall_h), (W / 2, 0, 0), (0, t / 2, 0), R["inner"])
    for x in (-W / 2 + t / 2, W / 2 - t / 2):
        body.face((x, 0, wall_h), (t / 2, 0, 0), (0, D / 2 - t, 0), R["inner"])
    # Cut ends of the tape, left behind on the sides when the flaps open.
    tab_len = TAPE_TAB + 2 * t
    tab_c = wall_h + 2 * t - tab_len / 2
    body.face((W / 2 + TAPE_LIFT, 0, tab_c), (0, TAPE_WIDTH / 2, 0), (0, 0, tab_len / 2), sub_rect(row, 0.0, tape_u(tab_len)))
    body.face((-W / 2 - TAPE_LIFT, 0, tab_c), (0, -TAPE_WIDTH / 2, 0), (0, 0, tab_len / 2), sub_rect(row, 0.3, 0.3 + tape_u(tab_len)))
    body.to_object("Body", material)

    # Outer flaps (front/back) meet over the middle; each carries half the tape.
    outer_depth = D / 2 - FLAP_GAP
    for name, sign in (("FlapFront", -1.0), ("FlapBack", 1.0)):
        flap = Builder()
        # Local frame: hinge at the origin, flap reaching toward the centre.
        y_lo, y_hi = (0.0, outer_depth) if sign < 0 else (-outer_depth, 0.0)
        z_lo, z_hi = t, 2 * t
        r = (W / 2, 0, 0) if sign < 0 else (-W / 2, 0, 0)
        u = (0, outer_depth / 2, 0) if sign < 0 else (0, -outer_depth / 2, 0)
        cy = (y_lo + y_hi) / 2
        hy = outer_depth / 2
        flap.face((0, cy, z_hi), r, u, R["flap"])
        flap.face((0, cy, z_lo), (W / 2, 0, 0), (0, -hy, 0), R["inner"])
        zc, hz2 = (z_lo + z_hi) / 2, (z_hi - z_lo) / 2
        flap.face((0, y_lo, zc), (W / 2, 0, 0), (0, 0, hz2), R["inner"])
        flap.face((0, y_hi, zc), (-W / 2, 0, 0), (0, 0, hz2), R["inner"])
        flap.face((W / 2, cy, zc), (0, hy, 0), (0, 0, hz2), R["inner"])
        flap.face((-W / 2, cy, zc), (0, -hy, 0), (0, 0, hz2), R["inner"])
        # Tape half: the strip's V runs across the seam, so the two halves
        # of the lettering part company when the box is opened.
        seam = outer_depth + FLAP_GAP  # distance from hinge to the seam
        half = TAPE_WIDTH / 2
        if sign < 0:
            flap.face((0, seam - FLAP_GAP - half / 2, z_hi + TAPE_LIFT), (W / 2, 0, 0), (0, half / 2, 0), sub_rect(row, 0.0, tape_u(W), 0.0, 0.5))
        else:
            flap.face((0, -(seam - FLAP_GAP - half / 2), z_hi + TAPE_LIFT), (W / 2, 0, 0), (0, half / 2, 0), sub_rect(row, 0.0, tape_u(W), 0.5, 1.0))
        flap.to_object(name, material, (0, sign * D / 2, wall_h))

    # Inner flaps (sides) fold first and sit under the outer ones.
    side_depth = W / 2 - FLAP_GAP * 2
    for name, sign in (("FlapRight", 1.0), ("FlapLeft", -1.0)):
        flap = Builder()
        x_lo, x_hi = (-side_depth, 0.0) if sign > 0 else (0.0, side_depth)
        y_half = D / 2 - FLAP_GAP
        flap.slab((x_lo, -y_half, 0.0), (x_hi, y_half, t), R["outer"], R["inner"], R["inner"])
        flap.to_object(name, material, (sign * W / 2, 0, wall_h))

    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            for p in o.data.polygons:
                p.use_smooth = False
    print("box", variant, "tris", triangle_count())
    export(os.path.join(CARGO, "sm_cargo_box_%s.glb" % variant))


# --- Content helpers ----------------------------------------------------------------

def lathe(name, profile, material, segments=14, start=0.0, span=math.tau, location=(0, 0, 0)):
    """Revolves (radius, z) points around Z. A partial span makes a curved
    shard; a full one closes the seam. Radius 0 ends become poles."""
    bm = bmesh.new()
    closed = abs(span - math.tau) < 1e-6
    steps = segments if closed else segments + 1
    rings = []
    for r, z in profile:
        ring = []
        for i in range(steps):
            a = start + span * i / segments
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        a_ring, b_ring = rings[k], rings[k + 1]
        for i in range(segments):
            j = (i + 1) % steps
            quad = [a_ring[i], a_ring[j], b_ring[j], b_ring[i]]
            unique = []
            for v in quad:
                if all((v.co - w.co).length > 1e-7 for w in unique):
                    unique.append(v)
            if len(unique) >= 3:
                try:
                    bm.faces.new(unique)
                except ValueError:
                    pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat(material))
    return obj


def solidify(obj, thickness):
    mod = obj.modifiers.new("Thickness", "SOLIDIFY")
    mod.thickness = thickness
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)
    return obj


def join(name, objects):
    objects = [o for o in objects if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Origin back to the content origin: every group shares the base centre.
    obj.select_set(False)
    return obj


def place(obj, location, rotation):
    """Re-centres obj's origin on its own geometry, then puts it there --
    rotating around the content origin would swing a piece out of the box."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.location = location
    obj.rotation_euler = rotation
    obj.select_set(False)
    return obj


def group(name, pieces):
    """An empty holding separate pieces (each keeps its own origin, at its
    own centre, so it tumbles believably once it's a rigid body)."""
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    for i, piece in enumerate(pieces):
        bpy.ops.object.select_all(action="DESELECT")
        piece.select_set(True)
        bpy.context.view_layer.objects.active = piece
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        piece.name = "%s_%02d" % (name, i)
        piece.parent = empty
    return empty


def scatter_strips(name, count, half_x, half_y, z0, z1, materials, seed, size=(0.07, 0.012, 0.004)):
    rng = random.Random(seed)
    strips = []
    for i in range(count):
        s = cube("%s%d" % (name, i), (rng.uniform(-half_x, half_x), rng.uniform(-half_y, half_y), rng.uniform(z0, z1)),
                 (size[0] * rng.uniform(0.6, 1.4), size[1], size[2]), rng.choice(materials),
                 rot=(rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, math.pi)))
        strips.append(s)
    return strips


def mound(name, half_x, half_y, height, material, seed, sub=6):
    """A lumpy bed filling the box floor."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=sub, y_subdivisions=sub, size=1.0, location=(0, 0, 0))
    o = bpy.context.object
    o.name = name
    o.scale = (half_x * 2, half_y * 2, 1)
    bpy.ops.object.transform_apply(scale=True)
    rng = random.Random(seed)
    for v in o.data.vertices:
        edge = max(abs(v.co.x) / half_x, abs(v.co.y) / half_y)
        v.co.z = height * (0.55 + 0.45 * rng.random()) * (1.0 - 0.35 * edge)
    o.data.materials.append(mat(material))
    return o


def finish(content_id):
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            for p in o.data.polygons:
                p.use_smooth = False
    print("content", content_id, "tris", triangle_count())
    export(os.path.join(CONTENTS, "sm_cargo_content_%s.glb" % content_id))


def inner_half(variant):
    W, D, H = LAYOUT[variant]["dims"]
    return W / 2 - BOARD - 0.004, D / 2 - BOARD - 0.004, H - 3 * BOARD


# --- Contents --------------------------------------------------------------------

VASE = [(0.0, 0.0), (0.075, 0.0), (0.11, 0.03), (0.15, 0.13), (0.152, 0.21), (0.115, 0.32), (0.062, 0.39),
        (0.058, 0.43), (0.088, 0.465), (0.078, 0.47), (0.05, 0.44), (0.0, 0.44)]


def porcelain_vase():
    """Fragile: a blue-and-white porcelain vase bedded in paper shreds."""
    clear()
    hx, hy, _ = inner_half("cube")
    bed_h = 0.06
    filler = [mound("bed", hx, hy, bed_h, "shreds", 11)]
    filler += scatter_strips("shred", 34, hx * 0.95, hy * 0.95, bed_h * 0.6, bed_h + 0.03, ["shreds", "shreds_light"], 12)
    join("Filler", filler)

    lift = bed_h - 0.01
    vase = lathe("vase", VASE, "porcelain", location=(0, 0, lift))
    bands = [lathe("band_low", [(0.153, 0.12), (0.157, 0.14), (0.157, 0.16), (0.153, 0.175)], "cobalt", location=(0, 0, lift)),
             lathe("band_neck", [(0.064, 0.37), (0.068, 0.38), (0.066, 0.4)], "cobalt", location=(0, 0, lift))]
    # A few painted petals on the belly.
    for i in range(6):
        a = i * math.tau / 6
        dot = blob("petal%d" % i, (math.cos(a) * 0.152, math.sin(a) * 0.152, lift + 0.22), (0.012, 0.012, 0.03), "cobalt")
        dot.rotation_euler = (0, 0, a)
        bands.append(dot)
    join("Intact", [vase] + bands)

    # AT_RISK: hairline cracks running across the belly.
    cracks = []
    rng = random.Random(3)
    for c in range(2):
        a = rng.uniform(-1.9, -1.2) + c * 0.5
        z = lift + 0.17 + c * 0.06
        for k in range(4):
            a2 = a + rng.uniform(0.08, 0.16)
            z2 = z + rng.uniform(-0.03, 0.03)
            mx, my = math.cos((a + a2) / 2) * 0.1545, math.sin((a + a2) / 2) * 0.1545
            seg = cube("crack", (mx, my, (z + z2) / 2), (0.004, 0.024, 0.0035), "crack",
                       rot=(math.atan2(z2 - z, 0.02), 0, (a + a2) / 2))
            cracks.append(seg)
            a, z = a2, z2
    join("Damage", cracks)

    # RUINED: the base still standing, the rest in curved shards.
    pieces = [lathe("base", [(0.0, 0.0), (0.075, 0.0), (0.11, 0.03), (0.14, 0.09), (0.0, 0.09)], "porcelain", location=(0, 0, lift))]
    rng = random.Random(9)
    for i in range(6):
        start = i * math.tau / 6 + rng.uniform(-0.2, 0.2)
        z0 = rng.choice([0.1, 0.2])
        shard = lathe("shard", [(0.152, z0), (0.15, z0 + 0.09), (0.12, z0 + 0.14)], "porcelain", segments=2, start=start, span=math.tau / 7)
        solidify(shard, 0.008)
        a = start + 0.4
        place(shard, (math.cos(a) * hx * 0.6, math.sin(a) * hy * 0.6, lift + 0.06),
              (rng.uniform(1.2, 1.5), rng.uniform(-0.3, 0.3), a + math.pi / 2))
        pieces.append(shard)
    neck = lathe("neck", [(0.062, 0.39), (0.058, 0.43), (0.088, 0.465), (0.05, 0.44), (0.062, 0.39)], "porcelain")
    place(neck, (0.12, -0.12, lift + 0.05), (1.45, 0, 0.6))
    pieces.append(neck)
    group("Ruined", pieces)
    finish("porcelain_vase")


def hen():
    """Ruidoso: a laying hen on a straw nest. Ruined means she got out."""
    clear()
    hx, hy, _ = inner_half("vented")
    nest_h = 0.07
    filler = [mound("nest", hx, hy, nest_h, "hay", 21)]
    filler += scatter_strips("straw", 40, hx * 0.95, hy * 0.95, nest_h * 0.5, nest_h + 0.04, ["hay", "straw"], 22, size=(0.09, 0.006, 0.006))
    join("Filler", filler)

    z = nest_h
    parts = [
        blob("body", (0, 0.02, z + 0.12), (0.15, 0.19, 0.13), "hen", 2),
        blob("breast", (0, -0.1, z + 0.14), (0.11, 0.09, 0.11), "hen", 1),
        blob("head", (0, -0.15, z + 0.29), (0.065, 0.07, 0.075), "hen", 1),
        blob("neck", (0, -0.13, z + 0.21), (0.06, 0.06, 0.08), "hen", 1),
        cone("beak", (0, -0.23, z + 0.29), 0.022, 0.0, 0.05, "beak", 6, rot=(math.pi / 2, 0, 0)),
        blob("wattle", (0, -0.2, z + 0.24), (0.016, 0.014, 0.028), "comb", 1),
        blob("eye_l", (0.052, -0.18, z + 0.31), (0.012, 0.012, 0.012), "eye", 1),
        blob("eye_r", (-0.052, -0.18, z + 0.31), (0.012, 0.012, 0.012), "eye", 1),
        blob("wing_l", (0.14, 0.03, z + 0.14), (0.03, 0.14, 0.08), "hen", 1),
        blob("wing_r", (-0.14, 0.03, z + 0.14), (0.03, 0.14, 0.08), "hen", 1),
    ]
    for i, dy in enumerate((-0.18, -0.15, -0.12)):
        parts.append(blob("comb%d" % i, (0, dy, z + 0.365 - abs(dy + 0.15) * 0.6), (0.014, 0.022, 0.03), "comb", 1))
    for i, (dx, tilt) in enumerate(((-0.05, -0.3), (0.0, 0.0), (0.05, 0.3))):
        parts.append(cone("tail%d" % i, (dx, 0.2, z + 0.26), 0.05, 0.012, 0.18, "hen", 5, rot=(-0.5, tilt, 0)))
    join("Intact", parts)

    rng = random.Random(4)
    feathers = []
    for i in range(9):
        f = blob("feather%d" % i, (rng.uniform(-hx * 0.8, hx * 0.8), rng.uniform(-hy * 0.8, hy * 0.8), nest_h + rng.uniform(0.02, 0.3)),
                 (0.012, 0.035, 0.004), "hen", 1)
        f.rotation_euler = (rng.uniform(0, 1), rng.uniform(0, 1), rng.uniform(0, math.tau))
        feathers.append(f)
    join("Damage", feathers)

    pieces = []
    for i in range(5):
        f = blob("loose%d" % i, (rng.uniform(-hx * 0.7, hx * 0.7), rng.uniform(-hy * 0.7, hy * 0.7), nest_h + 0.02),
                 (0.014, 0.04, 0.005), "hen", 1)
        f.rotation_euler = (0.2, 0.1, rng.uniform(0, math.tau))
        pieces.append(f)
    shell_a = solidify(lathe("shell_a", [(0.0, 0.0), (0.03, 0.006), (0.04, 0.03), (0.036, 0.045)], "egg", 10), 0.004)
    shell_a.location = (0.05, 0.02, nest_h + 0.005)
    shell_b = solidify(lathe("shell_b", [(0.0, 0.0), (0.028, 0.01), (0.038, 0.04)], "egg", 10), 0.004)
    shell_b.location = (-0.03, 0.08, nest_h + 0.03)
    shell_b.rotation_euler = (2.2, 0.3, 0)
    yolk = blob("yolk", (0.0, 0.05, nest_h + 0.005), (0.035, 0.03, 0.008), "yolk", 1)
    pieces += [shell_a, shell_b, yolk]
    group("Ruined", pieces)
    finish("hen")


def wedding_cake():
    """Equilibrio: three tiers on a board. Ruined means it slid and slumped."""
    clear()
    board_r = 0.19
    tiers = [(0.17, 0.2), (0.13, 0.16), (0.09, 0.14)]

    def build_tiers(prefix, lean=0.0, slump=1.0, offsets=None):
        objs = []
        z = 0.015
        for i, (r, h) in enumerate(tiers):
            h2 = h * slump
            ox, oy = offsets[i] if offsets else (0.0, 0.0)
            tier = cylinder("%stier%d" % (prefix, i), (ox, oy, z + h2 / 2), r, h2, "cake", 14)
            tier.rotation_euler = (lean * (i + 1), 0, 0)
            top = cylinder("%stop%d" % (prefix, i), (ox, oy, z + h2 + 0.004), r * 1.01, 0.012, "frosting", 14)
            top.rotation_euler = tier.rotation_euler
            objs += [tier, top]
            for k in range(10 if i < 2 else 8):
                a = k * math.tau / (10 if i < 2 else 8)
                bead = blob("%sbead%d_%d" % (prefix, i, k), (ox + math.cos(a) * r, oy + math.sin(a) * r, z + h2 + 0.006),
                            (0.018, 0.018, 0.016), "frosting", 1)
                objs.append(bead)
                if k % 2 == 0:
                    drip = blob("%sdrip%d_%d" % (prefix, i, k), (ox + math.cos(a) * r * 1.005, oy + math.sin(a) * r * 1.005, z + h2 - 0.03 * slump),
                                (0.014, 0.014, 0.035 * slump), "frosting", 1)
                    objs.append(drip)
            z += h2
        return objs, z

    board = cylinder("board", (0, 0, 0.0075), board_r, 0.015, "cake_board", 16)
    tier_objs, top_z = build_tiers("i")
    cherries = [blob("cherry%d" % k, (math.cos(k * 2.1) * 0.05, math.sin(k * 2.1) * 0.05, top_z + 0.02), (0.018, 0.018, 0.018), "cherry", 1) for k in range(3)]
    # The couple on top: two little peg figures.
    groom = [cylinder("groom", (-0.025, 0, top_z + 0.05), 0.017, 0.07, "suit", 8),
             blob("groom_head", (-0.025, 0, top_z + 0.1), (0.016, 0.016, 0.018), "skin_gnome", 1)]
    bride = [cone("bride", (0.025, 0, top_z + 0.045), 0.03, 0.012, 0.075, "dress", 8),
             blob("bride_head", (0.025, 0, top_z + 0.1), (0.016, 0.016, 0.018), "skin_gnome", 1)]
    join("Intact", [board] + tier_objs + cherries + groom + bride)

    smears = [blob("smear%d" % k, (math.cos(k * 1.7) * 0.16, math.sin(k * 1.7) * 0.16, 0.02), (0.03, 0.02, 0.008), "frosting", 1) for k in range(3)]
    smears.append(blob("fallen_cherry", (0.15, -0.1, 0.03), (0.018, 0.018, 0.018), "cherry", 1))
    join("Damage", smears)

    # Ruined: the board, a squashed bottom tier, and the top two slid off.
    ruined = [cylinder("r_board", (0, 0, 0.0075), board_r, 0.015, "cake_board", 16)]
    ruined.append(join("r_bottom", [cylinder("rb", (0.0, 0.0, 0.015 + 0.06), 0.175, 0.12, "cake", 14),
                                     cylinder("rbt", (0.0, 0.0, 0.14), 0.18, 0.02, "frosting", 14)]))
    mid = join("r_mid", [cylinder("rm", (0, 0, 0), 0.13, 0.12, "cake", 14), cylinder("rmt", (0, 0, 0.065), 0.135, 0.014, "frosting", 14),
                          cylinder("rms", (0, 0, -0.065), 0.12, 0.01, "sponge", 14)])
    mid.location = (0.05, -0.04, 0.23)
    mid.rotation_euler = (0.55, 0.25, 0)
    top = join("r_top", [cylinder("rt", (0, 0, 0), 0.09, 0.1, "cake", 12), cylinder("rtt", (0, 0, 0.055), 0.095, 0.012, "frosting", 12)])
    top.location = (-0.09, 0.08, 0.2)
    top.rotation_euler = (-0.3, 1.2, 0)
    ruined += [mid, top]
    ruined.append(join("r_groom", [cylinder("rg", (0, 0, 0), 0.017, 0.07, "suit", 8), blob("rgh", (0, 0, 0.05), (0.016, 0.016, 0.018), "skin_gnome", 1)]))
    ruined[-1].location = (0.12, 0.1, 0.05)
    ruined[-1].rotation_euler = (1.57, 0, 0.7)
    for k in range(4):
        ruined.append(blob("r_blob%d" % k, (math.cos(k * 1.9) * 0.14, math.sin(k * 1.9) * 0.14, 0.03), (0.05, 0.04, 0.03), "frosting", 1))
    group("Ruined", ruined)
    finish("wedding_cake")


def sourdough():
    """Peso creciente: a big bowl of sourdough that won't stop rising."""
    clear()
    hx, hy, _ = inner_half("flat")
    towel = mound("towel", hx * 0.92, hy * 0.92, 0.012, "towel", 31, sub=5)
    stripes = [cube("stripe%d" % k, (0, -hy * 0.8 + k * hy * 0.4, 0.014), (hx * 1.8, 0.03, 0.004), "towel_light") for k in range(5)]
    join("Filler", [towel] + stripes)

    bowl_profile = [(0.0, 0.015), (0.19, 0.015), (0.3, 0.08), (0.36, 0.17), (0.38, 0.23), (0.355, 0.235), (0.34, 0.18),
                    (0.29, 0.1), (0.18, 0.04), (0.0, 0.04)]
    bowl = lathe("bowl", bowl_profile, "bowl", 16)
    dough = blob("dough", (0, 0, 0.2), (0.33, 0.33, 0.1), "dough", 2)
    jitter(dough, 0.012, 5)
    card = cube("card", (0.3, -0.3, 0.03), (0.12, 0.08, 0.003), "card", rot=(0.0, 0.0, 0.4))
    string = cube("string", (0.25, -0.25, 0.03), (0.1, 0.004, 0.002), "towel", rot=(0, 0, 0.9))
    join("Intact", [bowl, dough, card, string])

    drips = []
    for k in range(4):
        a = k * math.tau / 4 + 0.4
        d = blob("over%d" % k, (math.cos(a) * 0.35, math.sin(a) * 0.35, 0.2), (0.08, 0.06, 0.07), "dough", 1)
        jitter(d, 0.008, 40 + k)
        drips.append(d)
    drips.append(blob("dome", (0, 0, 0.27), (0.26, 0.26, 0.08), "dough", 2))
    join("Damage", drips)

    ruined = [lathe("r_bowl", bowl_profile, "bowl", 16)]
    big = blob("r_dough", (0, 0, 0.22), (0.43, 0.43, 0.16), "dough", 2)
    jitter(big, 0.02, 7)
    ruined.append(big)
    for k in range(5):
        a = k * math.tau / 5
        spill = blob("r_spill%d" % k, (math.cos(a) * 0.33, math.sin(a) * 0.33, 0.04), (0.1, 0.08, 0.04), "dough", 1)
        jitter(spill, 0.01, 60 + k)
        ruined.append(spill)
    group("Ruined", ruined)
    finish("sourdough")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["boxes", "contents"]
    if "boxes" in argv:
        for variant in LAYOUT:
            build_box(variant)
    if "contents" in argv:
        porcelain_vase()
        hen()
        wedding_cake()
        sourdough()


main()
