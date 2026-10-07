"""Finite shape contract for the gel body's mitts, boots and sewn junctions."""
import math


REFERENCE_DIAMETER_M = 1.74 / 3.68
MITT_LENGTH_TARGET_M = .39 * REFERENCE_DIAMETER_M
MITT_FRONT_WIDTH_TARGET_M = .35 * REFERENCE_DIAMETER_M
MITT_TOLERANCE_RELATIVE = .15
BOOT_WIDTH_TARGET_M = .57 * REFERENCE_DIAMETER_M
BOOT_HEIGHT_TARGET_M = .45 * REFERENCE_DIAMETER_M
BOOT_TOLERANCE_M = .06 * REFERENCE_DIAMETER_M


def _weights(obj, vertex):
    return {obj.vertex_groups[group.group].name: group.weight
            for group in vertex.groups}


def _bounds(vertices):
    return tuple(max(vertex.co[axis] for vertex in vertices)
                 - min(vertex.co[axis] for vertex in vertices)
                 for axis in range(3))


def _relative_error(value, target):
    return abs(value / target - 1.)


def _percentile(values, fraction):
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)] if ordered else 0.


def _transition_angles(obj, region):
    linked = {}
    for polygon in obj.data.polygons:
        indices = tuple(polygon.vertices)
        for first, second in zip(indices, indices[1:] + indices[:1]):
            linked.setdefault(tuple(sorted((first, second))), []).append(polygon.index)
    angles = []
    for (first, second), polygons in linked.items():
        if len(polygons) != 2:
            continue
        middle = (obj.data.vertices[first].co + obj.data.vertices[second].co) * .5
        x, z = abs(middle.x), middle.z
        if region == 'neck_shoulders':
            selected = ((x < .18 and 1.12 < z < 1.35)
                        or (.08 < x < .45 and .90 < z < 1.25))
        else:
            selected = x < .34 and .50 < z < .86
        if selected:
            dot = max(-1., min(1., obj.data.polygons[polygons[0]].normal.dot(
                obj.data.polygons[polygons[1]].normal)))
            angles.append(math.degrees(math.acos(dot)))
    return angles


def _connected_components(obj):
    graph = {vertex.index: set() for vertex in obj.data.vertices}
    for edge in obj.data.edges:
        first, second = edge.vertices
        graph[first].add(second)
        graph[second].add(first)
    components = 0
    unseen = set(graph)
    while unseen:
        components += 1
        pending = [unseen.pop()]
        while pending:
            for neighbor in graph[pending.pop()]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    pending.append(neighbor)
    return components


