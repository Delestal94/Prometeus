class_name DeliveryPackage
extends RigidBody3D
## Physical entity and trap integration. Presentation subscribes independently.
##
## Host-authoritative, like the van: authority defaults to the host since
## this is a static, non-spawned node. Non-host peers freeze it and let
## their MultiplayerSynchronizer puppet the transform instead.

@export var package_id: StringName = &"fragile_01"
@export var trap_definition: Resource = preload("res://data/traps/fragile.tres")
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
const PACKAGE_COLLISION_MIN_SPEED: float = 2.2
const PACKAGE_COLLISION_DAMAGE_SCALE: float = 0.62
const PACKAGE_COLLISION_COOLDOWN: float = 0.16
const PLAYER_HIT_MIN_SPEED: float = 4.0
const PLAYER_HIT_PUSH_SCALE: float = 0.38

var trap_behavior: Resource
var is_held: bool = false:
	set(value):
		is_held = value
		collision_layer = 0 if value else 4
		collision_mask = 0 if value else 7
var is_loaded: bool = false
## Set by place_at(), cleared by release_mount(). Lets a pickup free its
## shelf slot with a direct reference instead of scanning every mount in
## the "package_mount" group to find whichever one claims this package.
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
## Lid state, host-authoritative and replicated (see package.tscn). Opening
## lets the crew check what they're carrying; an open box can spill, and
## the resident notices one that shows up open.
var is_open: bool = false
## Replicated too: once the contents are on the floor there's nothing left
## to close the box on.
var contents_spilled: bool = false
## Replicated in place of position/rotation (see package.tscn). Inside the
## truck's cargo bay the box is sent in the truck's own space, and a client
## puts it back on *its* copy of the truck. In world space the two arrived
## from separate synchronizers, out of step: at speed the boxes trailed the
## truck by a good part of a metre, so on clients they bounced about, went
## through the walls and seemed to fall out.
var net_transform: Transform3D = Transform3D.IDENTITY:
	set(value):
		net_transform = value
		_has_net_state = true
var net_in_vehicle: bool = false
var _has_net_state: bool = false
var _vehicle: Node3D = null
## Host: the carrier's latest hold pose, in the truck's space when aboard.
## Re-applied every tick against the host's own truck, so a box carried in
## the moving bay rides with it between the carrier's updates.
var _carry_pose: Transform3D = Transform3D.IDENTITY
var _carry_in_vehicle: bool = false
## Host: the peer whose seat looks after this box (seat_point.gd), the only
## one whose trap input counts, and how long since their last sample.
var tender_peer_id: int = 0
var _tender_input_age: float = 0.0
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
		return float(trap_behavior.get("integrity")) if trap_behavior != null else 100.0
var integrity_max: float:
	get:
		return float(trap_behavior.get("integrity_max")) if trap_behavior != null else 100.0
var trap_state: int:
	get:
		if _lost:
			return ITrapBehavior.TrapState.RUINED
		return int(trap_behavior.call("get_state")) if trap_behavior != null else 0
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


## Synced only to peers whose level is loaded (NetworkManager.is_peer_ready()),
## same as the players. Installed before the synchronizer (a child) enters the
## tree and registers: after a host restart the new level's boxes were synced
## to clients still on the old level, where a box handed over last run was
## gone; that client never resolved it and never saw that box move again.
func _enter_tree() -> void:
	var sync := get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if sync == null or network == null or not network.has_signal(&"peer_level_ready") \
			or network.is_connected(&"peer_level_ready", _on_peer_level_ready):
		return
	sync.add_visibility_filter(func(peer_id: int) -> bool:
		return not multiplayer.is_server() or bool(network.call(&"is_peer_ready", peer_id)))
	network.connect(&"peer_level_ready", _on_peer_level_ready)


func _on_peer_level_ready(peer_id: int) -> void:
	var sync := get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync != null and multiplayer.is_server():
		sync.update_visibility(peer_id)


func _ready() -> void:
	if not is_multiplayer_authority():
		freeze = true
		# Placed by the network every frame (_process), against the truck
		# as it's drawn: interpolating between physics ticks on top of that
		# only made it trail behind.
		physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	initialize_trap()
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
	if not player_input.is_empty():
		_tender_input_age += delta
		if _tender_input_age > TENDER_INPUT_TIMEOUT:
			player_input = {}
	_publish_net_state()


