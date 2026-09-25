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
@onready var _interaction_component: Node = $PlayerInteraction

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
const CarryPose = preload("res://scripts/gameplay/player/carry_pose.gd")
const FaceCatalog = preload("res://scripts/presentation/face_catalog.gd")
const CharacterFace = preload("res://scripts/presentation/character_face.gd")
## Astra's rounded character (2026-09-24), game export built by
## art/rounded_character/build_game_export.py -- see assets/README.md
## "Personajes" for its clips (Idle/Walk/Stroll/TurnInPlace/Jump/PickUpPackage/
## PickUpHigh/Sit). One skinned
## mesh; surface 0 is the T-shirt, which carries the crew colour.
const CHARACTER_SCENE: PackedScene = preload("res://assets/models/characters/sm_char_player_rounded.glb")
const ANIM_IDLE: StringName = &"Idle"
const ANIM_WALK: StringName = &"Walk"
const ANIM_JUMP: StringName = &"Jump"
const ANIM_PICKUP: StringName = &"PickUpPackage"
## PickUpPackage squats to the floor; PickUpHigh takes a box at the waist
## without squatting. Same length and grab/lift times, so a pickup plays a
## blend of both weighted by where the hands meet the box (pickup_high_weight)
## -- built once per weight step into PICKUP_BLEND_LIBRARY. Heights are the
## wrists at the grab in each clip, above the feet (animation_library.py
## PICKUP_GRAB_Z x 0.5 m/BU).
const ANIM_PICKUP_HIGH: StringName = &"PickUpHigh"
const PICKUP_LOW_GRIP: float = 0.51
const PICKUP_HIGH_GRIP: float = 0.925
const PICKUP_BLEND_STEPS: int = 8
const PICKUP_BLEND_LIBRARY: StringName = &"pickup_blend"
## Played by every peer while seat_node_path is set -- it's derived from that
## replicated path, not from anim_state, so it needs no sync of its own.
const ANIM_SIT: StringName = &"Sit"
## Presentation-only gait under Walk: a real walk for partial stick input.
## anim_state still says Walk; each peer picks the gait from the replicated
## locomotion_speed (_gait_clip()), so it needs no sync of its own.
const ANIM_STROLL: StringName = &"Stroll"
## Speeds (m/s) the gait clips were authored at: played at speed / this, the
## planted feet keep pace with the ground.
const WALK_AUTHORED_SPEED: float = 3.6
const STROLL_AUTHORED_SPEED: float = 1.5
## Hysteresis between the gaits, so a stick held near one speed doesn't flicker.
const STROLL_BELOW: float = 2.2
const WALK_ABOVE: float = 2.6
## Small steps in place while the player turns standing still (the whole
## body rotates with the look yaw; without this the feet swivelled on the
## spot). The owner picks it in _update_movement_anim() from its own look
## turn rate, so it reaches the other peers through anim_state. Rates in
## rad/s, smoothed; hysteresis so a mouse flick doesn't flicker it. Turning
## with the truck the player rides in doesn't count: the floor turns too.
const ANIM_TURN: StringName = &"TurnInPlace"
const TURN_STEP_ABOVE: float = 1.5
const TURN_STEP_BELOW: float = 0.8
const TURN_RATE_SMOOTHING: float = 10.0
## Under this ground speed (m/s) the player stands (Idle), over it walks.
const IDLE_BELOW_SPEED: float = 0.3
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
var _anim_player: AnimationPlayer = null
## Replicated (see player.tscn) so every peer's own copy of this player's
## AnimationPlayer plays the same clip -- movement/jump/pickup state is only
## ever computed on the owning peer (is_local()), same authority split as
## seat_node_path above.
var anim_state: StringName = ANIM_IDLE
## Presentation state authored by the owning peer, replicated with anim_state.
## Scales the gait clips (see WALK_AUTHORED_SPEED); jump samples the real
## ascent/landing instead of playing a crouch after leaving the floor.
var locomotion_speed: float = 0.0
var _strolling: bool = false
## Look yaw applied since the last physics tick, and its smoothed rate (rad/s).
var _turn_yaw: float = 0.0
var turn_rate: float = 0.0
## Last jump_anim_time seen here, to catch the touchdown (0.9) on every peer.
var _seen_jump_time: float = 0.0
var jump_anim_time: float = 0.0
var _jump_airborne: bool = false
var _jump_landing_elapsed: float = -1.0
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
## carries its riders by hand (_ride_with_vehicle), so the controller's own
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
	_limit_visibility_to_ready_peers()


