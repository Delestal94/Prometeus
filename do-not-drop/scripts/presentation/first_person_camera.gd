extends Camera3D
## A seat's own camera, parented directly to the seat anchor -- it inherits
## that seat's moving transform for free through the normal scene tree, no
## per-frame following needed. Starts inactive; a seat interaction calls
## activate(). A short shake on vehicle_impact keeps physical feedback raw
## and un-smoothed, the way PEAK's first-person camera sells its chaos.

@export var shake_decay: float = 6.0
@export var shake_position_scale: float = 0.012
@export var shake_rotation_scale_deg: float = 1.6

var _shake_strength: float = 0.0
var _rng := RandomNumberGenerator.new()
var _base_transform: Transform3D


func _ready() -> void:
	fov = 78.0
	near = 0.03
	_base_transform = transform
	_rng.randomize()
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("vehicle_impact", _on_vehicle_impact)


func activate() -> void:
	current = true


func deactivate() -> void:
	current = false


func _process(delta: float) -> void:
	if not current:
		return
	_shake_strength = maxf(0.0, _shake_strength - shake_decay * delta)
	if _shake_strength <= 0.0:
		transform = _base_transform
		return
	var jitter := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * shake_position_scale * _shake_strength
	var wobble_x: float = deg_to_rad(_rng.randf_range(-1.0, 1.0) * shake_rotation_scale_deg * _shake_strength)
	var wobble_y: float = deg_to_rad(_rng.randf_range(-1.0, 1.0) * shake_rotation_scale_deg * _shake_strength)
	transform = _base_transform.translated_local(jitter).rotated_local(Vector3.RIGHT, wobble_x).rotated_local(Vector3.UP, wobble_y)


func _on_vehicle_impact(strength: float, _impact_position: Vector3) -> void:
	if current:
		_shake_strength = clampf(_shake_strength + strength * 0.15, 0.0, 1.0)
