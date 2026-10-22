extends RefCounted
## The company-day bot's driver (tests/bot_company_day.gd, D-2016.2 drive and return). Not a test:
## preloaded. It drives the fleet's van (CompanyFleet, the real node in CompanyTrips' group) the way
## a player does, with no hand on the gate: the player opens the cab door and takes the wheel
## (SeatPoint.interact, as the host does), the driving actions are held down (Input, read by
## VehicleInputComponent) and CompanyTrips, which follows the node every physics tick, sees it cross.
## Out: the pedal until the van's Trip starts; back: the brake, which stops it and then reverses,
## until the Trip closes. Each waits at most DRIVE_TICKS and lets the van stop afterwards.

## The driver's seat of the van scene (as test_company_van_drive.gd) and the door it is boarded by.
const SEAT_PATH: NodePath = ^"CabinInterior/DriverEyePoint/InteractionArea"
const DRIVER_DOOR: StringName = &"cab_left"
const ACCELERATE: StringName = &"drive_accelerate"
const BRAKE: StringName = &"drive_brake"
## Physics ticks the van may take to cross the gate (out or back in) before the stage fails.
const DRIVE_TICKS: int = 900
## Physics ticks the van may take to stop once the pedal is let go.
const STOP_TICKS: int = 300
## Speed (m/s) under which the van counts as stopped.
const STOPPED_MPS: float = 0.3


## The fleet's vehicle `vehicle_id` of `level` (a CompanyRoot), or null.
static func van_of(level: CompanyRoot, vehicle_id: StringName) -> VehicleBody3D:
	return level.fleet.vehicle(String(vehicle_id)) as VehicleBody3D if level.fleet != null else null


## The player takes the wheel of the van parked in the yard and drives it out until its Trip starts,
## then lets it stop outside, still at the wheel. {"reason": "" when it left, else why; "metres": how
## far the van ended from where it was parked}.
static func drive_out(tree: SceneTree, level: CompanyRoot, vehicle_id: StringName) -> Dictionary:
	var trips: CompanyTrips = level.trips
	var van: VehicleBody3D = van_of(level, vehicle_id)
	if van == null:
		return {"reason": "no_van", "metres": 0.0}
	if trips.gate == null or trips.gate.side_of(van.global_position) != TripGate.INSIDE \
			or trips.trips_out() != 0:
		return {"reason": "van_not_in_yard", "metres": 0.0}
	var seat := van.get_node_or_null(SEAT_PATH) as SeatPoint
	if seat == null:
		return {"reason": "no_driver_seat", "metres": 0.0}
	# The seat has no reach check (the host trusts the interaction ray): no walk to the door.
	van.call(&"set_door_open", DRIVER_DOOR, true)
	seat.interact(level.player)
	await tree.physics_frame
	if int(van.get(&"driver_peer_id")) != level.player.get_multiplayer_authority():
		return {"reason": "not_at_wheel", "metres": 0.0}
	var start: Vector3 = van.global_position
	var left: bool = await hold_until(tree, ACCELERATE, func() -> bool: return trips.trip_of(vehicle_id) != null)
	await stop(tree, van)
	var metres: float = van.global_position.distance_to(start)
	if not left or trips.trips_out() != 1:
		return {"reason": "not_departed", "metres": metres}
	if trips.gate.side_of(van.global_position) != TripGate.OUTSIDE:
		return {"reason": "van_not_out", "metres": metres}
	return {"reason": "", "metres": metres}


## The driver backs the van out there into the yard until its Trip closes, lets it stop and gets out.
## "" when it is back inside, else why.
static func drive_back(tree: SceneTree, level: CompanyRoot, vehicle_id: StringName) -> String:
	var trips: CompanyTrips = level.trips
	var van: VehicleBody3D = van_of(level, vehicle_id)
	if van == null or int(van.get(&"driver_peer_id")) == 0:
		return "nobody_at_wheel"
	var back: bool = await hold_until(tree, BRAKE, func() -> bool: return trips.trip_of(vehicle_id) == null)
	await stop(tree, van)
	(level.player as Player).leave_seat()
	await tree.process_frame
	if not back or trips.gate.side_of(van.global_position) != TripGate.INSIDE:
		return "not_returned"
	return ""


## Holds the driving `action` down, a physics tick at a time, until `done` says so (true) or
## DRIVE_TICKS pass (false). The pedal is let go either way.
static func hold_until(tree: SceneTree, action: StringName, done: Callable) -> bool:
	Input.action_press(action)
	var reached: bool = false
	for _tick: int in DRIVE_TICKS:
		await tree.physics_frame
		if done.call():
			reached = true
			break
	Input.action_release(action)
	return reached


## Nobody on the pedal: the van brakes (vehicle.gd's idle brake) until it stands, at most STOP_TICKS.
static func stop(tree: SceneTree, van: VehicleBody3D) -> void:
	for _tick: int in STOP_TICKS:
		await tree.physics_frame
		if van.freeze or van.linear_velocity.length() < STOPPED_MPS:
			return
