class_name BusinessTick
extends Node
## The company's business tick (D-0232): the host's rules that only need to look at the world a few
## times a second run here, at CompanyTuning.BUSINESS_TICK_HZ, apart from physics and from the
## rendered frame. Adapter of the fixed_tick module (FixedTick, docs/modulos.md).
##
## CompanyRoot adds it on the host only (solo too): every step is a host rule that may publish or
## request through CompanyNet; a client's mirror changes only through the host's events. Steps run
## in the order they were added (add_step()); the first is DayCycle.poll, whose own _process the
## root turns off, so the day moves on the same tick as whatever joins it later (orders, the
## supplier, employees, machines).
##
## Profiling: last_run_usec() is what the steps cost on the last frame that ran a tick, and
## dropped_ticks() what hitches cost in ticks (more than FixedTick.DEFAULT_MAX_CATCH_UP due at once).

var tick := FixedTick.new(CompanyTuning.BUSINESS_TICK_HZ)


func _process(delta: float) -> void:
	tick.advance(delta)


## Adds `step` (no arguments) to run on every tick after the ones already added. False for a name
## already taken or an invalid Callable.
func add_step(step_name: StringName, step: Callable) -> bool:
	return tick.add_step(step_name, step)


func remove_step(step_name: StringName) -> bool:
	return tick.remove_step(step_name)


func has_step(step_name: StringName) -> bool:
	return tick.has_step(step_name)


func last_run_usec() -> int:
	return tick.last_run_usec


func dropped_ticks() -> int:
	return tick.dropped_ticks
