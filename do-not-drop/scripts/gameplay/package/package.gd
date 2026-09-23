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
## How close a player has to be to open or close it.
const OPEN_REACH: float = 3.0
const PACKAGE_COLLISION_MIN_SPEED: float = 2.2
const PACKAGE_COLLISION_DAMAGE_SCALE: float = 0.62
const PACKAGE_COLLISION_COOLDOWN: float = 0.16

var trap_behavior: Resource
var is_held: bool = false
var is_loaded: bool = false
## Set by place_at(), cleared by release_mount(). Lets a pickup free its
## shelf slot with a direct reference instead of scanning every mount in
## the "package_mount" group to find whichever one claims this package.
var current_mount: Node = null
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


func _ready() -> void:
	if not is_multiplayer_authority():
		freeze = true
	initialize_trap()
	body_entered.connect(_on_body_entered)


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
	trap_behavior.call("on_impact", maxf(delta_velocity, 0.0))
	_report_change(before_integrity, before_state, "El paquete sufrió demasiados golpes.")


func _on_body_entered(body: Node) -> void:
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
			return (player as Node3D).global_position.distance_to(global_position) <= OPEN_REACH
	return false


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
	player_input = input


## Whoever is carrying this package (on foot, not yet mounted) calls this
## every physics frame instead of setting global_transform directly -- the
## package is host-authoritative, so only the host's copy moving is real;
## everyone else, carrier included, sees it through the MultiplayerSynchronizer.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_carry_transform(carry_transform: Transform3D) -> void:
	if not is_multiplayer_authority():
		return
	if is_held:
		global_transform = carry_transform


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


## A carrier can always put a box back on the floor. Unlike a mount this
## keeps it loose and physical, so a mistaken pickup never traps the player.
@rpc("any_peer", "call_local", "reliable")
func request_drop(drop_transform: Transform3D) -> void:
	if not is_multiplayer_authority() or not is_held:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and carrier != null and int(carrier.get_multiplayer_authority()) != sender_id:
		return
	_release_carrier()
	global_transform = drop_transform
	set_held(false)


## For when the carrier goes away (disconnect) rather than letting go: the
## box must not stay frozen mid-air with collisions off forever.
func drop_loose(drop_transform: Transform3D) -> void:
	if not is_held:
		return
	carrier = null
	global_transform = drop_transform
	set_held(false)


## `mount` gives the transform to snap to (the marker); `mount_point` is the
## Interactable that actually tracks occupancy (its InteractionArea child --
## see package_mount_point.gd's `occupied_by`). They're usually different
## nodes, so release_mount() needs the latter, not the former.
func place_at(mount: Node3D, mount_point: Node = null) -> void:
	_release_carrier()
	global_transform = mount.global_transform
	set_held(false)
	is_loaded = true
	current_mount = mount_point if mount_point != null else mount
	# Frozen while loading, until level_base.gd starts the run. A box put back
	# mid-run has to ride physically like the rest, not stay glued to the shelf.
	freeze = not _is_run_active()
	_emit_event(&"package_placed", [package_id])


## A resident took the box at the door. Its carrier's hands have to empty on
## every peer before the node goes away, or they keep "holding" a freed box.
func consume() -> void:
	_release_carrier()
	release_mount()
	call_deferred(&"queue_free")


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
