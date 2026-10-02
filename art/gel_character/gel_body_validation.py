"""S-311 exported geometry checks, independent of the Blender body builder.

The deterministic sweep covers base, 22 single extremes and 30 mixed samples;
it is evidence for those samples, not a proof over the continuous slider space.
"""

from collections import Counter, defaultdict
import math
import random


MORPH_NAMES = ("general_thickness", "belly", "chest", "shoulders", "hips",
               "arm_thickness", "leg_thickness", "hand_size", "foot_size",
               "head_shape", "neck_thickness")
JOINT_NAMES = frozenset(["pelvis", "chest", "neck", "head"] + [
    name + side for side in (".L", ".R")
    for name in ("upper_arm", "forearm", "hand", "thumb", "grip", "thigh", "shin", "foot")])
BUDGETS = (6000, 2500, 800)
EPS = 1e-8


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def normal(triangle):
    return cross(sub(triangle[1], triangle[0]), sub(triangle[2], triangle[0]))


def cross2(a, b):
    return a[0] * b[1] - a[1] * b[0]


def overlap_area(a, b):
    """Convex clipping distinguishes interior overlap from edge/point contact."""
    polygon = list(a)
    orientation = 1 if cross2(sub(b[1], b[0]), sub(b[2], b[0])) >= 0 else -1
    for first, second in zip(b, b[1:] + b[:1]):
        edge = sub(second, first)
        output = []
        if not polygon:
            return 0.
        prior = polygon[-1]
        prior_d = orientation * cross2(edge, sub(prior, first))
        for current in polygon:
            current_d = orientation * cross2(edge, sub(current, first))
            if (current_d >= 0) != (prior_d >= 0):
                t = prior_d / (prior_d - current_d)
                output.append(tuple(p + t * (c - p) for p, c in zip(prior, current)))
            if current_d >= 0:
                output.append(current)
            prior, prior_d = current, current_d
        polygon = output
    return abs(sum(cross2(p, q) for p, q in zip(polygon, polygon[1:] + polygon[:1]))) * .5


def triangle_intersection(a, b):
    """Detect positive-area coplanar or nontrivial transverse triangle contact.

    A shared edge is excluded by the caller's welded topology. Here a common
    vertex alone does not hide a crossing away from that vertex.
    """
    na, nb = normal(a), normal(b)
    la, lb = math.sqrt(dot(na, na)), math.sqrt(dot(nb, nb))
    if min(la, lb) < EPS:
        return False
    na, nb = tuple(x / la for x in na), tuple(x / lb for x in nb)
    distances_b = [dot(na, sub(p, a[0])) for p in b]
    distances_a = [dot(nb, sub(p, b[0])) for p in a]
    if (min(distances_b) > EPS or max(distances_b) < -EPS or
            min(distances_a) > EPS or max(distances_a) < -EPS):
        return False
    if max(abs(d) for d in distances_b + distances_a) <= EPS:
        axis = max(range(3), key=lambda i: abs(na[i]))
        aa = [tuple(v for i, v in enumerate(p) if i != axis) for p in a]
        bb = [tuple(v for i, v in enumerate(p) if i != axis) for p in b]
        return overlap_area(aa, bb) > EPS * EPS

    def inside(p, tri, n):
        # Cross products are area units; scale the distance tolerance by edge
        # length so a short edge does not admit a point beyond its endpoint.
        return all(dot(cross(sub(q, v), sub(p, v)), n) >=
                   -EPS * math.sqrt(dot(sub(q, v), sub(q, v)))
                   for v, q in zip(tri, tri[1:] + tri[:1]))

    common = [p for p in a if any(dot(sub(p, q), sub(p, q)) <= EPS * EPS for q in b)]
    for source, target, distances, n in ((a, b, distances_a, nb), (b, a, distances_b, na)):
        for i in range(3):
            p, q = source[i], source[(i + 1) % 3]
            dp, dq = distances[i], distances[(i + 1) % 3]
            hits = []
            if abs(dp) <= EPS:
                hits.append(p)
            if dp * dq < 0:
                t = dp / (dp - dq)
                hits.append(tuple(x + t * (y - x) for x, y in zip(p, q)))
            for hit in hits:
                if inside(hit, target, n) and not any(
                        dot(sub(hit, v), sub(hit, v)) <= EPS * EPS for v in common):
                    return True
    return False


