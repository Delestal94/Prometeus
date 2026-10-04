"""Finite exported-GLB animation samples; not continuous pose/morph approval.

Run via check(path, lod). Uses glTF LINEAR quaternion SLERP and STEP sampling,
actual hierarchy/inverse binds, and transported normals rather than rest-facing
normals (a rigid 180-degree rotation must not be mistaken for a surface fold).
"""
import bisect
import math
from pathlib import Path

from validate_glb import Asset
from gel_body_validation import (matrix, multiply, transform, normal, dot,
                                 candidate_pairs, triangle_intersection)


def finite(values):
    if not all(math.isfinite(x) for x in values):
        raise ValueError('Nonfinite pose data')


def quaternion(q):
    finite(q)
    if len(q) != 4 or sum(x*x for x in q) < 1e-20:
        raise ValueError('Invalid quaternion')
    length = math.sqrt(sum(x*x for x in q))
    return tuple(x/length for x in q)


def sample_channel(times, values, time, path, interpolation='LINEAR'):
    """Clamp endpoints; interpolate rotation on the normalized shortest arc."""
    finite(times)
    finite([time])
    if not times or len(times) != len(values) or any(
            a >= b for a, b in zip(times, times[1:])):
        raise ValueError('Invalid animation time/output sequence')
    if interpolation not in ('LINEAR', 'STEP'):
        raise ValueError('Unsupported animation interpolation: '+interpolation)
    width = 4 if path == 'rotation' else 3
    if path not in ('translation', 'rotation', 'scale'):
        raise ValueError('Unsupported animation target: '+path)
    for value in values:
        finite(value)
        if len(value) != width:
            raise ValueError('Animation output width mismatch')
        if path == 'rotation':
            quaternion(value)
    index = max(0, min(len(times)-1, bisect.bisect_right(times, time)-1))
    first = quaternion(values[index]) if path == 'rotation' else values[index]
    if index == len(times)-1 or time <= times[0] or interpolation == 'STEP':
        return tuple(first)
    amount = (time-times[index])/(times[index+1]-times[index])
    second = values[index+1]
    if path != 'rotation':
        return tuple(a+(b-a)*amount for a, b in zip(first, second))
    second = quaternion(second)
    cosine = dot(first, second)
    if cosine < 0:
        second = tuple(-x for x in second)
        cosine = -cosine
    if cosine > .9995:
        return quaternion(tuple(a+(b-a)*amount for a, b in zip(first, second)))
    angle = math.acos(min(1., cosine))
    left = math.sin((1-amount)*angle)/math.sin(angle)
    right = math.sin(amount*angle)/math.sin(angle)
    return quaternion(tuple(a*left+b*right for a, b in zip(first, second)))


def normal_matrix(m):
    """Inverse-transpose of a blended 3x3; singular skinning is invalid."""
    a, b, c = [row[:3] for row in m[:3]]
    from gel_body_validation import cross
    cofactors = [cross(b, c), cross(c, a), cross(a, b)]
    determinant = dot(a, cofactors[0])
    if not math.isfinite(determinant) or abs(determinant) < 1e-12:
        raise ValueError('Singular blended skin matrix')
    return [[x/determinant for x in row] for row in cofactors]


