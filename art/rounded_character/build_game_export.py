"""Game export of the rounded character for Take My Package.

Opens personaje_redondeado.blend (never saves it) and writes
do-not-drop/assets/models/characters/sm_char_player_rounded.glb:

- one joined, decimated mesh (~20k tris instead of 64k), ASCII material names
  (Shirt is surface 0, so the player's crew colour lands on the T-shirt);
- rig rotated to face Godot's -Z and scaled 0.5 (about 1.74 m tall);
- the clips player.gd plays: Idle, Walk, Jump, PickUpPackage, Sit. The IK
  controls are baked into the deform bones by the exporter's sampling.

Run:
  blender --background --factory-startup -noaudio art/rounded_character/personaje_redondeado.blend \
      --python art/rounded_character/build_game_export.py
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector, Euler, Matrix

HERE = Path(bpy.data.filepath).parent
OUT = HERE.parent.parent / 'do-not-drop' / 'assets' / 'models' / 'characters' / 'sm_char_player_rounded.glb'
PREVIEW = '--preview' in sys.argv
FPS = 30

scene = bpy.context.scene
scene.render.fps = FPS
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == rig]

# --- Materials: short ASCII names Godot code can look up -------------------
MAT_NAMES = {'01': 'Skin', '02': 'Shirt', '03': 'ShirtTrim', '04': 'Shorts',
             '05': 'ShortsHem', '06': 'Shoe', '07': 'Sole'}
for mat in bpy.data.materials:
    if mat.name[:2] in MAT_NAMES:
        mat.name = MAT_NAMES[mat.name[:2]]

# --- Mesh: trim hidden overlaps, drop morphs, decimate, join ----------------
# Hidden in the rest pose, but once the thighs swing forward (Sit, Jump) the
# leg tops poke out of the shorts and the shorts' waist out of the shirt:
# each is weighted differently from the garment over it. Cut them where the
# garment still covers the cut (shorts hem 0.577-0.673, shirt hem ~1.11).
TRIM_ABOVE = {'Pierna': .64, 'Short · pieza': 1.3}
for o in meshes:
    limit = next((z for k, z in TRIM_ABOVE.items() if o.name.startswith(k)), None)
    if limit is None: continue
    bm = bmesh.new(); bm.from_mesh(o.data)
    doomed = [v for v in bm.verts if (o.matrix_world @ v.co).z > limit]
    bmesh.ops.delete(bm, geom=doomed, context='VERTS')
    bm.to_mesh(o.data); bm.free()
RATIOS = {'Brazo': .25, 'Camiseta · cuerpo': .25, 'Short · pieza': .25, 'Cabeza': .6}
bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
for o in meshes:
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True); bpy.context.view_layer.objects.active = o
    if o.data.shape_keys:
        o.active_shape_key_index = 0
        bpy.ops.object.shape_key_remove(all=True, apply_mix=False)
    ratio = next((r for k, r in RATIOS.items() if o.name.startswith(k)), .35)
    dec = o.modifiers.new('Decimar juego', 'DECIMATE'); dec.ratio = ratio
    # Keep the armature last so the decimate applies to rest geometry.
    while o.modifiers.find(dec.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=dec.name)
    bpy.ops.object.modifier_apply(modifier=dec.name)
    bpy.ops.object.shade_smooth()
shirt = next(o for o in meshes if o.name.startswith('Camiseta · cuerpo'))
bpy.ops.object.select_all(action='DESELECT')
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active = shirt
bpy.ops.object.join()
body = shirt; body.name = 'Body'; body.data.name = 'Body'
# Surface 0 must be the shirt: move its slot first.
while body.material_slots[0].material.name != 'Shirt':
    body.active_material_index = next(i for i, s in enumerate(body.material_slots) if s.material.name == 'Shirt')
    bpy.ops.object.material_slot_move(direction='UP')
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)

# --- Animation helpers -------------------------------------------------------
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
bpy.context.view_layer.objects.active = rig
rig.animation_data_create()
for k in list(rig.keys()):
    if k.startswith('IK_'): rig[k] = 1.0
REST = {pb.name: pb.bone.matrix_local.copy() for pb in rig.pose.bones}

def reset():
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_mode = 'XYZ'; pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)

def to_local(name, world_vec):
    return REST[name].to_3x3().inverted() @ Vector(world_vec)

def fk(name, rot=(0, 0, 0), loc=(0, 0, 0)):
    """Rotation (degrees, armature axes) about the bone's own head, plus an armature-space offset."""
    pb = rig.pose.bones[name]; r3 = REST[name].to_3x3()
    world = Euler([math.radians(a) for a in rot]).to_matrix()
    pb.rotation_euler = (r3.inverted() @ world @ r3).to_euler()
    pb.location = to_local(name, loc)

def ik(name, target, rot=(0, 0, 0)):
    """IK controls hang off CTRL_root, so local = rest-relative armature space."""
    fk(name, rot, Vector(target) - REST[name].translation)

def side_sign(side): return 1.0 if side == 'L' else -1.0

