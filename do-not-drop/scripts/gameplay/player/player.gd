class_name Player
extends CharacterBody3D
## On-foot, first-person controller for the loading area: walk up to a
## package or a seat and press interact. Reuses the driving axes for
## walking -- the two contexts never overlap, since seat_point.gd disables
## free movement the moment a player boards.

const WALK_SPEED: float = 3.6
const GRAVITY: float = 18.0
const MOUSE_SENSITIVITY: float = 0.0028
const PITCH_LIMIT: float = 1.4  # radians, ~80 degrees

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _hold_point: Marker3D = $Head/Camera3D/HoldPoint
@onready var _probe: Area3D = $Head/InteractionProbe

var carried_package: Node = null
var _seated: bool = false
var _pitch: float = 0.0
var _nearby: Array[Node] = []


func _ready() -> void:
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_probe.area_entered.connect(_on_probe_entered)
	_probe.area_exited.connect(_on_probe_exited)


func _unhandled_input(event: InputEvent) -> void:
	if _seated:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
		_head.rotation.x = _pitch
	elif event.is_action_pressed(&"interact"):
		_try_interact()


func _physics_process(delta: float) -> void:
	if _seated:
		if carried_package != null:
			carried_package.set(&"global_transform", _hold_point.global_transform)
		return
	var input_vector: Vector2 = Input.get_vector(&"drive_left", &"drive_right", &"drive_accelerate", &"drive_brake")
	var move_direction: Vector3 = (global_basis.x * input_vector.x) - (global_basis.z * input_vector.y)
	if move_direction.length() > 1.0:
		move_direction = move_direction.normalized()
	velocity.x = move_direction.x * WALK_SPEED
	velocity.z = move_direction.z * WALK_SPEED
	velocity.y = -0.2 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if carried_package != null:
		carried_package.set(&"global_transform", _hold_point.global_transform)


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
	visible = false
	_camera.current = false
	if seat_camera != null and seat_camera.has_method(&"activate"):
		seat_camera.call(&"activate")
	if is_driver and vehicle != null:
		vehicle.set(&"controls_enabled", true)
