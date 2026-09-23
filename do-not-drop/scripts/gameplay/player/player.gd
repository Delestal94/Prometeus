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
## Roughly 1.25 metres high: enough to clear a fallen branch or a small
## roadside obstacle without turning the on-foot traversal into floaty parkour.
const JUMP_VELOCITY: float = 6.7
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
## Keep the first-person walk almost still. The former values read as a hard
## camera thump rather than natural gait, especially at the short walk speed.
const BOB_AMPLITUDE: float = 0.008
const BOB_FREQUENCY: float = 3.2
const BOB_SMOOTH_SPEED: float = 3.0

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

var carried_package: DeliveryPackage = null
## The package at this player's seat, once they sit down as a passenger.
## Their input reaches its trap through here.
var tended_package: DeliveryPackage = null
var _seated: bool = false
var _seat_camera_path: NodePath = NodePath()
var _pitch: float = 0.0
var _nearby: Array[Node] = []
var _last_prompt: String = ""
var _last_carrying: bool = false
var _last_lid_hint: String = ""
var _highlighted: Node = null
const RenderLayers = preload("res://scripts/presentation/render_layers.gd")
## Rigged low-poly character (2026-09-22), replaces the old placeholder
## capsule -- see assets/README.md "Personajes" for what the 5 baked clips
## (Idle/Walk/Jump/PickUpPackage/Die) actually contain. Die isn't wired to
## anything here: there's no player-death state in this game yet (packages
## get ruined, not players), so it's just available on the AnimationPlayer
## for whenever that changes instead of invented on the spot.
const CHARACTER_SCENE: PackedScene = preload("res://assets/models/characters/sm_char_player_lowpoly.glb")
const ANIM_IDLE: StringName = &"Idle"
const ANIM_WALK: StringName = &"Walk"
const ANIM_JUMP: StringName = &"Jump"
const ANIM_PICKUP: StringName = &"PickUpPackage"
## Slightly under the clips' real length (1.67s each) so the lock releases
## right as the last frame settles, instead of holding an extra beat on the
## final pose before movement can take over again.
const JUMP_ANIM_LOCK_MS: int = 1500
const PICKUP_ANIM_LOCK_MS: int = 1550
var _body_visual: Node3D = null
var _anim_player: AnimationPlayer = null
## Replicated (see player.tscn) so every peer's own copy of this player's
## AnimationPlayer plays the same clip -- movement/jump/pickup state is only
## ever computed on the owning peer (is_local()), same authority split as
## seat_node_path above.
var anim_state: StringName = ANIM_IDLE
## While in the future (Time.get_ticks_msec()), a one-shot clip (Jump,
## PickUpPackage) is playing and the per-frame movement state (Idle/Walk)
## must not stomp over it.
var _anim_lock_until_msec: int = 0
var _bob_time: float = 0.0
var _bob_amount: float = 0.0
var _interact_was_down: bool = false
var _last_safe_ground: Vector3 = Vector3.ZERO
var _package_hit_cooldown: float = 0.0
var _seat_pose_blend: float = 0.0
var _flinch_time: float = 0.0
var _ragdolled: bool = false
## Replicated (see player.tscn): which seat anchor (e.g. DriverEyePoint) this
## player is sitting at, empty when on foot. board_seat() only ever runs on
## the boarding peer's own client (it's a targeted RPC, not a broadcast), so
## this is how every *other* client learns to start posing this player's
## body at the seat too -- it's a plain property write on this node's own
## authority (the boarding peer), which the MultiplayerSynchronizer already
## propagates to everyone, the same way driver_peer_id works on the vehicle.
var seat_node_path: NodePath = NodePath()
## Selected locally before a match, then replicated so every passenger sees
## the same uniform.
var cosmetic_id: StringName = &"mint_uniform":
	set(value):
		cosmetic_id = value
		_apply_cosmetic()


func _enter_tree() -> void:
	# Spawner replicates the name. Resolve authority before children/_ready on every peer.
	if String(name).begins_with("Player_"):
		var peer: int = int(String(name).trim_prefix("Player_"))
		if peer > 0:
			set_multiplayer_authority(peer)


## A player who disconnects mid-carry must not leave their box frozen in the
## air with collisions off. package.carrier is only ever set on the host, so
## this only acts there.
func _exit_tree() -> void:
	if not is_instance_valid(carried_package) or carried_package.carrier != self:
		return
	if not carried_package.is_inside_tree() or carried_package.is_queued_for_deletion():
		return
	carried_package.drop_loose(Transform3D(global_basis, global_position + Vector3.UP * 0.5))


