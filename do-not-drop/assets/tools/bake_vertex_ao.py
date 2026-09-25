"""Bakes ambient occlusion into the vertex colours of exported GLBs
(tareas de Nacho N-308.1, 2026-09-24).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/bake_vertex_ao.py -- \
        [--out DIR] model.glb [model.glb ...]

GL Compatibility has no SSAO, so the darkening where surfaces meet (a wall
into the ground, an eave over a wall, a wheel arch) is baked instead: each
GLB is imported, every face corner casts RAYS rays over its hemisphere
against the whole model and the ground under it, and the share that hits
something within DISTANCE darkens it -- softened, never darker than FLOOR
and only STRENGTH of the way. The model goes back out with that colour;
Godot's glTF importer multiplies the material colour by COLOR_0
(LowpolyMaterials keeps it).

Not Cycles' AO bake: these models are boxes pushed into each other, so many
corners sit inside another piece (a roof slab's top edge inside the ridge
cap), and a buried corner reads as black and smears over its whole face --
a roof open to the sky came out grey. Here a ray that starts inside a piece
hits the back of a face, and is thrown away instead of counted.

Run it again after rebuilding a model with its build_*.py script: those
export without AO. --out writes the results to another folder (for trying
it out) instead of over the originals.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

DISTANCE = 1.2      # metres an occluder counts from
RAYS = 96
STRENGTH = 0.75     # 1 = the raw occlusion, 0 = no AO at all
FLOOR = 0.45        # darkest a corner may get
NUDGE = 0.01        # off the face, and toward its middle, before casting
## Faces are cut until no edge is longer than this (world metres), so the
## darkening hugs the ground or the eave instead of greying a whole wall --
## a wall has only four corners to carry it otherwise.
SUBDIVIDE = 0.6


def args():
    after = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = None
    paths = []
    index = 0
    while index < len(after):
        if after[index] == "--out":
            out = after[index + 1]
            index += 2
            continue
        paths.append(after[index])
        index += 1
    return out, paths


def hemisphere(count):
    """Cosine-weighted directions around +Z (a Fibonacci spiral): the same
    set for every corner, turned onto its normal."""
    directions = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for index in range(count):
        radius = math.sqrt((index + 0.5) / count)
        angle = index * golden
        directions.append(Vector((math.cos(angle) * radius, math.sin(angle) * radius, math.sqrt(max(0.0, 1.0 - radius * radius)))))
    return directions


def occlusion(tree, ground, origin, normal, directions):
    turn = normal.to_track_quat("Z", "Y")
    hits = 0.0
    valid = 0
    for local in directions:
        direction = turn @ local
        hit, hit_normal, _index, distance = tree.ray_cast(origin, direction, DISTANCE)
        if hit is not None and hit_normal.dot(direction) > 0.0:
            continue  # started inside a piece: says nothing about this corner
        valid += 1
        if hit is None and direction.z < -1e-4:
            reach = (ground - origin.z) / direction.z
            if reach < DISTANCE:
                distance = reach
                hit = True
        if hit is not None:
            hits += 1.0 - distance / DISTANCE * 0.5
    return 1.0 if valid == 0 else 1.0 - hits / valid


def subdivide(obj):
    """Halves every edge longer than SUBDIVIDE, over and over: faces stay
    flat and keep their UVs, they just get more corners."""
    scale = max(obj.matrix_world.to_scale())
    part = bmesh.new()
    part.from_mesh(obj.data)
    for _round in range(6):
        long_edges = [e for e in part.edges if e.calc_length() * scale > SUBDIVIDE]
        if not long_edges:
            break
        bmesh.ops.subdivide_edges(part, edges=long_edges, cuts=1, use_grid_fill=True)
    part.to_mesh(obj.data)
    part.free()


def bake(path, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    scene = bpy.context.scene
    meshes = [o for o in scene.objects if o.type == "MESH"]
    if not meshes:
        print("SKIP (no mesh)", path)
        return
    for obj in meshes:
        subdivide(obj)
    # Everything in world space, in one tree.
    whole = bmesh.new()
    for obj in meshes:
        part = bmesh.new()
        part.from_mesh(obj.data)
        part.transform(obj.matrix_world)
        scratch = bpy.data.meshes.new("scratch")
        part.to_mesh(scratch)
        whole.from_mesh(scratch)
        bpy.data.meshes.remove(scratch)
        part.free()
    tree = BVHTree.FromBMesh(whole)
    ground = min(v.co.z for v in whole.verts)
    whole.free()
    directions = hemisphere(RAYS)
    darkest = 1.0
    for obj in meshes:
        mesh = obj.data
        colours = mesh.color_attributes.get("AO") or mesh.color_attributes.new("AO", "BYTE_COLOR", "CORNER")
        mesh.color_attributes.active_color = colours
        world = obj.matrix_world
        rotate = world.to_3x3().inverted().transposed()
        # Corners that share a vertex and face the same way are one point on
        # the same surface: averaged, so the sampling noise doesn't draw
        # triangles across a wall, while hard edges stay hard.
        shared = {}
        raws = {}
        for polygon in mesh.polygons:
            normal = (rotate @ polygon.normal).normalized()
            middle = world @ polygon.center
            for loop_index in polygon.loop_indices:
                vertex = mesh.loops[loop_index].vertex_index
                corner = world @ mesh.vertices[vertex].co
                origin = corner + (middle - corner).normalized() * NUDGE + normal * NUDGE
                raws[loop_index] = occlusion(tree, ground, origin, normal, directions)
                key = (vertex, round(normal.x, 2), round(normal.y, 2), round(normal.z, 2))
                shared.setdefault(key, []).append(loop_index)
        for loops in shared.values():
            raw = sum(raws[index] for index in loops) / len(loops)
            value = max(FLOOR, 1.0 - STRENGTH * (1.0 - raw))
            darkest = min(darkest, value)
            for index in loops:
                colours.data[index].color = (value, value, value, 1.0)
    target = os.path.join(out_dir, os.path.basename(path)) if out_dir else path
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=target, export_format="GLB", use_selection=True,
                              export_materials="EXPORT", export_apply=True,
                              export_vertex_color="ACTIVE")
    print("BAKED %s darkest %.2f -> %s" % (os.path.basename(path), darkest, target))


if __name__ == "__main__":
    out_dir, paths = args()
    for glb in paths:
        bake(os.path.abspath(glb), out_dir)
