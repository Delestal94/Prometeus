extends SceneTree
## Run (needs a GPU, not --headless):
##   Godot --path do-not-drop --script res://tests/render_cargo_animals.gd
## Review shots of the animals that go for the cargo (N-109): from behind the
## truck, through the open rear doors, the gull swooping in and on the box, the
## dog on the open box with its "throw a stick" prompt, and the bees round the
## cake, each with its icon. Saved to user://cargo_animals_*.png; the camera
## follows the box (_frame_camera).
##
## The director is driven by hand (advance()) with a forced plan, the same way
## test_cargo_animals.gd does, so each shot is the moment named.

var _level: Node
var _animals: Node
var _view: Node
var _vehicle: RigidBody3D
var _package: Node
var _camera: Camera3D
## How fast the truck counts as going while the director is ticked; it never
## really moves, so the box stays on its rack.
var _speed_mps: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(_level)
	current_scene = _level
	await process_frame
	var player: Node = _level.local_player
	_vehicle = _level.get_node(^"World/Vehicle")
	_animals = _level.get_node(^"CargoAnimals")
	_view = _animals.view
	_package = _level.packages[0]
	_vehicle.call(&"set_door_open", &"cab_left", true)
	_package.get_node(^"InteractionArea").interact(player)
	_vehicle.get_node(^"CargoBay/LeftShelfPackageMount/InteractionArea").interact(player)
	_vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea").interact(player)
	player.call(&"leave_seat")
	# Out of the pictures of the bay (it comes back for the prompt one).
	player.global_position = _vehicle.to_global(Vector3(7.0, 0.4, 14.0))
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_level.add_child(_camera)

	# Gull, mid-swoop then on the box.
	_speed_mps = 15.0
	await _shot("gull_warning", CargoAnimalPlan.GULL, 2.0)
	await _shot("gull_on_box", CargoAnimalPlan.GULL, 3.6)
	_animals.call(&"end_event", &"left", 0, true)

	# Dog on an open box, at a stop by a house.
	_speed_mps = 0.0
	var stop := Node3D.new()
	_level.add_child(stop)
	stop.global_position = _vehicle.global_position
	_animals.houses = [stop]
	_package.call(&"set_open", true)
	await _shot("dog_running_in", CargoAnimalPlan.DOG, 2.2)
	await _shot("dog_on_box", CargoAnimalPlan.DOG, 3.6)
	await _prompt_shot(player)
	_animals.call(&"end_event", &"left", 0, true)
	_package.call(&"set_open", false)

	# Bees round the cake.
	_speed_mps = 12.0
	_animals.zone_probe = func(_at: Vector3) -> bool: return true
	_package.content = load("res://data/contents/wedding_cake.tres")
	_package.call(&"set_open", true)
	await _shot("bees_arriving", CargoAnimalPlan.BEES, 2.0)
	await _shot("bees_round_cake", CargoAnimalPlan.BEES, 3.6)
	quit(0)


## Forces `kind` for this leg, lets the director announce it, runs `seconds` of
## it (the warning is 3 s) and saves the shot.
func _shot(shot_name: String, kind: StringName, seconds: float) -> void:
	_vehicle.linear_velocity = Vector3(0.0, 0.0, -_speed_mps)
	if _animals.phase == 0:
		_animals.set(&"events_this_run", 0)
		_animals.set(&"_cooldown", 0.0)
		_animals.set(&"_plan", {"kind": kind, "moving_seconds": 0.0})
		_animals.set(&"_fired", false)
		_animals.set(&"_poll", 0.0)
		_animals.set(&"_leg_moving", 100.0)
		_animals.call(&"advance", 1.0)
		_view.set_process(false)
		_view.call(&"_process", 0.0)
	# The view keeps its own clock: hand it the seconds up to this moment.
	var elapsed: float = float(_view.get(&"_age"))
	var step: float = 0.1
	while elapsed < seconds:
		_animals.call(&"advance", step)
		_view.call(&"_process", step)
		elapsed += step
	# The truck is held still for the picture.
	_vehicle.linear_velocity = Vector3.ZERO
	_vehicle.angular_velocity = Vector3.ZERO
	_frame_camera(kind, not shot_name.ends_with("_on_box") and not shot_name.ends_with("_round_cake"))
	_camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://cargo_animals_%s.png" % shot_name
	root.get_viewport().get_texture().get_image().save_png(path)
	print("RENDER: ", ProjectSettings.globalize_path(path))


## Looks at the box and the animal on it from the aisle side of the rear opening
## (the rack opens onto the aisle: from straight behind, the wall hides it),
## close enough to read them with the rear doors out of the way. `wide` frames
## the approach from behind the truck instead.
func _frame_camera(kind: StringName, wide: bool) -> void:
	var box_at: Vector3 = _package.global_position
	var focus: Vector3 = box_at + Vector3.UP * 0.4
	var local_box: Vector3 = _vehicle.to_local(box_at)
	var from_local := Vector3(1.1, local_box.y + 0.45, 5.6)
	if kind == CargoAnimalPlan.DOG:
		from_local = Vector3(0.45, local_box.y + 1.9, 7.2)
	_camera.fov = 62.0
	if wide:
		# The animal on its way in: from behind the truck, the whole approach.
		if kind == CargoAnimalPlan.DOG:
			_camera.global_position = _vehicle.to_global(Vector3(1.0, 1.7, 13.0))
			_camera.look_at(_vehicle.to_global(Vector3(0.1, 0.5, 6.0)))
		else:
			_camera.global_position = _vehicle.to_global(Vector3(0.7, 2.4, 10.5))
			_camera.look_at(_vehicle.to_global(Vector3(-0.2, 1.4, 4.5)))
		return
	_camera.global_position = _vehicle.to_global(from_local)
	if kind == CargoAnimalPlan.DOG:
		focus = _vehicle.to_global(Vector3(-0.05, 0.75, local_box.z))
	_camera.look_at(focus)


## The crew's view of the dog: the player stands in the bay a step from it,
## looking at it, and the game itself offers "throw it a stick" (the player's
## own interaction targeting publishes the prompt the HUD shows). The dog
## stands still for this, as it does while it works at the box.
func _prompt_shot(player: Node) -> void:
	_vehicle.linear_velocity = Vector3.ZERO
	player.global_position = _vehicle.to_global(Vector3(0.45, 0.4, 5.9))
	player.global_rotation = Vector3(0.0, _vehicle.global_rotation.y, 0.0)
	player.get_node(^"Head").rotation.x = -0.4
	var camera: Camera3D = player.get_node(^"Head/Camera3D")
	camera.make_current()
	for frame: int in range(12):
		await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var target: Node = player.call(&"_closest_interactable")
	print("PROMPT target: ", target, " prompt: ", String(player.get(&"_last_prompt")))
	var path := "user://cargo_animals_dog_prompt.png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("RENDER: ", ProjectSettings.globalize_path(path))
	player.global_position = _vehicle.to_global(Vector3(7.0, 0.4, 14.0))
