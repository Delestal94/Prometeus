class_name HostileTrapBehavior
extends ITrapBehavior
## A reactive creature: unlike Noisy (always hold to calm), its mood flips
## between CALMAR and NO TOCAR. Holding at the wrong moment is an attack.

var aggression: float = 0.0
## Aggression per running step with the box in the arms.
const RUN_STEP_AGGRESSION: float = 1.2
var command_calm: bool = true
var command_seconds: float = 2.8
var attack_count: int = 0
var _command_timer: float = 2.8
var _attack_cooldown: float = 0.0
var _correct_decay: float = 13.0
var _wrong_gain: float = 22.0
var _passive_gain: float = 3.5
var _calm_strength_required: float = 1.0

func on_setup(_package: Node, config: Dictionary) -> void:
	super.on_setup(_package, config)
	command_seconds = float(config.get("command_seconds", 2.8))
	_correct_decay = float(config.get("correct_decay", 13.0))
	_wrong_gain = float(config.get("wrong_gain", 22.0))
	_passive_gain = float(config.get("passive_gain", 3.5))
	_calm_strength_required = maxf(float(config.get("calm_strength_required", 1.0)), 0.1)
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
	var calm_strength: float = float(input.get("calm_strength", 1.0 if bool(input.get("calm", false)) else 0.0))
	var holding: bool = calm_strength > 0.0
	if holding == command_calm:
		var effectiveness: float = clampf(calm_strength / _calm_strength_required, 0.0, 1.0) if command_calm else 1.0
		aggression = maxf(0.0, aggression - _correct_decay * effectiveness * delta)
	else:
		aggression = minf(integrity_max, aggression + _passive_gain * delta)
		if _attack_cooldown <= 0.0:
			aggression = minf(integrity_max, aggression + _wrong_gain)
			attack_count += 1
			_attack_cooldown = 0.8
	_sync_integrity()
	if before_state == TrapState.AT_RISK and get_state() == TrapState.OK:
		_add_milestone(&"calmed")

## Every running step irritates it a little (N-115).
func on_carried_step(strength: float) -> float:
	if get_state() != TrapState.RUINED:
		aggression = minf(integrity_max, aggression + RUN_STEP_AGGRESSION * strength)
		_sync_integrity()
	return 0.0


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

func care_action() -> StringName:
	if get_state() == TrapState.RUINED:
		return &""
	return &"hold" if command_calm else &"release"

func hint_text() -> Array:
	if get_state() == TrapState.RUINED:
		return LocText.make("HUD_HINT_HOSTILE_RUINED")
	return LocText.make("HUD_HINT_HOSTILE_CALM" if command_calm else "HUD_HINT_HOSTILE_DONT_TOUCH")

func _sync_integrity() -> void:
	integrity = integrity_max * (1.0 - aggression / integrity_max)
