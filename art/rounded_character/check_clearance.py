"""Arms against the tummy: how many arm/hand vertices end up inside the
T-shirt in each clip, with the export's weights (model_fixes.py).

  blender --background --factory-startup -noaudio --python check_clearance.py [-- Clip ...]

Every 4th frame, every 3rd forearm/hand vertex; a vertex counts when it is more than
DEPTH behind the nearest shirt surface. Prints the worst frame per clip and
writes clearance_check into validation.json.
"""
import bpy, json, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
DEPTH = .01
only = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []

bpy.ops.wm.open_mainfile(filepath=str(HERE/'personaje_redondeado.blend'))
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
sys.path.insert(0, str(HERE))
import model_fixes
from animation_library import build, DURATIONS, FPS
scene = bpy.context.scene
rig = next(o for o in scene.objects if o.type == 'ARMATURE')
model_fixes.apply(rig)
bpy.context.view_layer.objects.active = rig
build(rig)
shirt = next(o for o in scene.objects if o.name.startswith('Camiseta · cuerpo'))
arms = [o for o in scene.objects if o.name.startswith('Brazo y mano')]
# Below the sleeve cuff only: the upper arm sits inside the sleeve on purpose.
bare = {o.name: [v.index for v in o.data.vertices if abs(v.co.x) > 1.2][::3] for o in arms}

def inside_count():
    dg = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(shirt, dg)
    count = 0
    for arm in arms:
        ev = arm.evaluated_get(dg); me = ev.to_mesh()
        for i in bare[arm.name]:
            v = me.vertices[i]
            loc, normal, _, _ = tree.find_nearest(v.co)
            if loc is not None and (v.co-loc).dot(normal) < -DEPTH:
                count += 1
        ev.to_mesh_clear()
    return count

report = {}
for clip, duration in DURATIONS.items():
    if only and clip not in only:
        continue
    rig.animation_data.action = bpy.data.actions[clip]
    worst = (0, 0); total = 0
    for frame in range(0, round(duration*FPS)+1, 4):
        scene.frame_set(frame)
        n = inside_count(); total += n
        worst = max(worst, (n, frame))
    report[clip] = {'worst_vertices': worst[0], 'worst_frame': worst[1], 'sum': total}
    print('CLEARANCE', clip, report[clip], flush=True)
path = HERE/'validation.json'
data = json.loads(path.read_text(encoding='utf8')) if path.exists() else {}
data['clearance_check'] = report
path.write_text(json.dumps(data, indent=2), encoding='utf8')
