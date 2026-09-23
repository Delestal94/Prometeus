extends Camera3D
## Drives the results shot built by SpectatorCamera.orbit_results(): a slow
## circle around the truck, a little above it, looking at the cab.

const RADIUS: float = 9.0
const HEIGHT: float = 3.2
const TURN_SPEED: float = 0.18

var target: Node3D
var _angle: float = 0.6


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_angle += TURN_SPEED * delta
	var centre: Vector3 = target.get_global_transform_interpolated().origin
	global_position = centre + Vector3(cos(_angle) * RADIUS, HEIGHT, sin(_angle) * RADIUS)
	look_at(centre + Vector3.UP * 1.0, Vector3.UP)