## A player who disconnects mid-carry must not leave their box frozen in the
## air with collisions off. package.carrier is only ever set on the host, so
## this only acts there.
func _exit_tree() -> void:
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network != null and network.call(&"is_host"):
		_release_seat_occupant(get_node_or_null(seat_node_path) as Node3D)
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
			face_eyes = profile.get("selected_eyes")
			face_mouth = profile.get("selected_mouth")
			profile.progress_changed.connect(_sync_profile_appearance)
	_build_body()
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
	_probe.area_entered.connect(_on_probe_entered)
	_probe.area_exited.connect(_on_probe_exited)


## Spawned into, and synced to, only the peers whose level is loaded (the
## host's call -- NetworkManager.is_peer_ready()). After a host restart each
## client reloads at its own pace; a spawn sent to one still on the old level
## was lost, and that client never saw this player again. Installed from
## _enter_tree(): set up in _ready, the synchronizer had already registered as
## public, and the host's own player started syncing to clients mid-reload --
## who couldn't resolve it and never saw the host move again.
func _limit_visibility_to_ready_peers() -> void:
	var sync := get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if sync == null or network == null or network.is_connected(&"peer_level_ready", _on_peer_level_ready):
		return
	sync.add_visibility_filter(func(peer_id: int) -> bool:
		return not multiplayer.is_server() or bool(network.call(&"is_peer_ready", peer_id)))
	if network.has_signal(&"peer_level_ready"):
		network.connect(&"peer_level_ready", _on_peer_level_ready)


func _on_peer_level_ready(peer_id: int) -> void:
	var sync := get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync != null and multiplayer.is_server():
		sync.update_visibility(peer_id)


## The rigged character, so teammates have someone to see. Colored per
## peer_id (see PLAYER_COLORS) doubles as the simplest possible "who is
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
	_enable_character_shadows(visual)

	_set_body_layers(visual, RenderLayers.LOCAL_BODY if is_local() else RenderLayers.WORLD)
	_apply_cosmetic()
	_character_face = CharacterFace.new()
	_character_face.setup(visual, _find_skeleton(visual), RenderLayers.LOCAL_BODY if is_local() else RenderLayers.WORLD)
	_apply_face()

	_anim_player = _find_animation_player(visual)
	if _anim_player != null:
		# The glTF importer doesn't carry Blender's "this clip loops" flag,
		# so it's set here once instead of needing a manual editor step
		# every time the source .blend is re-exported.
		for loop_clip: StringName in [ANIM_IDLE, ANIM_WALK, ANIM_STROLL, ANIM_SIT, ANIM_TURN]:
			if _anim_player.has_animation(loop_clip):
				_anim_player.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR
		_anim_player.play(ANIM_IDLE)
	_carry_pose = CarryPose.new()
	_carry_pose.name = "CarryPose"
	add_child(_carry_pose)
	_carry_pose.setup(self, _find_skeleton(visual))


func _set_body_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child: Node in node.get_children():
		_set_body_layers(child, layers)


func _apply_face() -> void:
	if _character_face != null:
		_character_face.set_expression(face_eyes, face_mouth)


func _sync_profile_appearance() -> void:
	var profile: Node = get_node_or_null("/root/UnlockManager")
	if profile != null and is_local():
		cosmetic_id = profile.selected_cosmetic
		face_eyes = profile.selected_eyes
		face_mouth = profile.selected_mouth


func _enable_character_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child: Node in node.get_children():
		_enable_character_shadows(child)



func _apply_cosmetic() -> void:
	if _body_visual == null:
		return
	var profile: Node = get_node_or_null("/root/UnlockManager")
	# The default ("team_color") keeps the per-peer crew colour, so teammates
	# can be told apart; a uniform someone picked replaces it.
	var color: Color = PLAYER_COLORS[get_multiplayer_authority() % PLAYER_COLORS.size()]
	if profile != null and not bool(profile.call(&"cosmetic_is_auto", cosmetic_id)):
		color = profile.call(&"cosmetic_color", cosmetic_id)
	var mesh_instance: MeshInstance3D = _find_mesh_instance(_body_visual)
	if mesh_instance != null and mesh_instance.mesh != null:
		# Surface 0 is the T-shirt; its collar/hem trim follows a shade darker.
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source: Material = mesh_instance.mesh.surface_get_material(surface)
			var tint: Color = color
			if surface != 0:
				if source == null or source.resource_name != "ShirtTrim":
					continue
				tint = color.darkened(0.18)
			var suit_material := (source.duplicate() if source != null else StandardMaterial3D.new()) as StandardMaterial3D
			suit_material.albedo_color = tint
			mesh_instance.set_surface_override_material(surface, suit_material)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Walk (a quick short-legged run) at full speed, Stroll for partial stick
