"""Review renders of the character with a face on, in Cycles.

Opens personaje_redondeado.blend (never saves it), lays the face textures on
the head the way character_face.gd does in the game (same curved patch) and
renders a front, a 3/4 and a close-up of the face into review/.

  blender --background --factory-startup -noaudio --python render_review.py -- [eyes] [mouth] [--pose Clip:frame]

The SVGs are rasterised with PyMuPDF from the system Python (python -m pip
install pymupdf) into the scratch folder given by REVIEW_TMP, or review/.
--pose builds the animation library and poses the rig on that clip frame.
"""
import bpy, math, os, subprocess, sys
from pathlib import Path
from mathutils import Vector, Matrix

HERE = Path(__file__).resolve().parent
FACES = HERE.parents[1] / 'do-not-drop' / 'assets' / 'textures' / 'characters' / 'faces'
OUT = HERE / 'review'
TMP = Path(os.environ.get('REVIEW_TMP', str(OUT)))
args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
pose = None
if '--pose' in args:
    i = args.index('--pose'); pose = args[i+1]; del args[i:i+2]
eyes, mouth = (args + ['classic', 'smile'])[:2] if len(args) < 2 else args[:2]

sys.path.insert(0, str(HERE))
bpy.ops.wm.open_mainfile(filepath=str(HERE / 'personaje_redondeado.blend'))
import head_shape as shape   # head formula shared with build_character.py
scene = bpy.context.scene
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

def raster(name):
    png = TMP / (name + '.png')
    code = ('import fitz,sys; d=fitz.open(sys.argv[1]); '
            'd[0].get_pixmap(alpha=True,dpi=144).save(sys.argv[2])')
    subprocess.run(['python', '-c', code, str(FACES / (name + '.svg')), str(png)], check=True)
    return png

def patch(name, png, lift=0.):
    """character_face.gd's curved patch, in Blender units, on the head bone."""
    steps = 20
    verts, faces, uvs = [], [], []
    for row in range(steps+1):
        for col in range(steps+1):
            u, v = col/steps, row/steps
            q = shape.face_point(u, v)
            verts.append(q + (q-shape.HEAD_CENTRE).normalized()*lift); uvs.append((u, 1-v))
    for row in range(steps):
        for col in range(steps):
            a = row*(steps+1)+col
            faces.append((a, a+1, a+steps+2, a+steps+1))
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces)
    layer = me.uv_layers.new()
    for poly in me.polygons:
        for li in poly.loop_indices:
            layer.data[li].uv = uvs[me.loops[li].vertex_index]
    o = bpy.data.objects.new(name, me); scene.collection.objects.link(o)
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    out = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
    for n in [n for n in nodes if n.type != 'OUTPUT_MATERIAL']: nodes.remove(n)
    tex = nodes.new('ShaderNodeTexImage'); tex.image = bpy.data.images.load(str(png))
    tex.extension = 'CLIP'
    emit = nodes.new('ShaderNodeEmission'); clear = nodes.new('ShaderNodeBsdfTransparent')
    mix = nodes.new('ShaderNodeMixShader')
    links.new(tex.outputs['Color'], emit.inputs['Color'])
    links.new(tex.outputs['Alpha'], mix.inputs[0])
    links.new(clear.outputs[0], mix.inputs[1]); links.new(emit.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs['Surface'])
    me.materials.append(mat)
    o.parent = rig; o.parent_type = 'BONE'; o.parent_bone = 'head'
    bone = rig.data.bones['head']
    o.matrix_parent_inverse = (rig.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))).inverted()
    return o

# Offset apart: two coincident alpha patches make Cycles skip one of them.
for kind, name, lift in (('eyes', eyes, 0.), ('mouth', mouth, .003)):
    if name != 'none':
        patch('Cara_' + kind, raster(kind + '_' + name), lift)

if pose:
    import model_fixes
    from animation_library import build, FPS
    clip, frame = pose.split(':')
    model_fixes.apply(rig)
    bpy.context.view_layer.objects.active = rig
    build(rig)
    rig.animation_data.action = bpy.data.actions[clip]
    scene.frame_set(int(frame))

for o in bpy.data.objects:
    if o.type in ('MESH', 'LIGHT', 'CAMERA'):
        o.hide_render = o.hide_render and not o.name.startswith('Cara_')
        o.hide_set(False)
cam = scene.camera
def track(o, p):
    o.rotation_euler = (Vector(p)-o.location).to_track_quat('-Z', 'Y').to_euler()
scene.cycles.samples = int(os.environ.get('SAMPLES', '24'))
scene.render.resolution_x = scene.render.resolution_y = int(os.environ.get('RES', '900'))
tag = os.environ.get('TAG', '')
for label, loc, target, ortho in [('front', (0, -12, 3.3), (0, 0, 1.75), 4.6),
                                  ('34', (6.5, -9.5, 4.2), (0, 0, 1.75), 4.6),
                                  ('face', (1.6, -12, 3.3), (0, 0, 2.85), 1.75)]:
    cam.location = loc; track(cam, target); cam.data.ortho_scale = ortho
    scene.render.filepath = str(OUT / f'review_{tag}{label}.png')
    bpy.ops.render.render(write_still=True)
print('REVIEW_DONE', eyes, mouth, pose)
