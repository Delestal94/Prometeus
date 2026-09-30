extends SceneTree
## Run without --headless. Tareas de Nacho N-116: the base at the end of the
## route. Saves, under user://, the shots to judge it by day and by night --
## force the light with the world mood:
##   <godot> --path do-not-drop --script res://tests/render_goal_lot.gd -- --mood=soleado_dia
##   <godot> --path do-not-drop --script res://tests/render_goal_lot.gd -- --mood=soleado_noche
## Files are named after the mood: render_goal_lot_<mood>_<shot>.png
##   approach   from the road 90 m out, at the driver's eye: is the base and its
##              sign readable, the gate up
##   gate       at the gate, looking in: the free bay, its number and arrow
##   bay        from the driver's seat on the way in, the free bay ahead
##   overview   high over the lot, from the gate: bays, trucks, workers, hose
##   unloading  the unloading truck, the cart and the workers up close
##   parked     the results shot: the truck parked in the bay, the sign behind
## -- --seed=N picks another road (default 4242, the same for every mood).

const EYE_HEIGHT: float = 2.3
const SpectatorCameraScript = preload("res://scripts/presentation/spectator_camera.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	var seed_value: int = 4242
	var mood: String = "default"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--mood="):
			mood = arg.get_slice("=", 1)
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
	var lot: RouteGoalLot = route.get(&"goal_lot")
	var camera := Camera3D.new()
	camera.far = 600.0
	camera.fov = 75.0
	level.add_child(camera)
	camera.make_current()
	for _i in range(4):
		await process_frame
	if lot == null:
		push_error("The route has no goal lot.")
		quit(1)
		return

	var forward: Vector3 = -lot.global_basis.z
	var gate: Vector3 = lot.to_global(Vector3(0.0, 0.0, RouteGoalLot.FRONT_Z))
	var bay: Vector3 = lot.bay_centre()
	lot.open_gate()
	# The barrier takes a moment to swing clear.
	await create_timer(1.3).timeout
	# The approach follows the real road back from the gate (it bends): a
	# straight line back from the gate ends up in a field.
	var path: Array = route.get(&"_path_points")
	var gate_index: int = 0
	for index: int in range(path.size()):
		if (path[index] as Vector3).distance_to(route.to_local(lot.position)) < 1.0:
			gate_index = index
			break
	for distance: float in [90.0, 30.0]:
		var from: Vector3 = route.to_global(_back_along(path, gate_index, distance))
		await _shot(camera, from + Vector3.UP * EYE_HEIGHT, gate + forward * 14.0 + Vector3.UP * 4.0, mood,
				"approach" if distance > 50.0 else "approach_near")
	await _shot(camera, gate - forward * 12.0 + Vector3.UP * EYE_HEIGHT, bay + Vector3.UP * 2.0, mood, "gate")
	await _shot(camera, lot.to_global(Vector3(0.0, 0.0, -10.0)) + Vector3.UP * EYE_HEIGHT, bay + Vector3.UP * 1.0, mood,
			"bay")
	await _shot(camera, gate + Vector3.UP * 16.0 - forward * 4.0, lot.to_global(Vector3(0.0, 0.0, -22.0)), mood,
			"overview")
	var side: float = lot.unload_side
	await _shot(camera, lot.to_global(Vector3(side * 9.5, 1.7, -3.0)), lot.to_global(Vector3(side * 15.4, 1.2, -8.0)),
			mood, "unloading")
	# The results shot: the truck in the bay, the camera as results_orbit.gd puts it.
	van.global_transform = lot.parking_pose()
	van.linear_velocity = Vector3.ZERO
	await process_frame
	var orbit: Camera3D = SpectatorCameraScript.orbit_results(van)
	for _i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://render_goal_lot_%s_parked.png" % mood)
	print("Saved ", ProjectSettings.globalize_path("user://render_goal_lot_%s_parked.png" % mood))
	orbit.queue_free()
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


func _shot(camera: Camera3D, from: Vector3, at: Vector3, mood: String, shot: String) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)
	for _i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://render_goal_lot_%s_%s.png" % [mood, shot]
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
