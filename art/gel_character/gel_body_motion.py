"""Endpoint-preserving retarget of rounded-character clips to the gel rig.

Only the derived gel skeleton is changed. Source actions and their timing remain
authoritative; solving the shorter/longer target chains avoids copying an IK
solution authored for different limb proportions.
"""
import math
from mathutils import Matrix, Vector


def _foot_targets(source, target):
    """Preserve source ankle offsets and target rest side spacing."""
    goals = {}
    for side in 'LR':
        name = 'foot.'+side
        source_foot = source.pose.bones[name]
        goal = (target.data.bones[name].head_local
                +(source_foot.head-source_foot.bone.head_local)*.5)
        goals[side] = goal
    return goals


def _wrist_goal(source, target, poses, side):
    hand, grip = 'hand.'+side, 'grip.'+side
    offset = (target.data.bones[hand].matrix_local.inverted()
              @ target.data.bones[grip].head_local)
    return source.pose.bones[grip].head*.5-poses[hand].to_quaternion() @ offset


def _fit_pelvis(target, poses, feet):
    """Small connected hip-height correction for reachable planted ankles.

    Different rest lengths can put a retained ankle trajectory just beyond a
    target leg. Move the whole presentation rig by the nearest feasible shared
    vertical offset, rather than sliding feet or stretching either leg.
    """
    low, high = -math.inf, math.inf
    for side in 'LR':
        upper, lower = 'thigh.'+side, 'shin.'+side
        difference = poses[upper].translation-feet[side]
        reach = target.data.bones[upper].length+target.data.bones[lower].length-1e-5
        horizontal = difference.x*difference.x+difference.y*difference.y
        if horizontal >= reach*reach:
            # No vertical correction can make this goal reachable. The IK
            # residual will expose it rather than hiding a failed trajectory.
            return 0.
        vertical = math.sqrt(reach*reach-horizontal)
        low = max(low, -vertical-difference.z)
        high = min(high, vertical-difference.z)
    if low > high:
        return 0.
    offset = max(low, min(high, 0.))
    # A height change larger than 2 cm is a different animation design; report
    # it through the unmodified IK residual instead of silently rewriting it.
    if abs(offset) > .02:
        return 0.
    for matrix in poses.values():
        matrix.translation += Vector((0., 0., offset))
    return offset


def _reach_torso(target, poses, goals, reaches=None):
    """Lean the connected chest hierarchy to reach the original pickup grips.

    This is a rotation about the existing chest head, not a free translation
    of the shoulder joint. Pelvis, legs and planted foot targets stay unchanged.
    Keep source wrist orientations while solving their new arm chains.
    """
    pivot = poses['chest'].translation.copy()
    def change(angle):
        return (Matrix.Translation(pivot) @ Matrix.Rotation(angle, 4, 'X')
                @ Matrix.Translation(-pivot))
    def reachable(angle):
        motion = change(angle)
        return all((goals[s]-motion @ poses['upper_arm.'+s].translation).length
                   <= (reaches[s] if reaches is not None else
                       target.data.bones['upper_arm.'+s].length
                       +target.data.bones['forearm.'+s].length-1e-5)
                   for s in 'LR')
    if reachable(0.):
        return 0.
    # Bound this presentation-only correction to a readable forward lean.
    # If the bounded connected torso cannot reach, the caller still receives
    # the concrete residual from IK; it must not certify a missed interaction.
    high = math.radians(30.)
    for angle in [math.radians(i*.5) for i in range(1, 61)]:
        if reachable(angle):
            high = angle
            break
    low = max(0., high-math.radians(.5))
    for _ in range(12):
        middle = (low+high)*.5
        if reachable(middle):
            high = middle
        else:
            low = middle
    motion = change(high)
    for name, pose in poses.items():
        bone = target.data.bones[name]
        if name == 'chest' or any(p.name == 'chest' for p in bone.parent_recursive):
            rotation = pose.to_quaternion()
            adjusted = motion @ pose
            if name.startswith(('hand.', 'thumb.', 'grip.')):
                adjusted = Matrix.LocRotScale(adjusted.translation, rotation,
                                              Vector((1., 1., 1.)))
            poses[name] = adjusted
    return high


def _aim(matrix, direction, position):
    """Swing the existing rotation to the requested axis, retaining its twist."""
    rotation = matrix.to_quaternion()
    # Armature world matrices already contain the rest basis; their local Y
    # axis is the bone direction. Multiplying by the world-space rest direction
    # again would apply that basis twice (especially destructive for legs).
    current = rotation @ Vector((0., 1., 0.))
    rotation = current.rotation_difference(direction.normalized()) @ rotation
    return Matrix.LocRotScale(position, rotation, Vector((1., 1., 1.)))


