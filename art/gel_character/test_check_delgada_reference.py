"""S-311 reference gate: the Blender-free check reproduces the approved round 149
silhouette IoU exactly and rejects a body that drifts away from the reference."""

from pathlib import Path
import unittest

import numpy as np

from check_delgada_reference import REFERENCE, load_rgb, silhouette_report

APPROVED_MASK = (Path(__file__).resolve().parent
                 / "review_bloque_e/round_149/godot_render_mask.png")


class DelgadaReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reference = load_rgb(REFERENCE)
        cls.mask = load_rgb(APPROVED_MASK)

    def test_reproduces_the_approved_round(self):
        report = silhouette_report(self.mask, self.reference)
        self.assertEqual(report["iou"], 0.920871)
        self.assertEqual(report["intersection_pixels"], 286295)
        self.assertEqual(report["union_pixels"], 310896)
        self.assertTrue(report["passed"])

    def test_a_narrower_body_fails(self):
        body = self.mask.min(axis=2) < 0.5
        shrunk = body.copy()
        for _ in range(6):  # Erode six pixels: about a 2 cm thinner silhouette.
            shrunk[:, 1:] &= body[:, :-1]
            shrunk[:, :-1] &= body[:, 1:]
            body = shrunk.copy()
        thinner = np.where(shrunk[..., None], 0.0, 1.0).repeat(3, axis=2).astype(np.float32)
        report = silhouette_report(thinner, self.reference)
        self.assertLess(report["iou"], 0.92)
        self.assertFalse(report["passed"])

    def test_rejects_a_mismatched_resolution(self):
        with self.assertRaises(ValueError):
            silhouette_report(self.mask[:-1], self.reference)


if __name__ == "__main__":
    unittest.main()