def hands(l, r, rot_l=None, rot_r=None):
    # Hanging hands point down: rotate the rest (+-X pointing) hand about Y.
    ik('CTRL_hand_IK.L', l, rot_l if rot_l is not None else (0, 80, 0))
    ik('CTRL_hand_IK.R', r, rot_r if rot_r is not None else (0, -80, 0))

def feet(l=(0, 0, 0), r=(0, 0, 0), rot_l=(0, 0, 0), rot_r=(0, 0, 0)):
    ik('CTRL_foot_IK.L', REST['CTRL_foot_IK.L'].translation + Vector(l), rot_l)
    ik('CTRL_foot_IK.R', REST['CTRL_foot_IK.R'].translation + Vector(r), rot_r)

def elbows_back():
    # Rest poles sit behind the elbows; pulled lower so the hanging arms bend slightly back.
    for s in 'LR':
        ik('CTRL_elbow.' + s, (side_sign(s) * 1.25, .9, 1.7))

HANG_L, HANG_R = Vector((1.14, -.02, 1.46)), Vector((-1.14, -.02, 1.46))

def stand(breath=0.0):
    reset()
    fk('pelvis', loc=(0, 0, -.06))
    fk('chest', rot=(-2 * breath, 0, 0))
    fk('belly', loc=(0, -.025 * breath, .01 * breath))
    fk('head', rot=(1.5 * breath, 0, 0))
    elbows_back()
    hands(HANG_L + Vector((0, 0, .02 * breath)), HANG_R + Vector((0, 0, .02 * breath)))
    feet()

def key(frame):
    for pb in rig.pose.bones:
        pb.keyframe_insert('location', frame=frame)
        pb.keyframe_insert('rotation_euler', frame=frame)
        pb.keyframe_insert('scale', frame=frame)

def make_action(name, frames, poses):
    act = bpy.data.actions.new(name); act.use_fake_user = True
    rig.animation_data.action = act
    for f, pose in zip(frames, poses):
        pose(); key(f)
    act.frame_range = (frames[0], frames[-1])
    try: act.use_frame_range = True
    except AttributeError: pass
    return act

# Idle: 2.5 s breathing loop.
make_action('Idle', [0, 38, 75], [lambda: stand(0), lambda: stand(1), lambda: stand(0)])

# Walk: brisk 0.667 s waddle. Legs are short (0.85 u), so the pelvis drops at contact.
STRIDE = .28
def walk(phase):
    reset()
    c = math.cos(phase); s = math.sin(phase)       # c=1: left foot forward
    lift_r = max(0.0, s) * .2; lift_l = max(0.0, -s) * .2
    fk('pelvis', rot=(0, 0, 6 * c), loc=(.035 * s, 0, -.1 + .06 * abs(s)))
    fk('spine', rot=(4, 0, 0)); fk('chest', rot=(0, 0, -8 * c))
    fk('belly', loc=(0, 0, .015 * abs(s)))
    elbows_back()
    hands(HANG_L + Vector((0, .22 * c, .03 + .04 * max(0, c))), HANG_R + Vector((0, -.22 * c, .03 + .04 * max(0, -c))))
    feet(l=(0, -STRIDE * c, lift_l), r=(0, STRIDE * c, lift_r),
         rot_l=(-12 * c, 0, 0), rot_r=(12 * c, 0, 0))
make_action('Walk', [0, 5, 10, 15, 20], [lambda p=p: walk(p * math.pi / 2) for p in range(5)])

# Jump: anticipation, take-off, tuck, landing (50 frames = 1.67 s, one-shot).
def crouch(depth, arm_z, arm_y, lean):
    reset()
    fk('pelvis', loc=(0, 0, -depth)); fk('spine', rot=(lean, 0, 0))
    elbows_back()
    hands(HANG_L + Vector((.05, arm_y, arm_z)), HANG_R + Vector((-.05, arm_y, arm_z)))
    feet()
def airborne():
    reset()
    fk('pelvis', loc=(0, 0, 0)); fk('spine', rot=(-4, 0, 0)); fk('head', rot=(-6, 0, 0))
    hands((1.05, -.25, 2.85), (-1.05, -.25, 2.85), (0, -20, 0), (0, 20, 0))
    feet(l=(0, -.12, .3), r=(0, .05, .22), rot_l=(20, 0, 0), rot_r=(-10, 0, 0))
make_action('Jump', [0, 8, 14, 30, 38, 50], [
    lambda: stand(0),
    lambda: crouch(.2, -.1, .35, 14),
    airborne, airborne,
    lambda: crouch(.18, .25, -.15, 10),
    lambda: stand(0)])

# PickUpPackage: bend, reach, grip, stand holding the box at the chest (50 frames).
def reach(depth, lean, hand_y, hand_z, width=.62):
    reset()
    fk('pelvis', loc=(0, .08 * depth / .25, -depth)); fk('spine', rot=(lean, 0, 0)); fk('chest', rot=(lean * .4, 0, 0))
    fk('head', rot=(-lean * .3, 0, 0))
    for s in 'LR':
        ik('CTRL_elbow.' + s, (side_sign(s) * 1.4, .3, 1.8))
    hands((width, hand_y, hand_z), (-width, hand_y, hand_z), (-70, 0, -90), (-70, 0, 90))
    feet()
