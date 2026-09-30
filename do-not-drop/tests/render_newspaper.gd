extends SceneTree
## Run without --headless. Saves the next-day newspaper page (N-606.2) under user://:
## a run with several stories in Spanish and in English, a clean run, and an Endless run.
## Window size: pass --resolution WxH to see other shapes.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	var bus: Node = root.get_node("EventBus")
	var settings: Node = root.get_node("GameSettings")
	var desk: GDScript = load("res://scripts/presentation/newspaper/news_desk.gd")
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
	var long: Array = [_fact("fault_police"), _fact("sheep_hit"), _fact("substituted", 1), _fact("repaired_tape", 0)]
	var endless: Dictionary = {"endless": true, "km": 3.2, "minutes": 4}
	var cases: Array = [
		["busy_es", "es", busy, {}, 12], ["busy_en", "en", busy, {}, 12], ["long_es", "es", long, {}, 3],
		["clean_es", "es", [], {}, 5], ["endless_es", "es", [_fact("endless_end", -1, [], 1)], endless, 5],
	]
	var results: Dictionary = {"delivered": true, "elapsed_seconds": 100.0, "score": 120, "best_score": 500,
			"breakdown": [], "deliveries": []}
	for case: Array in cases:
		settings.call(&"set_language", case[1])
		var context: Dictionary = {"seed": case[4], "town": "San Ceferino del Bache", "km": 1.5, "minutes": 3,
				"crew": crew}
		context.merge(case[3], true)
		bus.newspaper_ready.emit(desk.call(&"compose", case[2], context))
		bus.run_ended.emit(120, results)
		for _i in range(30):
			await process_frame
		await _shot("render_newspaper_%s.png" % case[0])
		hud.newspaper.dismiss()
		hud.overlay.hide()
		hud.overlay_mode = "run"
	quit()


func _fact(kind: String, house: int = -1, tags: Array = [], peer: int = 0) -> Dictionary:
	return {"kind": kind, "house": house, "tags": tags, "peer": peer}


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
