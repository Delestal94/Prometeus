class_name DeliveryPackage
extends RigidBody3D
## Physical entity and trap integration. Presentation subscribes independently.

@export var package_id: StringName = &"fragile_01"
@export var trap_definition: Resource = preload("res://data/traps/fragile.tres")
@export_range(0.0, 5.0, 0.05) var spawn_grace_time: float = 1.25
@export_range(0.0, 2.0, 0.05) var impact_cooldown: float = 0.30

var trap_behavior: Resource
var integrity: float:
	get:
		return float(trap_behavior.get("integrity")) if trap_behavior != null else 100.0
var integrity_max: float:
	get:
		return float(trap_behavior.get("integrity_max")) if trap_behavior != null else 100.0
var trap_state: int:
	get:
		return int(trap_behavior.call("get_state")) if trap_behavior != null else 0

var _previous_velocity: Vector3 = Vector3.ZERO
var _has_previous_velocity: bool = false
var _age: float = 0.0
var _impact_cooldown_remaining: float = 0.0


func _ready() -> void:
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
	_emit_event(&"package_integrity_changed", [package_id, integrity, integrity_max])
	_emit_event(&"package_state_changed", [package_id, trap_state])


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
		trap_behavior.call("on_physics_process", self, state.step, {
			"linear_velocity": current_velocity,
			"angular_velocity": state.angular_velocity,
		})


func apply_impact(delta_velocity: float) -> void:
	if trap_behavior == null or not _is_run_active():
		return
	var previous_state: int = trap_state
	var damage: float = float(trap_behavior.call("on_impact", maxf(delta_velocity, 0.0)))
	if damage <= 0.0:
		return
	_emit_event(&"package_damaged", [package_id, damage])
	_emit_event(&"package_integrity_changed", [package_id, integrity, integrity_max])
	if trap_state != previous_state:
		_emit_event(&"package_state_changed", [package_id, trap_state])
		if trap_state == 2:
			_emit_event(&"package_ruined", [package_id, "El paquete sufrió demasiados golpes."])


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
		bus.callv("emit_signal", [event_name] + arguments)
