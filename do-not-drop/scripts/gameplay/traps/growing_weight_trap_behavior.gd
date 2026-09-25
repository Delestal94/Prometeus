class_name GrowingWeightTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## Gets heavier unless its passenger keeps solving a short input sequence.
## The added mass is real, not cosmetic: a neglected box genuinely drags the
## van's handling down, which is what makes one distracted passenger
## everyone else's problem.

const DIRECTIONS: Array[StringName] = [&"up", &"down", &"left", &"right"]

var sequence: Array[StringName] = []
var sequence_index: int = 0
var mass_multiplier: float = 1.0

var _puzzle_time_limit: float = 8.0
var _sequence_length: int = 4
var _growth_step: float = 0.15
var _growth_interval: float = 2.0
var _fail_multiplier: float = 2.5
var _at_risk_multiplier: float = 1.5
var _base_mass: float = 8.0
var _time_since_solved: float = 0.0
var _time_since_growth: float = 0.0
var _rng := RandomNumberGenerator.new()


func on_setup(package: Node, config: Dictionary) -> void:
	super.on_setup(package, config)
	_puzzle_time_limit = float(config.get("puzzle_time_limit", 8.0))
	_sequence_length = int(config.get("sequence_length", 4))
	_growth_step = float(config.get("weight_growth_rate", 0.15))
	_growth_interval = maxf(float(config.get("weight_growth_interval", 2.0)), 0.05)
	_fail_multiplier = maxf(float(config.get("weight_fail_threshold", 2.5)), 1.01)
	_at_risk_multiplier = float(config.get("weight_at_risk_threshold", 1.5))
	if package != null:
		_base_mass = maxf(float(package.get("mass")), 0.01)
	_rng.randomize()
	mass_multiplier = 1.0
	_time_since_solved = 0.0
	_time_since_growth = 0.0
	_roll_sequence()


func on_physics_process(package: Node, delta: float, context: Dictionary) -> void:
	if get_state() == TrapState.RUINED:
		return
	_consume_input(context.get("input", {}) as Dictionary)
	_time_since_solved += delta
	if _time_since_solved >= _puzzle_time_limit:
		_time_since_growth += delta
		while _time_since_growth >= _growth_interval:
			_time_since_growth -= _growth_interval
			mass_multiplier += _growth_step
	_apply_mass(package)
	_sync_integrity()


## Called by the passenger's input each time they press a direction.
func press_direction(direction: StringName) -> bool:
	if get_state() == TrapState.RUINED or sequence.is_empty():
		return false
	if direction != sequence[sequence_index]:
		sequence_index = 0
		return false
	sequence_index += 1
	if sequence_index < sequence.size():
		return true
	_solve()
	return true


func get_state() -> int:
	if mass_multiplier >= _fail_multiplier:
		return TrapState.RUINED
	if mass_multiplier >= _at_risk_multiplier:
		return TrapState.AT_RISK
	return TrapState.OK


func get_hint() -> String:
	if get_state() == TrapState.RUINED:
		return "Imposible de sostener."
	var pending: String = ""
	for index: int in range(sequence.size()):
		pending += ("[%s] " % _arrow(sequence[index])) if index >= sequence_index else ""
	var seconds_left: float = maxf(_puzzle_time_limit - _time_since_solved, 0.0)
	if seconds_left > 0.0:
		return "Asegurá la carga: %s(%.0fs)" % [pending, seconds_left]
	return "¡Se está poniendo pesado! %s" % pending


func _solve() -> void:
	mass_multiplier = 1.0
	_time_since_solved = 0.0
	_time_since_growth = 0.0
	_roll_sequence()
	_sync_integrity()
	_add_milestone(&"sequence")


func _roll_sequence() -> void:
	sequence.clear()
	sequence_index = 0
	for _index: int in range(maxi(_sequence_length, 1)):
		sequence.append(DIRECTIONS[_rng.randi_range(0, DIRECTIONS.size() - 1)])


func _consume_input(input: Dictionary) -> void:
	var pressed: Variant = input.get("direction_pressed")
	if pressed != null and pressed is StringName:
		press_direction(pressed as StringName)


func _apply_mass(package: Node) -> void:
	if package != null:
		package.set(&"mass", _base_mass * mass_multiplier)


func _sync_integrity() -> void:
	# Distance left before the box becomes unmanageable, on the shared scale.
	var span: float = _fail_multiplier - 1.0
	var used: float = clampf((mass_multiplier - 1.0) / span, 0.0, 1.0)
	integrity = integrity_max * (1.0 - used)


func _arrow(direction: StringName) -> String:
	match direction:
		&"up":
			return "↑"
		&"down":
			return "↓"
		&"left":
			return "←"
		_:
			return "→"
