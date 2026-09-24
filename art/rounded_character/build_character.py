"""Rebuild the rounded reference character in a clean Blender background process.
Run: blender --background --factory-startup --python build_character.py
Front = -Y, Z up; dimensions in metres. No external assets or add-ons required.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector, Quaternion

OUT = Path(__file__).resolve().parent
PI = math.pi

def enum(obj, prop, value):
    items = obj.bl_rna.properties[prop].enum_items
    valid = {i.identifier for i in items}
    if value not in valid:
        raise RuntimeError(f'{prop}: {value} not in {valid}')
    setattr(obj, prop, value)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.name = 'Personaje redondeado | estudio'
scene.unit_settings.system = 'METRIC'
scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 90

def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c

geo = collection('01 · PERSONAJE')
rigcol = collection('02 · RIG')
studio = collection('03 · ESTUDIO (no exportar)')
shapes = collection('04 · Formas de controles')
shapes.hide_render = True

def move(obj, col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    return obj

def activate(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o

def apply(o, mod):
    activate(o)
    bpy.ops.object.modifier_apply(modifier=mod.name)

def material(name, rgb, roughness=.68):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Roughness'].default_value = roughness
    return m

skin = material('01 | Piel · durazno', (.70,.405,.265), .57)
shader = next(n for n in skin.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
if 'Subsurface Weight' in shader.inputs:
    shader.inputs['Subsurface Weight'].default_value = .055
blue = material('02 | Camiseta · azul aciano', (.028,.092,.31))
edgeblue = material('03 | Ribete azul', (.026,.082,.265))
brown = material('04 | Short · caramelo', (.255,.118,.060))
cuffmat = material('05 | Dobladillo short', (.30,.148,.080))
leather = material('06 | Zapato · cacao', (.135,.062,.033), .76)
solemat = material('07 | Suela', (.085,.041,.025), .82)
groundmat = material('Estudio | marfil', (.86,.845,.81), .85)
meshes = []

def finish(o, name, mat):
    o.name = name
    move(o, geo)
    o.data.materials.clear()
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    activate(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o

def sphere(name, loc, scale, mat, segments=48, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=loc)
    o = bpy.context.object
    o.scale = scale
    return finish(o, name, mat)

def tube(name, rings, mat, axis='Z', n=48):
    # Every ring is (axis coordinate, centre 1, centre 2, radius 1, radius 2).
    verts, faces = [], []
    for pos,c1,c2,r1,r2 in rings:
        for j in range(n):
            a = 2*PI*j/n
            if axis == 'Z':
                verts.append((c1+r1*math.cos(a),c2+r2*math.sin(a),pos))
            else:
                verts.append((pos,c1+r1*math.cos(a),c2+r2*math.sin(a)))
    for i in range(len(rings)-1):
        for j in range(n):
            a=i*n+j; b=i*n+(j+1)%n
            faces.append((a,b,b+n,a+n))
    faces.append(tuple(reversed(range(n))))
    faces.append(tuple((len(rings)-1)*n+j for j in range(n)))
    me=bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces); me.update()
    o=bpy.data.objects.new(name,me); geo.objects.link(o)
    finish(o,name,mat)
    # Recalculate normals also handles left-hand X ring winding.
    activate(o)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    sub=o.modifiers.new('Superficie redondeada','SUBSURF')
    sub.levels=1
    apply(o,sub)
    return o

def union(parts, name, mat, voxel=.032):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    o=parts[0]
    mod=o.modifiers.new('Union organica','REMESH')
    enum(mod,'mode','VOXEL')
    mod.voxel_size=voxel
    mod.use_smooth_shade=True
    apply(o,mod)
    mod=o.modifiers.new('Relajar superficie','SMOOTH'); mod.factor=1.15; mod.iterations=5
    apply(o,mod)
    mod=o.modifiers.new('Densidad para animacion','DECIMATE'); mod.ratio=.48
    apply(o,mod)
    finish(o,name,mat)
    return o

def ringband(name, centre, radii, thickness, mat, axis='Z'):
    # Closed elliptical torus with consistent topology for hems and collar.
    verts, faces=[],[]
    for i in range(64):
        a=2*PI*i/64
        for j in range(10):
            b=2*PI*j/10
            r=thickness*math.cos(b)
            if axis=='Z':
                p=((radii[0]+r)*math.cos(a),(radii[1]+r)*math.sin(a),thickness*math.sin(b))
            else:
                p=(thickness*math.sin(b),(radii[0]+r)*math.cos(a),(radii[1]+r)*math.sin(a))
            verts.append(tuple(Vector(centre)+Vector(p)))
    for i in range(64):
        for j in range(10):
            faces.append((i*10+j,((i+1)%64)*10+j,((i+1)%64)*10+(j+1)%10,i*10+(j+1)%10))
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    o=bpy.data.objects.new(name,me); geo.objects.link(o)
    return finish(o,name,mat)

# Silhouette: large blank head, soft pear-shaped shirt, short legs and mitten hands.
head=sphere('Cabeza · lisa como referencia',(0,0,2.89),(.575,.525,.58),skin)
neck=sphere('Cuello',(0,0,2.34),(.23,.225,.21),skin,32,20)
shirt=tube('Camiseta',[
    (1.11,0,-.005,.76,.42),(1.125,0,-.005,.83,.465),
    (1.18,0,-.015,.865,.49),(1.30,0,-.025,.89,.505),
    (1.49,0,-.03,.88,.51),(1.72,0,-.015,.82,.475),
    (1.93,0,0,.76,.41),(2.16,0,0,.725,.355),
    (2.30,0,0,.86,.325),(2.40,0,0,.83,.30),
    (2.46,0,0,.66,.275),(2.47,0,0,.30,.23),(2.48,0,0,.275,.22)
],blue)
shirtparts=[shirt]
for s,side in [(1,'L'),(-1,'R')]:
    sleeve=tube('Manga',[(s*x,0,z,ry,rz) for x,z,ry,rz in [
        (.59,2.23,.305,.235),(.70,2.25,.30,.242),(.84,2.25,.29,.244),
        (.98,2.25,.274,.24),(1.015,2.25,.268,.235)]],blue,'X')
    shirtparts.append(sleeve)
shirt=union(shirtparts,'Camiseta · cuerpo y mangas',blue,.027)
collar=ringband('Cuello · costura',(0,0,2.455),(.268,.217),.018,edgeblue)
hem=ringband('Camiseta · dobladillo',(0,-.005,1.155),(.818,.465),.016,edgeblue)

shortparts=[sphere('Cadera short',(0,.015,1.065),(.835,.425,.38),brown)]
limbs={}; hems={}; shoes={}; soles={}; arms={}; thumbs={}
for s,side in [(1,'L'),(-1,'R')]:
    shortparts.append(tube('Pernera short',[
        (.58,s*.414,0,.348,.335),(.61,s*.414,0,.37,.35),
        (.75,s*.422,.01,.385,.365),(.94,s*.417,.015,.395,.382),
        (1.12,s*.40,.015,.397,.386),(1.25,s*.37,.015,.39,.38)
    ],brown))
    hems[side]=tube('Short · vuelta.'+side,[
        (.577,s*.414,0,.348,.335),(.586,s*.414,0,.365,.351),
        (.614,s*.414,0,.373,.359),(.659,s*.414,0,.373,.359),
        (.673,s*.414,0,.364,.35)
    ],cuffmat)
    limbs[side]=tube('Pierna.'+side,[
        (.18,s*.42,0,.183,.195),(.25,s*.42,-.005,.203,.21),
        (.35,s*.42,-.025,.221,.227),(.46,s*.42,-.048,.246,.245),
        (.56,s*.42,-.06,.263,.256),(.67,s*.42,-.043,.284,.282),
        (.79,s*.42,-.025,.31,.307),(.93,s*.42,0,.316,.32)
    ],skin)
    shoes[side]=tube('Zapato.'+side,[
        (.04,s*.42,-.105,.248,.365),(.06,s*.42,-.105,.261,.376),
        (.11,s*.42,-.105,.265,.38),(.18,s*.42,-.104,.25,.35),
        (.23,s*.42,-.07,.225,.28),(.26,s*.42,-.025,.207,.22),
        (.275,s*.42,-.008,.184,.192)
    ],leather)
    soles[side]=tube('Suela.'+side,[
        (.018,s*.42,-.103,.248,.361),(.032,s*.42,-.103,.260,.374),
        (.055,s*.42,-.103,.267,.38),(.077,s*.42,-.103,.26,.374)
    ],solemat)
    # Slight elbow bend toward +Y; wrist remains precisely at the hand root.
    arm=tube('Brazo',[(s*x,y,z,ry,rz) for x,y,z,ry,rz in [
        (.85,0,2.25,.224,.214),(.99,.012,2.25,.223,.211),
        (1.12,.03,2.25,.216,.197),(1.25,.05,2.25,.20,.18),
        (1.34,.047,2.25,.185,.166),(1.46,.033,2.25,.16,.145),
        (1.60,.016,2.25,.128,.12),(1.72,0,2.25,.098,.094),
        (1.79,-.005,2.25,.10,.095)
    ]],skin,'X',32)
    palm=sphere('Manopla',(s*1.83,-.005,2.25),(.19,.115,.096),skin,32,20)
    tip=sphere('Dedos juntos',(s*1.971,-.005,2.263),(.105,.088,.054),skin,24,16)
    thumb=sphere('Pulgar',(s*1.80,-.078,2.169),(.105,.074,.106),skin,24,16)
    arms[side]=union([arm,palm,tip,thumb],'Brazo y mano.'+side,skin,.014)

shorts=union(shortparts,'Short · pieza continua',brown,.027)

# Shape keys affect the belly only; clothing thickness and skeleton are preserved.
shirt.shape_key_add(name='Basis')
breath=shirt.shape_key_add(name='Respirar')
squash=shirt.shape_key_add(name='Barriga_blanda')
for v in shirt.data.vertices:
    x,y,z=v.co
    mask=math.exp(-((x/.62)**4)-(((z-1.52)/.42)**4))*max(0,min(1,(-y-.05)/.35))
    breath.data[v.index].co.y-=.072*mask
    breath.data[v.index].co.x+=x*.045*mask
    squash.data[v.index].co.y-=.10*mask
    squash.data[v.index].co.z-=.065*mask

# Skeleton: actual deform hierarchy, FK limbs, IK targets/poles and secondary belly.
armdata=bpy.data.armatures.new('Esqueleto humanoide')
rig=bpy.data.objects.new('RIG · personaje redondeado',armdata)
rigcol.objects.link(rig)
rig.show_in_front=True
activate(rig)
bpy.ops.object.mode_set(mode='EDIT')

def bone(name, head, tail, parent=None, deform=True, connected=False):
    b=armdata.edit_bones.new(name); b.head=head; b.tail=tail
    if parent: b.parent=armdata.edit_bones[parent]
    b.use_connect=connected; b.use_deform=deform
    return b

bone('CTRL_root',(0,0,0),(0,0,.3),deform=False)
bone('pelvis',(0,0,1.04),(0,0,1.34),'CTRL_root')
bone('spine',(0,0,1.34),(0,0,1.83),'pelvis',connected=True)
bone('chest',(0,0,1.83),(0,0,2.29),'spine',connected=True)
bone('neck',(0,0,2.29),(0,0,2.40),'chest',connected=True)
bone('head',(0,0,2.40),(0,0,3.26),'neck',connected=True)
bone('belly',(0,-.12,1.53),(0,-.43,1.53),'spine')
for s,side in [(1,'L'),(-1,'R')]:
    bone('clavicle.'+side,(s*.12,0,2.27),(s*.72,0,2.25),'chest')
    bone('upper_arm.'+side,(s*.72,0,2.25),(s*1.29,.05,2.25),'clavicle.'+side,connected=True)
    bone('forearm.'+side,(s*1.29,.05,2.25),(s*1.73,0,2.25),'upper_arm.'+side,connected=True)
    bone('hand.'+side,(s*1.73,0,2.25),(s*1.98,0,2.25),'forearm.'+side,connected=True)
    bone('thumb.'+side,(s*1.78,-.045,2.225),(s*1.82,-.092,2.125),'hand.'+side)
    bone('grip.'+side,(s*1.84,-.08,2.24),(s*1.84,-.20,2.24),'hand.'+side)
    bone('thigh.'+side,(s*.42,0,1.09),(s*.42,-.06,.555),'pelvis')
    bone('shin.'+side,(s*.42,-.06,.555),(s*.42,0,.245),'thigh.'+side,connected=True)
    bone('foot.'+side,(s*.42,0,.245),(s*.42,-.245,.13),'shin.'+side,connected=True)
    bone('toe.'+side,(s*.42,-.245,.13),(s*.42,-.42,.12),'foot.'+side,connected=True)
    bone('CTRL_hand_IK.'+side,(s*1.73,0,2.25),(s*1.98,0,2.25),'CTRL_root',False)
    bone('CTRL_elbow.'+side,(s*1.29,.90,2.25),(s*1.29,.90,2.43),'CTRL_root',False)
    bone('CTRL_foot_IK.'+side,(s*.42,0,.245),(s*.42,-.245,.13),'CTRL_root',False)
    bone('CTRL_knee.'+side,(s*.42,-.85,.555),(s*.42,-.85,.75),'CTRL_root',False)
bpy.ops.object.mode_set(mode='OBJECT')

ctrl=armdata.collections.new('CONTROLES · IK y cuerpo')
fk=armdata.collections.new('FK · articulaciones')
deform=armdata.collections.new('Deformacion · auxiliares')
for b in armdata.bones:
    coll=ctrl if b.name.startswith('CTRL') or b.name in ['pelvis','spine','chest','head','belly'] else fk
    if b.name.startswith('grip') or b.name.startswith('thumb') or b.name=='neck': coll=deform
    coll.assign(b)
    b.color.palette='THEME04' if b.name.endswith('.L') else ('THEME03' if b.name.endswith('.R') else 'THEME09')
fk.is_visible=False; deform.is_visible=False

def controlshape(name, style):
    if style=='circle':
        pts=[(math.cos(i*2*PI/48),0,math.sin(i*2*PI/48)) for i in range(48)]
        edges=[(i,(i+1)%48) for i in range(48)]
    else:
        pts=[(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]
        edges=[(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]
    me=bpy.data.meshes.new(name); me.from_pydata(pts,edges,[])
    o=bpy.data.objects.new(name,me); shapes.objects.link(o); o.hide_set(True); o.hide_render=True
    return o

circle=controlshape('WGT · aro','circle'); box=controlshape('WGT · caja','box')
for pb in rig.pose.bones:
    pb.rotation_mode='XYZ'
    if pb.name.startswith('CTRL') or pb.name in ['pelvis','spine','chest','head','belly']:
        pb.custom_shape=box if '_IK.' in pb.name or 'elbow' in pb.name or 'knee' in pb.name else circle
        pb.use_custom_shape_bone_size=False
        size=.11 if '_IK.' in pb.name else .055
        if pb.name in ['pelvis','spine','chest']: size=.64
        if pb.name=='head': size=.63
        if pb.name=='belly': size=.18
        if pb.name=='CTRL_root': size=1.0
        pb.custom_shape_scale_xyz=(size,size,size)
        if pb.name=='head':
            pb.custom_shape_translation=(0,.45,0)
            pb.custom_shape_rotation_euler=(PI/2,0,0)
rig['Instrucciones']='Pose Mode: mover CTRL_hand_IK / CTRL_foot_IK; polos CTRL_elbow / CTRL_knee. IK=0 activa FK. Ver LEEME.md.'
rig['altura_m']=3.47
rig['frente']='-Y en Blender; +Z en GLB/Godot'
for side in ['L','R']:
    for limb,end,control,pole in [
        ('brazo','forearm','hand','elbow'),('pierna','shin','foot','knee')]:
        prop=f'IK_{limb}.{side}'
        rig[prop]=1.0; rig.id_properties_ui(prop).update(min=0,max=1,description='1: IK; 0: FK. Cambiar en pose neutra, sin auto-snap.')
        pb=rig.pose.bones[end+'.'+side]
        c=pb.constraints.new('IK'); c.name='IK · '+limb
        c.target=rig; c.subtarget=f'CTRL_{control}_IK.{side}'
        c.pole_target=rig; c.pole_subtarget=f'CTRL_{pole}.{side}'
        c.chain_count=2; c.use_stretch=False
        d=c.driver_add('influence').driver
        d.expression='ik'; v=d.variables.new(); v.name='ik'; v.targets[0].id=rig; v.targets[0].data_path='["'+prop+'"]'
        # Calibrate pole angle against the actual rest elbow/knee, avoiding a rest-pose snap.
        rest=armdata.bones[end+'.'+side].head_local.copy()
        best=(1e9,0)
        for i in range(73):
            a=-PI+2*PI*i/72; c.pole_angle=a
            bpy.context.view_layer.update()
            err=(pb.head-rest).length
            if err<best[0]: best=(err,a)
        c.pole_angle=best[1]
        rotation=rig.pose.bones[control+'.'+side].constraints.new('COPY_ROTATION')
        rotation.target=rig; rotation.subtarget=f'CTRL_{control}_IK.{side}'
        enum(rotation,'target_space','POSE'); enum(rotation,'owner_space','POSE')
        d=rotation.driver_add('influence').driver; d.expression='ik'
        v=d.variables.new(); v.name='ik'; v.targets[0].id=rig; v.targets[0].data_path='["'+prop+'"]'

def smoothstep(a,b,x):
    t=max(0,min(1,(x-a)/(b-a))); return t*t*(3-2*t)

def blend(a,b,t):
    return {a:1-t,b:t}

def torso_weights(v):
    x,y,z=v; side='L' if x>0 else 'R'
    if z<1.4: w=blend('pelvis','spine',smoothstep(1.12,1.60,z))
    else: w=blend('spine','chest',smoothstep(1.56,2.14,z))
    sleeve=smoothstep(.60,1.02,abs(x))*smoothstep(1.85,2.18,z)
    w={k:a*(1-sleeve) for k,a in w.items()}; w['upper_arm.'+side]=sleeve
    belly=.60*math.exp(-((x/.62)**4)-(((z-1.53)/.38)**4))*smoothstep(.05,.4,-y)
    w={k:a*(1-belly) for k,a in w.items()}; w['belly']=belly
    return w

def short_weights(v):
    x,y,z=v; side='L' if x>0 else 'R'
    t=(1-smoothstep(.76,1.20,z))*smoothstep(.03,.29,abs(x))
    return blend('pelvis','thigh.'+side,t)

def arm_weights(v,side):
    x,y,z=v; x=abs(x)
    if x<1.47:
        return blend('upper_arm.'+side,'forearm.'+side,smoothstep(1.13,1.46,x))
    w=blend('forearm.'+side,'hand.'+side,smoothstep(1.60,1.80,x))
    t=smoothstep(2.225,2.12,z)*smoothstep(1.70,1.80,x)*.85
    return {**{k:a*(1-t) for k,a in w.items()},'thumb.'+side:t}

def bind(obj, weights):
    meshes.append(obj)
    for name in [b.name for b in armdata.bones if b.use_deform]: obj.vertex_groups.new(name=name)
    for v in obj.data.vertices:
        w=weights(v.co) if callable(weights) else {weights:1}
        w={k:a for k,a in w.items() if a>.0001}
        # Four influences per vertex for predictable glTF skinning.
        w=dict(sorted(w.items(),key=lambda p:-p[1])[:4]); total=sum(w.values())
        for k,a in w.items(): obj.vertex_groups[k].add([v.index],a/total,'REPLACE')
    obj.parent=rig
    mod=obj.modifiers.new('Deformacion · esqueleto','ARMATURE'); mod.object=rig
    mod.use_deform_preserve_volume=False # Match glTF / Godot linear skinning.

bind(head,'head'); bind(neck,'neck'); bind(shirt,torso_weights)
bind(collar,'chest'); bind(hem,torso_weights); bind(shorts,short_weights)
for side in ['L','R']:
    bind(arms[side],lambda v,s=side:arm_weights(v,s))
    bind(hems[side],'thigh.'+side)
    bind(limbs[side],lambda v,s=side:blend('shin.'+s,'thigh.'+s,smoothstep(.43,.69,v.z)))
    bind(shoes[side],'foot.'+side); bind(soles[side],'foot.'+side)

# Demonstration animation: a restrained breathing loop, independent of limb IK.
for f,value,z in [(1,0,0),(23,.75,.014),(46,0,0),(68,.55,.011),(90,0,0)]:
    breath.value=value; breath.keyframe_insert('value',frame=f)
    pb=rig.pose.bones['belly']; pb.location.z=z; pb.keyframe_insert('location',frame=f,group='Barriga')
if rig.animation_data and rig.animation_data.action:
    rig.animation_data.action.name='Idle · respiracion'
if shirt.data.shape_keys.animation_data:
    shirt.data.shape_keys.animation_data.action.name='Idle · volumen barriga'
scene.frame_set(1)

# Seamless warm studio. Keep these objects out of the game export.
bpy.ops.mesh.primitive_plane_add(size=200)
floor=move(bpy.context.object,studio); floor.name='Suelo estudio'; floor.data.materials.append(groundmat)
def track(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
def area(name,loc,energy,size,color):
    data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.shape='DISK'; data.size=size; data.color=color
    o=bpy.data.objects.new(name,data); studio.objects.link(o); o.location=loc; track(o,(0,0,1.7))
area('Luz · ventana',(-3,-4.5,7),550,5,(1,.90,.81))
area('Luz · relleno',(4,-2,4.5),280,4,(.79,.87,1))
area('Luz · recorte',(0,3.3,5.5),500,3,(1,.93,.85))
world=bpy.data.worlds.new('Estudio suave'); world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND'); bg.inputs[0].default_value=(.78,.82,.9,1); bg.inputs[1].default_value=.32
scene.world=world
camdata=bpy.data.cameras.new('Camara'); cam=bpy.data.objects.new('Camara',camdata); studio.objects.link(cam)
cam.location=(4.4,-10,4.1); track(cam,(0,0,1.70)); camdata.type='ORTHO'; camdata.ortho_scale=4.95; scene.camera=cam
try: scene.render.engine='CYCLES'
except TypeError: pass
scene.cycles.samples=40
scene.cycles.use_denoising=True
scene.render.resolution_x=1400; scene.render.resolution_y=1400; scene.render.resolution_percentage=100
enum(scene.render.image_settings,'file_format','PNG')
# Factory color management is retained (dynamic OCIO enums are runtime-defined).

# Record measurable checks before saving/exporting.
bpy.context.view_layer.update()
report={'mesh_objects':len(meshes),'vertices':sum(len(o.data.vertices) for o in meshes),
        'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),
        'deform_bones':sum(b.use_deform for b in armdata.bones),'total_bones':len(armdata.bones),
        'unweighted_vertices':0,'max_weight_sum_error':0,'rest_joint_error':{}}
for o in meshes:
    for v in o.data.vertices:
        report['unweighted_vertices']+=int(not v.groups)
        report['max_weight_sum_error']=max(report['max_weight_sum_error'],abs(sum(g.weight for g in v.groups)-1))
for side in ['L','R']:
    for name in ['forearm','shin']:
        n=name+'.'+side
        report['rest_joint_error'][n]=(rig.pose.bones[n].head-armdata.bones[n].head_local).length
assert report['unweighted_vertices']==0
assert report['max_weight_sum_error']<1e-5
assert max(report['rest_joint_error'].values())<.015, report['rest_joint_error']
(OUT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')

# Export only the character. The GLB contains the evaluated skin and morph targets.
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active=rig
export_props=bpy.ops.export_scene.gltf.get_rna_type().properties
kwargs=dict(filepath=str(OUT/'personaje_redondeado.glb'),export_format='GLB',use_selection=True,
            export_animations=True,export_skins=True,export_morph=True,export_extras=True,
            export_nla_strips_merged_animation_name='Idle_Respiracion')
for key,val in [('export_def_bones',True),('export_animation_mode','SCENE'),('export_anim_scene_split_object',False),('export_frame_range',True),('export_force_sampling',True)]:
    if key in export_props:
        if export_props[key].type=='ENUM' and val not in {x.identifier for x in export_props[key].enum_items}: continue
        kwargs[key]=val
bpy.ops.export_scene.gltf(**kwargs)

# Useful starting view and embedded readme in the native Blender file.
readme=bpy.data.texts.new('LEEME · rig')
readme.write('PERSONAJE REDONDEADO\n\nSelecciona el rig y entra en Pose Mode.\n'
 'Mueve CTRL_hand_IK.L/R y CTRL_foot_IK.L/R.\n'
 'CTRL_elbow y CTRL_knee orientan la flexion.\n'
 'Rota pelvis, spine, chest, head; belly permite movimiento secundario manual.\n'
 'Propiedades personalizadas del rig: IK_brazo.L/R e IK_pierna.L/R, 1=IK, 0=FK.\n'
 'Para FK activa la coleccion de huesos FK. No hay auto-snap IK/FK.\n'
 'Camiseta: shape keys Respirar y Barriga_blanda.\n'
 'Timeline 1-90: respiracion de ejemplo. Frame 1: pose de reposo.\n'
 'Archivo GLB: mallas, materiales, skin, morphs y animacion horneada.\n'
 'Controles y constraints son propios de Blender.\n'
 'Ragdoll, limites fisicos, agarres y jiggle reactivo deben configurarse en Godot.\n'
 'La escena del juego existente no ha sido sustituida.\n')
activate(rig)
for obj in studio.objects: obj.hide_set(True)
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type=='VIEW_3D':
            sp=ar.spaces.active
            sp.region_3d.view_distance=5.8
            sp.region_3d.view_location=(0,0,1.73)
            sp.region_3d.view_rotation=Quaternion((1,0,0),PI/2)
            enum(sp.region_3d,'view_perspective','ORTHO')
            sp.clip_end=500
            enum(sp.shading,'type','MATERIAL')
            sp.overlay.show_floor=False
            sp.overlay.show_axis_x=False; sp.overlay.show_axis_y=False
            sp.overlay.show_ortho_grid=False; sp.overlay.show_extras=False
            sp.overlay.show_relationship_lines=False
            sp.region_3d.update()
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'personaje_redondeado.blend'))
scene.render.filepath=str(OUT/'preview_tres_cuartos.png')
bpy.ops.render.render(write_still=True)
cam.location=(0,-12,3.35); track(cam,(0,0,1.70)); camdata.ortho_scale=4.80
scene.render.filepath=str(OUT/'preview_frente.png')
bpy.ops.render.render(write_still=True)
print('CHARACTER_BUILD_COMPLETE',json.dumps(report))
