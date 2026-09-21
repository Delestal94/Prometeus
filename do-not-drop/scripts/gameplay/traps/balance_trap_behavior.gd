class_name BalanceTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## Must stay upright. Tilting past the safe angle bleeds integrity, and
## staying past the danger angle spills it outright. Its passenger can hold
## "steady" to push it back level -- enough to fight a normal corner, not
## enough to save an emergency brake.

var tilt_degrees: float = 0.0

var _angle_ok_max: float = 15.0
var _angle_at_risk_max: float = 30.0
var _fail_seconds: float = 1.5
var _damage_per_second: float = 20.0
var _correction_degrees_per_second: float = 20.0
var _seconds_past_danger: float = 0.0
var _is_steadying: bool = false


func on_setup(package: Node, config: Dictionary) -> void:
	super.on_setup(package, config)
	_angle_ok_max = float(config.get("angle_ok_max", 15.0))
	_angle_at_risk_max = float(config.get("angle_at_risk_max", 30.0))
	_fail_seconds = float(config.get("angle_fail_seconds", 1.5))
	_damage_per_second = float(config.get("damage_per_second_at_risk", 20.0))
	_correction_degrees_per_second = float(config.get("correction_strength", 20.0))
	tilt_degrees = 0.0
	_seconds_past_danger = 0.0


func on_physics_process(package: Node, delta: float, context: Dictionary) -> void:
	if get_state() == TrapState.RUINED:
		return
	var input: Dictionary = context.get("input", {}) as Dictionary
	_is_steadying = bool(input.get("steady", false))
	tilt_degrees = _measure_tilt(package)
	if _is_steadying:
		_apply_correction(package, delta)
	if tilt_degrees > _angle_at_risk_max:
		_seconds_past_danger += delta
	else:
		_seconds_past_danger = 0.0
	if _seconds_past_danger >= _fail_seconds:
		damage(integrity)
		return
	if tilt_degrees > _angle_ok_max:
		damage(_damage_per_second * delta)


func get_state() -> int:
	if integrity <= 0.0:
		return TrapState.RUINED
	if tilt_degrees > _angle_ok_max or integrity <= integrity_max * 0.4:
		return TrapState.AT_RISK
	return TrapState.OK


func get_hint() -> String:
	if get_state() == TrapState.RUINED:
		return "Se volcó."
	if tilt_degrees > _angle_at_risk_max:
		return "¡Se está volcando! Mantené para enderezar."
	if tilt_degrees > _angle_ok_max:
		return "Inclinado %.0f° · mantené para enderezar." % tilt_degrees
	return "Estable. Mantené para enderezar en las curvas."


func _measure_tilt(package: Node) -> float:
	if package == null:
		return tilt_degrees
	var up: Vector3 = (package.get(&"global_basis") as Basis).y
	return rad_to_deg(up.angle_to(Vector3.UP))


func _apply_correction(package: Node, delta: float) -> void:
	if package == null or tilt_degrees <= 0.01:
		return
	var basis: Basis = package.get(&"global_basis") as Basis
	var axis: Vector3 = basis.y.cross(Vector3.UP)
	if axis.length_squared() < 0.000001:
		return
	# Rotate the box back toward upright, capped so it can fight a corner
	# but never instantly undo a real slam.
	var step: float = minf(deg_to_rad(_correction_degrees_per_second * delta), deg_to_rad(tilt_degrees))
	var corrected: Basis = Basis(axis.normalized(), step) * basis
	var transform: Transform3D = package.get(&"global_transform") as Transform3D
	package.set(&"global_transform", Transform3D(corrected.orthonormalized(), transform.origin))
	tilt_degrees = _measure_tilt(package)
