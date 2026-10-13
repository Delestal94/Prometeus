"""Build the editable Blender counterpart of the S-311.38 Godot render.

blender --background --factory-startup --python-exit-code 1 --python art/gel_character/build_reference_scene.py
"""
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


HERE = Path(__file__).resolve().parent
SOURCE = HERE / "gel_body.blend"
SCENE = HERE / "gel_reference.blend"
OUTPUT = HERE / "review_bloque_e/s311_38_blender_reference.png"
WIDTH, HEIGHT = 832, 1248
CAMERA_DISTANCE_M = 4.0
CAMERA_FOV_DEGREES = 30.9
CAMERA_TARGET = Vector((0.0, 0.0, 0.813))
POSE_DEGREES = {"upper_arm": 100.0, "forearm": -25.0, "hand": 20.0}


def rotate_at_head(rig, name, degrees, sign):
    bone = rig.pose.bones[name]
    pivot = bone.head.copy()
    bone.matrix = (Matrix.Translation(pivot)
                   @ Matrix.Rotation(math.radians(degrees) * sign, 4, "Y")
                   @ Matrix.Translation(-pivot) @ bone.matrix)


def gel_material():
    material = bpy.data.materials.get("ReferenceMilkyGel") or bpy.data.materials.new("ReferenceMilkyGel")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    surface = nodes.new("ShaderNodeBsdfPrincipled")
    surface.name = "MilkyGelSurface"
    inputs = surface.inputs
    inputs["Base Color"].default_value = (0.58, 0.58, 0.78, 1.0)
    inputs["Roughness"].default_value = 0.16
    if "IOR" in inputs:
        inputs["IOR"].default_value = 1.33
    if "Transmission Weight" in inputs:
        inputs["Transmission Weight"].default_value = 0.62
    if "Coat Weight" in inputs:
        inputs["Coat Weight"].default_value = 0.22
    if "Subsurface Weight" in inputs:
        inputs["Subsurface Weight"].default_value = 0.08
    material.node_tree.links.new(surface.outputs["BSDF"], output.inputs["Surface"])
    return material


def look_at(camera, target):
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def add_area(name, location, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(light)
    light.location = location
    look_at(light, Vector((0.0, 0.0, 0.9)))
    return light


def build():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    rig = bpy.data.objects["GelSkeleton"]
    body = bpy.data.objects["GelBodyLOD0"]
    for obj in bpy.data.objects:
        obj.hide_render = obj != body and obj.type in {"MESH", "ARMATURE"}
    body.hide_render = False
    for key in body.data.shape_keys.key_blocks[1:]:
        key.value = 0.0
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    if rig.animation_data:
        rig.animation_data.action = None
    bpy.context.view_layer.update()
    for part, degrees in POSE_DEGREES.items():
        for side, sign in (("L", 1), ("R", -1)):
            rotate_at_head(rig, f"{part}.{side}", degrees, sign)
        bpy.context.view_layer.update()

    body.data.materials.clear()
    body.data.materials.append(gel_material())

    floor_material = bpy.data.materials.new("ReferenceWhiteFloor")
    floor_material.diffuse_color = (0.93, 0.93, 0.93, 1.0)
    floor_material.use_nodes = True
    floor_bsdf = floor_material.node_tree.nodes.get("Principled BSDF")
    floor_bsdf.inputs["Base Color"].default_value = (0.93, 0.93, 0.93, 1.0)
    floor_bsdf.inputs["Roughness"].default_value = 0.92
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    floor = bpy.context.object
    floor.name = "ReferenceWhiteFloor"
    floor.data.materials.append(floor_material)

    add_area("SoftKeyUpperLeft", (-2.5, -3.0, 4.0), 850.0, 3.0, (1.0, 0.94, 0.86))
    add_area("SoftFillRight", (2.5, -1.5, 2.2), 260.0, 3.5, (0.84, 0.89, 1.0))

    camera_data = bpy.data.cameras.new("ReferenceFrontCamera")
    camera_data.type = "PERSP"
    camera_data.sensor_fit = "VERTICAL"
    camera_data.sensor_height = 36.0
    camera_data.lens = (camera_data.sensor_height * 0.5) / math.tan(math.radians(CAMERA_FOV_DEGREES) * 0.5)
    camera = bpy.data.objects.new("ReferenceFrontCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0.0, -CAMERA_DISTANCE_M, CAMERA_TARGET.z)
    look_at(camera, CAMERA_TARGET)
    bpy.context.scene.camera = camera

    world = bpy.context.scene.world or bpy.data.worlds.new("ReferenceWhiteWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.65

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.filepath = str(OUTPUT)
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.look = "AgX - Medium High Contrast"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SCENE))
    bpy.ops.render.render(write_still=True)
    print(f"REFERENCE_SCENE_COMPLETE {SCENE} {OUTPUT}")


if __name__ == "__main__":
    build()