## Client: put the box where the host says, on this peer's truck if it rides.
func _process(_delta: float) -> void:
	if is_multiplayer_authority() or not _has_net_state or _consumed:
		return
	var vehicle: Node3D = _find_vehicle()
	if net_in_vehicle and vehicle != null:
		# A client's truck is frozen, so not interpolated: its interpolated
		# transform is then last frame's cached one, not where the network
		# just put it, and the box would trail the truck by a frame.
		var vehicle_pose: Transform3D = vehicle.get_global_transform_interpolated() if vehicle.is_physics_interpolated_and_enabled() else vehicle.global_transform
		global_transform = vehicle_pose * net_transform
	else:
		global_transform = net_transform


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
	trap_behavior = trap_definition.call("create_behavior")
	if trap_behavior == null:
		return
	var config: Dictionary = trap_definition.get("params")
	trap_behavior.call("on_setup", self, config.duplicate(true))
	_age = 0.0
	_impact_cooldown_remaining = 0.0
	_has_previous_velocity = false
	_lost = false


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
	if trap_behavior != null and _is_run_active():
		var before_integrity: float = integrity
		var before_state: int = trap_state
		trap_behavior.call("on_physics_process", self, state.step, {
			"linear_velocity": current_velocity,
			"angular_velocity": state.angular_velocity,
			"input": player_input,
		})
		# Traps that bleed over time (tilt, weight, agitation) change integrity
		# here rather than on impact, so the same events still have to fire.
		_report_change(before_integrity, before_state, "El paquete no aguantó el viaje.")
		_hint_relay_time += state.step
		if _hint_relay_time >= HINT_RELAY_INTERVAL:
			_hint_relay_time = 0.0
			# get_hint() reads trap_behavior directly, which only ever advances
			# here, on the host -- a client's own local copy is frozen and never
			# runs this, so its hint text would otherwise sit stale forever
			# (a countdown that never counts down, for instance).
			_emit_event(&"package_hint_changed", [package_id, get_hint()])


func apply_impact(delta_velocity: float) -> void:
	if trap_behavior == null or not _is_run_active():
		return
	var before_integrity: float = integrity
	var before_state: int = trap_state
	trap_behavior.call("on_impact", maxf(delta_velocity, 0.0) * impact_absorption)
	_report_change(before_integrity, before_state, "El paquete sufrió demasiados golpes.")


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


## Announces this package to the run. Called when the delivery starts, not at
## _ready: packages load before the level resets the run, and only cargo
## actually aboard should count toward the score.
func report_to_run() -> void:
	_emit_event(&"cargo_registered", [package_id, String(trap_definition.get("display_name"))])
	_emit_event(&"package_integrity_changed", [package_id, integrity, integrity_max])
	_emit_event(&"package_state_changed", [package_id, trap_state])
	_emit_event(&"package_hint_changed", [package_id, get_hint()])
	_hint_relay_time = 0.0


func mark_lost(cause: String) -> void:
	if _lost:
		return
	var before_integrity: float = integrity
	var before_state: int = trap_state
	_lost = true
	_report_change(before_integrity, before_state, cause)


func content_definition() -> Resource:
	if content == null and trap_definition != null and trap_definition.has_method(&"pick_content"):
		content = trap_definition.call(&"pick_content", package_id)
	return content


## Any peer asks; only the host decides. call_local, so the host's own
## player goes through the same checks (rpc_id(1, ...) resolves locally).
@rpc("any_peer", "call_local", "reliable")
func request_set_open(open: bool) -> void:
	if not is_multiplayer_authority():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and not _peer_within_reach(sender_id):
		return
	set_open(open)


## Host-only. A box whose contents already fell out stays open.
func set_open(open: bool) -> void:
	if contents_spilled or open == is_open:
		return
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
	mark_lost("Se le cayó el contenido.")


func _peer_within_reach(peer_id: int) -> bool:
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() == peer_id:
			return _reach_origin(player).distance_to(global_position) <= OPEN_REACH
	return false


## A seated player's body stays where they sat down; their seat is where they are.
static func _reach_origin(player: Node) -> Vector3:
	return player.call(&"reach_origin") if player.has_method(&"reach_origin") else (player as Node3D).global_position


func get_hint() -> String:
	return String(trap_behavior.call("get_hint")) if trap_behavior != null else ""


func _report_change(before_integrity: float, before_state: int, ruin_cause: String) -> void:
	var lost: float = before_integrity - integrity
	if lost > 0.0:
		_emit_event(&"package_damaged", [package_id, lost])
	if not is_equal_approx(before_integrity, integrity):
		_emit_event(&"package_integrity_changed", [package_id, integrity, integrity_max])
	if trap_state != before_state:
		_emit_event(&"package_state_changed", [package_id, trap_state])
		if trap_state == ITrapBehavior.TrapState.RUINED:
			_emit_event(&"package_ruined", [package_id, ruin_cause])


