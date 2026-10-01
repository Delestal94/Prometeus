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
@export var stick_sensitivity: float = 2.4

## Look, view and footstep constants live in player_movement.gd / player_input.gd; same names here.
const MOUSE_SENSITIVITY: float = OnFootInput.MOUSE_SENSITIVITY
const PITCH_LIMIT: float = Movement.PITCH_LIMIT
const WALK_FOV: float = Movement.WALK_FOV
const CARRY_FOV: float = Movement.CARRY_FOV
const FOV_SMOOTH_SPEED: float = Movement.FOV_SMOOTH_SPEED
const BOB_AMPLITUDE: float = Movement.BOB_AMPLITUDE
const BOB_FREQUENCY: float = Movement.BOB_FREQUENCY
const BOB_SMOOTH_SPEED: float = Movement.BOB_SMOOTH_SPEED

## One color per seat of a full room (NetworkManager.MAX_PLAYERS, N-228.3), picked by the
## colour slot the host gave the player (PlayerColorSlot, N-226): stable for the session.
## Slots 0..4 keep their order (saves index by it); 5..7 (off-white, cobalt, teal) differ
## in lightness too, so they survive deuteranopia/protanopia. Names: CrewProgression,
## voices: SynthAudioScenes.CALLOUT_VOICE_PITCHES; grow all three together.
const PLAYER_COLORS: Array[Color] = [
	Color("83e2ba"), Color("f4c562"), Color("f47e6d"), Color("6db3d6"), Color("c9a0e0"),
	Color("e8eaf0"), Color("5f7fd0"), Color("4f9a8f"),
]

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _hold_point: Marker3D = $Head/Camera3D/HoldPoint
@onready var _probe: Area3D = $Head/InteractionProbe
@onready var _interaction_component: Node = $PlayerInteraction
@onready var _carry_component: Node = $PlayerCarry
@onready var _seat_pose_component: Node = $PlayerSeatPose

