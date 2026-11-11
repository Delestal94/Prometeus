extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/fixed_tick/tests/test_fixed_tick.gd
##
## The fixed_tick module on its own (docs/modulos.md, FixedTick):
## - cadence: at 4 Hz, 10 s of 60 fps frames run 40 ticks (±1) and every step runs on each; at
##   144 fps and at 20 fps, the same 40; a frame shorter than a period runs nothing;
## - steps run in the order they were added; a name can't be taken twice, an invalid Callable is
##   refused, remove_step() takes one out, and a step whose object was freed is dropped;
## - a hitch (a 3 s frame) runs at most max_catch_up ticks and drops the rest, counted in
##   dropped_ticks; negative, NaN and infinite deltas run nothing;
## - a bad rate keeps 4 Hz; run_now() runs every step once, outside the cadence;
## - cost: 10 000 frames with an empty step take well under 1 ms a frame on average.

var _failures: int = 0


class Counter extends RefCounted:
	var calls: int = 0
	var trail: Array = []
	var tag: String = ""

	func _init(t: String = "", shared: Array = []) -> void:
		tag = t
		trail = shared

	func step() -> void:
		calls += 1
		trail.append(tag)


func _initialize() -> void:
	_check_cadence()
	_check_steps()
	_check_hitch()
	_check_cost()
	if _failures == 0:
		print("PASS: fixed ticks keep their cadence at any frame rate, run steps in order and cap"
			+ " the catch-up after a hitch")
	quit(_failures)


func _run_frames(tick: FixedTick, fps: float, seconds: float) -> int:
	var ran: int = 0
	for _i: int in roundi(fps * seconds):
		ran += tick.advance(1.0 / fps)
	return ran


func _check_cadence() -> void:
	for fps: float in [60.0, 144.0, 20.0]:
		var tick := FixedTick.new(4.0)
		var counter := Counter.new()
		tick.add_step(&"count", counter.step)
		var ran: int = _run_frames(tick, fps, 10.0)
		_expect(absi(ran - 40) <= 1 and counter.calls == ran and tick.tick_count == ran,
			"At %d fps, 10 s run 40 ticks ±1 and the step on each (got %d ticks, %d calls)"
			% [int(fps), ran, counter.calls])
	var short := FixedTick.new(4.0)
	_expect(short.advance(0.2) == 0 and short.advance(0.04) == 0 and short.advance(0.02) == 1,
		"Frames under a period run nothing until a whole period adds up")
	var bad := FixedTick.new(0.0)
	_expect(is_equal_approx(bad.step_seconds, 0.25) and is_equal_approx(FixedTick.new(NAN).step_seconds, 0.25)
		and is_equal_approx(FixedTick.new(10.0).step_seconds, 0.1),
		"A bad rate keeps 4 Hz; 10 Hz is a tenth of a second (got %.3f)" % bad.step_seconds)


func _check_steps() -> void:
	var tick := FixedTick.new(4.0)
	var order: Array = []
	var first := Counter.new("a", order)
	var second := Counter.new("b", order)
	_expect(tick.add_step(&"a", first.step) and tick.add_step(&"b", second.step),
		"Two steps with different names are added")
	_expect(not tick.add_step(&"a", second.step) and not tick.add_step(&"c", Callable()),
		"A name already taken and an invalid Callable are refused")
	tick.advance(0.5)
	_expect(order == ["a", "b", "a", "b"],
		"Steps run in the order they were added, once per tick (got %s)" % [order])
	_expect(tick.remove_step(&"a") and not tick.remove_step(&"a") and tick.step_names() == [&"b"],
		"remove_step() takes a step out once (left %s)" % [tick.step_names()])
	var node := Node.new()
	_expect(tick.add_step(&"node", node.get_index), "A step on a node is added")
	node.free()
	order.clear()
	tick.run_now()
	_expect(order == ["b"] and not tick.has_step(&"node"),
		"run_now() runs every step once and a freed object's step is dropped (got %s, %s)"
		% [order, tick.step_names()])


func _check_hitch() -> void:
	var tick := FixedTick.new(4.0, 3)
	var counter := Counter.new()
	tick.add_step(&"count", counter.step)
	var ran: int = tick.advance(3.0)
	_expect(ran == 3 and counter.calls == 3 and tick.dropped_ticks == 9,
		"A 3 s frame runs 3 ticks (the cap) and drops 9 (got %d ran, %d dropped)" % [ran, tick.dropped_ticks])
	_expect(tick.advance(0.2) == 0, "After a hitch the rest of the time is dropped, not carried")
	_expect(tick.advance(-1.0) == 0 and tick.advance(NAN) == 0 and tick.advance(INF) == 0
		and counter.calls == 3, "Negative, NaN and infinite deltas run nothing (calls %d)" % counter.calls)
	_expect(FixedTick.new(4.0, 0).max_catch_up == 1, "The catch-up cap is at least one tick")


func _check_cost() -> void:
	var tick := FixedTick.new(4.0)
	var counter := Counter.new()
	tick.add_step(&"count", counter.step)
	var started: int = Time.get_ticks_usec()
	_run_frames(tick, 60.0, 10000.0 / 60.0)
	var per_frame: float = float(Time.get_ticks_usec() - started) / 10000.0
	_expect(per_frame < 100.0, "A frame costs %.1f µs on average (limit 100 µs)" % per_frame)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