## Whoever is tending this package calls this on their own client every
## physics frame; only takes effect on the host, which is the only place
## trap_behavior should actually read it. Same unreliable-ordered reasoning
## as the van's driver input -- a dropped sample is superseded a frame later.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_tender_input(input: Dictionary) -> void:
	if not is_multiplayer_authority():
		return
	# Only whoever sits at this box's seat (0: a genuine local call).
	var sender: int = multiplayer.get_remote_sender_id()
	var from: int = sender if sender != 0 else multiplayer.get_unique_id()
	if tender_peer_id == 0 or from != tender_peer_id:
		return
	player_input = input
	_tender_input_age = 0.0


## Host: the seat's occupant changed (seat_point.gd). Nobody tending means no
## input at all -- not the last sample the previous passenger left behind.
func set_tender(peer_id: int) -> void:
	tender_peer_id = peer_id
	player_input = {}
	_tender_input_age = 0.0


## Whoever is carrying this package (on foot, not yet mounted) calls this
## every physics frame instead of setting global_transform directly -- the
## package is host-authoritative, so only the host's copy moving is real;
## everyone else, carrier included, sees it through the MultiplayerSynchronizer.
##
## `in_vehicle`: the pose is in the truck's space (the carrier is in the bay),
## and goes on the host's own truck -- each peer's copy of the truck is a
## little behind the host's, and a world pose put the box a metre behind the
## hands at speed.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_carry_transform(carry_transform: Transform3D, in_vehicle: bool = false) -> void:
	if not is_multiplayer_authority():
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
	collision_mask = 0 if held else 7
	# The velocity sampled before a pickup has nothing to do with the first
	# physics step after a drop; comparing the two read as a hard impact.
	_has_previous_velocity = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Host-only: pickup points call this instead of set_held(true) directly, so
## the package knows who has it -- needed to validate drop requests and to
## clear that player's hands on every peer when the box leaves them.
func take_by(player: Node) -> void:
	if is_loaded:
		release_mount()
	set_held(true)
	carrier = player
	player.rpc(&"pick_up", get_path())


## Hand-to-hand transfer. The host checks both the caller's ownership and
## physical distance, so a client cannot pass cargo across the map.
@rpc("any_peer", "call_local", "reliable")
func request_transfer(recipient_path: NodePath) -> void:
	if not is_multiplayer_authority() or not is_held or carrier == null:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and int(carrier.get_multiplayer_authority()) != sender_id:
		return
	var recipient := get_node_or_null(recipient_path) as Player
	if recipient == null or recipient == carrier or recipient.carried_package != null:
		return
	if _reach_origin(recipient).distance_to(_reach_origin(carrier)) > TRANSFER_REACH:
		return
	take_by(recipient)


## A carrier can always put a box back on the floor. Unlike a mount this
## keeps it loose and physical, so a mistaken pickup never traps the player.
## `in_vehicle` as in submit_carry_transform(): set down in the truck, it's
## placed on the host's truck and starts out moving with it.
@rpc("any_peer", "call_local", "reliable")
func request_drop(drop_transform: Transform3D, in_vehicle: bool = false) -> void:
	if not is_multiplayer_authority() or not is_held:
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


## A resident took the box at the door. Its carrier's hands have to empty on
## every peer before the node goes away, or they keep "holding" a freed box.
##
## With `hand_over_at` (the resident at the door) it doesn't just vanish
## (tareas de Slatex #15): it floats from the hands to the doorway and the
## resident takes it in, then it's gone. Already out of play from the first
## frame -- no collisions, no longer cargo -- so nothing can grab it back.
const HAND_OVER_SECONDS: float = 0.45
const TAKE_IN_SECONDS: float = 0.3


func consume(hand_over_at: Variant = null) -> void:
	_release_carrier()
	release_mount()
	# It's a scene node, not a spawned one: freeing it here never reached the
	# clients, where it stayed at the door, full size and still "cargo".
	if is_inside_tree():
		var run: Node = get_node_or_null(^"/root/RunManager")
		if run != null:
			(run.get(&"consumed_packages") as Array).append(String(get_path()))
		var network: Node = get_node_or_null(^"/root/NetworkManager")
		if network != null and bool(network.call(&"is_online")) and bool(network.call(&"is_host")):
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
	if not is_inside_tree():
		return true
	var run_manager: Node = get_node_or_null("/root/RunManager")
	return run_manager == null or bool(run_manager.get("is_running"))


func _emit_event(event_name: StringName, arguments: Array) -> void:
	if not is_inside_tree():
		return
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(event_name):
		bus.call(&"relay", event_name, arguments)
