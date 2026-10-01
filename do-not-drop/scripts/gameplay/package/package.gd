class_name DeliveryPackage
extends RigidBody3D
## Physical entity and trap integration. Presentation subscribes independently.
##
## Host-authoritative, like the van: authority defaults to the host since this is a static, non-spawned node.
## Non-host peers freeze it and let their MultiplayerSynchronizer puppet the transform instead.
##
## Split by responsibility (N-225.4), the state stays here: PackageHandling (carry, pass, drop, shelve, hand
## over), PackageTending (the tender, the helper, merit), PackageImpacts (hits), PackageRescue (care, rescue).
## This script keeps the RPCs (each one checks the request and resolves the sender before delegating; the
## helpers check the sender against the carrier) and thin wrappers.

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
const ASSIST_REACH: float = 1.5
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
## Replicated with them: the host's NetSnapshotBuffer.clock_ms() for this pose. A client draws the box from
## a buffer of them, a little in the past and interpolated, not on whichever came last (N-217).
var net_time: int = 0
var _net_buffer := NetSnapshotBuffer.new()
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
		var network: Node = get_node_or_null(^"/root/NetworkManager")
		if network != null and network.has_method(&"pose_net_sim"):
			_net_buffer.configure_sim(network.call(&"pose_net_sim"))
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
	if is_held:
		PackageHandling.hold_on_host(self)
	PackageTending.tick(self, delta)
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
	var vehicle: Node3D = _find_vehicle()
	# A client's truck is frozen, so not interpolated: its interpolated transform is then last frame's cached
	# one, not where the network just put it, and the box would trail the truck by a frame.
	var truck: Transform3D = Transform3D.IDENTITY
	if vehicle != null:
		truck = vehicle.get_global_transform_interpolated() if vehicle.is_physics_interpolated_and_enabled() else vehicle.global_transform
	if predicted:
		global_transform = truck * _predicted_pose if _predicted_in_vehicle and vehicle != null else _predicted_pose
		# Its poses from before the pickup are stale: once let go, the host's first one is drawn at once.
		_net_buffer.clear()
		return
	var now: float = NetSnapshotBuffer.local_now()
	_net_buffer.take(net_time, net_transform, net_in_vehicle and vehicle != null, now)
	global_transform = _net_buffer.sample(now, truck)


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
	net_time = NetSnapshotBuffer.clock_ms()


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
	PackageImpacts.integrate_forces(self, state)


func apply_impact(delta_velocity: float) -> void:
	PackageImpacts.apply_impact(self, delta_velocity)


func _on_body_entered(body: Node) -> void:
	PackageImpacts.on_body_entered(self, body)


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
			return _reach_origin(player).distance_to(global_position) <= OPEN_REACH + _reach_slack(player)
	return false


## A seated player's body stays where they sat down; their seat is where they are.
static func _reach_origin(player: Node) -> Vector3:
	return (player as Player).reach_origin() if player is Player else (player as Node3D).global_position


## Host: how much further a client's request may reach, for how stale its player is here (N-217).
static func _reach_slack(player: Node) -> float:
	return (player as Player).reach_slack() if player is Player else 0.0


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
	PackageImpacts.report_change(self, before_integrity, before_state, ruin_cause)


## Damage is applied to the real trap state, so it survives event cleanup.
func apply_parasite_damage(amount: float) -> void:
	apply_external_damage(amount, "HUD_PACKAGE_PARASITE_DAMAGE")


## Host-only. Harm from outside the box's own trap (a dog on it, bees round the
## cake: N-109), reported like any damage; see PackageRescue.apply_external_damage().
func apply_external_damage(amount: float, ruin_cause_key: String) -> void:
	PackageRescue.apply_external_damage(self, amount, ruin_cause_key)


## The peer behind a request: the remote sender, or this peer on a genuine local call (sender 0).
func _caller_peer() -> int:
	var sender: int = multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()


## The primary tender and, when present, one helper call this every physics frame. Only the host combines
## their samples and advances trap behavior. Same unreliable-ordered reasoning as the van's driver input -- a
## dropped sample is superseded a frame later.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_tender_input(input: Dictionary) -> void:
	if not is_multiplayer_authority() or not RpcGuard.dict_ok(input):
		return
	# Only whoever sits at this box's seat (see PackageTending.accept_input()).
	_accept_tender_input(_caller_peer(), input)


func _accept_tender_input(peer_id: int, input: Dictionary) -> bool:
	return PackageTending.accept_input(self, peer_id, input)


func set_tender(peer_id: int) -> void:
	PackageTending.set_tender(self, peer_id)


func set_assistant(peer_id: int) -> bool:
	return PackageTending.set_assistant(self, peer_id)


