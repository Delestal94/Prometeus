"""Source geometry contract tests; run inside the isolated Blender builder."""
import unittest
import importlib.util
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))


@unittest.skipUnless(importlib.util.find_spec('bpy'), 'requires Blender')
class SourceBodyTests(unittest.TestCase):
    def _weighted_bodies(self):
        import bpy
        import build_gel_body as body
        bpy.ops.wm.open_mainfile(filepath=str(
            body.ROOT/'art/rounded_character/personaje_redondeado.blend'))
        source = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
        for obj in list(bpy.data.objects):
            if obj != source:
                bpy.data.objects.remove(obj, do_unlink=True)
        rig, objects, report = body.build_body_lods(source)
        self._clip_durations = report['durations']
        self._clip_actions = {name: (bpy.data.actions[name], duration)
                              for name, duration in self._clip_durations.items()}
        return source, rig, objects

    def _pose_failures(self, obj, rig, *, shoulder_only=True):
        """Check actual evaluated geometry against transported local normals."""
        import bpy
        from mathutils import Matrix, Vector
        from gel_body_validation import candidate_pairs, triangle_intersection
        obj.data.calc_loop_triangles()
        faces = [tuple(f.vertices) for f in obj.data.loop_triangles]
        base = [v.co.copy() for v in obj.data.vertices]
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        points = [v.co.copy() for v in evaluated.data.vertices]
        triangles = [[tuple(points[i]) for i in f] for f in faces]
        contacts = [(i, j) for i, j in candidate_pairs(triangles)
                    if len(set(faces[i]) & set(faces[j])) < 2
                    and triangle_intersection(triangles[i], triangles[j])]
        transforms = {}
        for bone in rig.pose.bones:
            transforms[bone.name] = bone.matrix @ bone.bone.matrix_local.inverted()
        normals = []
        for vertex in obj.data.vertices:
            blend = Matrix.Identity(4)*0
            for group in vertex.groups:
                name = obj.vertex_groups[group.group].name
                if name in transforms:
                    blend += transforms[name]*group.weight
            normals.append(blend.to_3x3().inverted().transposed())
        flipped = []
        for index, face in enumerate(faces):
            # The transported-normal regression concerns the shoulder junction;
            # contacts above cover the entire surface, including hands/boots.
            if shoulder_only and not any(
                    .1 < abs(base[i].x) < .42 and .95 < base[i].z < 1.27 for i in face):
                continue
            a, b, c = [base[i] for i in face]
            rest_normal = (b-a).cross(c-a)
            expected = sum((normals[i] @ rest_normal for i in face), Vector())
            a, b, c = [points[i] for i in face]
            actual = (b-a).cross(c-a)
            if actual.length < 1e-10 or actual.dot(expected) <= 0:
                flipped.append(index)
        return contacts, flipped

    def test_shoulder_pose_surface_does_not_fold(self):
        """All LODs must retain a noncrossing shoulder through arms-down A90.

        These seven sampled poses do not certify all animations or the
        continuous morph/pose parameter space.
        """
        import bpy
        import math
        from mathutils import Matrix
        import build_gel_body as body
        _, rig, objects = self._weighted_bodies()
        rig.animation_data.action = None
        for angle in (0, 30, 60, 75, 80, 85, 90):
            for bone in rig.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
            bpy.context.view_layer.update()
            for side, sign in (('L', 1), ('R', -1)):
                bone = rig.pose.bones['upper_arm.'+side]
                pivot = bone.bone.head_local
                bone.matrix = (Matrix.Translation(pivot)
                    @ Matrix.Rotation(math.radians(angle)*sign, 4, 'Y')
                    @ Matrix.Translation(-pivot) @ bone.bone.matrix_local)
            bpy.context.view_layer.update()
            for level, obj in zip(body.LOD_LEVELS, objects):
                contacts, flipped = self._pose_failures(obj, rig)
                with self.subTest(level=level, angle=angle, criterion='contact'):
                    self.assertEqual(len(contacts), 0, contacts[:8])
                with self.subTest(level=level, angle=angle, criterion='orientation'):
                    self.assertEqual(len(flipped), 0, flipped[:8])

    def test_weights_repeat_normalize_and_preserve_boots(self):
        """Joint fields must repeat, fit four slots, and retain rigid boot soles."""
        import build_gel_body as body
        _, rig, objects = self._weighted_bodies()
        for level, first in zip(body.LOD_LEVELS, objects):
            second = (body.make_body(0, source=objects[1], rig=rig,
                                     clip_actions=self._clip_actions) if level == 0
                      else body.make_body(level))
            body.assign_weights(second, rig, reference=objects[1] if level == 0 else None)
            self.assertEqual([tuple(v.co) for v in first.data.vertices],
                             [tuple(v.co) for v in second.data.vertices])
            self.assertEqual([tuple(f.vertices) for f in first.data.polygons],
                             [tuple(f.vertices) for f in second.data.polygons])
            for a, b in zip(first.data.vertices, second.data.vertices):
                left = {first.vertex_groups[g.group].name: g.weight for g in a.groups
                        if first.vertex_groups[g.group].name in body.JOINTS}
                right = {second.vertex_groups[g.group].name: g.weight for g in b.groups
                         if second.vertex_groups[g.group].name in body.JOINTS}
                self.assertEqual(left.keys(), right.keys())
                self.assertLessEqual(len(left), 4)
                self.assertAlmostEqual(sum(left.values()), 1., places=6)
                for name in left:
                    self.assertAlmostEqual(left[name], right[name], places=6)
                    self.assertGreater(left[name], 0.)
                if a.co.z <= .14 or (a.co.y <= -.12 and a.co.z <= .21):
                    side = 'L' if a.co.x >= 0 else 'R'
                    expected = {'foot.'+side: 1.}
                    self.assertEqual(left.keys(), expected.keys())
                    for name in expected:
                        self.assertAlmostEqual(left[name], expected[name], places=6)

    def test_sampled_clip_surfaces_do_not_cross_or_fold(self):
        """Nine clips at five explicit times on the actual three-LOD pipeline.

        Contact tests cover the entire surface, including wrist and knee folds.
        This finite source sweep is not a continuous-animation certificate or
        a substitute for checking the exported GLBs independently.
        """
        import bpy
        import build_gel_body as body
        _, rig, objects = self._weighted_bodies()
        for name, duration in self._clip_durations.items():
            rig.animation_data.action = bpy.data.actions[name]
            for fraction in (0., .25, .5, .75, 1.):
                frame = round(duration*bpy.context.scene.render.fps)*fraction
                bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
                bpy.context.view_layer.update()
                for obj in objects:
                    contacts, flipped = self._pose_failures(obj, rig, shoulder_only=False)
                    with self.subTest(clip=name, fraction=fraction, lod=obj.name,
                                      criterion='contact'):
                        self.assertEqual(len(contacts), 0, contacts[:8])
                    with self.subTest(clip=name, fraction=fraction, lod=obj.name,
                                      criterion='orientation'):
                        self.assertEqual(len(flipped), 0, flipped[:8])

    def test_thick_arm_clearance_and_pickup_shoulders(self):
        """Keep the known thick A90 and pickup regressions at all three LODs.

        Morph-rest normals are transported, not compared against unmorphed
        Basis. These directed samples supplement the ordinary clip sweep.
        """
        import bpy
        import math
        from mathutils import Matrix
        import build_gel_body as body
        from gel_pose_validation import pose_surface
        _, rig, objects = self._weighted_bodies()

        def check(morph):
            transforms = [list(map(list, rig.pose.bones[name].matrix
                          @ rig.data.bones[name].matrix_local.inverted()))
                          for name in body.JOINTS]
            for obj in objects:
                obj.data.calc_loop_triangles()
                faces = [tuple(face.vertices) for face in obj.data.loop_triangles]
                points = [list(v.co+body.morph_delta(v.co, morph))
                          for v in obj.data.vertices]
                joints, weights = [], []
                for vertex in obj.data.vertices:
                    scores = [(body.JOINTS.index(obj.vertex_groups[g.group].name),
                               g.weight) for g in vertex.groups]
                    scores += [(0, 0.)]*(4-len(scores))
                    joints.append([i for i, _ in scores])
                    weights.append([w for _, w in scores])
                contacts, flipped = pose_surface(points, faces, joints, weights,
                                                  transforms, list(range(len(points))))
                with self.subTest(lod=obj.name, morph=morph, criterion='contact'):
                    self.assertEqual(contacts, [], contacts[:8])
                with self.subTest(lod=obj.name, morph=morph, criterion='orientation'):
                    self.assertEqual(flipped, [], flipped[:8])

        rig.animation_data.action = None
        for bone in rig.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        for side, sign in (('L', 1), ('R', -1)):
            bone = rig.pose.bones['upper_arm.'+side]
            pivot = bone.bone.head_local
            bone.matrix = (Matrix.Translation(pivot)
                @ Matrix.Rotation(math.pi*.5*sign, 4, 'Y')
                @ Matrix.Translation(-pivot) @ bone.bone.matrix_local)
        bpy.context.view_layer.update()
        for morph in ('general_thickness', 'leg_thickness'):
            with self.subTest(pose='A90'):
                check(morph)
        for clip in ('PickUpPackage', 'PickUpHigh'):
            rig.animation_data.action = bpy.data.actions[clip]
            for time in (.4, .42, 7/12, 1.2):
                frame = time*bpy.context.scene.render.fps
                bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
                bpy.context.view_layer.update()
                with self.subTest(clip=clip, time=time):
                    check('general_thickness')
        rig.animation_data.action = bpy.data.actions['Run']
        for time in (0., 1/12, 1/6, 1/3):
            frame = time*bpy.context.scene.render.fps
            bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
            bpy.context.view_layer.update()
            for morph in ('general_thickness', 'leg_thickness'):
                with self.subTest(clip='Run', time=time, morph=morph):
                    check(morph)

    def test_forward_thumb_has_meaningful_nonfolding_closure(self):
        """Anterior thumbs must really deform the mitten, not be dummy joints."""
        import bpy
        import math
        from mathutils import Matrix
        import build_gel_body as body
        bpy.ops.wm.open_mainfile(filepath=str(
            body.ROOT/'art/rounded_character/personaje_redondeado.blend'))
        source = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
        for obj in list(bpy.data.objects):
            if obj != source:
                bpy.data.objects.remove(obj, do_unlink=True)
        objects = [body.make_body(level) for level in (2, 1)]
        rig = body.create_rig(source)
        for obj in objects:
            body.assign_weights(obj, rig)
            self.assertGreater(sum(any(obj.vertex_groups[g.group].name.startswith('thumb.')
                                       and g.weight > .01 for g in v.groups)
                                   for v in obj.data.vertices), 0)
        for side in 'LR':
            self.assertLess(rig.data.bones['thumb.'+side].head_local.y,
                            rig.data.bones['grip.'+side].head_local.y)
        for angle in (0, -30, 30, -45, 45):
            for bone in rig.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
            bpy.context.view_layer.update()
            for side in 'LR':
                bone = rig.pose.bones['thumb.'+side]
                pivot = bone.bone.head_local
                bone.matrix = (Matrix.Translation(pivot)
                    @ Matrix.Rotation(math.radians(angle), 4, 'X')
                    @ Matrix.Translation(-pivot) @ bone.bone.matrix_local)
            bpy.context.view_layer.update()
            for obj in objects:
                with self.subTest(lod=obj.name, angle=angle):
                    contacts, flipped = self._pose_failures(obj, rig, shoulder_only=False)
                    self.assertEqual(contacts, [], contacts[:8])
                    self.assertEqual(flipped, [], flipped[:8])
                    if angle:
                        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
                        displacement = max((a.co-b.co).length for a, b in
                                           zip(evaluated.data.vertices, obj.data.vertices))
                        self.assertGreater(displacement, .01)

    def test_contract(self):
        import build_gel_body as body
        self.assertEqual(len(body.MORPHS), 11)
        self.assertEqual(len(body.JOINTS), 20)
        self.assertEqual(body.LOD_LEVELS, (2, 1, 0))
        self.assertEqual(body.BUDGETS, (6000, 2500, 800))

    def test_adapted_clips_keep_connected_chains_and_interaction_goals(self):
        """Check every baked keyframe, independently of expensive LOD construction.

        Endpoints and chain gaps do not prove a noncrossing skinned surface;
        the exported-pose validator and visual checks cover that separately.
        """
        import bpy
        import build_gel_body as body
        bpy.ops.wm.open_mainfile(filepath=str(
            body.ROOT/'art/rounded_character/personaje_redondeado.blend'))
        if bpy.context.object and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        source = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
        for obj in list(bpy.data.objects):
            if obj != source:
                bpy.data.objects.remove(obj, do_unlink=True)
        target = body.create_rig(source)
        report = body.bake_clips(source, target)
        self.assertEqual(len(report['durations']), 9)
        for metric in ('maximum_chain_attachment_error_m', 'maximum_ankle_goal_error_m',
                       'maximum_interaction_grip_error_m', 'maximum_unreachable_endpoint_m'):
            self.assertLess(report[metric], 1e-5, (metric, report[metric]))

    def test_lod2_inherits_exact_source_positions_and_weights(self):
        """No new heat solution or shifted morph trajectories in distant LOD."""
        _, _, objects = self._weighted_bodies()
        source, distant = objects[1:]
        indices = distant.data.attributes['LOD1SourceVertex'].data
        for vertex, index in zip(distant.data.vertices, indices):
            original = source.data.vertices[index.value]
            self.assertEqual(tuple(vertex.co), tuple(original.co))
            expected = {source.vertex_groups[g.group].name: g.weight for g in original.groups}
            actual = {distant.vertex_groups[g.group].name: g.weight for g in vertex.groups}
            self.assertEqual(actual, expected)
        distant.data.update()
        for polygon in distant.data.polygons:
            for loop in polygon.loop_indices:
                self.assertGreater(
                    polygon.normal.dot(distant.data.corner_normals[loop].vector), 0.,
                    (polygon.index, loop, polygon.use_smooth))

    def test_morph_defaults_are_base_delgada(self):
        """Authoring and export must start at Basis, not eleven +1 extremes."""
        import build_gel_body as body
        for level in body.LOD_LEVELS:
            obj = body.make_body(level)
            body.decorate(obj)
            self.assertEqual([k.value for k in obj.data.shape_keys.key_blocks[1:]],
                             [0.] * len(body.MORPHS), level)

    def test_thickness_preserves_limb_axes_and_foot_size_controls_boot_length(self):
        """General thickness must not lengthen a running boot into its calf."""
        from mathutils import Vector
        import build_gel_body as body
        boot = Vector((.145, -.22, .07))
        arm = Vector((.74, 0., 1.105))
        leg = Vector((.13, 0., .40))
        self.assertEqual(body.morph_delta(boot, 'general_thickness').y, 0.)
        self.assertLess(body.morph_delta(boot, 'foot_size').y, 0.)
        self.assertEqual(body.morph_delta(arm, 'general_thickness').x, 0.)
        self.assertEqual(body.morph_delta(leg, 'general_thickness').z, 0.)

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

    def test_delgada_front_sections_match_reference(self):
        """The base cage must match the measured neck and shoulder silhouette."""
        import build_gel_body as body

        obj = body.make_body(2)

        def horizontal_span(z):
            crossings = []
            for edge in obj.data.edges:
                a, b = (obj.data.vertices[index].co for index in edge.vertices)
                if min(a.z, b.z) <= z <= max(a.z, b.z) and a.z != b.z:
                    crossings.append(a.x + (b.x-a.x)*(z-a.z)/(b.z-a.z))
            self.assertTrue(crossings, z)
            return max(crossings)-min(crossings)

        # Pixel rows from referencia_frente.jpg converted with H=1038 px,
        # height=1.74 m. A 15% window allows the smooth 3D transition while
        # rejecting the former visibly over-wide neck and shoulders.
        for name, row, target_pixels in (
                ('neck', 383, 192), ('shoulders', 425, 305)):
            z = (1135-row)*(1.74/1038)
            target = target_pixels*(1.74/1038)
            measured = horizontal_span(z)
            self.assertLessEqual(abs(measured/target-1), .15,
                                 (name, measured, target))

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

    def test_lod2_morph_orientation_survives_collapse(self):
        """Keep hip transition loops through the same 53 exported morph samples.

        The former collapse formed a long thin thigh triangle that reversed at
        seeded sample 30. This conservative normal criterion matches the GLB
        validator; it does not certify continuous morphs or all contacts.
        """
        import random
        import build_gel_body as body
        obj = body.make_body(0)
        obj.data.calc_loop_triangles()
        points = [v.co.copy() for v in obj.data.vertices]
        deltas = [[body.morph_delta(p, name) for p in points] for name in body.MORPHS]
        samples = [[0.] * len(body.MORPHS)]
        for index in range(len(body.MORPHS)):
            for extreme in (-1., 1.):
                weights = [0.] * len(body.MORPHS)
                weights[index] = extreme
                samples.append(weights)
        rng = random.Random(311018)
        samples.extend([[rng.uniform(-1., 1.) for _ in body.MORPHS] for _ in range(30)])
        for sample, weights in enumerate(samples):
            posed = [p + sum((ds[i]*w for ds, w in zip(deltas, weights)), p*0)
                     for i, p in enumerate(points)]
            for face in obj.data.loop_triangles:
                a, b, c = [points[i] for i in face.vertices]
                x, y, z = [posed[i] for i in face.vertices]
                self.assertGreater((b-a).cross(c-a).dot((y-x).cross(z-x)), 0.,
                                   (sample, face.index, tuple(face.vertices)))


if __name__ == '__main__':
    unittest.main(argv=['test_gel_body_source'])
