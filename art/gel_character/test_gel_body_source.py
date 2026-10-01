"""Source geometry contract tests; run inside the isolated Blender builder."""
import unittest
import importlib.util
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))


@unittest.skipUnless(importlib.util.find_spec('bpy'), 'requires Blender')
class SourceBodyTests(unittest.TestCase):
    def test_contract(self):
        import build_gel_body as body
        self.assertEqual(len(body.MORPHS), 11)
        self.assertEqual(len(body.JOINTS), 20)
        self.assertEqual(body.LOD_LEVELS, (2, 1, 0))
        self.assertEqual(body.BUDGETS, (6000, 2500, 800))

    def test_geometry(self):
        import build_gel_body as body
        import bmesh
        for level, budget in zip(body.LOD_LEVELS, body.BUDGETS):
            obj = body.make_body(level)
            mesh = bmesh.new()
            mesh.from_mesh(obj.data)
            # Main authoring meshes remain quads. Derived distant LOD2 uses
            # conventional triangulated surface simplification, not a retopology.
            expected_size = 4 if level else 3
            self.assertTrue(all(len(f.verts) == expected_size for f in mesh.faces))
            self.assertTrue(all(e.is_manifold for e in mesh.edges))
            remaining = set(mesh.verts)
            pending = [remaining.pop()]
            while pending:
                vertex = pending.pop()
                for edge in vertex.link_edges:
                    neighbor = edge.other_vert(vertex)
                    if neighbor in remaining:
                        remaining.remove(neighbor)
                        pending.append(neighbor)
            self.assertFalse(remaining, 'Body must be exactly one connected surface')
            self.assertLessEqual(sum(len(f.verts)-2 for f in mesh.faces), budget)
            self.assertAlmostEqual(min(v.co.z for v in mesh.verts), 0, places=6)
            self.assertAlmostEqual(max(v.co.z for v in mesh.verts), 1.74, places=5)
            proportions = body.measured_proportions(obj)
            for name, target in (('arm_shoulder_to_hand_m', 1.74*.391),
                                 ('head_diameter_m', 1.74/3.68)):
                self.assertLessEqual(abs(proportions[name]/target-1), .05,
                                     (level, name, proportions[name], target))
            self.assertGreaterEqual(proportions['torso_waist_width_m'], .40)
            self.assertLessEqual(proportions['torso_waist_width_m'], .43)
            self.assertGreaterEqual(proportions['foot_forward_reach_m'], .18)
            self.assertGreaterEqual(proportions['foot_depth_m'], .23)
            self.assertGreaterEqual(proportions['flat_sole_vertices'], 4)
            self.assertGreaterEqual(proportions['flat_sole_depth_m'], .15)
            self.assertLessEqual(abs(proportions['foot_width_m']/(.57*1.74/3.68)-1), .05)
            for vertex in obj.data.vertices:
                if vertex.co.z < .14 and vertex.co.x > 0:
                    grown = vertex.co + body.morph_delta(vertex.co, 'foot_size')
                    self.assertGreater(grown.x, 0, 'Enlarged boots must retain the center gap')
            mesh.free()

    def test_lod2_flat_sole_survives_collapse(self):
        """Plane-error collapse must not erase or fold the flat sole boundary."""
        import build_gel_body as body
        from gel_body_validation import candidate_pairs, triangle_intersection
        source, distant = body.make_body(1), body.make_body(0)
        sole = {tuple(v.co) for v in source.data.vertices if abs(v.co.z) < 1e-6}
        self.assertEqual(sole, {tuple(v.co) for v in distant.data.vertices
                               if abs(v.co.z) < 1e-6})
        faces = [tuple(f.vertices) for f in distant.data.polygons]
        triangles = [[tuple(distant.data.vertices[i].co) for i in f] for f in faces]
        for i, j in candidate_pairs(triangles):
            if len(set(faces[i]) & set(faces[j])) >= 2:
                continue
            if any(abs(p[2]) < 1e-6 for p in triangles[i] + triangles[j]):
                self.assertFalse(triangle_intersection(triangles[i], triangles[j]), (i, j))


if __name__ == '__main__':
    unittest.main(argv=['test_gel_body_source'])
