extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_fleet.gd
##
## The company's vehicles in its world (expansion D-0302.2.b, with D-0316; CompanyFleet,
## scripts/gameplay/districts/company_fleet.gd, hooked in company_root.gd):
## - vehicle_ids(): an empty fleet is CompanyTuning.STARTING_FLEET; a "vehicle" fleet key takes the starting
##   fleet's definition first (van -> van_classic), an "id" names its own (van_vintage); entries naming nothing
##   that exists (a bike, junk) are skipped, at most MAX_VEHICLES; node_names() names the second of an id
##   "<id>_2" and never repeats a name.
## - Solo, company_root.tscn: World/Vehicles is a CompanyFleet holding exactly the fleet's vehicles, named by
##   id, each its definition's scene with its variant and in CompanyTrips.VEHICLE_GROUP, drivable outside a run
##   (test_company_van_drive) and parked in the playon, inside the gate (its far edge, CompanyFleet.gate_of()),
##   with its rear doors out of the shed and its nose away from it, sitting on the ground; no trip started
##   (trips_out() 0); the interest tracks its synchronizer and the host's cells anchor on it. build() with a
##   two-van fleet adds only the missing one, van_classic_2, parked beside it.
## - A player sits at the wheel (cab door open, the driver seat's interact(), as the host does): the van's
##   driver_peer_id is its peer and the player is seated there; getting up gives the wheel back.
## - With cargo staged on the van, moving it across the gate's line (the playon's far edge) outward starts a trip
##   with that order (OUT, and out in the TripsView); back across it closes the trip.
## - A rack of the van (a PackageMountPoint) taken by a box (its current_mount_path) is let go when the interest
##   hides that box's copy (copy_hidden: a stale copy kept it taken, D-0316.2) and taken back when it shows, unless
##   something else took it meanwhile; then the box's update taking it off that rack (current_mount_path empty)
##   leaves the rack to what holds it (package.gd, D-0316.4), while one off a rack it still holds frees it.
## - ENet pair in one process (the host on the NetworkManager autoload, the client on a second copy, each in
##   the real company_root.tscn, as test_company_online): the client builds the same
##   World/Vehicles/van_classic from the host's snapshot, a frozen copy it doesn't own. Until the client acks
##   it (its ack held back here, as if its snapshot had failed) the host's synchronizer stays closed to it and
##   no update arrives; an ack naming an unknown vehicle, too many, none, or from a peer that isn't there is
##   refused, also over the _have_fleet RPC. After the real ack (CompanyFleet.tell_host()) the copy receives
##   the host's updates, is shown, stands where the host's van does and follows it when it moves.
## - vehicle.gd: out of a run the parked van relays no vehicle_telemetry to the client; during one it does,
##   and it stops once the run ends.
## - The client's player takes the wheel (the seat's interact() on the host) and the client leaves: the host
##   frees the wheel (driver_peer_id 0, controls off) and the seat, and closes its vehicles to it.
## - The client at the wheel drives the host's van outside a run (D-0302.2.b.2): its copy is built
##   drivable_outside_run; once the host seats it, with its copy's controls set by hand (the input component reads
##   the host process's peer id here) the host's van is let go (net_simulating, its NetRestThrottle stops
##   resting), the client predicts its copy (is_predicted()), the host's van moves and the copy stays within a
##   metre of it; close_to() takes the client off the wheel and the van brakes, freezes within the parking wait
##   and its engine goes off.
## - D-0316.2, with the cap at 0 and cargo staged on the van: the client at the wheel drives it at the gate; the
##   host holds it inside (its centre never past the line, no trip, nothing out), the client's predicted copy
##   stays within 1.5 m of it and is never hidden, and only the client is told why (its TripsView's
##   departure_held, over _held_here, with WORLD_DISPATCH_FAR_LIMIT; the host's view tells nobody). Only the client
##   has a GateBrake (CompanyGateBrake, D-0316.4), braking its copy since the notice, on the host's very gate (same
##   side_of() and distance() all round the yard). Over a bad link (its copy's --net-sim 150 ms + 20 ms jitter),
##   driven at the playon's side at over 10 m/s: still held and predicted with no snap up to the gate; once told,
##   the client brakes its copy (over 60 ticks), with no snap during the hold and no jump (under 0.5 m a tick), and
##   the copy stays within 2.5 m of the host's van (before D-0316.4: one snap of ~3.1 m and a 5 m gap). Again with
##   the notice held back 85 ms on its way to the brake (a real link's half lag): no snap and no jump either; the
##   gap, the round trip it runs on before it is told, is only printed.
## - The van driven 1.1 km north in 200 m steps with the client's player in the shed: the client's copy ends up
##   hidden and out of physics (layer and mask 0); back at 600 m (2 cells) it shows, solid again, on the frame it
##   shows within 0.5 m of the host's van (drawn from the new pose, not slid from the old one).
## - No engine error on the way (a synchronizer reaching the client before its van existed logs one).

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const NETWORK_MANAGER := preload("res://scripts/core/network_manager.gd")
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const CREW_PROGRESSION: String = "res://scripts/core/crew_progression.gd"
const EVENT_BUS: String = "res://scripts/core/event_bus.gd"
const DIR: String = "user://test_company_fleet"
const PORT: int = 24691
const WAIT_SECONDS: float = 20.0
## vehicle.gd's RIDE_HEIGHT: how high its origin sits over flat ground once settled.
const RIDE_HEIGHT: float = 0.666
const SAME_M: float = 0.05
const SEAT_PATH: NodePath = ^"CabinInterior/DriverEyePoint/InteractionArea"
const HEN: Resource = preload("res://data/products/hen.tres")

var _failures: int = 0
var _catcher := ErrorCatcher.new()
var _host_session: NetSession
var _host_root: CompanyRoot
var _client_side: Node
var _client_session: NetSession
var _client_state: Node
var _client_root: CompanyRoot
## The client had its van when its snapshot came in (null: not seen yet).
var _van_at_snapshot: Variant = null