def bounds(points):
    return tuple(min(p[i] for p in points) for i in range(len(points[0]))), \
        tuple(max(p[i] for p in points) for i in range(len(points[0])))


def boxes_overlap(a, b):
    return all(a[0][i] <= b[1][i] + EPS and b[0][i] <= a[1][i] + EPS
               for i in range(len(a[0])))


def candidate_pairs(triangles):
    """Median AABB tree: no quadratic all-pairs scan of exported meshes."""
    boxes = [bounds(t) for t in triangles]

    def tree(ids):
        box = (tuple(min(boxes[j][0][i] for j in ids) for i in range(len(boxes[0][0]))),
               tuple(max(boxes[j][1][i] for j in ids) for i in range(len(boxes[0][0]))))
        if len(ids) <= 8:
            return box, ids, None
        axis = max(range(len(box[0])), key=lambda i: box[1][i] - box[0][i])
        ordered = sorted(ids, key=lambda j: boxes[j][0][axis] + boxes[j][1][axis])
        half = len(ordered) // 2
        return box, tree(ordered[:half]), tree(ordered[half:])

    def between(left, right):
        if not boxes_overlap(left[0], right[0]):
            return
        if left[2] is None and right[2] is None:
            for i in left[1]:
                for j in right[1]:
                    if boxes_overlap(boxes[i], boxes[j]):
                        yield i, j
        elif left[2] is None:
            yield from between(left, right[1])
            yield from between(left, right[2])
        else:
            yield from between(left[1], right)
            yield from between(left[2], right)

    def within(node):
        if node[2] is None:
            ids = node[1]
            for offset, i in enumerate(ids):
                for j in ids[offset + 1:]:
                    if boxes_overlap(boxes[i], boxes[j]):
                        yield i, j
        else:
            yield from within(node[1])
            yield from within(node[2])
            yield from between(node[1], node[2])

    if triangles:
        yield from within(tree(list(range(len(triangles)))))


def matrix(node):
    """Row-major working matrix from glTF's column-major matrix or TRS."""
    if "matrix" in node:
        if len(node["matrix"]) != 16:
            raise ValueError("Node matrix must contain 16 values")
        return [[node["matrix"][j * 4 + i] for j in range(4)] for i in range(4)]
    x, y, z, w = node.get("rotation", [0., 0., 0., 1.])
    sx, sy, sz = node.get("scale", [1., 1., 1.])
    tx, ty, tz = node.get("translation", [0., 0., 0.])
    return [[(1 - 2*y*y - 2*z*z)*sx, (2*x*y - 2*z*w)*sy, (2*x*z + 2*y*w)*sz, tx],
            [(2*x*y + 2*z*w)*sx, (1 - 2*x*x - 2*z*z)*sy, (2*y*z - 2*x*w)*sz, ty],
            [(2*x*z - 2*y*w)*sx, (2*y*z + 2*x*w)*sy, (1 - 2*x*x - 2*y*y)*sz, tz],
            [0., 0., 0., 1.]]


