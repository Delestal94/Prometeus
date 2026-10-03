extends SceneTree
## Run with a display (revisor-visual): Godot --path do-not-drop --script res://tests/render_town_delivery.gd
## Captures seeded street/depot with the real truck, the driver's GPS and a
## customer's porch. Output: user://town_delivery_<view>.png.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Town delivery visual review needs a display")
		quit(2)
		return
	var scene: PackedScene = load("res://scenes/gameplay/town/town_delivery.tscn")
	var level: Node3D = scene.instantiate()
	level.set(&"world_seed", 4242)
	root.add_child(level)
	current_scene = level
	for frame: int in range(20):
		await physics_frame
	var vehicle: Node3D = level.get(&"vehicle")
	var player: Node3D = level.get(&"local_player")
	var camera := Camera3D.new()
	camera.far = 1000
	camera.near = .1
	level.add_child(camera)
	camera.current = true
	camera.global_position = vehicle.to_global(Vector3(-13, 9, 14))
	camera.look_at(vehicle.global_position + Vector3(0, 1, 0))
	await _shot("depot")
	var packages: Array = level.get(&"packages")
	packages[0].get_node(^"InteractionArea").call(&"interact", player)
	vehicle.get_node(^"CargoBay/LeftShelfPackageMount/InteractionArea").call(&"interact", player)
	vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea").call(&"interact", player)
	level.call(&"select_house", 2)
	var driver_camera: Camera3D = vehicle.get_node(^"CabinInterior/DriverEyePoint/FirstPersonCamera")
	driver_camera.current = true
	for frame: int in range(10):
		await physics_frame
	await _shot("driver")
	player.call(&"leave_seat")
	var houses: Array = level.get(&"houses")
	var house: Node3D = houses[2]
	camera.current = true
	camera.global_position = house.to_global(Vector3(7, 3, -11))
	camera.look_at(house.global_position + Vector3(0, 1.8, 0))
	await _shot("customer")
	level.queue_free()
	await process_frame
	quit()


func _shot(title: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://town_delivery_%s.png" % title
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save town delivery capture: %s" % path)
	print(ProjectSettings.globalize_path(path))
