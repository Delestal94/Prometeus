extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_van_drive.gd
##
## The company's van is driven outside a delivery run (expansion D-0302.2.b.2, first part; vehicle.gd
## drivable_outside_run / is_drivable / park(), vehicle_input_component.gd, company_fleet.gd). RunManager.is_running
## is false the whole test.
## - vehicle.gd alone, flat ground: a van without the flag, with a driver and the pedal down, does not move (it
##   brakes, as before); built drivable_outside_run it does (> 5 m in two seconds). Driven and then left with
##   nobody at the wheel it stops and freezes by itself (_update_parking); built parked (park()) it is frozen
##   with its wheels posed, stays so with nobody at the wheel even with the input pressed (a player walking past
##   it must not press its pedal), and is let go the moment somebody takes the wheel and the pedal moves it, the
##   input read by VehicleInputComponent. Its engine is on only with a driver or while it rolls to a stop
##   (presentation_engine_running), and it relays no vehicle_telemetry out of a run.
## - Solo, company_root.tscn: the fleet's van is built drivable and parked (frozen) inside the playon: on the
##   shed's side of CompanyTrips' gate (CompanyFleet.gate_of(), the playon's far edge), PLAYON_DEPTH_M out, within
##   its opening, nothing out at spawn; the gate is not the shed's exit (it is farther out than the wall), and up
##   to three vans side by side are inside the opening (park_transform()).
## - A player takes its wheel (the seat's interact(), as the host does): the van is let go; with the accelerator
##   pressed it drives out across the gate with the cargo staged and the trip starts (OUT); the player gets out,
##   the van brakes and freezes again, quiet and driverless.
## - The gate's inside is the rectangle of the shed and the playon (TripGate.set_yard()): with cargo staged, a van
##   that leaves it round the playon's side, 8 m past the opening's edge, starts the trip too, one that left by
##   the opening and comes back in by the side closes it, and a seventh van still stands inside (PLAYON_SLOTS).
## - Ground: a ray of layer 1 every 32 m over the rectangle of all the zones always hits something (the backup
##   slab under the holes between the zones). A van that fell out of the world (y -20) on the host is put back
##   where it parks, still, and its trip is closed (trips_out() 0, CompanyFleet.vehicle_recovered).

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const VEHICLE_SCENE: String = "res://scenes/gameplay/vehicle/vehicle.tscn"
const DIR: String = "user://test_company_van_drive"
const SEAT_PATH: NodePath = ^"CabinInterior/DriverEyePoint/InteractionArea"
const ACCELERATE: StringName = &"drive_accelerate"
const HEN: Resource = preload("res://data/products/hen.tres")

var _failures: int = 0
var _telemetry: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	run.set(&"is_running", false)
	root.get_node(^"/root/EventBus").connect(&"vehicle_telemetry", func(_kmh: float) -> void: _telemetry += 1)
	await _check_vehicle_alone()
	await _check_company_world()
	Input.action_release(ACCELERATE)
	_expect(_telemetry == 0, "Out of a run the driven van relays no telemetry (got %d)" % _telemetry)
	if _failures == 0:
		print("PASS: the company's van drives out of a run only where it is asked to, parks and lets go by itself,"
			+ " stands inside the playon's gate and crossing it out starts the trip")
	quit(_failures)