func _ready() -> void:
	_last_safe_ground = global_position
	if is_local():
		var profile: Node = get_node_or_null("/root/UnlockManager")
		if profile != null:
			cosmetic_id = profile.get("selected_cosmetic")
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


## The rigged low-poly character, so teammates actually have someone to see
## at all -- until this, only the viewmodel hands existed, which are
## attached to this player's own camera and so only ever visible to
## themselves. Colored per peer_id (see PLAYER_COLORS) doubles as the
## simplest possible "who is that" cue: the imported suit material gets
## duplicated per instance (a surface override, not a mutation of the
## shared glTF resource) before recoloring, so tinting one player's suit
## never bleeds into every other instance of the same imported material.
## Own camera can see its own body too (no per-camera render-layer split
## yet) -- a minor rough edge, carried over unchanged from the placeholder.
func _build_body() -> void:
	var visual: Node3D = CHARACTER_SCENE.instantiate()
	visual.name = "BodyVisual"
	add_child(visual)
	_body_visual = visual

	var mesh_instance: MeshInstance3D = _find_mesh_instance(visual)
	if mesh_instance != null:
		mesh_instance.layers = RenderLayers.LOCAL_BODY if is_local() else RenderLayers.WORLD
	_apply_cosmetic()

	_anim_player = _find_animation_player(visual)
	if _anim_player != null:
		# The glTF importer doesn't carry Blender's "this clip loops" flag,
		# so it's set here once instead of needing a manual editor step
		# every time the source .blend is re-exported.
		for loop_clip: StringName in [ANIM_IDLE, ANIM_WALK]:
			if _anim_player.has_animation(loop_clip):
				_anim_player.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR
		_anim_player.play(ANIM_IDLE)



func _apply_cosmetic() -> void:
	if _body_visual == null:
		return
	var profile: Node = get_node_or_null("/root/UnlockManager")
	var color: Color = profile.call(&"cosmetic_color", cosmetic_id) if profile != null else PLAYER_COLORS[get_multiplayer_authority() % PLAYER_COLORS.size()]
	var mesh_instance: MeshInstance3D = _find_mesh_instance(_body_visual)
	if mesh_instance != null and mesh_instance.mesh != null:
		var suit_material: Material = mesh_instance.mesh.surface_get_material(0)
		if suit_material != null:
			suit_material = suit_material.duplicate()
			(suit_material as StandardMaterial3D).albedo_color = color
			mesh_instance.set_surface_override_material(0, suit_material)
	for hand: MeshInstance3D in [_camera.get_node(^"LeftHand"), _camera.get_node(^"RightHand")]:
		var hand_material := StandardMaterial3D.new()
		hand_material.albedo_color = color.lightened(0.3)
		hand_material.roughness = 0.85
		hand.material_override = hand_material


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


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
	if _is_drop_event(event):
		_drop_carried()
		return
	if _is_open_event(event):
		_toggle_package_lid()
		return
	if _seated:
		if _is_interact_event(event):
			# Mark this press as used, or _poll_interact() would read the
			# still-held E on the next physics tick and sit right back down.
			_interact_was_down = true
			leave_seat()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative * MOUSE_SENSITIVITY)
	elif event.is_action_pressed(&"look_center"):
		_pitch = 0.0
		_head.rotation.x = 0.0
	elif _is_interact_event(event):
		# Same press must not also reach _poll_interact() on the next physics
		# tick: two interactions per E put a box on the shelf and grabbed it
		# straight back, or opened a door and shut it again.
		_interact_was_down = true
		_try_interact()


## Runs on every peer's copy of this player, seated or driving, local or
## not -- posing BodyVisual at the seat is pure presentation, so it doesn't
## need authority the way movement/input do.
func _process(delta: float) -> void:
	_flinch_time = maxf(_flinch_time - delta, 0.0)
	# Runs for every peer's copy of this player, local or not -- anim_state
	# is only ever written by the owning peer (see _update_movement_anim()
	# and pick_up() below) and reaches everyone else through the
	# MultiplayerSynchronizer, same as seat_node_path.
	if _anim_player != null and _anim_player.current_animation != String(anim_state):
		_anim_player.play(String(anim_state))
	if not get_tree().physics_interpolation:
		_pose_seated_body(delta)


