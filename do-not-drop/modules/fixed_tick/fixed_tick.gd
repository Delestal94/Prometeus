class_name FixedTick
extends RefCounted
## Runs named steps at a fixed rate (e.g. 4 times a second) out of whatever delta the caller's
## frame had: logic that only needs to look at the world a few times a second (rules, timers,
## queues) runs on its own cadence, not once per rendered or physics frame.
##
## advance(delta) adds the delta to an accumulator and, for every whole step period in it, runs
## every step once, in the order they were added. After a hitch (a long frame) it runs at most
## max_catch_up ticks and drops the rest of the accumulated time, so a stall never turns into a
## burst of work that makes the next frame long too. A step whose object was freed is dropped the
## next time it would run.
##
## Pure: no node, no tree, no network. Who calls advance() (a node's _process, a test with made-up
## deltas) and on which machine is the caller's. It only reads Time.get_ticks_usec() to measure
## what the last advance() cost (last_run_usec), for a profiler.

## Ticks run in one advance() at most; the time past them is dropped.
const DEFAULT_MAX_CATCH_UP: int = 4

## Real seconds between two ticks.
var step_seconds: float = 0.25
## Ticks advance() runs at most per call (at least 1).
var max_catch_up: int = DEFAULT_MAX_CATCH_UP
## Ticks run since this FixedTick was made.
var tick_count: int = 0
## Ticks dropped after hitches (time past max_catch_up), since this FixedTick was made.
var dropped_ticks: int = 0
## Microseconds the steps took in the last advance() that ran a tick (0 before any).
var last_run_usec: int = 0

var _accumulated: float = 0.0
var _names: Array[StringName] = []
var _steps: Array[Callable] = []


## `rate_hz` ticks per real second (a rate of 0 or less, or one that isn't finite, keeps 4).
func _init(rate_hz: float = 4.0, catch_up: int = DEFAULT_MAX_CATCH_UP) -> void:
	if is_finite(rate_hz) and rate_hz > 0.0:
		step_seconds = 1.0 / rate_hz
	max_catch_up = maxi(catch_up, 1)


## Adds `step` (a Callable with no arguments) under `step_name`; it runs on every tick after the
## steps added before it. False, changing nothing, for a name already taken or a step that isn't
## valid.
func add_step(step_name: StringName, step: Callable) -> bool:
	if step_name in _names or not step.is_valid():
		return false
	_names.append(step_name)
	_steps.append(step)
	return true


## Takes out the step named `step_name`. False when there is none.
func remove_step(step_name: StringName) -> bool:
	var index: int = _names.find(step_name)
	if index < 0:
		return false
	_names.remove_at(index)
	_steps.remove_at(index)
	return true


func has_step(step_name: StringName) -> bool:
	return step_name in _names


## The names of the steps, in the order they run.
func step_names() -> Array[StringName]:
	return _names.duplicate()


## Adds `delta` real seconds (a negative or non-finite one counts as 0) and runs the ticks now due,
## at most max_catch_up of them. Returns how many ran.
func advance(delta: float) -> int:
	if is_finite(delta) and delta > 0.0:
		_accumulated += delta
	var due: int = floori(_accumulated / step_seconds)
	if due <= 0:
		return 0
	var ran: int = mini(due, max_catch_up)
	if due > ran:
		dropped_ticks += due - ran
		_accumulated = 0.0
	else:
		_accumulated -= float(ran) * step_seconds
	var started: int = Time.get_ticks_usec()
	for _i: int in ran:
		_run_once()
	last_run_usec = Time.get_ticks_usec() - started
	return ran


## Runs every step once, now, outside the cadence (it counts as a tick). A test, or a caller that
## needs the rules applied at once (the moment a world comes up), calls it.
func run_now() -> void:
	_run_once()


func _run_once() -> void:
	tick_count += 1
	var index: int = 0
	while index < _steps.size():
		var step: Callable = _steps[index]
		if not step.is_valid():
			_names.remove_at(index)
			_steps.remove_at(index)
			continue
		step.call()
		index += 1
