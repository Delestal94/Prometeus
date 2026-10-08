class_name GelAnimationFit
extends RefCounted
## Proportion-aware presentation math for the gel rig (S-311.25).
## Gameplay speed and collision stay unchanged: leg length only changes gait
## playback, while low-clearance correction moves the visible model.

const MIN_LENGTH_FACTOR: float = 0.75
const MAX_LENGTH_FACTOR: float = 1.25


## Scales the existing gait rate inversely with leg length. The distance the
## player covers during one clip cycle therefore grows with the visual stride.
static func gait_speed_scale(
	ground_speed: float,
	authored_speed: float,
	leg_length: float,
	minimum: float,
	maximum: float
) -> float:
	if authored_speed <= 0.0:
		return 1.0
	var bounded_length: float = clampf(leg_length, MIN_LENGTH_FACTOR, MAX_LENGTH_FACTOR)
	return clampf(ground_speed / authored_speed, minimum, maximum) / bounded_length


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
