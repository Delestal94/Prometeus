extends SceneTree
## Run without --headless. Saves the loading screen (N-407) on its way from the
## menu to the real level: once while loading, once while the level builds,
## and the level right after the cover lifted (textures and materials loaded
## on a thread must look the same as ever under GL Compatibility).


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
	for i in range(6):
		await process_frame
	menu.call(&"_play_solo")
	var loader: LoadingScreen = menu.get(&"_loading")
	loader.tip_key = "UI_LOADING_TIP_EXPLOSIVE"
	loader.minimum_seconds = 2.0
	var shots: Dictionary = {}
	var frames: int = 0
	while is_instance_valid(loader) and frames < 4000:
		await process_frame
		frames += 1
		if not is_instance_valid(loader):
			break
		if not shots.has("loading") and loader.stage == SceneLoader.Stage.LOADING and frames > 20:
			shots["loading"] = true
			await _shot("render_loading_screen.png")
		elif not shots.has("building") and loader.stage == SceneLoader.Stage.SETTLING:
			shots["building"] = true
			await _shot("render_loading_screen_building.png")
	for i in range(20):
		await process_frame
	await _shot("render_loading_screen_level.png")
	# A narrow window: the two cards must not overlap or leave the screen.
	root.size = Vector2i(1024, 600)
	var screen := LoadingScreen.new()
	screen.mode_text = "Crear sala"
	screen.tip_key = "UI_LOADING_TIP_MERIT"
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	var cover := Control.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cover)
	screen.call(&"_build_cover", cover)
	screen.call(&"_show_progress", 0.45, SceneLoader.Stage.LOADING)
	for i in range(6):
		await process_frame
	await _shot("render_loading_screen_narrow.png")
	screen.free()
	quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
