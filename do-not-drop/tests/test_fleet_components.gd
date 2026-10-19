extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_fleet_components.gd
##
## The components every fleet vehicle shares (expansion D-0208, scripts/gameplay/fleet/):
## - FleetCargo works on a plain Node3D that is no VehicleBody3D (a stand-in for a boat or a
##   plane): carries() with and without margin, point_velocity() with spin around the centre
##   of mass, needs_sweep(), get_cargo_spawn_transform(), the cargo shell (a copy of the
##   shapes on layer 64 that follows the body's velocity) and on_package_placed() (a wide
##   box slid in from the wall);
## - FleetSeats finds the seats under such an owner and answers occupancy and driver queries;
## - the van (vehicle.gd) keeps its public API on top of them: the same carries() answers as
##   the bay AABB in its own space (moved and turned), point_velocity(), the constants other
##   scripts read, the cargo shell as its CargoShell child, the spawn marker, and 11 seats
##   with exactly one driver's, driver_peer_id staying a property of the van.

const VAN_SCENE := "res://scenes/gameplay/vehicle/vehicle.tscn"
const CargoScript = preload("res://scripts/gameplay/fleet/fleet_cargo.gd")
const SeatsScript = preload("res://scripts/gameplay/fleet/fleet_seats.gd")
## Not a VehicleBody3D, not even a body: only the properties the components read.
const OWNER_SOURCE := "extends Node3D\n" \
	+ "var linear_velocity := Vector3.ZERO\nvar angular_velocity := Vector3.ZERO\n" \
	+ "var center_of_mass := Vector3.ZERO\nvar driver_peer_id: int = 0\n"
const SEAT_SOURCE := "extends Node3D\nvar role: StringName = &\"passenger\"\nvar taken := false\n" \
	+ "func is_occupied() -> bool:\n\treturn taken\n"
const PACKAGE_SOURCE := "extends Node3D\nvar package_id: StringName = &\"fleet_box\"\n" \
	+ "var current_mount: Node = null\nfunc get_half_extents() -> Vector3:\n\treturn Vector3(0.5, 0.5, 0.5)\n"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_fake_owner()
	await _check_van()
	quit(_failures)


func _scripted(source: String) -> Node3D:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	return node