var carried_package: DeliveryPackage = null
## The package at this player's seat, once they sit down as a passenger.
## Their input reaches its trap through here.
var tended_package: DeliveryPackage = null
## A second box this player is helping after their own is lost. Unlike
## tended_package, this can belong to an adjacent seat or be helped on foot.
var assisted_package: DeliveryPackage = null
var _seated: bool = false
var _seat_camera_path: NodePath = NodePath()
var _pitch: float = 0.0
var _nearby: Array[Node] = []
var _last_prompt: String = ""
var _last_carrying: bool = false
var _last_lid_hint: String = ""
var _highlighted: Node = null
## Loaded by path because isolated `--script` tests run before Godot refreshes
## the editor-managed global class cache after this helper was split out.
const PING_INPUT_PATH: String = "res://scripts/gameplay/player/player_ping_input.gd"
var _ping_input: Variant = (load(PING_INPUT_PATH) as Script).new(self)
## Rescue panel and assisting another box (player_cargo_care.gd).
var _cargo_care: Node
var _sprint: Node  # Speeds, footfalls, the box's shaking and the trip (player_sprint.gd).
const RenderLayers = preload("res://scripts/core/render_layers.gd")
## Split out of this file (N-225.5): static helpers that take the player and keep no state of their own.
const Ride = preload("res://scripts/gameplay/player/player_ride.gd")
const Movement = preload("res://scripts/gameplay/player/player_movement.gd")
const OnFootInput = preload("res://scripts/gameplay/player/player_input.gd")
const NetVisibility = preload("res://scripts/gameplay/player/player_net_visibility.gd")
const CarryPose = preload("res://scripts/gameplay/player/carry_pose.gd")
const FaceCatalog = preload("res://scripts/core/face_catalog.gd")
const CharacterFace = preload("res://scripts/presentation/character_face.gd")
const TutorialData = preload("res://scripts/ui/tutorial_catalog.gd")
## Astra's rounded character (2026-09-24), game export built by
## art/rounded_character/build_game_export.py -- see assets/README.md
## "Personajes" for its clips (Idle/Walk/Stroll/TurnInPlace/Jump/PickUpPackage/
## PickUpHigh/Sit). One skinned
## mesh; surface 0 is the T-shirt, which carries the crew colour.
const CHARACTER_SCENE: PackedScene = preload("res://assets/models/characters/sm_char_player_rounded.glb")
const ANIM_IDLE: StringName = &"Idle"
const ANIM_WALK: StringName = &"Walk"
## Held-sprint gait (player_sprint.gd); without the clip PlayerAnimator plays a faster Walk.
const ANIM_RUN: StringName = &"Run"
const ANIM_JUMP: StringName = &"Jump"
const ANIM_PICKUP: StringName = &"PickUpPackage"
## PickUpPackage squats to the floor; PickUpHigh takes a box at the waist
## without squatting. Same length and grab/lift times, so a pickup plays a
## blend of both weighted by where the hands meet the box (pickup_high_weight)
## -- built once per weight step into PlayerAnimator.PICKUP_BLEND_LIBRARY. Heights are the
## wrists at the grab in each clip, above the feet (animation_library.py
## PICKUP_GRAB_Z x 0.5 m/BU).
const ANIM_PICKUP_HIGH: StringName = &"PickUpHigh"
const PICKUP_LOW_GRIP: float = 0.51
const PICKUP_HIGH_GRIP: float = 0.925
## Played by every peer while seat_node_path is set -- it's derived from that
## replicated path, not from anim_state, so it needs no sync of its own.
const ANIM_SIT: StringName = &"Sit"
## Presentation-only gait under Walk: a real walk for partial stick input.
## anim_state still says Walk; each peer picks the gait from the replicated
## locomotion_speed (PlayerAnimator), so it needs no sync of its own.
const ANIM_STROLL: StringName = &"Stroll"
## Small steps in place while the player turns standing still (the whole
## body rotates with the look yaw; without this the feet swivelled on the
## spot). The owner picks it (PlayerAnimator.update_movement()) from its own look
## turn rate, so it reaches the other peers through anim_state. Rates in
## rad/s, smoothed; hysteresis so a mouse flick doesn't flicker it. Turning
## with the truck the player rides in doesn't count: the floor turns too.
const ANIM_TURN: StringName = &"TurnInPlace"
## Driver IK chain on the rounded character's skeleton (glTF bone names).
const DRIVER_ARM_BONES: Dictionary = {
	-1.0: [&"upper_arm.L", &"hand.L"],
	1.0: [&"upper_arm.R", &"hand.R"],
}
## Slightly under the clips' real length (1.6 s each) so the lock releases
## right as the last frame settles, instead of holding an extra beat on the
## final pose before movement can take over again.
const JUMP_ANIM_LOCK_MS: int = 1500
const PICKUP_ANIM_LOCK_MS: int = 1550
var _body_visual: Node3D = null
## Replicated (see player.tscn) so every peer's own copy of this player's
## AnimationPlayer plays the same clip -- movement/jump/pickup state is only
## ever computed on the owning peer (is_local()), same authority split as
## seat_node_path above.
var anim_state: StringName = ANIM_IDLE
## Picks anim_state (owner) and plays it (every peer); see PlayerAnimator.
var animator: PlayerAnimator
## Presentation state authored by the owning peer, replicated with anim_state.
## Scales the gait clips (see PlayerAnimator.WALK_AUTHORED_SPEED); jump samples the real
## ascent/landing instead of playing a crouch after leaving the floor.
var locomotion_speed: float = 0.0
var turn_rate: float = 0.0
var jump_anim_time: float = 0.0
var _carry_pose: Node3D
var _pickup_elapsed: float = 2.0
var _pickup_from: Transform3D = Transform3D.IDENTITY
var _pickup_in_vehicle: bool = false
## 0 = box on the floor (full squat) .. 1 = box at the waist. Set by pick_up()
## on every peer from the same package position, so it needs no sync.
var pickup_high_weight: float = 0.0
var _character_face: BoneAttachment3D
var face_eyes: StringName = FaceCatalog.DEFAULT_EYES:
	set(value):
		face_eyes = FaceCatalog.valid_eyes(value)
		_apply_face()
var face_mouth: StringName = FaceCatalog.DEFAULT_MOUTH:
	set(value):
		face_mouth = FaceCatalog.valid_mouth(value)
		_apply_face()
var _bob_time: float = 0.0
var _bob_amount: float = 0.0
var _interact_was_down: bool = false
var _last_safe_ground: Vector3 = Vector3.ZERO
var _package_hit_cooldown: float = 0.0
var _seat_pose_blend: float = 0.0
var _flinch_time: float = 0.0
var _ragdolled: bool = false
var _package_focus: CameraAttributesPractical
var _driver_ik_ready: bool = false
var _driver_ik_nodes: Array[SkeletonIK3D] = []
var _driver_arm_targets: Array[Node3D] = []
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
var cosmetic_id: StringName = &"team_color":
	set(value):
		cosmetic_id = value
		_apply_cosmetic()