## input: the run played slowly reads as slow motion, not as walking.
func _gait_clip() -> StringName:
	if _strolling and locomotion_speed > WALK_ABOVE:
		_strolling = false
	elif not _strolling and locomotion_speed < STROLL_BELOW:
		_strolling = true
	return ANIM_STROLL if _strolling and _anim_player.has_animation(ANIM_STROLL) else ANIM_WALK


## Both gaits start on the left foot's touchdown, so switching between them
## keeps the cycle phase: the feet carry on instead of skating to a new step.
func _play_clip(clip: StringName) -> void:
	var gaits: Array[String] = [String(ANIM_WALK), String(ANIM_STROLL)]
	var phase: float = -1.0
	if _anim_player.current_animation in gaits and String(clip) in gaits:
		phase = _anim_player.current_animation_position / maxf(_anim_player.current_animation_length, 0.001)
	# A pickup whose height arrives late (anim_state replicated before the
	# pick_up RPC) swaps blends in place instead of restarting the squat.
	var pickup_time: float = -1.0
	if _is_pickup_clip(StringName(_anim_player.current_animation)) and _is_pickup_clip(clip):
		pickup_time = _anim_player.current_animation_position
	# Idle <-> TurnInPlace blend a little longer: a step cut short settles.
	var turn_blend: bool = clip == ANIM_TURN or _anim_player.current_animation == String(ANIM_TURN)
	_anim_player.play(String(clip), 0.2 if phase >= 0.0 or turn_blend else 0.15)
	if phase >= 0.0:
		_anim_player.seek(phase * _anim_player.current_animation_length)
	elif pickup_time >= 0.0:
		_anim_player.seek(pickup_time)


func _is_pickup_clip(clip: StringName) -> bool:
	return clip == ANIM_PICKUP or clip == ANIM_PICKUP_HIGH or String(clip).begins_with(String(PICKUP_BLEND_LIBRARY) + "/")


## How much of PickUpHigh a pickup plays, from the height above the feet at
## which the hands meet the box (0 at the floor clip's grip, 1 at the high one's).
static func pickup_high_weight_for(grip_height: float) -> float:
	return clampf((grip_height - PICKUP_LOW_GRIP) / (PICKUP_HIGH_GRIP - PICKUP_LOW_GRIP), 0.0, 1.0)


## Same contact point carry_pose.gd puts the hands on: the box's upper sides.
func pickup_high_weight_for_package(package: Node3D) -> float:
	var half: Vector3 = package.call(&"get_half_extents") if package.has_method(&"get_half_extents") else Vector3.ONE * 0.325
	var grip: float = package.global_position.y + minf(half.y * 0.65, 0.16)
	return pickup_high_weight_for(grip - global_position.y)


## The pickup clip for pickup_high_weight: either authored clip at the ends,
## a baked blend of both in between (quantised, so at most a handful exist).
func _pickup_clip() -> StringName:
	var step: int = roundi(pickup_high_weight * PICKUP_BLEND_STEPS)
	if step <= 0 or not _anim_player.has_animation(ANIM_PICKUP_HIGH):
		return ANIM_PICKUP
	if step >= PICKUP_BLEND_STEPS:
		return ANIM_PICKUP_HIGH
	var blend_name := StringName("%s/%d" % [PICKUP_BLEND_LIBRARY, step])
	if not _anim_player.has_animation(blend_name):
		if not _anim_player.has_animation_library(PICKUP_BLEND_LIBRARY):
			_anim_player.add_animation_library(PICKUP_BLEND_LIBRARY, AnimationLibrary.new())
		var blended: Animation = blend_clips(_anim_player.get_animation(ANIM_PICKUP),
			_anim_player.get_animation(ANIM_PICKUP_HIGH), float(step) / PICKUP_BLEND_STEPS)
		_anim_player.get_animation_library(PICKUP_BLEND_LIBRARY).add_animation(StringName(str(step)), blended)
	return blend_name


