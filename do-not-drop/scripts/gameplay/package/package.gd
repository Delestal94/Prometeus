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

var trap_behavior: Resource
var is_held: bool = false
var is_loaded: bool = false
## Written each frame by whoever is tending this package. Plain data, so the
## host can apply a remote client's input the same way once networking lands.
var player_input: Dictionary = {}
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


func _ready() -> void:
	if not is_multiplayer_authority():
		freeze = true
	initialize_trap()


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
	if _has_previous_velocity and _age >= spawn_grace_time and _is_run_active():
		# Gravity during free fall is not an impact. Collision resolution changes
		# velocity suddenly, while this subtraction removes the expected gravity step.
		var collision_delta: Vector3 = current_velocity - _previous_velocity - state.total_gravity * state.step
		if _impact_cooldown_remaining <= 0.0:
			var previous_integrity: float = integrity
			apply_impact(collision_delta.length())
			if integrity < previous_integrity:
				_impact_cooldown_remaining = impact_cooldown
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


func place_at(mount: Node3D) -> void:
	global_transform = mount.global_transform
	set_held(false)
	is_loaded = true
	# Stays frozen until level_base.gd starts the run -- see docs/plan-desarrollo.md.
	freeze = true


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
