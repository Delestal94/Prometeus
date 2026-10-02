"""S-311 B18: independently encoded GLBs exercise strict exported-body checks.

Run with: python -m unittest discover -s art/gel_character -p test_validate_glb.py
No Blender, Godot or generated-body metadata is used by these fixtures.
"""

import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

from validate_glb import validate, validate_gel_body


JOINT_NAMES = ["pelvis", "chest", "neck", "head"] + [
    name + side for side in (".L", ".R")
    for name in ("upper_arm", "forearm", "hand", "thumb", "grip", "thigh", "shin", "foot")]
MORPH_NAMES = ["general_thickness", "belly", "chest", "shoulders", "hips",
               "arm_thickness", "leg_thickness", "hand_size", "foot_size",
               "head_shape", "neck_thickness"]


def fixture(path, change=None):
    """Closed oriented tetrahedron with UV-split vertices and eleven real targets."""
    points = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.)]
    faces = [(0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)]
    state = {"points": points, "faces": faces, "names": list(JOINT_NAMES),
             "morph_names": list(MORPH_NAMES), "zero_weight": False,
             "uv_overlap": False, "translation": [0., 0., 0.],
             "bad_index": False, "bad_morph_count": False, "nan": False,
             "split_morph": False, "collapse_morph": False,
             "morph_by_point": False, "joint_offset": 0.,
             "floor_morph": False, "bind_offset": 0., "tiny_split_morph": False,
             "skin_cancels_raw_seam": False}
    if change:
        change(state)
    binary, views, accessors = bytearray(), [], []

    def add(values, kind, component=5126):
        while len(binary) % 4:
            binary.append(0)
        start = len(binary)
        fmt = {5126: "f", 5123: "H"}[component]
        for value in values:
            binary.extend(struct.pack("<" + fmt * len(value), *value))
        views.append({"buffer": 0, "byteOffset": start, "byteLength": len(binary) - start})
        accessors.append({"bufferView": len(views) - 1, "componentType": component,
                          "count": len(values), "type": kind})
        return len(accessors) - 1

    positions, uvs, normals = [], [], []
    point_ids = []
    grid = math.ceil(math.sqrt(len(state["faces"])))
    for f, face in enumerate(state["faces"]):
        positions.extend(state["points"][v] for v in face)
        point_ids.extend(face)
        cell = 1. / grid
        x = .05 * cell if state["uv_overlap"] else (.05 + f % grid) * cell
        y = .05 * cell if state["uv_overlap"] else (.05 + f // grid) * cell
        uvs.extend([(x, y), (x + .8 * cell, y), (x, y + .8 * cell)])
        a, b, c = (state["points"][i] for i in face)
        u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
        n = (u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0])
        length = math.sqrt(sum(x*x for x in n))
        n = tuple(x / length for x in n) if length else (0., 1., 0.)
        if state.get("reversed_normals"):
            n = tuple(-x for x in n)
        normals.extend([state.get("normal_override", n)] * 3)
    if state["nan"]:
        positions[0] = (math.nan, 0., 0.)
    if state["skin_cancels_raw_seam"]:
        positions[0] = (.125, 0., 0.)
    count = len(positions)
    indices = [(i,) for i in range(count)]
    if state["bad_index"]:
        indices[0] = (count,)
    attrs = {"POSITION": add(positions, "VEC3"), "NORMAL": add(normals, "VEC3"),
             "TEXCOORD_0": add(uvs, "VEC2"),
             "COLOR_0": add([(1., 0., 0., 1.)] * count, "VEC4"),
             "JOINTS_0": add([(1 if state["skin_cancels_raw_seam"] and i == 0 else 0, 0, 0, 0)
                              for i in range(count)], "VEC4", 5123),
             "WEIGHTS_0": add([(0. if state["zero_weight"] else 1., 0., 0., 0.)] * count, "VEC4")}
    targets = []
    for target in range(11):
        deltas = [(p[0] * .001 * (target + 1), 0., p[2] * .001) for p in positions]
        if state["skin_cancels_raw_seam"]:
            deltas[0] = (0., 0., 0.)
        if state["morph_by_point"]:
            deltas = [(d[0] + point_ids[i] * .00001, d[1], d[2]) for i, d in enumerate(deltas)]
        if state["split_morph"] and target == 0:
            deltas[0] = (.2, 0., 0.)
        if state["tiny_split_morph"] and target == 0:
            deltas[0] = (deltas[0][0] + 1e-7, deltas[0][1], deltas[0][2])
        if state["collapse_morph"] and target == 0:
            deltas = [(-p[0], -p[1], -p[2]) for p in positions]
        if state["floor_morph"] and target == 0:
            deltas = [(d[0], .1, d[2]) for d in deltas]
        if state["bad_morph_count"] and target == 0:
            deltas = deltas[:-1]
        targets.append({"POSITION": add(deltas, "VEC3")})
    nodes = [{"name": n} for n in state["names"]]
    nodes[0]["translation"] = [0., state["joint_offset"], 0.]
    if state["skin_cancels_raw_seam"]:
        nodes[1]["translation"] = [-.125, 0., 0.]
    nodes.append({"name": "GelBody", "mesh": 0, "skin": 0,
                  "translation": state["translation"]})
    skin = {"joints": list(range(len(state["names"])))}
    if state["bind_offset"]:
        bind = (1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., state["bind_offset"], 0., 1.)
        skin["inverseBindMatrices"] = add([bind] * len(state["names"]), "MAT4")
    doc = {"asset": {"version": "2.0"}, "scene": 0,
           "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes,
           "skins": [skin],
           "meshes": [{"extras": {"targetNames": state["morph_names"]},
                       "primitives": [{"attributes": attrs, "indices": add(indices, "SCALAR", 5123),
                                       "targets": targets}]}],
           "buffers": [{"byteLength": len(binary)}], "bufferViews": views, "accessors": accessors}
    if "mesh_weights" in state:
        doc["meshes"][0]["weights"] = state["mesh_weights"]
    if "node_weights" in state:
        nodes[-1]["weights"] = state["node_weights"]
    encoded = json.dumps(doc).encode()
    encoded += b" " * (-len(encoded) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    total = 12 + 8 + len(encoded) + 8 + len(binary)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, total) +
                     struct.pack("<II", len(encoded), 0x4E4F534A) + encoded +
                     struct.pack("<II", len(binary), 0x004E4942) + binary)
    return path


class StrictBodyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "fixture.glb"

    def tearDown(self):
        self.directory.cleanup()

    def report(self, change=None):
        return validate_gel_body(fixture(self.path, change), lod=0)

    def invalid(self, change, term):
        report = self.report(change)
        self.assertFalse(report["valid"], report)
        self.assertIn(term, " ".join(report["errors"]).lower())

    def test_valid_uv_seam_welding_and_sampling(self):
        report = self.report()
        self.assertTrue(report["valid"], report)
        self.assertEqual(report["gel_body"]["welded_vertices"], 4)
        self.assertEqual(report["gel_body"]["sample_count"], 53)
        self.assertEqual(report["gel_body"]["random_seed"], 311018)

    def test_generic_validation_remains_optional(self):
        path = fixture(self.path, lambda s: s.update(morph_names=[]))
        self.assertTrue(validate(path)["valid"])

    def test_default_morph_weights_load_delgada(self):
        for weights in ([1.] * 11, [-1.] + [0.] * 10,
                        [0.] * 10, [float('nan')] + [0.] * 10):
            for location in ('mesh_weights', 'node_weights'):
                with self.subTest(location=location, weights=weights):
                    self.invalid(lambda s: s.update({location: weights}), 'default morph')

    def test_node_morph_defaults_override_mesh_defaults(self):
        report = self.report(lambda s: s.update(mesh_weights=[1.] * 11,
                                               node_weights=[0.] * 11))
        self.assertTrue(report['valid'], report)
        report = self.report(lambda s: s.update(mesh_weights=[0.] * 11))
        self.assertTrue(report['valid'], report)

    def test_hole(self):
        self.invalid(lambda s: s["faces"].pop(), "watertight")

    def test_missing_joint(self):
        self.invalid(lambda s: s["names"].pop(), "joints")

    def test_zero_weights(self):
        self.invalid(lambda s: s.update(zero_weight=True), "weight")

    def test_wrong_morph_count(self):
        self.invalid(lambda s: s.update(bad_morph_count=True), "morph")

    def test_wrong_morph_names(self):
        self.invalid(lambda s: s["morph_names"].__setitem__(0, "height"), "morph")

    def test_indices(self):
        self.invalid(lambda s: s.update(bad_index=True), "indices")

    def test_uv_overlap(self):
        self.invalid(lambda s: s.update(uv_overlap=True), "uv")

    def test_nonfinite(self):
        self.invalid(lambda s: s.update(nan=True), "finite")

    def test_actual_world_pivot(self):
        self.invalid(lambda s: s.update(translation=[0., .2, 0.]), "pivot")

    def test_actual_skinned_world_pivot(self):
        self.invalid(lambda s: s.update(joint_offset=.2), "pivot")

    def test_inverse_bind_mismatch_pivot(self):
        self.invalid(lambda s: s.update(bind_offset=.2), "pivot")

    def test_morph_sole_pivot(self):
        self.invalid(lambda s: s.update(floor_morph=True), "pivot")

    def test_morph_welding_requires_all_deltas(self):
        self.invalid(lambda s: s.update(split_morph=True), "watertight")

    def test_morph_welding_rejects_submicrometre_seam(self):
        self.invalid(lambda s: s.update(tiny_split_morph=True), "watertight")

    def test_raw_seam_cannot_be_hidden_by_different_skin_transforms(self):
        self.invalid(lambda s: s.update(skin_cancels_raw_seam=True), "watertight")

    def test_collapsed_morph(self):
        self.invalid(lambda s: s.update(collapse_morph=True), "degenerate")

    def test_inverted_face(self):
        def change(s):
            s["faces"][0] = tuple(reversed(s["faces"][0]))
        self.invalid(change, "orientation")

    def test_consistent_inward_hull(self):
        self.invalid(lambda s: s.update(faces=[tuple(reversed(f)) for f in s["faces"]]), "outward")

    def test_reversed_unit_shading_normals(self):
        self.invalid(lambda s: s.update(reversed_normals=True), "outward shading normals")

    def test_constant_unit_normals_are_not_outward_on_every_face(self):
        self.invalid(lambda s: s.update(normal_override=(0., 1., 0.)), "outward shading normals")

    def test_pinched_vertex_is_not_a_manifold_surface(self):
        self.invalid(lambda s: s.update(
            points=[(0., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.),
                    (-1., 0., 0.), (-.2, 1., 0.), (0., 0., -1.)],
            faces=[(0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3),
                   (0, 5, 4), (0, 4, 6), (0, 6, 5), (4, 5, 6)]), "manifold")

    def test_cli_reports_malformed_file_without_traceback(self):
        self.path.write_bytes(b"bad")
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("validate_glb.py")),
                                 str(self.path), "--gel-body"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(json.loads(result.stdout)["valid"])
        self.assertNotIn("Traceback", result.stderr)

    def test_coplanar_overlap(self):
        from gel_body_validation import triangle_intersection
        a = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.)]
        b = [(.1, .1, 0.), (.6, .1, 0.), (.1, .6, 0.)]
        self.assertTrue(triangle_intersection(a, b))
        self.assertFalse(triangle_intersection(a, [(1., 0., 0.), (2., 0., 0.), (1., 1., 0.)]))

    def test_noncoplanar_intersection(self):
        from gel_body_validation import triangle_intersection
        self.assertTrue(triangle_intersection(
            [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.)],
            [(.2, .2, -1.), (.2, .2, 1.), (.8, .2, 0.)]))

    def test_near_plane_shared_endpoint_is_not_a_crossing(self):
        """Independent coordinates captured from a valid segmented quad edge.

        Skinning roundoff extended a plane hit 31 nm past the common vertex;
        that point is outside the other triangle, not an interior crossing.
        """
        from gel_body_validation import triangle_intersection
        a = [(0.1592371016740799, -0.11349065601825714, 0.8567417860031128),
             (-2.7388122325611164e-10, -0.12859080731868744, 0.9732456803321838),
             (-6.859862122787774e-10, -0.13005274534225464, 0.8773510456085205)]
        b = [(0.14189526438713074, -0.11699701845645905, 0.9645093083381653),
             (2.3351742761690275e-10, -0.12712886929512024, 1.0691403150558472),
             a[1]]
        c = [a[1], b[1],
             (-0.12455340474843979, -0.12050338089466095, 1.0722767114639282)]
        for first, second in ((a, b), (b, a), (c, a), (a, c)):
            with self.subTest(first=first, second=second):
                self.assertFalse(triangle_intersection(first, second))

    def test_near_plane_and_shared_vertex_real_crossings_remain_detected(self):
        from gel_body_validation import triangle_intersection
        a = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.)]
        for b in ([a[0], (.2, .2, -1.), (.2, .2, 1.)],
                  [(.2, .2, -1e-7), (.2, .2, 1e-7), (.8, .2, 0.)]):
            self.assertTrue(triangle_intersection(a, b))
            self.assertTrue(triangle_intersection(b, a))

    def test_shallow_crossing_with_endpoints_inside_plane_tolerance(self):
        """A transverse segment remains real even when its z offsets are tiny."""
        from gel_body_validation import triangle_intersection
        a = [(-6., 2., 0.), (6., 2., 0.), (0., -100., 0.)]
        b = [(-10., -1., -5e-9), (10., -1., -5e-9), (0., 3., 5e-9)]
        # The actual segment [(-5, 1, 0), (5, 1, 0)] lies inside both triangles.
        self.assertTrue(triangle_intersection(a, b))
        self.assertTrue(triangle_intersection(b, a))

    def test_actual_glb_self_intersection(self):
        def change(s):
            # A closed quad tube follows a figure eight: its crossing is real
            # geometry, not a metadata assertion or an extra disconnected mesh.
            rings, sides = 24, 6
            points = []
            for ring in range(rings):
                t = .07 + math.tau * ring / rings
                dx, dz = math.cos(t), 2 * math.cos(2*t)
                length = math.hypot(dx, dz)
                nx, nz = -dz / length, dx / length
                for side in range(sides):
                    theta = math.tau * side / sides
                    points.append((math.sin(t) + .15 * nx * math.cos(theta),
                                   .15 * math.sin(theta),
                                   math.sin(2*t) + .15 * nz * math.cos(theta)))
            floor = min(p[1] for p in points)
            s["points"] = [(p[0], p[1] - floor, p[2]) for p in points]
            faces = []
            for ring in range(rings):
                for side in range(sides):
                    a = ring * sides + side
                    b = ((ring + 1) % rings) * sides + side
                    c = ((ring + 1) % rings) * sides + (side + 1) % sides
                    d = ring * sides + (side + 1) % sides
                    faces.extend([(a, b, c), (a, c, d)])
            s["faces"] = faces
        self.invalid(change, "self-intersection")

    def test_actual_glb_coplanar_overlap(self):
        def change(s):
            # An octahedron's four equator points lie on one line. Its upper
            # triangles have positive area but overlap in the same plane. No
            # vertex coincidence, open edge or degenerate triangle hides this.
            s["points"] = [(0., 1., 0.), (0., 0., 0.), (1., .5, 0.),
                           (0., .5, 1.), (.8, .5, .2), (.2, .5, .8)]
            s["faces"] = [(0, 2, 3), (0, 3, 4), (0, 4, 5), (0, 5, 2),
                          (1, 3, 2), (1, 4, 3), (1, 5, 4), (1, 2, 5)]
        self.invalid(change, "self-intersection")


if __name__ == "__main__":
    unittest.main()
