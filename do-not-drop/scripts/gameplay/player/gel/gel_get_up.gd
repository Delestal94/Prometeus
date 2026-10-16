class_name GelGetUp
extends RefCounted
## Two procedural get-up clips sampled by the active ragdoll (S-311.50).
##
## Face-up recovery leads with the torso; face-down recovery plants the arms
## first and delays the hips and legs. Both curves begin at the exact physical
## pose and finish at the animation target, so no authored first-frame pose can
## pop the visible rig.

const FACE_UP: StringName = &"GetUpFaceUp"
const FACE_DOWN: StringName = &"GetUpFaceDown"

const FACE_UP_TIMING: Dictionary = {
	&"chest": 0.00,
	&"head": 0.03,
	&"pelvis": 0.10,
	&"upper_arm.L": 0.15,
	&"upper_arm.R": 0.15,
	&"forearm.L": 0.20,
	&"forearm.R": 0.20,
	&"thigh.L": 0.22,
	&"thigh.R": 0.22,
	&"shin.L": 0.30,
	&"shin.R": 0.30,
}
const FACE_DOWN_TIMING: Dictionary = {
	&"upper_arm.L": 0.00,
	&"upper_arm.R": 0.00,
	&"forearm.L": 0.03,
	&"forearm.R": 0.03,
	&"chest": 0.12,
	&"head": 0.17,
	&"pelvis": 0.25,
	&"thigh.L": 0.32,
	&"thigh.R": 0.32,
	&"shin.L": 0.38,
	&"shin.R": 0.38,
}


## Skeletons face along local -Z. Its vertical sign distinguishes lying on
## the back from lying on the chest; an upright tie safely defaults face-up.
static func select_clip(chest_basis: Basis) -> StringName:
	var face_direction: Vector3 = -chest_basis.orthonormalized().z
	return FACE_UP if face_direction.dot(Vector3.UP) >= 0.0 else FACE_DOWN


static func pose_weight(clip: StringName, bone_name: StringName, progress: float) -> float:
	var timing: Dictionary = FACE_DOWN_TIMING if clip == FACE_DOWN else FACE_UP_TIMING
	var delay: float = float(timing.get(bone_name, 0.0))
	var normalized: float = clampf((progress - delay) / maxf(1.0 - delay, 0.001), 0.0, 1.0)
	return smoothstep(0.0, 1.0, normalized)


static func blend_pose(
	clip: StringName,
	bone_name: StringName,
	physical_pose: Transform3D,
	animation_pose: Transform3D,
	progress: float
) -> Transform3D:
	return physical_pose.interpolate_with(animation_pose, pose_weight(clip, bone_name, progress))