## Errors (not warnings) logged while the worlds come and go.
class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d in %s)"
			% [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = _messages.duplicate()
		_messages.clear()
		_mutex.unlock()
		return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	RpcGuard.reset()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	OS.add_logger(_catcher)
	_catcher.take()
	_check_ids()
	await _check_solo(state)
	state.call(&"reset")
	await _check_pair(state)
	var errors: Array[String] = _catcher.take()
	OS.remove_logger(_catcher)
	_expect(errors.is_empty(), "No engine error while the vehicles are built, used and sent (got %s)" % [errors])
	state.call(&"reset")
	_clean()
	if _failures == 0:
		print("PASS: the company's fleet parks outside the exit on every peer, named by id, in the vehicle group;"
			+ " it seats a driver, starts a trip across the gate (or is held there, its driver told why) and its copy"
			+ " follows the host's, hidden far and shown where it is")
	quit(_failures)


## vehicle_ids() and node_names() alone.
func _check_ids() -> void:
	var catalog := CompanyCatalog.load_all()
	var none: Array = []
	_expect(CompanyFleet.vehicle_ids(none, catalog) == CompanyTuning.STARTING_FLEET,
		"An empty fleet is the starting fleet %s (got %s)"
		% [CompanyTuning.STARTING_FLEET, CompanyFleet.vehicle_ids(none, catalog)])
	var vans: Array = [{"vehicle": &"van"}, {"vehicle": "van", "plate": "TMP-1"}, {"id": &"van_vintage"}]
	var ids: Array[StringName] = CompanyFleet.vehicle_ids(vans, catalog)
	_expect(ids == ([&"van_classic", &"van_classic", &"van_vintage"] as Array[StringName]),
		"The fleet key van is the starting van, an id names its own (got %s)" % [ids])
	var junk: Array = [{"vehicle": &"bike"}, {"id": "../van_classic"}, {"vehicle": 5}, "van", {"key": &"van"}]
	var kept: Array[StringName] = CompanyFleet.vehicle_ids(junk, catalog)
	_expect(kept == ([&"van_classic"] as Array[StringName]),
		"Entries naming no vehicle that exists are skipped; the key field counts (got %s)" % [kept])
	_expect(CompanyFleet.vehicle_ids([{"vehicle": &"bike"}], catalog) == CompanyTuning.STARTING_FLEET,
		"A fleet with no vehicle that exists is the starting fleet")
	var many: Array = []
	for _i: int in range(CompanyFleet.MAX_VEHICLES + 4):
		many.append({"vehicle": &"van"})
	_expect(CompanyFleet.vehicle_ids(many, catalog).size() == CompanyFleet.MAX_VEHICLES,
		"At most %d vehicles are built from one fleet" % CompanyFleet.MAX_VEHICLES)
	var twice: Array[StringName] = [&"van_classic", &"van_classic", &"van_classic_2", &"van_agile"]
	var names: Array[String] = CompanyFleet.node_names(twice)
	_expect(names[0] == "van_classic" and names[1] == "van_classic_2" and names[3] == "van_agile"
		and names[2] != names[1] and names.size() == 4,
		"Node names are the id, then <id>_2, never one twice (got %s)" % [names])


## The solo world: the fleet parked, seated, driven across the gate.
func _check_solo(state: Node) -> void:
	var level: CompanyRoot = _instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	for _tick: int in range(30):
		await physics_frame
	var fleet: CompanyFleet = level.get_node_or_null(^"World/Vehicles") as CompanyFleet
	_expect(fleet != null and fleet == level.fleet, "The world has its World/Vehicles CompanyFleet")
	if fleet == null:
		_free_level(level)
		return
	var catalog := CompanyCatalog.load_all()
	var fleet_entries: Variant = state.get(&"fleet")
	var ids: Array[StringName] = CompanyFleet.vehicle_ids(fleet_entries, catalog)
	var names: Array[String] = CompanyFleet.node_names(ids)
	var children: Array[String] = []
	for body: Node3D in fleet.vehicles():
		children.append(String(body.name))
	_expect(children == names and names == ["van_classic"],
		"Solo, World/Vehicles holds exactly the fleet's vehicles, by id (got %s, fleet %s)" % [children, names])
	var van: VehicleBody3D = fleet.vehicle("van_classic") as VehicleBody3D
	_expect(van != null, "The van is the definition's scene, a VehicleBody3D")
	if van == null:
		_free_level(level)
		return
	var definition: VehicleDefinition = catalog.vehicle(&"van_classic")
	_expect(van.scene_file_path == definition.scene.resource_path and van.get(&"variant_id") == definition.variant,
		"...with its definition's variant %s (got %s)" % [definition.variant, van.get(&"variant_id")])
	_expect(van.is_in_group(CompanyTrips.VEHICLE_GROUP) and van.freeze,
		"...in CompanyTrips.VEHICLE_GROUP, parked (frozen) on the host")
	_expect(bool(van.get(&"drivable_outside_run")), "...drivable outside a run")
	_check_parked(level, van)
	await _check_tracked(level, van)
	await _check_second_van(level, fleet)
	await _check_seat(level, van)
	await _check_crossing(level, van)
	await _check_rack_slot(level, van)
	_free_level(level)
	await process_frame


## Parked in the playon (inside the gate's line), rear doors out of the shed, nose away from it, on the ground, no
## trip.
func _check_parked(level: CompanyRoot, van: VehicleBody3D) -> void:
	var trips: CompanyTrips = level.trips
	var outward: Vector3 = -level.shed.global_basis.z
	var wall_out: float = trips.gate.distance(CompanyFleet.exit_of(level.shed, level.net.company)) \
		+ CompanyFleet.PLAYON_DEPTH_M + CompanyShed.WALL_THICKNESS
	var nose_tip: Vector3 = van.to_global(Vector3(0.0, 1.0, -2.7))
	_expect(trips != null and trips.gate.side_of(van.global_position) == TripGate.INSIDE
		and trips.gate.side_of(nose_tip) == TripGate.INSIDE and absf(wall_out) < SAME_M,
		"The van parks in the playon, inside the gate's line (%.2f m from it, nose %.2f m)"
		% [trips.gate.distance(van.global_position), trips.gate.distance(nose_tip)])
	var rear: Vector3 = van.to_global(Vector3(0.0, 1.0, 4.6))
	_expect(not level.shed.holds(rear) and trips.gate.distance(rear)
		< -CompanyFleet.PLAYON_DEPTH_M + CompanyFleet.PARK_GAP_M + 0.5 + CompanyShed.WALL_THICKNESS,
		"...its rear doors out of the shed and its wall (%s)" % rear)
	var nose: Vector3 = -van.global_basis.z
	_expect(nose.dot(outward) > 0.99, "...nose away from the shed (front %s, out %s)" % [nose, outward])
	var query := PhysicsRayQueryParameters3D.create(van.global_position + Vector3.UP, van.global_position
		+ Vector3.DOWN * 3.0, 1)
	var hit: Dictionary = van.get_world_3d().direct_space_state.intersect_ray(query)
	var height: float = van.global_position.y - (hit["position"] as Vector3).y if not hit.is_empty() else -1.0
	_expect(absf(height - RIDE_HEIGHT) < SAME_M, "...sitting on the ground (%.3f m over it)" % height)
	_expect(trips.trips_out() == 0 and level.trips_view.trips_out() == 0,
		"Parked, it started no trip (trips_out %d)" % trips.trips_out())


## The interest tracks the van's synchronizer; solo is the host, so the cells anchor on it.
func _check_tracked(level: CompanyRoot, van: VehicleBody3D) -> void:
	var sync := van.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	level.interest.step(Time.get_ticks_msec() / 1000.0 + 1.0)
	_expect(level.interest.is_tracked(sync), "The interest tracks the van's synchronizer (D-0316)")
	await process_frame
	var anchored: bool = false
	for at: Vector3 in level.cells.anchors:
		anchored = anchored or at.distance_to(van.global_position) < SAME_M
	_expect(anchored, "The host's cells anchor on the van (anchors %s)" % [level.cells.anchors])
	var throttle := van.get_node_or_null(^"NetRestThrottle") as NetRestThrottle
	var resting: bool = throttle != null and await _wait_for(func() -> bool: return throttle.is_resting(), 3.0)
	_expect(resting and sync.replication_interval >= throttle.rest_interval,
		"Parked, the van sends its pose at the rest interval (every %.3f s)" % sync.replication_interval)


## build() with a fleet of two vans adds only the missing one, beside the first.
func _check_second_van(level: CompanyRoot, fleet: CompanyFleet) -> void:
	var two: Node = (load(STATE_SCRIPT) as GDScript).new()
	two.set(&"fleet", [{"vehicle": &"van"}, {"vehicle": &"van"}] as Array[Dictionary])
	var added: int = fleet.build(two)
	two.free()
	var second: Node3D = fleet.vehicle("van_classic_2")
	var first: Node3D = fleet.vehicle("van_classic")
	_expect(added == 1 and second != null and second.is_in_group(CompanyTrips.VEHICLE_GROUP),
		"A two-van fleet adds van_classic_2 only (added %d)" % added)
	if second != null and first != null:
		var apart: float = Vector2(second.global_position.x - first.global_position.x,
			second.global_position.z - first.global_position.z).length()
		_expect(apart > CompanyFleet.PARK_SPACING_M - SAME_M and level.trips.gate.side_of(second.global_position)
			== TripGate.INSIDE, "...parked beside it, %.2f m apart, inside the gate's line too" % apart)
		second.free()
	await physics_frame


## The host seats a player at the wheel: the van's driver is its peer; getting up gives the wheel back.
func _check_seat(level: CompanyRoot, van: VehicleBody3D) -> void:
	var player: Player = level.player as Player
	var seat: Node = van.get_node_or_null(SEAT_PATH)
	_expect(player != null and seat is SeatPoint, "There is a player and the van has its driver's seat")
	if player == null or not seat is SeatPoint:
		return
	var home: Vector3 = player.global_position
	van.call(&"set_door_open", &"cab_left", true)
	_expect(bool(seat.call(&"can_interact", player)), "With the cab door open the player may take the wheel")
	seat.call(&"interact", player)
	await process_frame
	_expect(int(van.get(&"driver_peer_id")) == player.get_multiplayer_authority()
		and player.seat_node_path == (seat as Node).get_parent().get_path(),
		"Seated at the wheel, the van's driver is its peer (driver %d, seat %s)"
		% [van.get(&"driver_peer_id"), player.seat_node_path])
	player.leave_seat()
	await process_frame
	_expect(int(van.get(&"driver_peer_id")) == 0 and player.seat_node_path.is_empty(),
		"Getting up gives the wheel back (driver %d)" % van.get(&"driver_peer_id"))
	player.global_position = home
	await physics_frame


## Cargo staged on the van, moved across the gate's line outward: a trip with that order; back in, it closes.
func _check_crossing(level: CompanyRoot, van: VehicleBody3D) -> void:
	var trips: CompanyTrips = level.trips
	var parked: Transform3D = van.global_transform
	var products: Dictionary = {&"hen": HEN}
	trips.book.add(Order.make(&"o_fleet", "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0,
		products))
	trips.book.mark_packed(&"o_fleet", &"box_fleet")
	trips.stage_cargo(&"van_classic", [&"o_fleet"], [&"box_fleet"])
	var exit: Vector3 = CompanyFleet.gate_of(level.shed, level.net.company)
	var outward: Vector3 = -level.shed.global_basis.z
	await _put(van, exit - outward * 1.0)
	_expect(trips.trips_out() == 0, "Inside the gate's line with cargo staged, nothing has left yet")
	await _put(van, exit + outward * 3.0)
	var trip: Trip = trips.trip_of(&"van_classic")
	_expect(trips.trips_out() == 1 and trip != null and trip.order_ids == ([&"o_fleet"] as Array[StringName])
		and trips.book.state_of(&"o_fleet") == Order.STATE_OUT and level.trips_view.is_out(&"van_classic"),
		"Across the gate outward the van starts a trip with its order OUT (trips out %d)" % trips.trips_out())
	await _put(van, exit - outward * 1.0)
	_expect(trips.trips_out() == 0 and trips.book.state_of(&"o_fleet") == Order.STATE_FAILED
		and not level.trips_view.is_out(&"van_classic"), "Back across it the trip closes (trips out %d)"
		% trips.trips_out())
	van.global_transform = parked
	await physics_frame
	await physics_frame
	_expect(trips.trips_out() == 0, "Parked again with nothing staged, no trip starts")


## A rack taken by a box is let go while the interest hides the box's copy and taken back when it shows.
func _check_rack_slot(level: CompanyRoot, van: VehicleBody3D) -> void:
	var mount: Node = null
	for area: Node in van.find_children("*", "Area3D", true, false):
		if &"occupied_by" in area:
			mount = area
			break
	var box := (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate() as DeliveryPackage
	_expect(mount != null and box != null, "The van has racks (PackageMountPoint) and a box can be made")
	if mount == null or box == null:
		return
	level.add_child(box)
	box.current_mount_path = box.get_path_to(mount)
	_expect(mount.get(&"occupied_by") == box, "The box's current_mount_path takes the rack")
	level.interest.copy_hidden.emit(box)
	_expect(mount.get(&"occupied_by") == null, "Its copy hidden, the rack is free here")
	level.interest.copy_shown.emit(box)
	_expect(mount.get(&"occupied_by") == box, "Shown again, the box takes the rack back")
	level.interest.copy_hidden.emit(box)
	var other := Node.new()
	mount.set(&"occupied_by", other)
	level.interest.copy_shown.emit(box)
	_expect(mount.get(&"occupied_by") == other, "...but not from what took it while the copy was hidden")
	box.current_mount_path = NodePath()
	_expect(mount.get(&"occupied_by") == other,
		"...nor emptied under it when the box's update takes the box off that rack (current_mount_path, D-0316.4)")
	mount.set(&"occupied_by", null)
	box.current_mount_path = box.get_path_to(mount)
	box.current_mount_path = NodePath()
	_expect(mount.get(&"occupied_by") == null, "A box taken off a rack it still holds lets it go")
	other.free()
	box.queue_free()
	await process_frame


## Moves the (frozen) van and lets the gate look at it.
func _put(van: Node3D, at: Vector3) -> void:
	van.global_position = Vector3(at.x, van.global_position.y, at.z)
	await physics_frame
	await physics_frame


## Host and client in one process, each in the real world: the client's van is the host's.
func _check_pair(host_state: Node) -> void:
	_host_session = root.get_node(^"/root/NetworkManager") as NetSession
	_host_session.transport = NetSession.Transport.ENET
	_host_session.session_scene = SCENE
	var hosted: bool = _host_session.host_session(PORT) == OK
	_expect(hosted, "The host opens an ENet room on localhost:%d" % PORT)
	if hosted:
		_host_root = _instantiate()
		root.add_child(_host_root)
		current_scene = _host_root
		await process_frame
		if await _join():
			await _check_copy()
	await _tear_down()
	host_state.call(&"reset")


## The client joins: its world comes up, the host sends the snapshot, the client builds its van.
func _join() -> bool:
	_client_side = Node.new()
	_client_side.name = "ClientSide"
	root.add_child(_client_side)
	set_multiplayer(SceneMultiplayer.new(), _client_side.get_path())
	_client_session = NETWORK_MANAGER.new() as NetSession
	_client_session.name = "NetworkManager"
	_client_side.add_child(_client_session)
	_client_side.add_child(_client_crew_progression())
	# The client's own EventBus (each process has one): the host's van relays its telemetry through it.
	var bus: Node = (load(EVENT_BUS) as GDScript).new()
	bus.name = "EventBus"
	_client_side.add_child(bus)
	_client_state = (load(STATE_SCRIPT) as GDScript).new()
	_client_state.name = "CompanyState"
	_client_side.add_child(_client_state)
	_client_state.call(&"reset")
	_client_session.transport = NetSession.Transport.ENET
	_client_session.session_ready.connect(_on_client_session_ready)
	_expect(_client_session.join_session("127.0.0.1", PORT) == OK, "The client starts joining")
	var joined: bool = await _wait_for(func() -> bool:
		return (_client_root != null and _client_root.fleet != null
			and _client_root.fleet.vehicle("van_classic") != null and not _client_root.net.awaiting_snapshot()))
	_expect(joined, "The client's world builds World/Vehicles/van_classic from the host's snapshot")
	return joined


func _check_copy() -> void:
	var client_id: int = _client_side.multiplayer.get_unique_id()
	var host_fleet: CompanyFleet = _host_root.fleet
	var client_fleet: CompanyFleet = _client_root.fleet
	var host_van: VehicleBody3D = host_fleet.vehicle("van_classic") as VehicleBody3D
	var copy: VehicleBody3D = client_fleet.vehicle("van_classic") as VehicleBody3D
	_expect(host_van != null and copy != null and copy.get_path() != host_van.get_path()
		and _host_root.get_path_to(host_van) == _client_root.get_path_to(copy),
		"Both worlds hold the van at the same path under their root")
	if host_van == null or copy == null:
		return
	_expect(_van_at_snapshot == true, "The client has its van once the snapshot is in (got %s)" % [_van_at_snapshot])
	_expect(not copy.is_multiplayer_authority() and copy.freeze and copy.is_in_group(CompanyTrips.VEHICLE_GROUP),
		"The client's copy is the host's, frozen, in the vehicle group")
	var host_sync := host_van.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var copy_sync := copy.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var received: Array[int] = [0]
	for arrived: Signal in [copy_sync.synchronized, copy_sync.delta_synchronized]:
		arrived.connect(func() -> void: received[0] += 1)
	var telemetry: Array[int] = [0]
	_client_side.get_node(^"EventBus").connect(&"vehicle_telemetry", func(_kmh: float) -> void: telemetry[0] += 1)
	# The snapshot is in and the van built, but this client hasn't acked it (its ack is held back, as if its
	# snapshot had failed): the host's synchronizer stays closed to it, and nothing of the van arrives.
	await _seconds(1.0)
	_expect(not host_fleet.is_open_to(client_id, "van_classic") and received[0] == 0,
		"Without the client's ack the host's van stays closed to it (open %s, %d updates)"
		% [host_fleet.is_open_to(client_id, "van_classic"), received[0]])
	_expect(telemetry[0] == 0, "Out of a run the parked van relays no telemetry to the client (got %d)" % telemetry[0])
	await _check_bad_acks(host_fleet, client_fleet, client_id)
	_expect(client_fleet.tell_host(), "The client tells the host which vehicles it has")
	var opened: bool = await _wait_for(func() -> bool:
		return host_fleet.is_open_to(client_id, "van_classic") and host_sync.get_visibility_for(client_id))
	_expect(opened, "After its ack the host's van synchronizer reaches the client")
	var follows: Callable = func() -> bool:
		return (received[0] > 0 and not _client_root.interest.is_hidden_here(copy_sync)
			and copy.global_position.distance_to(host_van.global_position) < SAME_M)
	_expect(await _wait_for(follows), "The client's copy gets the host's updates, is shown and stands where the"
		+ " host's van does (%s vs %s, %d updates)" % [copy.global_position, host_van.global_position, received[0]])
	host_van.global_position += Vector3(2.0, 0.0, -1.0)
	_expect(await _wait_for(follows), "...and follows it when the host moves it (%s vs %s)"
		% [copy.global_position, host_van.global_position])
	await _check_run_telemetry(telemetry)
	await _check_client_drives(host_van, copy, client_id)
	await _check_held_at_gate(host_van, copy, client_id)
	await _check_far_copy(host_van, copy)
	await _check_driver_leaves(host_van, client_id)


## Bad acks change nothing: an unknown vehicle, too many names, a peer that isn't there, and the same over the RPC.
func _check_bad_acks(host_fleet: CompanyFleet, client_fleet: CompanyFleet, client_id: int) -> void:
	var many := PackedStringArray()
	for _i: int in range(CompanyFleet.MAX_VEHICLES + 1):
		many.append("van_classic")
	var unknown := PackedStringArray(["van_classic", "nope"])
	_expect(not host_fleet.ack(client_id, unknown) and not host_fleet.ack(client_id, many)
		and not host_fleet.ack(client_id, PackedStringArray())
		and not host_fleet.ack(4242, PackedStringArray(["van_classic"]))
		and not host_fleet.is_open_to(client_id, "van_classic"),
		"An ack naming an unknown vehicle, too many, none, or from a peer that isn't there is refused")
	client_fleet.rpc_id(1, &"_have_fleet", unknown)
	client_fleet.rpc_id(1, &"_have_fleet", many)
	await _seconds(0.3)
	_expect(not host_fleet.is_open_to(client_id, "van_classic"), "...and so is a bad _have_fleet from the client")


## During a run the host's van relays its telemetry to the client again; once it ends, it stops.
func _check_run_telemetry(telemetry: Array[int]) -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	telemetry[0] = 0
	run.set(&"is_running", true)
	await _seconds(0.6)
	run.set(&"is_running", false)
	var during: int = telemetry[0]
	await _seconds(0.3)
	var after_end: int = telemetry[0]
	await _seconds(0.5)
	run.call(&"reset_run")
	_expect(during > 0 and telemetry[0] == after_end,
		"During a run the client gets the van's telemetry (%d), none once it ended (%d more)"
		% [during, telemetry[0] - after_end])


## The client's player takes the wheel and drives its copy (controls set by hand: in this process the input
## component compares with the host's peer id); close_to() then takes it off the wheel.
func _check_client_drives(host_van: VehicleBody3D, copy: VehicleBody3D, client_id: int) -> void:
	_expect(bool(copy.get(&"drivable_outside_run")), "The client's copy is drivable outside a run too")
	var seat := host_van.get_node_or_null(SEAT_PATH) as SeatPoint
	var driver: Node = _host_root.get_node_or_null(NodePath("World/Player_%d" % client_id))
	if seat == null or driver == null:
		_expect(false, "The host has the van's driver seat and the client's player")
		return
	var constants: Dictionary = (host_van.get_script() as GDScript).get_script_constant_map()
	var park_wait: float = float(constants["PARK_MAX_WAIT_SECONDS"])
	var throttle := host_van.get_node(^"NetRestThrottle") as NetRestThrottle
	_expect(host_van.freeze and not host_van.net_simulating, "Parked, the host's van is frozen and not simulating")
	var start: Vector3 = host_van.global_position
	host_van.call(&"set_door_open", &"cab_left", true)
	seat.interact(driver)
	_expect(int(host_van.get(&"driver_peer_id")) == client_id, "The host seats the client at the wheel")
	var awake_at: int = -1
	var predicted_at: int = -1
	for tick: int in range(150):
		copy.call(&"set_controls", 1.0, 0.0, false)
		await physics_frame
		if awake_at < 0 and not throttle.is_resting():
			awake_at = tick
		if predicted_at < 0 and copy.is_predicted():
			predicted_at = tick
	_expect(host_van.net_simulating and not host_van.freeze, "The host's van is let go and simulating")
	_expect(awake_at >= 0 and awake_at < 10,
		"...its NetRestThrottle stops resting within 10 ticks (tick %d)" % awake_at)
	_expect(predicted_at >= 0, "...the client predicts its copy (is_predicted, from tick %d)" % predicted_at)
	var moved: float = host_van.global_position.distance_to(start)
	var gap: float = copy.global_position.distance_to(host_van.global_position)
	_expect(moved > 2.0 and gap < 1.0, "...the host's van moved %.1f m and the copy is %.2f m from it" % [moved, gap])
	_expect(bool(host_van.get(&"presentation_engine_running")), "...with its engine on")
	_host_root.fleet.close_to(client_id)
	_expect(int(host_van.get(&"driver_peer_id")) == 0, "close_to() takes the client off the wheel")
	var froze_at: float = -1.0
	for tick: int in range(int((park_wait + 4.0) * 60.0)):
		await physics_frame
		if host_van.freeze:
			froze_at = float(tick) / 60.0
			break
	_expect(froze_at >= 0.0 and froze_at < park_wait + 1.0 and bool(host_van.get(&"_parked")),
		"...the van brakes and freezes within the parking wait (after %.1f s)" % froze_at)
	_expect(not bool(host_van.get(&"presentation_engine_running")), "...and its engine is off")
	# The client's player climbs out (its own gesture), so the seat is free for the next check.
	var own: Player = _client_root.get_node_or_null(NodePath("World/Player_%d" % client_id)) as Player
	if own != null:
		own.leave_seat()
	var seat_free: Callable = func() -> bool:
		return (driver as Player).seat_node_path.is_empty() and seat.occupant == null
	_expect(await _wait_for(seat_free), "The client's player gets out and the seat is free again")


## D-0316.2: the cap at 0 and cargo staged; the client drives the van at the gate and is held there, and told why.
func _check_held_at_gate(host_van: VehicleBody3D, copy: VehicleBody3D, client_id: int) -> void:
	var trips: CompanyTrips = _host_root.trips
	var seat := host_van.get_node_or_null(SEAT_PATH) as SeatPoint
	var driver: Node = _host_root.get_node_or_null(NodePath("World/Player_%d" % client_id))
	if seat == null or driver == null:
		_expect(false, "The host has the van's driver seat and the client's player")
		return
	# close_to() (the last check) closed the van to the client: it acks again, and its copy, still at the wheel there
	# with the pedal down, hears it no longer is.
	copy.call(&"set_controls", 0.0, 0.0, false)
	_expect(_client_root.fleet.tell_host() and await _wait_for(func() -> bool:
		return _host_root.fleet.is_open_to(client_id, "van_classic") and not copy.is_predicted()),
		"The client acks the van again and its copy stops predicting")
	host_van.call(&"park", CompanyFleet.park_transform(_host_root.shed, _host_root.net.company, 0))
	_expect(await _wait_for(func() -> bool: return copy.global_position.distance_to(host_van.global_position) < 0.1),
		"Parked back in the playon, the copy stands where the host's van does")
	var products: Dictionary = {&"hen": HEN}
	trips.book.add(Order.make(&"o_held", "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0,
		products))
	trips.book.mark_packed(&"o_held", &"box_held")
	trips.stage_cargo(&"van_classic", [&"o_held"], [&"box_held"])
	trips.far_max = 0
	var told: Array = []
	_client_root.trips_view.departure_held.connect(func(id: StringName, text: String) -> void:
		told.append([id, text]))
	var host_told: Array[int] = [0]
	_host_root.trips_view.departure_held.connect(func(_id: StringName, _text: String) -> void: host_told[0] += 1)
	host_van.call(&"set_door_open", &"cab_left", true)
	seat.interact(driver)
	var copy_sync := copy.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var worst_past: float = -INF
	var worst_gap: float = 0.0
	var ever_hidden: bool = false
	for tick: int in range(480):
		copy.call(&"set_controls", 1.0, 0.0, false)
		await physics_frame
		worst_past = maxf(worst_past, trips.gate.distance(host_van.global_position))
		if copy.is_predicted():
			worst_gap = maxf(worst_gap, copy.global_position.distance_to(host_van.global_position))
		ever_hidden = ever_hidden or _client_root.interest.is_hidden_here(copy_sync)
	_expect(worst_past < 0.4 and worst_past > -2.0 and trips.trips_out() == 0 and trips.trip_of(&"van_classic") == null,
		"The host holds the van at the gate: its centre reached the line, never a tick's travel past it (%.2f m)"
		% worst_past)
	_expect(worst_gap < 1.5 and not ever_hidden,
		"...the client's predicted copy stays within 1.5 m of it (worst %.2f m) and is never hidden" % worst_gap)
	_check_brake_gate(trips.gate, _client_root.gate_brake)
	var text: String = tr(CompanyTrips.FAR_LIMIT)
	if text.count("%") == 1:
		text = text % 0
	_expect(told.size() >= 1 and told[0] == [&"van_classic", text] and host_told[0] == 0,
		"...and only the client, its driver, is told why (client %s, host %d)" % [told, host_told[0]])
	var own: Player = _client_root.get_node_or_null(NodePath("World/Player_%d" % client_id)) as Player
	if own != null:
		own.leave_seat()
	_expect(await _wait_for(func() -> bool: return seat.occupant == null and not copy.is_predicted()),
		"The client gets out of the held van")
	await _check_held_lagged(host_van, copy, seat, driver)
	await _check_held_lagged(host_van, copy, seat, driver, 85)
	trips.far_max = CompanyTuning.VEHICLES_FAR_MAX
	trips.forget(&"van_classic")


## D-0316.4: only the client has a GateBrake, braking its copy since the notice, and it stands on the host's gate.
func _check_brake_gate(host_gate: TripGate, brake: CompanyGateBrake) -> void:
	_expect(_host_root.gate_brake == null and brake != null and brake.is_braking(&"van_classic"),
		"...only the client has a GateBrake, and it brakes its copy since the notice")
	if brake == null or brake.gate() == null:
		return
	var origin: Vector3 = CompanyFleet.gate_of(_host_root.shed, _host_root.net.company)
	var same: bool = true
	for x: float in [-14.0, -12.0, 0.0, 12.0, 14.0]:
		for z: float in [-30.0, -2.0, 0.0, 2.0, 30.0]:
			var at: Vector3 = origin + Vector3(x, 0.0, z)
			same = same and brake.gate().side_of(at) == host_gate.side_of(at) \
				and is_equal_approx(brake.gate().distance(at), host_gate.distance(at))
	_expect(same, "...on the host's gate: the same line and the same yard (CompanyFleet.trip_gate())")


## The same hold over a bad link (--net-sim 150 ms, 20 ms jitter on the client's copy): the van faces the playon's
## side, ~13 m of run-up, and the client drives it at the edge at ~12 m/s. The host holds it and, once told, the client
## brakes its own copy there too (CompanyGateBrake, D-0316.4): no snap, the copy within 2.5 m of the host's van.
## `notice_late_ms` holds the notice back on its way to the client's brake, as a real link would (here it is an RPC
## over localhost, while the copy's states come the link's half lag late).
func _check_held_lagged(host_van: VehicleBody3D, copy: VehicleBody3D, seat: SeatPoint, driver: Node,
		notice_late_ms: int = 0) -> void:
	var trips: CompanyTrips = _host_root.trips
	var brake: CompanyGateBrake = _client_root.gate_brake
	var view: CompanyTripsView = _client_root.trips_view
	var start: Transform3D = CompanyFleet.park_transform(_host_root.shed, _host_root.net.company, 0)
	host_van.call(&"park", Transform3D(Basis(Vector3.UP, -PI * 0.5) * start.basis, start.origin))
	_expect(await _wait_for(func() -> bool: return copy.global_position.distance_to(host_van.global_position) < 0.1),
		"Turned to the playon's side, the copy stands where the host's van does")
	# The last hold's brake runs out first (and with it the host's pause between two notices): this one starts told
	# nothing, so the brake comes only from its own notice.
	_expect(await _wait_for(func() -> bool: return not brake.is_braking(&"van_classic")),
		"The client's brake from the last hold has let go")
	var late: Array = []
	var hold_late: Callable = func(id: StringName, cap: int) -> void:
		late.append([Time.get_ticks_msec() + notice_late_ms, id, cap])
	if notice_late_ms > 0:
		view.held_at_gate.disconnect(brake.hold)
		view.held_at_gate.connect(hold_late)
	copy.call(&"configure_net_sim", {"lag_ms": 150, "jitter_ms": 20, "loss_pct": 0.0})
	var prediction: Object = copy.get(&"_prediction")
	var reconciler: NetPredictionReconciler = prediction.get(&"reconciler")
	var snaps_before: int = reconciler.snaps
	host_van.call(&"set_door_open", &"cab_left", true)
	seat.interact(driver)
	var top_speed: float = 0.0
	var worst_shift: float = 0.0
	var worst_gap: float = 0.0
	var worst_out: float = 0.0
	var worst_jump: float = 0.0
	var was_at: Vector3 = copy.global_position
	var predicted_ticks: int = 0
	var braked_ticks: int = 0
	var held: Array[bool] = [false]
	var on_held: Callable = func(_id: StringName, _reason: Dictionary, _driver: int) -> void: held[0] = true
	trips.departure_held.connect(on_held)
	# Before the hold, the same link: what the prediction does at that speed anyway.
	var before: Array[float] = [0.0, 0.0]
	var snaps_free: int = -1
	for _tick: int in range(420):
		while not late.is_empty() and Time.get_ticks_msec() >= int(late[0][0]):
			brake.hold(late[0][1], late[0][2])
			late.pop_front()
		copy.call(&"set_controls", 1.0, 0.0, false)
		await physics_frame
		var flat := Vector3(host_van.linear_velocity.x, 0.0, host_van.linear_velocity.z)
		top_speed = maxf(top_speed, flat.length())
		if held[0] and snaps_free < 0:
			snaps_free = reconciler.snaps - snaps_before
		if brake.is_braking(&"van_classic"):
			braked_ticks += 1
		var moved: float = copy.global_position.distance_to(was_at)
		was_at = copy.global_position
		if not copy.is_predicted():
			continue
		predicted_ticks += 1
		var shift: float = float(prediction.get(&"last_shift"))
		var gap: float = copy.global_position.distance_to(host_van.global_position) if predicted_ticks > 30 else 0.0
		if held[0]:
			worst_shift = maxf(worst_shift, shift)
			worst_gap = maxf(worst_gap, gap)
			worst_out = maxf(worst_out, _out_of_compound(copy.global_position))
			worst_jump = maxf(worst_jump, moved)
		else:
			before = [maxf(before[0], shift), maxf(before[1], gap)]
	trips.departure_held.disconnect(on_held)
	if notice_late_ms > 0:
		view.held_at_gate.disconnect(hold_late)
		brake.attach(view)
	var snaps: int = reconciler.snaps - snaps_before - maxi(snaps_free, 0)
	print("test_company_fleet: held at the gate over 150 ms + 20 ms jitter, the notice %d ms late: top %.1f m/s;"
		% [notice_late_ms, top_speed] + " before the hold worst shift %.2f m, gap %.2f m, %d snaps;"
		% [before[0], before[1], maxi(snaps_free, 0)] + " held: worst shift %.2f m, gap %.2f m, %d snaps,"
		% [worst_shift, worst_gap, snaps] + " the copy at most %.2f m out of the compound and %.2f m in a tick,"
		% [worst_out, worst_jump] + " braked %d ticks" % braked_ticks)
	_expect(top_speed > 10.0 and trips.trips_out() == 0 and trips.trip_of(&"van_classic") == null,
		"Lagged, the client drives the van at the side at %.1f m/s and the host still holds it" % top_speed)
	_expect(predicted_ticks > 30 and before[0] < NetPredictionReconciler.SNAP_DISTANCE and snaps_free <= 0,
		"...and predicts its copy up to the gate with no snap (worst shift %.2f m)" % before[0])
	# Before D-0316.4 the copy ran on past the line for a round trip and the host's stop was snapped in: one snap of
	# 3.05-3.17 m at 12 m/s, the copy ~5 m from the host's van.
	_expect(held[0] and braked_ticks > 60,
		"...its GateBrake brakes the client's copy at the gate once told (%d ticks)" % braked_ticks)
	_expect(snaps == 0 and worst_jump < 0.5,
		"...with no snap (%d, worst shift %.2f m) and no jump: at most %.2f m a tick, its own speed's"
		% [snaps, worst_shift, worst_jump])
	# The notice late, the copy runs on that much longer before it brakes: the gap is the round trip's, only printed.
	_expect(notice_late_ms > 0 or worst_gap < 2.5,
		"...and the copy within 2.5 m of the host's van (worst %.2f m)" % worst_gap)
	copy.call(&"configure_net_sim", {"lag_ms": 0, "jitter_ms": 0, "loss_pct": 0.0})
	var own: Player = _client_root.get_node_or_null(NodePath("World/Player_%d" % driver.get_multiplayer_authority())) \
		as Player
	if own != null:
		own.leave_seat()
	_expect(await _wait_for(func() -> bool: return seat.occupant == null), "The client gets out of the held van")


## How far `at` is out of the compound (the host's gate yard: past the playon's far edge or a side), 0 inside it.
func _out_of_compound(at: Vector3) -> float:
	var company: Object = _host_root.net.company
	var origin: Vector3 = CompanyFleet.gate_of(_host_root.shed, company)
	var north: Vector3 = -_host_root.shed.global_basis.z
	var off := Vector3(at.x - origin.x, 0.0, at.z - origin.z)
	var past_side: float = absf(off.dot(north.cross(Vector3.UP).normalized())) \
		- CompanyFleet.yard_half_width_m(company)
	return maxf(maxf(off.dot(north), past_side), 0.0)


## The van far from the client's player and back: its copy hides, out of physics, and shows where the host has it.
func _check_far_copy(host_van: VehicleBody3D, copy: VehicleBody3D) -> void:
	var copy_sync := copy.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var interest: CompanyInterest = _client_root.interest
	var start: Transform3D = CompanyFleet.park_transform(_host_root.shed, _host_root.net.company, 0)
	var north: Vector3 = -_host_root.shed.global_basis.z
	for metres: float in [200.0, 400.0, 600.0, 800.0, 1000.0, 1100.0]:
		host_van.call(&"park", start.translated(north * metres))
		await _seconds(0.4)
	var hidden: bool = await _wait_for(func() -> bool: return interest.is_hidden_here(copy_sync), 5.0)
	_expect(hidden and not copy.visible and copy.collision_layer == 0 and copy.collision_mask == 0,
		"1.1 km from the client's player the copy is hidden and out of physics (hidden %s)" % hidden)
	host_van.call(&"park", start.translated(north * 600.0))
	# Checked at the start of each frame: the first time it is shown, as the last frame drew it.
	var shown: bool = await _wait_for(func() -> bool: return not interest.is_hidden_here(copy_sync), 5.0)
	var shown_gap: float = copy.global_position.distance_to(host_van.global_position)
	_expect(shown and copy.visible and copy.collision_layer != 0,
		"Back at 600 m (2 cells) it shows, solid again (layer %d)" % copy.collision_layer)
	_expect(shown_gap < 0.5,
		"...on the frame it shows, within 0.5 m of the host's van (%.2f m): drawn from the new pose" % shown_gap)
	host_van.call(&"park", start)
	await _seconds(0.5)


## The client sits at the wheel of the host's van and leaves: the host takes it off the wheel and the seat.
func _check_driver_leaves(host_van: VehicleBody3D, client_id: int) -> void:
	var seat := host_van.get_node_or_null(SEAT_PATH) as SeatPoint
	var driver: Node = _host_root.get_node_or_null(NodePath("World/Player_%d" % client_id))
	_expect(seat != null and driver != null, "The host has the van's driver seat and the client's player")
	if seat == null or driver == null:
		return
	host_van.call(&"set_door_open", &"cab_left", true)
	seat.interact(driver)
	_expect(int(host_van.get(&"driver_peer_id")) == client_id and host_van.get(&"controls_enabled") == true
		and seat.occupant == driver,
		"The client's player takes the wheel (driver %d)" % host_van.get(&"driver_peer_id"))
	_client_session.leave_session()
	var released: bool = await _wait_for(func() -> bool:
		return int(host_van.get(&"driver_peer_id")) == 0 and not _host_root.fleet.is_open_to(client_id, "van_classic"))
	_expect(released and host_van.get(&"controls_enabled") == false and seat.occupant == null,
		"The driver leaving frees the wheel and the seat on the host, and closes its vehicles (driver %d)"
		% host_van.get(&"driver_peer_id"))


## Client: the snapshot is in; its fleet built the van, but the ack is held back here (_check_copy() sends it).
func _on_client_snapshot(_snapshot_seq: int) -> void:
	_client_root.fleet.build(_client_root.net.company)
	if _van_at_snapshot == null:
		_van_at_snapshot = _client_root.fleet.vehicle("van_classic") != null


## Client: the handshake picked its level; it is built next frame, as the menu's loader would.
func _on_client_session_ready(is_host: bool) -> void:
	if not is_host:
		_enter_client_world.call_deferred()


func _enter_client_world() -> void:
	var level: CompanyRoot = _instantiate()
	level.session = _client_session
	level.company_state = _client_state
	_client_side.add_child(level)
	_client_root = level
	# The fleet's own handler builds and acks; this one only builds, so the test decides when the ack goes.
	level.net.company_state_restored.disconnect(level.fleet._on_snapshot)
	level.net.company_state_restored.connect(_on_client_snapshot)


func _tear_down() -> void:
	if _client_root != null and is_instance_valid(_client_root):
		_client_root.queue_free()
	if _client_session != null and is_instance_valid(_client_session):
		_client_session.leave_session()
	if _host_root != null and is_instance_valid(_host_root):
		_host_root.queue_free()
	current_scene = null
	if _host_session != null:
		_host_session.leave_session()
		_host_session.transport = NetSession.Transport.AUTO
	await process_frame
	await process_frame
	if _client_side != null and is_instance_valid(_client_side):
		set_multiplayer(null, _client_side.get_path())
		_client_side.free()
	RpcGuard.reset()


## The client's own CrewProgression autoload, as test_company_online's: the real script's RPCs, nothing else.
func _client_crew_progression() -> Node:
	var script := GDScript.new()
	script.source_code = "extends \"%s\"\n\n\nfunc _ready() -> void:\n\tpass\n" % CREW_PROGRESSION
	var stand_in: Node = script.new() if script.reload() == OK else Node.new()
	stand_in.name = "CrewProgression"
	return stand_in


func _instantiate() -> CompanyRoot:
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	return level


func _free_level(level: Node) -> void:
	level.queue_free()
	current_scene = null


## Waits `seconds` of real time, frame by frame.
func _seconds(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _wait_for(done: Callable, seconds: float = WAIT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