def pose_surface(points, faces, joints, weights, transforms, trajectory_keys):
    """Return concrete whole-surface contacts and conservative local folds."""
    if not (len(points) == len(joints) == len(weights) == len(trajectory_keys)):
        raise ValueError('Skin attribute counts mismatch')
    for m in transforms:
        finite([x for row in m for x in row])
    posed, normals, mapping, welded = [], [], [], {}
    for p, js, ws, key in zip(points, joints, weights, trajectory_keys):
        finite(p)
        finite(ws)
        if len(p) != 3 or len(js) != 4 or len(ws) != 4 or any(w < 0 for w in ws):
            raise ValueError('Invalid four-slot skin weights/position')
        if abs(sum(ws)-1.) > 1e-4:
            raise ValueError('Skin weights must sum to one')
        if any(not isinstance(j, int) or j < 0 or j >= len(transforms) for j in js):
            raise ValueError('Skin joint index out of range')
        blend = [[sum(transforms[j][r][c]*w for j, w in zip(js, ws))
                  for c in range(4)] for r in range(4)]
        posed.append(transform(blend, p))
        normals.append(normal_matrix(blend))
        if key not in welded:
            welded[key] = len(welded)
        mapping.append(welded[key])
    if any(len(face) != 3 or any(not isinstance(i, int) or i < 0 or i >= len(points)
                               for i in face) for face in faces):
        raise ValueError('Triangle index out of range')
    topology = [tuple(mapping[i] for i in face) for face in faces]
    triangles = [[posed[i] for i in face] for face in faces]
    contacts = [(i, j) for i, j in candidate_pairs(triangles)
                if len(set(topology[i]) & set(topology[j])) < 2
                and triangle_intersection(triangles[i], triangles[j])]
    flipped = []
    for index, face in enumerate(faces):
        rest = normal([points[i] for i in face])
        expected = tuple(sum(sum(normals[i][axis][k]*rest[k] for k in range(3))
                             for i in face) for axis in range(3))
        actual = normal(triangles[index])
        if math.sqrt(dot(actual, actual)) < 1e-10 or dot(actual, expected) <= 0:
            flipped.append(index)
    return contacts, flipped


def check(path, lod, fractions=(0., .25, .5, .75, 1.), morph_weights=None):
    """Validate finite samples of every supplied GLB clip; return errors/report."""
    try:
        return check_asset(Asset(Path(path)), lod, fractions, morph_weights)
    except (ValueError, KeyError, IndexError, TypeError, OSError) as error:
        return [str(error)], {'lod': lod, 'samples': [], 'scope': 'finite samples only'}


