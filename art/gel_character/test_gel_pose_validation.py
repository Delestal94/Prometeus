"""Fast stdlib pose-validator fixtures; no Blender or real-asset sweeps.

Protect glTF interpolation, exact trajectory welding, transported normals and
concrete surface crossing diagnostics. Real 9-clip asset gates run separately.
"""
import math
import sys
import unittest
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gel_pose_validation import check_asset, sample_channel, pose_surface
from gel_body_validation import matrix


class ToyAsset:
    def __init__(self):
        self.rows = [
            [(0.,0.,0.), (1.,0.,0.), (0.,1.,0.)],
            [(0,0,0,0)]*3, [(1.,0.,0.,0.)]*3,
            [(0,), (1,), (2,)], [(0.,), (1.,)],
            [(0.,0.,0.), (2.,0.,0.)],
        ]
        self.data = {'nodes': [{'children': [1], 'translation': [3.,0.,0.]},
                               {}, {'mesh': 0, 'skin': 0}],
                     'skins': [{'joints': [1]}],
                     'meshes': [{'primitives': [{'attributes':
                         {'POSITION': 0, 'JOINTS_0': 1, 'WEIGHTS_0': 2}, 'indices': 3}]}],
                     'animations': [{'name': 'Move', 'samplers': [{'input': 4, 'output': 5}],
                         'channels': [{'sampler': 0, 'target': {'node': 1, 'path': 'translation'}}]}]}

    def accessor(self, index):
        return self.rows[index]


