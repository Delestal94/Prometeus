"""Validate actual IK and vertex movement, then render a bent-limb proof pose.
Last, check the shorts crotch in the clips (model_fixes.py weights).

  blender --background --factory-startup --python check_deformation.py [-- --crotch-only]

--crotch-only skips the IK test and its Cycles render.
"""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent
CROTCH_ONLY='--crotch-only' in sys.argv

def crotch_check():
    """Shorts crotch with the export's weights, in every clip.

    With both thighs up (Sit) the crotch used to stay on the pelvis and hang
    between the knees as a pointed fold. Two measures on the full-resolution
    shorts (the export decimates them, but the fold was in the weights):
    - sag: how far the crotch midline hangs below the plane of both thighs,
      minus how far the cuffs' underside does. Before the fix +0.014 (the
      crotch hung past the cuffs), after about -0.07.
    - fold: largest angle between the normals of neighbouring faces at the
      bottom of the crotch (rest |x|<0.2, z<0.72), every 6th frame of each
      clip. Before: Sit 77 deg, Walk 62, PickUpPackage 60, Stroll 40; after:
      Sit 23, Walk 48, Stroll 53 (a crease between the legs, not visible),
      the rest 26 (the seam's own curve at rest).
    """
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'personaje_redondeado.blend'))
    sys.path.insert(0, str(OUT))
    import model_fixes
    from animation_library import build, FPS, DURATIONS
    scene=bpy.context.scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    model_fixes.apply(rig)
    bpy.context.view_layer.objects.active=rig
    build(rig)
    shorts=next(o for o in scene.objects if o.name.startswith('Short · pieza'))
    cuff=next(o for o in scene.objects if o.name.startswith('Short · vuelta.'))
    rest=[v.co.copy() for v in shorts.data.vertices]
    bottom=lambda co: abs(co.x)<.2 and co.z<.72
    midline=[i for i,co in enumerate(rest) if abs(co.x)<.03 and co.z<.9]
    def evaluated(obj):
        ob=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me=ob.to_mesh(); bm=bmesh.new(); bm.from_mesh(me); ob.to_mesh_clear()
        return bm
    def fold():
        bm=evaluated(shorts); bm.normal_update()
        worst=max((math.degrees(e.link_faces[0].normal.angle(e.link_faces[1].normal,0.))
                   for e in bm.edges if len(e.link_faces)==2 and all(bottom(rest[v.index]) for v in e.verts)), default=0.)
        bm.free(); return worst
    def sag():
        pb=rig.pose.bones; M=rig.matrix_world
        a,b,c=M@pb['thigh.L'].head, M@pb['thigh.L'].tail, M@pb['thigh.R'].head
        n=(b-a).cross(c-a).normalized()
        if n.z>0: n=-n
        bm=evaluated(shorts); bm.verts.ensure_lookup_table()
        crotch=max((M@bm.verts[i].co)@n for i in midline)-a@n; bm.free()
        bm=evaluated(cuff); under=max((M@v.co)@n for v in bm.verts)-a@n; bm.free()
        return crotch-under
    folds={}
    for act in DURATIONS:
        rig.animation_data.action=bpy.data.actions[act]
        for f in range(0, round(DURATIONS[act]*FPS)+1, 6):
            scene.frame_set(f)
            folds[act]=max(folds.get(act,0.), fold())
    rig.animation_data.action=bpy.data.actions['Sit']
    sit_sag=[]
    for f in range(0, round(DURATIONS['Sit']*FPS)+1, 12):
        scene.frame_set(f); sit_sag.append(sag())
    result={'crotch_fold_deg':{k:round(v,1) for k,v in folds.items()},'sit_crotch_sag_m':round(max(sit_sag),3)}
    assert folds['Sit']<40, result
    assert max(folds.values())<58, result
    assert max(sit_sag)<-.03, result
    return result

if CROTCH_ONLY:
    report=json.loads((OUT/'validation.json').read_text())
    report['crotch_test']=crotch_check()
    (OUT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print('CROTCH_CHECK_PASS',json.dumps(report['crotch_test']))
    sys.exit(0)
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
report['crotch_test']=crotch_check()
(OUT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('CROTCH_CHECK_PASS',json.dumps(report['crotch_test']))