## low blended toward high by weight, bone by bone, sampled at 30 Hz (the
## export's rate). Tracks high lacks, and non-transform tracks, come from low.
static func blend_clips(low: Animation, high: Animation, weight: float) -> Animation:
	var out := Animation.new()
	out.length = low.length
	var frames: int = ceili(low.length * 30.0)
	for track: int in low.get_track_count():
		var type: Animation.TrackType = low.track_get_type(track)
		var other: int = high.find_track(low.track_get_path(track), type)
		var index: int = out.add_track(type)
		out.track_set_path(index, low.track_get_path(track))
		out.track_set_interpolation_type(index, low.track_get_interpolation_type(track))
		var transform_track: bool = type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]
		if other < 0 or not transform_track:
			for key: int in low.track_get_key_count(track):
				out.track_insert_key(index, low.track_get_key_time(track, key), low.track_get_key_value(track, key))
			continue
		for frame: int in frames + 1:
			var t: float = minf(frame / 30.0, low.length)
			match type:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(index, t, low.position_track_interpolate(track, t).lerp(high.position_track_interpolate(other, t), weight))
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(index, t, low.rotation_track_interpolate(track, t).slerp(high.rotation_track_interpolate(other, t), weight))
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(index, t, low.scale_track_interpolate(track, t).lerp(high.scale_track_interpolate(other, t), weight))
	return out


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
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
	if event.is_action_pressed(&"use_card"):
		_use_card()
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
	var clip: StringName = anim_state if seat_node_path.is_empty() else ANIM_SIT
	if _anim_player != null and clip == ANIM_WALK:
		clip = _gait_clip()
	elif _anim_player != null and clip == ANIM_PICKUP:
		clip = _pickup_clip()
	elif _anim_player != null and clip == ANIM_TURN and not _anim_player.has_animation(ANIM_TURN):
		clip = ANIM_IDLE
	if _anim_player != null and _anim_player.current_animation != String(clip):
		_play_clip(clip)
	if _anim_player != null:
		if clip == ANIM_JUMP:
			_anim_player.speed_scale = 0.0
			_anim_player.seek(jump_anim_time, true)
			# The eyes squeeze shut as the landing's squash hits.
			if jump_anim_time >= 0.9 and _seen_jump_time < 0.9 and _character_face != null:
				_character_face.blink()
			_seen_jump_time = jump_anim_time
		elif clip == ANIM_WALK:
			_anim_player.speed_scale = clampf(locomotion_speed / WALK_AUTHORED_SPEED, 0.5, 1.5)
		elif clip == ANIM_STROLL:
			_anim_player.speed_scale = clampf(locomotion_speed / STROLL_AUTHORED_SPEED, 0.2, 1.6)
		else:
			_anim_player.speed_scale = 1.0
	if not is_local():
		_apply_net_state()
	elif not _seated:
		_ride_frame_by_frame()
	if not is_physics_interpolated_and_enabled():
		_pose_seated_body(delta)
	if _carry_pose != null:
		_carry_pose.update_pose(carried_package, _pickup_elapsed, delta)


## A client's truck is teleported by the network whenever an update lands,
## not on physics ticks, and isn't interpolated. A rider moved with it only
## on ticks, and drawn interpolated between them, was drawn up to a metre
## behind it at speed: the view jumped against the truck's own walls. While
## riding such a truck the owner follows it every frame, uninterpolated.
func _ride_frame_by_frame() -> void:
	var vehicle: Node3D = _find_vehicle()
	var per_frame: bool = _riding and vehicle != null and not vehicle.is_physics_interpolated_and_enabled()
	var wanted: Node.PhysicsInterpolationMode = PHYSICS_INTERPOLATION_MODE_OFF if per_frame else PHYSICS_INTERPOLATION_MODE_INHERIT
	if physics_interpolation_mode != wanted:
		physics_interpolation_mode = wanted
		reset_physics_interpolation()
	if per_frame:
		_ride_with_vehicle()


## Everyone else's copy of this player: where the owner says, inside this
## peer's truck if they're riding in it. Each frame against the truck as
## drawn -- except riding a simulated (interpolated) truck, the host's: there
## this body is solid in the moving bay, and a frame's drawn pose is up to a
## tick behind the simulated one. So there it follows the truck on the ticks
## (`on_tick`, from _physics_process) and is drawn interpolated along with it;
## placed per frame it rammed the loose boxes at every step.
func _apply_net_state(on_tick: bool = false) -> void:
	if not _has_net_state:
		return
	var vehicle: Node3D = _find_vehicle()
	var riding: bool = net_in_vehicle and vehicle != null
	var tick_placed: bool = riding and vehicle.is_physics_interpolated_and_enabled()
	var wanted: Node.PhysicsInterpolationMode = PHYSICS_INTERPOLATION_MODE_INHERIT if tick_placed else PHYSICS_INTERPOLATION_MODE_OFF
	if physics_interpolation_mode != wanted:
		physics_interpolation_mode = wanted
		reset_physics_interpolation()
	if on_tick != tick_placed:
		return
	if riding:
		global_position = (vehicle.global_transform if on_tick else _drawn_transform(vehicle)) * net_position
	else:
		global_position = net_position


