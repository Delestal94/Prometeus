"""Reproduce the Delgada/reference front-silhouette comparison in Blender.

blender --background --factory-startup --python-exit-code 1 --python art/gel_character/compare_delgada_silhouette.py
"""
from array import array
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import build_gel_body as body_source

REFERENCE = HERE / 'referencia/referencia_frente.jpg'
REFERENCE_MASK = HERE / 'referencia/silueta_mascara.png'
OUT = HERE / 'review_bloque_b'
WIDTH, HEIGHT = 832, 1248
MIN_IOU = .84
REFERENCE_POSE = {'upper_arm_degrees': 100, 'forearm_degrees': -25,
                  'hand_degrees': 20}


def reference_mask():
    image = bpy.data.images.load(str(REFERENCE_MASK), check_existing=False)
    image.colorspace_settings.name = 'Non-Color'
    pixels = image.pixels[:]
    mask = bytearray(WIDTH*HEIGHT)
    for y in range(HEIGHT):
        source_y = HEIGHT-1-y
        for x in range(WIDTH):
            index = (source_y*WIDTH+x)*4
            mask[y*WIDTH+x] = pixels[index] >= .5
    bpy.data.images.remove(image)
    return mask


def rotate_at_head(rig, name, degrees, sign):
    bone = rig.pose.bones[name]
    pivot = bone.head.copy()
    bone.matrix = (Matrix.Translation(pivot)
                   @ Matrix.Rotation(math.radians(degrees)*sign, 4, 'Y')
                   @ Matrix.Translation(-pivot) @ bone.matrix)


def evaluated_surface():
    master = ROOT / 'art/rounded_character/personaje_redondeado.blend'
    bpy.ops.wm.open_mainfile(filepath=str(master))
    source = next(obj for obj in bpy.data.objects if obj.type == 'ARMATURE')
    for obj in list(bpy.data.objects):
        if obj != source:
            bpy.data.objects.remove(obj, do_unlink=True)
    body = body_source.make_body(2)
    rig = body_source.create_rig(source)
    body_source.assign_weights(body, rig)
    for side, sign in (('L', 1), ('R', -1)):
        rotate_at_head(rig, 'upper_arm.'+side,
                       REFERENCE_POSE['upper_arm_degrees'], sign)
    bpy.context.view_layer.update()
    for side, sign in (('L', 1), ('R', -1)):
        rotate_at_head(rig, 'forearm.'+side,
                       REFERENCE_POSE['forearm_degrees'], sign)
    bpy.context.view_layer.update()
    for side, sign in (('L', 1), ('R', -1)):
        rotate_at_head(rig, 'hand.'+side,
                       REFERENCE_POSE['hand_degrees'], sign)
    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.data
    mesh.calc_loop_triangles()
    points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    faces = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
    return body_source.measured_proportions(body), points, faces


def rasterize(points, faces, reference):
    occupied = [index for index, value in enumerate(reference) if value]
    xs = [index % WIDTH for index in occupied]
    ys = [index // WIDTH for index in occupied]
    box = (min(xs), min(ys), max(xs), max(ys))
    scale = (box[3]-box[1]+1)/1.74
    center_x = (box[0]+box[2])/2
    projected = [(center_x+point.x*scale, box[3]-point.z*scale)
                 for point in points]
    mask = bytearray(WIDTH*HEIGHT)
    for face in faces:
        triangle = [projected[index] for index in face]
        minimum = max(0, math.floor(min(point[1] for point in triangle)))
        maximum = min(HEIGHT-1, math.ceil(max(point[1] for point in triangle)))
        for y in range(minimum, maximum+1):
            scan = y+.5
            crossings = []
            for first, second in zip(triangle, triangle[1:]+triangle[:1]):
                if ((first[1] <= scan < second[1])
                        or (second[1] <= scan < first[1])):
                    crossings.append(first[0] + (second[0]-first[0])
                                     *(scan-first[1])/(second[1]-first[1]))
            if len(crossings) >= 2:
                start = max(0, math.ceil(min(crossings)-.5))
                end = min(WIDTH-1, math.floor(max(crossings)-.5))
                if end >= start:
                    mask[y*WIDTH+start:y*WIDTH+end+1] = b'\1'*(end-start+1)
    return mask, box, scale


def save_overlay(reference, model):
    pixels = array('f', [1.])*(WIDTH*HEIGHT*4)
    colors = {(1, 1): (.18, .18, .18), (1, 0): (0., .70, 1.),
              (0, 1): (1., 0., .65)}
    for y in range(HEIGHT):
        for x in range(WIDTH):
            color = colors.get((reference[y*WIDTH+x], model[y*WIDTH+x]))
            if color is None:
                continue
            index = ((HEIGHT-1-y)*WIDTH+x)*4
            pixels[index:index+3] = array('f', color)
    image = bpy.data.images.new('DelgadaSilhouetteOverlay', WIDTH, HEIGHT)
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(OUT/'delgada_silhouette_overlay.png')
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)


def main():
    reference = reference_mask()
    proportions, points, faces = evaluated_surface()
    model, box, scale = rasterize(points, faces, reference)
    intersection = sum(a and b for a, b in zip(reference, model))
    union = sum(a or b for a, b in zip(reference, model))
    report = {'reference': str(REFERENCE.relative_to(ROOT)).replace('\\', '/'),
              'reference_box_px': box, 'scale_px_per_m': scale,
              'pose': REFERENCE_POSE, 'minimum_iou': MIN_IOU,
              'iou': intersection/union, 'intersection_px': intersection,
              'union_px': union, 'reference_area_px': sum(reference),
              'model_area_px': sum(model), 'measured_proportions': proportions}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'delgada_silhouette_report.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    save_overlay(reference, model)
    print('DELGADA_SILHOUETTE', json.dumps(report))
    assert report['iou'] >= MIN_IOU, report


if __name__ == '__main__':
    main()