## Replicated in place of position (see player.tscn), written by the owning
## peer. Standing in the truck's cargo bay it's in the truck's own space, so
## everyone else puts this player back inside *their* copy of the truck
## instead of where a world position from a moment ago left them (a metre
## behind at speed: through the rear doors, or out of the truck).
var net_position: Vector3 = Vector3.ZERO:
	set(value):
		net_position = value
		_has_net_state = true
var net_in_vehicle: bool = false
var _has_net_state: bool = false
var _vehicle: Node3D = null
## Owner only: the truck's pose last physics tick, while standing in its bay.
var _riding: bool = false
var _ride_last_transform: Transform3D = Transform3D.IDENTITY
## Physics layers of the truck and of its cargo shell (vehicle.gd SHELL_LAYER),
## the kinematic copy of it that players actually collide with. The truck
## carries its riders by hand (Ride.ride_with_vehicle), so the controller's own
## platform handling must ignore both or they'd move twice.
const VEHICLE_LAYER: int = 2
const SHELL_LAYER: int = 64
## How far past the cargo bay's edge someone already aboard still counts as
## aboard (see Vehicle.carries()).
const RIDE_MARGIN: float = 0.4


func _enter_tree() -> void:
	# Spawner replicates the name. Resolve authority before children/_ready on every peer.
	if String(name).begins_with("Player_"):
		var peer: int = int(String(name).trim_prefix("Player_"))
		if peer > 0:
			set_multiplayer_authority(peer)
	# Before the synchronizer (a child) enters the tree: it registers with the
	# network right then, and without the filter it counted as public.
	NetVisibility.limit_to_ready_peers(self)


## A player who disconnects mid-carry must not leave their box frozen in the
## air with collisions off. package.carrier is only ever set on the host, so
## this only acts there.
func _exit_tree() -> void:
	_ping_input.close_wheel()
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network != null and network.call(&"is_host"):
		_seat_pose_component.release_seat_occupant(get_node_or_null(seat_node_path) as Node3D)
	if not is_instance_valid(carried_package) or carried_package.carrier != self:
		return
	if not carried_package.is_inside_tree() or carried_package.is_queued_for_deletion():
		return
	carried_package.drop_loose(Transform3D(global_basis, global_position + Vector3.UP * 0.5))


func _ready() -> void:
	_cargo_care = preload("res://scripts/gameplay/player/player_cargo_care.gd").new()
	_cargo_care.name = "CargoCare"
	add_child(_cargo_care)
	_sprint = preload("res://scripts/gameplay/player/player_sprint.gd").new()
	add_child(_sprint)
	add_child(preload("res://scripts/gameplay/player/player_voice.gd").new())
	_last_safe_ground = global_position
	if is_local():
		var profile: Node = get_node_or_null("/root/UnlockManager")
		if profile != null:
			cosmetic_id = profile.get("selected_cosmetic")
			face_eyes = profile.get("selected_eyes")
			face_mouth = profile.get("selected_mouth")
			profile.progress_changed.connect(_sync_profile_appearance)
	_build_body()
	PlayerColorSlot.follow(_apply_cosmetic)
	# Depth of field needs Forward+ or Mobile: GL Compatibility (this game's
	# renderer) never drew it and warned on every carry.
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_package_focus = CameraAttributesPractical.new()
		_package_focus.dof_blur_far_enabled = false
		_package_focus.dof_blur_near_enabled = false
		_camera.attributes = _package_focus
	RenderLayers.configure_first_person(_camera)
	# The spawn state is the host's copy of these, sent before the owner's
	# first update: start them at the spawn point, not at the world origin.
	# (A late joiner already got the host's latest pair, applied before this.)
	if not _has_net_state:
		net_position = global_position
	platform_floor_layers &= ~(VEHICLE_LAYER | SHELL_LAYER)
	# Only the player this peer controls owns the view and reads input;
	# everyone else's body is here to be seen, not driven.
	if not is_local():
		_camera.current = false
		# Placed by the network every frame (_process), against the truck as
		# it's drawn: interpolating between physics ticks on top of that
		# only made riders trail behind it.
		physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
		return
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ping_input.build_wheel()
	_probe.area_entered.connect(_interaction_component.on_probe_entered)
	_probe.area_exited.connect(_interaction_component.on_probe_exited)


