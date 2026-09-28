extends SceneTree
## Run without --headless. Saves the main menu plus progress/record overlays.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for i in range(10):
		await process_frame
	await _shot("render_main_menu.png")
	var unlocks: Node = root.get_node(^"UnlockManager")
	unlocks.total_score = 225
	unlocks.successful_deliveries = 3
	unlocks.unlocked = {&"starter_kit": true, &"growing_weight_trap": true, &"noisy_trap": true}
	menu.call(&"_open_progress")
	for i in range(3):
		await process_frame
	await _shot("render_progress.png")
	var run_manager: Node = root.get_node(^"RunManager")
	run_manager.leaderboard = [
		{"score": 640, "mode": &"delivery", "crew_size": 3, "date": "2026-09-26"},
		{"score": 420, "mode": &"delivery", "crew_size": 1, "date": "2026-09-24"},
		{"score": 1880, "mode": &"endless", "crew_size": 2, "date": "2026-09-25"},
	]
	menu.get_node("ProgressPanel").call(&"close")
	menu.call(&"_open_leaderboard")
	for i in range(3):
		await process_frame
	await _shot("render_leaderboard_delivery.png")
	menu.get_node("LeaderboardPanel").call(&"_set_mode", &"endless")
	await process_frame
	await _shot("render_leaderboard_endless.png")
	quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
