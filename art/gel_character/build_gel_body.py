"""Deterministic, closed quad gel-body source. Run in a fresh background Blender.

blender --background --factory-startup --python-exit-code 1 --python art/gel_character/build_gel_body.py
The rounded modeling master is only read, never overwritten.
"""
import hashlib
import json
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
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
_LOD_CACHE = {}


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


def rebuild_axilla(obj):
    """Reconstruct crossed quad loops against the curved LOD0 shoulder surface.

    Skin's lower thoracic poles span the shoulder in long diagonal faces.
    Splitting only their longitudinal edges retains the transverse crease.
    Opposite-edge rings in both directions keep a conforming closed quad mesh;
    curved surface samples replace the planar patch, not merely its density.
    Rings propagate outside the patch to avoid hanging vertices. Only shoulder
    positions and newly added arm/hand samples move; original extremities stay.
    """
    reference = make_body(2)
    surface = BVHTree.FromPolygons(
        [v.co.copy() for v in reference.data.vertices],
        [tuple(f.vertices) for f in reference.data.polygons])
    reference_mesh = reference.data
    bpy.data.objects.remove(reference, do_unlink=True)
    bpy.data.meshes.remove(reference_mesh)
    points = [v.co.copy() for v in obj.data.vertices]
    original_count = len(points)
    faces = [tuple(f.vertices) for f in obj.data.polygons]

    def edge(a, b):
        return tuple(sorted((a, b)))

    linked = {}
    for index, face in enumerate(faces):
        for a, b in zip(face, face[1:]+face[:1]):
            linked.setdefault(edge(a, b), []).append(index)
    seeds = [e for e in linked
             if all(.1 < abs(points[i].x) < .24 and .85 < points[i].z < 1.11
                    for i in e) and (points[e[0]]-points[e[1]]).length > .09]
    assert seeds, 'Missing long axillary patch edges'
    selected, pending = set(seeds), list(seeds)
    while pending:
        current = pending.pop()
        for index in linked[current]:
            face = faces[index]
            edges = [edge(a, b) for a, b in zip(face, face[1:]+face[:1])]
            opposite = edges[(edges.index(current)+2) % 4]
            if opposite not in selected:
                selected.add(opposite)
                pending.append(opposite)
    splits = {}
    for current in sorted(selected):
        splits[current] = len(points)
        points.append((points[current[0]]+points[current[1]])*.5)
    rebuilt = []
    for face in faces:
        edges = [edge(a, b) for a, b in zip(face, face[1:]+face[:1])]
        chosen = [i for i, current in enumerate(edges) if current in selected]
        if not chosen:
            rebuilt.append(face)
        elif len(chosen) == 4:
            center = len(points)
            points.append(sum((points[i] for i in face), Vector())*.25)
            for i in range(4):
                rebuilt.append((face[i], splits[edges[i]], center,
                                splits[edges[(i-1) % 4]]))
        else:
            assert len(chosen) == 2 and chosen[1]-chosen[0] == 2
            start = chosen[0]
            a, b, c, d = face[start:]+face[:start]
            middle_a, middle_b = splits[edge(a, b)], splits[edge(c, d)]
            rebuilt.extend(((a, middle_a, middle_b, d),
                            (middle_a, b, c, middle_b)))
    for index, point in enumerate(points):
        shoulder = .08 < abs(point.x) < .42 and .91 < point.z < 1.27
        new_arm = index >= original_count and .85 < point.z < 1.27 and abs(point.x) > .08
        if shoulder or new_arm:
            target, _, _, _ = surface.find_nearest(point)
            points[index] = target
    assert len(rebuilt)*2 <= BUDGETS[1], 'Axillary patch exceeds LOD1 budget'
    old_mesh = obj.data
    mesh = bpy.data.meshes.new('GelAxillaryQuadLoops')
    mesh.from_pydata(points, [], rebuilt)
    mesh.update()
    obj.data = mesh
    bpy.data.meshes.remove(old_mesh)


