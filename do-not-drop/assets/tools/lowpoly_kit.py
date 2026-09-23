"""Shared helpers for the low-poly GLB builders (Blender 5.2, background mode).

Same primitives and material rules as `build_lowpoly_glb_assets.py` (batch 1),
split out so later batches can reuse them without re-exporting batch 1.
Blender is Z-up; the glTF exporter converts to Godot's Y-up. Every model sits
with its origin at the centre of its base, in metres.
"""
import bpy
import math
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

PALETTE = {
    # Batch 1 colours, unchanged so both batches read as one set.
    "wall": (0.66, 0.46, 0.30, 1), "plaster": (0.78, 0.66, 0.48, 1),
    "roof": (0.36, 0.12, 0.08, 1), "roof_blue": (0.10, 0.22, 0.28, 1),
    "wood": (0.28, 0.13, 0.055, 1), "window": (0.20, 0.48, 0.58, 1),
    "trim": (0.91, 0.79, 0.52, 1), "chimney": (0.30, 0.24, 0.22, 1),
    "trunk": (0.22, 0.10, 0.035, 1), "leaf": (0.12, 0.40, 0.15, 1),
    "leaf_dark": (0.06, 0.26, 0.10, 1), "grass": (0.25, 0.47, 0.16, 1),
    "flower": (0.93, 0.55, 0.24, 1), "stone": (0.30, 0.36, 0.32, 1),
    "metal": (0.22, 0.31, 0.34, 1), "cardboard": (0.54, 0.31, 0.13, 1),
    "danger": (0.83, 0.16, 0.08, 1), "orange": (0.95, 0.31, 0.05, 1),
    "rubber": (0.035, 0.045, 0.04, 1), "lamp": (1.0, 0.75, 0.24, 1),
    # Batch 2 additions, taken from docs/direccion-visual.md section 3.
    "warning": (0.79, 0.52, 0.08, 1),      # WARNING #e7be51 in linear
    "sign_ink": (0.02, 0.03, 0.03, 1),
    "mint": (0.23, 0.76, 0.49, 1),         # MINT #83e2ba in linear
    "sign_white": (0.83, 0.86, 0.80, 1),
    "concrete": (0.26, 0.30, 0.28, 1),     # CONCRETE #8c9791 in linear
    "guardrail": (0.55, 0.60, 0.60, 1),
    "hay": (0.72, 0.50, 0.15, 1), "barn_red": (0.42, 0.06, 0.04, 1),
    "cloud": (0.92, 0.95, 0.94, 1), "mountain_far": (0.20, 0.33, 0.35, 1),
    "mountain_snow": (0.80, 0.86, 0.86, 1), "phone": (0.03, 0.05, 0.06, 1),
    "screen": (0.10, 0.45, 0.40, 1), "glove": (0.16, 0.18, 0.17, 1),
    "PlayerTint": (0.85, 0.85, 0.85, 1),   # recoloured per player in Godot
    "skin_gnome": (0.85, 0.55, 0.40, 1), "water_tank": (0.35, 0.45, 0.47, 1),
    # Batch-1 colours the refined models reuse, and a few new accents.
    "birch": (0.72, 0.70, 0.57, 1), "leaf_light": (0.28, 0.54, 0.14, 1),
    "fern": (0.08, 0.34, 0.13, 1), "mushroom": (0.76, 0.16, 0.10, 1),
    "car_blue": (0.07, 0.28, 0.52, 1), "car_red": (0.62, 0.07, 0.05, 1),
    "shutter": (0.05, 0.24, 0.25, 1), "shutter_red": (0.45, 0.10, 0.07, 1),
    "terracotta": (0.62, 0.24, 0.10, 1), "moss": (0.14, 0.33, 0.08, 1),
    "straw": (0.80, 0.62, 0.24, 1), "reflector": (0.95, 0.95, 0.90, 1),
}
MATS = {}


