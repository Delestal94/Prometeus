extends SceneTree
## Run with a display (revisor-visual): Godot --path do-not-drop --script res://tests/render_town_delivery.gd
## Captures seeded street/depot with the real truck, the driver's GPS and a
## customer's porch, plus six rack orders, the GPS and a center customer. Output: user://town_delivery_<view>.png.


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
	var depot: Node3D = level.get(&"town").get_node(^"depot_1")
	var lot: Dictionary = depot.get_meta(&"lot")
	var front: Vector2 = (lot.frontage - lot.position).rotated(-float(lot.angle))
	var rack: Node3D = depot.get_node(^"LoadingRack")
	camera.global_position = (
		rack.global_position + depot.global_basis * Vector3(1.5, 2, signf(front.y) * 6)
	)
	camera.look_at(rack.global_position + Vector3(0, 1.2, 0))
	await _shot("six_orders")
	var packages: Array = level.get(&"packages")
	packages[0].get_node(^"InteractionArea").call(&"interact", player)
	vehicle.get_node(^"CargoBay/LeftShelfPackageMount/InteractionArea").call(&"interact", player)
	vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea").call(&"interact", player)
	level.call(&"select_house", 2)
	var driver_camera: Camera3D = vehicle.get_node(
		^"CabinInterior/DriverEyePoint/FirstPersonCamera"
	)
	driver_camera.current = true
	for frame: int in range(10):
		await physics_frame
	await _shot("driver")
	level.call(&"select_house", 3)
	await _shot("center_order_gps")
	level.call(&"select_center")
	await _shot("center_gps")
	level.call(&"select_house", 2)
	player.call(&"leave_seat")
	var houses: Array = level.get(&"houses")
	var house: Node3D = houses[2]
	camera.current = true
	camera.global_position = house.to_global(Vector3(7, 3, -11))
	camera.look_at(house.global_position + Vector3(0, 1.8, 0))
	await _shot("customer")
	house = houses[3]
	level.call(&"select_house", 3)
	player.global_position = house.to_global(Vector3(0, 0, -5))
	player.look_at(
		Vector3(house.global_position.x, player.global_position.y, house.global_position.z)
	)
	camera.global_position = house.to_global(Vector3(8, 5, -14))
	camera.look_at(house.global_position + Vector3(0, 3, 0))
	await _shot("center_customer")
	level.queue_free()
	await process_frame
	quit()


func _shot(title: String) -> void:
	var was_processing: bool = current_scene.is_processing()
	current_scene.call(&"_process", .2)
	current_scene.call(&"_refresh_status")
	current_scene.set_process(false)
	for frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://town_delivery_%s.png" % title
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save town delivery capture: %s" % path)
	print(ProjectSettings.globalize_path(path))
	current_scene.set_process(was_processing)
