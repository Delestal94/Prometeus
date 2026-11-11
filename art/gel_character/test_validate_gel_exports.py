"""Aggregation contract for the finite final-GLB pose gate."""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_gel_exports import DURATIONS, EXPECTED_SAMPLES, validate_exports


class ExportGateTests(unittest.TestCase):
    def test_three_lods_and_morph_states_require_exact_sample_matrix(self):
        animations = [{'name': name, 'duration_seconds': duration}
                      for name, duration in DURATIONS.items()]
        static = {'valid': True, 'errors': [], 'triangles': 10,
                  'gel_body': {'sample_count': 53}, 'animations': animations}
        samples = [{'contacts': 0, 'orientation_failures': 0}
                   for _ in range(len(DURATIONS) * 5)]
        with tempfile.TemporaryDirectory() as directory, \
                patch('validate_gel_exports.validate_gel_body', return_value=static) as strict, \
                patch('validate_gel_exports.check_poses', return_value=([], {'samples': samples})) as poses:
            report = validate_exports(Path(directory))
        self.assertTrue(report['valid'], report)
        self.assertEqual(report['sample_count'], EXPECTED_SAMPLES)
        self.assertEqual(len(report['static']), 3)
        self.assertEqual(len(report['animated']), 9)
        self.assertEqual(strict.call_count, 3)
        self.assertEqual(poses.call_count, 9)

    def test_pose_error_or_missing_sample_fails_gate(self):
        animations = [{'name': name, 'duration_seconds': duration}
                      for name, duration in DURATIONS.items()]
        static = {'valid': True, 'errors': [], 'triangles': 10,
                  'gel_body': {'sample_count': 53}, 'animations': animations}
        samples = [{'contacts': 0, 'orientation_failures': 0}
                   for _ in range(len(DURATIONS) * 5 - 1)]
        with tempfile.TemporaryDirectory() as directory, \
                patch('validate_gel_exports.validate_gel_body', return_value=static), \
                patch('validate_gel_exports.check_poses',
                      return_value=(['fold'], {'samples': samples})):
            report = validate_exports(Path(directory))
        self.assertFalse(report['valid'])
        self.assertIn('fold', ' '.join(report['errors']))
        self.assertIn('Expected %d' % EXPECTED_SAMPLES, report['errors'][-1])

    def test_targeted_clip_gate_keeps_all_lods_and_morph_states(self):
        animations = [{'name': name, 'duration_seconds': duration}
                      for name, duration in DURATIONS.items()]
        static = {'valid': True, 'errors': [], 'triangles': 10,
                  'gel_body': {'sample_count': 53}, 'animations': animations}
        samples = [{'contacts': 0, 'orientation_failures': 0} for _ in range(5)]
        with tempfile.TemporaryDirectory() as directory, \
                patch('validate_gel_exports.validate_gel_body', return_value=static), \
                patch('validate_gel_exports.check_poses',
                      return_value=([], {'samples': samples})) as poses:
            report = validate_exports(Path(directory), ['Clap'])
        self.assertTrue(report['valid'], report)
        self.assertEqual(report['sample_count'], 45)
        self.assertTrue(all(call.kwargs['animation_names'] == ['Clap']
                            for call in poses.call_args_list))

    def test_wrong_animation_names_or_durations_fail_gate(self):
        static = {'valid': True, 'errors': [], 'triangles': 10,
                  'gel_body': {'sample_count': 53},
                  'animations': [{'name': 'Idle', 'duration_seconds': 1.}]}
        samples = [{'contacts': 0, 'orientation_failures': 0}
                   for _ in range(len(DURATIONS) * 5)]
        with tempfile.TemporaryDirectory() as directory, \
                patch('validate_gel_exports.validate_gel_body', return_value=static), \
                patch('validate_gel_exports.check_poses', return_value=([], {'samples': samples})):
            report = validate_exports(Path(directory))
        self.assertFalse(report['valid'])
        self.assertIn('Animation names differ', ' '.join(report['errors']))
        self.assertIn('Idle duration differs', ' '.join(report['errors']))


if __name__ == '__main__':
    unittest.main()