## Where a node is drawn this frame. A client's truck is frozen and not
## interpolated, and then get_global_transform_interpolated() hands back last
## frame's cached pose instead of where the network just put it.
static func _drawn_transform(node: Node3D) -> Transform3D:
	return node.get_global_transform_interpolated() if node.is_physics_interpolated_and_enabled() else node.global_transform


func _publish_net_state() -> void:
	var vehicle: Node3D = _find_vehicle()
	# A little give once aboard, so standing right at the rear doors doesn't
	# flip between the truck's space and the world's every other frame.
	var riding: bool = vehicle != null and bool(vehicle.call(&"carries", global_position, RIDE_MARGIN if net_in_vehicle else 0.0))
	net_in_vehicle = riding
	net_position = vehicle.to_local(global_position) if riding else global_position


## Standing (or jumping) in the cargo bay, the owner is moved along with the
## truck by however much it moved since the last tick, turning with it. On a
## client the truck is a copy the network teleports, which carries nobody by
## itself: its walls just slid over the player (through the closed doors,
## and out the back).
func _ride_with_vehicle() -> void:
	var vehicle: Node3D = _find_vehicle()
	if vehicle == null:
		_riding = false
		return
	var now: Transform3D = vehicle.global_transform
	if _riding:
		var motion: Transform3D = now * _ride_last_transform.affine_inverse()
		global_position = motion * global_position
		var heading: Vector3 = motion.basis * -global_basis.z
		heading.y = 0.0
		if heading.length_squared() > 0.0001:
			rotate_y((-global_basis.z).signed_angle_to(heading.normalized(), Vector3.UP))
	_riding = bool(vehicle.call(&"carries", global_position, RIDE_MARGIN if _riding else 0.0))
	_ride_last_transform = now


## Where this player is for anything within reach -- opening a box, a
## photo, a ping: at their seat while seated. The body itself stays where
## they sat down (only its visual rides along), so the host measured a
## passenger kilometres from the box on their lap.
func reach_origin() -> Vector3:
	var seat: Node3D = get_node_or_null(seat_node_path) as Node3D if not seat_node_path.is_empty() else null
	return seat.global_position if seat != null else global_position


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
	if not riding:
		return ON_FOOT_MASK
	var vehicle: Node3D = _find_vehicle()
	var moving: bool = vehicle is RigidBody3D and (vehicle as RigidBody3D).linear_velocity.length() > RIDING_SPEED
	return RIDING_MASK if moving else ON_FOOT_MASK


func _find_vehicle() -> Node3D:
	if not is_instance_valid(_vehicle) and is_inside_tree():
		var found: Node = get_tree().get_first_node_in_group(&"vehicle")
		_vehicle = found as Node3D if found != null and found.has_method(&"carries") else null
	return _vehicle


## With physics interpolation on, the van is drawn between its physics ticks.
## A body snapped to the seat every rendered frame would sit at the raw tick
## pose instead and shake against the smoothly drawn cab, so the owner's own
## body is posed on the ticks (from _physics_process) and interpolated right
## along with it. Everyone else's copy isn't interpolated (it's placed by the
## network each frame), so it's posed every frame against the seat as drawn.
func _pose_seated_body(delta: float) -> void:
	if seat_node_path.is_empty():
		_stop_driver_ik()
		if _body_visual != null:
			# Clear the seat's world-space offset on every peer after standing.
			_body_visual.position = Vector3.ZERO
			_body_visual.rotation.y = 0.0
			_body_visual.rotation.z = 0.0
			_body_visual.position.y = sin(_bob_time * TAU) * 0.025 * _bob_amount
			var flinch: float = sin(_flinch_time / 0.32 * PI) * 0.26
			_body_visual.rotation.x = move_toward(_body_visual.rotation.x, flinch, delta * 12.0)
		return
	var seat: Node3D = get_node_or_null(seat_node_path) as Node3D
	if seat == null:
		return
	# Seat anchors are eye height (where the camera goes), while this character
	# is rooted at its feet; the Sit clip drops its pelvis to about the root.
	_seat_pose_blend = minf(_seat_pose_blend + delta * 7.0, 1.0)
	var seat_offset: Vector3 = _seat_body_offset(seat.name)
	var seat_pose: Transform3D = seat.global_transform if is_physics_interpolated_and_enabled() else _drawn_transform(seat)
	var target_pose := seat_pose.translated_local(seat_offset)
	_body_visual.global_transform = _body_visual.global_transform.interpolate_with(target_pose, _seat_pose_blend)
	# Leaning back suits the driver's reach; in the cargo bay a full lean put
	# the head into the wall behind the seat.
	# The rack jump seats are too shallow to lean at all without the head
	# touching the wall.
	var lean: float = 0.18 if seat.name == &"DriverEyePoint" else (0.0 if String(seat.name).begins_with("RackSeat") else 0.08)
	_body_visual.rotation.x = lean + sin(Time.get_ticks_msec() * 0.008) * 0.025
	_configure_driver_ik(seat)


