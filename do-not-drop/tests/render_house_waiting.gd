extends SceneTree
## Run without --headless. Tareas de Nacho N-501: can you tell from the road
## which house is waiting for a box? Saves, under user://, the first house
## as the driver sees it coming 120 m and 40 m down the road (eye height),
## and its front yard up close. Force the light with the world mood:
##   <godot> --path do-not-drop --script res://tests/render_house_waiting.gd -- --mood=soleado_dia
##   <godot> --path do-not-drop --script res://tests/render_house_waiting.gd -- --mood=soleado_noche
## Files are named after the mood: render_house_waiting_<mood>_{120m,40m,yard}.png
## -- --seed=N picks another road (default 4242, the same for every mood).

const EYE_HEIGHT: float = 2.3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	# The same road every run, so day and night show the same house.
	var seed_value: int = 4242
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
	root.get_node(^"/root/NetworkManager").set(&"world_seed", seed_value)
	var level: Node3D = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	level.get_node("HUD").hide()
	var van: VehicleBody3D = level.vehicle
	van.set_physics_process(false)
	for child in level.get_node("World").get_children():
		if child.is_in_group(&"player"):
			child.hide()
	var route: Node3D = level.get_node("World/Route")
	var camera := Camera3D.new()
	camera.far = 600.0
	camera.fov = 75.0
	level.add_child(camera)
	camera.make_current()
	for _i in range(4):
		await process_frame

	var mood: String = "default"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mood="):
			mood = arg.get_slice("=", 1)
	var houses: Array = route.get(&"houses")
	if houses.is_empty():
		push_error("The route has no house to look at.")
		quit(1)
		return
	var house: Node3D = houses[0]
	var path: Array = route.get(&"_path_points")
	var stop: Vector3 = ((route.get(&"_house_anchors") as Array)[0].cursor as Transform3D).origin
	var stop_index: int = 0
	for index: int in range(path.size()):
		if (path[index] as Vector3).distance_to(stop) < (path[stop_index] as Vector3).distance_to(stop):
			stop_index = index
	for distance: float in [120.0, 40.0]:
		var at: Vector3 = _back_along(path, stop_index, distance)
		await _shot(camera, route.to_global(at) + Vector3.UP * EYE_HEIGHT, house.global_position + Vector3.UP * 1.5, "render_house_waiting_%s_%dm.png" % [mood, int(distance)])
	var front: Vector3 = -house.global_basis.z
	await _shot(camera, house.global_position + front * 9.0 + Vector3.UP * 2.0, house.global_position + front * 3.0 + Vector3.UP * 1.3, "render_house_waiting_%s_yard.png" % mood)
	quit()


## The path point `distance` metres before `index`, along the road.
func _back_along(path: Array, index: int, distance: float) -> Vector3:
	var left: float = distance
	var i: int = index
	while i > 0:
		var step: float = (path[i] as Vector3).distance_to(path[i - 1])
		if step >= left:
			return (path[i] as Vector3).lerp(path[i - 1], left / step)
		left -= step
		i -= 1
	return path[0]


func _shot(camera: Camera3D, from: Vector3, at: Vector3, file_name: String) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)
	for _i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
