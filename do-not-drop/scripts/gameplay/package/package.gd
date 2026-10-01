class_name DeliveryPackage
extends RigidBody3D
## Physical entity and trap integration. Presentation subscribes independently.
##
## Host-authoritative, like the van: authority defaults to the host since this is a static, non-spawned node.
## Non-host peers freeze it and let their MultiplayerSynchronizer puppet the transform instead.

@export var package_id: StringName = &"fragile_01"
@export var trap_definition: TrapDefinition = preload("res://data/traps/fragile.tres")
@export_range(0.0, 5.0, 0.05) var spawn_grace_time: float = 1.25
@export_range(0.0, 2.0, 0.05) var impact_cooldown: float = 0.30
## What's inside (PackageContent). Left empty, the trap picks one from its
## own list -- see content_definition().
@export var content: Resource = null
## An open box tips its contents out past this tilt from upright (~70°)...
@export_range(0.0, 1.0, 0.01) var spill_tilt_cos: float = 0.34
## ...or when a hit this hard (change in velocity, m/s) catches it open.
@export_range(0.0, 30.0, 0.5) var spill_impact: float = 9.0
## Scales every impact before the trap sees it: 1 is bare, lower absorbs
## (the depot's padding supply sets it for the run -- see depot.gd).
@export_range(0.0, 1.0, 0.05) var impact_absorption: float = 1.0
## How close a player has to be to open or close it.
const OPEN_REACH: float = 3.0
const TRANSFER_REACH: float = 2.4
const ASSIST_REACH: float = 1.5
const ASSIST_MERIT_SECONDS: float = 10.0
const PACKAGE_COLLISION_MIN_SPEED: float = 2.2
const PACKAGE_COLLISION_DAMAGE_SCALE: float = 0.62
const PACKAGE_COLLISION_COOLDOWN: float = 0.16
const PLAYER_HIT_MIN_SPEED: float = 4.0
## An impact at least this hard (m/s) briefly interrupts tool work.
const HARD_HIT_SPEED: float = 6.0
const CareModel = preload("res://scripts/gameplay/package/package_care.gd")
var care = CareModel.new()
var care_state: Dictionary = {}:
	set(value):
		care_state = value
		if is_inside_tree() and not is_multiplayer_authority():
			care.apply_snapshot(value)
var salvage_state: Dictionary = {}
var _care_publish_time: float = 0.0
var _care_worker: int = 0
var _assist_age: float = 99.0
var _motion_velocity := Vector3.ZERO
var _motion_initialized: bool = false
var _motion_acceleration := Vector3.ZERO
var _salvage_view: Node
## Replicated: the rack bay a box on its tender's lap goes back to (SeatTending.bind_lap()).
var lap_mount_path: NodePath = NodePath()
## What a loose box collides with: the environment, other boxes and the
## truck's cargo shell (vehicle.gd SHELL_LAYER) -- never the truck's own body,
## which a box sliding about the bay used to shove (it drove in jerks).
const LOOSE_MASK: int = 1 | 4 | 64
const PLAYER_HIT_PUSH_SCALE: float = 0.38

var trap_behavior: ITrapBehavior
var is_held: bool = false:
	set(value):
		is_held = value
		collision_layer = 0 if value else 4
		collision_mask = 0 if value else LOOSE_MASK
var is_loaded: bool = false
## Set by place_at(), cleared by release_mount(). Lets a pickup free its shelf slot with a direct reference
## instead of scanning every mount in the "package_mount" group to find whichever one claims this package.
var current_mount: Node = null
## Replicate shelf occupancy as well as the box transform: clients use it
## to decide whether they may board, tend cargo or place another box.
var current_mount_path: NodePath = NodePath():
	set(value):
		if is_instance_valid(current_mount) and &"occupied_by" in current_mount:
			current_mount.set(&"occupied_by", null)
		current_mount_path = value
		current_mount = get_node_or_null(value) if not value.is_empty() and is_inside_tree() else null
		if current_mount != null and &"occupied_by" in current_mount:
			current_mount.set(&"occupied_by", self)
## Host-only: the player holding this box right now. Clients never set it.
var carrier: Node = null
## Written each frame by whoever is tending this package. Plain data, so the
## host can apply a remote client's input the same way once networking lands.
var player_input: Dictionary = {}
## Lid state, host-authoritative and replicated (see package.tscn). Opening lets the crew check what they're
## carrying; an open box can spill, and the resident notices one that shows up open.
var is_open: bool = false
## Host decides these event effects; MultiplayerSynchronizer copies them.
var label_swapped_with: StringName = &""
var disguise_trap_id: StringName = &""
var disguise_revealed: bool = false
var parasite_partner_id: StringName = &""
## The opener is recorded before package_lid_changed is relayed.
var last_opener_peer_id: int = 0
var _sharing_parasite_damage: bool = false
## Damage copied through a parasite link stays outside the trap behavior:
## several traps derive their raw integrity from a timer/aggression every
## frame, which would otherwise overwrite damage applied through damage().
var _parasite_damage: float = 0.0
## Replicated too: once the contents are on the floor there's nothing left
## to close the box on.
var contents_spilled: bool = false
## Replicated in place of position/rotation (see package.tscn). Inside the truck's cargo bay the box is sent
## in the truck's own space, and a client puts it back on *its* copy of the truck. In world space the two
## arrived from separate synchronizers, out of step: at speed the boxes trailed the truck by a good part of a
## metre, so on clients they bounced about, went through the walls and seemed to fall out.
var net_transform: Transform3D = Transform3D.IDENTITY:
	set(value):
		net_transform = value
		_has_net_state = true
