"""Measurable authoring-topology contract for the deformable gel body.

LOD0 and LOD1 are quad authoring surfaces.  LOD2 is a derived triangular
runtime simplification and deliberately remains outside this contract.
"""
from collections import Counter


# Coordinates match anatomical_rest() in build_gel_body.py.  Windows cover the
# visible bending span rather than a single zero-width bone pivot.
JOINT_ZONES = {
    'shoulder': {'axis': 0, 'center': .30, 'window': .13, 'region': 'arm'},
    'elbow': {'axis': 0, 'center': .47645, 'window': .13, 'region': 'arm'},
    'wrist': {'axis': 0, 'center': .69045, 'window': .12, 'region': 'arm'},
    'hip': {'axis': 2, 'center': .67, 'window': .15, 'region': 'leg'},
    'knee': {'axis': 2, 'center': .375, 'window': .14, 'region': 'leg'},
    'ankle': {'axis': 2, 'center': .16, 'window': .12, 'region': 'leg'},
    'neck': {'axis': 2, 'center': 1.26, 'window': .15, 'region': 'neck'},
}


def _inside(point, region):
    if region == 'arm':
        return abs(point.x) > .1 and .9 < point.z < 1.3
    if region == 'leg':
        return 0. < abs(point.x) < .35 and point.z < .85
    return abs(point.x) < .16 and abs(point.y) < .16


def _projection(point, zone):
    value = point[zone['axis']]
    return abs(value) if zone['axis'] == 0 else value


def _joint_edges(obj, zone):
    points = [vertex.co for vertex in obj.data.vertices]
    selected = []
    for edge in obj.data.edges:
        first, second = edge.vertices
        a, b = points[first], points[second]
        delta = a-b
        middle = (_projection(a, zone)+_projection(b, zone))*.5
        if (abs(middle-zone['center']) <= zone['window']
                and _inside(a, zone['region']) and _inside(b, zone['region'])
                and (zone['region'] == 'neck' or a.x*b.x > 0.)
                and abs(_projection(a, zone)-_projection(b, zone))
                    <= max(1e-5, delta.length*.55)):
            selected.append((first, second))
    return selected


def _closed_cycles(edges):
    graph = {}
    for first, second in edges:
        graph.setdefault(first, set()).add(second)
        graph.setdefault(second, set()).add(first)
    cycles = []
    while graph:
        pending = [next(iter(graph))]
        vertices = set(pending)
        while pending:
            current = pending.pop()
            for neighbor in graph[current]:
                if neighbor not in vertices:
                    vertices.add(neighbor)
                    pending.append(neighbor)
        edge_count = sum(len(graph[vertex] & vertices) for vertex in vertices)//2
        if edge_count == len(vertices) and all(
                len(graph[vertex] & vertices) == 2 for vertex in vertices):
            cycles.append(vertices)
        for vertex in vertices:
            del graph[vertex]
    return cycles


def _percentile(values, fraction):
    ordered = sorted(values)
    return ordered[round((len(ordered)-1)*fraction)]


def _aspect_percentile(obj, zone, morph_names, morph_delta, fraction=.9):
    base = [vertex.co.copy() for vertex in obj.data.vertices]
    samples = [base]
    for name in morph_names:
        delta = [morph_delta(point, name) for point in base]
        samples.extend(([point-change for point, change in zip(base, delta)],
                        [point+change for point, change in zip(base, delta)]))
    aspects = []
    for points in samples:
        for face in obj.data.polygons:
            indices = tuple(face.vertices)
            center = sum((points[index] for index in indices), points[indices[0]]*0)
            center /= len(indices)
            if (abs(_projection(center, zone)-zone['center']) > zone['window']
                    or not _inside(center, zone['region'])):
                continue
            lengths = [(points[first]-points[second]).length
                       for first, second in zip(indices, indices[1:]+indices[:1])]
            aspects.append(max(lengths)/min(lengths))
    if not aspects:
        raise AssertionError(('Empty topology density zone', obj.name, zone))
    return _percentile(aspects, fraction)


def topology_report(obj, morph_names, morph_delta):
    """Return the finite, deterministic topology gate used by build and tests."""
    adjacency = Counter(index for edge in obj.data.edges for index in edge.vertices)
    points = [vertex.co for vertex in obj.data.vertices]
    joints = {}
    for name, zone in JOINT_ZONES.items():
        cycles = _closed_cycles(_joint_edges(obj, zone))
        centers = [sum(_projection(points[index], zone) for index in cycle)/len(cycle)
                   for cycle in cycles]
        zone_vertices = [vertex.index for vertex in obj.data.vertices
                         if _inside(vertex.co, zone['region'])
                         and abs(_projection(vertex.co, zone)-zone['center']) <= zone['window']]
        joints[name] = {
            'closed_loops': len(cycles),
            'minimum_loop_vertices': min(map(len, cycles), default=0),
            'nearest_loop_distance_m': min(
                (abs(center-zone['center']) for center in centers), default=None),
            'maximum_vertex_valence': max((adjacency[index] for index in zone_vertices), default=0),
            'morph_extremes_edge_aspect_p90': _aspect_percentile(
                obj, zone, morph_names, morph_delta),
        }
    return {
        'faces': len(obj.data.polygons),
        'quad_faces': sum(len(face.vertices) == 4 for face in obj.data.polygons),
        'joint_contract': {
            'minimum_bilateral_loops': 2,
            'minimum_neck_loops': 1,
            'minimum_vertices_per_loop': 8,
            'maximum_joint_valence': 5,
            'maximum_morph_extremes_edge_aspect_p90': 3.5,
        },
        'joints': joints,
    }


def assert_topology_report(report):
    contract = report['joint_contract']
    assert report['quad_faces'] == report['faces'], report
    for name, joint in report['joints'].items():
        minimum = (contract['minimum_neck_loops'] if name == 'neck'
                   else contract['minimum_bilateral_loops'])
        assert joint['closed_loops'] >= minimum, (name, joint)
        assert joint['minimum_loop_vertices'] >= contract['minimum_vertices_per_loop'], (name, joint)
        assert joint['maximum_vertex_valence'] <= contract['maximum_joint_valence'], (name, joint)
        assert (joint['morph_extremes_edge_aspect_p90']
                <= contract['maximum_morph_extremes_edge_aspect_p90']), (name, joint)
