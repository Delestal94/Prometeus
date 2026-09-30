class_name NoisyTrapBehavior
extends ITrapBehavior
## Something alive is in the box. Bumps agitate it; its passenger has to
## keep calming it down. It settles a little on its own, but never fast
## enough to survive a rough stretch unattended. The truck's radio (N-406)
## leans on it a little: calm music settles it faster, loud music stirs it.

var agitation: float = 0.0
## Agitation per running step with the box in the arms.
const RUN_STEP_AGITATION: float = 3.5

var _agitation_max: float = 100.0
var _gain_per_shake: float = 25.0
var _shake_threshold: float = 7.0
var _calm_rate: float = 30.0
var _passive_decay: float = 5.0
var _at_risk_at: float = 60.0
var _seconds_at_max: float = 0.0
var _fail_seconds: float = 2.0
var _escaped: bool = false
## Radio (TruckRadio): extra settling per second under calm music, and under
## loud music the multiplier on each shake's gain and on the passive settling.
## The mode is read every tick from the context; off (the default) and the
## newscast change nothing.
var _radio_calm_extra_decay: float = 0.0
var _radio_loud_gain_mult: float = 1.0
var _radio_loud_passive_mult: float = 1.0
var _radio_mode: StringName = &"off"
## The box, to ask the radio for its mode the moment a shake lands (the tick
## only runs while the truck moves or the box is tended).
var _box: Node


func on_setup(package: Node, config: Dictionary) -> void:
	super.on_setup(package, config)
	_agitation_max = maxf(float(config.get("agitation_max", 100.0)), 1.0)
	_gain_per_shake = float(config.get("agitation_gain_per_shake", 25.0))
	_shake_threshold = float(config.get("shake_threshold", 7.0))
	_calm_rate = float(config.get("agitation_decay_rate", 30.0))
	_passive_decay = float(config.get("agitation_passive_decay", 5.0))
	_at_risk_at = float(config.get("at_risk_at", 60.0))
	_fail_seconds = float(config.get("fail_seconds_at_max", 2.0))
	_radio_calm_extra_decay = float(config.get("radio_calm_extra_decay", 0.0))
	_radio_loud_gain_mult = float(config.get("radio_loud_gain_mult", 1.0))
	_radio_loud_passive_mult = float(config.get("radio_loud_passive_mult", 1.0))
	_radio_mode = &"off"
	_box = package
	agitation = 0.0
	_seconds_at_max = 0.0
	_escaped = false


func on_physics_process(_package: Node, delta: float, context: Dictionary) -> void:
	_radio_mode = StringName(context.get("radio_mode", &"off"))
	if _escaped:
		return
	var before_state: int = get_state()
	var input: Dictionary = context.get("input", {}) as Dictionary
	var calm_strength: float = float(input.get("calm_strength", 1.0 if bool(input.get("calm", false)) else 0.0))
	var calming: bool = calm_strength > 0.0
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
	var decay: float = lerpf(_radio_passive_decay(), _calm_rate, clampf(calm_strength, 0.0, 1.0))
	agitation = clampf(agitation - decay * delta, 0.0, _agitation_max)
	if agitation < _agitation_max:
		_seconds_at_max = 0.0
	_sync_integrity()
	if before_state == TrapState.AT_RISK and get_state() == TrapState.OK:
		_add_milestone(&"calmed")


func on_impact(delta_velocity: float) -> float:
	if _escaped or delta_velocity < _shake_threshold:
		return 0.0
	var before: float = integrity
	_radio_mode = _current_radio_mode()
	agitation = clampf(agitation + _gain_per_shake * (_radio_loud_gain_mult if _radio_mode == &"loud" else 1.0),
			0.0, _agitation_max)
	_sync_integrity()
	return maxf(before - integrity, 0.0)


## The hen does not like being run with: each step riles it up (N-115).
func on_carried_step(strength: float) -> float:
	if _escaped:
		return 0.0
	var before: float = integrity
	agitation = clampf(agitation + RUN_STEP_AGITATION * strength, 0.0, _agitation_max)
	_sync_integrity()
	return maxf(before - integrity, 0.0)


func get_state() -> int:
	if _escaped:
		return TrapState.RUINED
	if agitation >= _at_risk_at:
		return TrapState.AT_RISK
	return TrapState.OK


func hint_text() -> Array:
	if _escaped:
		return LocText.make("HUD_HINT_NOISY_RUINED")
	if agitation >= _agitation_max:
		return LocText.make("HUD_HINT_NOISY_DANGER")
	if agitation >= _at_risk_at:
		return LocText.make("HUD_HINT_NOISY_RISK")
	return LocText.make("HUD_HINT_NOISY_OK")


## The radio's mode right now: the box's truck when it can be asked, else the
## last one a tick saw.
func _current_radio_mode() -> StringName:
	if is_instance_valid(_box) and _box is DeliveryPackage:
		return PackageRescue.radio_mode(_box as DeliveryPackage)
	return _radio_mode


## What it settles per second with nobody calming it, with the radio's say.
func _radio_passive_decay() -> float:
	match _radio_mode:
		&"calm":
			return _passive_decay + _radio_calm_extra_decay
		&"loud":
			return _passive_decay * _radio_loud_passive_mult
	return _passive_decay


func _sync_integrity() -> void:
	# Agitation is the failure axis, reported on the shared scale so the HUD
	# and the score treat it like any other trap.
	integrity = integrity_max * (1.0 - agitation / _agitation_max)