def _solve_chain(target, poses, upper, lower, endpoint, goal, pole):
    """Analytic two-bone IK with an explicit, source-derived bend plane."""
    a, b = target.data.bones[upper], target.data.bones[lower]
    start = poses[upper].translation.copy()
    direction = goal-start
    distance = direction.length
    if distance < 1e-8:
        raise ValueError('Coincident IK endpoint: '+upper)
    direction.normalize()
    # Clamp only unreachable goals, not rotation amplitudes or whole clips.
    reach = min(max(distance, abs(a.length-b.length)+1e-6),
                a.length+b.length-1e-6)
    goal = start+direction*reach
    bend = pole-start
    bend -= direction*bend.dot(direction)
    if bend.length < 1e-8:
        # Choose the Cartesian axis least aligned with the chain; a fixed
        # forward axis becomes zero for a collinear forward-facing pole.
        axis = min(range(3), key=lambda i: abs(direction[i]))
        bend = Vector(tuple(float(i == axis) for i in range(3)))
        bend -= direction*bend.dot(direction)
    if bend.length < 1e-8:
        raise ValueError('Degenerate IK bend plane: '+upper)
    bend.normalize()
    along = (a.length*a.length-b.length*b.length+reach*reach)/(2.*reach)
    height = max(0., a.length*a.length-along*along)**.5
    joint = start+direction*along+bend*height
    poses[upper] = _aim(poses[upper], joint-start, start)
    poses[lower] = _aim(poses[lower], goal-joint, joint)
    poses[endpoint].translation = goal
    return abs(distance-reach)


def adapt_pose(source, target, poses, clip, time):
    """Return gel world matrices and maximum unreachable endpoint distance.

    Called after the ordinary world-rotation retarget and before keyframes.
    Feet retain the source ankle trajectory at 0.5 scale, but use the gel rest
    ankle and side spacing. The bend plane comes from the animated source knee.
    Pickups and sitting preserve the source interaction grips instead of
    reconstructing their positions from a foreign FK chain. An unreachable
    grip is reported, never silently certified as a successful interaction.
    """
    poses = {name: matrix.copy() for name, matrix in poses.items()}
    feet = _foot_targets(source, target)
    _fit_pelvis(target, poses, feet)
    arms = {}
    if clip in ('PickUpPackage', 'PickUpHigh', 'Sit'):
        for side in 'LR':
            goal = _wrist_goal(source, target, poses, side)
            if clip != 'Sit':
                # Freeze the requested blended goal before torso correction.
                # Recomputing it from the already-moved FK wrist changes the
                # target underneath the reach solver during the transition.
                t = max(0., min(1., time/.42))
                blend = t*t*t*(t*(6.*t-15.)+10.)
                goal = poses['hand.'+side].translation.lerp(goal, blend)
            arms[side] = goal
    if clip in ('PickUpPackage', 'PickUpHigh'):
        # Reaching only the maximum target arm length erases the authored elbow
        # bend and collapses its IK circle. Preserve the source bend angle with
        # the target segment lengths; blend this requirement through the same
        # pre-grab transition as the original grip goal.
        reaches = {}
        t = max(0., min(1., time/.42))
        blend = t*t*t*(t*(6.*t-15.)+10.)
        for side in 'LR':
            upper, lower = 'upper_arm.'+side, 'forearm.'+side
            src_upper, src_lower = source.pose.bones[upper], source.pose.bones[lower]
            cosine = max(-1., min(1., (src_upper.tail-src_upper.head).normalized()
                                  .dot((src_lower.tail-src_lower.head).normalized())))
            a, b = target.data.bones[upper].length, target.data.bones[lower].length
            distance = math.sqrt(max(0., a*a+b*b+2.*a*b*cosine))
            reaches[side] = (a+b)*(1.-blend)+distance*blend-1e-5
        _reach_torso(target, poses, arms, reaches)
    maximum = 0.
    for side in 'LR':
        thigh, shin, foot = ('thigh.'+side, 'shin.'+side, 'foot.'+side)
        goal = feet[side]
        pole = (target.data.bones[shin].head_local
                +(source.pose.bones[shin].head
                  -source.data.bones[shin].head_local)*.5)
        maximum = max(maximum, _solve_chain(target, poses, thigh, shin, foot,
                                            goal, pole))
        if clip not in ('PickUpPackage', 'PickUpHigh', 'Sit'):
            continue
        upper, lower, hand = ('upper_arm.'+side, 'forearm.'+side, 'hand.'+side)
        # Match the interaction anchor, not the foreign wrist. The gel hand
        # itself is longer; forcing its wrist to the source wrist would push
        # the grip past the box and can make an otherwise reachable grab fail.
        goal = arms[side]
        pole = source.pose.bones[lower].head*.5
        maximum = max(maximum, _solve_chain(target, poses, upper, lower, hand,
                                            goal, pole))
        # Thumb/grip are children of the wrist: move their attachments with the
        # corrected wrist, keeping their existing world rotations.
        for child in ('thumb.'+side, 'grip.'+side):
            rest = target.data.bones[hand].matrix_local
            poses[child].translation = (poses[hand] @ rest.inverted()
                                       @ target.data.bones[child].matrix_local).translation
    return poses, maximum