## Where the rounded character's root goes, in the seat marker's space, so
## its Sit pose rests on that seat's cushion. Measured in the truck by
## tests/render_player_character.gd (2026-09-24): the wall cushions are
## ~0.58 m under their eye markers, the rack jump seats ~0.55 m and only
## 0.36 m deep, and the driver's cushion sits behind the wheel -- 0.37 m
## forward keeps both wrists on the rim at full reach. The cab is 6 cm too
## low for this character fully on the cushion, so the driver sinks into it
## a little rather than putting his head through the roof.
func _seat_body_offset(seat_name: StringName) -> Vector3:
	if seat_name == &"DriverEyePoint":
		return Vector3(0.0, -0.73, -0.37)
	if String(seat_name).begins_with("RackSeat"):
		return Vector3(0.0, -0.35, -0.14)
	if seat_name == &"CenterSeatEyePoint":
		# Backs onto the cab bulkhead: slid 0.19 m away from it (seat-local +X
		# is the van's +Z) or a foot and forearm poke into the cab.
		return Vector3(0.19, -0.38, -0.16)
	return Vector3(0.0, -0.38, -0.16)


## Real skeletal IK for the driver: the two target nodes live on the wheel,
## therefore they rotate with it and SkeletonIK3D solves upper arm → forearm
## → hand every frame. It only activates on the designated driver anchor;
## passengers keep the Sit clip's hands-on-lap pose. The rounded character's
## own arms reach the wheel, so the old stand-in arm cylinders are gone.
func _configure_driver_ik(seat: Node3D) -> void:
	if _driver_ik_ready or seat.name != &"DriverEyePoint" or _body_visual == null:
		return
	var wheel: Node3D = seat.get_parent().get_parent().find_child("SteeringWheel", true, false) as Node3D
	var skeleton := _find_skeleton(_body_visual)
	if wheel == null or skeleton == null:
		return
	for side: float in DRIVER_ARM_BONES:
		var bones: Array = DRIVER_ARM_BONES[side]
		var target := Marker3D.new()
		target.name = "DriverHandTargetLeft" if side < 0.0 else "DriverHandTargetRight"
		target.position = Vector3(side * 0.19, 0.0, -0.03)
		wheel.add_child(target)
		var ik := SkeletonIK3D.new()
		ik.name = "DriverIK" + str(side)
		ik.root_bone = bones[0]
		ik.tip_bone = bones[1]
		ik.override_tip_basis = false
		skeleton.add_child(ik)
		# An absolute target path is required here: the wheel is in the vehicle
		# branch, outside the player's Skeleton3D branch. The relative path was
		# accepted by the property but never solved, leaving both arms at rest.
		ik.target_node = target.get_path()
		# Continuous, not start(true): a one-time solve is overwritten by the
		# Sit clip on the very next frame, which is why the arms never reached
		# the wheel before and stand-in cylinders were drawn instead.
		ik.start(false)
		_driver_ik_nodes.append(ik)
		_driver_arm_targets.append(target)
	_driver_ik_ready = not _driver_ik_nodes.is_empty()


func _stop_driver_ik() -> void:
	if not _driver_ik_ready:
		return
	# Freed, not just stopped: boarding again builds a fresh pair, and the old
	# ones would otherwise pile up on the skeleton and the wheel.
	for ik: SkeletonIK3D in _driver_ik_nodes:
		if is_instance_valid(ik):
			ik.stop()
			ik.queue_free()
	_driver_ik_nodes.clear()
	for target: Node3D in _driver_arm_targets:
		if is_instance_valid(target):
			target.queue_free()
	_driver_arm_targets.clear()
	_driver_ik_ready = false


func _physics_process(delta: float) -> void:
	_package_hit_cooldown = maxf(0.0, _package_hit_cooldown - delta)
	_pickup_elapsed += delta
	# Remote players must also stop colliding while seated. Their input RPC
	# is targeted, but their seat path is replicated to everyone.
	if not is_local():
		collision_layer = 8 if seat_node_path.is_empty() else 0
		collision_mask = _on_foot_mask(net_in_vehicle) if seat_node_path.is_empty() else 0
		_apply_net_state(true)
	if is_physics_interpolated_and_enabled():
		_pose_seated_body(delta)
	if not is_local():
		return
	# Before any early return: a menu open in the back of a moving truck
	# must not leave the player behind.
	if _seated:
		_riding = false
	else:
		_ride_with_vehicle()
		collision_mask = _on_foot_mask(_riding)
	_publish_net_state()
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
	locomotion_speed = ground_speed
	_update_jump_animation(delta, ground_speed)
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
	return _interaction_component.is_interact_event(event)


