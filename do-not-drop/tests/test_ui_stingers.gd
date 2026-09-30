extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ui_stingers.gd
##
## S-403: the six musical stingers of ui_sounds.gd (perfect delivery, delivery
## with losses, new record, unlock, route event won, route event failed).
##   - each is a synthesized 2-4 s clip, non-silent, peak-normalised well
##     below clipping, and distinct from the others; the eight short UI cues
##     stay exactly as they were;
##   - they play through ONE root-level player on the Music bus, so a new
##     stinger replaces the one still ringing instead of stacking;
##   - UiSounds.result_stinger() picks RECORD over everything, PERFECT when
##     nothing was lost, LOSSES otherwise (hud_results.gd plays that pick);
##   - a route event resolving while the run is over (the run's end closes it as
##     failed) plays nothing, so it does not clash with the result stinger; the
##     unlock stinger is queued behind the result one (hud_notices.gd), even
##     when two unlocks arrive in the same frame; event stingers wait a moment
##     and stay silent if the run ended meanwhile (a client's relayed close);
##   - warm_stingers() fills the cache from a worker thread.

const UiSounds = preload("res://scripts/ui/ui_sounds.gd")
const MAX_PEAK: float = 0.708  # -3 dBFS

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_warm()
	_test_streams()
	_test_single_music_player()
	_test_result_choice()
	await _test_hud_triggers()
	if _failures == 0:
		print("PASS: six distinct 2-4 s stingers on one Music-bus player, result choice and HUD triggers work")
	quit(_failures)


func _test_warm() -> void:
	UiSounds._stinger_cache.clear()
	UiSounds.warm_stingers()
	var deadline: int = Time.get_ticks_msec() + 5000
	while UiSounds._stinger_cache.size() < UiSounds.STINGERS.size() and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(UiSounds._stinger_cache.size() == UiSounds.STINGERS.size(),
			"warm_stingers() builds all six off the main thread (got %d)" % UiSounds._stinger_cache.size())


func _test_streams() -> void:
	_expect(UiSounds.STINGERS.size() == 6, "Six stingers are declared (got %d)" % UiSounds.STINGERS.size())
	_expect(UiSounds.CUES.size() == 8, "The short UI cues are untouched (got %d)" % UiSounds.CUES.size())
	for id: StringName in UiSounds.STINGERS:
		_expect(not UiSounds.CUES.has(id), "%s is not one of the short SFX cues" % id)
		var stream: AudioStreamWAV = UiSounds.stinger_stream(id)
		_expect(stream != null, "%s has a stream" % id)
		if stream == null:
			continue
		_expect(stream == UiSounds.stinger_stream(id), "%s is built once and cached" % id)
		var duration: float = UiSounds.stinger_duration(id)
		_expect(duration >= 2.0 and duration <= 4.0, "%s lasts 2-4 s (got %.2f)" % [id, duration])
		var peak: float = _peak(stream)
		_expect(peak > 0.1, "%s is not silence (peak %.3f)" % [id, peak])
		_expect(peak <= MAX_PEAK, "%s peaks at or below -3 dBFS (got %.3f)" % [id, peak])
		_expect(_edge_level(stream) < 0.02, "%s starts and ends without a click (edge %.4f)" % [id,
				_edge_level(stream)])
		_expect(UiSounds.stinger_volume_db(id) <= 0.0, "%s is not boosted (got %.1f dB)" % [id,
				UiSounds.stinger_volume_db(id)])
	var hashes: Dictionary = {}
	for id: StringName in UiSounds.STINGERS:
		hashes[UiSounds.stinger_stream(id).data.hex_encode().sha256_text()] = true
	_expect(hashes.size() == UiSounds.STINGERS.size(),
			"Every stinger is its own phrase (%d distinct)" % hashes.size())
	_expect(UiSounds.stinger_stream(&"nope") == null and UiSounds.stinger_duration(&"nope") == 0.0,
			"An unknown stinger id yields nothing")
	_expect(UiSounds.play_stinger(root, &"nope") == null, "Playing an unknown stinger id does nothing")


