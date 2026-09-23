class_name LiquidTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## A leaky package is not Balance 2.0: small tilts create a manageable
## puddle, impacts make it surge, and a passenger can mop it down before the
## leak becomes a full loss.  Cleaning lowers current spill, never restores
## integrity already lost.

var spill_amount: float = 0.0
var tilt_degrees: float = 0.0
var _safe_angle: float = 10.0
var _danger_angle: float = 24.0
var _leak_per_second: float = 7.0
var _surge_per_second: float = 24.0
var _impact_threshold: float = 4.0
var _impact_spill: float = 18.0
var _mop_rate: float = 22.0
var _integrity_loss_per_spill: float = 0.23


func on_setup(_package: Node, config: Dictionary) -> void:
	super.on_setup(_package, config)
	_safe_angle = float(config.get("safe_angle", 10.0))
	_danger_angle = float(config.get("danger_angle", 24.0))
	_leak_per_second = float(config.get("leak_per_second", 7.0))
	_surge_per_second = float(config.get("surge_per_second", 24.0))
	_impact_threshold = float(config.get("impact_threshold", 4.0))
	_impact_spill = float(config.get("impact_spill", 18.0))
	_mop_rate = float(config.get("mop_rate", 22.0))
	_integrity_loss_per_spill = float(config.get("integrity_loss_per_spill", 0.23))
	spill_amount = 0.0


func on_physics_process(package: Node, delta: float, context: Dictionary) -> void:
	if get_state() == TrapState.RUINED:
		return
	tilt_degrees = _measure_tilt(package)
	var tilt_ratio: float = clampf((tilt_degrees - _safe_angle) / maxf(_danger_angle - _safe_angle, 0.01), 0.0, 1.0)
	if tilt_ratio > 0.0:
		var rate: float = lerpf(_leak_per_second, _surge_per_second, tilt_ratio)
		spill_amount = minf(integrity_max, spill_amount + rate * delta)
	var input: Dictionary = context.get("input", {}) as Dictionary
	if bool(input.get("calm", false)):
		spill_amount = maxf(0.0, spill_amount - _mop_rate * delta)
	# The wetness is the danger buffer.  Once it gets serious, it converts
	# into permanent package damage at a pace a teammate can still fight.
	if spill_amount > integrity_max * 0.14:
		damage((spill_amount / integrity_max) * _integrity_loss_per_spill * 100.0 * delta)


func on_impact(delta_velocity: float) -> float:
	if delta_velocity >= _impact_threshold:
		spill_amount = minf(integrity_max, spill_amount + _impact_spill * (delta_velocity / _impact_threshold))
	return 0.0


func get_state() -> int:
	if integrity <= 0.0 or spill_amount >= integrity_max:
		return TrapState.RUINED
	if spill_amount >= integrity_max * 0.30 or tilt_degrees > _safe_angle:
		return TrapState.AT_RISK
	return TrapState.OK


func get_hint() -> String:
	if get_state() == TrapState.RUINED:
		return "Se derramó por completo."
	if spill_amount >= integrity_max * 0.30:
		return "¡Charco creciendo! Mantené para secar."
	if tilt_degrees > _safe_angle:
		return "Inclinado %.0f° · mantené para secar." % tilt_degrees
	return "Líquido estable. Secá cualquier derrame."


func _measure_tilt(package: Node) -> float:
	if package == null:
		return tilt_degrees
	var up: Vector3 = (package.get(&"global_basis") as Basis).y
	return rad_to_deg(up.angle_to(Vector3.UP))