func _is_drop_event(event: InputEvent) -> bool:
	return _interaction_component.is_drop_event(event)


func _is_open_event(event: InputEvent) -> bool:
	return _interaction_component.is_open_event(event)


## The box a lid action applies to: the one in hand first, then the one at
## this player's seat, then whichever package they're looking at.
func _lid_target(aimed: Node = null) -> DeliveryPackage:
	return _interaction_component.lid_target(aimed)


## Opening goes through the host like everything else that changes a
## package (rpc_id(1, ...) resolves to a local call on the host itself).
func _toggle_package_lid() -> void:
	_interaction_component.toggle_package_lid()


func _publish_lid_hint(package: DeliveryPackage) -> void:
	_interaction_component.publish_lid_hint(package)


func _poll_interact() -> void:
	_interaction_component.poll_interact()


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
	_turn_yaw += motion.x
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
	_measure_turn_rate(get_physics_process_delta_time())
	# An interrupted pickup must not make a moving player slide on its
	# planted crouch. The package lift and hand contact continue independently.
	if anim_state == ANIM_PICKUP and ground_speed > 0.3 and _pickup_elapsed > 0.16:
		_anim_lock_until_msec = 0
	if anim_state == ANIM_JUMP and _jump_airborne:
		return
	if Time.get_ticks_msec() < _anim_lock_until_msec:
		return
	var next_state: StringName = movement_state(ground_speed, is_on_floor(), turn_rate, anim_state == ANIM_TURN)
	if anim_state != next_state:
		anim_state = next_state


## Walk when moving on the floor; standing, TurnInPlace while turning faster
## than TURN_STEP_ABOVE (until it drops under TURN_STEP_BELOW), else Idle.
static func movement_state(ground_speed: float, on_floor: bool, rate: float, turning: bool) -> StringName:
	if ground_speed > IDLE_BELOW_SPEED and on_floor:
		return ANIM_WALK
	if on_floor and rate > (TURN_STEP_BELOW if turning else TURN_STEP_ABOVE):
		return ANIM_TURN
	return ANIM_IDLE


## The yaw rate of this body (which carries BodyVisual) from the look input
## since the last tick, smoothed: mouse motion lands in bursts between ticks.
func _measure_turn_rate(delta: float) -> void:
	if delta <= 0.0:
		return
	var rate: float = absf(_turn_yaw) / delta
	_turn_yaw = 0.0
	turn_rate = lerpf(turn_rate, rate, 1.0 - exp(-TURN_RATE_SMOOTHING * delta))


func _play_one_shot(clip: StringName, lock_ms: int) -> void:
	anim_state = clip
	_anim_lock_until_msec = Time.get_ticks_msec() + lock_ms
	if clip == ANIM_JUMP:
		_jump_airborne = true
		_jump_landing_elapsed = -1.0
		jump_anim_time = 0.0


func _update_jump_animation(delta: float, ground_speed: float) -> void:
	if anim_state != ANIM_JUMP:
		# Also pose an unplanned fall from a ledge, without changing physics.
		if not is_on_floor() and velocity.y < -1.0 and anim_state != ANIM_PICKUP:
			_play_one_shot(ANIM_JUMP, JUMP_ANIM_LOCK_MS)
		else:
			return
	if not is_on_floor():
		_jump_airborne = true
		_jump_landing_elapsed = -1.0
		if velocity.y >= 0.0:
			jump_anim_time = lerpf(0.0, 0.4, clampf(1.0 - velocity.y / JUMP_VELOCITY, 0.0, 1.0))
		else:
			jump_anim_time = lerpf(0.4, 0.84, clampf(-velocity.y / JUMP_VELOCITY, 0.0, 1.0))
	else:
		_jump_landing_elapsed = maxf(_jump_landing_elapsed, 0.0) + delta
		jump_anim_time = minf(1.6, 0.9 + _jump_landing_elapsed)
		if _jump_landing_elapsed >= (0.24 if ground_speed > 0.3 else 0.65):
			_jump_airborne = false
			_anim_lock_until_msec = 0


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
	_interaction_component.publish_prompt(value)


