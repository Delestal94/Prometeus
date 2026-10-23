class_name GelAnimationFit
extends RefCounted
## Proportion-aware presentation math for the gel rig (S-311.25).
## Gameplay speed and collision stay unchanged. Leg length changes the limb
## reach, but the exported IK foot targets keep their authored horizontal
## stride, so gait tempo follows ground speed alone. Low-clearance correction
## moves only the visible model.

const MIN_LENGTH_FACTOR: float = 0.75
const MAX_LENGTH_FACTOR: float = 1.25
## Measured from the exported gel rig's planted-foot windows. Scaling the
## thigh/shin rests changes the IK solve slightly: short legs cover more of the
## authored horizontal target and long legs cover less. One continuous factor
## keeps Walk, Stroll and Run below 2 cm of horizontal drift across the range.
const STRIDE_AT_MIN_LENGTH: float = 1.145
const STRIDE_AT_MAX_LENGTH: float = 0.915


## Matches the measured IK-foot travel to ground speed.
static func gait_speed_scale(
	ground_speed: float,
	authored_speed: float,
	leg_length: float,
	minimum: float,
	maximum: float
) -> float:
	if authored_speed <= 0.0:
		return 1.0
	return clampf(ground_speed / authored_speed, minimum, maximum) / stride_factor(leg_length)


static func stride_factor(leg_length: float) -> float:
	var bounded: float = clampf(leg_length, MIN_LENGTH_FACTOR, MAX_LENGTH_FACTOR)
	if bounded < 1.0:
		return lerpf(STRIDE_AT_MIN_LENGTH, 1.0,
			(bounded - MIN_LENGTH_FACTOR) / (1.0 - MIN_LENGTH_FACTOR))
	return lerpf(1.0, STRIDE_AT_MAX_LENGTH,
		(bounded - 1.0) / (MAX_LENGTH_FACTOR - 1.0))


## Low ceilings and door frames only offset the visible body. The capsule,
## camera, interaction reach and world geometry remain where they are.
static func fit_head_below(
	model: Node3D,
	current_head_top: float,
	clearance_top: float,
	margin: float = 0.02
) -> float:
	if model == null:
		return 0.0
	var offset: float = minf(clearance_top - margin - current_head_top, 0.0)
	model.global_position += Vector3.UP * offset
	return offset
