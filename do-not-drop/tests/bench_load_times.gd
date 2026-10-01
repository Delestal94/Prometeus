extends SceneTree
## Load times and memory (tareas de Nacho N-220). Run WITHOUT --headless (the
## loader prefetches models on threads and the first draw compiles shaders:
## only a real window measures what the player waits for):
##   <godot> --path do-not-drop --resolution 1920x1080 --windowed --script res://tests/bench_load_times.gd
## Optional user args: -- --seed=4242 --trips=solo,endless,solo --quality=low|medium|high
##
## Plays the real trip of the menu ("JUGAR" / "Endless" -> LoadingScreen -> the
## level) the way test_menu_to_level.gd does, and prints per trip:
##   - the time from pressing the button to the loader being gone, and how long
##     each SceneLoader stage took (LOADING / BUILDING / SETTLING / DONE);
##   - the frames under the cover: how many took more than 33 ms / 100 ms and the
##     longest one (the freeze the player would see; N-408 brought it to < 0.5 s);
##   - memory at the moment the level is ready: MEMORY_STATIC, RENDER_VIDEO_MEM_USED,
##     OBJECT_COUNT / NODE_COUNT / RESOURCE_COUNT / ORPHAN_NODE_COUNT;
##   - the same after freeing the level and going back to the menu, so what stays
##     behind (the static mesh/material caches, not a leak) shows as a number.
## Before the trips it prints the time from engine start to the menu being drawn.
## Several trips in a row (default solo, endless, solo) show whether going back
## and forth keeps growing the memory (the second solo against the first).
## Everything runs with the preset the options hold (High by default) unless
## --quality= forces another for this run, without saving it.

const MENU: String = "res://scenes/ui/main_menu.tscn"
const TIMEOUT_MSEC: int = 120_000

var _menu: Control = null
var _frames: Array[float] = []
var _stage_ms: Dictionary = {}
var _stage_started: int = 0
var _stage_name: String = ""
## When the cover lifted (stage DONE): ms from the button, and how many frames had passed.
var _lifted_ms: float = 0.0
var _lifted_frames: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("bench_load_times needs a rendering display; omit --headless.")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node(^"/root/NetworkManager").set(&"world_seed", int(_arg("seed", "4242")))
	var quality_arg: String = _arg("quality", "")
	if quality_arg != "":
		var names: Array[String] = ["low", "medium", "high"]
		var wanted: int = names.find(quality_arg.to_lower())
		WorldQuality.apply(self, wanted if wanted >= 0 else int(quality_arg))
	print("LOAD quality=%s window=%s" % [WorldQuality.NAMES[WorldQuality.level], str(DisplayServer.window_get_size())])
	var engine_ms: int = Time.get_ticks_msec()
	var menu_start: int = Time.get_ticks_usec()
	_open_menu()
	await process_frame
	await process_frame
	await process_frame
	var menu_ms: float = (Time.get_ticks_usec() - menu_start) / 1000.0
	print("LOAD menu: engine start to script %d ms, menu built and drawn in %.0f ms " % [engine_ms, menu_ms]
		+ "(engine start to menu on screen: %.0f ms)" % (float(engine_ms) + menu_ms))
	_print_memory("menu")
	for trip: String in _arg("trips", "solo,endless,solo").split(","):
		await _trip(trip)
	quit()


func _open_menu() -> void:
	_menu = load(MENU).instantiate()
	root.add_child(_menu)
	current_scene = _menu
	# A Steam lobby callback must not send this menu somewhere on its own.
	var network: Node = root.get_node(^"/root/NetworkManager")
	if network.is_connected(&"session_ready", Callable(_menu, "_on_session_ready")):
		network.disconnect(&"session_ready", Callable(_menu, "_on_session_ready"))


func _trip(kind: String) -> void:
	_frames.clear()
	_stage_ms.clear()
	_stage_name = "LOADING"
	_lifted_ms = 0.0
	_lifted_frames = -1
	var method: String = "_play_endless" if kind == "endless" else "_play_solo"
	var start: int = Time.get_ticks_usec()
	_stage_started = start
	_menu.call(method)
	var loader: LoadingScreen = _menu.get("_loading")
	if loader == null:
		print("LOAD %s: no loader" % kind)
		return
	loader.stage_changed.connect(func(stage: SceneLoader.Stage) -> void:
		var now: int = Time.get_ticks_usec()
		_stage_ms[_stage_name] = float(_stage_ms.get(_stage_name, 0.0)) + (now - _stage_started) / 1000.0
		_stage_started = now
		_stage_name = SceneLoader.Stage.keys()[stage]
		if stage == SceneLoader.Stage.DONE:
			_lifted_ms = (now - start) / 1000.0
			_lifted_frames = _frames.size())
	var last: int = Time.get_ticks_usec()
	var wall_start: int = Time.get_ticks_msec()
	while is_instance_valid(loader) and Time.get_ticks_msec() - wall_start < TIMEOUT_MSEC:
		await process_frame
		var now: int = Time.get_ticks_usec()
		_frames.append((now - last) / 1000.0)
		last = now
	var total_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	# A few frames with the level running behind the cover gone, for the first
	# frames of play (shaders of what only shows up once the cover lifts).
	var after: Array[float] = []
	for _i: int in range(120):
		await process_frame
		var now: int = Time.get_ticks_usec()
		after.append((now - last) / 1000.0)
		last = now
	var over_33: int = 0
	var over_100: int = 0
	var longest: float = 0.0
	var under_cover: Array[float] = _frames.slice(0, _lifted_frames if _lifted_frames >= 0 else _frames.size())
	for ms: float in under_cover:
		over_33 += 1 if ms > 33.0 else 0
		over_100 += 1 if ms > 100.0 else 0
		longest = maxf(longest, ms)
	var after_longest: float = 0.0
	var after_over_33: int = 0
	for ms: float in after:
		after_longest = maxf(after_longest, ms)
		after_over_33 += 1 if ms > 33.0 else 0
	print("LOAD %s: button to the cover lifting %.0f ms (stages %s); then the loader lingers until %.0f ms "
		% [kind, _lifted_ms, _stage_summary(), total_ms]
		+ "for the music fade; frames under the cover n=%d, >33ms=%d, >100ms=%d, longest=%.0f ms; "
		% [under_cover.size(), over_33, over_100, longest]
		+ "first 120 frames after the loader: >33ms=%d, longest=%.0f ms" % [after_over_33, after_longest])
	_print_memory("%s ready" % kind)
	# Back to the menu: free the level, build the menu again.
	var level: Node = current_scene
	if level != null and level != _menu and is_instance_valid(level):
		level.queue_free()
	if is_instance_valid(_menu):
		_menu.queue_free()
	root.get_node(^"/root/RunManager").call(&"reset_run")
	for _i: int in range(5):
		await process_frame
	_open_menu()
	for _i: int in range(5):
		await process_frame
	_print_memory("back at the menu after %s" % kind)


func _stage_summary() -> String:
	var parts: Array[String] = []
	for key: String in _stage_ms:
		parts.append("%s %.0f ms" % [key, _stage_ms[key]])
	return ", ".join(parts)


func _print_memory(label: String) -> void:
	print("LOAD memory [%s]: static=%.1f MiB video=%.1f MiB texture=%.1f MiB " % [
		label,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0]
		+ "objects=%d nodes=%d resources=%d orphans=%d" % [
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])