func _test_single_music_player() -> void:
	_expect(AudioServer.get_bus_index(&"Music") >= 0, "The Music bus exists in the layout")
	var first: AudioStreamPlayer = UiSounds.play_stinger(root, UiSounds.STINGER_PERFECT)
	_expect(first != null and first.bus == &"Music", "A stinger plays on the Music bus")
	_expect(first != null and first.playing and first.stream == UiSounds.stinger_stream(UiSounds.STINGER_PERFECT),
			"The perfect stinger is playing")
	_expect(first != null and first.process_mode == Node.PROCESS_MODE_ALWAYS,
			"The stinger player keeps playing while the tree is paused")
	var second: AudioStreamPlayer = UiSounds.play_stinger(root, UiSounds.STINGER_LOSSES)
	_expect(second == first, "A second stinger reuses the same player instead of stacking")
	_expect(second != null and second.stream == UiSounds.stinger_stream(UiSounds.STINGER_LOSSES),
			"...and replaces what was ringing")
	var count: int = 0
	for child: Node in root.get_children():
		if child is AudioStreamPlayer and String(child.name).begins_with(UiSounds.STINGER_PLAYER_NAME):
			count += 1
	_expect(count == 1, "Exactly one stinger player lives at the root (got %d)" % count)
	_expect(UiSounds.stinger_player(root) == first, "stinger_player() finds it")
	first.stop()


func _test_result_choice() -> void:
	var clean: Dictionary = {"delivered": true, "cargo_total": 3, "cargo_intact": 3, "cargo_ruined": 0,
			"houses_delivered": 3, "houses_missed": 0, "houses_lost": 0,
			"deliveries": [{"outcome": &"delivered_ok"}, {"outcome": &"delivered_at_risk"}]}
	_expect(UiSounds.result_stinger(clean, false) == UiSounds.STINGER_PERFECT, "Nothing lost is a perfect delivery")
	_expect(UiSounds.result_stinger(clean, true) == UiSounds.STINGER_RECORD, "A new record beats a perfect delivery")
	var ruined: Dictionary = clean.duplicate(true)
	ruined["cargo_ruined"] = 1
	_expect(UiSounds.result_stinger(ruined, false) == UiSounds.STINGER_LOSSES, "A ruined box plays the losses stinger")
	_expect(UiSounds.result_stinger(ruined, true) == UiSounds.STINGER_RECORD, "A new record beats the losses too")
	var missed: Dictionary = clean.duplicate(true)
	missed["houses_missed"] = 1
	_expect(UiSounds.result_stinger(missed, false) == UiSounds.STINGER_LOSSES, "A missed door counts as a loss")
	var left_on_road: Dictionary = clean.duplicate(true)
	left_on_road["houses_lost"] = 1
	_expect(UiSounds.result_stinger(left_on_road, false) == UiSounds.STINGER_LOSSES,
			"A box left on the road counts as a loss")
	var bad_row: Dictionary = clean.duplicate(true)
	bad_row["deliveries"] = [{"outcome": &"delivered_ruined"}]
	_expect(UiSounds.result_stinger(bad_row, false) == UiSounds.STINGER_LOSSES,
			"A delivery row that arrived ruined counts as a loss")
	_expect(UiSounds.result_stinger({"delivered": false, "reason": "x"}, false) == UiSounds.STINGER_LOSSES,
			"A failed run plays the losses stinger")
	var endless: Dictionary = {"distance_traveled": 300.0, "cargo_ruined": 0}
	_expect(UiSounds.result_stinger(endless, false) == UiSounds.STINGER_PERFECT,
			"Endless with every box alive is perfect")
	endless["cargo_ruined"] = 2
	_expect(UiSounds.result_stinger(endless, false) == UiSounds.STINGER_LOSSES, "Endless with ruined boxes is losses")
	_expect(UiSounds.result_stinger({}, false) == UiSounds.STINGER_LOSSES, "An empty result is not a perfect one")