## The callable the NetworkManager signal is connected to (player_net_visibility.gd; re-sends pick_up, N-908).
func _on_peer_level_ready(peer_id: int) -> void:
	NetVisibility.refresh_peer(self, peer_id)


## The rigged character, so teammates have someone to see. Colored per
## colour slot (see PLAYER_COLORS) doubles as the simplest possible "who is
## that" cue: the imported suit material gets duplicated per instance (a
## surface override, not a mutation of the shared glTF resource) before
## recoloring, so tinting one player's suit never bleeds into every other
## instance of the same imported material. This player's own cameras leave
## it out (RenderLayers.LOCAL_BODY), and nothing stands in for it there: no
## first-person hands float in front of the lens.
func _build_body() -> void:
	var visual: Node3D = CHARACTER_SCENE.instantiate()
	visual.name = "BodyVisual"
	add_child(visual)
	_body_visual = visual
	PlayerAppearance.enable_shadows(visual)

	PlayerAppearance.set_layers(visual, RenderLayers.LOCAL_BODY if is_local() else RenderLayers.WORLD)
	_apply_cosmetic()
	_character_face = CharacterFace.new()
	_character_face.setup(visual, PlayerAppearance.find_skeleton(visual), RenderLayers.LOCAL_BODY if is_local() else RenderLayers.WORLD)
	_apply_face()

	animator = PlayerAnimator.new(self, PlayerAppearance.find_animation_player(visual), _character_face)
	_carry_pose = CarryPose.new()
	_carry_pose.name = "CarryPose"
	add_child(_carry_pose)
	_carry_pose.setup(self, PlayerAppearance.find_skeleton(visual))


func _apply_face() -> void:
	if _character_face != null:
		_character_face.set_expression(face_eyes, face_mouth)


func _sync_profile_appearance() -> void:
	var profile: Node = get_node_or_null("/root/UnlockManager")
	if profile != null and is_local():
		cosmetic_id = profile.selected_cosmetic
		face_eyes = profile.selected_eyes
		face_mouth = profile.selected_mouth


func _apply_cosmetic() -> void:
	if _body_visual == null:
		return
	var profile: Node = get_node_or_null("/root/UnlockManager")
	# "team_color" keeps the crew-slot colour (teammates stay apart); a picked uniform replaces it.
	var color: Color = PLAYER_COLORS[PlayerColorSlot.slot(get_multiplayer_authority(), PLAYER_COLORS.size())]
	if profile != null and not bool(profile.call(&"cosmetic_is_auto", cosmetic_id)):
		color = profile.call(&"cosmetic_color", cosmetic_id)
	PlayerAppearance.tint_shirt(_body_visual, color)


## How much of PickUpHigh a pickup plays, from the height above the feet at
## which the hands meet the box (0 at the floor clip's grip, 1 at the high one's).
static func pickup_high_weight_for(grip_height: float) -> float:
	return clampf((grip_height - PICKUP_LOW_GRIP) / (PICKUP_HIGH_GRIP - PICKUP_LOW_GRIP), 0.0, 1.0)


## Same contact point carry_pose.gd puts the hands on: the box's upper sides.
func pickup_high_weight_for_package(package: Node3D) -> float:
	var half: Vector3 = package.call(&"get_half_extents") if package.has_method(&"get_half_extents") else Vector3.ONE * 0.325
	var grip: float = package.global_position.y + minf(half.y * 0.65, 0.16)
	return pickup_high_weight_for(grip - global_position.y)


func is_local() -> bool:
	return is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	OnFootInput.handle_event(self, event)


## Runs on every peer's copy of this player, seated or driving, local or
## not -- posing BodyVisual at the seat is pure presentation, so it doesn't
## need authority the way movement/input do.
func _process(delta: float) -> void:
	_flinch_time = maxf(_flinch_time - delta, 0.0)
	_ping_input.update(delta)
	animator.animate()
	if not is_local():
		Ride.apply_net_state(self)
	elif not _seated:
		Ride.ride_frame_by_frame(self)
	if not is_physics_interpolated_and_enabled():
		_seat_pose_component.pose_seated_body(delta)
	if _carry_pose != null:
		_carry_pose.update_pose(carried_package, _pickup_elapsed, delta)


## Where this player is for anything within reach -- opening a box, a
## photo, a ping: at their seat while seated. The body itself stays where
## they sat down (only its visual rides along), so the host measured a
## passenger kilometres from the box on their lap.
func reach_origin() -> Vector3:
	return _seat_pose_component.reach_origin()


func reach_slack() -> float:
	return Ride.reach_slack(self)


