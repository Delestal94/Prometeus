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

## Three contexts, three frames -- walking, driving (FirstPersonCamera's own
## BASE_FOV) and carrying a package don't feel like the same view even
## though they used to share one flat 78°.
const WALK_FOV: float = 78.0
const CARRY_FOV: float = 70.0
const FOV_SMOOTH_SPEED: float = 6.0
## Footstep bob: a small vertical sine wave on the camera itself, so a held
## package (which follows the camera's hold point) bobs with it too --
## before this, walking anywhere felt perfectly flat, "on rails."
const BOB_AMPLITUDE: float = 0.045
const BOB_FREQUENCY: float = 9.0
const BOB_SMOOTH_SPEED: float = 8.0

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
var _seat_camera_path: NodePath = NodePath()
var _pitch: float = 0.0
var _nearby: Array[Node] = []
var _last_prompt: String = ""
var _highlighted: Node = null
const RenderLayers = preload("res://scripts/presentation/render_layers.gd")
var _body_visual: MeshInstance3D = null
var _bob_time: float = 0.0
var _bob_amount: float = 0.0
## Replicated (see player.tscn): which seat anchor (e.g. DriverEyePoint) this
## player is sitting at, empty when on foot. board_seat() only ever runs on
## the boarding peer's own client (it's a targeted RPC, not a broadcast), so
## this is how every *other* client learns to start posing this player's
## body at the seat too -- it's a plain property write on this node's own
## authority (the boarding peer), which the MultiplayerSynchronizer already
## propagates to everyone, the same way driver_peer_id works on the vehicle.
var seat_node_path: NodePath = NodePath()


func _enter_tree() -> void:
	# Spawner replicates the name. Resolve authority before children/_ready on every peer.
	if String(name).begins_with("Player_"):
		var peer: int = int(String(name).trim_prefix("Player_"))
		if peer > 0:
			set_multiplayer_authority(peer)


func _ready() -> void:
	_build_body()
	RenderLayers.configure_first_person(_camera)
	RenderLayers.show_viewmodel(_camera, is_local())
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
	mesh.name = "BodyVisual"
	mesh.layers = RenderLayers.LOCAL_BODY if is_local() else RenderLayers.WORLD
	mesh.material_override = material
	mesh.position = Vector3(0.0, 0.8, 0.0)
	add_child(mesh)
	_body_visual = mesh
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
		if event.is_action_pressed(&"interact"):
			leave_seat()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative * MOUSE_SENSITIVITY)
	elif event.is_action_pressed(&"look_center"):
		_pitch = 0.0
		_head.rotation.x = 0.0
	elif event.is_action_pressed(&"interact"):
		_try_interact()


## Runs on every peer's copy of this player, seated or driving, local or
## not -- posing BodyVisual at the seat is pure presentation, so it doesn't
## need authority the way movement/input do.
func _process(_delta: float) -> void:
	if seat_node_path.is_empty():
		return
	var seat: Node3D = get_node_or_null(seat_node_path) as Node3D
	if seat == null:
		return
	# Seat anchors are eye height (where the camera goes); a seated torso
	# centers noticeably lower than that.
	_body_visual.global_transform = seat.global_transform.translated_local(Vector3(0.0, -0.55, 0.0))


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
	_apply_head_bob(delta, Vector2(velocity.x, velocity.z).length())
	_apply_context_fov(delta)
	if carried_package != null:
		_update_carried_package()
	var target: Node = _closest_interactable()
	_publish_prompt(str(target.call(&"get_prompt")) if target != null else "")
	_update_highlight(target)


func _apply_look(motion: Vector2) -> void:
	rotate_y(-motion.x)
	_pitch = clampf(_pitch - motion.y, -PITCH_LIMIT, PITCH_LIMIT)
	_head.rotation.x = _pitch


## Only runs on foot (the seated/driving path returns early above, and
## FirstPersonCamera -- a different node entirely -- has its own shake
## instead). A footstep sine wave that fades in/out with actual ground
## speed rather than snapping on the instant a key is pressed.
func _apply_head_bob(delta: float, ground_speed: float) -> void:
	# No is_on_floor() gate: there's no jump in this game, gravity always
	# eventually grounds the player, and requiring floor contact here would
	# only mean a player who spawns a frame before the ground settles under
	# them gets a flat glide instead of a bob for no real reason.
	var moving: bool = ground_speed > 0.3
	var target_amount: float = 1.0 if moving else 0.0
	_bob_amount = move_toward(_bob_amount, target_amount, BOB_SMOOTH_SPEED * delta)
	if moving:
		_bob_time += delta * BOB_FREQUENCY * clampf(ground_speed / WALK_SPEED, 0.4, 1.0)
	_camera.position.y = sin(_bob_time * TAU) * BOB_AMPLITUDE * _bob_amount


func _apply_context_fov(delta: float) -> void:
	var target_fov: float = CARRY_FOV if carried_package != null else WALK_FOV
	_camera.fov = move_toward(_camera.fov, target_fov, FOV_SMOOTH_SPEED * delta)


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


## A visible glow on whatever the player is currently looking at (item #98),
## instead of only the HUD's text prompt. Duck-typed via has_method(): not
## every Interactable bothers implementing highlight() (a package mount is
## an empty slot, nothing to glow), so this is opt-in per type.
func _update_highlight(target: Node) -> void:
	if target == _highlighted:
		return
	if is_instance_valid(_highlighted) and _highlighted.has_method(&"highlight"):
		_highlighted.call(&"highlight", false)
	_highlighted = target
	if is_instance_valid(_highlighted) and _highlighted.has_method(&"highlight"):
		_highlighted.call(&"highlight", true)


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
func board_seat(seat_camera_path: NodePath, seat_path: NodePath) -> void:
	if not _from_host():
		return
	_seated = true
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	# Visible stays true now -- BodyVisual tracks the seat (see _process())
	# instead of disappearing, so teammates actually have someone to look at
	# during the ride. Only this player's own camera stops rendering it
	# (RenderLayers.LOCAL_BODY, set once in _build_body()).
	_camera.current = false
	seat_node_path = seat_path
	_seat_camera_path = seat_camera_path
	# board_seat() only ever runs on the boarding peer's own client (it's a
	# targeted RPC, not a broadcast -- see seat_point.gd), so this is
	# guaranteed to be the local player's own view swapping cameras. A quick
	# fade softens what would otherwise be an instant teleport-cut from
	# standing on foot to sitting in the seat.
	EventBus.emit_signal(&"quick_fade_requested", 0.2)
	var seat_camera: Node = get_node_or_null(seat_camera_path)
	if seat_camera != null and seat_camera.has_method(&"activate"):
		seat_camera.call(&"activate")


## Seats are a temporary safe spot, not a lock-in. Leaving restores the
## on-foot controller at the seat's location, so passengers can react to
## loose cargo while the van is moving.
func leave_seat() -> void:
	if not _seated:
		return
	var seat: Node3D = get_node_or_null(seat_node_path) as Node3D
	if seat != null:
		global_position = seat.global_position + seat.global_basis.z * 0.45
	var seat_camera: Node = get_node_or_null(_seat_camera_path)
	if seat_camera != null and seat_camera.has_method(&"deactivate"):
		seat_camera.call(&"deactivate")
	_seated = false
	tended_package = null
	seat_node_path = NodePath()
	_seat_camera_path = NodePath()
	collision_layer = 8
	collision_mask = 7
	_camera.current = true


func _from_host() -> bool:
	var sender_id: int = multiplayer.get_remote_sender_id()
	return sender_id == 0 or sender_id == 1  # 0: a genuine local call (offline).
