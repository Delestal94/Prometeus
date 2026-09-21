extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_streaming.gd
## Covers RouteStreamer in isolation, without a real vehicle: a plain Node3D
## stands in for the tracked target and gets moved by hand, since what's
## under test is the spawn/cull bookkeeping, not vehicle physics.

var _failures: int = 0


func _initialize() -> void:
	await process_frame

	var streamer := RouteStreamer.new()
	root.add_child(streamer)
	var target := Node3D.new()
	root.add_child(target)

	streamer.start(target)
	_expect((streamer.get(&"_active") as Array).size() > 0,
		"start() spawns at least one segment ahead of the target immediately")

	var initial_next_z: float = float(streamer.get(&"_next_z"))
	_expect(initial_next_z < 0.0,
		"Segments chain forward (more negative Z), matching route.gd's direction of travel")

	# Push the target far down the route and let the streamer catch up, the
	# same way _physics_process would across many frames -- called directly
	# so the test doesn't depend on real frame timing.
	target.position.z = -500.0
	for _step: int in range(50):
		streamer.call(&"_fill_ahead")
		streamer.call(&"_cull_behind")

	var active: Array = streamer.get(&"_active")
	_expect(not active.is_empty(), "Streaming keeps producing segments far down the route")

	var horizon: float = target.position.z - float(streamer.get(&"lookahead_distance"))
	_expect(float(streamer.get(&"_next_z")) <= horizon,
		"Always keeps at least lookahead_distance of road already built ahead of the target")

	var behind_keep: float = float(streamer.get(&"behind_keep_distance"))
	var stale_found: bool = false
	for segment: Node in active:
		var exit_z: float = float(segment.position.z) - float(segment.get(&"length"))
		if target.position.z < exit_z - behind_keep:
			stale_found = true
	_expect(not stale_found, "Segments well behind the target get freed, not kept forever")

	var repeated_type: bool = false
	for index: int in range(1, active.size()):
		if active[index].get_script() == active[index - 1].get_script():
			repeated_type = true
	_expect(not repeated_type,
		"Combination rule holds: no two consecutive segments are the same type")

	if _failures == 0:
		print("PASS: RouteStreamer spawns ahead, culls behind, and never repeats a segment type back to back")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
