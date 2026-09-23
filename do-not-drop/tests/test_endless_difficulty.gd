extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_endless_difficulty.gd
## Endless mode gets harder the further you go (docs/tareas-nacho.md #49):
## far fewer hard segments in the first stretch than two kilometres in, and
## never three hard ones back to back at any point.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _hard_share(streamer: Node, at_distance: float, picks: int) -> float:
	var hard: int = 0
	for _i: int in range(picks):
		streamer.set(&"_next_z", -at_distance)
		var script: Script = streamer.call(&"_pick_next_script")
		streamer.set(&"_last_script", script)
		streamer.set(&"_hard_streak", int(streamer.get(&"_hard_streak")) + 1 if (streamer.get(&"hard_segments") as Array).has(script) else 0)
		if (streamer.get(&"hard_segments") as Array).has(script):
			hard += 1
	return float(hard) / picks


func _run() -> void:
	var streamer: Node = load("res://scripts/gameplay/route/route_streamer.gd").new()
	root.add_child(streamer)
	await process_frame
	var early: float = _hard_share(streamer, 50.0, 3000)
	var late: float = _hard_share(streamer, 2500.0, 3000)
	_expect(late > early + 0.15, "Far more hard segments deep into the run (%.0f%% at 50 m vs %.0f%% at 2.5 km)" % [early * 100.0, late * 100.0])
	_expect(is_equal_approx(streamer.call(&"hard_weight_at", 0.0), 0.25) and is_equal_approx(streamer.call(&"hard_weight_at", 5000.0), 2.5), "The ramp starts gentle and tops out")
	var streak: int = 0
	var worst: int = 0
	streamer.set(&"_hard_streak", 0)
	for _i: int in range(4000):
		streamer.set(&"_next_z", -3000.0)
		var script: Script = streamer.call(&"_pick_next_script")
		streamer.set(&"_last_script", script)
		streak = streak + 1 if (streamer.get(&"hard_segments") as Array).has(script) else 0
		streamer.set(&"_hard_streak", streak)
		worst = maxi(worst, streak)
	_expect(worst <= 2, "Even at full difficulty, never three hard segments in a row (worst %d)" % worst)
	streamer.free()
	if _failures == 0:
		print("PASS: endless mode ramps up with distance and still leaves breathers")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
