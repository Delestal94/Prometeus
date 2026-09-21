class_name Player
extends CharacterBody3D
## On-foot, first-person controller for the loading area: walk up to a
## package or a seat and press interact. WASD/left stick walk, mouse/right
## stick look. The on-foot controller stops consuming input once seated.

const WALK_SPEED: float = 3.6
const GRAVITY: float = 18.0
const MOUSE_SENSITIVITY: float = 0.0028
const PITCH_LIMIT: float = 1.4  # radians, ~80 degrees
@export var stick_sensitivity: float = 2.4

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _hold_point: Marker3D = $Head/Camera3D/HoldPoint
@onready var _probe: Area3D = $Head/InteractionProbe

var carried_package: Node = null
## The package at this player's seat, once they sit down as a passenger.
## Their input reaches its trap through here.
var tended_package: Node = null
var _seated: bool = false
var _pitch: float = 0.0
var _nearby: Array[Node] = []
var _last_prompt: String = ""


func _ready() -> void:
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_probe.area_entered.connect(_on_probe_entered)
	_probe.area_exited.connect(_on_probe_exited)


func _unhandled_input(event: InputEvent) -> void:
	if _seated or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative * MOUSE_SENSITIVITY)
	elif event.is_action_pressed(&"look_center"):
		_pitch = 0.0
		_head.rotation.x = 0.0
	elif event.is_action_pressed(&"interact"):
		_try_interact()


func _physics_process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_publish_prompt("")
		return
	if _seated:
		_publish_prompt("")
		if carried_package != null:
			_update_carried_package()
		if tended_package != null:
			tended_package.set(&"player_input", _gather_package_input())
		return
	var stick: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	_apply_look(stick * stick_sensitivity * delta)
	# get_vector's y is -1 for forward and +1 for back;
	# local forward is -Z, so the two negatives cancel out to a plain +basis.z.
	var input_vector: Vector2 = Input.get_vector(&"drive_left", &"drive_right", &"walk_forward", &"walk_backward")
	var move_direction: Vector3 = (global_basis.x * input_vector.x) + (global_basis.z * input_vector.y)
	if move_direction.length() > 1.0:
		move_direction = move_direction.normalized()
	velocity.x = move_direction.x * WALK_SPEED
	velocity.z = move_direction.z * WALK_SPEED
	velocity.y = -0.2 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if carried_package != null:
		_update_carried_package()
	var target: Node = _closest_interactable()
	_publish_prompt(str(target.call(&"get_prompt")) if target != null else "")


func _apply_look(motion: Vector2) -> void:
	rotate_y(-motion.x)
	_pitch = clampf(_pitch - motion.y, -PITCH_LIMIT, PITCH_LIMIT)
	_head.rotation.x = _pitch


func _gather_package_input() -> Dictionary:
	# One held action covers every "keep it under control" trap, and the walk
	# keys double as the sequence input -- a seated passenger isn't using them
	# to move. Plain data, so the host can apply a remote client's input the
	# same way once networking lands.
	var holding: bool = Input.is_action_pressed(&"package_action_primary")
	var direction: Variant = null
	if Input.is_action_just_pressed(&"walk_forward"):
		direction = &"up"
	elif Input.is_action_just_pressed(&"walk_backward"):
		direction = &"down"
	elif Input.is_action_just_pressed(&"drive_left"):
		direction = &"left"
	elif Input.is_action_just_pressed(&"drive_right"):
		direction = &"right"
	return {"steady": holding, "calm": holding, "direction_pressed": direction}


func tend_package(package: Node) -> void:
	tended_package = package


func _publish_prompt(value: String) -> void:
	if value == _last_prompt:
		return
	_last_prompt = value
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal(&"interaction_prompt_changed", value)


func _update_carried_package() -> void:
	# Position follows the hold point (in front of the camera, so it bobs
	# naturally with head look), but rotation stays tied to the body's yaw
	# only -- looking down doesn't swing the box's face into the lens.
	carried_package.set(&"global_transform", Transform3D(global_basis, _hold_point.global_position))


func _try_interact() -> void:
	var target: Node = _closest_interactable()
	if target != null:
		target.call(&"interact", self)


func _closest_interactable() -> Node:
	var best: Node = null
	var best_distance: float = INF
	for area: Node in _nearby:
		if not is_instance_valid(area):
			continue
		if not bool(area.call(&"can_interact", self)):
			continue
		var distance: float = global_position.distance_to((area as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = area
	return best


func _on_probe_entered(area: Area3D) -> void:
	if area.has_method(&"interact"):
		_nearby.append(area)


func _on_probe_exited(area: Area3D) -> void:
	_nearby.erase(area)


func pick_up(package: Node) -> void:
	carried_package = package
	package.call(&"set_held", true)


func drop_carried() -> void:
	carried_package = null


func board_seat(seat_camera: Node, is_driver: bool, vehicle: Node) -> void:
	_seated = true
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	visible = false
	_camera.current = false
	if seat_camera != null and seat_camera.has_method(&"activate"):
		seat_camera.call(&"activate")
	if is_driver and vehicle != null:
		vehicle.set(&"controls_enabled", true)