var net_in_vehicle: bool = false
var _has_net_state: bool = false
var _vehicle: Node3D = null
## Host: the carrier's latest hold pose, in the truck's space when aboard. Re-applied every tick against the
## host's own truck, so a box carried in the moving bay rides with it between the carrier's updates.
var _carry_pose: Transform3D = Transform3D.IDENTITY
var _carry_in_vehicle: bool = false
## Carrier's own client: where its hands hold the box this tick (see
## predict_carry()), in the truck's space when aboard.
const PREDICTION_FRAMES: int = 2
var _predicted_pose: Transform3D = Transform3D.IDENTITY
var _predicted_in_vehicle: bool = false
var _predicted_frame: int = -100
## Host: the peer whose seat looks after this box (seat_point.gd), the only
## one whose trap input counts, and how long since their last sample.
var tender_peer_id: int = 0
var assistant_peer_id: int = 0
## peer id -> {"input": Dictionary, "age": float}. The host combines the
## primary sample at full strength and one assistant at half strength.
var _tender_inputs: Dictionary = {}
var _assist_seconds: float = 0.0
## Host-only merit attribution. Trap milestones belong to the last passenger who sent an input that could
## actually affect the box; carry milestones belong to the last player who held it.
var _last_tender_peer: int = 0
var _last_holder_peer: int = 0
var _rescue_pending: bool = false
var _milestone_counts: Dictionary = {}
## Host: the last announced bump this box already felt (RoadImpacts id, -1
## none), so crossing one counts once.
var _road_jolted: int = -1
## Host: what the last published cushion state looked like (bump announced,
## tap shielding, hits saved, taps), so a change goes out at once instead of
## waiting for the next 0.1 s publish.
var _cushion_signature: int = 0
## Stale trap input is dropped after this long: a passenger who paused, or
## tabbed out, holding "steady" would otherwise keep the trap calm forever.
const TENDER_INPUT_TIMEOUT: float = 0.25
## Handed over at a door: on a client the network stops placing it, the
## hand-over plays out and it goes.
var _consumed: bool = false
## How far past the cargo bay's edge a box already aboard still counts as
## aboard (see Vehicle.carries()).
const RIDE_MARGIN: float = 0.4
var integrity: float:
	get:
		var raw: float = trap_behavior.integrity if trap_behavior != null else 100.0
		return minf(care.quality_cap, maxf(raw - _parasite_damage, 0.0))
var integrity_max: float:
	get:
		return trap_behavior.integrity_max if trap_behavior != null else 100.0
var trap_state: int:
	get:
		if _lost or care.phase == &"lost":
			return ITrapBehavior.TrapState.RUINED
		if care.needs_restore:
			return ITrapBehavior.TrapState.AT_RISK
		if integrity <= 0.0:
			return ITrapBehavior.TrapState.AT_RISK
		return trap_behavior.get_state() if trap_behavior != null else 0
## A package can be written off for reasons no trap knows about -- falling out
## of the van, say -- without every trap needing its own concept of that.
var _lost: bool = false

var _previous_velocity: Vector3 = Vector3.ZERO
var _has_previous_velocity: bool = false
var _age: float = 0.0
var _impact_cooldown_remaining: float = 0.0
const HINT_RELAY_INTERVAL: float = 0.25
var _hint_relay_time: float = 0.0
var _package_hit_cooldowns: Dictionary = {}


## Synced only to peers whose level is loaded (NetworkManager.is_peer_ready()), same as the players. Installed
## before the synchronizer (a child) enters the tree and registers: after a host restart the new level's boxes
## were synced to clients still on the old level, where a box handed over last run was gone; that client never
## resolved it and never saw that box move again.
func _enter_tree() -> void:
	var sync := get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var network := PackageAutoloads.network(self)
	if sync == null or network == null or network.peer_level_ready.is_connected(_on_peer_level_ready):
		return
	sync.add_visibility_filter(func(peer_id: int) -> bool:
		return not multiplayer.is_server() or network.is_peer_ready(peer_id))
	network.peer_level_ready.connect(_on_peer_level_ready)
	network.peer_removed.connect(peer_left)  # Not peer_disconnected: late for a dropped ghost (N-221).


func _on_peer_level_ready(peer_id: int) -> void:
	var sync := get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync != null and multiplayer.is_server():
		sync.update_visibility(peer_id)


func _ready() -> void:
	if not is_multiplayer_authority():
		freeze = true
		# Placed by the network every frame (_process), against the truck as it's drawn: interpolating between
		# physics ticks on top of that only made it trail behind.
		physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	initialize_trap()
	_salvage_view = preload("res://scripts/gameplay/package/package_salvage.gd").new()
	_salvage_view.name = "PackageSalvage"
	add_child(_salvage_view)
	body_entered.connect(_on_body_entered)
	if is_multiplayer_authority():
		_publish_net_state()


