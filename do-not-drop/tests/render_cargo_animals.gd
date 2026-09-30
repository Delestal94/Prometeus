extends SceneTree
## Run (needs a GPU, not --headless):
##   Godot --path do-not-drop --script res://tests/render_cargo_animals.gd
## Review shots of the animals that go for the cargo (N-109): from behind the
## truck, through the open rear doors, the gull swooping in and on the box, the
## dog on the open box with its "throw a stick" prompt, and the bees round the
## cake, each with its icon. Saved to user://cargo_animals_*.png.
##
## The director is driven by hand (advance()) with a forced plan, the same way
## test_cargo_animals.gd does, so each shot is the moment named.

var _level: Node
var _animals: Node
var _view: Node
var _vehicle: RigidBody3D
var _package: Node
var _camera: Camera3D


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
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_level.add_child(_camera)

	# Gull, mid-swoop then on the box.
	_vehicle.linear_velocity = Vector3(0.0, 0.0, -15.0)
	await _shot("gull_warning", CargoAnimalPlan.GULL, 1.5)
	await _shot("gull_on_box", CargoAnimalPlan.GULL, 3.6)
	_animals.call(&"end_event", &"left", 0, true)

	# Dog on an open box, at a stop by a house.
	_vehicle.linear_velocity = Vector3.ZERO
	var stop := Node3D.new()
	_level.add_child(stop)
	stop.global_position = _vehicle.global_position
	_animals.houses = [stop]
	_package.call(&"set_open", true)
	await _shot("dog_running_in", CargoAnimalPlan.DOG, 1.4)
	await _shot("dog_on_box", CargoAnimalPlan.DOG, 3.6)
	_animals.call(&"end_event", &"left", 0, true)
	_package.call(&"set_open", false)

	# Bees round the cake.
	_vehicle.linear_velocity = Vector3(0.0, 0.0, -12.0)
	_animals.zone_probe = func(_at: Vector3) -> bool: return true
	_package.content = load("res://data/contents/wedding_cake.tres")
	_package.call(&"set_open", true)
	await _shot("bees_arriving", CargoAnimalPlan.BEES, 1.4)
	await _shot("bees_round_cake", CargoAnimalPlan.BEES, 3.6)
	quit(0)


## Forces `kind` for this leg, lets the director announce it, runs `seconds` of
## it (the warning is 3 s) and saves the shot.
func _shot(shot_name: String, kind: StringName, seconds: float) -> void:
	if _animals.phase == 0:
		_animals.set(&"events_this_run", 0)
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
	_camera.global_position = _vehicle.to_global(Vector3(0.0, 2.3, 9.0))
	_camera.look_at(_vehicle.to_global(Vector3(-0.3, 1.2, 2.5)))
	_camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://cargo_animals_%s.png" % shot_name
	root.get_viewport().get_texture().get_image().save_png(path)
	print("RENDER: ", ProjectSettings.globalize_path(path))