## What an on-foot player collides with. Riding in the bay of a truck that's
## moving, not the loose boxes: a player is carried along by being moved
## between physics steps, so during each step they stood still in the world
## while the truck and its boxes moved on -- and every box they touched was
## struck at the truck's speed, losing integrity or flying off the rack.
## Parked (loading at the depot, a stop at a door) they collide as usual.
## The truck itself is never in these: a player is solid against its shell,
## so they can't shove it (vehicle.gd SHELL_LAYER).
const ON_FOOT_MASK: int = 1 | SHELL_LAYER | 4
const RIDING_MASK: int = 1 | SHELL_LAYER
const RIDING_SPEED: float = 1.0


func _on_foot_mask(riding: bool) -> int:
	return Ride.on_foot_mask(self, riding)


func _find_vehicle() -> Node3D:
	return Ride.find_vehicle(self)


## Where a node is drawn this frame (see Ride.drawn_transform).
static func _drawn_transform(node: Node3D) -> Transform3D:
	return Ride.drawn_transform(node)


## Where the rounded character's root goes, in the seat marker's space, so
## its Sit pose rests on that seat's cushion. Measured in the truck by
## tests/render_player_character.gd (2026-09-24): the wall cushions are
## ~0.58 m under their eye markers, the rack jump seats ~0.55 m and only
## 0.36 m deep, and the driver's cushion sits behind the wheel -- 0.37 m
## forward keeps both wrists on the rim at full reach. The cab is too low for
## this character fully on the cushion, so the driver sinks into it rather
## than putting his head through the roof. Re-measured for the chubbier body
## with hair (2026-09-27): the driver sinks 2 cm more (the cowlick is kept
## low for him), the passengers sit 7 cm lower and 10 cm further forward.
func _seat_body_offset(seat_name: StringName) -> Vector3:
	return _seat_pose_component.seat_body_offset(seat_name)


func _physics_process(delta: float) -> void:
	_package_hit_cooldown = maxf(0.0, _package_hit_cooldown - delta)
	_pickup_elapsed += delta
	# Remote players must also stop colliding while seated. Their input RPC
	# is targeted, but their seat path is replicated to everyone.
	if not is_local():
		collision_layer = 8 if seat_node_path.is_empty() else 0
		collision_mask = _on_foot_mask(net_in_vehicle) if seat_node_path.is_empty() else 0
		Ride.apply_net_state(self, true)
	if is_physics_interpolated_and_enabled():
		_seat_pose_component.pose_seated_body(delta)
	if not is_local():
		return
	# Before any early return: a menu open in the back of a moving truck
	# must not leave the player behind.
	if _seated:
		_riding = false
	else:
		Ride.ride_with_vehicle(self)
		collision_mask = _on_foot_mask(_riding)
	Ride.publish_net_state(self)
	if carried_package != null and not is_instance_valid(carried_package):
		carried_package = null
	_publish_carry(carried_package != null)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_interaction_component.publish_prompt("")
		_interaction_component.publish_lid_hint(null)
		return
	if _seated:
		var candidate: DeliveryPackage = (_cargo_care.assist_candidate() if tended_package != null
				and tended_package.run_state() == ITrapBehavior.TrapState.RUINED else null)
		_interaction_component.publish_prompt(
				candidate.assist_prompt() if candidate != null and assisted_package == null else "")
		_interaction_component.publish_lid_hint(_lid_target())
		if carried_package != null:
			_carry_component.update_carried_package()
		if assisted_package != null:
			_cargo_care.update_assisting()
		elif candidate != null and Input.is_action_just_pressed(&"interact"):
			candidate.rpc_id(1, &"request_assist")
		return
	Movement.on_foot_step(self, delta)


func _update_ground_safety() -> void:
	Movement.update_ground_safety(self)


## The box a lid action applies to: the one in hand first, then the one at
## this player's seat, then whichever package they're looking at.
func _lid_target(aimed: Node = null) -> DeliveryPackage:
	return _interaction_component.lid_target(aimed)


## Opening goes through the host like everything else that changes a
## package (rpc_id(1, ...) resolves to a local call on the host itself).
func _toggle_package_lid() -> void:
	_interaction_component.toggle_package_lid()


func _apply_look(motion: Vector2) -> void:
	Movement.apply_look(self, motion)


func _gather_package_input() -> Dictionary:
	return _seat_pose_component.gather_package_input()


func _publish_carry(carrying: bool) -> void:
	if carrying == _last_carrying:
		return
	_last_carrying = carrying
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal(&"carry_changed", carrying)


