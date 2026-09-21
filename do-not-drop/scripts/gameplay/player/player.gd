class_name Player
extends CharacterBody3D
## On-foot, first-person controller for the loading area: walk up to a
## package or a seat and press interact. WASD/left stick walk, mouse/right
## stick look. The on-foot controller stops consuming input once seated.
##
## Movement/look/camera stay authoritative on the owning peer -- client-side,
## like most co-op party games, since nothing here is competitive enough to
## be worth fighting latency over. Game *decisions* (did the interaction
## succeed, who's carrying what) are the host's call; see interactable.gd
## and the RPC methods below, which the host calls on this specific peer to
## announce the outcome.

const WALK_SPEED: float = 3.6
const GRAVITY: float = 18.0
const MOUSE_SENSITIVITY: float = 0.0028
const PITCH_LIMIT: float = 1.4  # radians, ~80 degrees
@export var stick_sensitivity: float = 2.4

## One color per player so teammates can be told apart at a glance -- there's
## no cosmetics system yet (docs/plan-desarrollo.md Fase 5), so this is the
## cheapest thing that actually solves "who is that". Same palette family as
## the rest of the UI (docs/direccion-visual.md), picked by peer id so it's
## stable and doesn't need any network sync of its own.
const PLAYER_COLORS: Array[Color] = [
	Color("83e2ba"), Color("f4c562"), Color("f47e6d"), Color("6db3d6"), Color("c9a0e0"),
]

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
	_build_body()
	# Only the player this peer controls owns the view and reads input;
	# everyone else's body is here to be seen, not driven.
	if not is_local():
		_camera.current = false
		return
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_probe.area_entered.connect(_on_probe_entered)
	_probe.area_exited.connect(_on_probe_exited)


## A placeholder capsule matching the collision shape, so teammates actually
## have someone to see at all -- until now only the viewmodel hands existed,
## which are attached to this player's own camera and so only ever visible
## to themselves. Colored per peer_id (see PLAYER_COLORS) doubles as the
## simplest possible "who is that" cue. Own camera can see its own body too
## (no per-camera render-layer split yet) -- a minor rough edge, acceptable
## while everything here is still placeholder geometry.
func _build_body() -> void:
	var color: Color = PLAYER_COLORS[get_multiplayer_authority() % PLAYER_COLORS.size()]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = 1.6
	mesh.mesh = capsule
	mesh.material_override = material
	mesh.position = Vector3(0.0, 0.8, 0.0)
	add_child(mesh)
	for hand: MeshInstance3D in [_camera.get_node(^"LeftHand"), _camera.get_node(^"RightHand")]:
		var hand_material := StandardMaterial3D.new()
		hand_material.albedo_color = color.lightened(0.3)
		hand_material.roughness = 0.85
		hand.material_override = hand_material


func is_local() -> bool:
	return is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# Ping works seated or not -- it's communication, not a physical action,
	# so it's checked before the _seated gate below applies to the rest.
	if event.is_action_pressed(&"ui_ping"):
		_send_ping()
		return
	if _seated:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative * MOUSE_SENSITIVITY)
	elif event.is_action_pressed(&"look_center"):
		_pitch = 0.0
		_head.rotation.x = 0.0
	elif event.is_action_pressed(&"interact"):
		_try_interact()


func _physics_process(delta: float) -> void:
	if not is_local():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_publish_prompt("")
		return
	if _seated:
		_publish_prompt("")
		if carried_package != null:
			_update_carried_package()
		if tended_package != null:
			tended_package.rpc_id(1, &"submit_tender_input", _gather_package_input())
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
	# to move.
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
	# only -- looking down doesn't swing the box's face into the lens. Goes
	# through the host either way (rpc_id(1, ...) with call_local resolves to
	# a direct call when this peer already is the host), since the package is
	# host-authoritative and only it should ever move the real one.
	var carry_transform := Transform3D(global_basis, _hold_point.global_position)
	carried_package.rpc_id(1, &"submit_carry_transform", carry_transform)


## MVP has a single, always-available ping ("¡Cuidado!") instead of a wheel
## of options -- docs/controles-y-ui.md sketches "¡ayuda!"/"¡cuidado!" as
## examples, not a mandate, and one message covers the actual need (warn
## teammates) without a second input to design around it.
const PING_LABEL: String = "¡Cuidado!"


func _send_ping() -> void:
	if NetworkManager.is_online() and not NetworkManager.is_host():
		EventBus.rpc_id(1, &"request_ping", global_position, PING_LABEL)
	else:
		EventBus.call(&"request_ping", global_position, PING_LABEL)


func _try_interact() -> void:
	var target: Node = _closest_interactable()
	if target == null:
		return
	if NetworkManager.is_online() and not NetworkManager.is_host():
		target.rpc_id(1, &"request_interact")
	else:
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


## The host announces the outcome of an interaction by calling these on the
## specific peer they concern (rpc_id(target_peer, ...)), never broadcast --
## nobody else needs to know that *I* am now holding this box, only that the
## box itself moved (which its own MultiplayerSynchronizer already covers).
## _from_host() guards every one, since any_peer is required for the host to
## reach a peer that isn't itself the authority of this node.

@rpc("any_peer", "call_local", "reliable")
func pick_up(package_path: NodePath) -> void:
	if not _from_host():
		return
	carried_package = get_node_or_null(package_path)


@rpc("any_peer", "call_local", "reliable")
func drop_carried() -> void:
	if not _from_host():
		return
	carried_package = null


@rpc("any_peer", "call_local", "reliable")
func tend_package(package_path: NodePath) -> void:
	if not _from_host():
		return
	tended_package = get_node_or_null(package_path)


@rpc("any_peer", "call_local", "reliable")
func board_seat(seat_camera_path: NodePath) -> void:
	if not _from_host():
		return
	_seated = true
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	visible = false
	_camera.current = false
	var seat_camera: Node = get_node_or_null(seat_camera_path)
	if seat_camera != null and seat_camera.has_method(&"activate"):
		seat_camera.call(&"activate")


func _from_host() -> bool:
	var sender_id: int = multiplayer.get_remote_sender_id()
	return sender_id == 0 or sender_id == 1  # 0: a genuine local call (offline).
