import bpy
import math
from mathutils import Vector

# Clean scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, rough=0.72):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = next((node for node in m.node_tree.nodes if node.type == 'BSDF_PRINCIPLED'), None)
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = rough
    return m

skin = material('Piel cálida', (0.73, 0.43, 0.31))
blue = material('Camiseta azul', (0.035, 0.18, 0.55))
brown = material('Pantalón marrón', (0.25, 0.10, 0.045))
shoe = material('Zapatos', (0.10, 0.035, 0.018))
eye = material('Ojos', (0.035, 0.012, 0.008))
mouthmat = material('Boca', (0.18, 0.045, 0.025))
floor = material('Fondo', (0.84, 0.84, 0.82))

def smooth(obj):
    for p in obj.data.polygons: p.use_smooth = True

def uv(name, loc, scale, mat, seg=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat); smooth(o); return o

def cube(name, loc, scale, mat, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    if bevel:
        mod=o.modifiers.new('Bordes suaves','BEVEL'); mod.width=bevel; mod.segments=2
    return o

def cyl_between(name, a, b, radius, mat, vertices=10):
    a,b=Vector(a),Vector(b); d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length, location=(a+b)/2)
    o=bpy.context.object; o.name=name; o.data.materials.append(mat)
    o.rotation_mode='QUATERNION'; o.rotation_quaternion=Vector((0,0,1)).rotation_difference(d.normalized())
    return o

# feet on ground, character centered around z=3
cube('Zapato izquierdo', (-0.46, -0.05, .22), (.36,.48,.20), shoe, .12)
cube('Zapato derecho', ( .46, -0.05, .22), (.36,.48,.20), shoe, .12)
cyl_between('Pierna izquierda', (-.46,0,.42), (-.46,0,1.30), .24, skin, 10)
cyl_between('Pierna derecha', (.46,0,.42), (.46,0,1.30), .24, skin, 10)

# shorts: two legs and central bridge
cube('Pantalón corto izquierdo', (-.43,0,1.48), (.38,.37,.42), brown, .10)
cube('Pantalón corto derecho', (.43,0,1.48), (.38,.37,.42), brown, .10)
cube('Cintura pantalón', (0,0,1.77), (.82,.37,.22), brown, .09)

# rounded blocky t-shirt
torso = cube('Camiseta', (0,0,2.47), (.88,.42,.77), blue, .16)
# sleeves, arms in T pose
cube('Manga izquierda', (-1.08,0,2.89), (.28,.43,.31), blue, .12)
cube('Manga derecha', (1.08,0,2.89), (.28,.43,.31), blue, .12)
cyl_between('Brazo izquierdo', (-1.28,0,2.89), (-2.35,0,2.89), .19, skin, 10)
cyl_between('Brazo derecho', (1.28,0,2.89), (2.35,0,2.89), .19, skin, 10)

# simplified hands and thumbs
uv('Mano izquierda', (-2.48,0,2.89), (.26,.20,.16), skin, 10, 6)
uv('Mano derecha', (2.48,0,2.89), (.26,.20,.16), skin, 10, 6)
cyl_between('Pulgar izquierdo', (-2.43,-.02,2.83), (-2.60,-.12,2.70), .07, skin, 8)
cyl_between('Pulgar derecho', (2.43,-.02,2.83), (2.60,-.12,2.70), .07, skin, 8)

# neck and faceted head
cyl_between('Cuello', (0,0,3.20), (0,0,3.38), .25, skin, 12)
head=uv('Cabeza', (0,-.01,3.92), (.66,.55,.70), skin, 16, 9)

# face (front is y=-)
uv('Ojo izquierdo', (-.23,-.53,4.03), (.075,.045,.09), eye, 12, 6)
uv('Ojo derecho', (.23,-.53,4.03), (.075,.045,.09), eye, 12, 6)
# subtle nose
uv('Nariz', (0,-.56,3.88), (.06,.045,.05), skin, 10, 5)
# mouth as shallow dark rounded bar
cube('Boca', (0,-.555,3.70), (.16,.025,.025), mouthmat, .025)

# floor
bpy.ops.mesh.primitive_plane_add(size=30, location=(0,0,0))
pl=bpy.context.object; pl.name='Suelo'; pl.data.materials.append(floor)

# Camera
bpy.ops.object.camera_add(location=(7,-13,6.0))
cam=bpy.context.object; cam.name='Cámara'; bpy.context.scene.camera=cam
def point(obj, target): obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
point(cam,(0,0,2.3)); cam.data.lens=52

# Lighting
bpy.ops.object.light_add(type='AREA', location=( -4,-5,8)); key=bpy.context.object; key.name='Luz principal'; key.data.energy=900; key.data.shape='DISK'; key.data.size=5; point(key,(0,0,2.4))
bpy.ops.object.light_add(type='AREA', location=(4,-2,5)); fill=bpy.context.object; fill.name='Luz relleno'; fill.data.energy=500; fill.data.size=4; point(fill,(0,0,2.5))
bpy.ops.object.light_add(type='AREA', location=(0,4,7)); rim=bpy.context.object; rim.name='Contraluz'; rim.data.energy=650; rim.data.size=3; point(rim,(0,0,2.8))

scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=720; scene.render.resolution_y=720; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.filepath=r'D:\Programas\Utilities\Proyectos\Prometeus\personaje_lowpoly.png'
scene.world.color=(0.78,0.78,0.78)
scene.view_settings.look='AgX - Medium High Contrast'
bpy.ops.wm.save_as_mainfile(filepath=r'D:\Programas\Utilities\Proyectos\Prometeus\personaje_lowpoly.blend')
bpy.ops.render.render(write_still=True)