## vehicle.gd on flat ground: the flag, the parking and the input.
func _check_vehicle_alone() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)

	var plain: VehicleBody3D = _van(world, Vector3(-30.0, 0.8, 0.0), false)
	var drivable: VehicleBody3D = _van(world, Vector3(30.0, 0.8, 0.0), true)
	for _tick: int in range(40):
		await physics_frame
	for van: VehicleBody3D in [plain, drivable]:
		van.set(&"driver_peer_id", 1)
		van.set(&"controls_enabled", false)
	var plain_start: Vector3 = plain.global_position
	var drivable_start: Vector3 = drivable.global_position
	for _tick: int in range(120):
		plain.call(&"set_controls", 1.0, 0.0, false)
		drivable.call(&"set_controls", 1.0, 0.0, false)
		await physics_frame
	var plain_moved: float = plain.global_position.distance_to(plain_start)
	_expect(plain_moved < 0.5, "Without the flag a van with a driver does not move out of a run (%.2f m)" % plain_moved)
	_expect(drivable.global_position.distance_to(drivable_start) > 5.0 and bool(drivable.get(&"is_drivable")),
		"Built drivable_outside_run it drives (%.2f m)" % drivable.global_position.distance_to(drivable_start))
	_expect(bool(drivable.get(&"presentation_engine_running")) and not bool(plain.get(&"presentation_engine_running")),
		"...with its engine on; the one without the flag has it off")
	# Nobody at the wheel any more, handbrake as the seat leaves it: it stops and freezes by itself.
	drivable.set(&"driver_peer_id", 0)
	drivable.call(&"set_controls", 0.0, 0.0, true)
	var frozen: bool = false
	for _tick: int in range(900):
		await physics_frame
		if drivable.freeze:
			frozen = true
			break
	_expect(frozen and bool(drivable.get(&"_parked")), "Driverless and stopped, the driven van freezes by itself")
	_expect(not bool(drivable.get(&"presentation_engine_running")), "...and its engine is off")
	# Somebody takes the wheel and presses the pedal: it is let go and moves.
	var rest: Vector3 = drivable.global_position
	drivable.set(&"driver_peer_id", 1)
	drivable.call(&"set_controls", 1.0, 0.0, false)
	for _tick: int in range(90):
		drivable.call(&"set_controls", 1.0, 0.0, false)
		await physics_frame
	var released_by: float = drivable.global_position.distance_to(rest)
	_expect(not drivable.freeze and released_by > 2.0,
		"Somebody at the wheel with the pedal down lets the parked van go (%.2f m)" % released_by)
	world.free()
	await physics_frame
	await _check_parked_at_birth()


## A van built parked (what CompanyFleet does), read through the real input component.
func _check_parked_at_birth() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	var van: VehicleBody3D = _van(world, Vector3(0.0, 0.8, 0.0), true)
	var constants: Dictionary = (van.get_script() as GDScript).get_script_constant_map()
	van.call(&"park")
	for _tick: int in range(30):
		await physics_frame
	_expect(van.freeze and bool(van.get(&"_parked")), "A van built parked is frozen")
	var wheel := van.get_node(^"FrontLeftWheel") as VehicleWheel3D if van.has_node(^"FrontLeftWheel") else null
	var wheel_y: float = wheel.position.y if wheel != null else 0.0
	var settled_y: float = float(constants["TIRE_RADIUS"]) - float(constants["RIDE_HEIGHT"])
	_expect(wheel == null or absf(wheel_y - settled_y) < 0.01,
		"...with its wheels set where the settled suspension holds them (y %.3f)" % wheel_y)
	var start: Vector3 = van.global_position
	van.set(&"controls_enabled", true)
	Input.action_press(ACCELERATE)
	for _tick: int in range(60):
		await physics_frame
	_expect(van.freeze and van.global_position.distance_to(start) < 0.05,
		"With nobody at the wheel the accelerator moves nothing: the input is not read")
	van.set(&"driver_peer_id", 1)
	for _tick: int in range(120):
		await physics_frame
	Input.action_release(ACCELERATE)
	_expect(not van.freeze and van.global_position.distance_to(start) > 3.0,
		"With a driver the input component reads the accelerator and the van drives (%.2f m)"
		% van.global_position.distance_to(start))
	world.free()
	await physics_frame


func _van(world: Node3D, at: Vector3, flag: bool) -> VehicleBody3D:
	var van := (load(VEHICLE_SCENE) as PackedScene).instantiate() as VehicleBody3D
	van.position = at
	van.set(&"drivable_outside_run", flag)
	world.add_child(van)
	return van


## The company's world: the fleet's van parked inside the playon, taken out through its gate.
func _check_company_world() -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	for _tick: int in range(40):
		await physics_frame
	var van := level.fleet.vehicle("van_classic") as VehicleBody3D if level.fleet != null else null
	_expect(van != null, "The company's world has its van")
	if van == null:
		_free_level(level, state)
		return
	var trips: CompanyTrips = level.trips
	_expect(bool(van.get(&"drivable_outside_run")) and van.freeze and bool(van.get(&"_parked")),
		"The fleet's van is built drivable and parked (frozen)")
	var gate: Vector3 = CompanyFleet.gate_of(level.shed, level.net.company)
	var exit: Vector3 = CompanyFleet.exit_of(level.shed, level.net.company)
	var outward: Vector3 = -level.shed.global_basis.z
	_expect(is_equal_approx((gate - exit).dot(outward), CompanyShed.WALL_THICKNESS + CompanyFleet.PLAYON_DEPTH_M)
		and trips.gate.distance(exit) < -CompanyFleet.PLAYON_DEPTH_M,
		"CompanyTrips' gate is the playon's far edge, past the shed's exit (exit is %.2f m inside it)"
		% -trips.gate.distance(exit))
	_expect(trips.gate.side_of(van.global_position) == TripGate.INSIDE and trips.trips_out() == 0,
		"The parked van is inside the gate (%.2f m from it), nothing out" % trips.gate.distance(van.global_position))
	var half_opening: float = CompanyFleet.PLAYON_WIDTH_M * 0.5
	var all_inside: bool = true
	for index: int in range(3):
		var at: Transform3D = CompanyFleet.park_transform(level.shed, level.net.company, index)
		var lateral: float = absf((at.origin - gate).dot(level.shed.global_basis.x))
		var front: float = (at.origin - gate).dot(outward) - (-at.basis.z).dot(outward) * -2.7
		all_inside = all_inside and lateral + 1.1 <= half_opening and front < 0.0
	_expect(all_inside, "Three vans side by side fit the playon, inside the gate's opening")
	await _check_ground(level)
	await _check_yard(level, van)
	await _check_fallen(level, van)
	await _check_driving_out(level, van)
	_free_level(level, state)
	await process_frame


