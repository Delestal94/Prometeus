extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_endless_physics_spike.gd
##
## N-219: the physics tick that spawned an Endless segment used to take up to
## ~100 ms (a bridge 35-90 ms, a tunnel 25 ms). Guards the three causes:
## - RouteSegment._model() keeps each model's PackedScene: a bridge made ~40
##   load()s from disk per spawn (route_segment.gd).
## - RouteStreamer warms those models and the river loop while the level loads,
##   so the first bridge does not read/synthesize them (route_streamer.gd).
## - SegmentStreamer merges a segment's boxes one tick after building it, never
##   in the same one, and is back to nothing pending a tick later
##   (segment_streamer.gd, flush_batches()).
## Plus a loose wall-clock ceiling on building the heavy segments once warm
## (measured ~3-5 ms, limit 30 ms so a busy machine does not flake).

const DRIVE_METRES: float = 600.0
const STEP_METRES: float = 0.4
const BUILD_CEILING_MS: float = 30.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	var streamer := RouteStreamer.new()
	root.add_child(streamer)
	var target := Node3D.new()
	root.add_child(target)

	# Warm-up: nothing the pool's segments instance is left to load at spawn.
	var scenes: Dictionary = RouteSegment._scenes
	for path: String in RouteStreamer.WARM_MODELS:
		_expect(ResourceLoader.exists(path), "WARM_MODELS lists a model that exists: " + path)
		_expect(scenes.has(path), "The model is loaded while the level builds: " + path)
	var before: AudioStreamWAV = SynthAudio.river_flow_loop()
	_expect(before != null and SynthAudio.river_flow_loop() == before, "The river loop is already cached")

	# Heavy segments built warm, twice each: the second one must not be slower
	# than the ceiling either (it used to be the cheap one, and is now both).
	var heavy: Array[Script] = [NarrowBridgeSegment, TunnelSegment, ConstructionZoneSegment, ChicaneSegment]
	for script: Script in heavy:
		for round_index: int in range(2):
			var segment: RouteSegment = script.new()
			var started: int = Time.get_ticks_usec()
			streamer.add_child(segment)
			var ms: float = (Time.get_ticks_usec() - started) / 1000.0
			_expect(ms < BUILD_CEILING_MS, "%s builds in %.1f ms (ceiling %.0f)"
					% [script.get_global_name(), ms, BUILD_CEILING_MS])
			segment.queue_free()
	await process_frame

	# The bridge's scene is the same object every time it is asked for.
	var deck: String = NarrowBridgeSegment.DECK_MODEL
	_expect(scenes.get(deck) == RouteSegment._scene(deck), "A model's PackedScene is kept, not reloaded")

	# Build and merge never share a tick, and nothing stays pending.
	streamer.start(target)
	_expect((streamer.get(&"_unbatched") as Array).is_empty(), "start() leaves every starting segment merged")
	var spawns: int = 0
	var worst_pending: int = 0
	var ridden: float = 0.0
	var both_in_one_tick: int = 0
	var stuck_pending: int = 0
	var pending_since_spawn: int = 0
	while ridden < DRIVE_METRES:
		ridden += STEP_METRES
		target.global_position = streamer.point_at(ridden)
		var spawned_before: int = int(streamer.get(&"_spawn_count"))
		var pending_before: int = (streamer.get(&"_unbatched") as Array).size()
		streamer.call(&"_physics_process", 1.0 / 60.0)
		var pending_after: int = (streamer.get(&"_unbatched") as Array).size()
		var spawned: bool = int(streamer.get(&"_spawn_count")) > spawned_before
		if spawned:
			spawns += 1
			if pending_after < pending_before + 1:
				both_in_one_tick += 1  # a segment was merged in the tick that built one
		worst_pending = maxi(worst_pending, pending_after)
		pending_since_spawn = 0 if pending_after == 0 else pending_since_spawn + 1
		stuck_pending = maxi(stuck_pending, pending_since_spawn)
		await process_frame
	_expect(spawns >= 5, "The drive spawned segments (%d)" % spawns)
	_expect(both_in_one_tick == 0, "No tick both builds a segment and merges one (%d did)" % both_in_one_tick)
	_expect(worst_pending <= 2, "At most 2 segments wait for their merge (%d)" % worst_pending)
	_expect(stuck_pending <= 3, "A spawn's merge is done within 3 ticks (%d pending in a row)" % stuck_pending)

	# flush_batches() empties the queue; a culled segment leaves it.
	streamer.call(&"_spawn_next")
	streamer.call(&"_spawn_next")
	_expect((streamer.get(&"_unbatched") as Array).size() >= 2, "Fresh segments wait to be merged")
	streamer.call(&"flush_batches")
	_expect((streamer.get(&"_unbatched") as Array).is_empty(), "flush_batches() merges everything pending")

	network.set(&"world_seed", 0)
	if _failures == 0:
		print("PASS: Endless segment spawns keep their models warm and merge a tick after they build")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