def make_body(level, *, source=None, rig=None, clip_actions=None):
    """A tree Skin surface is sewn at every branch, then subdivided as quads."""
    if level == 0:
        return make_distant_body(source, rig, clip_actions=clip_actions)
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
        # A neutral arms-down thumb points forward, not into the thick thigh.
        thumb = node((s*arm_x(.735), -.09, 1.130), (.039, .038), hand)
        node((s*arm_x(.760), -.14, 1.140), (.031, .030), thumb)
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
    if level == 1:
        rebuild_axilla(obj)
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


def make_distant_body(source=None, rig=None, *, clip_actions=None):
    """Collapse LOD1 endpoints, guarding actual morphs and optional skin poses.

    Production passes its weighted LOD1 and rig explicitly. Geometry-only callers
    validate the same morph contract without inventing a scene-global skeleton.
    """
    import numpy as np
    from gel_body_lod import simplify_morph_safe
    temporary = source is None
    source = make_body(1) if temporary else source
    source.data.calc_loop_triangles()
    points = np.asarray([tuple(v.co) for v in source.data.vertices])
    faces = np.asarray([tuple(f.vertices) for f in source.data.loop_triangles])
    deltas = np.asarray([[tuple(morph_delta(v.co, name))
                         for v in source.data.vertices] for name in MORPHS])
    weights = [[0.]*len(MORPHS)]
    for index in range(len(MORPHS)):
        for value in (-1., 1.):
            sample = [0.]*len(MORPHS)
            sample[index] = value
            weights.append(sample)
    rng = random.Random(311018)
    weights.extend([[rng.uniform(-1., 1.) for _ in MORPHS] for _ in range(30)])
    samples = points[None, :, :]+np.einsum('sm,mni->sni', np.asarray(weights), deltas)
    poses, normals = canonical_pose_samples(source, rig, clip_actions=clip_actions) if rig else (None, None)
    protected = [i for i, p in enumerate(points) if abs(p[2]) < 1e-6
                 or abs(p[2]-max(points[:, 2])) < 1e-6]
    # Repeated source tests build identical meshes. Cache only immutable inputs;
    # changed weights, geometry, morphs, poses or protection produce a new key.
    digest = hashlib.sha256()
    for values in (points, faces, samples, np.asarray(protected), poses, normals):
        if values is not None:
            digest.update(np.asarray(values).tobytes())
    key = digest.digest()
    if key not in _LOD_CACHE:
        result = simplify_morph_safe(points, faces, samples,
            protected_vertices=protected, pose_samples=poses, pose_normal_matrices=normals)
        if not result[2]['target_reached'] or result[2]['triangle_count'] > BUDGETS[2]:
            raise ValueError('Morph-safe LOD2 cannot meet its existing triangle budget')
        if len(_LOD_CACHE) >= 2:
            _LOD_CACHE.pop(next(iter(_LOD_CACHE)))
        _LOD_CACHE[key] = result
    kept, triangles, report = _LOD_CACHE[key]
    mesh = bpy.data.meshes.new('GelMorphSafeLOD2')
    mesh.from_pydata(points[kept].tolist(), [], triangles)
    mesh.update()
    attribute = mesh.attributes.new(name='LOD1SourceVertex', type='INT', domain='POINT')
    for value, index in zip(attribute.data, kept):
        value.value = index
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.update()
    # A severe concave reduction can average one corner normal through its
    # triangle. Keep smooth shading elsewhere and split only such unstable
    # triangles to their outward geometric normal.
    for polygon in mesh.polygons:
        if any(polygon.normal.dot(mesh.corner_normals[loop].vector) <= 0.
               for loop in polygon.loop_indices):
            polygon.use_smooth = False
    mesh.update()
    obj = bpy.data.objects.new('GelBodyLOD2', mesh)
    bpy.context.collection.objects.link(obj)
    obj['lod2_morph_samples'] = report['morph_sample_count']
    obj['lod2_pose_samples'] = report['pose_sample_count']
    if temporary:
        reference_mesh = source.data
        bpy.data.objects.remove(source, do_unlink=True)
        bpy.data.meshes.remove(reference_mesh)
    return obj


