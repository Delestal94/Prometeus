"""Game export of the rounded character for Take My Package.

Opens personaje_redondeado.blend (never saves it) and writes
do-not-drop/assets/models/characters/sm_char_player_rounded.glb:

- one joined, decimated mesh (~20k tris instead of 64k), ASCII material names
  (Shirt is surface 0, so the player's crew colour lands on the T-shirt);
- rig rotated to face Godot's -Z and scaled 0.5 (about 1.74 m tall);
- the clips player.gd plays: Idle, Walk, Stroll, Jump, PickUpPackage,
  PickUpHigh (blended with PickUpPackage by box height), Sit, TurnInPlace
  (steps while turning standing still)
  (animation_library.py). The IK controls are baked into the deform bones
  by the exporter's sampling; model_fixes.py corrects skin weights first.

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

sys.path.insert(0, str(HERE))
import model_fixes
model_fixes.apply(rig)

# --- Materials: short ASCII names Godot code can look up -------------------
MAT_NAMES = {'01': 'Skin', '02': 'Shirt', '03': 'ShirtTrim', '04': 'Shorts',
             '05': 'ShortsHem', '06': 'Shoe', '07': 'Sole'}
for mat in bpy.data.materials:
    if mat.name[:2] in MAT_NAMES:
        mat.name = MAT_NAMES[mat.name[:2]]

# --- Mesh: drop morphs, decimate, join (hidden overlaps: model_fixes) ---------
RATIOS = {'Brazo': .25, 'Camiseta · cuerpo': .25, 'Short · pieza': .25, 'Cabeza': .8}
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

# --- Animation library: grounded contact paths and staged one-shots ----------
from animation_library import build, FPS, DURATIONS
scene.render.fps = FPS
bpy.context.view_layer.objects.active = rig
build(rig)
scene.frame_set(0)

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
    for act_name, frames in [('Idle', [0]), ('Walk', [0, 5, 10, 15]), ('Stroll', [0, 9, 18, 27]), ('Jump', [6, 24, 56, 64]), ('PickUpPackage', [20, 32, 60, 90]), ('PickUpHigh', [20, 32, 60, 90]), ('Sit', [0]), ('TurnInPlace', [0, 6, 10, 14, 24, 34, 38, 42])]:
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
# Editable animation master, separate from the original modeling/rest file.
rig.animation_data.action = bpy.data.actions['Idle']
scene.frame_start = 0
scene.frame_end = round(DURATIONS['Idle'] * FPS)
scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE / 'personaje_animado.blend'))
bpy.ops.export_scene.gltf(**kwargs)
print('GAME_EXPORT', json.dumps({'file': str(OUT), 'triangles': tris,
      'materials': [s.material.name for s in body.material_slots],
      'actions': {a.name: list(a.frame_range) for a in bpy.data.actions}}))