func _update_carried_package() -> void:
	_carry_component.update_carried_package()


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
	return _carry_component.carry_position()


func _raycast(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	return _carry_component.raycast(from, to, mask)


## The quick ping's callout: its network label (never translated), taken
## from the catalog so the Spanish phrase lives in one place.
const PING_LABEL: String = PingCatalog.OPTIONS[0]["label"]


func _send_ping(label: String = PING_LABEL) -> void:
	_interaction_component.send_ping(label)


func _show_first_trap_tip(package: DeliveryPackage) -> void:
	if package == null or package.trap_definition == null:
		return
	var trap_id: StringName = StringName(package.trap_definition.get(&"id"))
	var profile: Node = get_node_or_null(^"/root/UnlockManager")
	if profile == null or not bool(profile.call(&"mark_tip_seen", trap_id)):
		return
	var text: String = TutorialData.tip_text(trap_id)
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null and not text.is_empty():
		bus.emit_signal(&"tutorial_tip_requested", text)


func _try_interact() -> void:
	_interaction_component.try_interact()


func _transfer_target() -> Player:
	return _carry_component.transfer_target() as Player


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
	_carry_component.drop_carried()


func _drop_position(half_extents: Vector3) -> Vector3:
	return _carry_component.drop_position(half_extents)


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
	return _interaction_component.closest_interactable()


func _within_reach(target: Node3D) -> bool:
	return _interaction_component.within_reach(target)


## A loose package can bowl somebody over. This intentionally stays a
## controllable knockback with the current rig; a real ragdoll needs a
## dedicated physical skeleton asset rather than faking one by deleting the
## controller under a networked player.
@rpc("any_peer", "call_local", "unreliable")
func receive_package_hit(push: Vector3) -> void:
	# Loose boxes are simulated on the host; nobody else gets to knock people over.
	if not _from_host() or not RpcGuard.finite_vec3(push):
		return
	if _package_hit_cooldown > 0.0 or _seated:
		return
	_package_hit_cooldown = 0.45
	_flinch_time = 0.32
	velocity += push + Vector3.UP * 1.4
	if is_local():
		animator.play_one_shot(ANIM_JUMP, 420)
	if push.length() >= 2.2:
		_activate_ragdoll(push)


func _activate_ragdoll(push: Vector3) -> void:
	if _ragdolled:
		return
	_ragdolled = true
	var ragdoll := preload("res://modules/ragdoll/player_ragdoll.gd").new()
	get_parent().add_child(ragdoll)
	ragdoll.setup(self, get_tree().get_first_node_in_group(&"vehicle"), 1 | 64)
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
	_carry_component.apply_pick_up(package_path)


@rpc("any_peer", "call_local", "reliable")
func drop_carried() -> void:
	if not _from_host():
		return
	_carry_component.apply_drop_carried()


@rpc("any_peer", "call_local", "reliable")
func tend_package(package_path: NodePath) -> void:
	if not _from_host():
		return
	_seat_pose_component.apply_tend_package(package_path)


@rpc("any_peer", "call_local", "reliable")
func assist_package(package_path: NodePath) -> void:
	if not _from_host():
		return
	assisted_package = get_node_or_null(package_path) as DeliveryPackage


@rpc("any_peer", "call_local", "reliable")
func stop_assisting(package_path: NodePath) -> void:
	if not _from_host():
		return
	if assisted_package != null and assisted_package.get_path() == package_path:
		assisted_package = null


@rpc("any_peer", "call_local", "reliable")
func board_seat(seat_camera_path: NodePath, seat_path: NodePath) -> void:
	if not _from_host():
		return
	_seat_pose_component.apply_board_seat(seat_camera_path, seat_path)


## Seats are a temporary safe spot, not a lock-in. Leaving restores the
## on-foot controller at the seat's location, so passengers can react to
## loose cargo while the van is moving.
func leave_seat() -> void:
	_seat_pose_component.leave_seat()


## Where to stand when getting up: the seat's own "ExitPoint" if it has one
## (the driver climbs out through the cab door), otherwise a step forward
## from the seat, into the aisle it faces. Either way, dropped onto whatever
## floor is under that spot -- never left at eye height or inside a wall.
func _seat_exit_position(seat: Node3D) -> Vector3:
	return _seat_pose_component.seat_exit_position(seat)


func _from_host() -> bool:
	return RpcGuard.from_host(self)  # Also a genuine local call (offline).