def canonical_pose_samples(obj, rig, *, clip_actions=None):
    """Evaluate arm poses and supplied gel clips; restore the caller's rig state.

    Clip actions must be baked for this target, not borrowed from the source35.
    Five times per clip are finite simplification guards, not continuous proof.
    """
    import numpy as np
    old_action = rig.animation_data.action
    old_basis = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
    scene = bpy.context.scene
    old_frame, old_subframe = scene.frame_current, scene.frame_subframe
    points, normal_matrices = [], []
    obj.data.calc_loop_triangles()
    faces = [tuple(f.vertices) for f in obj.data.loop_triangles]
    source_points = [tuple(v.co) for v in obj.data.vertices]
    source_joints, source_weights = [], []
    for vertex in obj.data.vertices:
        scores = [(JOINTS.index(obj.vertex_groups[g.group].name), g.weight)
                  for g in vertex.groups]
        scores += [(0, 0.)]*(4-len(scores))
        source_joints.append([joint for joint, _ in scores])
        source_weights.append([weight for _, weight in scores])
    def capture(*, validate_surface=False):
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        points.append([tuple(v.co) for v in evaluated.data.vertices])
        transforms = {b.name: b.matrix @ b.bone.matrix_local.inverted()
                      for b in rig.pose.bones}
        if validate_surface:
            from gel_pose_validation import pose_surface
            contacts, flipped = pose_surface(source_points, faces, source_joints,
                source_weights, [[tuple(row) for row in transforms[name]] for name in JOINTS],
                list(range(len(source_points))))
            if contacts or flipped:
                raise ValueError(('LOD1 source clip surface must pass before simplification',
                                  rig.animation_data.action.name, scene.frame_current,
                                  len(contacts), len(flipped), contacts[:3], flipped[:3]))
        matrices = []
        for vertex in obj.data.vertices:
            blend = Matrix.Identity(4)*0
            for group in vertex.groups:
                blend += transforms[obj.vertex_groups[group.group].name]*group.weight
            matrices.append([tuple(row) for row in blend.to_3x3().inverted().transposed()])
        normal_matrices.append(matrices)
    try:
        rig.animation_data.action = None
        for angle in (0, 30, 60, 75, 80, 85, 90):
            for bone in rig.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
            bpy.context.view_layer.update()
            for side, sign in (('L', 1), ('R', -1)):
                bone = rig.pose.bones['upper_arm.'+side]
                pivot = bone.bone.head_local
                bone.matrix = (Matrix.Translation(pivot)
                    @ Matrix.Rotation(math.radians(angle)*sign, 4, 'Y')
                    @ Matrix.Translation(-pivot) @ bone.bone.matrix_local)
            bpy.context.view_layer.update()
            capture()
        for action, duration in (clip_actions or {}).values():
            rig.animation_data.action = action
            for fraction in (0., .25, .5, .75, 1.):
                frame = round(duration*scene.render.fps)*fraction
                scene.frame_set(int(frame), subframe=frame-int(frame))
                bpy.context.view_layer.update()
                capture(validate_surface=True)
    finally:
        rig.animation_data.action = old_action
        scene.frame_set(old_frame, subframe=old_subframe)
        for bone in rig.pose.bones:
            bone.matrix_basis = old_basis[bone.name]
        bpy.context.view_layer.update()
    return np.asarray(points), np.asarray(normal_matrices)


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
        # Thickness preserves limb axes: X along arms, Y along the boot.
        # Foot length belongs to foot_size; swelling it here makes the toe
        # collide with the calf during a retained running ankle trajectory.
        center.y = y*foot
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
        # Blender initializes a newly added relative key at one. Export Basis
        # explicitly rather than leaving every authored extreme active.
        key.value = 0.
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
            # Keep the derived shoulder inside its surface, below the arm
            # centerline, without shortening the connected grip chain.
            ('upper_arm',(sign*.30,0,1.05),p(.46,0,1.105),'chest'),
            ('forearm',p(.46,0,1.105),p(.66,0,1.105),'upper_arm.'+side),
            ('hand',p(.66,0,1.105),p(.82,0,1.105),'forearm.'+side),
            ('thumb',p(.735,-.09,1.130),p(.760,-.14,1.140),'hand.'+side),
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


