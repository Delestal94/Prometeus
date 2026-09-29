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
	# The frosted glass must follow the card when the window changes size: it
	# used to stay at the card's old spot, a second card behind the real one.
	root.size = root.size + Vector2i(260, 120)
	for i in range(4):
		await process_frame
	if not _frost_matches_card(menu):
		quit(1)
		return
	await _shot("render_main_menu_resized.png")
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


func _frost_matches_card(menu: Node) -> bool:
	var frost := menu.get(&"_frost") as TextureRect
	var card := menu.get(&"_card") as Control
	if frost == null:
		push_error("No frosted card was built.")
		return false
	var rect: Vector4 = (frost.material as ShaderMaterial).get_shader_parameter(&"card_rect")
	var expected := Rect2(card.global_position - frost.global_position, card.size)
	if Rect2(rect.x, rect.y, rect.z, rect.w).is_equal_approx(expected):
		print("Frost follows the card after a resize.")
		return true
	push_error("Frost mask %s, card at %s" % [rect, expected])
	return false
