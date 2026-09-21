extends Camera3D
## A seat's own camera, parented directly to the seat anchor -- it inherits
## that seat's moving transform for free through the normal scene tree, no
## per-frame following needed. Mouse/right stick rotate relative to that anchor,
## C/right-stick click recenter. A seat interaction calls activate().
## A short shake on vehicle_impact keeps physical feedback raw
## and un-smoothed, the way PEAK's first-person camera sells its chaos.

@export var shake_decay: float = 6.0
@export var shake_position_scale: float = 0.012
@export var shake_rotation_scale_deg: float = 1.6
@export var mouse_sensitivity: float = 0.0028
@export var stick_sensitivity: float = 2.4  ## Radians per second at full deflection.
@export_range(0.0, 180.0) var yaw_limit_degrees: float = 160.0
@export_range(0.0, 89.0) var pitch_limit_degrees: float = 80.0

var _shake_strength: float = 0.0
var _rng := RandomNumberGenerator.new()
var _base_transform: Transform3D
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0


func _ready() -> void:
	fov = 78.0
	near = 0.03
	_base_transform = transform
	_rng.randomize()
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("vehicle_impact", _on_vehicle_impact)


func activate() -> void:
	reset_look()
	current = true


func deactivate() -> void:
	current = false
	_shake_strength = 0.0
	reset_look()


func reset_look() -> void:
	_look_yaw = 0.0
	_look_pitch = 0.0
	transform = _base_transform


func _can_look() -> bool:
	return current and not get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _can_look():
		return
	if event is InputEventMouseMotion:
		_apply_look(event.relative * mouse_sensitivity)
	elif event.is_action_pressed(&"look_center"):
		reset_look()
		get_viewport().set_input_as_handled()


func _apply_look(motion: Vector2) -> void:
	_look_yaw = clampf(_look_yaw - motion.x, -deg_to_rad(yaw_limit_degrees), deg_to_rad(yaw_limit_degrees))
	_look_pitch = clampf(_look_pitch - motion.y, -deg_to_rad(pitch_limit_degrees), deg_to_rad(pitch_limit_degrees))


func _look_transform() -> Transform3D:
	# Look is relative to the seat; head rotation must not rotate the eye position.
	var pose := _base_transform
	pose.basis = _base_transform.basis * Basis(Vector3.UP, _look_yaw) * Basis(Vector3.RIGHT, _look_pitch)
	return pose


func _process(delta: float) -> void:
	if not current:
		return
	if get_tree().paused:
		return
	if _can_look():
		var stick: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		_apply_look(stick * stick_sensitivity * delta)
	var look_pose: Transform3D = _look_transform()
	_shake_strength = maxf(0.0, _shake_strength - shake_decay * delta)
	if _shake_strength <= 0.0:
		transform = look_pose
		return
	var jitter := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * shake_position_scale * _shake_strength
	var wobble_x: float = deg_to_rad(_rng.randf_range(-1.0, 1.0) * shake_rotation_scale_deg * _shake_strength)
	var wobble_y: float = deg_to_rad(_rng.randf_range(-1.0, 1.0) * shake_rotation_scale_deg * _shake_strength)
	transform = look_pose.translated_local(jitter).rotated_local(Vector3.RIGHT, wobble_x).rotated_local(Vector3.UP, wobble_y)


func _on_vehicle_impact(strength: float, _impact_position: Vector3) -> void:
	if current:
		_shake_strength = clampf(_shake_strength + strength * 0.15, 0.0, 1.0)
