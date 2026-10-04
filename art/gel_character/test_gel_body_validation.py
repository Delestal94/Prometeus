"""Exact shared-plane identity regressions from evaluated Jump float32 soles.

Run: python -m unittest discover -s art/gel_character -p test_gel_body_validation.py
No Blender or asset builds. Point adjacency must not hide a genuine crossing.
"""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gel_body_validation import triangle_intersection


class SharedPlaneIdentityTests(unittest.TestCase):
    def test_jump_rigid_sole_shared_vertex_has_no_phantom_crossing(self):
        # Exact coordinates from evaluated LOD0 Jump frame24. The former dot
        # product assigned the shared vertex a -2.25e-20 signed distance and
        # manufactured a hit10.11695nm away, outside EPS and outside the face.
        sole = [(0.0631839707493782,-0.16201962530612946,0.16420167684555054),
                (0.039854343980550766,-0.17012935876846313,0.16333523392677307),
                (0.028589263558387756,-0.13623474538326263,0.16695652902126312)]
        neighbors = [
            [(0.07442498952150345,-0.18503324687480927,0.1617428958415985),
             (0.06356901675462723,-0.1961166113615036,0.1605587601661682),
             sole[1]],
            [(0.06356901675462723,-0.1961166113615036,0.1605587601661682),
             (0.03195815533399582,-0.18810191750526428,0.2407168745994568),
             sole[1]],
        ]
        for neighbor in neighbors:
            for first,second in ((sole,neighbor),(neighbor,sole)):
                with self.subTest(first=first,second=second):
                    self.assertFalse(triangle_intersection(first,second))
                    self.assertFalse(triangle_intersection([tuple(p) for p in first],
                                                           [list(p) for p in second]))

    def test_shared_vertex_does_not_exclude_crossing_elsewhere(self):
        first = [(0.,0.,0.),(2.,0.,0.),(0.,2.,0.)]
        second = [(0.,0.,0.),(1.,1.,-1.),(1.,1.,1.)]
        self.assertTrue(triangle_intersection(first,second))
        self.assertTrue(triangle_intersection(second,first))


if __name__ == '__main__':
    unittest.main()