def multiply(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def transform(m, p, delta=False):
    return tuple(sum(m[i][j] * p[j] for j in range(3)) + (0 if delta else m[i][3]) for i in range(3))


def check(asset, lod):
    doc, errors = asset.data, []
    report = {"lod": lod, "triangle_budget": BUDGETS[lod], "random_seed": 311018,
              "sample_count": 0, "welded_vertices": 0,
              "orientation_criterion": "sample triangle normal dot base normal > 0; rejects >90-degree reorientation",
              "scope": "base, 22 single extremes, 30 seeded combinations; not continuous proof"}

    def require(ok, message):
        if not ok:
            errors.append(message)

    nodes, skins = doc.get("nodes", []), doc.get("skins", [])
    require(len(skins) == 1, "Gel body must use exactly one skin")
    if skins:
        names = [nodes[j].get("name", "") for j in skins[0]["joints"]]
        require(len(names) == 20 and set(names) == JOINT_NAMES,
                "Gel body requires exactly the 20 prescribed joints (including grips/thumbs)")
    mesh_nodes = [i for i, n in enumerate(nodes) if "mesh" in n]
    require(len(mesh_nodes) == 1, "Gel body must contain one exterior mesh node")
    if len(mesh_nodes) != 1:
        return errors, report
    parents = {}
    for i, node in enumerate(nodes):
        for child in node.get("children", []):
            require(child not in parents, "Node has multiple parents")
            parents[child] = i

    def world(index, visited=None):
        visited = set() if visited is None else visited
        if index in visited:
            raise ValueError("Node hierarchy contains a cycle")
        visited.add(index)
        local = matrix(nodes[index])
        return multiply(world(parents[index], visited), local) if index in parents else local

    node_id = mesh_nodes[0]
    node = nodes[node_id]
    require("skin" in node, "Gel body exterior must be skinned")
    require(node.get("skin") == 0, "Gel body must reference its only skin")
    mesh = doc["meshes"][node["mesh"]]
    require(tuple(mesh.get("extras", {}).get("targetNames", [])) == MORPH_NAMES,
            "Gel body morph names/order must be the eleven prescribed shape morphs")
    default_weights = node.get("weights", mesh.get("weights", [0.] * len(MORPH_NAMES)))
    require(isinstance(default_weights, list)
            and len(default_weights) == len(MORPH_NAMES)
            and all(type(weight) in (int, float) and math.isfinite(weight) and weight == 0
                    for weight in default_weights),
            "Gel body default morph weights must load Delgada (eleven finite zeros)")
    m = world(node_id)
    skin_matrices = []
    if skins:
        skin = skins[0]
        if "inverseBindMatrices" in skin:
            binds = asset.accessor(skin["inverseBindMatrices"])
        else:
            binds = [(1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.)] * len(skin["joints"])
        for joint, bind in zip(skin["joints"], binds):
            inverse_bind = [[bind[j * 4 + i] for j in range(4)] for i in range(4)]
            skin_matrices.append(multiply(world(joint), inverse_bind))
    node_space_vertices = []
    raw_seam_keys = []
    vertices, deltas, uv_triangles, faces = [], [[] for _ in MORPH_NAMES], [], []
    for primitive in mesh["primitives"]:
        require(primitive.get("mode", 4) == 4, "Gel body must use triangle primitives")
        attrs = primitive["attributes"]
        positions = asset.accessor(attrs["POSITION"])
        require(all(len(p) == 3 for p in positions), "POSITION must be VEC3")
        require("NORMAL" in attrs, "Gel body is missing normals")
        if "NORMAL" in attrs:
            normals = asset.accessor(attrs["NORMAL"])
            require(all(len(n) == 3 and abs(dot(n, n) - 1) < .01 for n in normals), "Gel body normals must be unit VEC3")
        require("TEXCOORD_0" in attrs, "Gel body requires UV0")
        require("COLOR_0" in attrs or "TEXCOORD_1" in attrs, "Gel body requires vertex-color or UV1 zones")
        if "COLOR_0" in attrs:
            colors = asset.accessor(attrs["COLOR_0"])
            require(all(len(c) in (3, 4) and all(0 <= v <= 1 for v in c) for c in colors),
                    "Vertex-color zones must be VEC3/VEC4 within [0,1]")
        if "TEXCOORD_1" in attrs:
            require(all(len(uv) == 2 for uv in asset.accessor(attrs["TEXCOORD_1"])), "UV1 zones must be VEC2")
        targets = primitive.get("targets", [])
        require(len(targets) == 11, "Gel body must have exactly eleven morph targets")
        actual_deltas = []
        for i, target in enumerate(targets):
            require("POSITION" in target, f"Morph {i} is missing POSITION deltas")
            values = asset.accessor(target["POSITION"]) if "POSITION" in target else []
            require(len(values) == len(positions) and all(len(v) == 3 for v in values),
                    f"Morph {i} has wrong delta vertex count/type")
            for semantic, accessor_id in target.items():
                require(semantic in ("POSITION", "NORMAL", "TANGENT"), "Morph cannot change UV0/zones")
                require(len(asset.accessor(accessor_id)) == len(positions), f"Morph {i} {semantic} count mismatch")
            actual_deltas.append(values)
        index_values = asset.accessor(primitive["indices"]) if "indices" in primitive else [(i,) for i in range(len(positions))]
        indices = [p[0] for p in index_values]
        require(len(indices) % 3 == 0 and all(isinstance(i, int) and 0 <= i < len(positions) for i in indices),
                "Gel body triangle indices are invalid")
        if errors:
            continue
        offset = len(vertices)
        raw_seam_keys.extend(tuple(v for vec in [p] + [d[i] for d in actual_deltas] for v in vec)
                             for i, p in enumerate(positions))
        node_space_vertices.extend(transform(m, p) for p in positions)
        weight_sets = sorted(key for key in attrs if key.startswith("WEIGHTS_"))
        influences = [[] for _ in positions]
        for key in weight_sets:
            weights = asset.accessor(attrs[key])
            joints = asset.accessor(attrs[key.replace("WEIGHTS_", "JOINTS_")])
            for i, (js, ws) in enumerate(zip(joints, weights)):
                influences[i].extend((skin_matrices[j], w) for j, w in zip(js, ws) if w > 0)

        def skinned(value, index, delta=False):
            transformed = [(transform(bone, value, delta), weight) for bone, weight in influences[index]]
            return tuple(sum(p[axis] * weight for p, weight in transformed) for axis in range(3))

        vertices.extend(skinned(p, i) for i, p in enumerate(positions))
        for i, values in enumerate(actual_deltas):
            deltas[i].extend(skinned(p, j, True) for j, p in enumerate(values))
        uvs = asset.accessor(attrs["TEXCOORD_0"])
        require(all(len(uv) == 2 and all(0 <= v <= 1 for v in uv) for uv in uvs), "UV0 must be VEC2 within [0,1]")
        for start in range(0, len(indices), 3):
            face = tuple(indices[start:start + 3])
            geometric_normal = normal([positions[i] for i in face])
            tolerance = EPS * math.sqrt(dot(geometric_normal, geometric_normal))
            require(all(dot(geometric_normal, normals[i]) >= -tolerance for i in face),
                    f"Triangle {start // 3} must have outward shading normals")
            faces.append(tuple(i + offset for i in face))
            uv_triangles.append([uvs[i] for i in face])
    if errors:
        return errors, report
    require(len(faces) <= BUDGETS[lod], f"LOD{lod} triangle budget exceeded: {len(faces)} > {BUDGETS[lod]}")
    require(bool(vertices), "Gel body is empty")
    if not vertices:
        return errors, report
    require(abs(min(v[1] for v in vertices)) <= 1e-4,
            "Gel body foot pivot: skinned world-space sole minimum Y must be zero")
    require(abs(min(v[1] for v in node_space_vertices)) <= 1e-4,
            "Gel body foot pivot: transformed mesh sole minimum Y must be zero")
    # A UV duplicate is the same geometric vertex only when ALL targets agree.
    welded, mapping = {}, []
    for i, p in enumerate(vertices):
        # GLB UV duplicates have identical exported float32 positions/deltas.
        # No spatial tolerance may join distinct morph trajectories: even a
        # tiny differing delta is a real opening at a slider extreme.
        # Distinct raw seams must not disappear when different skin transforms
        # happen to cancel their gaps at rest. Require raw AND evaluated data.
        key = raw_seam_keys[i] + tuple(v for vec in [p] + [d[i] for d in deltas] for v in vec)
        if key not in welded:
            welded[key] = len(welded)
        mapping.append(welded[key])
    topology = [tuple(mapping[i] for i in face) for face in faces]
    report["welded_vertices"] = len(welded)
    edges, directed = Counter(), Counter()
    neighbors = defaultdict(set)
    for face in topology:
        for first, second in zip(face, face[1:] + face[:1]):
            edges[tuple(sorted((first, second)))] += 1
            directed[first, second] += 1
            neighbors[first].add(second)
            neighbors[second].add(first)
    require(all(v == 2 for v in edges.values()), "Gel body is not watertight: each welded edge must have two faces")
    require(all(directed[a, b] == 1 and directed[b, a] == 1 for a, b in edges),
            "Gel body face orientation is inconsistent across welded edges")
    seen, pending = set(), [0]
    while pending:
        current = pending.pop()
        if current not in seen:
            seen.add(current)
            pending.extend(neighbors[current] - seen)
    require(len(seen) == len(welded), "Gel body must be one connected exterior surface")
    # A closed edge-manifold may still pinch two surface fans at one vertex.
    # Each vertex link must be exactly one cycle, not disconnected cycles.
    links = defaultdict(lambda: defaultdict(set))
    for a, b, c in topology:
        for vertex, first, second in ((a, b, c), (b, c, a), (c, a, b)):
            links[vertex][first].add(second)
            links[vertex][second].add(first)
    for vertex, link in links.items():
        reached, pending = set(), [next(iter(link))]
        while pending:
            current = pending.pop()
            if current not in reached:
                reached.add(current)
                pending.extend(link[current] - reached)
        require(len(reached) == len(link) and all(len(n) == 2 for n in link.values()),
                f"Gel body vertex {vertex} is not manifold: link must be one cycle")
    for i, tri in enumerate(uv_triangles):
        require(abs(cross2(sub(tri[1], tri[0]), sub(tri[2], tri[0]))) > EPS * EPS,
                f"UV0 triangle {i} is degenerate")
    for i, j in candidate_pairs(uv_triangles):
        if overlap_area(uv_triangles[i], uv_triangles[j]) > EPS * EPS:
            errors.append(f"UV0 triangles {i}/{j} overlap in their interiors")
            break
    if errors:
        return errors, report
    base_triangles = [[vertices[i] for i in f] for f in faces]
    base_normals = [normal(t) for t in base_triangles]
    # Consistent edge orientation alone also accepts a completely inward hull.
    # For the one closed component, signed enclosed volume establishes outward
    # winding. Centering reduces cancellation for translated world positions.
    center = tuple(sum(p[axis] for p in vertices) / len(vertices) for axis in range(3))
    signed_volume = math.fsum(dot(sub(t[0], center), cross(sub(t[1], center), sub(t[2], center)))
                              for t in base_triangles) / 6.
    report["base_signed_volume_m3"] = signed_volume
    samples = [[0.] * 11]
    for i in range(11):
        for value in (-1., 1.):
            weights = [0.] * 11
            weights[i] = value
            samples.append(weights)
    rng = random.Random(311018)
    samples.extend([[rng.uniform(-1., 1.) for _ in range(11)] for _ in range(30)])
    for sample_index, weights in enumerate(samples):
        deformed = [tuple(p[axis] + sum(weights[k] * deltas[k][i][axis] for k in range(11))
                          for axis in range(3)) for i, p in enumerate(vertices)]
        tris = [[deformed[i] for i in f] for f in faces]
        report["sample_count"] += 1
        if abs(min(p[1] for p in deformed)) > 1e-4:
            errors.append(f"Morph sample {sample_index} changes the world-space foot pivot")
            break
        for i, tri in enumerate(tris):
            n = normal(tri)
            if dot(n, n) <= EPS * EPS:
                errors.append(f"Morph sample {sample_index} has degenerate triangle {i}")
                break
            if dot(n, base_normals[i]) <= 0:
                # Shape morphs are radial, not rigid rotations. This criterion
                # conservatively rejects a normal turning >=90 degrees; it is
                # not a general mathematical inversion test for arbitrary 3D
                # deformations (a rigid 180-degree rotation would also fail).
                errors.append(f"Morph sample {sample_index} has inverted/reoriented triangle {i} (normal dot base <= 0)")
                break
        if errors:
            break
        for i, j in candidate_pairs(tris):
            if len(set(topology[i]) & set(topology[j])) >= 2:
                continue
            if triangle_intersection(tris[i], tris[j]):
                errors.append(f"Morph sample {sample_index} has self-intersection triangles {i}/{j}")
                break
        if errors:
            break
    require(signed_volume > 1e-12,
            "Gel body must have outward baseline winding and positive enclosed signed volume")
    return errors, report