def check_asset(asset, lod, fractions=(0., .25, .5, .75, 1.), morph_weights=None):
    errors = []
    report = {'lod': lod, 'samples': [], 'scope':
              'all supplied clips at listed fractions and fixed morph weights; '
              'not continuous pose/morph proof or visual approval',
              'orientation_criterion': 'face normal dot inverse-transpose '
              'transported per-vertex local normals > 0 (conservative fold gate)'}
    try:
        finite(fractions)
        if not fractions or any(f < 0 or f > 1 for f in fractions):
            raise ValueError('Fractions must be nonempty and within [0,1]')
        doc = asset.data
        original = doc['nodes']
        parents = {}
        for parent, node in enumerate(original):
            for child in node.get('children', []):
                if not isinstance(child, int) or not 0 <= child < len(original) or child in parents:
                    raise ValueError('Invalid node hierarchy')
                parents[child] = parent
        mesh_nodes = [n for n in original if 'mesh' in n]
        if len(mesh_nodes) != 1:
            raise ValueError('Pose checker requires one skinned mesh node')
        node = mesh_nodes[0]
        skin = doc['skins'][node['skin']]
        primitives = doc['meshes'][node['mesh']]['primitives']
        if len(primitives) != 1:
            raise ValueError('Pose checker requires one triangle primitive')
        primitive = primitives[0]
        if primitive.get('mode', 4) != 4:
            raise ValueError('Pose checker requires triangles')
        attrs = primitive['attributes']
        raw = asset.accessor(attrs['POSITION'])
        joints = asset.accessor(attrs['JOINTS_0'])
        weights = asset.accessor(attrs['WEIGHTS_0'])
        deltas = [asset.accessor(t['POSITION']) for t in primitive.get('targets', [])]
        morphs = list(morph_weights) if morph_weights is not None else list(
            node.get('weights', doc['meshes'][node['mesh']].get('weights', [0.]*len(deltas))))
        finite(morphs)
        if len(morphs) != len(deltas) or any(len(d) != len(raw) for d in deltas):
            raise ValueError('Morph counts mismatch')
        for delta in deltas:
            for p in delta:
                finite(p)
                if len(p) != 3:
                    raise ValueError('Invalid morph position width')
        points = [tuple(p[a]+sum(d[i][a]*w for d, w in zip(deltas, morphs))
                        for a in range(3)) for i, p in enumerate(raw)]
        # Raw trajectory equality only; neither rounding nor spatial tolerance.
        keys = []
        for i, p in enumerate(raw):
            trajectory = {}
            for joint, weight in zip(joints[i], weights[i]):
                if weight > 0:
                    trajectory[joint] = trajectory.get(joint, 0.)+weight
            keys.append((tuple(p), tuple(tuple(d[i]) for d in deltas),
                         tuple(sorted(trajectory.items()))))
        indices = [row[0] for row in asset.accessor(primitive['indices'])]
        if len(indices) % 3:
            raise ValueError('Triangle index count mismatch')
        faces = [tuple(indices[i:i+3]) for i in range(0, len(indices), 3)]
        identity = matrix({})
        binds = asset.accessor(skin['inverseBindMatrices']) if 'inverseBindMatrices' in skin else [
            tuple(identity[i][j] for j in range(4) for i in range(4)) for _ in skin['joints']]
        if len(binds) != len(skin['joints']):
            raise ValueError('Inverse bind count mismatch')
        if not doc.get('animations'):
            raise ValueError('Pose checker requires animation clips')
        for animation in doc['animations']:
            channels, starts, ends = [], [], []
            for channel in animation['channels']:
                sampler = animation['samplers'][channel['sampler']]
                times = [row[0] for row in asset.accessor(sampler['input'])]
                values = asset.accessor(sampler['output'])
                target = channel['target']
                index = target['node']
                if not isinstance(index, int) or not 0 <= index < len(original) or 'matrix' in original[index]:
                    raise ValueError('Animation target node invalid or matrix-authored')
                interpolation = sampler.get('interpolation', 'LINEAR')
                sample_channel(times, values, 0., target['path'], interpolation)
                channels.append((index, target['path'], times, values, interpolation))
                starts.append(times[0]); ends.append(times[-1])
            if not channels:
                raise ValueError('Empty animation clip')
            start, end = min(starts), max(ends)
            for fraction in fractions:
                time = start+(end-start)*fraction
                nodes = [dict(n) for n in original]
                for index, path, times, values, interpolation in channels:
                    nodes[index][path] = sample_channel(times, values, time, path, interpolation)
                cache, visiting = {}, set()

                def world(index):
                    if not isinstance(index, int) or not 0 <= index < len(nodes):
                        raise ValueError('Skin node index out of range')
                    if index in visiting:
                        raise ValueError('Node hierarchy cycle')
                    if index not in cache:
                        visiting.add(index)
                        local = matrix(nodes[index])
                        finite([x for row in local for x in row])
                        cache[index] = multiply(world(parents[index]), local) if index in parents else local
                        visiting.remove(index)
                    return cache[index]

                transforms = [multiply(world(j), matrix({'matrix': bind}))
                              for j, bind in zip(skin['joints'], binds)]
                # Joint world * inverse bind maps mesh coordinates to world.
                # The common mesh-world inverse then mesh-world cancels here.
                contacts, flipped = pose_surface(points, faces, joints, weights, transforms, keys)
                sample = {'clip': animation.get('name', ''), 'fraction': fraction,
                          'time': time, 'contacts': len(contacts), 'first_pairs': contacts[:8],
                          'orientation_failures': len(flipped), 'first_flipped_faces': flipped[:8]}
                report['samples'].append(sample)
                if contacts or flipped:
                    errors.append(f"{sample['clip']} at {time:g}: {len(contacts)} contacts, "
                                  f"{len(flipped)} orientation failures")
        report['morph_weights'] = morphs
        report['fractions'] = list(fractions)
    except (ValueError, KeyError, IndexError, TypeError, ZeroDivisionError) as error:
        errors.append(str(error))
    return errors, report
