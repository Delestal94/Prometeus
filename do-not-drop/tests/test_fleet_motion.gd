extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_fleet_motion.gd
##
## The movement interface every fleet vehicle offers its cargo (expansion D-0209,
## scripts/gameplay/fleet/fleet_motion.gd):
## - a stand-in vehicle (a plain Node3D with the interface over its own FleetMotion, no wheels)
##   and the van, given the same turned pose and the same velocity sequence, report the same
##   cargo_acceleration() (within 5 %, and the one the motion implies), heading, right and local
##   space, and give a box riding along the same acceleration through
##   PackageRescue.local_acceleration(), the piece simulate_cargo() feeds the care model with;
## - a vehicle that doesn't offer the interface (the plain fakes other tests put in the "vehicle"
##   group) is read from its transform, as before;
## - ground_contact() is 1 on the stand-in, stays in 0..1 on the van, is 1 with all four wheels on
##   the road and drops once the van is lifted off it; the van keeps its speed_kmh property.

const VAN_SCENE := "res://scenes/gameplay/vehicle/vehicle.tscn"
const RescueScript = preload("res://scripts/gameplay/package/package_rescue.gd")
const MotionScript = preload("res://scripts/gameplay/fleet/fleet_motion.gd")
## Not a body, no wheels: a FleetMotion and the cargo questions the care model asks.
const STAND_IN_SOURCE := "extends Node3D\n" \
	+ "const FleetCargo = preload(\"res://scripts/gameplay/fleet/fleet_cargo.gd\")\n" \
	+ "const FleetMotion = preload(\"res://scripts/gameplay/fleet/fleet_motion.gd\")\n" \
	+ "var linear_velocity := Vector3.ZERO\nvar angular_velocity := Vector3.ZERO\n" \
	+ "var center_of_mass := Vector3.ZERO\n" \
	+ "var cargo = FleetCargo.new(self)\nvar fleet_motion = FleetMotion.new(self)\n" \
	+ "var speed_kmh: float:\n\tget:\n\t\treturn fleet_motion.speed_kmh()\n" \
	+ "func carries(p: Vector3, margin: float = 0.0) -> bool:\n\treturn cargo.carries(p, margin)\n" \
	+ "func point_velocity(p: Vector3) -> Vector3:\n\treturn cargo.point_velocity(p)\n"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_same_acceleration()
	await _check_ground_contact()
	quit(_failures)


func _stand_in() -> Node3D:
	var script := GDScript.new()
	script.source_code = STAND_IN_SOURCE
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	return node


## Within 5 % of the reference (and a hair of slack for a reference that is nearly zero).
func _close(value: Vector3, reference: Vector3) -> bool:
	return (value - reference).length() <= 0.05 * reference.length() + 0.001


