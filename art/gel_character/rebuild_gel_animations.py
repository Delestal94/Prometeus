"""Rebake animation-only changes into the certified gel LOD geometry.

Run after editing art/rounded_character/animation_library.py:

blender --background --factory-startup --python-exit-code 1 --python \
    art/gel_character/rebuild_gel_animations.py

The full build_gel_body.py remains authoritative for geometry, weights and
LOD generation. This helper deliberately reuses those already-built meshes,
rebakes every action through the same retargeter, exports all three GLBs and
updates only the animation section of the reproducible build report.
"""
import json
import math
import sys
from pathlib import Path

import bpy


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import build_gel_body

OUT = ROOT/'do-not-drop/assets/models/characters/gel'
BLEND = HERE/'gel_body.blend'
MASTER = ROOT/'art/rounded_character/personaje_redondeado.blend'
REPORT = HERE/'gel_body_build_report.json'
MESH_NAMES = ('GelBodyLOD0', 'GelBodyLOD1', 'GelBodyLOD2')


def main():
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    source = bpy.data.objects.get('AuthorSkeleton35')
    rig = bpy.data.objects.get('GelSkeleton')
    assert rig is not None and rig.type == 'ARMATURE'
    meshes = [bpy.data.objects.get(name) for name in MESH_NAMES]
    assert all(obj is not None and obj.type == 'MESH' for obj in meshes)

    # Reload the pristine authoring armature. The saved export blend keeps an
    # evaluated source pose for inspection; reusing it changes pickup reach.
    if source is not None:
        bpy.data.objects.remove(source, do_unlink=True)
    with bpy.data.libraries.load(str(MASTER), link=False) as (available, loaded):
        loaded.objects = list(available.objects)
    source = next(obj for obj in loaded.objects
                  if obj is not None and obj.type == 'ARMATURE')
    bpy.context.collection.objects.link(source)
    source.name = 'AuthorSkeleton35'
    for obj in loaded.objects:
        if obj is not None and obj != source:
            bpy.data.objects.remove(obj, do_unlink=True)

    # The saved export rig retains evaluated pose state. The full builder
    # always bakes into a fresh rig, so mirror that invariant here and reuse
    # the resulting name-bound actions on the existing skinned rig.
    bake_rig = build_gel_body.create_rig(source)
    animation_report = build_gel_body.bake_clips(source, bake_rig)
    bake_data = bake_rig.data
    bpy.data.objects.remove(bake_rig, do_unlink=True)
    bpy.data.armatures.remove(bake_data)
    rig.rotation_euler.z = math.pi
    for action in bpy.data.actions:
        rig.animation_data.action = action
        bpy.context.view_layer.update()
    rig.animation_data.action = bpy.data.actions['Idle']
    bpy.context.scene.frame_set(0)
    OUT.mkdir(parents=True, exist_ok=True)
    for index, obj in enumerate(meshes):
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.export_scene.gltf(
            filepath=str(OUT/f'gel_body_lod{index}.glb'),
            export_format='GLB', use_selection=True, export_skins=True,
            export_morph=True, export_animations=True,
            export_animation_mode='ACTIONS', export_frame_range=False,
            export_force_sampling=True, export_anim_single_armature=True,
            export_apply=False, export_vertex_color='ACTIVE',
            export_extras=True)

    report = json.loads(REPORT.read_text(encoding='utf-8'))
    report['animations'] = animation_report
    REPORT.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    for obj in meshes[1:]:
        obj.hide_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    print('GEL_ANIMATION_REBUILD', json.dumps({
        'clips': len(animation_report['durations']),
        'lods': len(meshes),
        'maximum_unreachable_endpoint_m':
            animation_report['maximum_unreachable_endpoint_m'],
    }))


if __name__ == '__main__':
    main()
