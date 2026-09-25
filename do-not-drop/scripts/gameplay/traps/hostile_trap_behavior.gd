class_name HostileTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## A reactive creature: unlike Noisy (always hold to calm), its mood flips
## between CALMAR and NO TOCAR. Holding at the wrong moment is an attack.

var aggression: float = 0.0
var command_calm: bool = true
var command_seconds: float = 2.8
var attack_count: int = 0
var _command_timer: float = 2.8
var _attack_cooldown: float = 0.0
var _correct_decay: float = 13.0
var _wrong_gain: float = 22.0
var _passive_gain: float = 3.5

func on_setup(_package: Node, config: Dictionary) -> void:
	super.on_setup(_package, config)
	command_seconds = float(config.get("command_seconds", 2.8))
	_correct_decay = float(config.get("correct_decay", 13.0))
	_wrong_gain = float(config.get("wrong_gain", 22.0))
	_passive_gain = float(config.get("passive_gain", 3.5))
	aggression = 0.0
	command_calm = true
	_command_timer = command_seconds
	attack_count = 0
	_attack_cooldown = 0.0

func on_physics_process(_package: Node, delta: float, context: Dictionary) -> void:
	if get_state() == TrapState.RUINED:
		return
	var before_state: int = get_state()
	_command_timer -= delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _command_timer <= 0.0:
		command_calm = not command_calm
		_command_timer += command_seconds
	var input: Dictionary = context.get("input", {}) as Dictionary
	var holding: bool = bool(input.get("calm", false))
	if holding == command_calm:
		aggression = maxf(0.0, aggression - _correct_decay * delta)
	else:
		aggression = minf(integrity_max, aggression + _passive_gain * delta)
		if _attack_cooldown <= 0.0:
			aggression = minf(integrity_max, aggression + _wrong_gain)
			attack_count += 1
			_attack_cooldown = 0.8
	_sync_integrity()
	if before_state == TrapState.AT_RISK and get_state() == TrapState.OK:
		_add_milestone(&"calmed")

func on_impact(delta_velocity: float) -> float:
	if delta_velocity >= 5.0:
		aggression = minf(integrity_max, aggression + 12.0)
	_sync_integrity()
	return 0.0

func get_state() -> int:
	if aggression >= integrity_max:
		return TrapState.RUINED
	if aggression >= integrity_max * 0.55:
		return TrapState.AT_RISK
	return TrapState.OK

func get_hint() -> String:
	if get_state() == TrapState.RUINED:
		return "La criatura escapó."
	return "CALMÁ (mantené)" if command_calm else "NO TOCAR (soltá)"

func _sync_integrity() -> void:
	integrity = integrity_max * (1.0 - aggression / integrity_max)
