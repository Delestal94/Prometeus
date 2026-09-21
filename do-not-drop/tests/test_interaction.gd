extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_interaction.gd
## Exercises pick up -> carry -> place -> board without needing real input,
## by calling the same methods seat_point.gd/package_mount_point.gd call.
## Uses load() at runtime, not preload() at parse time -- vehicle.gd
## references the RunManager autoload as a bare global, which isn't
## resolvable yet while this script itself is still being compiled.

var _failures: int = 0


func _initialize() -> void:
	var player_scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")
	var package_scene: PackedScene = load("res://scenes/gameplay/package/package.tscn")
	var vehicle_scene: PackedScene = load("res://scenes/gameplay/vehicle/vehicle.tscn")
	var player: Node = player_scene.instantiate()
	var package: Node = package_scene.instantiate()
	var vehicle: Node = vehicle_scene.instantiate()
	root.add_child(player)
	root.add_child(package)
	root.add_child(vehicle)
	await process_frame
	await physics_frame

	_expect(not bool(package.get(&"is_held")), "Package starts unheld")

	player.call(&"pick_up", package)
	_expect(bool(package.get(&"is_held")), "pick_up marks the package as held")
	_expect(player.get(&"carried_package") == package, "Player tracks the carried package")
	_expect(bool(package.get(&"freeze")), "Held package freezes so it stops fighting physics")

	var mount: Node = vehicle.get_node(^"CargoBay/LeftSeat1PackageMount")
	package.call(&"place_at", mount)
	_expect(not bool(package.get(&"is_held")), "place_at releases the held flag")
	var distance: float = (package.get(&"global_position") as Vector3).distance_to(mount.get(&"global_position") as Vector3)
	_expect(distance < 0.01, "place_at snaps the package to the mount's transform")

	var camera: Node = vehicle.get_node(^"CabinInterior/DriverEyePoint/FirstPersonCamera")
	_expect(not bool(camera.get(&"current")), "Seat camera starts inactive")
	_expect(not bool(vehicle.get(&"controls_enabled")), "Vehicle ignores input until a driver boards")

	player.call(&"board_seat", camera, true, vehicle)
	_expect(bool(camera.get(&"current")), "Boarding activates the seat's camera")
	_expect(bool(vehicle.get(&"controls_enabled")), "Boarding as driver enables the vehicle's controls")
	_expect(not bool(player.get(&"visible")), "Seated player hides their on-foot body")

	player.free()
	package.free()
	vehicle.free()
	if _failures == 0:
		print("PASS: pick up, place at mount, and board seat all update state correctly")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
