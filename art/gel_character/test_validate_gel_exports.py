"""Aggregation contract for the finite final-GLB pose gate."""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_gel_exports import validate_exports


class ExportGateTests(unittest.TestCase):
    def test_three_lods_and_morph_states_require_exactly_405_clean_samples(self):
        animations = [{'name': name, 'duration_seconds': duration}
                      for name, duration in {
                          'Idle': 6., 'Walk': 1/3, 'Stroll': .6, 'Run': 1/3,
                          'Jump': 1.6, 'PickUpPackage': 1.6, 'PickUpHigh': 1.6,
                          'Sit': 4., 'TurnInPlace': .8}.items()]
        static = {'valid': True, 'errors': [], 'triangles': 10,
                  'gel_body': {'sample_count': 53}, 'animations': animations}
        samples = [{'contacts': 0, 'orientation_failures': 0} for _ in range(45)]
        with tempfile.TemporaryDirectory() as directory, \
                patch('validate_gel_exports.validate_gel_body', return_value=static) as strict, \
                patch('validate_gel_exports.check_poses', return_value=([], {'samples': samples})) as poses:
            report = validate_exports(Path(directory))
        self.assertTrue(report['valid'], report)
        self.assertEqual(report['sample_count'], 405)
        self.assertEqual(len(report['static']), 3)
        self.assertEqual(len(report['animated']), 9)
        self.assertEqual(strict.call_count, 3)
        self.assertEqual(poses.call_count, 9)

    def test_pose_error_or_missing_sample_fails_gate(self):
        animations = [{'name': name, 'duration_seconds': duration}
                      for name, duration in {
                          'Idle': 6., 'Walk': 1/3, 'Stroll': .6, 'Run': 1/3,
                          'Jump': 1.6, 'PickUpPackage': 1.6, 'PickUpHigh': 1.6,
                          'Sit': 4., 'TurnInPlace': .8}.items()]
        static = {'valid': True, 'errors': [], 'triangles': 10,
                  'gel_body': {'sample_count': 53}, 'animations': animations}
        samples = [{'contacts': 0, 'orientation_failures': 0} for _ in range(44)]
        with tempfile.TemporaryDirectory() as directory, \
                patch('validate_gel_exports.validate_gel_body', return_value=static), \
                patch('validate_gel_exports.check_poses',
                      return_value=(['fold'], {'samples': samples})):
            report = validate_exports(Path(directory))
        self.assertFalse(report['valid'])
        self.assertIn('fold', ' '.join(report['errors']))
        self.assertIn('Expected 405', report['errors'][-1])

    def test_wrong_animation_names_or_durations_fail_gate(self):
        static = {'valid': True, 'errors': [], 'triangles': 10,
                  'gel_body': {'sample_count': 53},
                  'animations': [{'name': 'Idle', 'duration_seconds': 1.}]}
        samples = [{'contacts': 0, 'orientation_failures': 0} for _ in range(45)]
        with tempfile.TemporaryDirectory() as directory, \
                patch('validate_gel_exports.validate_gel_body', return_value=static), \
                patch('validate_gel_exports.check_poses', return_value=([], {'samples': samples})):
            report = validate_exports(Path(directory))
        self.assertFalse(report['valid'])
        self.assertIn('Animation names differ', ' '.join(report['errors']))
        self.assertIn('Idle duration differs', ' '.join(report['errors']))


if __name__ == '__main__':
    unittest.main()
