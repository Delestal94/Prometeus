"""Deterministic, closed quad gel-body source. Run in a fresh background Blender.

blender --background --factory-startup --python art/gel_character/build_gel_body.py
The rounded modeling master is only read, never overwritten.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / 'do-not-drop/assets/models/characters/gel'
MORPHS = ('general_thickness', 'belly', 'chest', 'shoulders', 'hips',
          'arm_thickness', 'leg_thickness', 'hand_size', 'foot_size',
          'head_shape', 'neck_thickness')
JOINTS = ('pelvis', 'chest', 'neck', 'head') + tuple(
    n + '.' + s for s in 'LR' for n in
    ('upper_arm', 'forearm', 'hand', 'thumb', 'grip', 'thigh', 'shin', 'foot'))
LOD_LEVELS = (2, 1, 0)
BUDGETS = (6000, 2500, 800)
ARM_SHOULDER_X = .225
ARM_LENGTH_SCALE = 1.124


def arm_x(x):
    """Lengthen the arm centerline beyond its fixed shoulder anchor."""
    return x if x <= ARM_SHOULDER_X else ARM_SHOULDER_X+(x-ARM_SHOULDER_X)*ARM_LENGTH_SCALE


def measured_proportions(obj):
    vertices = [v.co for v in obj.data.vertices]
    head = [p for p in vertices if p.z > 1.32]
    waist = [p for p in vertices if .82 < p.z < .90]
    foot = [p for p in vertices if p.x > 0 and p.z < .14]
    sole = [p for p in foot if abs(p.z) < 1e-6]
    return {'height_m': max(p.z for p in vertices)-min(p.z for p in vertices),
            'head_diameter_m': max(p.x for p in head)-min(p.x for p in head),
            'arm_shoulder_to_hand_m': max(abs(p.x) for p in vertices)-ARM_SHOULDER_X,
            'torso_waist_width_m': max(p.x for p in waist)-min(p.x for p in waist),
            'foot_width_m': max(p.x for p in foot)-min(p.x for p in foot),
            'foot_forward_reach_m': -min(p.y for p in foot),
            'foot_depth_m': max(p.y for p in foot)-min(p.y for p in foot),
            'flat_sole_vertices': len(sole),
            'flat_sole_depth_m': max(p.y for p in sole)-min(p.y for p in sole)}


def make_body(level):
    """A tree Skin surface is sewn at every branch, then subdivided as quads."""
    if level == 0:
        # LOD2 optimizes the already faithful LOD1, never the authoring topology.
        # Collapsing skeleton branches before Skin loses the head and arm silhouette.
        obj = make_body(1)
        obj.name = 'GelBodyLOD2'
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        decimate = obj.modifiers.new('LOD2 surface error collapse', 'DECIMATE')
        # Flat soles have zero plane error, so unconstrained quadric collapse
        # can fold their boundary across neighboring sole triangles. Preserve
        # those existing vertices while spending the distant-LOD budget on the
        # curved surface; this changes simplification, not the source silhouette.
        sole = obj.vertex_groups.new(name='LOD2 flat sole protection')
        sole.add([v.index for v in obj.data.vertices if abs(v.co.z) < 1e-6], 1., 'REPLACE')
        decimate.vertex_group = sole.name
        decimate.invert_vertex_group = True
        decimate.vertex_group_factor = 1000.
        decimate.ratio = 794/sum(len(f.vertices)-2 for f in obj.data.polygons)
        decimate.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        obj.select_set(False)
        return obj
    coords, edges, radii = [], [], []
    def node(point, radius, parent=None):
        i = len(coords)
        coords.append(point)
        radii.append(radius)
        if parent is not None:
            edges.append((parent, i))
        return i
    pelvis = node((0, 0, .70), (.18, .135))
    belly = node((0, 0, .86), (.20, .145), pelvis)
    chest = node((0, 0, 1.09), (.20, .14), belly)
    neck = node((0, 0, 1.275), (.12, .105), chest)
    head = node((0, 0, 1.485), (.235, .235), neck)
    crown = node((0, 0, 1.57), (.20, .20), head)
    node((0, 0, 1.65), (.13, .13), crown)
    for s in (-1, 1):
        shoulder = node((s*.225, 0, 1.105), (.102, .092), chest)
        elbow = node((s*arm_x(.46), 0, 1.105), (.064, .063), shoulder)
        wrist = node((s*arm_x(.66), 0, 1.105), (.055, .056), elbow)
        hand = node((s*arm_x(.735), 0, 1.105), (.078, .073), wrist)
        node((s*arm_x(.82), 0, 1.105), (.060, .060), hand)
        thumb = node((s*arm_x(.735), -.025, 1.015), (.039, .038), hand)
        node((s*arm_x(.760), -.035, .965), (.031, .030), thumb)
        hip = node((s*.13, 0, .635), (.09, .086), pelvis)
        knee = node((s*.145, 0, .375), (.072, .075), hip)
        ankle = node((s*.145, 0, .16), (.065, .063), knee)
        heel = node((s*.145, -.025, .105), (.100, .145), ankle)
        node((s*.145, -.205, .10), (.085, .145), heel)
    mesh = bpy.data.meshes.new('GelQuadCage')
    mesh.from_pydata(coords, edges, [])
    obj = bpy.data.objects.new('GelBodyLOD'+str(2-level), mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    skin = obj.modifiers.new('Sewn branches', 'SKIN')
    skin.use_smooth_shade = True
    for v, r in zip(mesh.skin_vertices[0].data, radii):
        v.radius = r
    mesh.skin_vertices[0].data[pelvis].use_root = True
    bpy.ops.object.modifier_apply(modifier=skin.name)
    # Authoring LOD0 and LOD1 keep the sewn quad topology and joint loops.
    sub = obj.modifiers.new('Quad joint loops', 'SUBSURF')
    sub.levels = max(1, level)
    bpy.ops.object.modifier_apply(modifier=sub.name)
    # Preserve the neck junction while projecting the head cap onto a sphere.
    for v in obj.data.vertices:
        p = v.co
        if p.z > 1.32:
            d = p - Vector((0, 0, 1.485))
            target = Vector((0, 0, 1.485)) + d.normalized()*.235
            factor = min(1., (p.z-1.32)/.06)
            p[:] = p.lerp(target, factor)
        # A broad, genuinely flat sole, not a tangential sphere contact.
        if p.z < .08:
            p.z = .025
    low = min(v.co.z for v in obj.data.vertices)
    high = max(v.co.z for v in obj.data.vertices)
    scale = 1.74/(high-low)
    for v in obj.data.vertices:
        v.co *= scale
        v.co.z -= low*scale
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges), ('Skin branch did not close', level, len([e for e in bm.edges if not e.is_manifold]))
    assert all(len(f.verts) == 4 for f in bm.faces), 'Non-quad source'
    bm.to_mesh(obj.data)
    bm.free()
    for f in obj.data.polygons:
        f.use_smooth = True
    obj.select_set(False)
    return obj


def zones(p):
    x, y, z = p
    if z > 1.32:
        return 'head', (0., 0., 1.)
    if z > 1.21 and abs(x) < .15:
        return 'neck', (0., 1., 1.)
    if abs(x) > arm_x(.28) and z > .85:
        return ('hand', (1.,1.,1.)) if abs(x) > arm_x(.68) else ('arm', (1.,0.,0.))
    if z < .21:
        return 'foot', (1., 1., 0.)
    if z < .67:
        return 'leg', (0., 1., 0.)
    return 'torso', (1., 0., 1.)


def morph_delta(p, name):
    """Shape only: never translate a joint or change limb centerline length."""
    x, y, z = p
    def smooth(a, b, value):
        t = max(0., min(1., (value-a)/(b-a)))
        return t*t*(3-2*t)
    arm = smooth(arm_x(.22),arm_x(.40),abs(x))*smooth(.75,.95,z)
    leg = 1-smooth(.54,.76,z)
    head = smooth(1.25,1.36,z)
    hand = arm*smooth(arm_x(.62),arm_x(.74),abs(x))
    foot = 1-smooth(.14,.25,z)
    torso = (1-arm)*(1-leg)*(1-head)
    # Smoothly split the two leg centerlines through the crotch. A signed step
    # at x=0 folds center seam triangles even when each leg radius is positive.
    center = Vector((.145*math.tanh(x/.10)*leg, 0, z*(1-arm)+1.105*arm))
    amount = 0.
    if name == 'general_thickness':
        amount = .30*(1-head)
        center.x = center.x*(1-arm)+x*arm
    elif name == 'belly':
        amount = .18*torso*math.exp(-((z-.86)/.14)**2)
    elif name == 'chest':
        amount = .15*torso*math.exp(-((z-1.08)/.14)**2)
    elif name == 'shoulders':
        amount = .12*(1-head)*math.exp(-((abs(x)-arm_x(.23))/(.12*ARM_LENGTH_SCALE))**2)*math.exp(-((z-1.105)/.16)**2)
    elif name == 'hips':
        amount = .14*(1-arm)*math.exp(-((z-.67)/.12)**2)
    elif name == 'arm_thickness':
        amount = .18*arm*(1-hand)
        center.x = x
    elif name == 'leg_thickness':
        amount = .18*leg*(1-foot)
    elif name == 'hand_size':
        amount = .15*hand
        center = Vector((math.copysign(arm_x(.735), x), 0, 1.105))
    elif name == 'foot_size':
        amount = .15*foot
        center = Vector((math.copysign(.145, x), -.06, 0))
    elif name == 'head_shape':
        return Vector((-x*.08, -y*.08, (z-1.485)*.08))*head
    elif name == 'neck_thickness':
        amount = .15*math.exp(-((z-1.25)/.08)**2)*(1-arm)
    delta = (Vector(p)-center)*amount
    if name == 'foot_size':
        # Inner boot edges share the narrow reference stance. Fade their lateral
        # growth continuously toward the midline so +1 retains a real gap.
        delta.x *= smooth(0., .08, abs(x))
    return delta


def decorate(obj):
    obj.shape_key_add(name='Basis')
    for name in MORPHS:
        key = obj.shape_key_add(name=name)
        key.slider_min, key.slider_max = -1, 1
        for v, k in zip(obj.data.vertices, key.data):
            k.co = v.co + morph_delta(v.co, name)
    uv = obj.data.uv_layers.new(name='UVMap')
    grid = math.ceil(math.sqrt(len(obj.data.polygons)))
    for f in obj.data.polygons:
        col, row = f.index % grid, f.index // grid
        for loop, (u, v) in zip(f.loop_indices, ((.1,.1),(.9,.1),(.9,.9),(.1,.9))):
            uv.data[loop].uv = ((col+u)/grid, (row+v)/grid)
    color = obj.data.color_attributes.new(name='GelZone', type='FLOAT_COLOR', domain='POINT')
    for v, c in zip(obj.data.vertices, color.data):
        c.color = (*zones(v.co)[1], 1)
    obj.data.color_attributes.active_color = color
    mat = bpy.data.materials.get('GelBodyOpaque') or bpy.data.materials.new('GelBodyOpaque')
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (.73,.77,.91,1)
    bsdf.inputs['Roughness'].default_value = .24
    obj.data.materials.append(mat)


def anatomical_rest():
    bones = {
        'pelvis': ((0,0,.65),(0,0,.84),None),
        'chest': ((0,0,.84),(0,0,1.20),'pelvis'),
        'neck': ((0,0,1.20),(0,0,1.28),'chest'),
        'head': ((0,0,1.28),(0,0,1.69),'neck'),
    }
    for side, sign in (('L',1),('R',-1)):
        def p(x,y,z): return (sign*arm_x(x),y,z)
        for name, start, end, parent in (
            ('upper_arm',p(.225,0,1.105),p(.46,0,1.105),'chest'),
            ('forearm',p(.46,0,1.105),p(.66,0,1.105),'upper_arm.'+side),
            ('hand',p(.66,0,1.105),p(.82,0,1.105),'forearm.'+side),
            ('thumb',p(.735,-.025,1.015),p(.760,-.035,.965),'hand.'+side),
            ('grip',p(.735,-.04,1.105),p(.735,-.12,1.105),'hand.'+side),
            ('thigh',p(.13,0,.635),p(.145,0,.375),'pelvis'),
            ('shin',p(.145,0,.375),p(.145,0,.16),'thigh.'+side),
            ('foot',p(.145,0,.16),p(.145,-.14,.105),'shin.'+side)):
            bones[name+'.'+side] = (start,end,parent)
    return bones


def create_rig(source):
    bpy.ops.object.select_all(action='DESELECT')
    data = bpy.data.armatures.new('GelSkeleton')
    rig = bpy.data.objects.new('GelSkeleton', data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    rest = anatomical_rest()
    for name in JOINTS:
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = rest[name][:2]
        # Keep the source axes; copying Euler values across different axes is invalid.
        axis = source.data.bones[name].matrix_local.to_3x3().col[2]
        bone.align_roll(axis)
    for name in JOINTS:
        parent = rest[name][2]
        if parent:
            data.edit_bones[name].parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.animation_data_create()
    return rig


def assign_weights(obj, rig):
    """Inverse-distance capsule weights, smoothly blending the nearest four bones."""
    for name in JOINTS:
        obj.vertex_groups.new(name=name)
    for vertex in obj.data.vertices:
        p = vertex.co
        zone, _ = zones(p)
        side = 'L' if p.x >= 0 else 'R'
        candidates = {
            'head': ('head','neck'), 'neck': ('neck','head','chest'),
            'torso': ('pelvis','chest','neck','thigh.'+side),
            'arm': ('upper_arm.'+side,'forearm.'+side,'hand.'+side,'chest'),
            'hand': ('hand.'+side,'forearm.'+side,'thumb.'+side),
            'leg': ('thigh.'+side,'shin.'+side,'pelvis','foot.'+side),
            'foot': ('foot.'+side,'shin.'+side),
        }[zone]
        if zone == 'foot':
            # Preserve the planted sole and forward toe as a foot, rather than
            # bending the lower boot back toward the vertical shin capsule.
            shin_blend = max(0., min(1., (p.z-.14)/.07))*.25
            obj.vertex_groups['foot.'+side].add([vertex.index], 1-shin_blend, 'REPLACE')
            if shin_blend:
                obj.vertex_groups['shin.'+side].add([vertex.index], shin_blend, 'REPLACE')
            continue
        scores = []
        for name in candidates:
            b = rig.data.bones[name]
            a, d = b.head_local, b.tail_local-b.head_local
            t = max(0., min(1., (p-a).dot(d)/d.length_squared))
            distance = (p-a-d*t).length
            scores.append((name, 1./(distance+.012)**4))
        total = sum(weight for _, weight in scores)
        for name, weight in scores:
            obj.vertex_groups[name].add([vertex.index], weight/total, 'REPLACE')
    obj.parent = rig
    mod = obj.modifiers.new('Gel skin', 'ARMATURE')
    mod.object = rig


def bake_clips(source, target):
    sys.path.insert(0, str(ROOT/'art/rounded_character'))
    from animation_library import build, FPS, DURATIONS
    bpy.context.scene.render.fps = FPS
    bpy.context.view_layer.objects.active = source
    build(source)
    source_actions = {name: bpy.data.actions[name] for name in DURATIONS}
    for name, action in source_actions.items():
        assert tuple(action.frame_range) == (0, round(DURATIONS[name]*FPS))
        action.name = 'Source_'+name
    order = sorted(JOINTS, key=lambda n: len(target.data.bones[n].parent_recursive))
    max_rotation_error = 0.
    max_bone_length_error = 0.
    foot_ranges = {}
    for name, duration in DURATIONS.items():
        source.animation_data.action = source_actions[name]
        action = bpy.data.actions.new(name)
        target.animation_data.action = action
        action.use_fake_user = True
        last = round(duration*FPS)
        feet = []
        for frame in range(last+1):
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            poses = {}
            for bone_name in order:
                src = source.pose.bones[bone_name]
                dst = target.pose.bones[bone_name]
                delta = src.matrix.to_3x3().normalized() @ src.bone.matrix_local.to_3x3().inverted()
                rotation = (delta @ dst.bone.matrix_local.to_3x3()).to_quaternion()
                if dst.parent:
                    parent_rest = dst.parent.bone.matrix_local
                    location = (poses[dst.parent.name] @ parent_rest.inverted() @ dst.bone.matrix_local).translation
                else:
                    location = dst.bone.head_local + (src.matrix.translation-src.bone.head_local)*.5
                world = Matrix.LocRotScale(location, rotation, Vector((1,1,1)))
                poses[bone_name] = world
                dst.rotation_mode = 'QUATERNION'
                inherited = (poses[dst.parent.name] @ dst.parent.bone.matrix_local.inverted() @ dst.bone.matrix_local) if dst.parent else dst.bone.matrix_local
                dst.matrix_basis = inherited.inverted() @ world
                dst.keyframe_insert('location', frame=frame, group=bone_name)
                dst.keyframe_insert('rotation_quaternion', frame=frame, group=bone_name)
                dst.keyframe_insert('scale', frame=frame, group=bone_name)
            bpy.context.view_layer.update()
            for bone_name, wanted in poses.items():
                angle = target.pose.bones[bone_name].matrix.to_quaternion().rotation_difference(wanted.to_quaternion()).angle
                max_rotation_error = max(max_rotation_error, min(angle, math.tau-angle))
                pb = target.pose.bones[bone_name]
                max_bone_length_error = max(max_bone_length_error, abs((pb.tail-pb.head).length-pb.bone.length))
            feet.extend(target.pose.bones['foot.'+side].head.z for side in 'LR')
        action.frame_range = (0,last)
        action.use_frame_range = True
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = 'LINEAR'
        foot_ranges[name] = [min(feet), max(feet)]
    source.animation_data.action = None
    for action in source_actions.values():
        bpy.data.actions.remove(action)
    target.animation_data.action = bpy.data.actions['Idle']
    bpy.context.scene.frame_set(0)
    assert max_rotation_error < .001, max_rotation_error
    assert max_bone_length_error < .00001, max_bone_length_error
    return {'durations': DURATIONS, 'maximum_rotation_error_radians': max_rotation_error,
            'maximum_bone_length_error_m': max_bone_length_error,
            'foot_joint_height_ranges_m': foot_ranges,
            'foot_plant_status': 'joint ranges measured; deformed sole contact requires independent pose capture',
            'retarget': 'world rotation delta against source rest; target parent rest offset; root translation scale 0.5'}


def main():
    master = ROOT/'art/rounded_character/personaje_redondeado.blend'
    source_hash = hashlib.sha256(master.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(master))
    source = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    source.name = 'AuthorSkeleton35'
    for o in list(bpy.data.objects):
        if o != source:
            bpy.data.objects.remove(o, do_unlink=True)
    objects = [make_body(level) for level in LOD_LEVELS]
    for obj, budget in zip(objects, BUDGETS):
        tris = sum(len(f.vertices)-2 for f in obj.data.polygons)
        assert tris <= budget, (obj.name, tris, budget)
        decorate(obj)
    rig = create_rig(source)
    for obj in objects:
        assign_weights(obj, rig)
    animation_report = bake_clips(source, rig)
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    # Rotate in the rig node: Blender +Y exports Godot -Z, consistent with game.
    rig.rotation_euler.z = math.pi
    source.hide_render = source.hide_viewport = True
    spec = {'schema_version': 1, 'height_m': 1.74, 'head_diameter_m': 1.74/3.68,
            'arm_shoulder_to_hand_target_m': 1.74*.391,
            'arm_length_scale': ARM_LENGTH_SCALE,
            'proportion_tolerance_relative': .05,
            'proportion_measurement': 'head width above z=1.32; maximum hand x minus fixed shoulder x=0.225, base mesh meters',
            'morph_names': list(MORPHS), 'required_joints': list(JOINTS),
            'morph_range': [-1,1], 'lod_triangle_budgets': list(BUDGETS),
            'flaca': {'general_thickness': -1},
            'zones': {'head':[0,0,1], 'neck':[0,1,1], 'arm':[1,0,0], 'hand':[1,1,1],
                      'foot':[1,1,0], 'leg':[0,1,0], 'torso':[1,0,1]},
            'atlas': 'independent quad islands, 10% cell inset',
            'lod2_algorithm': 'quadric-error collapse of faithful LOD1 to target 794 triangles, flat sole vertices protected, triangulated; morphs evaluated after simplification',
            'foot_depth_design_m': .28, 'foot_depth_source': 'profile design, not inferred from frontal JPG',
            'reference_shape_targets': {'torso_waist_width_m': [.40,.43],
                'foot_width_m': .57*(1.74/3.68), 'neck_visible_height_m': .11*(1.74/3.68)},
            'reference_pose': 'static diagnostic A-pose, arms 15 degrees from vertical; eight animation clips preserve source rotations',
            'morph_amplitudes': dict(zip(MORPHS,(.30,.18,.15,.12,.14,.18,.18,.15,.15,.08,.15)))}
    OUT.mkdir(parents=True, exist_ok=True)
    report = {'source_sha256':source_hash, 'animations':animation_report, 'lods':[]}
    for index, obj in enumerate(objects):
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.export_scene.gltf(filepath=str(OUT/f'gel_body_lod{index}.glb'),
            export_format='GLB', use_selection=True, export_skins=True,
            export_morph=True, export_animations=True, export_animation_mode='ACTIONS',
            export_frame_range=False, export_force_sampling=True,
            export_anim_single_armature=True, export_apply=False,
            export_vertex_color='ACTIVE', export_extras=True)
        topology = [(tuple(v.co),) for v in obj.data.vertices]
        topology.extend(tuple(f.vertices) for f in obj.data.polygons)
        report['lods'].append({'name':obj.name,'vertices':len(obj.data.vertices),
            'measured_proportions': measured_proportions(obj),
            'triangles':sum(len(f.vertices)-2 for f in obj.data.polygons),
            'geometry_sha256':hashlib.sha256(repr(topology).encode()).hexdigest(),
            'morph_sha256':hashlib.sha256(repr([[tuple(v.co) for v in key.data] for key in obj.data.shape_keys.key_blocks]).encode()).hexdigest()})
    for obj in objects[1:]:
        obj.hide_render = True
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 360
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'gel_body.blend'))
    assert hashlib.sha256(master.read_bytes()).hexdigest() == source_hash
    (HERE/'gel_body_spec.json').write_text(json.dumps(spec,indent=2)+'\n',encoding='utf-8')
    (HERE/'gel_body_build_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('GEL_BODY_BUILD', json.dumps(report))


if __name__ == '__main__':
    main()