## With physics interpolation on, the van is drawn between its physics ticks.
## A body snapped to the seat every rendered frame would sit at the raw tick
## pose instead and shake against the smoothly drawn cab, so it's posed on
## the ticks (from _physics_process) and interpolated right along with it.
func _pose_seated_body(delta: float) -> void:
	if seat_node_path.is_empty():
		if _body_visual != null:
			_body_visual.position.y = sin(_bob_time * TAU) * 0.025 * _bob_amount
			var flinch: float = sin(_flinch_time / 0.32 * PI) * 0.26
			_body_visual.rotation.x = move_toward(_body_visual.rotation.x, flinch, delta * 12.0)
		return
	var seat: Node3D = get_node_or_null(seat_node_path) as Node3D
	if seat == null:
		return
	# Seat anchors are eye height (where the camera goes); a seated torso
	# centers noticeably lower than that.
	_seat_pose_blend = minf(_seat_pose_blend + delta * 7.0, 1.0)
	var target_pose := seat.global_transform.translated_local(Vector3(0.0, -0.55, 0.0))
	_body_visual.global_transform = _body_visual.global_transform.interpolate_with(target_pose, _seat_pose_blend)
	_body_visual.rotation.x = 0.18 + sin(Time.get_ticks_msec() * 0.008) * 0.025


func _physics_process(delta: float) -> void:
	_package_hit_cooldown = maxf(0.0, _package_hit_cooldown - delta)
	if get_tree().physics_interpolation:
		_pose_seated_body(delta)
	if not is_local():
		return
	if carried_package != null and not is_instance_valid(carried_package):
		carried_package = null
	_publish_carry(carried_package != null)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_publish_prompt("")
		_publish_lid_hint(null)
		return
	if _seated:
		_publish_prompt("")
		_publish_lid_hint(_lid_target())
		if carried_package != null:
			_update_carried_package()
		if tended_package != null:
			tended_package.rpc_id(1, &"submit_tender_input", _gather_package_input())
		return
	_poll_interact()
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
	if is_on_floor():
		# Keep the body snapped to slopes when walking, but preserve a newly
		# requested jump impulse instead of immediately overwriting it.
		if Input.is_action_just_pressed(&"jump"):
			velocity.y = JUMP_VELOCITY
			_play_one_shot(ANIM_JUMP, JUMP_ANIM_LOCK_MS)
		else:
			velocity.y = -0.2
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_update_ground_safety()
	var ground_speed: float = Vector2(velocity.x, velocity.z).length()
	_apply_head_bob(delta, ground_speed)
	_update_movement_anim(ground_speed)
	_apply_context_fov(delta)
	if carried_package != null:
		_update_carried_package()
	var target: Node = _closest_interactable()
	_publish_prompt(str(target.call(&"get_prompt")) if target != null else "")
	_update_highlight(target)
	_publish_lid_hint(_lid_target(target))


func _update_ground_safety() -> void:
	# A last grounded position also works on hills, unlike an absolute Y cutoff.
	if global_position.y < _last_safe_ground.y - 15.0:
		global_position = _last_safe_ground + Vector3.UP * 0.5
		velocity = Vector3.ZERO
		reset_physics_interpolation()  # A rescue, not a fall: no streak between the two spots.
	elif is_on_floor():
		_last_safe_ground = global_position


func _is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"interact"):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode == KEY_E or event.physical_keycode == KEY_E
	return false


func _is_drop_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"package_drop"):
		return true
	# Same logical-keycode fallback as _is_interact_event().
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_Q or event.physical_keycode == KEY_Q)


func _is_open_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"package_open"):
		return true
	# Same logical-keycode fallback as _is_interact_event().
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_T or event.physical_keycode == KEY_T)


## The box a lid action applies to: the one in hand first, then the one at
## this player's seat, then whichever package they're looking at.
func _lid_target(aimed: Node = null) -> DeliveryPackage:
	if is_instance_valid(carried_package):
		return carried_package
	if _seated:
		return tended_package if is_instance_valid(tended_package) else null
	if aimed == null:
		aimed = _closest_interactable()
	if aimed != null and aimed.get_parent() is DeliveryPackage:
		return aimed.get_parent() as DeliveryPackage
	return null


