class_name ExplosiveTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## "Pedí el código" (N-117): a short code under a real timer, drawn fresh for
## every box by the host (never the same answer twice, so it can't be
## memorized). The box's owner does not get to see it: the driver reads it
## off the dashboard (DashboardGps) and says it out loud, and the owner taps
## the directions. A mistake burns time but does not draw a new code, so
## teams can recover instead of guessing forever.
##
## Who may read the code travels with the sequence state ("reader"): the
## package decides it each tick (context["code_reader"]) -- the driver, or
## the owner when there is no other human at the wheel.

const DIRECTIONS: Array[StringName] = [&"up", &"down", &"left", &"right"]
const READER_DRIVER: StringName = &"driver"
const READER_OWNER: StringName = &"owner"
## Seconds off the fuse per running step with the box in the arms (N-115).
const RUN_STEP_FUSE: float = 0.12

var seconds_left: float = 14.0
var _countdown_total: float = 14.0
var sequence_index: int = 0
var sequence: Array[StringName] = []
var _code_length: int = 3
var _rng := RandomNumberGenerator.new()
var _mistake_penalty: float = 1.5
var _defused: bool = false
var _mistakes: int = 0
var _code_reader: StringName = READER_DRIVER


## Config: `sequence` fixes the code (tests and tuning); otherwise
## `code_length` steps are drawn from `roll_seed` (the package derives it
## from the session seed, see DeliveryPackage.initialize_trap()), or from
## the clock when there is none.
func on_setup(_package: Node, config: Dictionary) -> void:
	super.on_setup(_package, config)
	_countdown_total = float(config.get("countdown_seconds", 14.0))
	seconds_left = _countdown_total
	_mistake_penalty = float(config.get("mistake_penalty", 1.5))
	_code_length = clampi(int(config.get("code_length", 3)), 2, 6)
	var roll_seed: int = int(config.get("roll_seed", 0))
	if roll_seed != 0:
		_rng.seed = roll_seed
	else:
		_rng.randomize()
	_roll_sequence()
	var fixed: Array = config.get("sequence", []) as Array
	if not fixed.is_empty():
		sequence = Array(fixed, TYPE_STRING_NAME, "", null)
	sequence_index = 0
	_defused = false
	_mistakes = 0
	_code_reader = READER_DRIVER


func on_physics_process(_package: Node, delta: float, context: Dictionary) -> void:
	var reader := StringName(context.get("code_reader", _code_reader))
	if reader == READER_DRIVER or reader == READER_OWNER:
		_code_reader = reader
	if _defused or seconds_left <= 0.0:
		return
	seconds_left = maxf(0.0, seconds_left - delta)
	var input: Dictionary = context.get("input", {}) as Dictionary
	var direction: Variant = input.get("direction_pressed", null)
	if direction != null:
		_consume_direction(StringName(direction))
	_sync_integrity()


## Running with a bomb in the arms: each step shaves a little off the fuse (N-115).
func on_carried_step(strength: float) -> float:
	if not _defused and seconds_left > 0.0:
		seconds_left = maxf(0.0, seconds_left - RUN_STEP_FUSE * strength)
		_sync_integrity()
	return 0.0


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


## The hint goes to every peer's HUD, so unless the owner is the one who
## reads the code it says who has it, never the code itself.
func hint_text() -> Array:
	if seconds_left <= 0.0:
		return LocText.make("HUD_HINT_EXPLOSIVE_RUINED")
	if _defused:
		return LocText.make("HUD_HINT_EXPLOSIVE_SAFE")
	if _code_reader == READER_OWNER:
		return LocText.make("HUD_HINT_EXPLOSIVE_SEQUENCE",
			[ceili(seconds_left), _direction_text(sequence[sequence_index])])
	return LocText.make("HUD_HINT_EXPLOSIVE_CODE", [ceili(seconds_left), sequence_index, sequence.size()])


func next_direction() -> StringName:
	return &"" if _defused or seconds_left <= 0.0 else sequence[sequence_index]


## Draws a new code: `_code_length` directions, never the same one twice in a
## row (easier to say aloud, and to tell apart from a double tap).
func _roll_sequence() -> void:
	sequence.clear()
	sequence_index = 0
	var previous: StringName = &""
	while sequence.size() < maxi(_code_length, 1):
		var pick: StringName = DIRECTIONS[_rng.randi_range(0, DIRECTIONS.size() - 1)]
		if pick == previous:
			continue
		sequence.append(pick)
		previous = pick


func _consume_direction(direction: StringName) -> void:
	if direction == sequence[sequence_index]:
		sequence_index += 1
		if sequence_index >= sequence.size():
			_defused = true
			integrity = integrity_max
			_add_milestone(&"defused")
	else:
		seconds_left = maxf(0.0, seconds_left - _mistake_penalty)
		# The wrong key that happens to be the first step still starts over.
		sequence_index = 1 if direction == sequence[0] and sequence.size() > 1 else 0
		_mistakes += 1


## The code and how far along it is, for every peer's copy (published with
## the care state). `reader` says whose screen shows the arrows: the
## owner's card hides them unless it is `owner`.
func sequence_state() -> Dictionary:
	if seconds_left <= 0.0:
		return {}
	return {"steps": sequence.duplicate(), "index": sequence.size() if _defused else sequence_index,
		"mistakes": _mistakes, "solved": 1 if _defused else 0, "seconds": seconds_left,
		"verb": "HUD_CARE_VERB_DEFUSE", "reader": _code_reader}


func _sync_integrity() -> void:
	if _defused:
		integrity = integrity_max
	else:
		integrity = integrity_max * clampf(seconds_left / maxf(_countdown_total, 0.01), 0.0, 1.0)


func _direction_text(direction: StringName) -> String:
	return {&"up": "↑", &"down": "↓", &"left": "←", &"right": "→"}.get(direction, "?")