func _check_fake_owner() -> void:
	var owner_node: Node3D = _scripted(OWNER_SOURCE)
	owner_node.position = Vector3(10.0, 0.0, 0.0)
	var spawn := Marker3D.new()
	spawn.position = Vector3(0.0, 1.0, 1.5)
	owner_node.add_child(spawn)
	var hull := CollisionShape3D.new()
	hull.name = "HullCollision"
	hull.shape = BoxShape3D.new()
	owner_node.add_child(hull)
	root.add_child(owner_node)
	_expect(not (owner_node is VehicleBody3D), "the stand-in is no VehicleBody3D")

	var cargo = CargoScript.new(owner_node)
	cargo.spawn_point = spawn
	var inside: Vector3 = owner_node.to_global(Vector3(0.0, 1.0, 2.0))
	var behind: Vector3 = owner_node.to_global(Vector3(0.0, 1.0, 5.2))
	_expect(cargo.carries(inside), "fake owner: a point in the bay rides along")
	_expect(not cargo.carries(behind), "fake owner: a point past the rear doors doesn't")
	_expect(cargo.carries(behind, 0.8), "fake owner: ...but counts with a margin")
	_expect(not cargo.carries(owner_node.to_global(Vector3(3.0, 1.0, 2.0))), "fake owner: nor one beside it")
	cargo.bay = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 1.0, 2.0))
	_expect(not cargo.carries(inside), "fake owner: another vehicle sets its own bay")
	cargo.bay = CargoScript.CARGO_BAY

	_expect(cargo.point_velocity(inside) == Vector3.ZERO, "fake owner: at rest, nothing is carried")
	owner_node.set(&"linear_velocity", Vector3(0.0, 0.0, -5.0))
	owner_node.set(&"angular_velocity", Vector3(0.0, 2.0, 0.0))
	owner_node.set(&"center_of_mass", Vector3(0.0, 0.0, 1.0))
	var centre: Vector3 = owner_node.to_global(Vector3(0.0, 0.0, 1.0))
	var expected: Vector3 = Vector3(0.0, 0.0, -5.0) + Vector3(0.0, 2.0, 0.0).cross(inside - centre)
	var carried: Vector3 = cargo.point_velocity(inside)
	_expect(carried.is_equal_approx(expected),
		"fake owner: point_velocity adds the spin around the centre of mass (%s vs %s)" % [carried, expected])

	var box := RigidBody3D.new()
	root.add_child(box)
	box.global_position = inside
	box.linear_velocity = cargo.point_velocity(inside)
	_expect(not cargo.needs_sweep(box), "fake owner: a box riding along doesn't sweep")
	box.linear_velocity = cargo.point_velocity(inside) + Vector3(0.0, 0.0, 30.0)
	_expect(cargo.needs_sweep(box), "fake owner: a box thrown inside the bay sweeps")
	box.global_position = behind
	_expect(cargo.needs_sweep(box), "fake owner: a box loose in the world sweeps")
	box.queue_free()

	_expect(cargo.get_cargo_spawn_transform() == spawn.global_transform, "fake owner: boxes appear at the spawn marker")

	cargo.build_shell()
	_expect(cargo.shell != null and owner_node.get_node_or_null(^"CargoShell") == cargo.shell,
		"fake owner: the shell is the child CargoShell")
	_expect(cargo.shell.collision_layer == CargoScript.SHELL_LAYER and cargo.shell.collision_mask == 0,
		"fake owner: the shell is on layer 64 and looks at nothing")
	_expect(cargo.shell.get_node_or_null(^"HullCollision") != null
		and (cargo.shell.get_node(^"HullCollision") as CollisionShape3D).shape == hull.shape,
		"fake owner: the shell copies the body's shapes, sharing them")
	await physics_frame
	owner_node.set(&"linear_velocity", Vector3(3.0, 0.0, 0.0))
	owner_node.set(&"angular_velocity", Vector3.ZERO)
	owner_node.set(&"center_of_mass", Vector3.ZERO)
	cargo.follow(0.1)
	_expect(absf(cargo.shell.global_position.x - 10.3) < 0.001,
		"fake owner: the shell is put where the body will be after the step (x %s)" % cargo.shell.global_position.x)

	var marker := Marker3D.new()
	marker.position = Vector3(0.9, 1.0, 1.0)
	owner_node.add_child(marker)
	var package: Node3D = _scripted(PACKAGE_SOURCE)
	package.add_to_group(&"cargo")
	package.set(&"current_mount", marker)
	root.add_child(package)
	cargo.on_package_placed(&"other_box")
	_expect(package.global_position == Vector3.ZERO, "fake owner: another box id is left alone")
	cargo.on_package_placed(&"fleet_box")
	var local: Vector3 = owner_node.to_local(package.global_position)
	var limit: float = CargoScript.CARGO_WALL_INNER_X - (0.5 + CargoScript.CARGO_WALL_CLEARANCE)
	_expect(absf(local.x - limit) < 0.001 and absf(local.y - 1.175) < 0.001,
		"fake owner: a wide box shelved by the wall is slid in and set on its deck (%s)" % local)
	package.queue_free()

	var seats = SeatsScript.new(owner_node)
	_expect(seats.seat_count() == 0 and seats.driver_seat() == null and not seats.has_free_seat(),
		"fake owner: no seats, no driver seat")
	_expect(not seats.has_driver(), "fake owner: nobody drives")
	var driver_seat: Node3D = _scripted(SEAT_SOURCE)
	driver_seat.set(&"role", &"driver")
	var passenger_seat: Node3D = _scripted(SEAT_SOURCE)
	var nested := Node3D.new()
	owner_node.add_child(nested)
	nested.add_child(driver_seat)
	nested.add_child(passenger_seat)
	nested.add_child(Marker3D.new())
	seats.forget()
	_expect(seats.seat_count() == 2 and seats.driver_seat() == driver_seat, "fake owner: seats are found at any depth")
	_expect(seats.occupied_count() == 0 and seats.free_seats().size() == 2 and seats.has_free_seat(),
		"fake owner: both seats are free")
	passenger_seat.set(&"taken", true)
	_expect(seats.occupied_count() == 1 and seats.free_seats() == [driver_seat as Node],
		"fake owner: occupancy follows the seats")
	owner_node.set(&"driver_peer_id", 4)
	_expect(seats.has_driver() and seats.is_driver(4) and not seats.is_driver(5) and not seats.is_driver(0),
		"fake owner: the driver is the owner's driver_peer_id")

	owner_node.queue_free()
	await process_frame


