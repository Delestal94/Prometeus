"""Product icons for the UI (expansion D-1845), rendered from the product models in Blender's background mode:

    blender --background --python do-not-drop/assets/tools/render_product_icons.py

For every assets/models/products/sm_product_<id>.glb: a clean scene, the model imported, an orthographic camera at
a three-quarter view framing its bounds with a margin, a sun and soft ambient light, Workbench at SIZE x SIZE on a
transparent background. Written to assets/ui/icons/products/icon_product_<id>.png. No window opens.
"""
import glob
import math
import os

import bpy
from mathutils import Vector

ASSETS = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ASSETS, "models", "products")
OUT = os.path.join(ASSETS, "ui", "icons", "products")
SIZE = 128
MARGIN = 1.18


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    engines = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_WORKBENCH" if "BLENDER_WORKBENCH" in engines else engines[0]
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = False
    shading.show_cavity = True
    return scene


def render(path):
    product_id = os.path.basename(path)[len("sm_product_"):-len(".glb")]
    scene = reset()
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in scene.objects if o.type == "MESH" and not o.name.endswith("-colonly")]
    for o in scene.objects:
        if o.name.endswith("-colonly"):
            o.hide_render = True
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    centre = (low + high) / 2
    radius = max((high - low).length / 2, 0.01)
    camera_data = bpy.data.cameras.new("IconCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = radius * 2 * MARGIN
    camera = bpy.data.objects.new("IconCamera", camera_data)
    scene.collection.objects.link(camera)
    direction = Vector((math.cos(math.radians(-50)), math.sin(math.radians(-50)), 0.6)).normalized()
    camera.location = centre + direction * radius * 6
    camera.rotation_euler = (centre - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.clip_end = radius * 20
    scene.camera = camera
    scene.render.filepath = os.path.join(OUT, "icon_product_%s.png" % product_id)
    bpy.ops.render.render(write_still=True)
    print("ICON", product_id)


os.makedirs(OUT, exist_ok=True)
for model in sorted(glob.glob(os.path.join(SRC, "sm_product_*.glb"))):
    render(model)
