"""Validate S-311.12 authoring topology and pairwise morph extremes.

blender --background --factory-startup --python-exit-code 1 --python \
  art/gel_character/validate_gel_topology.py

The 243 states per authoring LOD cover Basis, every single extreme and every
pair of simultaneous extremes.  This is a deterministic finite gate, not a
mathematical proof over the continuous eleven-dimensional morph space.
"""
import json
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import build_gel_body as body
from gel_body_topology import assert_topology_report, topology_report
from gel_body_validation import candidate_pairs, dot, normal, triangle_intersection


def pairwise_extreme_samples():
    samples = [('Basis', [0.] * len(body.MORPHS))]
    for index, name in enumerate(body.MORPHS):
        for value in (-1., 1.):
            weights = [0.] * len(body.MORPHS)
            weights[index] = value
            samples.append((f'{name}:{value:+g}', weights))
    for first in range(len(body.MORPHS)):
        for second in range(first + 1, len(body.MORPHS)):
            for a in (-1., 1.):
                for b in (-1., 1.):
                    weights = [0.] * len(body.MORPHS)
                    weights[first], weights[second] = a, b
                    samples.append((
                        f'{body.MORPHS[first]}:{a:+g},{body.MORPHS[second]}:{b:+g}',
                        weights))
    return samples


def validate_morph_pairs(obj):
    obj.data.calc_loop_triangles()
    faces = [tuple(face.vertices) for face in obj.data.loop_triangles]
    base = [tuple(vertex.co) for vertex in obj.data.vertices]
    deltas = [[tuple(body.morph_delta(vertex.co, name))
               for vertex in obj.data.vertices] for name in body.MORPHS]
    base_normals = [normal([base[index] for index in face]) for face in faces]
    samples = pairwise_extreme_samples()
    for sample_index, (name, weights) in enumerate(samples):
        points = [tuple(point[axis] + sum(
            weights[morph] * deltas[morph][vertex][axis]
            for morph in range(len(weights))) for axis in range(3))
            for vertex, point in enumerate(base)]
        triangles = [[points[index] for index in face] for face in faces]
        for face_index, triangle in enumerate(triangles):
            changed = normal(triangle)
            if dot(changed, changed) <= 1e-20 or dot(changed, base_normals[face_index]) <= 0.:
                return {
                    'valid': False, 'samples_checked': sample_index + 1,
                    'failed_sample': name, 'failure': 'degenerate_or_reoriented_face',
                    'face': face_index,
                }
        for first, second in candidate_pairs(triangles):
            if len(set(faces[first]) & set(faces[second])) >= 2:
                continue
            if triangle_intersection(triangles[first], triangles[second]):
                return {
                    'valid': False, 'samples_checked': sample_index + 1,
                    'failed_sample': name, 'failure': 'self_intersection',
                    'faces': [first, second],
                }
    return {'valid': True, 'samples_checked': len(samples)}


def validate():
    lods, errors = [], []
    for level in (2, 1):
        obj = body.make_body(level)
        topology = topology_report(obj, body.MORPHS, body.morph_delta)
        try:
            assert_topology_report(topology)
        except AssertionError as error:
            errors.append(f'LOD{2-level} topology: {error}')
        morphs = validate_morph_pairs(obj)
        if not morphs['valid']:
            errors.append(f'LOD{2-level} morphs: {morphs}')
        lods.append({'lod': 2-level, 'topology': topology,
                     'pairwise_morph_extremes': morphs})
    return {
        'schema_version': 1,
        'scope': 'quad authoring LOD0/LOD1; LOD2 remains a derived runtime simplification',
        'morph_gate': ('Basis, 22 single extremes and 220 pairwise extremes per LOD; '
                       'finite deterministic coverage, not a continuous-space proof'),
        'valid': not errors,
        'errors': errors,
        'lods': lods,
    }


def main():
    report = validate()
    encoded = json.dumps(report, indent=2) + '\n'
    output = HERE/'review_bloque_b/topology_report.json'
    output.write_text(encoded, encoding='utf-8')
    print(encoded, end='')
    return 0 if report['valid'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