def mat(name):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.diffuse_color = PALETTE[name]
        m.use_nodes = True
        # Look the node up by type: labels are localised in non-English Blender.
        principled = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if principled is None:
            raise RuntimeError("Principled BSDF missing for material %s" % name)
        principled.inputs["Base Color"].default_value = PALETTE[name]
        principled.inputs["Roughness"].default_value = 0.88
        m.roughness = 0.88
        MATS[name] = m
    return MATS[name]


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def cube(name, loc, size, material, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new("SoftEdges", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.rotation_euler = rot
    o.data.materials.append(mat(material))
    return o


def cone(name, loc, radius1, radius2, depth, material, verts=8, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius1, radius2=radius2, depth=depth, location=loc)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = rot
    o.data.materials.append(mat(material))
    return o


def cylinder(name, loc, radius, depth, material, verts=10, rot=(0, 0, 0)):
    return cone(name, loc, radius, radius, depth, material, verts, rot)


def blob(name, loc, size, material, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat(material))
    return o


def roof(name, z, width, depth, material, pitch=0.48):
    for x, angle in [(-width * 0.25, -pitch), (width * 0.25, pitch)]:
        cube(name, (x, 0, z), (width * 0.58, depth * 1.1, 0.20), material, 0.04, rot=(0, angle, 0))


def export(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_materials="EXPORT", export_apply=True)
    print("EXPORTED", os.path.relpath(path, ROOT))


def triangle_count():
    total = 0
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            total += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return total


# --- Refined-modelling helpers (build_lowpoly_refined.py) -------------------

import bmesh  # noqa: E402
import random  # noqa: E402


def flat_poly(name, points, y, thickness, material, plane="xz"):
    """An extruded 2D outline. `points` are (a, b) pairs in the plane (x, z)
    for plane="xz" (a sign face, a gable) or (x, y) for plane="xy" (flat on
    the ground); the outline is extruded `thickness` along the third axis
    starting at `y`. Concave outlines are fine (arrows, figures)."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()

    def point(a, b, c):
        if plane == "xz":
            return (a, c, b)
        if plane == "yz":
            return (c, a, b)
        return (a, b, c)

    front = [bm.verts.new(point(a, b, y)) for a, b in points]
    back = [bm.verts.new(point(a, b, y + thickness)) for a, b in points]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    count = len(points)
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new([front[i], front[j], back[j], back[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def circle_points(cx, cz, radius, sides=12, start=0.0):
    return [(cx + math.cos(start + i * math.tau / sides) * radius, cz + math.sin(start + i * math.tau / sides) * radius) for i in range(sides)]


def jitter(obj, amount, seed, keep_bottom=None):
    """Nudges every vertex by up to `amount` (deterministic per seed). Shared
    vertices move together, so the mesh never cracks. Vertices at or below
    `keep_bottom` (object-local z) stay put, so a crown or rock keeps a clean
    base."""
    rng = random.Random(seed)
    for v in obj.data.vertices:
        if keep_bottom is not None and v.co.z <= keep_bottom + 1e-4:
            continue
        v.co.x += rng.uniform(-amount, amount)
        v.co.y += rng.uniform(-amount, amount)
        v.co.z += rng.uniform(-amount, amount)
    obj.data.update()
    return obj


def squash_bottom(obj, floor_z):
    """Flattens everything below `floor_z` (object-local) onto it."""
    for v in obj.data.vertices:
        if v.co.z < floor_z:
            v.co.z = floor_z
    obj.data.update()
    return obj


def gable_roof(name, wall_top, width, depth, pitch, material, gable_material, overhang=0.35, thickness=0.18, ridge_material=None):
    """A closed gable roof: two slabs with eaves overhang, a ridge cap, and
    solid triangular gable walls front and back (the old roof left them
    open). Width runs along X, the ridge along Y."""
    rise = (width / 2.0) * math.tan(pitch)
    ridge_z = wall_top + rise
    half_run = width / 2.0 + overhang
    eave_z = wall_top - overhang * math.tan(pitch)
    length = math.hypot(half_run, ridge_z - eave_z)
    for side in (-1.0, 1.0):
        cx = side * half_run / 2.0
        cz = (ridge_z + eave_z) / 2.0
        normal = (side * math.sin(pitch), math.cos(pitch))
        cube(name, (cx + normal[0] * thickness / 2.0, 0.0, cz + normal[1] * thickness / 2.0),
             (length + thickness * 0.5, depth + overhang * 2.0, thickness), material, 0.02, rot=(0, side * pitch, 0))
    cube(name + "Ridge", (0.0, 0.0, ridge_z + thickness * 0.9), (0.22, depth + overhang * 2.0 + 0.04, 0.16), ridge_material or material, 0.02)
    for y, t in ((depth / 2.0 - 0.02, 0.06), (-depth / 2.0 - 0.04, 0.06)):
        flat_poly(name + "Gable", [(-width / 2.0, wall_top), (width / 2.0, wall_top), (0.0, ridge_z)], y, t, gable_material)
    return ridge_z


def slab(name, p0, p1, depth, thickness, material, y=0.0, outward=1.0):
    """A board from (x0, z0) to (x1, z1) in the XZ plane, `depth` long along
    Y, lying on the side `outward` points to (roof slabs sit on top of the
    line, not centred on it)."""
    dx, dz = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dz)
    angle = math.atan2(dz, dx)
    nx, nz = -math.sin(angle) * outward, math.cos(angle) * outward
    cx = (p0[0] + p1[0]) / 2.0 + nx * thickness / 2.0
    cz = (p0[1] + p1[1]) / 2.0 + nz * thickness / 2.0
    return cube(name, (cx, y, cz), (length, depth, thickness), material, 0.015, rot=(0, -angle, 0))


def objects_since(before):
    return [o for o in bpy.context.scene.objects if o.name not in before]


def move_new(before, dx=0.0, dy=0.0, dz=0.0):
    for o in objects_since(before):
        o.location.x += dx
        o.location.y += dy
        o.location.z += dz