## Opening goes through the host like everything else that changes a
## package (rpc_id(1, ...) resolves to a local call on the host itself).
func _toggle_package_lid() -> void:
	var package: DeliveryPackage = _lid_target()
	if package == null or package.contents_spilled:
		return
	package.rpc_id(1, &"request_set_open", not package.is_open)


func _publish_lid_hint(package: DeliveryPackage) -> void:
	var action: String = ""
	var inside: String = ""
	if package != null:
		if not package.contents_spilled:
			action = "Cerrar caja" if package.is_open else "Abrir caja"
		var view: Node = package.get_node_or_null(^"PackageContentsView")
		if view != null:
			inside = str(view.call(&"describe"))
	var key: String = action + "|" + inside
	if key == _last_lid_hint:
		return
	_last_lid_hint = key
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal(&"package_lid_hint_changed", action, inside)


func _poll_interact() -> void:
	# Keeps interaction responsive even if another Control consumes the input
	# event first. The explicit E fallback also supports keyboards that report
	# a logical keycode instead of the physical layout saved in project.godot.
	var is_down: bool = Input.is_action_pressed(&"interact") or Input.is_key_pressed(KEY_E)
	if is_down and not _interact_was_down:
		_try_interact()
	_interact_was_down = is_down


func _apply_look(motion: Vector2) -> void:
	# Sensitivity and Y inversion are player settings now (GameSettings), and
	# both get applied in this one place so mouse and stick stay consistent
	# with each other. 1.0 / not-inverted is exactly the tuning this shipped
	# with, so the defaults change nothing.
	var settings: Node = get_node_or_null("/root/GameSettings")
	var sensitivity: float = float(settings.get("look_sensitivity")) if settings != null else 1.0
	var y_sign: float = float(settings.call(&"look_y_sign")) if settings != null else 1.0
	motion.x *= sensitivity
	motion.y *= sensitivity * y_sign
	rotate_y(-motion.x)
	_pitch = clampf(_pitch - motion.y, -PITCH_LIMIT, PITCH_LIMIT)
	_head.rotation.x = _pitch


## Only runs on foot (the seated/driving path returns early above, and
## FirstPersonCamera -- a different node entirely -- has its own shake
## instead). A footstep sine wave that fades in/out with actual ground
## speed rather than snapping on the instant a key is pressed.
func _apply_head_bob(delta: float, ground_speed: float) -> void:
	# Do not bob while airborne: the jump already provides the vertical motion.
	var moving: bool = ground_speed > 0.3 and is_on_floor()
	var target_amount: float = 1.0 if moving else 0.0
	_bob_amount = move_toward(_bob_amount, target_amount, BOB_SMOOTH_SPEED * delta)
	if moving:
		_bob_time += delta * BOB_FREQUENCY * clampf(ground_speed / WALK_SPEED, 0.45, 1.0)
	# Always write the offset so it eases back to eye height after stopping or
	# jumping; previously it could freeze at the final high/low bob position.
	_camera.position.y = sin(_bob_time * TAU) * BOB_AMPLITUDE * _bob_amount


## Idle/Walk while on foot, unless a one-shot (Jump, PickUpPackage) locked
## anim_state a moment ago -- checked every physics frame but only actually
## writes (and re-replicates) anim_state when the target state changes.
func _update_movement_anim(ground_speed: float) -> void:
	if Time.get_ticks_msec() < _anim_lock_until_msec:
		return
	var next_state: StringName = ANIM_WALK if (ground_speed > 0.3 and is_on_floor()) else ANIM_IDLE
	if anim_state != next_state:
		anim_state = next_state


func _play_one_shot(clip: StringName, lock_ms: int) -> void:
	anim_state = clip
	_anim_lock_until_msec = Time.get_ticks_msec() + lock_ms


func _apply_context_fov(delta: float) -> void:
	# The options FOV is the neutral reference. Carrying still narrows the
	# view by the same readable amount, rather than silently ignoring a
	# player's accessibility preference.
	var settings: Node = get_node_or_null("/root/GameSettings")
	var preferred_fov: float = float(settings.get("preferred_fov")) if settings != null else 82.0
	var fov_offset: float = preferred_fov - 82.0
	var target_fov: float = (CARRY_FOV if carried_package != null else WALK_FOV) + fov_offset
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


