extends SceneTree
## Run without --headless. Saves the main menu as user://render_main_menu.png.


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
	await RenderingServer.frame_post_draw
	var path: String = "user://render_main_menu.png"
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
	quit()
