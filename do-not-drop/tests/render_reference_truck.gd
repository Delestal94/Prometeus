extends SceneTree
## Run (needs a GPU, not --headless):
##   Godot --path do-not-drop --script res://tests/render_reference_truck.gd
## Saves review shots of the box truck to user://: 3/4 exterior, the rear
## with doors and ramp out, the loaded rack from the doorway, the aisle from
## the seats, the driver's view, and the cab doors open.

const SHOTS := [
	["exterior", Vector3(6.2, 3.0, -5.8), Vector3(0.0, 1.0, 0.2)],
	["rear_open", Vector3(3.6, 2.4, 10.2), Vector3(0.0, 0.9, 3.4)],
	["rack_from_doorway", Vector3(0.55, 1.75, 5.3), Vector3(-0.45, 0.9, 2.6)],
	["aisle_from_seats", Vector3(0.1, 1.55, 0.3), Vector3(0.1, 0.9, 4.4)],
	["upper_shelf_from_aisle", Vector3(0.45, 1.05, 3.9), Vector3(-0.52, 1.75, 3.2)],
	["highlighted_box", Vector3(0.1, 1.3, 2.9), Vector3(-0.52, 0.8, 2.305)],
	["side_window_outside", Vector3(-3.0, 1.9, -1.2), Vector3(-1.0, 1.55, -1.5)],
	["cab_from_passenger", Vector3(0.45, 1.5, -0.9), Vector3(-0.6, 1.1, -2.0)],
	["cab_through_door", Vector3(-1.9, 1.3, -0.7), Vector3(0.2, 0.9, -1.6)],
	["cab_doors_open", Vector3(-5.2, 2.2, -4.6), Vector3(0.0, 1.0, -1.2)],
]

var _van: VehicleBody3D
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.95)
	env.ambient_light_energy = 0.75
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.light_energy = 1.6
	light.shadow_enabled = true
	world.add_child(light)
	var ground := StaticBody3D.new()
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.47, 0.6, 0.36)
	plane.material = grass
	ground_mesh.mesh = plane
	ground.add_child(ground_mesh)
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(60.0, 1.0, 60.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	world.add_child(ground)
	_van = (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	_van.position.y = 1.0
	world.add_child(_van)
	for tick in range(120):
		await physics_frame
	_van.freeze = true
	await _load_rack(world)
	# One box shown as targeted, and one fold-down seat lowered as if taken.
	var first: Node = get_nodes_in_group(&"cargo")[0]
	first.get_node(^"InteractionArea").call(&"highlight", true)
	var adapter: Node = _van.get_node(^"ReferenceTruck")
	adapter.set_process(false)
	(_van.get_node(^"BodyVisuals/CargoFittings/RackSeat3Fold") as Node3D).rotation.z = 0.0
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.near = 0.03
	world.add_child(_camera)
	await process_frame

	for shot: Array in SHOTS:
		if shot[0] == "cab_doors_open":
			_van.set_door_open(&"cab_left", true)
			_van.set_door_open(&"cab_right", true)
			await create_timer(0.8).timeout
		_camera.global_position = _van.to_global(shot[1])
		_camera.look_at(_van.to_global(shot[2]))
		await _save(shot[0])
	_van.set_door_open(&"cab_left", false)
	_van.set_door_open(&"cab_right", false)
	await create_timer(0.8).timeout
	# The driver's own view, straight through the windshield.
	var eye := _van.get_node(^"CabinInterior/DriverEyePoint") as Node3D
	_camera.global_transform = eye.global_transform
	_camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-6.0))
	await _save("driver_view")
	quit(0)


## One box of each shape (plus a second standard one) resting in the rack.
func _load_rack(world: Node3D) -> void:
	var traps := ["growing_weight", "balance", "fragile", "noisy"]
	var mounts := ["LeftSeat1PackageMount", "RightSeat2PackageMount", "LeftShelfPackageMount", "LeftSeat2PackageMount"]
	for index in range(traps.size()):
		var package := (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate() as RigidBody3D
		package.set(&"trap_definition", load("res://data/traps/%s.tres" % traps[index]))
		package.freeze = true
		world.add_child(package)
		# The trap shape (tall, flat...) is applied a frame after spawning.
		await process_frame
		var marker := _van.get_node(NodePath("CargoBay/" + mounts[index])) as Node3D
		var half: Vector3 = package.call(&"get_half_extents")
		package.global_transform = marker.global_transform.translated_local(Vector3(0.0, half.y - 0.325, 0.0))


func _save(shot_name: String) -> void:
	_camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := "user://truck_%s.png" % shot_name
	image.save_png(path)
	print("RENDER: ", ProjectSettings.globalize_path(path))