## A visible glow on whatever the player is currently looking at (item #98),
## instead of only the HUD's text prompt. Duck-typed via has_method(): not
## every Interactable bothers implementing highlight() (a package mount is
## an empty slot, nothing to glow), so this is opt-in per type.
func _update_highlight(target: Node) -> void:
	_interaction_component.update_highlight(target)


func _update_carried_package() -> void:
	# Position follows the hold point (in front of the camera, so it bobs
	# naturally with head look), but rotation stays tied to the body's yaw
	# only -- looking down doesn't swing the box's face into the lens. Goes
	# through the host either way (rpc_id(1, ...) with call_local resolves to
	# a direct call when this peer already is the host), since the package is
	# host-authoritative and only it should ever move the real one.
	var carry_transform := Transform3D(global_basis, _carry_position())
	# The box waits for the reaching hands, then follows the lift instead of
	# teleporting to chest height on the first pickup tick. Ownership/collisions
	# remain host-authoritative throughout this presentation transition.
	if _pickup_elapsed < 1.3:
		var origin: Transform3D = _pickup_from
		var pickup_vehicle: Node3D = _find_vehicle()
		if _pickup_in_vehicle and pickup_vehicle != null:
			origin = pickup_vehicle.global_transform * origin
		var lift: float = smoothstep(0.42, 1.3, _pickup_elapsed)
		# Moving away accelerates the lift so the arms are never left behind.
		if locomotion_speed > 0.3:
			lift = maxf(lift, smoothstep(0.16, 0.5, _pickup_elapsed))
		carry_transform = origin.interpolate_with(carry_transform, lift)
	# In the truck, in the truck's space: this client's copy of the truck
	# trails the host's, and a world position placed against the host's put
	# the box a metre behind the hands at speed.
	var vehicle: Node3D = _find_vehicle()
	var aboard: bool = vehicle != null and bool(vehicle.call(&"carries", carry_transform.origin, RIDE_MARGIN))
	if aboard:
		carry_transform = vehicle.global_transform.affine_inverse() * carry_transform
	carried_package.rpc_id(1, &"submit_carry_transform", carry_transform, aboard)
	_package_focus.dof_blur_far_enabled = true
	_package_focus.dof_blur_far_distance = 1.45
	_package_focus.dof_blur_far_transition = 1.0
	_package_focus.dof_blur_amount = 0.18


func _clear_carry_focus() -> void:
	if _package_focus != null:
		_package_focus.dof_blur_far_enabled = false

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
	# Looking up should not lift a box beyond this short character's arms.
	target.y = clampf(target.y, global_position.y + 0.8, global_position.y + 1.3)
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
	_interaction_component.send_ping()


func _use_card() -> void:
	_interaction_component.use_card()


func _try_interact() -> void:
	_interaction_component.try_interact()


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
	# Same as carrying: set down in the truck, it's placed on the host's truck.
	var vehicle: Node3D = _find_vehicle()
	var aboard: bool = vehicle != null and bool(vehicle.call(&"carries", drop_transform.origin, RIDE_MARGIN))
	if aboard:
		drop_transform = vehicle.global_transform.affine_inverse() * drop_transform
	carried_package.rpc_id(1, &"request_drop", drop_transform, aboard)
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
	return _interaction_component.closest_interactable()


func _within_reach(target: Node3D) -> bool:
	return _interaction_component.within_reach(target)


func _on_probe_entered(area: Area3D) -> void:
	_interaction_component.on_probe_entered(area)


func _on_probe_exited(area: Area3D) -> void:
	_interaction_component.on_probe_exited(area)


## A loose package can bowl somebody over. This intentionally stays a
## controllable knockback with the current rig; a real ragdoll needs a
## dedicated physical skeleton asset rather than faking one by deleting the
## controller under a networked player.
@rpc("any_peer", "call_local", "unreliable")
func receive_package_hit(push: Vector3) -> void:
	# Loose boxes are simulated on the host; nobody else gets to knock people over.
	if not _from_host():
		return
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
	if was_empty and carried_package != null:
		_pickup_elapsed = 0.0
		_pickup_from = carried_package.global_transform
		pickup_high_weight = pickup_high_weight_for_package(carried_package)
		var pickup_vehicle: Node3D = _find_vehicle()
		_pickup_in_vehicle = pickup_vehicle != null and bool(pickup_vehicle.call(&"carries", _pickup_from.origin, RIDE_MARGIN))
		if _pickup_in_vehicle:
			_pickup_from = pickup_vehicle.global_transform.affine_inverse() * _pickup_from
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
		_clear_carry_focus()


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
	collision_mask = ON_FOOT_MASK
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
