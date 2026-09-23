extends SceneTree
## Run without --headless. Saves views of the route dressing under user://:
## a delivery house with its yard, a warning sign as the driver meets it, the
## horizon + clouds from the road, a curve's guardrail and a far landmark.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	var level: Node3D = load("res://scenes/gameplay/level_base.tscn").instantiate()
	# Keep every placed piece a node, so the shots below can find a guardrail
	# or a landmark by its model file (batched, they'd be MultiMesh instances).
	level.get_node(^"World/Route").set(&"batch_dressing", false)
	root.add_child(level)
	current_scene = level
	level.get_node("HUD").hide()
	var van: VehicleBody3D = level.vehicle
	van.set_physics_process(false)
	van.get_node("VehicleInputComponent").set_physics_process(false)
	for child in level.get_node("World").get_children():
		if child.is_in_group(&"player"):
			child.hide()
	var route: Node3D = level.get_node("World/Route")
	var camera := Camera3D.new()
	camera.far = 600.0
	level.add_child(camera)
	camera.make_current()
	for _i in range(4):
		await process_frame

	var house: Node3D = route.get(&"houses")[0]
	var house_front: Vector3 = -house.global_basis.z
	await _shot(camera, house.global_position + house_front * 17.0 + Vector3.UP * 3.2, house.global_position + Vector3.UP * 1.6, "render_route_house.png")

	var sign_node: Node3D = _first(route, "/signs/sm_env_sign_curve")
	if sign_node == null:
		sign_node = _first(route, "/signs/")
	if sign_node != null:
		var facing: Vector3 = -sign_node.global_basis.z.normalized()
		await _shot(camera, sign_node.global_position + facing * 9.0 + Vector3.UP * 1.9 - sign_node.global_basis.x.normalized() * 3.0, sign_node.global_position + Vector3.UP * 2.0, "render_route_sign.png")

	await _shot(camera, van.global_position + Vector3(0.0, 4.0, -6.0), van.global_position + Vector3(0.0, 14.0, -120.0), "render_route_horizon.png")

	var rail: Node3D = _first(route, "sm_env_prop_guardrail")
	if rail != null:
		await _shot(camera, rail.global_position + (-rail.global_basis.z).normalized() * 9.0 + Vector3.UP * 2.5 + rail.global_basis.x.normalized() * 8.0, rail.global_position + Vector3.UP * 0.5, "render_route_guardrail.png")

	var landmark: Node3D = _first(route, "/landmarks/")
	if landmark != null:
		var toward_road: Vector3 = -landmark.global_basis.z.normalized()
		await _shot(camera, landmark.global_position + toward_road * 42.0 + Vector3.UP * 6.0, landmark.global_position + Vector3.UP * 8.0, "render_route_landmark.png")
	quit()


func _first(route: Node, fragment: String) -> Node3D:
	for node: Node in route.find_children("*", "Node3D", true, false):
		if node.scene_file_path.contains(fragment):
			return node as Node3D
	return null


func _shot(camera: Camera3D, from: Vector3, at: Vector3, file_name: String) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)
	for _i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