def assign_weights(obj, rig, *, reference=None):
    """Surface-connected bone heat, normalized to four influences per vertex.

    A spatial zone cutoff excluded the arm from adjacent torso vertices and
    folded the shoulder when lowered. Heat considers the sewn surface instead.
    A smooth chest/upper-arm partition keeps the axillary weight gradient from
    folding when the derived shoulder reaches the arms-down pose.
    """
    if reference is not None:
        source_indices = obj.data.attributes['LOD1SourceVertex'].data
        for name in JOINTS:
            obj.vertex_groups.new(name=name)
        for vertex, index in zip(obj.data.vertices, source_indices):
            for group in reference.data.vertices[index.value].groups:
                name = reference.vertex_groups[group.group].name
                obj.vertex_groups[name].add([vertex.index], group.weight, 'REPLACE')
        obj.parent = rig
        modifier = obj.modifiers.new('Gel skin', 'ARMATURE')
        modifier.object = rig
        return
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    def smooth(a, b, value):
        t = max(0., min(1., (value-a)/(b-a)))
        return t*t*(3-2*t)
    heat = []
    for vertex in obj.data.vertices:
        scores = [(obj.vertex_groups[g.group].name, g.weight)
                  for g in vertex.groups
                  if obj.vertex_groups[g.group].name in JOINTS and g.weight > 0.]
        p = vertex.co
        x = abs(p.x)
        amount = (smooth(.08, .12, x)*(1-smooth(.42, .50, x))
                  *smooth(.91, 1.0, p.z)*(1-smooth(1.20, 1.27, p.z)))
        if amount:
            old = dict(scores)
            arm = smooth(.10, .42, x)
            side = 'L' if p.x >= 0 else 'R'
            target = {'upper_arm.'+side: arm, 'chest': 1-arm}
            scores = [(name, old.get(name, 0.)*(1-amount)
                       +target.get(name, 0.)*amount) for name in JOINTS]
            scores = [(name, weight) for name, weight in scores if weight > 0.]
        scores = sorted(scores, key=lambda item: (-item[1], JOINTS.index(item[0])))[:4]
        total = sum(weight for _, weight in scores)
        assert total > 0., ('Bone heat left vertex unweighted', obj.name, vertex.index)
        heat.append([(name, weight/total) for name, weight in scores])
    # The LOD2 sole-protection group has served its simplification purpose.
    # Rebuild only the twenty deform groups, in the same export order as before.
    obj.vertex_groups.clear()
    for name in JOINTS:
        obj.vertex_groups.new(name=name)
    for vertex, scores in zip(obj.data.vertices, heat):
        p = vertex.co
        zone, _ = zones(p)
        side = 'L' if p.x >= 0 else 'R'
        if zone == 'foot':
            # Preserve the planted sole and forward toe as a foot, rather than
            # bending the lower boot back toward the vertical shin capsule.
            shin_blend = max(0., min(1., (p.z-.14)/.07))*.25
            obj.vertex_groups['foot.'+side].add([vertex.index], 1-shin_blend, 'REPLACE')
            if shin_blend:
                obj.vertex_groups['shin.'+side].add([vertex.index], shin_blend, 'REPLACE')
            continue
        for name, weight in scores:
            obj.vertex_groups[name].add([vertex.index], weight, 'REPLACE')
    next(mod for mod in obj.modifiers if mod.type == 'ARMATURE').name = 'Gel skin'
    refine_joint_weights(obj, rig)


