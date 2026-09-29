"""Build a neutral gel character on the game's existing humanoid rig.

Run with Blender in the background, opening the rounded character master .blend:
blender --background art/rounded_character/personaje_redondeado.blend \
    --python art/gel_character/build_gel_character.py

This is a candidate asset. It does not replace the current player until its
deformation and appearance have been reviewed in Godot.
"""
import bpy
import math
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "art" / "rounded_character"))
from animation_library import build, FPS, DURATIONS

rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and obj.parent == rig:
        bpy.data.objects.remove(obj, do_unlink=True)

gel = bpy.data.materials.new("GelOpalino")
gel.diffuse_color = (0.73, 0.77, 0.91, 1.0)
gel.use_nodes = True
shader = next(n for n in gel.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
shader.inputs["Base Color"].default_value = (0.73, 0.77, 0.91, 1.0)
shader.inputs["Roughness"].default_value = 0.16
shader.inputs["Metallic"].default_value = 0.0
if "Coat Weight" in shader.inputs:
    shader.inputs["Coat Weight"].default_value = 0.7
if "Coat Roughness" in shader.inputs:
    shader.inputs["Coat Roughness"].default_value = 0.08
if "Subsurface Weight" in shader.inputs:
    shader.inputs["Subsurface Weight"].default_value = 0.16
if "Transmission Weight" in shader.inputs:
    shader.inputs["Transmission Weight"].default_value = 0.08

ink = bpy.data.materials.new("RostroTinta")
ink.diffuse_color = (0.014, 0.018, 0.026, 1.0)
ink.use_nodes = True
ink.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = ink.diffuse_color

parts = []


def ellipsoid(name, center, radii, material, segments=48, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = radii
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


def limb(name, start, end, radius_a, radius_b):
    start, end = Vector(start), Vector(end)
    direction = end - start
    middle = (start + end) * 0.5
    obj = ellipsoid(name, middle, (radius_a, radius_b, direction.length * 0.61), gel, 32, 20)
    obj.rotation_euler = Vector((0, 0, 1)).rotation_difference(direction).to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


parts.append(ellipsoid("Gel · torso", (0, 0, 1.62), (.72, .53, .88), gel))
parts.append(ellipsoid("Gel · cuello", (0, 0, 2.33), (.31, .31, .32), gel))
parts.append(ellipsoid("Gel · cabeza", (0, -.015, 2.95), (.63, .59, .64), gel, 64, 40))
for side in (-1, 1):
    parts.append(limb("Gel · brazo", (side * .64, 0, 2.24), (side * 1.58, -.04, 1.48), .25, .25))
    parts.append(ellipsoid("Gel · mano", (side * 1.59, -.04, 1.48), (.24, .21, .28), gel))
    parts.append(limb("Gel · pierna", (side * .39, 0, 1.0), (side * .42, -.02, .28), .27, .27))
    parts.append(ellipsoid("Gel · pie", (side * .42, -.14, .22), (.31, .43, .20), gel))

# Weld the overlapping primitives into one continuous surface; separate pieces
# made the original prototype look like a stack of translucent balloons.
bpy.ops.object.select_all(action="DESELECT")
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
body = parts[0]
body.name = "GelBody"
body.data.remesh_voxel_size = 0.035
bpy.ops.object.voxel_remesh()
smooth = body.modifiers.new("Smooth gel silhouette", "SMOOTH")
smooth.factor = 1.6
smooth.iterations = 5
bpy.ops.object.modifier_apply(modifier=smooth.name)
for face in body.data.polygons:
    face.use_smooth = True

# Blender's heat weights produce gradual transitions at the shoulders, hips and
# neck. Region thresholds on a continuous mesh create visible torn seams.
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

# Minimal face, weighted to the head. Front is Blender -Y.
face_parts = [
    ellipsoid("GelEyeL", (-.22, -.575, 3.01), (.047, .022, .050), ink, 20, 12),
    ellipsoid("GelEyeR", (.22, -.575, 3.01), (.047, .022, .050), ink, 20, 12),
    ellipsoid("GelMouth", (0, -.614, 2.84), (.095, .016, .015), ink, 20, 12),
]
for obj in face_parts:
    group = obj.vertex_groups.new(name="head")
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.parent = rig
    mod = obj.modifiers.new("Face rig", "ARMATURE")
    mod.object = rig

bpy.context.scene.render.fps = FPS
bpy.context.view_layer.objects.active = rig
build(rig)
if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
rig.rotation_mode = "XYZ"
rig.rotation_euler = (0, 0, math.pi)
rig.scale = (.5, .5, .5)
rig.animation_data.action = bpy.data.actions["Idle"]
bpy.context.scene.frame_set(0)

HERE.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
for obj in [rig, body] + face_parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=str(HERE / "gel_character_candidate.glb"),
    export_format="GLB", use_selection=True, export_animations=True,
    export_skins=True, export_morph=False,
)

# Review render is deliberately opaque enough to read against any game scene.
for obj in bpy.data.objects:
    if obj.type == "MESH" and obj not in [body] + face_parts:
        obj.hide_render = True
camera = bpy.data.objects.get("Camara")
if camera is not None:
    camera.location = (4.2, 7.0, 3.5)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.65
    camera.rotation_euler = (Vector((0, 0, .90)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
bpy.context.scene.frame_set(0)
rig.animation_data.action = None
bpy.context.scene.render.engine = "CYCLES"
bpy.context.scene.cycles.samples = 24
bpy.context.scene.render.resolution_x = 800
bpy.context.scene.render.resolution_y = 900
bpy.context.scene.render.resolution_percentage = 100
bpy.context.scene.render.filepath = str(HERE / "gel_character_candidate.png")
bpy.ops.render.render(write_still=True)
print("GEL_CANDIDATE", len(body.data.vertices), str(HERE))