func can_assist(peer_id: int) -> bool:
	return PackageTending.can_assist(self, peer_id)


func assist_available() -> bool:
	return PackageTending.assist_available(self)


func run_state() -> int:
	return PackageTending.run_state(self)


func assist_prompt() -> String:
	return PackageTending.assist_prompt(self)


@rpc("any_peer", "call_local", "reliable")
func request_assist() -> void:
	if is_multiplayer_authority() and RpcGuard.allow_request(self):
		PackageTending.assist(self, _caller_peer())


@rpc("any_peer", "call_local", "reliable")
func request_stop_assist() -> void:
	if is_multiplayer_authority() and RpcGuard.allow_request(self):
		PackageTending.stop_assist(self, _caller_peer())


func _refresh_combined_input() -> void:
	PackageRescue.refresh_combined_input(self)


func _has_fresh_input(peer_id: int) -> bool:
	return PackageTending.has_fresh_input(self, peer_id)


func _player_for_peer(peer_id: int) -> Node:
	return PackageTending.player_for_peer(self, peer_id)


## Whoever is carrying this package (on foot, not yet mounted) calls this every physics frame instead of
## setting global_transform directly -- the package is host-authoritative, so only the host's copy moving is
## real; everyone else, carrier included, sees it through the MultiplayerSynchronizer. `in_vehicle`: the pose
## is in the truck's space (see PackageHandling.accept_carry()).
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_carry_transform(carry_transform: Transform3D, in_vehicle: bool = false) -> void:
	if is_multiplayer_authority() and RpcGuard.finite_transform(carry_transform):
		PackageHandling.accept_carry(self, multiplayer.get_remote_sender_id(), carry_transform, in_vehicle)


func set_held(held: bool) -> void:
	PackageHandling.set_held(self, held)


func take_by(player: Node) -> void:
	PackageHandling.take_by(self, player)


func is_aboard() -> bool:
	return PackageHandling.is_aboard(self)


## Hand-to-hand transfer: see PackageHandling.transfer().
@rpc("any_peer", "call_local", "reliable")
func request_transfer(recipient_path: NodePath) -> void:
	if not is_multiplayer_authority() or not is_held or carrier == null or not RpcGuard.allow_request(self):
		return
	PackageHandling.transfer(self, multiplayer.get_remote_sender_id(), recipient_path)


## Put the box back on the floor: see PackageHandling.drop(). Critical (RpcGuard): a lost one leaves hands full.
@rpc("any_peer", "call_local", "reliable")
func request_drop(drop_transform: Transform3D, in_vehicle: bool = false) -> void:
	if not is_multiplayer_authority() or not is_held or not RpcGuard.finite_transform(drop_transform):
		return
	if RpcGuard.allow_critical_request(self):
		PackageHandling.drop(self, multiplayer.get_remote_sender_id(), drop_transform, in_vehicle)


func _ride_along_if_aboard() -> void:
	PackageHandling.ride_along_if_aboard(self)


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


func drop_loose(drop_transform: Transform3D) -> void:
	PackageHandling.drop_loose(self, drop_transform)


func place_at(mount: Node3D, mount_point: Node = null) -> void:
	PackageHandling.place_at(self, mount, mount_point)


func consume(hand_over_at: Variant = null) -> void:
	PackageHandling.consume(self, hand_over_at)


@rpc("authority", "call_remote", "reliable")
func _remote_consume(hand_over_at: Variant) -> void:
	PackageHandling.play_consume(self, hand_over_at)


## Trap types reshape the collider at runtime (package_feedback.gd), so this
## reads the live shape instead of assuming one box size.
func get_half_extents() -> Vector3:
	var collider: CollisionShape3D = get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collider != null and collider.shape is BoxShape3D:
		return (collider.shape as BoxShape3D).size * 0.5
	return Vector3.ONE * 0.325


func _release_carrier() -> void:
	PackageHandling.release_carrier(self)


func release_mount() -> void:
	PackageHandling.release_mount(self)


func _is_run_active() -> bool:
	var run_manager: Node = PackageAutoloads.run_manager(self)
	return run_manager == null or bool(run_manager.get("is_running"))


func _award_pending_trap_milestones() -> void:
	PackageTending.award_pending_trap_milestones(self)


func _award_milestone(peer_id: int, milestone: StringName) -> bool:
	return PackageTending.award_milestone(self, peer_id, milestone)


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
	return PackageTending.has_useful_input(input)


func _emit_event(event_name: StringName, arguments: Array) -> void:
	if not is_inside_tree():
		return
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(event_name):
		bus.call(&"relay", event_name, arguments)
