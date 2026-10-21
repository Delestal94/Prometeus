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
## No catch-up: after a hitch it runs one tick and drops the rest. Its steps look at the world as it
## is (they don't integrate time), so running them again in the same frame would only see the same
## world, and DayCycle could cross two phases in one frame (CLOSING must last at least one poll).
##
## Profiling: last_run_usec() is what the steps cost on the last frame that ran a tick, and
## dropped_ticks() what hitches cost in ticks.

var tick := FixedTick.new(CompanyTuning.BUSINESS_TICK_HZ, 1)


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
