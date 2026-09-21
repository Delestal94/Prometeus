class_name NoisyTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## Something alive is in the box. Bumps agitate it; its passenger has to
## keep calming it down. It settles a little on its own, but never fast
## enough to survive a rough stretch unattended.

var agitation: float = 0.0

var _agitation_max: float = 100.0
var _gain_per_shake: float = 25.0
var _shake_threshold: float = 7.0
var _calm_rate: float = 30.0
var _passive_decay: float = 5.0
var _at_risk_at: float = 60.0
var _seconds_at_max: float = 0.0
var _fail_seconds: float = 2.0
var _escaped: bool = false


func on_setup(package: Node, config: Dictionary) -> void:
	super.on_setup(package, config)
	_agitation_max = maxf(float(config.get("agitation_max", 100.0)), 1.0)
	_gain_per_shake = float(config.get("agitation_gain_per_shake", 25.0))
	_shake_threshold = float(config.get("shake_threshold", 7.0))
	_calm_rate = float(config.get("agitation_decay_rate", 30.0))
	_passive_decay = float(config.get("agitation_passive_decay", 5.0))
	_at_risk_at = float(config.get("at_risk_at", 60.0))
	_fail_seconds = float(config.get("fail_seconds_at_max", 2.0))
	agitation = 0.0
	_seconds_at_max = 0.0
	_escaped = false


func on_physics_process(_package: Node, delta: float, context: Dictionary) -> void:
	if _escaped:
		return
	var input: Dictionary = context.get("input", {}) as Dictionary
	var calming: bool = bool(input.get("calm", false))
	if agitation >= _agitation_max and not calming:
		# Once it's fully worked up it does not settle on its own: only a
		# passenger actively calming it can pull it back before it gets loose.
		# Without this it would shed agitation the same frame it peaked and
		# could never actually escape.
		_seconds_at_max += delta
		if _seconds_at_max >= _fail_seconds:
			_escaped = true
		_sync_integrity()
		return
	var decay: float = _calm_rate if calming else _passive_decay
	agitation = clampf(agitation - decay * delta, 0.0, _agitation_max)
	if agitation < _agitation_max:
		_seconds_at_max = 0.0
	_sync_integrity()


func on_impact(delta_velocity: float) -> float:
	if _escaped or delta_velocity < _shake_threshold:
		return 0.0
	var before: float = integrity
	agitation = clampf(agitation + _gain_per_shake, 0.0, _agitation_max)
	_sync_integrity()
	return maxf(before - integrity, 0.0)


func get_state() -> int:
	if _escaped:
		return TrapState.RUINED
	if agitation >= _at_risk_at:
		return TrapState.AT_RISK
	return TrapState.OK


func get_hint() -> String:
	if _escaped:
		return "Se escapó."
	if agitation >= _agitation_max:
		return "¡Se suelta! Mantené para calmarlo."
	if agitation >= _at_risk_at:
		return "Muy inquieto · mantené para calmarlo."
	return "Tranquilo por ahora. Los golpes lo alteran."


func _sync_integrity() -> void:
	# Agitation is the failure axis, reported on the shared scale so the HUD
	# and the score treat it like any other trap.
	integrity = integrity_max * (1.0 - agitation / _agitation_max)