func _check_same_acceleration() -> void:
	var van := (load(VAN_SCENE) as PackedScene).instantiate() as VehicleBody3D
	var fake: Node3D = _stand_in()
	var legacy := Node3D.new()
	for vehicle: Node3D in [van, fake, legacy]:
		vehicle.position = Vector3(5.0, 0.0, 3.0)
		vehicle.rotation = Vector3(0.0, 0.7, 0.0)
		root.add_child(vehicle)
	van.name = "Van"
	fake.name = "StandIn"
	legacy.name = "Legacy"
	fake.set(&"center_of_mass", van.center_of_mass)
	_expect(not (fake is VehicleBody3D) and van.fleet_motion != null, "the stand-in is no body; the van has a motion")

	# The heading, the right and the local space: the van, the stand-in and a plain Node3D agree.
	var basis: Basis = van.global_basis
	var sample_direction := Vector3(1.0, 0.5, -2.0)
	for vehicle: Node3D in [van, fake, legacy]:
		var who: String = vehicle.name
		_expect(MotionScript.forward_of(vehicle).is_equal_approx(-basis.z), "%s: forward is -Z" % who)
		_expect(MotionScript.right_of(vehicle).is_equal_approx(basis.x), "%s: right is +X" % who)
		var local: Vector3 = MotionScript.local_direction(vehicle, sample_direction)
		_expect(local.is_equal_approx(basis.inverse() * sample_direction),
			"%s: a world direction goes to the vehicle's space" % who)
	_expect(MotionScript.cargo_acceleration_of(legacy) == Vector3.ZERO
		and MotionScript.ground_contact_of(legacy) == 1.0,
		"a vehicle without the interface: no acceleration, resting on the ground")

	# The same accelerated motion, tick by tick: 1.2 m/s^2 to the side of the world, 3 forward, and a turn.
	var delta: float = 1.0 / 60.0
	var world_acceleration := Vector3(1.2, 0.0, -3.0)
	var spin := Vector3(0.0, 0.4, 0.0)
	var probe: Vector3 = van.to_global(Vector3(0.5, 1.0, 3.0))
	var box_van := Vector3.ZERO
	var box_fake := Vector3.ZERO
	var previous_van: Vector3 = van.point_velocity(probe)
	var previous_fake: Vector3 = fake.point_velocity(probe)
	for tick: int in range(1, 61):
		for vehicle: Node3D in [van, fake]:
			vehicle.set(&"linear_velocity", world_acceleration * (tick * delta))
			vehicle.set(&"angular_velocity", spin)
		van.fleet_motion.sample(delta)
		fake.fleet_motion.sample(delta)
		var now_van: Vector3 = van.point_velocity(probe)
		var now_fake: Vector3 = fake.point_velocity(probe)
		var follow: float = minf(1.0, delta * 8.0)
		box_van = box_van.lerp(RescueScript.local_acceleration(van, now_van, previous_van, delta), follow)
		box_fake = box_fake.lerp(RescueScript.local_acceleration(fake, now_fake, previous_fake, delta), follow)
		previous_van = now_van
		previous_fake = now_fake
	var implied: Vector3 = basis.inverse() * world_acceleration
	_expect(implied.length() > 3.0, "the motion is a real acceleration (%s)" % implied)
	var felt_van: Vector3 = van.fleet_motion.cargo_acceleration()
	var felt_fake: Vector3 = fake.fleet_motion.cargo_acceleration()
	_expect(_close(felt_van, felt_fake),
		"van and stand-in: the same cargo acceleration (%s vs %s)" % [felt_van, felt_fake])
	_expect(_close(felt_van, implied),
		"the van's cargo acceleration is the motion's, in its space (%s vs %s)" % [felt_van, implied])
	_expect(_close(box_van, box_fake),
		"a box riding the van feels what it feels on the stand-in (%s vs %s)" % [box_van, box_fake])
	_expect(_close(box_van, implied), "...and it is the motion's acceleration (%s vs %s)" % [box_van, implied])
	var read_speed: float = MotionScript.speed_kmh_of(van)
	_expect(absf(van.speed_kmh - fake.speed_kmh) < 0.001 and absf(read_speed - van.speed_kmh) < 0.001
		and MotionScript.speed_kmh_of(legacy) == 0.0, "speed_kmh: the van's property, the same on the stand-in")
	for vehicle: Node3D in [van, fake, legacy]:
		vehicle.queue_free()
	await process_frame


func _check_ground_contact() -> void:
	var fake: Node3D = _stand_in()
	root.add_child(fake)
	_expect(fake.fleet_motion.ground_contact() == 1.0, "the stand-in rests on the ground unless told otherwise")
	fake.fleet_motion.ground_probe = func() -> float: return 3.0
	_expect(fake.fleet_motion.ground_contact() == 1.0, "ground_contact() is clamped to 0..1 (high)")
	fake.fleet_motion.ground_probe = func() -> float: return -2.0
	_expect(fake.fleet_motion.ground_contact() == 0.0, "ground_contact() is clamped to 0..1 (low)")
	fake.queue_free()

	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(80.0, 1.0, 80.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	world.add_child(ground)
	var van := (load(VAN_SCENE) as PackedScene).instantiate() as VehicleBody3D
	van.position.y = 1.5
	world.add_child(van)
	# Somebody at the wheel, so it isn't parked (frozen, and then resting by definition).
	van.driver_peer_id = 7
	var contact: float = van.fleet_motion.ground_contact()
	_expect(contact >= 0.0 and contact <= 1.0, "the van's ground contact is a fraction (%s)" % contact)
	for tick: int in range(240):
		await physics_frame
		contact = van.fleet_motion.ground_contact()
		if contact < 0.0 or contact > 1.0:
			_expect(false, "the van's ground contact left 0..1 (%s)" % contact)
			break
	_expect(not van.freeze and van.fleet_motion.ground_contact() == 1.0,
		"the van settled on the road rests on all four wheels (%s)" % van.fleet_motion.ground_contact())
	var felt: Vector3 = van.fleet_motion.cargo_acceleration()
	_expect(felt.length() < 1.0, "...and the boxes feel nothing (%s)" % felt)
	_expect(van.speed_kmh < 1.0, "...at rest (%s km/h)" % van.speed_kmh)
	van.global_position.y += 4.0
	van.linear_velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	contact = van.fleet_motion.ground_contact()
	_expect(contact < 0.3, "lifted off the road it is airborne (%s)" % contact)
	world.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
