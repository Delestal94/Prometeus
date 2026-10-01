"""Independent metric tests; ordinary Python, no Blender dependency."""
import unittest
from analyze_gel_body import triangle_stretch, summarize, correction_fit


class MetricsTests(unittest.TestCase):
    def test_identity(self):
        tri = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
        self.assertEqual(triangle_stretch(tri, tri), (1., 1.))

    def test_uniform_expansion_not_hidden_as_uv_stability(self):
        base = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
        changed = [(0, 0, 0), (1.3, 0, 0), (0, 1.3, 0)]
        lo, hi = triangle_stretch(base, changed)
        self.assertAlmostEqual(lo, 1.3)
        self.assertAlmostEqual(hi, 1.3)
        self.assertGreater(max(abs(lo-1), abs(hi-1)), .15)

    def test_shear_and_rigid_rotation(self):
        base = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
        self.assertEqual(triangle_stretch(base, [(0, 0, 1), (0, 1, 1), (-1, 0, 1)]), (1., 1.))
        lo, hi = triangle_stretch(base, [(0, 0, 0), (1, 0, 0), (1, 1, 0)])
        self.assertLess(lo, .7)
        self.assertGreater(hi, 1.6)

    def test_degenerate_rejected(self):
        with self.assertRaises(ValueError):
            triangle_stretch([(0, 0, 0)]*3, [(0, 0, 0)]*3)

    def test_missing_rays_not_silently_zero(self):
        report = summarize([.1, None, .3])
        self.assertEqual(report['missing'], 1)
        self.assertAlmostEqual(report['mean_m'], .2)

    def test_correction_reports_asymmetry(self):
        fit = correction_fit([.2, None], [.3, .4], [.05, .2])
        self.assertAlmostEqual(fit['coefficients_m'][0], .125)
        self.assertAlmostEqual(fit['max_extreme_error_m'], .025)
        self.assertIsNone(fit['coefficients_m'][1])


if __name__ == '__main__':
    unittest.main()