## Every 32 m over the rectangle of all the zones there is ground (layer 1) to hit.
func _check_ground(level: CompanyRoot) -> void:
	var rect: Rect2 = CompanyGround.zones_rect(level.zones)
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var misses: int = 0
	var rays: int = 0
	var first: Vector2 = Vector2.ZERO
	var x: float = rect.position.x + 16.0
	while x < rect.end.x:
		var z: float = rect.position.y + 16.0
		while z < rect.end.y:
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, 5.0, z), Vector3(x, -5.0, z), 1)
			rays += 1
			if space.intersect_ray(query).is_empty():
				if misses == 0:
					first = Vector2(x, z)
				misses += 1
			z += 32.0
		x += 32.0
	_expect(rays > 1000 and misses == 0, ("A ray every 32 m over the zones' rectangle always finds ground (%d of %d"
		+ " missed, first at %s)") % [misses, rays, first])


## The yard rectangle: a departure round the playon's side, a return by it, the seventh slot inside.
func _check_yard(level: CompanyRoot, van: VehicleBody3D) -> void:
	var trips: CompanyTrips = level.trips
	var company: Object = level.net.company
	var gate: Vector3 = CompanyFleet.gate_of(level.shed, company)
	var outward: Vector3 = -level.shed.global_basis.z
	var side: Vector3 = level.shed.global_basis.x
	var half_opening: float = CompanyFleet.PLAYON_WIDTH_M * 0.5
	var products: Dictionary = {&"hen": HEN}
	var parked: Transform3D = van.global_transform
	for slot: int in range(CompanyFleet.PLAYON_SLOTS):
		var at: Vector3 = CompanyFleet.park_transform(level.shed, company, slot).origin
		_expect(trips.gate.side_of(at) == TripGate.INSIDE, "Slot %d of the playon is inside the compound" % slot)
	trips.book.add(Order.make(&"o_side", "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products))
	trips.book.mark_packed(&"o_side", &"box_side")
	trips.stage_cargo(&"van_classic", [&"o_side"], [&"box_side"])
	# Round the side, 8 m past the opening's edge, a few metres short of the gate's line.
	await _put(van, gate + side * (half_opening + 8.0) - outward * 5.0)
	_expect(trips.trips_out() == 1 and trips.trip_of(&"van_classic") != null,
		"Leaving round the playon's side starts the trip (trips out %d)" % trips.trips_out())
	await _put(van, gate - outward * 5.0)
	_expect(trips.trips_out() == 0 and trips.book.state_of(&"o_side") == Order.STATE_FAILED,
		"...and coming back in closes it (trips out %d)" % trips.trips_out())
	# Out through the opening, back in by the side.
	trips.book.add(Order.make(&"o_back", "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products))
	trips.book.mark_packed(&"o_back", &"box_back")
	trips.stage_cargo(&"van_classic", [&"o_back"], [&"box_back"])
	await _put(van, gate + outward * 3.0)
	_expect(trips.trips_out() == 1, "Out through the opening starts the trip (trips out %d)" % trips.trips_out())
	await _put(van, gate + side * (half_opening + 8.0) - outward * 5.0)
	_expect(trips.trips_out() == 1, "...it stays out outside the compound's side")
	await _put(van, gate + side * (half_opening - 4.0) - outward * 5.0)
	_expect(trips.trips_out() == 0, "...and coming back in by the side closes it (trips out %d)" % trips.trips_out())
	van.global_transform = parked
	await physics_frame
	await physics_frame


## A van that fell out of the world with a trip out is put back where it parks, still, and the trip is closed.
func _check_fallen(level: CompanyRoot, van: VehicleBody3D) -> void:
	var trips: CompanyTrips = level.trips
	var recovered: Array[StringName] = []
	level.fleet.vehicle_recovered.connect(func(id: StringName) -> void: recovered.append(id))
	var products: Dictionary = {&"hen": HEN}
	trips.book.add(Order.make(&"o_fall", "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products))
	trips.book.mark_packed(&"o_fall", &"box_fall")
	trips.stage_cargo(&"van_classic", [&"o_fall"], [&"box_fall"])
	var gate: Vector3 = CompanyFleet.gate_of(level.shed, level.net.company)
	await _put(van, gate - level.shed.global_basis.z * 4.0)
	_expect(trips.trips_out() == 1, "A trip is out before the van falls (trips out %d)" % trips.trips_out())
	van.global_position = Vector3(gate.x, -20.0, gate.z)
	for _tick: int in range(4):
		await physics_frame
	var home: Vector3 = CompanyFleet.park_transform(level.shed, level.net.company, 0).origin
	_expect(recovered == ([&"van_classic"] as Array[StringName]) and van.freeze and bool(van.get(&"_parked"))
		and Vector2(van.global_position.x - home.x, van.global_position.z - home.z).length() < 0.1
		and van.global_position.y > -1.0 and van.linear_velocity.length() < 0.01,
		"The fallen van is back where it parks, still (at %s, home %s)" % [van.global_position, home])
	_expect(trips.trips_out() == 0 and not level.trips_view.is_out(&"van_classic")
		and trips.book.state_of(&"o_fall") == Order.STATE_FAILED,
		"...and its trip is closed (trips out %d)" % trips.trips_out())
	for _tick: int in range(30):
		await physics_frame
	_expect(trips.trips_out() == 0 and trips.gate.side_of(van.global_position) == TripGate.INSIDE,
		"...and it stays inside the gate")


## Moves the (frozen) van and lets the gate look at it.
func _put(van: Node3D, at: Vector3) -> void:
	van.global_position = Vector3(at.x, van.global_position.y, at.z)
	await physics_frame
	await physics_frame


func _check_driving_out(level: CompanyRoot, van: VehicleBody3D) -> void:
	var trips: CompanyTrips = level.trips
	var player: Player = level.player as Player
	var seat: Node = van.get_node_or_null(SEAT_PATH)
	_expect(player != null and seat is SeatPoint, "There is a player and the van has its driver's seat")
	if player == null or not seat is SeatPoint:
		return
	var products: Dictionary = {&"hen": HEN}
	trips.book.add(Order.make(&"o_drive", "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products))
	trips.book.mark_packed(&"o_drive", &"box_drive")
	trips.stage_cargo(&"van_classic", [&"o_drive"], [&"box_drive"])
	van.call(&"set_door_open", &"cab_left", true)
	var start: Vector3 = van.global_position
	(seat as SeatPoint).interact(player)
	await physics_frame
	_expect(int(van.get(&"driver_peer_id")) != 0 and van.get(&"controls_enabled") == true,
		"The player takes the wheel (driver %d)" % van.get(&"driver_peer_id"))
	Input.action_press(ACCELERATE)
	var left: bool = false
	for _tick: int in range(900):
		await physics_frame
		left = left or trips.trips_out() > 0
		if left or van.global_position.distance_to(start) > 40.0:
			break
	Input.action_release(ACCELERATE)
	var trip: Trip = trips.trip_of(&"van_classic")
	_expect(not van.freeze and left and trip != null and trip.order_ids == ([&"o_drive"] as Array[StringName])
		and trips.book.state_of(&"o_drive") == Order.STATE_OUT and level.trips_view.is_out(&"van_classic"),
		"Driven out across the gate it starts the trip with its order OUT (moved %.1f m, trips out %d)"
		% [van.global_position.distance_to(start), trips.trips_out()])
	_expect(trips.gate.side_of(van.global_position) == TripGate.OUTSIDE, "...and it is outside the gate")
	# The player gets out: it brakes and freezes again, nobody driving, nothing pressed.
	player.leave_seat()
	await process_frame
	var frozen: bool = false
	for _tick: int in range(900):
		await physics_frame
		if van.freeze:
			frozen = true
			break
	_expect(int(van.get(&"driver_peer_id")) == 0 and frozen and bool(van.get(&"_parked")),
		"The player gets out: the van brakes and freezes again (driver %d, frozen %s)"
		% [van.get(&"driver_peer_id"), frozen])


func _free_level(level: Node, state: Node) -> void:
	level.queue_free()
	current_scene = null
	state.call(&"reset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
