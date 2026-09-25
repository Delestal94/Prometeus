extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cargo_shell.gd
##
## Cargo and crew don't drive the truck (playtest 2026-09-25: it went in jerks
## and a box flew out through the front of the rack):
## - the truck's own body only collides with the environment; boxes, players,
##   clutter and ragdolls collide with its kinematic cargo shell instead
##   (vehicle.gd _build_cargo_shell), a copy of every one of its shapes;
## - two identical trucks, one of them carrying four of the heaviest boxes
##   there are (a Peso creciente at its limit), drive, brake and take a hard
##   knock exactly alike;
## - the shell keeps up with the truck at speed, so the boxes ride inside it
##   and are still in the bay after the knock;
## - moved by hand (a test, a reset), the shell jumps along before the next
##   step instead of sweeping the way.

## (Game scripts are load()ed at run time: they use autoloads, which don't
## exist yet when this script is compiled.)
const VEHICLE_LAYER: int = 2
const RIDE_HEIGHT: float = 0.666
## A Peso creciente box at its failure threshold: 8 kg x 2.5.
const HEAVIEST_BOX_KG: float = 20.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run_manager: Node = root.get_node(^"/root/RunManager")
	var shell: int = (load("res://scripts/gameplay/vehicle/vehicle.gd") as Script).get_script_constant_map()["SHELL_LAYER"]
	var player_masks: Dictionary = (load("res://scripts/gameplay/player/player.gd") as Script).get_script_constant_map()
	var loose_mask: int = (load("res://scripts/gameplay/package/package.gd") as Script).get_script_constant_map()["LOOSE_MASK"]

	# --- who collides with what ---
	for mask_name: String in ["ON_FOOT_MASK", "RIDING_MASK"]:
		var mask: int = player_masks[mask_name]
		_expect(mask & VEHICLE_LAYER == 0 and mask & shell != 0,
			"A player's %s collides with the cargo shell, not the truck (mask %d)" % [mask_name, mask])
	_expect(loose_mask & VEHICLE_LAYER == 0 and loose_mask & shell != 0,
		"A loose box collides with the shell, not the truck (mask %d)" % loose_mask)

	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(200.0, 1.0, 400.0)
	ground_shape.shape = slab
	ground.add_child(ground_shape)
	ground.position = Vector3(0.0, -0.5, -150.0)
	world.add_child(ground)
	var empty: VehicleBody3D = _truck(world, Vector3(-30.0, 0.0, 0.0))
	var loaded: VehicleBody3D = _truck(world, Vector3(30.0, 0.0, 0.0))
	for i: int in range(40):
		await physics_frame

	_expect(loaded.collision_mask == 1, "The truck's own body only collides with the environment (mask %d)" % loaded.collision_mask)
	var shell_body := loaded.get_node_or_null(^"CargoShell") as AnimatableBody3D
	_expect(shell_body != null, "The host's truck has a kinematic cargo shell")
	if shell_body == null:
		_finish(world, run_manager)
		return
	var truck_shapes: int = 0
	for child: Node in loaded.get_children():
		if child is CollisionShape3D:
			truck_shapes += 1
	_expect(shell_body.collision_layer == shell and shell_body.get_child_count() == truck_shapes,
		"The shell is on its own layer and copies all %d of the truck's shapes (layer %d, %d shapes)" % [truck_shapes, shell_body.collision_layer, shell_body.get_child_count()])
	_expect(shell_body.global_position.distance_to(loaded.global_position) < 0.02, "At rest the shell sits on the truck")

	# --- four of the heaviest boxes in the bay: on both rack decks and loose in the aisle ---
	var boxes: Array[RigidBody3D] = []
	var spots: Array[Vector3] = [
		loaded.get_node(^"CargoBay/LeftSeat1PackageMount").position,
		loaded.get_node(^"CargoBay/LeftSeat2PackageMount").position,
		Vector3(0.45, 0.6, 1.2),
		Vector3(0.45, 0.6, 3.6),
	]
	for spot: Vector3 in spots:
		var box: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
		box.set(&"package_id", StringName("shell_box_%d" % boxes.size()))
		world.add_child(box)
		box.global_transform = Transform3D(loaded.global_basis, loaded.to_global(spot + Vector3.UP * 0.02))
		box.mass = HEAVIEST_BOX_KG
		boxes.append(box)
	# Doors shut: with them open a box is meant to slide out the back.
	loaded.call(&"set_door_open", &"rear", false)
	for i: int in range(30):
		await physics_frame
	for box: RigidBody3D in boxes:
		_expect(bool(loaded.call(&"carries", box.global_position)), "%s settles inside the bay" % box.name)

	# --- the same drive for both: full throttle, a hard knock, full brakes ---
	run_manager.set(&"is_running", true)
	for truck: VehicleBody3D in [empty, loaded]:
		truck.set(&"driver_peer_id", 1)
		truck.call(&"set_controls", 1.0, 0.0, false)
	var worst_drift: float = 0.0
	var worst_lag: float = 0.0
	var empty_start: Transform3D = empty.global_transform
	var loaded_start: Transform3D = loaded.global_transform
	for tick: int in range(260):
		if tick == 150:
			# Hit something: half the speed gone in one tick. Everything loose
			# in the back keeps going.
			for truck: VehicleBody3D in [empty, loaded]:
				truck.linear_velocity *= 0.5
		if tick == 160:
			for truck: VehicleBody3D in [empty, loaded]:
				truck.call(&"set_controls", -1.0, 0.0, false)
		await physics_frame
		var empty_moved: Transform3D = empty_start.affine_inverse() * empty.global_transform
		var loaded_moved: Transform3D = loaded_start.affine_inverse() * loaded.global_transform
		worst_drift = maxf(worst_drift, empty_moved.origin.distance_to(loaded_moved.origin))
		worst_lag = maxf(worst_lag, shell_body.global_position.distance_to(loaded.global_position))
	var top_speed: float = loaded.linear_velocity.length()
	_expect(worst_drift < 0.01,
		"Carrying %.0f kg of loose boxes, the truck drives exactly like an empty one (off by up to %.4f m)" % [HEAVIEST_BOX_KG * boxes.size(), worst_drift])
	_expect(worst_lag < 0.05, "The shell keeps up with the truck at speed (off by up to %.3f m)" % worst_lag)
	for box: RigidBody3D in boxes:
		_expect(bool(loaded.call(&"carries", box.global_position)),
			"%s is still in the bay after the knock and the brakes (at %s in the truck)" % [box.name, loaded.to_local(box.global_position)])
	_expect(top_speed < 30.0, "The drive stayed sane (%.1f m/s at the end)" % top_speed)

	# --- moved by hand, the shell goes along at once ---
	run_manager.set(&"is_running", false)
	loaded.freeze = true
	loaded.global_transform = Transform3D(loaded.global_basis.rotated(Vector3.UP, 0.4), loaded.global_position + Vector3(6.0, 0.0, -9.0))
	# Transform notifications are flushed once a frame, before the next step.
	await process_frame
	_expect(shell_body.global_position.distance_to(loaded.global_position) < 0.01,
		"A truck moved by hand takes its shell along before the next step (off by %.3f m)" % shell_body.global_position.distance_to(loaded.global_position))

	_finish(world, run_manager)


func _truck(world: Node3D, at: Vector3) -> VehicleBody3D:
	var truck: VehicleBody3D = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	truck.position = at + Vector3.UP * RIDE_HEIGHT
	world.add_child(truck)
	return truck


func _finish(world: Node3D, run_manager: Node) -> void:
	run_manager.set(&"is_running", false)
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: cargo rides the truck's kinematic shell and never pushes the truck itself")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