make_action('PickUpPackage', [0, 14, 22, 28, 40, 50], [
    lambda: stand(0),
    lambda: reach(.25, 26, -.95, 1.15),
    lambda: reach(.27, 28, -.9, 1.12, .55),
    lambda: reach(.2, 18, -.82, 1.35, .55),
    lambda: reach(.02, 0, -.78, 1.8, .55),
    lambda: reach(0, 0, -.76, 1.82, .55)])

# Sit: pelvis drops 1.0 u (0.5 m), to about the root. player.gd places the
# root on each seat's cushion (Player._seat_body_offset).
SIT_DROP = 1.0
def sit(breath=0.0):
    reset()
    fk('pelvis', loc=(0, .05, -SIT_DROP)); fk('spine', rot=(-4, 0, 0)); fk('chest', rot=(-2 * breath, 0, 0))
    fk('belly', loc=(0, -.02 * breath, 0))
    hip = 1.09 - SIT_DROP
    for s in 'LR':
        ik('CTRL_knee.' + s, (side_sign(s) * .46, -1.4, hip + .2))
        ik('CTRL_elbow.' + s, (side_sign(s) * 1.4, .6, 1.3))
    feet(l=(.04, -.58, hip - .8 + .005 * breath), r=(-.04, -.58, hip - .8), rot_l=(0, 0, 0), rot_r=(0, 0, 0))
    # Palms down on the outer thighs, fingers forward (the belly fills the lap).
    hands((.62, -.22, hip + .12 + .015 * breath), (-.62, -.22, hip + .12 + .015 * breath), (0, 15, -80), (0, -15, 80))
make_action('Sit', [0, 30, 60], [lambda: sit(0), lambda: sit(1), lambda: sit(0)])

rig.animation_data.action = bpy.data.actions['Idle']
stand(0)

# --- Orientation and scale for Godot ----------------------------------------
# Blender front is -Y; +Y becomes glTF -Z, Godot's forward. 0.5 gives 1.74 m.
rig.rotation_mode = 'XYZ'
rig.rotation_euler = (0, 0, math.pi)
rig.scale = (.5, .5, .5)

if PREVIEW:
    import os
    prev_dir = Path(os.environ.get('PREVIEW_DIR', str(HERE)))
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'; scene.display.shading.color_type = 'MATERIAL'
    scene.render.resolution_x = 360; scene.render.resolution_y = 420
    cam = bpy.data.objects.get('Camara')
    for o in bpy.data.objects:
        if o.type == 'MESH' and o != body: o.hide_render = True
    cam.location = (4.6, 3.4, 1.5); cam.data.ortho_scale = 2.6  # front 3/4 (rig already faces +Y)
    cam.rotation_euler = (Vector((0, 0, .85)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    for act_name, frames in [('Idle', [0]), ('Walk', [0, 5, 10]), ('Jump', [8, 20, 38]), ('PickUpPackage', [14, 22, 40]), ('Sit', [0])]:
        rig.animation_data.action = bpy.data.actions[act_name]
        for f in frames:
            scene.frame_set(f)
            scene.render.filepath = str(prev_dir / f'prev_{act_name}_{f:02d}.png')
            bpy.ops.render.render(write_still=True)
    # Sit from the side and from the front: legs against the shorts, belly.
    rig.animation_data.action = bpy.data.actions['Sit']; scene.frame_set(0)
    for tag, loc in [('side', (5.0, .2, .6)), ('front', (1.2, 5.0, .7))]:
        cam.location = loc; cam.data.ortho_scale = 2.2
        cam.rotation_euler = (Vector((0, 0, .5)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(prev_dir / f'prev_Sit_{tag}.png')
        bpy.ops.render.render(write_still=True)
    rig.animation_data.action = bpy.data.actions['Idle']
    scene.frame_set(0)

# --- Export --------------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True); body.select_set(True)
bpy.context.view_layer.objects.active = rig
props = bpy.ops.export_scene.gltf.get_rna_type().properties
kwargs = dict(filepath=str(OUT), export_format='GLB', use_selection=True,
              export_animations=True, export_skins=True, export_morph=False)
for k, v in [('export_def_bones', True), ('export_animation_mode', 'ACTIONS'), ('export_force_sampling', True),
             ('export_frame_range', False), ('export_anim_single_armature', True), ('export_reset_pose_bones', True),
             ('export_extras', False), ('export_apply', False)]:
    if k in props:
        if props[k].type == 'ENUM' and v not in {x.identifier for x in props[k].enum_items}: continue
        kwargs[k] = v
bpy.ops.export_scene.gltf(**kwargs)
print('GAME_EXPORT', json.dumps({'file': str(OUT), 'triangles': tris,
      'materials': [s.material.name for s in body.material_slots],
      'actions': {a.name: list(a.frame_range) for a in bpy.data.actions}}))
