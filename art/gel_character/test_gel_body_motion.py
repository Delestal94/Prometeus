"""Fast isolated Blender IK contracts; no body builds or source assets.

Protect both unreachable-distance bounds, pole singularities, chain continuity
and adapt_pose input ownership. Plain Python explicitly skips Blender fixtures.
"""
import importlib.util
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))


@unittest.skipUnless(importlib.util.find_spec('bpy'), 'requires Blender')
class MotionContractTests(unittest.TestCase):
    def rig(self, first=.5, second=.5):
        import bpy
        bpy.ops.wm.read_factory_settings(use_empty=True)
        data = bpy.data.armatures.new('IKContract')
        rig = bpy.data.objects.new('IKContract', data)
        bpy.context.collection.objects.link(rig)
        bpy.context.view_layer.objects.active = rig
        rig.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        for side, sign in (('L',1), ('R',-1)):
            for name, y, length, parent in (
                    ('thigh',0.,first,None), ('shin',first,second,'thigh'),
                    ('foot',first+second,.2,'shin')):
                bone = data.edit_bones.new(name+'.'+side)
                bone.head = (sign,y,0.)
                bone.tail = (sign,y+length,0.)
                if parent:
                    bone.parent = data.edit_bones[parent+'.'+side]
        bpy.ops.object.mode_set(mode='OBJECT')
        bpy.context.view_layer.update()
        return rig, {b.name: b.matrix_local.copy() for b in data.bones}

    def solved(self, first, second, offset, pole):
        from mathutils import Vector
        from gel_body_motion import _solve_chain
        rig, poses = self.rig(first, second)
        start = poses['thigh.L'].translation.copy()
        wanted = start+Vector(offset)
        residual = _solve_chain(rig, poses, 'thigh.L', 'shin.L', 'foot.L',
                                wanted, start+Vector(pole))
        joint, end = poses['shin.L'].translation, poses['foot.L'].translation
        upper_tip = start+poses['thigh.L'].to_quaternion()@Vector((0.,first,0.))
        lower_tip = joint+poses['shin.L'].to_quaternion()@Vector((0.,second,0.))
        self.assertAlmostEqual((joint-start).length, first, places=5)
        self.assertAlmostEqual((end-joint).length, second, places=5)
        self.assertLess((upper_tip-joint).length, 1e-5)
        self.assertLess((lower_tip-end).length, 1e-5)
        self.assertAlmostEqual(residual, (end-wanted).length, places=5)
        return residual

    def test_reachable_chain_preserves_lengths_and_endpoint(self):
        self.assertLess(self.solved(.5,.5,(.6,.2,0.),(0.,0.,1.)), 1e-5)

    def test_unreachable_inner_and_outer_bounds_are_reported(self):
        self.assertGreater(self.solved(1.,.5,(.1,0.,0.),(0.,1.,0.)), .39)
        self.assertGreater(self.solved(.5,.5,(2.,0.,0.),(0.,1.,0.)), .99)

    def test_collinear_pole_does_not_disconnect_bones(self):
        self.assertLess(self.solved(.5,.5,(0.,-.8,0.),(0.,-.4,0.)), 1e-5)

    def test_adaptation_does_not_mutate_input_matrices(self):
        from gel_body_motion import adapt_pose
        rig, poses = self.rig()
        before = {n: tuple(tuple(row) for row in m) for n,m in poses.items()}
        adapted, residual = adapt_pose(rig, rig, poses, 'Idle', 0.)
        self.assertEqual(before, {n: tuple(tuple(row) for row in m) for n,m in poses.items()})
        self.assertIsNot(adapted, poses)
        self.assertTrue(all(adapted[n] is not poses[n] for n in poses))
        self.assertLess(residual, 1e-5)


if __name__ == '__main__':
    unittest.main(argv=['test_gel_body_motion'])