func _publish_carry(carrying: bool) -> void:
	if carrying == _last_carrying:
		return
	_last_carrying = carrying
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal(&"carry_changed", carrying)


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
	var carry_transform := Transform3D(global_basis, _carry_position())
	carried_package.rpc_id(1, &"submit_carry_transform", carry_transform)
	_pose_viewmodel_hands(carried_package.get_half_extents())


func _pose_viewmodel_hands(half_extents: Vector3) -> void:
	# The gloves now meet the sides of the actual box rather than floating
	# near the camera. A wider package spreads the hands a little, which is
	# enough visual grounding without inventing a second animation rig.
	var spread: float = clampf(half_extents.x + 0.04, 0.22, 0.42)
	var left: MeshInstance3D = _camera.get_node(^"LeftHand") as MeshInstance3D
	var right: MeshInstance3D = _camera.get_node(^"RightHand") as MeshInstance3D
	left.position = left.position.lerp(Vector3(-spread, -0.36, -0.76), 0.25)
	right.position = right.position.lerp(Vector3(spread, -0.36, -0.76), 0.25)
	left.rotation_degrees = left.rotation_degrees.lerp(Vector3(62, 0, 30), 0.25)
	right.rotation_degrees = right.rotation_degrees.lerp(Vector3(62, 0, -30), 0.25)


func _reset_viewmodel_hands() -> void:
	for hand: MeshInstance3D in [_camera.get_node(^"LeftHand"), _camera.get_node(^"RightHand")]:
		var side: float = -1.0 if hand.name == &"LeftHand" else 1.0
		hand.position = Vector3(side * 0.16, -0.2, -0.3)
		hand.rotation_degrees = Vector3(75, 0, -side * 12)


## Collisions are off while carried, so without this the box pokes straight
## through the van's walls, doors and shelves whenever the player faces them.
## Pulls it back toward the camera until its front face sits against whatever
## is in the way, never closer than CARRY_MIN_DISTANCE -- face-planted into a
## wall there's no room for the box at all, and a sliver of clipping reads
## better than a crate filling the whole screen.
const CARRY_MIN_DISTANCE: float = 0.3
## Room between the camera and the near face of a carried box.
const CARRY_FACE_CLEARANCE: float = 0.12
const WORLD_BLOCKING_MASK: int = 1 | 2 | 4  # environment, vehicle, packages


func _carry_position() -> Vector3:
	var from: Vector3 = _camera.global_position
	var target: Vector3 = _hold_point.global_position
	var offset: Vector3 = target - from
	var reach: float = offset.length()
	if reach < 0.001:
		return target
	var direction: Vector3 = offset / reach
	# How far the box reaches from its centre toward the camera along this
	# ray: the box keeps the body's yaw, so project each half extent onto
	# the ray. The camera must stay outside that, or you see from inside
	# the box (looking up with it at head height, or up against a wall).
	var half: Vector3 = carried_package.get_half_extents()
	var support: float = (absf(direction.dot(global_basis.x)) * half.x
		+ absf(direction.dot(global_basis.y)) * half.y
		+ absf(direction.dot(global_basis.z)) * half.z)
	var min_distance: float = maxf(CARRY_MIN_DISTANCE, support + CARRY_FACE_CLEARANCE)
	var hit: Dictionary = _raycast(from, target + direction * support, WORLD_BLOCKING_MASK)
	if hit.is_empty():
		return from + direction * maxf(reach, min_distance)
	var allowed: float = from.distance_to(hit["position"]) - support - 0.02
	return from + direction * clampf(allowed, min_distance, maxf(reach, min_distance))