func _check_van() -> void:
	var van := (load(VAN_SCENE) as PackedScene).instantiate() as VehicleBody3D
	_expect(van != null, "the van instantiates")
	if van == null:
		return
	van.position = Vector3(5.0, 0.0, 3.0)
	van.rotation = Vector3(0.0, 0.7, 0.0)
	root.add_child(van)
	var script: GDScript = van.get_script()
	var consts: Dictionary = script.get_script_constant_map()
	_expect(consts["CARGO_BAY"] == CargoScript.CARGO_BAY and consts["SHELL_LAYER"] == 64
		and consts["CARGO_WALL_INNER_X"] == 1.0 and is_equal_approx(consts["CARGO_WALL_CLEARANCE"], 0.045)
		and is_equal_approx(consts["MOUNT_REFERENCE_HALF_HEIGHT"], 0.325), "the van keeps its cargo constants")

	var bay: AABB = consts["CARGO_BAY"]
	for sample: Array in [
		[Vector3(0.0, 1.0, 2.0), 0.0], [Vector3(0.0, 1.0, 8.0), 0.0], [Vector3(3.0, 1.0, 2.0), 0.0],
		[Vector3(0.0, 1.0, 4.9), 0.0], [Vector3(0.0, 1.0, 4.9), 0.4], [Vector3(1.2, 1.0, 2.0), 0.0],
		[Vector3(1.2, 1.0, 2.0), 0.4], [Vector3(0.0, 3.0, 2.0), 0.0], [Vector3(0.0, 3.0, 2.0), 0.6],
	]:
		var world_point: Vector3 = van.to_global(sample[0])
		var margin: float = sample[1]
		_expect(van.carries(world_point, margin) == bay.grow(margin).has_point(van.to_local(world_point)),
			"van.carries(%s, %s) answers as the bay in its own space" % [sample[0], margin])
	_expect(van.carries(van.to_global(Vector3(0.0, 1.0, 2.0))), "van: a point inside the bay rides along")
	_expect(not van.carries(van.to_global(Vector3(0.0, 1.0, 8.0))), "van: a point outside doesn't")

	van.linear_velocity = Vector3(1.0, 0.0, -4.0)
	van.angular_velocity = Vector3(0.0, 1.5, 0.0)
	var probe: Vector3 = van.to_global(Vector3(0.5, 1.0, 3.0))
	var centre: Vector3 = van.global_transform * van.center_of_mass
	var expected: Vector3 = van.linear_velocity + van.angular_velocity.cross(probe - centre)
	_expect(van.point_velocity(probe).is_equal_approx(expected), "van.point_velocity() is unchanged")
	var box := RigidBody3D.new()
	root.add_child(box)
	box.global_position = van.to_global(Vector3(0.0, 1.0, 2.0))
	box.linear_velocity = van.point_velocity(box.global_position)
	_expect(not van.needs_sweep(box), "van.needs_sweep(): a box riding along doesn't sweep")
	box.global_position = van.to_global(Vector3(0.0, 1.0, 9.0))
	_expect(van.needs_sweep(box), "van.needs_sweep(): a box loose in the world does")
	box.queue_free()

	var first_mount := van.get_node(^"CargoBay/LeftSeat1PackageMount") as Node3D
	_expect(van.get_cargo_spawn_transform() == first_mount.global_transform,
		"van.get_cargo_spawn_transform() is the first seat's mount")
	var shell := van.get_node_or_null(^"CargoShell") as StaticBody3D
	_expect(shell != null and shell == van.fleet_cargo.shell and shell.collision_layer == 64,
		"van: CargoShell is built by the component, on layer 64")
	van.set_rear_cargo_open(false)
	await physics_frame
	var blocker := shell.get_node_or_null(^"RearDoorCollision") as CollisionShape3D if shell != null else null
	_expect(blocker != null and not blocker.disabled,
		"van: shutting the rear doors enables the shell's blocker too")

	var seats = van.fleet_seats
	_expect(seats.seat_count() == 11, "van: 11 seats found under it (got %s)" % seats.seat_count())
	var driver_seat: Node = seats.driver_seat()
	_expect(driver_seat != null and driver_seat.get(&"role") == &"driver", "van: one seat holds the wheel")
	var driver_count: int = 0
	for seat: Node in seats.seat_points():
		driver_count += 1 if seat.get(&"role") == &"driver" else 0
	_expect(driver_count == 1, "van: exactly one driver's seat (got %s)" % driver_count)
	_expect(not seats.has_driver() and van.driver_peer_id == 0, "van: nobody drives at first")
	van.driver_peer_id = 7
	_expect(seats.has_driver() and seats.is_driver(7) and van.driver_peer_id == 7,
		"van: driver_peer_id stays a property of the van and the component reads it")
	van.driver_peer_id = 0

	van.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