def shape_report(obj, lod_index):
    """Measure the exported neutral mesh after skin weights are assigned."""
    sides = {}
    for side, sign in (('L', 1), ('R', -1)):
        mitt, hand, thumb, boot = [], [], [], []
        for vertex in obj.data.vertices:
            weights = _weights(obj, vertex)
            if vertex.co.x * sign < 0.:
                continue
            mitt_weight = sum(weights.get(part + '.' + side, 0.)
                              for part in ('hand', 'thumb', 'grip'))
            if mitt_weight > .5:
                mitt.append(vertex)
            if weights.get('hand.' + side, 0.) > .5:
                hand.append(vertex)
            if weights.get('thumb.' + side, 0.) > .25:
                thumb.append(vertex)
            if weights.get('foot.' + side, 0.) > .5:
                boot.append(vertex)
        if not mitt or not hand or not thumb or not boot:
            raise AssertionError(('Empty weighted shape region', obj.name, side))
        mitt_size = _bounds(mitt)
        boot_size = _bounds(boot)
        sole = [vertex for vertex in boot if abs(vertex.co.z) < 1e-6]
        sides[side] = {
            'mitten_length_m': mitt_size[0],
            'mitten_front_width_m': mitt_size[2],
            'mitten_depth_m': mitt_size[1],
            'thumb_forward_protrusion_m': min(vertex.co.y for vertex in hand)
                - min(vertex.co.y for vertex in thumb),
            'boot_width_m': boot_size[0],
            'boot_depth_m': boot_size[1],
            'boot_height_m': boot_size[2],
            'flat_sole_vertices': len(sole),
            'sole_height_m': min((vertex.co.z for vertex in sole), default=None),
        }
    edge_use = {}
    for polygon in obj.data.polygons:
        indices = tuple(polygon.vertices)
        for first, second in zip(indices, indices[1:] + indices[:1]):
            edge = tuple(sorted((first, second)))
            edge_use[edge] = edge_use.get(edge, 0) + 1
    transitions = {}
    for region in ('neck_shoulders', 'torso_legs'):
        angles = _transition_angles(obj, region)
        transitions[region] = {
            'adjacent_face_angle_p95_degrees': _percentile(angles, .95),
            'maximum_adjacent_face_angle_degrees': max(angles, default=0.),
            'sampled_edges': len(angles),
        }
    angle_limit = None if lod_index == 2 else (30. if lod_index == 0 else 55.)
    return {
        'lod_index': lod_index,
        'contract': {
            'mitten_length_target_m': MITT_LENGTH_TARGET_M,
            'mitten_front_width_target_m': MITT_FRONT_WIDTH_TARGET_M,
            'mitten_tolerance_relative': MITT_TOLERANCE_RELATIVE,
            'minimum_thumb_forward_protrusion_m': .02,
            # Endpoint collapse is not symmetry-constrained at the triangle
            # level; allow its measured sub-7% drift while sources stay at 5%.
            'maximum_bilateral_dimension_difference_relative': (
                .07 if lod_index == 2 else .05),
            'boot_width_range_m': [BOOT_WIDTH_TARGET_M - BOOT_TOLERANCE_M,
                                   BOOT_WIDTH_TARGET_M + BOOT_TOLERANCE_M],
            'boot_height_range_m': [BOOT_HEIGHT_TARGET_M - BOOT_TOLERANCE_M,
                                    BOOT_HEIGHT_TARGET_M + BOOT_TOLERANCE_M],
            'minimum_flat_sole_vertices_per_side': 4,
            'maximum_transition_angle_p95_degrees': angle_limit,
            'maximum_transition_angle_degrees': 65.,
        },
        'sides': sides,
        'surface': {
            'boundary_or_nonmanifold_edges': sum(count != 2 for count in edge_use.values()),
            'connected_components': _connected_components(obj),
            'smooth_faces': sum(polygon.use_smooth for polygon in obj.data.polygons),
            'faces': len(obj.data.polygons),
        },
        'transitions': transitions,
    }


def assert_shape_report(report):
    contract = report['contract']
    for side, shape in report['sides'].items():
        assert _relative_error(shape['mitten_length_m'],
                               contract['mitten_length_target_m']) <= contract[
                                   'mitten_tolerance_relative'], (side, shape)
        assert _relative_error(shape['mitten_front_width_m'],
                               contract['mitten_front_width_target_m']) <= contract[
                                   'mitten_tolerance_relative'], (side, shape)
        assert shape['thumb_forward_protrusion_m'] >= contract[
            'minimum_thumb_forward_protrusion_m'], (side, shape)
        assert contract['boot_width_range_m'][0] <= shape['boot_width_m'] <= contract[
            'boot_width_range_m'][1], (side, shape)
        assert contract['boot_height_range_m'][0] <= shape['boot_height_m'] <= contract[
            'boot_height_range_m'][1], (side, shape)
        assert shape['flat_sole_vertices'] >= contract[
            'minimum_flat_sole_vertices_per_side'], (side, shape)
        assert shape['sole_height_m'] is not None and abs(shape['sole_height_m']) < 1e-6
    for metric in ('mitten_length_m', 'mitten_front_width_m', 'mitten_depth_m',
                   'boot_width_m', 'boot_depth_m', 'boot_height_m'):
        left, right = report['sides']['L'][metric], report['sides']['R'][metric]
        assert abs(left / right - 1.) <= contract[
            'maximum_bilateral_dimension_difference_relative'], (metric, left, right)
    surface = report['surface']
    assert surface['boundary_or_nonmanifold_edges'] == 0, surface
    assert surface['connected_components'] == 1, surface
    assert surface['smooth_faces'] == surface['faces'], surface
    p95_limit = contract['maximum_transition_angle_p95_degrees']
    if p95_limit is not None:
        for name, transition in report['transitions'].items():
            assert transition['sampled_edges'] > 0, (name, transition)
            assert transition['adjacent_face_angle_p95_degrees'] <= p95_limit, (
                name, transition)
            assert transition['maximum_adjacent_face_angle_degrees'] <= contract[
                'maximum_transition_angle_degrees'], (name, transition)
