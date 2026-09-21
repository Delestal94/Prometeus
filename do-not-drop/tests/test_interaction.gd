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

	# pick_up/board_seat are @rpc methods now, called from seat_point.gd /
	# package_pickup_point.gd with rpc_id(). Calling them directly here (no
	# active RPC in flight) makes get_remote_sender_id() report 0, which
	# _from_host() treats as a genuine local call -- exactly what a
	# single-player host doing its own interactions looks like.
	player.call(&"pick_up", package.get_path())
	_expect(bool(package.get(&"is_held")) == false, "pick_up alone doesn't touch the package -- the caller (package_pickup_point.gd) sets is_held directly")
	_expect(player.get(&"carried_package") == package, "Player tracks the carried package")

	var mount: Node = vehicle.get_node(^"CargoBay/LeftSeat1PackageMount")
	package.call(&"place_at", mount)
	_expect(not bool(package.get(&"is_held")), "place_at releases the held flag")
	var distance: float = (package.get(&"global_position") as Vector3).distance_to(mount.get(&"global_position") as Vector3)
	_expect(distance < 0.01, "place_at snaps the package to the mount's transform")

	var camera: Node = vehicle.get_node(^"CabinInterior/DriverEyePoint/FirstPersonCamera")
	_expect(not bool(camera.get(&"current")), "Seat camera starts inactive")
	_expect(not bool(vehicle.get(&"controls_enabled")), "Vehicle ignores input until a driver boards")

	# seat_point.gd sets these two directly on the (host-authoritative)
	# vehicle before RPC'ing board_seat to the boarding peer -- simulated
	# here since this test calls board_seat directly, bypassing the seat.
	vehicle.set(&"controls_enabled", true)
	vehicle.set(&"driver_peer_id", 1)
	var seat: Node = camera.get_parent()  # DriverEyePoint, the seat anchor
	player.call(&"board_seat", camera.get_path(), seat.get_path())
	_expect(bool(camera.get(&"current")), "Boarding activates the seat's camera")
	_expect(bool(vehicle.get(&"controls_enabled")), "Boarding as driver enables the vehicle's controls")
	_expect(bool(player.get(&"visible")), "Seated player stays visible -- teammates should see them, not just an empty seat")
	_expect(NodePath(player.get(&"seat_node_path")) == seat.get_path(), "Player remembers which seat it's tracking")

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
