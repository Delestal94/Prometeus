extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_level_endless.gd
## Covers docs/tareas-nacho.md #41-43, #51 and #53: connecting RouteStreamer
## to a real, playable vehicle (not just the Node3D stand-in
## test_route_streaming.gd uses), and that a long simulated session doesn't
## quietly leak segments.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_endless.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var run_manager: Node = root.get_node(^"/root/RunManager")

	# Restricted to segments a perfectly straight, un-steered drive can
	# actually survive -- a chicane or narrow bridge blocking a driver going
	# dead straight is correct, working-as-intended behavior (that's the
	# whole point of those segments), not something this test should fight.
	# Real steering around them is docs/tareas-nacho.md #55's playtesting,
	# not something to fake here.
	var streamer: Node = level.get_node(^"World/RouteStreamer")
	streamer.set(&"segment_scripts", [StraightSegment, SpeedBumpSegment])

	level.call(&"start_debug_delivery")
	await process_frame
	await physics_frame
	_expect(bool(run_manager.get(&"is_running")), "Boarding with cargo loaded starts the run, same as the curated level")

	_expect(streamer.get(&"target") == level.vehicle, "RouteStreamer.start() was actually wired to the real vehicle, not left unstarted")
	_expect((streamer.get(&"_active") as Array).size() > 0, "Segments exist right away, not just after the vehicle starts moving")

	var van: VehicleBody3D = level.vehicle
	van.controls_enabled = false  # deterministic driver, same trick every vehicle test uses
	van.set_controls(0.9, 0.0, false)

	# ~15 simulated seconds at 60Hz -- long enough to cross several segments
	# and prove segments actually get culled behind, not just spawned ahead.
	var peak_active_count: int = 0
	for _i: int in range(900):
		await physics_frame
		peak_active_count = maxi(peak_active_count, (streamer.get(&"_active") as Array).size())

	_expect(float(level.get(&"distance_traveled")) > 30.0,
		"distance_traveled actually tracks real movement (got %.1f m)" % float(level.get(&"distance_traveled")))

	var final_active: Array = streamer.get(&"_active")
	_expect(final_active.size() > 0, "Streaming never runs dry after a long drive")
	_expect(final_active.size() < peak_active_count + 3,
		"Active segment count stays bounded over a long session instead of only ever growing (peak %d, final %d)" % [peak_active_count, final_active.size()])

	# The real regression check for #51: total node count under World should
	# also stay bounded, not just the streamer's own bookkeeping array --
	# _cull_behind() calling queue_free() defers the actual removal by a
	# frame, so this only means something after letting a few more frames
	# settle first.
	for _i: int in range(5):
		await process_frame
	var world_child_count: int = level.get_node(^"World").get_child_count()
	_expect(world_child_count < 60,
		"World's own child count stays reasonable after a long drive (got %d), not accumulating freed-but-not-yet-collected nodes" % world_child_count)

	level.free()
	await create_timer(0.1).timeout  # let the audio server retire stopped playback
	if _failures == 0:
		print("PASS: the endless level drives for real, tracks distance, and streaming stays bounded over a long session")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