class PoseValidationTests(unittest.TestCase):
    def surface(self, points=None, faces=None, transforms=None, keys=None, weights=None, joints=None):
        points = points or [(0.,0.,0.), (1.,0.,0.), (0.,1.,0.)]
        return pose_surface(points, faces or [(0,1,2)],
                            joints or [(0,0,0,0)]*len(points),
                            weights or [(1.,0.,0.,0.)]*len(points),
                            transforms or [matrix({})], keys or list(points))

    def test_linear_translation_clamps_and_step_holds(self):
        values = [(0.,0.,0.), (2.,4.,6.)]
        self.assertEqual(sample_channel([1.,3.], values, 2., 'translation'), (1.,2.,3.))
        self.assertEqual(sample_channel([1.,3.], values, -10., 'translation'), values[0])
        self.assertEqual(sample_channel([1.,3.], values, 10., 'translation'), values[1])
        self.assertEqual(sample_channel([1.,3.], values, 2., 'translation', 'STEP'), values[0])
        self.assertEqual(sample_channel([1.,3.], values, 3., 'translation', 'STEP'), values[1])

    def test_quaternion_slerp_and_antipodal(self):
        q = sample_channel([0.,1.], [(0.,0.,0.,1.), (0.,0.,1.,0.)], .5, 'rotation')
        self.assertAlmostEqual(q[2], math.sqrt(.5))
        self.assertAlmostEqual(q[3], math.sqrt(.5))
        q = sample_channel([0.,1.], [(0.,0.,0.,1.), (0.,0.,0.,-1.)], .5, 'rotation')
        self.assertEqual(q, (0.,0.,0.,1.))

    def test_rigid_rotation_is_not_surface_fold(self):
        self.assertEqual(self.surface(transforms=[matrix({'rotation': [1.,0.,0.,0.]})]), ([], []))
        self.assertEqual(self.surface(transforms=[matrix({'translation': [3.,-2.,1.]})]), ([], []))

    def test_invalid_skin_data_rejected(self):
        for changes in ({'weights': [(float('nan'),0.,0.,0.)]*3},
                        {'weights': [(1.1,-.1,0.,0.)]*3},
                        {'weights': [(.5,0.,0.,0.)]*3},
                        {'joints': [(-1,0,0,0)]*3},
                        {'joints': [(1,0,0,0)]*3},
                        {'faces': [(-1,1,2)]},
                        {'transforms': [matrix({'scale': [0.,1.,1.]})]}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.surface(**changes)

    def test_invalid_interpolation_and_nonfinite_rejected(self):
        for times, values, mode in (([0.,0.], [(0.,0.,0.)]*2, 'LINEAR'),
                                    ([0.,1.], [(0.,0.,0.)]*2, 'CUBICSPLINE'),
                                    ([0.,float('nan')], [(0.,0.,0.)]*2, 'STEP'),
                                    ([0.,1.], [(0.,0.,0.), (float('nan'),0.,0.)], 'LINEAR')):
            with self.assertRaises(ValueError):
                sample_channel(times, values, .5, 'translation', mode)

    def test_crossing_with_shared_vertex_is_not_excluded(self):
        points = [(0.,0.,0.), (2.,0.,0.), (0.,2.,0.), (1.,1.,-1.), (1.,1.,1.)]
        contacts, _ = self.surface(points, [(0,1,2), (0,3,4)])
        self.assertTrue(contacts)

    def test_exact_edge_weld_requires_same_trajectory(self):
        points = [(0.,0.,0.), (2.,0.,0.), (0.,2.,0.),
                  (0.,0.,0.), (2.,0.,0.), (1.,.5,0.)]
        # Overlap is adjacent only when the two exact duplicate edge endpoints
        # have identical raw morph/skin trajectories, not merely close positions.
        contacts, _ = self.surface(points, [(0,1,2), (3,4,5)])
        self.assertFalse(contacts)
        contacts, _ = self.surface(points, [(0,1,2), (3,4,5)], keys=list(range(6)))
        self.assertTrue(contacts)

    def test_hierarchy_animation_and_error_report(self):
        transforms = []
        def capture(points, faces, joints, weights, matrices, keys):
            transforms.append(matrices)
            return pose_surface(points, faces, joints, weights, matrices, keys)
        with patch('gel_pose_validation.pose_surface', side_effect=capture):
            errors, report = check_asset(ToyAsset(), 0)
        self.assertFalse(errors, errors)
        self.assertEqual(len(report['samples']), 5)
        self.assertEqual(report['samples'][-1]['time'], 1.)
        self.assertIn('not continuous', report['scope'])
        self.assertEqual([m[0][0][3] for m in transforms], [3.,3.5,4.,4.5,5.])
        toy = ToyAsset()
        toy.data['nodes'][1]['children'] = [0]
        errors, _ = check_asset(toy, 0)
        self.assertIn('Node hierarchy cycle', errors)

    def test_actual_joint_world_and_inverse_bind_used(self):
        toy = ToyAsset()
        # Three independently moving joints fold this triangle only if the
        # animated parent translation and per-joint inverse bind are applied.
        toy.data['nodes'] = [{'children': [1,2,3]}, {}, {}, {}, {'mesh':0,'skin':0}]
        toy.data['skins'] = [{'joints':[1,2,3], 'inverseBindMatrices':6}]
        toy.rows[1] = [(0,0,0,0), (1,0,0,0), (2,0,0,0)]
        identity = tuple(matrix({})[i][j] for j in range(4) for i in range(4))
        shift = tuple(matrix({'translation':[0.,-3.,0.]})[i][j] for j in range(4) for i in range(4))
        toy.rows.append([identity, identity, shift])
        errors, report = check_asset(toy, 0, fractions=(0.,))
        self.assertTrue(errors)
        self.assertEqual(report['samples'][0]['orientation_failures'], 1)

    def test_malformed_asset_returns_explicit_errors(self):
        for mutate in (lambda a: a.data['animations'][0]['samplers'][0].update(interpolation='CUBICSPLINE'),
                       lambda a: a.rows[0].__setitem__(0, (float('nan'),0.,0.)),
                       lambda a: a.rows[1].__setitem__(0, (-1,0,0,0)),
                       lambda a: a.data['nodes'][1].update(scale=[0.,1.,1.])):
            toy = ToyAsset()
            mutate(toy)
            errors, _ = check_asset(toy, 0)
            self.assertTrue(errors)


if __name__ == '__main__':
    unittest.main()