def refine_joint_weights(obj, rig):
    """Joint-span C1 fields, retaining rigid soles and same-side limb ownership.

    Normalize to four influences after each stage, just as in the finite
    geometry probes. LOD2 inherits the resulting fine weights without another
    heat solution. The 1.3 envelope is the maximum general-thickness radius.
    """
    def smooth(a, b, value):
        t = max(0., min(1., (value-a)/(b-a)))
        return t*t*(3-2*t)

    def read(vertex):
        return {obj.vertex_groups[g.group].name: g.weight for g in vertex.groups}

    def write(vertex, scores):
        chosen = sorted(((n, w) for n, w in scores.items() if w > 0.),
                        key=lambda pair: (-pair[1], JOINTS.index(pair[0])))[:4]
        total = sum(w for _, w in chosen)
        assert total > 0., ('Joint field left vertex unweighted', obj.name, vertex.index)
        for group in obj.vertex_groups:
            group.remove([vertex.index])
        for name, weight in chosen:
            obj.vertex_groups[name].add([vertex.index], weight/total, 'REPLACE')

    def blend(vertex, target, amount):
        old = read(vertex)
        write(vertex, {n: old.get(n, 0.)*(1-amount)+target.get(n, 0.)*amount
                       for n in JOINTS})

    # Preserve the combined chest/limb owner total across the shoulder.
    for vertex in obj.data.vertices:
        x, z = abs(vertex.co.x), vertex.co.z
        if not .9 < z < 1.3:
            continue
        side = 'L' if vertex.co.x >= 0 else 'R'
        names = {part+'.'+side for part in ('upper_arm', 'forearm', 'hand', 'thumb', 'grip')}
        old = read(vertex)
        total = old.get('chest', 0.)+sum(w for n, w in old.items() if n in names)
        arm = smooth(.052, .468, x)
        amount = smooth(.9, .95, z)*(1-smooth(1.25, 1.3, z))
        target = {'chest': total*(1-arm), 'upper_arm.'+side: total*arm}
        write(vertex, {n: (old.get(n, 0.)*(1-amount)+target.get(n, 0.)*amount)
                      if n == 'chest' or n in names else old.get(n, 0.) for n in JOINTS})

    for vertex in obj.data.vertices:
        x, z = abs(vertex.co.x), vertex.co.z
        if not (.21 < z < .60 and x < .30):
            continue
        side = 'L' if vertex.co.x >= 0 else 'R'
        width = (rig.data.bones['thigh.'+side].head_local.z
                 -rig.data.bones['foot.'+side].head_local.z)*1.3
        thigh = smooth(.375-width*.5, .375+width*.5, z)
        amount = smooth(.21, .25, z)*(1-smooth(.55, .60, z))*(1-smooth(.25, .30, x))
        blend(vertex, {'thigh.'+side: thigh, 'shin.'+side: 1-thigh}, amount)

    for vertex in obj.data.vertices:
        p = vertex.co
        x, z = abs(p.x), p.z
        amount = (1-smooth(.52, .60, z))*(1-smooth(.25, .30, x))
        if amount <= 0.:
            continue
        side = 'L' if p.x >= 0 else 'R'
        knee = rig.data.bones['shin.'+side].head_local.z
        width = (rig.data.bones['thigh.'+side].head_local.z
                 -rig.data.bones['foot.'+side].head_local.z)*1.3
        thigh = smooth(knee-width*.5, knee+width*.5, z)
        foot = 1-smooth(.14, knee, z)
        toe = (1-smooth(-.12, -.08, p.y))*(1-smooth(.21, .30, z))
        foot = 1-(1-foot)*(1-toe)
        blend(vertex, {'foot.'+side: foot, 'shin.'+side: (1-foot)*(1-thigh),
                       'thigh.'+side: (1-foot)*thigh}, amount)

    for vertex in obj.data.vertices:
        p = vertex.co
        x, z = abs(p.x), p.z
        amount = smooth(.50, .56, z)*(1-smooth(.96, 1., z))*(1-smooth(.25, .30, x))
        if amount <= 0.:
            continue
        side = 'L' if p.x >= 0 else 'R'
        hip = rig.data.bones['thigh.'+side].head_local.z
        width = (rig.data.bones['chest'].head_local.z
                 -rig.data.bones['shin.'+side].head_local.z)*1.3
        thigh = 1-smooth(hip-width*.5, hip+width*.5, z)
        left = smooth(-.065, .065, p.x)
        width = (rig.data.bones['neck'].head_local.z
                 -rig.data.bones['pelvis'].head_local.z)*1.3
        center = rig.data.bones['chest'].head_local.z
        chest = smooth(center-width*.5, center+width*.5, z)
        arm = smooth(.10, .42, x)*smooth(.85, 1., z)
        blend(vertex, {'thigh.L': (1-arm)*(1-chest)*thigh*left,
                       'thigh.R': (1-arm)*(1-chest)*thigh*(1-left),
                       'pelvis': (1-arm)*(1-chest)*(1-thigh),
                       'chest': (1-arm)*chest, 'upper_arm.'+side: arm}, amount)

    for vertex in obj.data.vertices:
        x, z = abs(vertex.co.x), vertex.co.z
        if not (.1 < x < 1. and .9 < z < 1.3):
            continue
        side = 'L' if vertex.co.x >= 0 else 'R'
        names = {part+'.'+side for part in ('upper_arm', 'forearm', 'hand', 'thumb', 'grip')}
        old = read(vertex)
        total = sum(w for n, w in old.items() if n in names)
        fore = smooth(.295, .685, x)
        hand = smooth(.52, .86, x)
        thumb = smooth(.74, .82, x)*(1-smooth(-.120, -.040, vertex.co.y))
        target = {'upper_arm.'+side: 1-fore, 'forearm.'+side: fore*(1-hand),
                  'hand.'+side: fore*hand*(1-thumb), 'thumb.'+side: fore*hand*thumb}
        write(vertex, {n: w for n, w in old.items() if n not in names}
                      | {n: w*total for n, w in target.items()})

    # A sub-percent C1 redistribution removes late pickup shoulder folds.
    # Keep all other owners and slots exactly: only chest/upper-arm exchange.
    shoulder_field = (
        (.265, 1.035, .0018835696882960966),
        (.265, 1.075, .004092546952032621),
        (.265, 1.115, .001535457253029704),
        (.310, 1.035, .0012947610511028045),
        (.310, 1.075, .0024248141476813576),
        (.310, 1.115, .0007206838006233915),
        (.355, 1.035, -.0007488921265232677),
        (.355, 1.075, -.002900386169198112),
        (.355, 1.115, -.001355284192354062),
    )
    for vertex in obj.data.vertices:
        x, y, z = abs(vertex.co.x), vertex.co.y, vertex.co.z
        envelope = (smooth(.20, .24, x)*(1-smooth(.40, .44, x))
                    *smooth(.96, 1., z)*(1-smooth(1.17, 1.22, z))
                    *smooth(-.16, -.13, y)*(1-smooth(-.02, .03, y)))
        if envelope <= 0.:
            continue
        upper = 'upper_arm.'+('L' if vertex.co.x >= 0 else 'R')
        old = read(vertex)
        if old.get('chest', 0.) <= 0. or old.get(upper, 0.) <= 0.:
            continue
        delta = envelope*sum(c*math.exp(-.5*((x-a)/.035)**2
                                       -.5*((z-b)/.028)**2
                                       -.5*((y+.07)/.05)**2)
                             for a, b, c in shoulder_field)
        assert old[upper]+delta > 0. and old['chest']-delta > 0.
        obj.vertex_groups[upper].add([vertex.index], old[upper]+delta, 'REPLACE')
        obj.vertex_groups['chest'].add([vertex.index], old['chest']-delta, 'REPLACE')


