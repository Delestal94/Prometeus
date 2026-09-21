class_name FragileTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"

var _threshold_light: float = 3.0
var _threshold_heavy: float = 7.0
var _damage_light: float = 10.0
var _damage_heavy: float = 35.0
var _at_risk_at: float = 40.0
var _ruined_at: float = 0.0


func on_setup(package: Node, config: Dictionary) -> void:
	super.on_setup(package, config)
	_threshold_light = float(config.get("impact_threshold_light", 3.0))
	_threshold_heavy = float(config.get("impact_threshold_heavy", 7.0))
	_damage_light = float(config.get("impact_damage_light", 10.0))
	_damage_heavy = float(config.get("impact_damage_heavy", 35.0))
	_at_risk_at = float(config.get("at_risk_at", 40.0))
	_ruined_at = float(config.get("ruined_at", 0.0))


func on_impact(delta_velocity: float) -> float:
	if get_state() == TrapState.RUINED:
		return 0.0
	var damage: float = 0.0
	if delta_velocity >= _threshold_heavy:
		damage = _damage_heavy
	elif delta_velocity >= _threshold_light:
		damage = _damage_light
	var previous_integrity: float = integrity
	integrity = clampf(integrity - damage, 0.0, integrity_max)
	return previous_integrity - integrity


func get_state() -> int:
	if integrity <= _ruined_at:
		return TrapState.RUINED
	if integrity <= _at_risk_at:
		return TrapState.AT_RISK
	return TrapState.OK