func _test_hud_triggers() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var run_manager: Node = root.get_node(^"/root/RunManager")
	var events: Dictionary = root.get_node(^"/root/RouteEventManager").EVENTS
	var event_id: StringName = StringName(events.keys()[0])
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var was_running: bool = bool(run_manager.is_running)

	# The results screen plays the pick of result_stinger().
	_silence()
	hud.results._on_ended(400, {"delivered": true, "cargo_total": 1, "cargo_intact": 1, "cargo_ruined": 0,
			"is_new_best": false, "best_score": 900})
	_expect(_current() == UiSounds.stinger_stream(UiSounds.STINGER_PERFECT), "The results screen plays PERFECT")
	_silence()
	hud.results._on_ended(400, {"delivered": true, "cargo_total": 1, "cargo_ruined": 1, "is_new_best": false,
			"best_score": 900})
	_expect(_current() == UiSounds.stinger_stream(UiSounds.STINGER_LOSSES), "...LOSSES when a box was ruined")
	_silence()
	hud.results._on_ended(1200, {"delivered": true, "cargo_total": 1, "cargo_ruined": 1, "is_new_best": true,
			"best_score": 1200})
	_expect(_current() == UiSounds.stinger_stream(UiSounds.STINGER_RECORD), "...RECORD over the losses on a new best")
	_silence()

	# A route event resolving after the run ended stays silent...
	var delay: float = hud.notices.EVENT_STINGER_DELAY + 0.1
	run_manager.is_running = false
	bus.route_event_resolved.emit(event_id, false, 0)
	await create_timer(delay).timeout
	_expect(_current() == null, "An event closed at the run's end plays no stinger")
	# ...and so does one whose run ends before the delay (a client gets the
	# host's relayed close just before its own run_ended)...
	run_manager.is_running = true
	bus.route_event_resolved.emit(event_id, false, 0)
	run_manager.is_running = false
	await create_timer(delay).timeout
	_expect(_current() == null, "An event closed right before run_ended plays no stinger")
	# ...while one resolved mid-run gets its own.
	run_manager.is_running = true
	bus.route_event_resolved.emit(event_id, true, 1)
	await create_timer(delay).timeout
	_expect(_current() == UiSounds.stinger_stream(UiSounds.STINGER_EVENT_WON), "A resolved event plays EVENT_WON")
	bus.route_event_resolved.emit(event_id, false, 1)
	await create_timer(delay).timeout
	_expect(_current() == UiSounds.stinger_stream(UiSounds.STINGER_EVENT_FAILED), "A failed event plays EVENT_FAILED")
	run_manager.is_running = false
	_silence()

	# Unlock waits for the result stinger that follows it in the same frame.
	# Two unlocks in the same run_ended share the single queue slot.
	bus.unlock_earned.emit(&"starter_kit", "Kit")
	bus.unlock_earned.emit(&"starter_kit", "Kit")
	hud.results._on_ended(400, {"delivered": true, "cargo_total": 1, "cargo_ruined": 0, "is_new_best": false})
	await process_frame
	await process_frame
	var player: AudioStreamPlayer = UiSounds.stinger_player(root)
	_expect(player != null and player.stream == UiSounds.stinger_stream(UiSounds.STINGER_PERFECT),
			"The unlock stinger does not cut the result stinger")
	_expect(player != null and StringName(player.get_meta(UiSounds.STINGER_QUEUED_META, &""))
			== UiSounds.STINGER_UNLOCK, "...it waits queued behind it")
	# With nothing ringing, the unlock stinger plays on its own.
	_silence()
	UiSounds.queue_stinger(root, UiSounds.STINGER_UNLOCK)
	await process_frame
	await process_frame
	_expect(_current() == UiSounds.stinger_stream(UiSounds.STINGER_UNLOCK) and player.playing,
			"An unlock on its own plays right away")

	run_manager.is_running = was_running
	_silence()
	hud.queue_free()
	await process_frame


## Stops the shared player and forgets its stream, so the next check reads
## only what happened after this call.
func _silence() -> void:
	var player: AudioStreamPlayer = UiSounds.stinger_player(root)
	if player != null:
		player.stop()
		player.stream = null
		if player.has_meta(UiSounds.STINGER_QUEUED_META):
			player.remove_meta(UiSounds.STINGER_QUEUED_META)


func _current() -> AudioStream:
	var player: AudioStreamPlayer = UiSounds.stinger_player(root)
	return null if player == null else player.stream


func _peak(stream: AudioStreamWAV) -> float:
	var peak: float = 0.0
	for index: int in range(stream.data.size() / 2):
		peak = maxf(peak, absf(stream.data.decode_s16(index * 2)) / 32768.0)
	return peak


func _edge_level(stream: AudioStreamWAV) -> float:
	var last: int = stream.data.size() / 2 - 1
	return maxf(absf(stream.data.decode_s16(0)), absf(stream.data.decode_s16(last * 2))) / 32768.0


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