## Host: what the synchronizer sends this tick. Read before the physics step,
## so the box and the truck come from the same step.
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if is_held and _carry_in_vehicle:
		var vehicle: Node3D = _find_vehicle()
		if vehicle != null:
			global_transform = vehicle.global_transform * _carry_pose
	_age_tender_inputs(delta)
	if assistant_peer_id > 0 and trap_state != ITrapBehavior.TrapState.AT_RISK:
		set_assistant(0)
	elif assistant_peer_id > 0 and _has_fresh_input(assistant_peer_id):
		_assist_seconds += delta
		if _assist_seconds >= ASSIST_MERIT_SECONDS:
			_assist_seconds -= ASSIST_MERIT_SECONDS
			_award_milestone(assistant_peer_id, &"assist")
	# A care worker whose input stopped arriving is no longer working the box.
	if _care_worker != 0 and not _has_fresh_input(_care_worker):
		_care_worker = 0
	_assist_age += delta
	# Worn off here, not in the care model, so a box outside the run's
	# cargo (or not simulated this tick) can't stay shielded forever.
	care.recent_hit = maxf(0.0, care.recent_hit - delta)
	if _is_run_active() and not _consumed and _registered_for_run():
		_simulate_cargo(delta)
	_publish_net_state()
	# Continuous collision only while loose, or thrown about the bay: riding along with it on, a box was swept
	# out through the shut rear doors (playtest 2026-09-27, see Vehicle.needs_sweep()).
	var vehicle: Node3D = _find_vehicle()
	var sweep: bool = vehicle == null or bool(vehicle.call(&"needs_sweep", self,
			RIDE_MARGIN if net_in_vehicle else 0.0))
	if continuous_cd != sweep:
		continuous_cd = sweep


## Client: put the box where the host says, on this peer's truck if it rides
## -- or, in the carrier's own hands, where they hold it right now.
func _process(_delta: float) -> void:
	if is_multiplayer_authority() or _consumed:
		return
	var predicted: bool = Engine.get_physics_frames() - _predicted_frame <= PREDICTION_FRAMES
	if not predicted and not _has_net_state:
		return
	var pose: Transform3D = _predicted_pose if predicted else net_transform
	var riding: bool = _predicted_in_vehicle if predicted else net_in_vehicle
	var vehicle: Node3D = _find_vehicle()
	if riding and vehicle != null:
		# A client's truck is frozen, so not interpolated: its interpolated transform is then last frame's
		# cached one, not where the network just put it, and the box would trail the truck by a frame.
		var vehicle_pose: Transform3D = vehicle.get_global_transform_interpolated() if vehicle.is_physics_interpolated_and_enabled() else vehicle.global_transform
		global_transform = vehicle_pose * pose
	else:
		global_transform = pose


## The carrier's own client, every physics tick next to submit_carry_transform: draw the box in its hands now
## instead of when the host's copy comes back. Over Steam it trailed the carrier by the whole round trip
## (playtest 2026-09-29). The host still decides where the box is; this only lasts while the carrier keeps
## calling it.
func predict_carry(carry_transform: Transform3D, in_vehicle: bool = false) -> void:
	if is_multiplayer_authority():
		return
	_predicted_pose = carry_transform
	_predicted_in_vehicle = in_vehicle
	_predicted_frame = Engine.get_physics_frames()


func _publish_net_state() -> void:
	if not is_inside_tree():
		return
	var vehicle: Node3D = _find_vehicle()
	# A little give once aboard: a box right at the rear doors mustn't flip
	# between the truck's space and the world's every other frame.
	var riding: bool = vehicle != null and bool(vehicle.call(&"carries", global_position, RIDE_MARGIN if net_in_vehicle else 0.0))
	net_in_vehicle = riding
	net_transform = vehicle.global_transform.affine_inverse() * global_transform if riding else global_transform


func _find_vehicle() -> Node3D:
	if not is_instance_valid(_vehicle) and is_inside_tree():
		var found: Node = get_tree().get_first_node_in_group(&"vehicle")
		_vehicle = found as Node3D if found != null and found.has_method(&"carries") else null
	return _vehicle


