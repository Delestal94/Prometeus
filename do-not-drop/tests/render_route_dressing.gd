extends SceneTree
## Run without --headless. Saves views of the route dressing under user://:
## a delivery house with its yard, a warning sign as the driver meets it, the
## horizon + clouds from the road, a curve's guardrail and a far landmark.
## The same road every run, so before/after captures of a mood compare the
## same frames (N-317): default seed 7 (a curve sign, a guardrail and open
## road past the depot), -- --seed=N for another.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	var seed_value: int = 7
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
	root.get_node(^"/root/NetworkManager").set(&"world_seed", seed_value)
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

	# From the road itself, well past the depot's gate and its banner (at the
	# van it filled 61 % of the frame, N-317.1): road in the lower middle,
	# horizon across the middle.
	var horizon_view: Array[Vector3] = []
	for metres: float in [70.0, 110.0, 150.0, 200.0, 260.0]:
		horizon_view = _road_view(route, metres)
		if not horizon_view.is_empty() and _open_view(level, horizon_view[0], horizon_view[1]):
			break
	if horizon_view.is_empty():
		horizon_view = [van.global_position + Vector3(0.0, 5.0, -45.0), van.global_position + Vector3(0.0, 8.0, -220.0)]
	await _shot(camera, horizon_view[0], horizon_view[1], "render_route_horizon.png")

	var rail: Node3D = _first(route, "sm_env_prop_guardrail")
	if rail != null:
		await _shot(camera, rail.global_position + (-rail.global_basis.z).normalized() * 9.0 + Vector3.UP * 2.5 + rail.global_basis.x.normalized() * 8.0, rail.global_position + Vector3.UP * 0.5, "render_route_guardrail.png")

	var landmark: Node3D = _first(route, "/landmarks/")
	if landmark != null:
		var toward_road: Vector3 = -landmark.global_basis.z.normalized()
		await _shot(camera, landmark.global_position + toward_road * 42.0 + Vector3.UP * 6.0, landmark.global_position + Vector3.UP * 8.0, "render_route_landmark.png")
	quit()


## [from, at] for a shot down the road `metres` past its start: eye height
## over the road, looking 200 m on along the road's heading, a touch down.
func _road_view(route: Node, metres: float) -> Array[Vector3]:
	var points: Array = route.get(&"_path_points")
	if points.size() < 2:
		return []
	var index: int = 0
	var travelled: float = 0.0
	while index < points.size() - 1 and travelled < metres:
		travelled += (points[index + 1] as Vector3).distance_to(points[index])
		index += 1
	var ahead: int = index
	var run: float = 0.0
	while ahead < points.size() - 1 and run < 25.0:
		run += (points[ahead + 1] as Vector3).distance_to(points[ahead])
		ahead += 1
	var heading: Vector3 = (points[ahead] as Vector3) - (points[index] as Vector3)
	heading.y = 0.0
	if heading.length() < 1.0:
		return []
	var from: Vector3 = (points[index] as Vector3) + Vector3.UP * 4.5
	return [from, from + heading.normalized() * 200.0 + Vector3.DOWN * 9.0]


## Nothing overhead (a tunnel, a bridge) and nothing in the first 25 m of the
## view (a sign, a banner) to fill the frame.
func _open_view(level: Node3D, from: Vector3, at: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var up := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 40.0)
	var forward := PhysicsRayQueryParameters3D.create(from, from + (at - from).normalized() * 25.0)
	return space.intersect_ray(up).is_empty() and space.intersect_ray(forward).is_empty()


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
