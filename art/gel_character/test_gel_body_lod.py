"""Pure endpoint-LOD regressions: finite guards, determinism and closed topology."""
import sys
import unittest
import inspect
from unittest.mock import patch
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gel_body_lod import simplify_morph_safe


class MorphSafeLodTests(unittest.TestCase):
    def tetrahedron(self):
        points = np.array(((1,1,1),(-1,-1,1),(-1,1,-1),(1,-1,-1)), dtype=float)
        faces = ((0,2,1),(0,1,3),(0,3,2),(1,2,3))
        return points,faces

    def octahedron(self):
        points = np.array(((0,0,1),(0,0,-1),(1,0,0),(0,1,0),(-1,0,0),(0,-1,0)), dtype=float)
        faces = ((0,2,3),(0,3,4),(0,4,5),(0,5,2),
                 (1,3,2),(1,4,3),(1,5,4),(1,2,5))
        return points,faces

    def assert_closed_unique(self, faces):
        keys = [tuple(sorted(f)) for f in faces]
        self.assertEqual(len(keys),len(set(keys)))
        edges = Counter(tuple(sorted((f[i],f[(i+1)%3]))) for f in faces for i in range(3))
        self.assertTrue(all(count==2 for count in edges.values()))

    def test_tetrahedron_cannot_collapse_to_duplicate_opposite_faces(self):
        """The vertex-neighbor link check alone admits this zero-volume collapse."""
        points,faces = self.tetrahedron()
        kept,result,report = simplify_morph_safe(points,faces,[points],target_triangles=2)
        self.assertEqual(len(kept),4)
        self.assertEqual(report['triangle_count'],4)
        self.assertFalse(report['target_reached'])
        self.assert_closed_unique(result)

    def test_endpoint_result_repeats_and_preserves_protected_source_indices(self):
        points,faces = self.octahedron()
        samples = np.array((points,points*np.array((1.1,.9,1.))))
        first = simplify_morph_safe(points,faces,samples,target_triangles=6,protected_vertices=(0,1))
        second = simplify_morph_safe(points,faces,samples,target_triangles=6,protected_vertices=(0,1))
        self.assertEqual(first,second)
        kept,result,report = first
        self.assertTrue(report['target_reached'])
        self.assertIn(0,kept)
        self.assertIn(1,kept)
        self.assert_closed_unique(result)

    def test_all_protected_mesh_remains_unmodified(self):
        points,faces = self.octahedron()
        kept,result,report = simplify_morph_safe(points,faces,[points],
            target_triangles=6,protected_vertices=range(len(points)))
        self.assertEqual(kept,list(range(len(points))))
        self.assertEqual(result,[list(f) for f in faces])
        self.assertFalse(report['target_reached'])

    def test_identity_pose_samples_match_geometry_only_result(self):
        points,faces = self.octahedron()
        normal_matrices = np.tile(np.eye(3),(1,len(points),1,1))
        kept,result,report = simplify_morph_safe(points,faces,[points],target_triangles=6,
            pose_samples=[points],pose_normal_matrices=normal_matrices)
        self.assertTrue(report['target_reached'])
        self.assertEqual(report['pose_sample_count'],1)
        self.assert_closed_unique(result)

    def test_batched_contacts_match_previous_predicate_order_and_output(self):
        """105 guards cross chunk boundaries without changing any contact call.

        The reference restores only the former contact hot loop; all other QEM
        logic is shared verbatim. No real-body build belongs in this fast test.
        """
        import gel_body_lod
        import gel_body_validation
        source = inspect.getsource(gel_body_lod)
        first = source.index('        # Topology does not vary')
        last = source.index('        if contacts:\n', first)
        reference_loop = '''        for sample in range(len(samples)):
            for index,face in enumerate(proposed):
                possible = np.flatnonzero(active & np.all(minima[sample]<=hi[sample,index]+EPS,axis=1)
                    & np.all(maxima[sample]>=lo[sample,index]-EPS,axis=1))
                for other in possible:
                    if int(other) in excluded or len(set(face)&set(faces[other]))>=2:continue
                    if triangle_intersection(candidate_coordinates[sample,index].tolist(),
                                             samples[sample,faces[other]].tolist()):
                        contacts = True
                        break
                if contacts:break
                for previous in range(index):
                    if len(set(face)&set(proposed[previous]))>=2:continue
                    if triangle_intersection(candidate_coordinates[sample,index].tolist(),
                                             candidate_coordinates[sample,previous].tolist()):
                        contacts = True
                        break
                if contacts:break
            if contacts:break
'''
        namespace = {}
        exec(compile(source[:first]+reference_loop+source[last:], '<reference QEM>', 'exec'), namespace)
        points, faces = self.octahedron()
        morphs = [points*np.array((1+i*.001,1-i*.0005,1.)) for i in range(53)]
        angles = np.arange(52)*.02
        rotations = np.array([((np.cos(a),-np.sin(a),0),
                               (np.sin(a),np.cos(a),0),(0,0,1)) for a in angles])
        poses = np.einsum('sij,vj->svi',rotations,points)
        normals = np.tile(rotations[:,None,:,:],(1,len(points),1,1))
        predicate = gel_body_validation.triangle_intersection
        outcomes = []
        for function in (namespace['simplify_morph_safe'], simplify_morph_safe):
            calls = []
            def recorded(a,b):
                calls.append((a,b))
                return predicate(a,b)
            with patch.object(gel_body_validation,'triangle_intersection',side_effect=recorded):
                result = function(points,faces,morphs,target_triangles=6,
                                  pose_samples=poses,pose_normal_matrices=normals)
            outcomes.append((result,calls))
        self.assertTrue(outcomes[0][1], 'Fixture must exercise contact predicates')
        self.assertEqual(outcomes[0],outcomes[1])

    def test_invalid_inputs_are_rejected(self):
        points,faces = self.tetrahedron()
        invalid_samples = points.copy()
        invalid_samples[0,0] = np.nan
        cases = (
            dict(morph_samples=[points+.1]),
            dict(morph_samples=[points,invalid_samples]),
            dict(morph_samples=[]),
            dict(triangles=[(0,1,20)]),
            dict(triangles=[(0,1,-1)]),
            dict(triangles=[(0,1,2),(2,1,0)]),
            dict(triangles=faces[:-1]),
            dict(pose_samples=[points],pose_normal_matrices=[]),
            dict(protected_vertices=(len(points),)),
        )
        for change in cases:
            arguments = dict(points=points,triangles=faces,morph_samples=[points])
            arguments.update(change)
            with self.subTest(change=change),self.assertRaises(ValueError):
                simplify_morph_safe(**arguments)


if __name__ == '__main__':
    unittest.main()
