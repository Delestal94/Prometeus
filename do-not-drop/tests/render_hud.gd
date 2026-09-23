extends SceneTree
## Run without --headless. Saves the HUD's main states under user://:
## the start card, the in-run dashboard with four boxes (one at risk, one
## lost), and the results card.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	var level: Node3D = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	var hud: Node = level.get_node("HUD")
	for _i in range(8):
		await process_frame
	await _shot("render_hud_start.png")

	hud.call(&"_primary_action")
	var event_bus: Node = root.get_node("EventBus")
	var boxes: Array = [[&"a", "Frágil"], [&"b", "Equilibrio"], [&"c", "Peso creciente"], [&"d", "Ruidoso"]]
	for box: Array in boxes:
		event_bus.cargo_registered.emit(box[0], box[1])
	var run_manager: Node = root.get_node("RunManager")
	run_manager.cargo[&"b"] = {"state": 1, "integrity": 34.0}
	run_manager.cargo[&"d"] = {"state": 2, "integrity": 0.0}
	event_bus.package_integrity_changed.emit(&"b", 34.0, 100.0)
	event_bus.package_integrity_changed.emit(&"d", 0.0, 100.0)
	event_bus.vehicle_telemetry.emit(47.0)
	event_bus.route_progress_changed.emit(0.42, 1180.0, "Camino a casa 2/3")
	event_bus.interaction_prompt_changed.emit("Agarrar paquete")
	event_bus.ping_sent.emit(1, Vector3.ZERO, "¡Cuidado!")
	for _i in range(6):
		await process_frame
	await _shot("render_hud_run.png")

	event_bus.interaction_prompt_changed.emit("")
	event_bus.run_ended.emit(1840, {
		"delivered": true, "reason": "", "elapsed_seconds": 212.4, "cargo_points": 900,
		"time_bonus": 340, "delivery_points": 600, "chaos_multiplier": 1.5,
		"houses_delivered": 2, "houses_missed": 1, "cargo_total": 1, "cargo_intact": 1,
		"cargo_ruined": 0, "is_new_best": true, "best_score": 1840,
		"complaints": [{"house": 1, "dismissed": true}],
	})
	for _i in range(6):
		await process_frame
	await _shot("render_hud_results.png")
	quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
