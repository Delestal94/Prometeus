"""Measure source geometry independently, never certify the future gel shader.

Run: blender --background --factory-startup --python analyze_gel_body.py --
     --blend art/gel_character/gel_body.blend
UV stretch is physical surface change relative to Basis, not merely fixed UVs.
Thickness is the inward opposite-surface ray from each triangle centroid, metres.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def subtract(a, b):
    return tuple(x-y for x, y in zip(a, b))


def triangle_stretch(base, changed):
    """Singular values of the tangent deformation, independent of orientation."""
    a, b = subtract(base[1], base[0]), subtract(base[2], base[0])
    c, d = subtract(changed[1], changed[0]), subtract(changed[2], changed[0])
    aa, ab, bb = dot(a, a), dot(a, b), dot(b, b)
    cc, cd, dd = dot(c, c), dot(c, d), dot(d, d)
    determinant = aa*bb-ab*ab
    if determinant <= 1e-20:
        raise ValueError('Degenerate reference triangle')
    trace = (bb*cc+aa*dd-2*ab*cd)/determinant
    det = (cc*dd-cd*cd)/determinant
    disc = max(0., trace*trace-4*det)
    return math.sqrt(max(0., (trace-math.sqrt(disc))/2)), math.sqrt(max(0., (trace+math.sqrt(disc))/2))


def summarize(values):
    valid = sorted(v for v in values if v is not None)
    return {'samples': len(values), 'missing': len(values)-len(valid),
            'min_m': valid[0] if valid else None,
            'max_m': valid[-1] if valid else None,
            'mean_m': sum(valid)/len(valid) if valid else None}


def correction_fit(base, positive, negative):
    coefficients, errors = [], []
    for b, p, n in zip(base, positive, negative):
        if b is None or p is None or n is None:
            coefficients.append(None)
            continue
        coefficient = (p-n)/2
        coefficients.append(coefficient)
        errors.extend((abs(b+coefficient-p), abs(b-coefficient-n)))
    return {'coefficients_m': coefficients,
            'max_extreme_error_m': max(errors) if errors else None,
            'mean_extreme_error_m': sum(errors)/len(errors) if errors else None,
            'valid_samples': len(coefficients)-coefficients.count(None)}


def ray_thickness(coords, faces):
    from mathutils.bvhtree import BVHTree
    from mathutils import Vector
    tree = BVHTree.FromPolygons(coords, faces, all_triangles=True)
    values = []
    epsilon = 1e-6
    for face in faces:
        a, b, c = (coords[i] for i in face)
        normal = (b-a).cross(c-a)
        if normal.length < 1e-12:
            values.append(None)
            continue
        normal.normalize()
        origin = (a+b+c)/3-normal*epsilon
        hit, _, _, distance = tree.ray_cast(origin, -normal, 5.)
        values.append(distance+epsilon if hit is not None and distance > epsilon else None)
    return values


def measure_uv(base, coords, faces):
    stretches = [triangle_stretch([base[i] for i in f], [coords[i] for i in f]) for f in faces]
    scale = [max(abs(a-1), abs(b-1)) for a, b in stretches]
    aniso = [b/a-1 if a > 1e-10 else float('inf') for a, b in stretches]
    return {'max_relative_scale_change': max(scale),
            'max_relative_anisotropy_change': max(aniso),
            'triangles_over_15_percent': sum(max(s, a) > .15+1e-9 for s, a in zip(scale, aniso)),
            'passes_15_percent': max(max(scale), max(aniso)) <= .15+1e-9}


def write_map(mesh, thickness, path, width=1024):
    """Raster actual UV triangle atlas; missing rays remain transparent, never zero."""
    import bpy
    pixels = [0.]*(width*width*4)
    uv = mesh.uv_layers.active.data
    normalization_m = 2.
    for triangle, value in zip(mesh.loop_triangles, thickness):
        if value is None:
            continue
        points = [tuple(uv[i].uv) for i in triangle.loops]
        a, b, c = points
        det = (b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1])
        if abs(det) < 1e-16:
            raise ValueError('Degenerate UV triangle')
        low_x = max(0, int(min(p[0] for p in points)*width))
        high_x = min(width-1, math.ceil(max(p[0] for p in points)*width))
        low_y = max(0, int(min(p[1] for p in points)*width))
        high_y = min(width-1, math.ceil(max(p[1] for p in points)*width))
        for y in range(low_y, high_y+1):
            for x in range(low_x, high_x+1):
                px, py = (x+.5)/width-a[0], (y+.5)/width-a[1]
                u = (px*(c[1]-a[1])-py*(c[0]-a[0]))/det
                v = ((b[0]-a[0])*py-(b[1]-a[1])*px)/det
                if u >= -1e-9 and v >= -1e-9 and u+v <= 1+1e-9:
                    start = (y*width+x)*4
                    pixels[start:start+4] = [min(1., value/normalization_m)]*3+[1.]
    image = bpy.data.images.new('MeasuredGelThickness', width, width, alpha=True, float_buffer=False)
    image.colorspace_settings.name = 'Non-Color'
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path.resolve())
    image.file_format = 'PNG'
    image.save()
    return {'path': path.name, 'resolution': [width, width],
            'decode_metres': 'red * 2.0', 'ray_missing_alpha': 0,
            'quantization_max_error_m': normalization_m/510,
            'clipped_samples': sum(v is not None and v > normalization_m for v in thickness)}


def core_experiment(obj, base, faces, output):
    """Separate 3 mm offset candidate; retain weights/morphs, never activate it."""
    import bpy
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    offset = .003

    def shrink(coords):
        normals = [Vector() for _ in coords]
        for a, b, c in faces:
            normal = (coords[b]-coords[a]).cross(coords[c]-coords[a])
            for i in (a, b, c):
                normals[i] += normal
        return [v-normal.normalized()*offset for v, normal in zip(coords, normals)]

    def containment(outer, inner):
        tree = BVHTree.FromPolygons(outer, faces, all_triangles=True)
        # Nearest-oriented-surface test: local containment, not a global proof.
        outside = 0
        minimum = float('inf')
        for point in inner:
            hit, normal, _, distance = tree.find_nearest(point)
            if hit is None or (point-hit).dot(normal) > 1e-7:
                outside += 1
            if hit is not None:
                minimum = min(minimum, distance)
        return {'outside_or_missing_vertices': outside, 'minimum_separation_m': minimum,
                'method': 'nearest oriented surface per vertex; full global self-intersection certification deferred'}

    keys = obj.data.shape_keys.key_blocks
    small_base = shrink(base)
    candidate = obj.copy()
    candidate.data = obj.data.copy()
    candidate.name = 'GelCoreExperiment'
    bpy.context.collection.objects.link(candidate)
    inverse = obj.matrix_world.inverted()
    for v, point in zip(candidate.data.shape_keys.key_blocks['Basis'].data, small_base):
        v.co = inverse @ point
    report = {'selected_for_final': False, 'offset_m': offset,
              'same_topology_morphs_weights': True, 'outer_triangles': len(faces),
              'core_triangles': len(faces), 'combined_triangles': 2*len(faces),
              'combined_exceeds_lod0_6000': 2*len(faces) > 6000,
              'estimated_body_drawcalls': 2, 'gpu_measured': False,
              'selection_requires_D_E': True, 'containment': {'Basis': containment(base, small_base)}}
    for key in keys:
        if key.name == 'Basis':
            continue
        positive = [obj.matrix_world @ v.co for v in key.data]
        small_positive = shrink(positive)
        target = candidate.data.shape_keys.key_blocks[key.name]
        for v, point in zip(target.data, small_positive):
            v.co = inverse @ point
        report['containment'][key.name+':1'] = containment(positive, small_positive)
        negative = [2*b-p for b, p in zip(base, positive)]
        small_negative = [2*b-p for b, p in zip(small_base, small_positive)]
        report['containment'][key.name+':-1'] = containment(negative, small_negative)
    # Offset preserves index connectivity, but that is not proof of geometric validity.
    report['geometric_self_intersection_certified'] = False
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    candidate.select_set(True)
    rig = obj.find_armature()
    if rig is not None:
        rig.select_set(True)
    bpy.context.view_layer.objects.active = candidate
    bpy.ops.export_scene.gltf(filepath=str(output/'core_experiment.glb'),
        export_format='GLB', use_selection=True, export_skins=True,
        export_morph=True, export_animations=False, export_apply=False,
        export_vertex_color='ACTIVE')
    (output/'core_experiment_report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    bpy.data.objects.remove(candidate, do_unlink=True)
    return {k:v for k,v in report.items() if k != 'containment'}


def main():
    import bpy
    argv = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    here = Path(__file__).resolve().parent
    parser.add_argument('--blend', type=Path, default=here/'gel_body.blend')
    parser.add_argument('--output', type=Path, default=here/'review_bloque_b')
    parser.add_argument('--core-experiment', action='store_true')
    args = parser.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=str(args.blend.resolve()))
    obj = bpy.data.objects.get('GelBodyLOD0')
    if obj is None:
        raise ValueError('Expected GelBodyLOD0 source mesh')
    mesh = obj.data
    mesh.calc_loop_triangles()
    faces = [tuple(t.vertices) for t in mesh.loop_triangles]
    keys = mesh.shape_keys.key_blocks
    base = [obj.matrix_world @ v.co for v in keys['Basis'].data]
    base_thickness = ray_thickness(base, faces)
    report = {'object': obj.name, 'triangles': len(faces), 'units': 'metres',
              'source_blend_sha256': hashlib.sha256(args.blend.read_bytes()).hexdigest(),
              'blender_version': bpy.app.version_string,
              'thickness_sampling': 'all triangle centroids inward normal rays, not vertex baking',
              'basis': {'thickness': summarize(base_thickness)},
              'uv_metric': 'tangent deformation singular values relative to Basis; scale=max(abs(s-1)); anisotropy=smax/smin-1',
              'extremes': {}, 'shader_correction': {
                  'implemented': False, 'status': 'unvalidated_linear_candidate_not_ready_for_D',
                  'contract': 'candidate t(UV,w)=t_base(UV)+sum(w_i*c_i(UV)); errors below are measured, not acceptance; no claim for combined morphs',
                  'indexing': 'coefficient array indexed by source mesh loop-triangle, same UV as thickness.png',
                  'maps_required_in_D': 'bake each coefficient field to signed texture array or shader-readable atlas; fit is evidence only',
                  'all_morphs': {}, 'acceptance': 'D must independently compare integrated shader with ray reference, including clipping and alpha'}}
    for key in keys:
        if key.name == 'Basis':
            continue
        delta = [obj.matrix_world.to_3x3() @ (v.co-b.co) for v, b in zip(key.data, keys['Basis'].data)]
        extremes = []
        for sign in (-1, 1):
            coords = [b+sign*d for b, d in zip(base, delta)]
            values = ray_thickness(coords, faces)
            report['extremes'][key.name+':'+str(sign)] = {
                'thickness': summarize(values), 'uv': measure_uv(base, coords, faces)}
            extremes.append(values)
        report['shader_correction']['all_morphs'][key.name] = correction_fit(base_thickness, extremes[1], extremes[0])
    report['uv_passes_15_percent'] = all(e['uv']['passes_15_percent'] for e in report['extremes'].values())
    report['shader_correction']['maximum_single_extreme_error_m'] = max(
        c['max_extreme_error_m'] for c in report['shader_correction']['all_morphs'].values()
        if c['max_extreme_error_m'] is not None)
    args.output.mkdir(parents=True, exist_ok=True)
    report['thickness_map'] = write_map(mesh, base_thickness, args.output/'thickness.png')
    if args.core_experiment:
        report['core_experiment'] = core_experiment(obj, base, faces, args.output)
    # Deterministic JSON; raw coefficients retained, not replaced with a success flag.
    (args.output/'geometry_metrics.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({'basis': report['basis'], 'uv_passes_15_percent': report['uv_passes_15_percent'],
                      'extremes_measured': len(report['extremes'])}, indent=2))


if __name__ == '__main__':
    main()