func _raycast(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


## MVP has a single, always-available ping ("¡Cuidado!") instead of a wheel
## of options -- docs/controles-y-ui.md sketches "¡ayuda!"/"¡cuidado!" as
## examples, not a mandate, and one message covers the actual need (warn
## teammates) without a second input to design around it.
const PING_LABEL: String = "¡Cuidado!"


func _send_ping() -> void:
	var network: Node = get_node_or_null("/root/NetworkManager")
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus == null:
		return
	if network != null and network.call(&"is_online") and not network.call(&"is_host"):
		bus.rpc_id(1, &"request_ping", global_position, PING_LABEL)
	else:
		bus.call(&"request_ping", global_position, PING_LABEL)


func _try_interact() -> void:
	if carried_package != null:
		var teammate := _transfer_target()
		if teammate != null:
			carried_package.rpc_id(1, &"request_transfer", teammate.get_path())
			return
	var target: Node = _closest_interactable()
	if target == null:
		return
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network != null and network.call(&"is_online") and not network.call(&"is_host"):
		target.rpc_id(1, &"request_interact")
	else:
		target.call(&"interact", self)


func _transfer_target() -> Player:
	var eye: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_basis.z
	var best: Player = null
	var best_score: float = 0.7
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var teammate := node as Player
		if teammate == null or teammate == self or teammate.carried_package != null:
			continue
		var to_teammate: Vector3 = teammate.global_position - eye
		var distance: float = to_teammate.length()
		if distance > 2.4 or distance < 0.05:
			continue
		var score: float = forward.dot(to_teammate / distance)
		if score > best_score:
			best_score = score
			best = teammate
	return best


## The box is set down just clear of the player's own capsule, then settled
## onto whatever is actually under that spot: terrain, the van's cargo floor
## or a shelf, or another box (so boxes can be stacked by hand).
const BODY_RADIUS: float = 0.35
const DROP_GAP: float = 0.1
const DROP_CHEST_HEIGHT: float = 1.0
## How far below the chest the ground probe may look. Past this (dropping
## over an edge) the box is released at chest height and simply falls.
const DROP_GROUND_PROBE: float = 2.5
const DROP_SETTLE_MARGIN: float = 0.02


func _drop_carried() -> void:
	if carried_package == null:
		return
	var drop_transform := Transform3D(global_basis, _drop_position(carried_package.get_half_extents()))
	carried_package.rpc_id(1, &"request_drop", drop_transform)
	# The host confirms by clearing this on every peer; clearing it here too
	# just keeps the local hands responsive while that RPC is in flight.
	carried_package = null


func _drop_position(half_extents: Vector3) -> Vector3:
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var chest: Vector3 = global_position + Vector3.UP * DROP_CHEST_HEIGHT
	var distance: float = BODY_RADIUS + DROP_GAP + half_extents.z
	# A wall, the van's side or a door in front: set it down short of that
	# instead of spawning the box half inside it.
	var wall: Dictionary = _raycast(chest, chest + forward * (distance + half_extents.z), WORLD_BLOCKING_MASK)
	if not wall.is_empty():
		distance = maxf(chest.distance_to(wall["position"]) - half_extents.z - DROP_SETTLE_MARGIN, 0.0)
	var spot: Vector3 = chest + forward * distance
	var ground: Dictionary = _raycast(spot, spot - Vector3.UP * DROP_GROUND_PROBE, WORLD_BLOCKING_MASK)
	if ground.is_empty():
		return spot
	return Vector3(spot.x, (ground["position"] as Vector3).y + half_extents.y + DROP_SETTLE_MARGIN, spot.z)


## What gets the interact prompt: whatever the player is looking at most
## directly, not just whatever is nearest their feet -- the van's six cargo
## slots sit close enough together that nearest-first made it impossible to
## choose which one a box went into.
const AIM_DISTANCE_WEIGHT: float = 0.3
## How far forward of a seat a passenger stands up (see _seat_exit_position).
const SEAT_EXIT_STEP: float = 0.55
## Only what's physically within reach can be used: something solid between
## the eyes and the target blocks it (a seat or shelf through the truck's
## wall). A hit this close to the target doesn't count -- door handles and
## seats reached through an open door sit right on a surface.
const REACH_SURFACE_TOLERANCE: float = 0.3


func _closest_interactable() -> Node:
	var best: Node = null
	var best_score: float = -INF
	var eye: Vector3 = _camera.global_position
	var look: Vector3 = -_camera.global_basis.z
	for area: Node in _nearby:
		if not is_instance_valid(area):
			continue
		if not bool(area.call(&"can_interact", self)):
			continue
		if not _within_reach(area as Node3D):
			continue
		var to_target: Vector3 = (area as Node3D).global_position - eye
		var distance: float = to_target.length()
		var alignment: float = look.dot(to_target / distance) if distance > 0.001 else 1.0
		var score: float = alignment - distance * AIM_DISTANCE_WEIGHT
		if score > best_score:
			best_score = score
			best = area
	return best


func _within_reach(target: Node3D) -> bool:
	var eye: Vector3 = _camera.global_position
	var hit: Dictionary = _raycast(eye, target.global_position, 1 | 2)
	if hit.is_empty():
		return true
	return (hit["position"] as Vector3).distance_to(target.global_position) <= REACH_SURFACE_TOLERANCE


func _on_probe_entered(area: Area3D) -> void:
	if area.has_method(&"interact"):
		_nearby.append(area)


func _on_probe_exited(area: Area3D) -> void:
	_nearby.erase(area)


## A loose package can bowl somebody over. This intentionally stays a
## controllable knockback with the current rig; a real ragdoll needs a
## dedicated physical skeleton asset rather than faking one by deleting the
## controller under a networked player.
@rpc("any_peer", "call_local", "unreliable")
func receive_package_hit(push: Vector3) -> void:
	if _package_hit_cooldown > 0.0 or _seated:
		return
	_package_hit_cooldown = 0.45
	_flinch_time = 0.32
	velocity += push + Vector3.UP * 1.4
	if is_local():
		_play_one_shot(ANIM_JUMP, 420)
	if push.length() >= 2.2:
		_activate_ragdoll(push)


func _activate_ragdoll(push: Vector3) -> void:
	if _ragdolled:
		return
	_ragdolled = true
	var ragdoll := preload("res://scripts/gameplay/player/player_ragdoll.gd").new()
	get_parent().add_child(ragdoll)
	ragdoll.setup(self)
	ragdoll.fall(push)
	await get_tree().create_timer(2.8).timeout
	_ragdolled = false


## The host announces the outcome of an interaction by calling these on the
## peers they concern. pick_up/drop_carried are broadcast: the host's own copy
## of a remote player has to know what that player holds, or every mount and
## pickup check it runs for them reads empty hands. The rest are targeted.
## _from_host() guards every one, since any_peer is required for the host to
## reach a peer that isn't itself the authority of this node.

@rpc("any_peer", "call_local", "reliable")
func pick_up(package_path: NodePath) -> void:
	if not _from_host():
		return
	var was_empty: bool = carried_package == null
	carried_package = get_node_or_null(package_path) as DeliveryPackage
	# Only the owning peer drives anim_state (see _update_movement_anim) --
	# this RPC reaches every peer that can see the pickup, but the write
	# below only matters, and only actually replicates, from is_local()'s copy.
	if is_local() and was_empty and carried_package != null:
		_play_one_shot(ANIM_PICKUP, PICKUP_ANIM_LOCK_MS)


@rpc("any_peer", "call_local", "reliable")
func drop_carried() -> void:
	if not _from_host():
		return
	carried_package = null
	if is_local():
		_reset_viewmodel_hands()


@rpc("any_peer", "call_local", "reliable")
func tend_package(package_path: NodePath) -> void:
	if not _from_host():
		return
	tended_package = get_node_or_null(package_path) as DeliveryPackage


@rpc("any_peer", "call_local", "reliable")
func board_seat(seat_camera_path: NodePath, seat_path: NodePath) -> void:
	if not _from_host():
		return
	_seated = true
	_seat_pose_blend = 0.0
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
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal(&"quick_fade_requested", 0.2)
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
	_release_seat_occupant(seat)
	if seat != null:
		global_position = _seat_exit_position(seat)
		reset_physics_interpolation()
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


## Where to stand when getting up: the seat's own "ExitPoint" if it has one
## (the driver climbs out through the cab door), otherwise a step forward
## from the seat, into the aisle it faces. Either way, dropped onto whatever
## floor is under that spot -- never left at eye height or inside a wall.
func _seat_exit_position(seat: Node3D) -> Vector3:
	var exit_point := seat.get_node_or_null(^"ExitPoint") as Node3D
	var spot: Vector3 = exit_point.global_position if exit_point != null else seat.global_position - seat.global_basis.z * SEAT_EXIT_STEP
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.2, spot + Vector3.DOWN * 3.0, 1 | 2, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3) + Vector3.UP * 0.02 if not hit.is_empty() else spot


func _release_seat_occupant(seat: Node3D) -> void:
	if seat == null:
		return
	var interaction: Node = seat.get_node_or_null(^"InteractionArea")
	if interaction == null or not interaction.has_method(&"release_occupant"):
		return
	var peer_id: int = get_multiplayer_authority()
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network != null and network.call(&"is_online") and not network.call(&"is_host"):
		interaction.rpc_id(1, &"release_occupant", peer_id)
	else:
		interaction.call(&"release_occupant", peer_id)


func _from_host() -> bool:
	var sender_id: int = multiplayer.get_remote_sender_id()
	return sender_id == 0 or sender_id == 1  # 0: a genuine local call (offline).
