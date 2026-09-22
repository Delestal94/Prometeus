extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_difficulty.gd
## Covers docs/tareas-nacho.md #47: with the pool grown to 7 segment types,
## three "hard" ones (chicane, narrow bridge, S-curve, gravel, construction
## zone) landing back to back became a real possibility by chance alone.
## RouteStreamer now forces a breather after two in a row.

var _failures: int = 0


func _initialize() -> void:
	await process_frame

	var streamer := RouteStreamer.new()
	root.add_child(streamer)
	var target := Node3D.new()
	root.add_child(target)
	streamer.start(target)

	var picks: Array[Script] = []
	streamer.child_entered_tree.connect(func(segment: Node) -> void: picks.append(segment.get_script()))
	# ~1.8km simulated, advancing in chunks so _fill_ahead()/_cull_behind()
	# behave like the real per-physics-frame usage instead of one giant
	# batch spawn -- plenty of segments for a real statistical check without
	# ever letting _active grow unbounded (nothing here awaits a frame, so
	# nothing needs to; test_route_streaming.gd uses the same direct-call
	# pattern successfully).
	for _i: int in range(120):
		target.position.z -= 15.0
		streamer.call(&"_fill_ahead")
		streamer.call(&"_cull_behind")

	var hard_segments: Array[Script] = streamer.get(&"hard_segments")
	_expect(hard_segments.size() == 5, "RouteStreamer actually populated its hard-segment list (got %d)" % hard_segments.size())

	var hard_run: int = 0
	var worst_run: int = 0
	for script: Script in picks:
		if hard_segments.has(script):
			hard_run += 1
			worst_run = maxi(worst_run, hard_run)
		else:
			hard_run = 0
	_expect(worst_run <= 2,
		"Never three hard segments back to back across a long simulated drive (longest hard run: %d, %d segments total)" % [worst_run, picks.size()])

	var hard_count: int = 0
	for script: Script in picks:
		if hard_segments.has(script):
			hard_count += 1
	_expect(hard_count > 0, "Hard segments still actually get picked, not filtered out entirely (got %d/%d)" % [hard_count, picks.size()])

	streamer.free()
	target.free()
	if _failures == 0:
		print("PASS: RouteStreamer never strings together three hard segments in a row")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
