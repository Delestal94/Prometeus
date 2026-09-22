extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("NetworkManager").world_seed = 12345
	var level: Node3D = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	level.get_node("HUD")._primary_action()
	for i: int in range(60):
		await physics_frame
	level.get_node("HUD").hide()
	var camera := Camera3D.new()
	level.add_child(camera)
	camera.fov = 72.0
	camera.cull_mask &= ~4
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var route: Node3D = level.get_node("World/Route")
	var views: Array[Dictionary] = [
		{"name": "start", "eye": Vector3(8.0, 1.7, 8.0), "target": Vector3(0.0, 1.0, -24.0)},
		{"name": "relief", "eye": route._path_points[30] + Vector3(12.0, 9.0, 10.0), "target": route._path_points[33]},
		{"name": "house", "eye": route.houses[0].position + Vector3(8.0, 4.0, 9.0), "target": route.houses[0].position + Vector3(0.0, 1.2, 0.0)},
	]
	for view: Dictionary in views:
		camera.global_position = view.eye
		camera.look_at(view.target)
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "user://terrain_%s.png" % view.name
		root.get_texture().get_image().save_png(path)
		print("RENDER: ", ProjectSettings.globalize_path(path))
	level.free()
	quit()