func initialize_trap() -> void:
	# Definitions may be shared; behavior resources must not be.
	trap_behavior = trap_definition.create_behavior() as ITrapBehavior
	if trap_behavior == null:
		return
	var config: Dictionary = trap_definition.params.duplicate(true)
	config["roll_seed"] = PackageRescue.roll_seed(self)
	trap_behavior.on_setup(self, config)
	_road_jolted = -1
	_age = 0.0
	_impact_cooldown_remaining = 0.0
	_has_previous_velocity = false
	_lost = false
	_parasite_damage = 0.0
	_last_tender_peer = 0
	_last_holder_peer = 0
	_rescue_pending = false
	_milestone_counts.clear()
	care = CareModel.new()
	care_state = care.snapshot()
	salvage_state = {}
	_motion_initialized = false
	_tender_inputs.clear()
	assistant_peer_id = 0
	_assist_seconds = 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var current_velocity: Vector3 = state.linear_velocity
	_age += state.step
	_impact_cooldown_remaining = maxf(0.0, _impact_cooldown_remaining - state.step)
	for other_id: int in _package_hit_cooldowns.keys():
		var seconds: float = float(_package_hit_cooldowns[other_id]) - state.step
		if seconds <= 0.0:
			_package_hit_cooldowns.erase(other_id)
		else:
			_package_hit_cooldowns[other_id] = seconds
	if _has_previous_velocity and _age >= spawn_grace_time and _is_run_active():
		# Gravity during free fall is not an impact. Collision resolution changes
		# velocity suddenly, while this subtraction removes the expected gravity step.
		var collision_delta: Vector3 = current_velocity - _previous_velocity - state.total_gravity * state.step
		if _impact_cooldown_remaining <= 0.0:
			var previous_integrity: float = integrity
			apply_impact(collision_delta.length())
			if integrity < previous_integrity:
				_impact_cooldown_remaining = impact_cooldown
	if is_open and not contents_spilled and not is_held:
		var hit: float = 0.0
		if _has_previous_velocity and _age >= spawn_grace_time:
			hit = (current_velocity - _previous_velocity - state.total_gravity * state.step).length()
		if state.transform.basis.y.normalized().dot(Vector3.UP) < spill_tilt_cos or hit > spill_impact:
			spill_contents(current_velocity)
	_previous_velocity = current_velocity
	_has_previous_velocity = true


func apply_impact(delta_velocity: float) -> void:
	if trap_behavior == null or not _is_run_active():
		return
	# Mid-rescue the contents are already out: nothing left for a hit to break.
	# Echoes of one collision are already folded by PACKAGE_COLLISION_COOLDOWN.
	if care.needs_restore or care.phase == &"lost":
		return
	var routes: Node = PackageAutoloads.routes(self)
	if routes != null:
		routes.call(&"on_package_impact", self, delta_velocity)
	var before_integrity: float = integrity
	var before_state: int = trap_state
	var strength: float = clampf(delta_velocity, 0.0, 9.0) * impact_absorption * care.impact_scale()
	trap_behavior.on_impact(strength)
	if delta_velocity >= HARD_HIT_SPEED:
		# Shaken hard: tool work pauses a moment (package_care.gd advance_work).
		care.recent_hit = 0.65
	care.on_hard_hit(delta_velocity)
	_check_recovery()
	_report_change(before_integrity, before_state, tr("HUD_PACKAGE_RUINED_IMPACTS"))


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_hit_player(body as Player)
		return
	var other := body as DeliveryPackage
	if other == null or other == self or is_held or other.is_held or freeze or other.freeze:
		return
	if not _is_run_active() or not other._is_run_active():
		return
	var other_id: int = other.get_instance_id()
	if _package_hit_cooldowns.has(other_id):
		return
	var relative_velocity: Vector3 = linear_velocity - other.linear_velocity
	var strength: float = relative_velocity.length()
	if strength < PACKAGE_COLLISION_MIN_SPEED:
		return
	_package_hit_cooldowns[other_id] = PACKAGE_COLLISION_COOLDOWN
	other._package_hit_cooldowns[get_instance_id()] = PACKAGE_COLLISION_COOLDOWN
	# The normal physics bounce remains authoritative.  Adding a little spin
	# lets a hard hit visibly cascade through a stack of loose cargo.
	var spin: Vector3 = relative_velocity.normalized().cross(Vector3.UP)
	apply_torque_impulse(spin * strength * 0.12)
	other.apply_torque_impulse(-spin * strength * 0.12)
	var damage_speed: float = strength * PACKAGE_COLLISION_DAMAGE_SCALE
	apply_impact(damage_speed)
	other.apply_impact(damage_speed)
	_emit_event(&"package_collision", [package_id, other.package_id, strength])
	_emit_event(&"package_collision", [other.package_id, package_id, strength])


func _hit_player(player: Player) -> void:
	if is_held or freeze or not _is_run_active():
		return
	var speed: float = linear_velocity.length()
	if speed < PLAYER_HIT_MIN_SPEED:
		return
	var push: Vector3 = linear_velocity.normalized() * minf(speed * PLAYER_HIT_PUSH_SCALE, 5.0)
	player.rpc(&"receive_package_hit", push)
	apply_impact(speed * 0.35)


## Announces this package to the run. Called when the delivery starts, not at _ready: packages load before the
## level resets the run, and only cargo actually aboard should count toward the score.
func report_to_run() -> void:
	_emit_event(&"cargo_registered", [package_id, trap_definition.name_key()])
	_emit_event(&"package_integrity_changed", [package_id, integrity, integrity_max])
	_emit_event(&"package_state_changed", [package_id, trap_state])
	_emit_event(&"package_hint_changed", [package_id, hint_text()])
	_hint_relay_time = 0.0


## cause: a translation key (or plain text), shown to each peer in its language.
func mark_lost(cause: String) -> void:
	if _lost:
		return
	var before_integrity: float = integrity
	var before_state: int = trap_state
	_lost = true
	care.phase = &"lost"
	care.message = LocText.make(cause)
	_publish_care()
	_report_change(before_integrity, before_state, tr(cause))


func content_definition() -> Resource:
	if content == null and trap_definition != null:
		content = trap_definition.pick_content(package_id)
	return content


