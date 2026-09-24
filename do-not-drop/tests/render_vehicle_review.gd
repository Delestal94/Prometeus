extends SceneTree
## Run without --headless. Saves front/rear rendered views under user://.


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
	level.get_node("HUD").hide()
	var van: VehicleBody3D = level.vehicle
	van.set_physics_process(false)
	van.get_node("VehicleInputComponent").set_physics_process(false)
	van.presentation_engine_running = true
	van.steering = -0.3
	van.presentation_braking = true
	var visual: Node = van.get_node("VehiclePresentation")
	visual.audio_enabled = false
	for child in level.get_node("World").get_children():
		if child.is_in_group(&"player"):
			child.hide()
	var camera := Camera3D.new()
	level.add_child(camera)
	camera.fov = 58.0
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var views: Dictionary = {
		"front": Vector3(-5.8, 3.7, -7.0),
		"rear": Vector3(5.5, 3.0, 6.8),
		"driver": van.get_node("CabinInterior/DriverEyePoint").global_position,
	}
	for view: String in views:
		camera.global_position = views[view]
		camera.look_at(van.global_position + Vector3(0, 0.4, 0))
		if view == "driver":
			camera.look_at(van.global_position + Vector3(-0.45, 0.7, -2.2))
		await process_frame
		await RenderingServer.frame_post_draw
		var output: String = "user://review_vehicle_%s.png" % view
		var result: Error = root.get_texture().get_image().save_png(output)
		if result != OK:
			push_error("Screenshot failed: %s" % output)
			quit(1)
			return
		print("RENDER: ", ProjectSettings.globalize_path(output))
	level.free()
	await process_frame
	quit(0)
