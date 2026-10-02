extends SceneTree
## Run without --headless. Saves the next-day newspaper scene (N-606.3) under
## user://render_newspaper_scene/ (or --out=<absolute dir>): one image per shot
## of a busy run in Spanish (office, approach, spread, each story's close-up,
## spread again, reaction), the results that follow, a skip hint, and the
## front close-up of the same paper in English and of a clean run.
## Window size: pass --resolution WxH to see other shapes.

const DESK: GDScript = preload("res://scripts/presentation/newspaper/news_desk.gd")

var out_dir: String = "user://render_newspaper_scene"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bus: Node = root.get_node("EventBus")
	var settings: Node = root.get_node("GameSettings")
	settings.set(&"newspaper_mode", 0)
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	for _i in range(4):
		await process_frame
	hud.pause.primary_action()
	var crew: Array = [{"peer": 1, "nick": "Turbo"}, {"peer": 2, "nick": ""}, {"peer": 3, "nick": "Manos de Manteca"}]
	var busy: Array = [
		_fact("deer_hit", -1, [], 1), _fact("missed", 1, ["cake"]), _fact("abandoned", 0, ["hen", "noisy"]),
		_fact("fault_mirror"), _fact("delivered_ruined", 2, ["vase"]), _fact("photo", 2),
	]
	var context: Dictionary = {"seed": 12, "town": "San Ceferino del Bache", "km": 1.5, "minutes": 3, "crew": crew}
	var results: Dictionary = {"delivered": true, "elapsed_seconds": 100.0, "score": 120, "best_score": 500,
			"cargo_total": 5, "cargo_intact": 3, "houses_delivered": 3, "houses_missed": 2, "breakdown": [],
			"deliveries": []}
	var paper: Dictionary = DESK.compose(busy, context)

	# Every shot of the busy run, in Spanish.
	settings.call(&"set_language", "es")
	var director: Control = await _open(bus, hud, paper, results)
	var timeline: Array = director.get("timeline")
	var duration: float = director.get("duration")
	for index: int in timeline.size():
		var shot: Dictionary = timeline[index]
		var at: float = float(shot["start"]) + float(shot["seconds"]) * (0.5 if shot["id"] in ["office", "approach"] else 0.97)
		await _seek(director, at)
		await _shot("%02d_%s" % [index + 1, shot["id"]])
		if shot["id"] == "spread":
			director.call(&"_input", _action(&"interact", true))
			await _seek(director, float(director.get("time")) + 0.3)
			await _shot("%02d_skip_hint" % (timeline.size() + 1))
			director.call(&"_input", _action(&"interact", false))
	await _seek(director, duration + 0.2)
	for _i in range(6):
		await process_frame
	await _shot("%02d_results" % (timeline.size() + 2))
	_close_results(hud)

	# The same paper in English, and a clean run: the front close-up.
	for case: Array in [["en", paper, "front_en"], ["es", DESK.compose([], context), "front_clean"]]:
		settings.call(&"set_language", case[0])
		director = await _open(bus, hud, case[1], results)
		for shot: Dictionary in director.get("timeline"):
			if shot["id"] == "front":
				await _seek(director, float(shot["start"]) + float(shot["seconds"]) - 0.1)
		await _shot(case[2])
		hud.newspaper.dismiss()
		_close_results(hud)
	settings.call(&"set_language", "es")
	print("Saved to ", ProjectSettings.globalize_path(out_dir))
	quit()


func _open(bus: Node, hud: CanvasLayer, paper: Dictionary, results: Dictionary) -> Control:
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	for _i in range(8):
		await process_frame
	return hud.newspaper.director


## Jumps the scene's clock to `at` seconds as if it had played up to there.
func _seek(director: Control, at: float) -> void:
	# Driven by hand only: the captures take real frames, which mustn't move the clock.
	if is_instance_valid(director):
		director.set_process(false)
	while is_instance_valid(director) and not bool(director.get("done")) and float(director.get("time")) < at:
		director.call(&"_process", minf(0.1, at - float(director.get("time"))))
	await process_frame


func _shot(file_name: String) -> void:
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = out_dir.path_join(file_name + ".png")
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))


func _fact(kind: String, house: int = -1, tags: Array = [], peer: int = 0) -> Dictionary:
	return {"kind": kind, "house": house, "tags": tags, "peer": peer}


func _action(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _close_results(hud: CanvasLayer) -> void:
	hud.overlay.hide()
	hud.overlay_mode = "run"