## Any peer asks; only the host decides. call_local, so the host's own
## player goes through the same checks (rpc_id(1, ...) resolves locally).
@rpc("any_peer", "call_local", "reliable")
func request_set_open(open: bool) -> void:
	if not is_multiplayer_authority() or not RpcGuard.allow_request(self):
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and not _peer_within_reach(sender_id):
		return
	set_open(open, sender_id if sender_id != 0 else multiplayer.get_unique_id())


## Host-only. A box whose contents already fell out stays open.
func set_open(open: bool, opener_peer_id: int = 0) -> void:
	if contents_spilled or open == is_open:
		return
	if open:
		last_opener_peer_id = opener_peer_id
	is_open = open
	_emit_event(&"package_lid_changed", [package_id, open])


## Host-only: the open box went over (or took a hit) and what was inside is
## now on the floor. Presentation throws the actual pieces (every peer does
## its own, like the torn-off shipping label); the package itself is a loss.
func spill_contents(velocity: Vector3 = Vector3.ZERO) -> void:
	if contents_spilled:
		return
	contents_spilled = true
	_emit_event(&"package_contents_spilled", [package_id, velocity, trap_state])
	care.begin_crisis(_trap_kind(), true)
	_spawn_salvage()
	_publish_care()
	_emit_event(&"package_state_changed", [package_id, trap_state])


func _peer_within_reach(peer_id: int) -> bool:
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() == peer_id:
			return _reach_origin(player).distance_to(global_position) <= OPEN_REACH
	return false


## A seated player's body stays where they sat down; their seat is where they are.
static func _reach_origin(player: Node) -> Vector3:
	return (player as Player).reach_origin() if player is Player else (player as Node3D).global_position


## What this box asks for now, as a LocText line: relayed as is, so each
## peer reads it in its own language (N-805).
func hint_text() -> Array:
	if care.phase == &"crisis":
		return LocText.make("HUD_CARE_CRISIS_HINT", [ceili(care.crisis_left), care.missing_parts])
	if care.needs_restore or care.phase == &"lost" or care.substituted:
		return care.message
	return trap_behavior.hint_text() if trap_behavior != null else []


func get_hint() -> String:
	return LocText.render(hint_text())


func _report_change(before_integrity: float, before_state: int, ruin_cause: String) -> void:
	var lost: float = before_integrity - integrity
	if lost > 0.0:
		_emit_event(&"package_damaged", [package_id, lost])
		if not _sharing_parasite_damage and not parasite_partner_id.is_empty() and is_inside_tree():
			for candidate: Node in get_tree().get_nodes_in_group(&"cargo"):
				if candidate is DeliveryPackage and candidate.package_id == parasite_partner_id:
					candidate.apply_parasite_damage(lost * 0.5)
					break
	if not is_equal_approx(before_integrity, integrity):
		_emit_event(&"package_integrity_changed", [package_id, integrity, integrity_max])
	if trap_state != before_state:
		_emit_event(&"package_state_changed", [package_id, trap_state])
		if trap_state == ITrapBehavior.TrapState.RUINED:
			_emit_event(&"package_ruined", [package_id, ruin_cause])


## Damage is applied to the real trap state, so it survives event cleanup.
func apply_parasite_damage(amount: float) -> void:
	apply_external_damage(amount, "HUD_PACKAGE_PARASITE_DAMAGE")


## Host-only. Harm from outside the box's own trap (a dog on it, bees round the
## cake: N-109), reported like any damage; see PackageRescue.apply_external_damage().
func apply_external_damage(amount: float, ruin_cause_key: String) -> void:
	PackageRescue.apply_external_damage(self, amount, ruin_cause_key)


## The primary tender and, when present, one helper call this every physics frame. Only the host combines
## their samples and advances trap behavior. Same unreliable-ordered reasoning as the van's driver input -- a
## dropped sample is superseded a frame later.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_tender_input(input: Dictionary) -> void:
	if not is_multiplayer_authority() or not RpcGuard.dict_ok(input):
		return
	# Only whoever sits at this box's seat (0: a genuine local call).
	var sender: int = multiplayer.get_remote_sender_id()
	var from: int = sender if sender != 0 else multiplayer.get_unique_id()
	_accept_tender_input(from, input)


func _accept_tender_input(peer_id: int, input: Dictionary) -> bool:
	if peer_id <= 0 or (peer_id != tender_peer_id and peer_id != assistant_peer_id):
		return false
	_tender_inputs[peer_id] = {"input": input.duplicate(true), "age": 0.0}
	if _has_useful_input(input):
		_last_tender_peer = peer_id
	_refresh_combined_input()
	return true


## Host: the seat's occupant changed (seat_point.gd). Nobody tending means no
## input at all -- not the last sample the previous passenger left behind.
func set_tender(peer_id: int) -> void:
	tender_peer_id = peer_id
	_tender_inputs.clear()
	player_input = {}
	if peer_id == 0 or assistant_peer_id == peer_id:
		set_assistant(0)
	_assist_seconds = 0.0


