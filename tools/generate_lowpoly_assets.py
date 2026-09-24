"""Generates the missing low-poly gameplay props as separate GLB files.
Run with Blender in background mode; meshes use flat shading and simple,
readable silhouettes intended for Godot's GL Compatibility renderer.
"""
import bpy
import math
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "do-not-drop", "assets", "models"))


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def mat(name, color):
    value = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1)
    value.use_nodes = True
    value.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
    value.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = .82
    return value


def box(name, loc, scale, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = [x * .5 for x in scale]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if bevel:
        mod = obj.modifiers.new("EdgeBevel", "BEVEL")
        mod.width, mod.segments = bevel, 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def cyl(name, loc, radius, depth, material, rot=(0, 0, 0), vertices=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def export(relative):
    path = os.path.join(ROOT, relative)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_materials="EXPORT")


def vehicle(name, kind, color):
    clear()
    paint, dark, glass, chrome = mat("paint", color), mat("tire", (.045, .055, .06)), mat("glass", (.18,.34,.39)), mat("metal", (.55,.59,.6))
    if kind == "sedan":
        box("Body", (0, .62, 0), (2.05,.75,4.3), paint, .12)
        box("Cabin", (0, 1.18, -.15), (1.78,.72,2.15), paint, .12)
        for x in (-.94,.94):
            for z in (-1.4,1.38): cyl("Wheel", (x,.42,z), .42,.25,dark,(0,math.pi/2,0),12); cyl("Rim", (x*1.01,.42,z), .22,.27,chrome,(0,math.pi/2,0),10)
    elif kind == "van":
        box("CargoBody", (0,1.05,.25), (2.35,2.1,4.8), paint, .1)
        box("Cab", (0,.85,-1.75), (2.25,1.65,1.45), paint, .13)
        for x in (-1.08,1.08):
            for z in (-1.55,1.55): cyl("Wheel",(x,.43,z),.43,.27,dark,(0,math.pi/2,0),12); cyl("Rim",(x*1.01,.43,z),.22,.29,chrome,(0,math.pi/2,0),10)
    else:
        box("Engine", (0,1.0,-.8), (1.7,1.2,1.8), paint, .08); box("Rear", (0,.74,1.15),(1.55,.75,1.8),paint,.08)
        cyl("Exhaust", (.68,1.85,.55),.12,1.25,dark,vertices=8)
        for x in (-1.0,1.0):
            cyl("RearWheel",(x,.52,1.25),.62,.32,dark,(0,math.pi/2,0),12); cyl("FrontWheel",(x,.42,-1.35),.38,.28,dark,(0,math.pi/2,0),10)
    for x in (-.58,.58): box("Window", (x,1.28,-1.98 if kind=="van" else -.35), (.64,.42,.035),glass)
    box("Bumper",(0,.42,-2.2 if kind=="sedan" else -2.42),(2.12,.18,.16),chrome)
    export("vehicles/" + name + ".glb")


def phone():
    clear(); dark=mat("phone_dark",(.035,.05,.065)); screen=mat("screen",(.12,.55,.64)); trim=mat("trim",(.62,.68,.7))
    box("PhoneBody",(0,0,0),(0.72,.12,1.42),dark,.08); box("Screen",(0,-.07,.03),(.57,.018,.92),screen,.025)
    cyl("Camera",(.2,-.08,-.48),.065,.024,trim,(math.pi/2,0,0),10); cyl("Camera",(.04,-.08,-.48),.065,.024,trim,(math.pi/2,0,0),10)
    export("props/handheld/sm_prop_phone_refined.glb")


def lamp():
    clear(); metal=mat("lamp_metal",(.16,.22,.24)); glow=mat("lamp_glass",(.95,.75,.3))
    cyl("Pole",(0,2.3,0),.12,4.6,metal,vertices=8); cyl("Base",(0,.12,0),.35,.24,metal,vertices=10)
    box("Arm",(.48,4.35,0),(.9,.1,.1),metal); cyl("Lantern",(.92,4.08,0),.22,.42,glow,vertices=8)
    export("environment/props/sm_env_prop_street_lamp_refined.glb")


phone(); lamp()
vehicle("sm_vehicle_parked_sedan_refined", "sedan", (.24,.38,.62))
vehicle("sm_vehicle_competitor_van", "van", (.83,.38,.12))
vehicle("sm_vehicle_tractor", "tractor", (.32,.55,.19))
