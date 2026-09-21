extends Camera3D
## Rigidly follows a seat anchor (driver or passenger) — no smoothing, so every
## bump the vehicle takes reaches the player directly. That rawness is the point:
## PEAK's first-person camera sells its physical chaos the same way. A short
## shake on vehicle_impact adds punch without hiding what the physics already do.

@export var seat_path: NodePath
@export var shake_decay: float = 6.0
@export var shake_position_scale: float = 0.012
@export var shake_rotation_scale_deg: float = 1.6

var _seat: Node3D
var _shake_strength: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_seat = get_node_or_null(seat_path) as Node3D
	current = true
	fov = 78.0
	near = 0.03
	_rng.randomize()
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("vehicle_impact", _on_vehicle_impact)


func _process(delta: float) -> void:
	if not is_instance_valid(_seat):
		return
	global_transform = _seat.global_transform
	_shake_strength = maxf(0.0, _shake_strength - shake_decay * delta)
	if _shake_strength <= 0.0:
		return
	var jitter := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * shake_position_scale * _shake_strength
	translate_object_local(jitter)
	rotate_object_local(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-1.0, 1.0) * shake_rotation_scale_deg * _shake_strength))
	rotate_object_local(Vector3.UP, deg_to_rad(_rng.randf_range(-1.0, 1.0) * shake_rotation_scale_deg * _shake_strength))


func _on_vehicle_impact(strength: float, _impact_position: Vector3) -> void:
	_shake_strength = clampf(_shake_strength + strength * 0.15, 0.0, 1.0)