func set_assistant(peer_id: int) -> bool:
	if peer_id > 0 and (tender_peer_id <= 0 or peer_id == tender_peer_id or (assistant_peer_id > 0
			and assistant_peer_id != peer_id)):
		return false
	var previous: int = assistant_peer_id
	if previous > 0:
		_tender_inputs.erase(previous)
	assistant_peer_id = peer_id
	_assist_seconds = 0.0
	_refresh_combined_input()
	if previous > 0 and previous != peer_id and is_inside_tree():
		var previous_player: Node = _player_for_peer(previous)
		if previous_player != null and previous_player.has_method(&"stop_assisting"):
			previous_player.rpc_id(previous, &"stop_assisting", get_path())
	return true


func can_assist(peer_id: int) -> bool:
	return peer_id > 0 and peer_id != tender_peer_id and tender_peer_id > 0 \
			and (assistant_peer_id == 0 or assistant_peer_id == peer_id) \
			and assist_available()


func assist_available() -> bool:
	return tender_peer_id > 0 and run_state() == ITrapBehavior.TrapState.AT_RISK


func run_state() -> int:
	var run: Node = PackageAutoloads.run_manager(self)
	if run != null:
		var run_cargo: Dictionary = run.get(&"cargo")
		if run_cargo.has(package_id):
			return int((run_cargo[package_id] as Dictionary).get("state", trap_state))
	return trap_state


func assist_prompt() -> String:
	var crew: Node = PackageAutoloads.crew(self)
	var color: String = String(crew.call(&"player_color_name", tender_peer_id)) if crew != null \
		else tr("HUD_YOUR_TEAMMATE")
	return tr("HUD_PROMPT_HELP_PACKAGE") % color


@rpc("any_peer", "call_local", "reliable")
func request_assist() -> void:
	if not is_multiplayer_authority() or not RpcGuard.allow_request(self):
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender if sender != 0 else multiplayer.get_unique_id()
	if not can_assist(peer_id) or not _peer_within_assist_reach(peer_id):
		return
	if not set_assistant(peer_id):
		return
	var player: Node = _player_for_peer(peer_id)
	if player != null and player.has_method(&"assist_package"):
		player.rpc_id(peer_id, &"assist_package", get_path())


@rpc("any_peer", "call_local", "reliable")
func request_stop_assist() -> void:
	if not is_multiplayer_authority() or not RpcGuard.allow_request(self):
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender if sender != 0 else multiplayer.get_unique_id()
	if peer_id == assistant_peer_id:
		set_assistant(0)


func _age_tender_inputs(delta: float) -> void:
	for raw_peer: Variant in _tender_inputs.keys():
		var sample: Dictionary = _tender_inputs[raw_peer]
		sample["age"] = float(sample.get("age", 0.0)) + delta
		if float(sample["age"]) > TENDER_INPUT_TIMEOUT:
			_tender_inputs.erase(raw_peer)
		else:
			_tender_inputs[raw_peer] = sample
	_refresh_combined_input()


func _refresh_combined_input() -> void:
	PackageRescue.refresh_combined_input(self)


func _has_fresh_input(peer_id: int) -> bool:
	return _tender_inputs.has(peer_id) and float((_tender_inputs[peer_id] as Dictionary).get("age",
			INF)) <= TENDER_INPUT_TIMEOUT


func _peer_within_assist_reach(peer_id: int) -> bool:
	var player: Node = _player_for_peer(peer_id)
	return player != null and _reach_origin(player).distance_to(global_position) <= ASSIST_REACH


func _player_for_peer(peer_id: int) -> Node:
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() == peer_id:
			return player
	return null


## Whoever is carrying this package (on foot, not yet mounted) calls this every physics frame instead of
## setting global_transform directly -- the package is host-authoritative, so only the host's copy moving is
## real; everyone else, carrier included, sees it through the MultiplayerSynchronizer.
##
## `in_vehicle`: the pose is in the truck's space (the carrier is in the bay),
## and goes on the host's own truck -- each peer's copy of the truck is a little behind the host's, and a
## world pose put the box a metre behind the hands at speed.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_carry_transform(carry_transform: Transform3D, in_vehicle: bool = false) -> void:
	if not is_multiplayer_authority() or not RpcGuard.finite_transform(carry_transform):
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and (not is_instance_valid(carrier) or sender != carrier.get_multiplayer_authority()):
		return
	if not is_held:
		return
	var vehicle: Node3D = _find_vehicle()
	_carry_in_vehicle = in_vehicle and vehicle != null
	_carry_pose = carry_transform
	global_transform = vehicle.global_transform * carry_transform if _carry_in_vehicle else carry_transform


func set_held(held: bool) -> void:
	is_held = held
	freeze = held
	# Disabled while carried: a held package following the hold point every
	# frame shouldn't shove the player or clip weirdly through the world.
	collision_layer = 0 if held else 4
	collision_mask = 0 if held else LOOSE_MASK
	# The velocity sampled before a pickup has nothing to do with the first
	# physics step after a drop; comparing the two read as a hard impact.
	_has_previous_velocity = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Host-only: pickup points call this instead of set_held(true) directly, so the package knows who has it --
