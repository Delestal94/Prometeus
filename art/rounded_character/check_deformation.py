"""Validate actual IK and vertex movement, then render a bent-limb proof pose."""
import bpy, json, math
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(OUT/'personaje_redondeado.blend'))
scene=bpy.context.scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
scene.frame_set(1)

def target(name,delta):
    pb=rig.pose.bones[name]
    matrix=pb.matrix.copy(); matrix.translation+=Vector(delta); pb.matrix=matrix
    bpy.context.view_layer.update()

def evaluated_positions(obj):
    ob=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me=ob.to_mesh(); verts=[v.co.copy() for v in me.vertices]; ob.to_mesh_clear()
    return verts

arm=bpy.data.objects['Brazo y mano.L']
before=evaluated_positions(arm)
# Hands reach forward/inward; left foot lifts, right foot remains planted.
target('CTRL_hand_IK.L',(-.40,-.50,.25))
target('CTRL_hand_IK.R',(.35,-.43,-.25))
target('CTRL_foot_IK.L',(.03,-.19,.17))
after=evaluated_positions(arm)
maxmove=max((a-b).length for a,b in zip(before,after))
assert maxmove>.35, maxmove
errors={}
for side in ['L','R']:
    for end,ctrl in [('forearm','hand'),('shin','foot')]:
        error=(rig.pose.bones[end+'.'+side].tail-rig.pose.bones['CTRL_'+ctrl+'_IK.'+side].head).length
        errors[end+'.'+side]=error
assert max(errors.values())<.012,errors
for o in scene.objects:
    if o.type=='MESH' and o.parent==rig:
        verts=evaluated_positions(o)
        assert all(math.isfinite(c) for v in verts for c in v),o.name

report=json.loads((OUT/'validation.json').read_text())
report['pose_test']={'ik_endpoint_errors_m':errors,'max_arm_vertex_motion_m':maxmove,'finite_deformation':True}
(OUT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
scene.render.resolution_x=1100; scene.render.resolution_y=1100
scene.cycles.samples=32
scene.render.filepath=str(OUT/'preview_pose_rig.png')
bpy.ops.render.render(write_still=True)
# This demonstration remains separate; the delivered .blend opens in rest pose.
print('POSE_CHECK_PASS',json.dumps(report['pose_test']))