def bake_clips(source, target):
    from gel_body_motion import adapt_pose
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
    max_unreachable_endpoint = 0.
    max_chain_attachment_error = 0.
    max_ankle_goal_error = 0.
    max_interaction_grip_error = 0.
    max_pelvis_adjustment = 0.
    unreachable_by_clip = {}
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
            pelvis_before = poses['pelvis'].translation.copy()
            poses, unreachable = adapt_pose(source, target, poses, name, frame/FPS)
            max_pelvis_adjustment = max(max_pelvis_adjustment,
                (poses['pelvis'].translation-pelvis_before).length)
            max_unreachable_endpoint = max(max_unreachable_endpoint, unreachable)
            if unreachable > unreachable_by_clip.get(name, {}).get('distance_m', -1.):
                unreachable_by_clip[name] = {'distance_m': unreachable,
                                             'time_s': frame/FPS}
            for bone_name in order:
                dst = target.pose.bones[bone_name]
                world = poses[bone_name]
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
            for side in 'LR':
                for parent, child in (('thigh.', 'shin.'), ('shin.', 'foot.'),
                                      ('upper_arm.', 'forearm.'), ('forearm.', 'hand.')):
                    gap = (target.pose.bones[parent+side].tail
                           -target.pose.bones[child+side].head).length
                    max_chain_attachment_error = max(max_chain_attachment_error, gap)
                foot = source.pose.bones['foot.'+side]
                ankle_goal = (target.data.bones['foot.'+side].head_local
                              +(foot.head-foot.bone.head_local)*.5)
                error = (target.pose.bones['foot.'+side].head-ankle_goal).length
                max_ankle_goal_error = max(max_ankle_goal_error, error)
                if name == 'Sit' or (name in ('PickUpPackage', 'PickUpHigh')
                                     and frame/FPS >= .42):
                    goal = source.pose.bones['grip.'+side].head*.5
                    error = (target.pose.bones['grip.'+side].head-goal).length
                    max_interaction_grip_error = max(max_interaction_grip_error, error)
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
    assert max_unreachable_endpoint < .00001, unreachable_by_clip
    assert max_chain_attachment_error < .00001, max_chain_attachment_error
    assert max_ankle_goal_error < .00001, max_ankle_goal_error
    assert max_interaction_grip_error < .00001, max_interaction_grip_error
    return {'durations': DURATIONS, 'maximum_rotation_error_radians': max_rotation_error,
            'maximum_bone_length_error_m': max_bone_length_error,
            'maximum_unreachable_endpoint_m': max_unreachable_endpoint,
            'maximum_unreachable_endpoint_by_clip': unreachable_by_clip,
            'maximum_chain_attachment_error_m': max_chain_attachment_error,
            'maximum_ankle_goal_error_m': max_ankle_goal_error,
            'maximum_interaction_grip_error_m': max_interaction_grip_error,
            'maximum_pelvis_adjustment_m': max_pelvis_adjustment,
            'endpoint_measurement': 'baked keyframes; all ankle targets; Sit grips and pickup grips from 0.42 seconds onward; no continuous interpolation certification',
            'foot_joint_height_ranges_m': foot_ranges,
            'foot_plant_status': 'joint ranges measured; deformed sole contact requires independent pose capture',
            'retarget': 'source world rotation delta and root translation scale 0.5; gel two-bone IK preserves source-relative ankles and interaction grips; connected chest reach correction for pickups'}