## needed to validate drop requests and to clear that player's hands on every peer when the box leaves them.
func take_by(player: Node) -> void:
	var peer_id: int = int(player.get_multiplayer_authority())
	var vehicle: Node3D = _find_vehicle()
	if _is_run_active() and not is_held and not is_loaded \
			and (vehicle == null or not bool(vehicle.call(&"carries", global_position))):
		_rescue_pending = true
	lap_mount_path = NodePath()
	if is_loaded:
		release_mount()
	set_held(true)
	carrier = player
	_last_holder_peer = peer_id
	player.rpc(&"pick_up", get_path())


## Riding with the crew: on a rack, or on the lap of whoever sits tending it
## (seat_point.gd). Built from replicated state so every peer agrees; the
## carrier check only narrows it on the host, where it is known.
func is_aboard() -> bool:
	if is_loaded:
		return true
	if not is_held or tender_peer_id <= 0:
		return false
	return carrier == null or int(carrier.get_multiplayer_authority()) == tender_peer_id


## Hand-to-hand transfer. The host checks both the caller's ownership and
## physical distance, so a client cannot pass cargo across the map.
@rpc("any_peer", "call_local", "reliable")
func request_transfer(recipient_path: NodePath) -> void:
	if not is_multiplayer_authority() or not is_held or carrier == null or not RpcGuard.allow_request(self):
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and int(carrier.get_multiplayer_authority()) != sender_id:
		return
	var recipient: Player = get_node_or_null(recipient_path) as Player if RpcGuard.path_ok(recipient_path) else null
	if recipient == null or recipient == carrier or recipient.carried_package != null:
		return
	if _reach_origin(recipient).distance_to(_reach_origin(carrier)) > TRANSFER_REACH:
		return
	var giver_peer_id: int = _last_holder_peer
	take_by(recipient)
	if _is_run_active():
		_award_milestone(giver_peer_id, &"handover")


## A carrier can always put a box back on the floor. Unlike a mount this
## keeps it loose and physical, so a mistaken pickup never traps the player.
## `in_vehicle` as in submit_carry_transform(): set down in the truck, it's
## placed on the host's truck and starts out moving with it. Critical (RpcGuard): a lost one leaves hands full.
@rpc("any_peer", "call_local", "reliable")
func request_drop(drop_transform: Transform3D, in_vehicle: bool = false) -> void:
	if not is_multiplayer_authority() or not is_held or not RpcGuard.finite_transform(drop_transform):
		return
	if not RpcGuard.allow_critical_request(self):
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and carrier != null and int(carrier.get_multiplayer_authority()) != sender_id:
		return
	_release_carrier()
	var vehicle: Node3D = _find_vehicle()
	global_transform = vehicle.global_transform * drop_transform if in_vehicle and vehicle != null else drop_transform
	reset_physics_interpolation()
	set_held(false)
	_ride_along_if_aboard()


## Let go of inside the moving truck (dropped, or put back on the rack
## mid-run): start with the truck's own velocity, or the box behaves as if
## dropped from a standstill and slams into the rear wall.
func _ride_along_if_aboard() -> void:
	if freeze:
		return
	var vehicle: Node3D = _find_vehicle()
	if vehicle != null and bool(vehicle.call(&"carries", global_position)) and vehicle.has_method(&"point_velocity"):
		linear_velocity = vehicle.call(&"point_velocity", global_position)


## Host: the seated passenger tending this box moves it between their lap
## and the rack it came from. The lap cushions hits but ties up the hands;
## the rack frees them for tools but needs a strap (package_care.gd).
@rpc("any_peer", "call_local", "reliable")
func request_lap_toggle() -> void:
	if RpcGuard.allow_request(self):
		PackageRescue.request_lap_toggle(self)


## Host: someone dropped out (peer_removed). If they were looking after this box, its
## rescue window is held so the crew can reach it -- leaving never loses a
## box on the spot (docs/jugabilidad-paquetes-rescate.md, "Caída de un jugador").
func peer_left(peer_id: int) -> void:
	PackageRescue.peer_left(self, peer_id)


## For when the carrier goes away (disconnect) rather than letting go: the
## box must not stay frozen mid-air with collisions off forever.
func drop_loose(drop_transform: Transform3D) -> void:
	if not is_held:
		return
	carrier = null
	global_transform = drop_transform
	reset_physics_interpolation()
	set_held(false)


## `mount` gives the transform to snap to (the marker); `mount_point` is the
## Interactable that actually tracks occupancy (its InteractionArea child --
## see package_mount_point.gd's `occupied_by`). They're usually different
## nodes, so release_mount() needs the latter, not the former.
func place_at(mount: Node3D, mount_point: Node = null) -> void:
	_release_carrier()
	global_transform = mount.global_transform
	# Snapped onto the shelf: drawn there at once, not slid in from the hands.
	reset_physics_interpolation()
	set_held(false)
	is_loaded = true
	current_mount_path = (mount_point if mount_point != null else mount).get_path()
	# Frozen while loading, until level_base.gd starts the run. A box put back
	# mid-run has to ride physically like the rest, not stay glued to the shelf.
	freeze = not _is_run_active()
	_ride_along_if_aboard()
	_emit_event(&"package_placed", [package_id])
	if _rescue_pending:
		_rescue_pending = false
		_award_milestone(_last_holder_peer, &"rescued")


