class_name ExplosiveTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## A short sequence under a real timer.  Unlike the continuous care traps,
## it wants distinct directional inputs. A mistake burns time but does not
## randomize the answer, so teams can recover instead of guessing forever.

var seconds_left: float = 14.0
var _countdown_total: float = 14.0
var sequence_index: int = 0
var sequence: Array[StringName] = [&"up", &"left", &"down"]
var _mistake_penalty: float = 1.5
var _defused: bool = false
var _last_input: StringName = &""
var _mistakes: int = 0

func on_setup(_package: Node, config: Dictionary) -> void:
	super.on_setup(_package, config)
	_countdown_total = float(config.get("countdown_seconds", 14.0))
	seconds_left = _countdown_total
	_mistake_penalty = float(config.get("mistake_penalty", 1.5))
	sequence = Array(config.get("sequence", [&"up", &"left", &"down"]), TYPE_STRING_NAME, "", null)
	if sequence.is_empty():
		sequence = [&"up", &"left", &"down"]
	sequence_index = 0
	_defused = false
	_last_input = &""
	_mistakes = 0

func on_physics_process(_package: Node, delta: float, context: Dictionary) -> void:
	if _defused or seconds_left <= 0.0:
		return
	seconds_left = maxf(0.0, seconds_left - delta)
	var input: Dictionary = context.get("input", {}) as Dictionary
	var direction: Variant = input.get("direction_pressed", null)
	if direction != null:
		_consume_direction(StringName(direction))
	_sync_integrity()

func on_impact(delta_velocity: float) -> float:
	if delta_velocity >= 7.0 and not _defused:
		seconds_left = maxf(0.0, seconds_left - 0.8)
	_sync_integrity()
	return 0.0

func get_state() -> int:
	if seconds_left <= 0.0:
		return TrapState.RUINED
	if _defused:
		return TrapState.OK
	if seconds_left <= 6.0:
		return TrapState.AT_RISK
	return TrapState.OK

func get_hint() -> String:
	if seconds_left <= 0.0:
		return tr("HUD_HINT_EXPLOSIVE_RUINED")
	if _defused:
		return tr("HUD_HINT_EXPLOSIVE_SAFE")
	return tr("HUD_HINT_EXPLOSIVE_SEQUENCE") % [ceili(seconds_left), _direction_text(sequence[sequence_index])]

func next_direction() -> StringName:
	return &"" if _defused or seconds_left <= 0.0 else sequence[sequence_index]

func _consume_direction(direction: StringName) -> void:
	if direction == _last_input:
		return
	_last_input = direction
	if direction == sequence[sequence_index]:
		sequence_index += 1
		if sequence_index >= sequence.size():
			_defused = true
			integrity = integrity_max
			_add_milestone(&"defused")
	else:
		seconds_left = maxf(0.0, seconds_left - _mistake_penalty)
		sequence_index = 0
		_mistakes += 1

func sequence_state() -> Dictionary:
	if seconds_left <= 0.0:
		return {}
	return {"steps": sequence.duplicate(), "index": sequence.size() if _defused else sequence_index,
		"mistakes": _mistakes, "solved": 1 if _defused else 0, "seconds": seconds_left, "verb": "Desactivar"}

func _sync_integrity() -> void:
	if _defused:
		integrity = integrity_max
	else:
		integrity = integrity_max * clampf(seconds_left / maxf(_countdown_total, 0.01), 0.0, 1.0)

func _direction_text(direction: StringName) -> String:
	return {&"up": "↑", &"down": "↓", &"left": "←", &"right": "→"}.get(direction, "?")