def build_body_lods(source):
    """Build the same explicitly weighted LOD pipeline in export and tests."""
    objects = [make_body(level) for level in LOD_LEVELS[:2]]
    rig = create_rig(source)
    for obj in objects:
        assign_weights(obj, rig)
    animation_report = bake_clips(source, rig)
    clips = {name: (bpy.data.actions[name], duration)
             for name, duration in animation_report['durations'].items()}
    distant = make_body(0, source=objects[1], rig=rig, clip_actions=clips)
    assign_weights(distant, rig, reference=objects[1])
    objects.append(distant)
    return rig, objects, animation_report


def main():
    master = ROOT/'art/rounded_character/personaje_redondeado.blend'
    source_hash = hashlib.sha256(master.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(master))
    source = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    source.name = 'AuthorSkeleton35'
    for o in list(bpy.data.objects):
        if o != source:
            bpy.data.objects.remove(o, do_unlink=True)
    rig, objects, animation_report = build_body_lods(source)
    for obj, budget in zip(objects, BUDGETS):
        tris = sum(len(f.vertices)-2 for f in obj.data.polygons)
        assert tris <= budget, (obj.name, tris, budget)
        decorate(obj)
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
            'lod2_algorithm': 'morph-aware endpoint quadric collapse of weighted LOD1 to target 794 triangles; 53 morphs, seven arm poses and five times per gel clip guard exact source positions/weights and flat sole vertices',
            'foot_depth_design_m': .28, 'foot_depth_source': 'profile design, not inferred from frontal JPG',
            'reference_shape_targets': {'torso_waist_width_m': [.40,.43],
                'foot_width_m': .57*(1.74/3.68), 'neck_visible_height_m': .11*(1.74/3.68)},
            'reference_pose': f'static diagnostic A-pose, arms 15 degrees from vertical; {len(animation_report["durations"])} source-timed clips adapted to gel limb proportions',
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