## A resident took the box at the door. Its carrier's hands have to empty on
## every peer before the node goes away, or they keep "holding" a freed box.
##
## With `hand_over_at` (the resident at the door) it doesn't just vanish (tareas de Slatex #15): it floats
## from the hands to the doorway and the resident takes it in, then it's gone. Already out of play from the
## first frame -- no collisions, no longer cargo -- so nothing can grab it back.
const HAND_OVER_SECONDS: float = 0.45
const TAKE_IN_SECONDS: float = 0.3


func consume(hand_over_at: Variant = null) -> void:
	_release_carrier()
	release_mount()
	# It's a scene node, not a spawned one: freeing it here never reached the
	# clients, where it stayed at the door, full size and still "cargo".
	if is_inside_tree():
		var run: Node = PackageAutoloads.run_manager(self)
		if run != null:
			(run.get(&"consumed_packages") as Array).append(String(get_path()))
		var network := PackageAutoloads.network(self)
		if network != null and network.is_online() and network.is_host():
			_remote_consume.rpc(hand_over_at)
	_play_consume(hand_over_at)


@rpc("authority", "call_remote", "reliable")
func _remote_consume(hand_over_at: Variant) -> void:
	_play_consume(hand_over_at)


func _play_consume(hand_over_at: Variant) -> void:
	_consumed = true
	if hand_over_at == null or not is_inside_tree():
		remove_from_group(&"cargo")
		call_deferred(&"queue_free")
		return
	remove_from_group(&"cargo")
	set_deferred(&"freeze", true)
	collision_layer = 0
	collision_mask = 0
	var tween := create_tween()
	tween.tween_property(self, ^"global_position", hand_over_at as Vector3, HAND_OVER_SECONDS) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, ^"scale", Vector3.ONE * 0.05, TAKE_IN_SECONDS) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


## Trap types reshape the collider at runtime (package_feedback.gd), so this
## reads the live shape instead of assuming one box size.
func get_half_extents() -> Vector3:
	var collider: CollisionShape3D = get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collider != null and collider.shape is BoxShape3D:
		return (collider.shape as BoxShape3D).size * 0.5
	return Vector3.ONE * 0.325


func _release_carrier() -> void:
	lap_mount_path = NodePath()
	if carrier != null and is_instance_valid(carrier) and carrier.is_inside_tree():
		carrier.rpc(&"drop_carried")
	carrier = null


## Frees the shelf slot this package occupies, if any. Without this the mount
## stays marked occupied forever and nothing can ever be placed there again --
## including this same box on the way back (docs/colaboracion-equipo.md).
func release_mount() -> void:
	if current_mount != null and is_instance_valid(current_mount):
		current_mount.set(&"occupied_by", null)
	current_mount = null
	current_mount_path = NodePath()
	is_loaded = false


func _is_run_active() -> bool:
	var run_manager: Node = PackageAutoloads.run_manager(self)
	return run_manager == null or bool(run_manager.get("is_running"))


func _award_pending_trap_milestones() -> void:
	if trap_behavior == null:
		return
	for milestone: StringName in trap_behavior.take_milestones():
		_award_milestone(_last_tender_peer, milestone)


func _award_milestone(peer_id: int, milestone: StringName) -> bool:
	if peer_id <= 0 or milestone.is_empty() or not is_inside_tree():
		return false
	var progression: Node = PackageAutoloads.crew(self)
	if progression == null or not progression.has_method(&"award_milestone"):
		return false
	var occurrence: int = int(_milestone_counts.get(milestone, 0)) + 1
	if not bool(progression.call(&"award_milestone", peer_id, package_id, milestone, occurrence)):
		return false
	_milestone_counts[milestone] = occurrence
	return true


func _registered_for_run() -> bool:
	var run: Node = PackageAutoloads.run_manager(self)
	return run != null and (run.get(&"cargo") as Dictionary).has(package_id)


func _trap_kind() -> StringName:
	return trap_definition.id if trap_definition != null else &"fragile"


func _simulate_cargo(delta: float) -> void:
	PackageRescue.simulate_cargo(self, delta)


func _check_recovery() -> void:
	PackageRescue.check_recovery(self)


func _complete_care_tool(tool: StringName) -> void:
	PackageRescue.complete_care_tool(self, tool)


func _publish_care() -> void:
	PackageRescue.publish_care(self)


func _spawn_salvage() -> void:
	PackageRescue.spawn_salvage(self)


func collect_salvage(index: int, player: Node, point: Vector3) -> void:
	PackageRescue.collect_salvage(self, index, player, point)


## Client sends intent only. Ownership/reach, action duration, direction, speed,
## inventory and the final result are all checked by the host.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_care_input(input: Dictionary) -> void:
	if RpcGuard.dict_ok(input):
		PackageRescue.submit_care_input(self, input)


func delivery_assessment() -> Dictionary:
	return PackageRescue.delivery_assessment(self)


static func _has_useful_input(input: Dictionary) -> bool:
	for value: Variant in input.values():
		if value is bool and bool(value):
			return true
		if (value is StringName or value is String) and not String(value).is_empty():
			return true
	return false


func _emit_event(event_name: StringName, arguments: Array) -> void:
	if not is_inside_tree():
		return
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(event_name):
		bus.call(&"relay", event_name, arguments)
