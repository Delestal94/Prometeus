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
##   id, each its definition's scene with its variant and in CompanyTrips.VEHICLE_GROUP, parked past the gate's
##   line with its rear doors out of the shed and its nose away from it, sitting on the ground; no trip started
##   (trips_out() 0); the interest tracks its synchronizer and the host's cells anchor on it. build() with a
##   two-van fleet adds only the missing one, van_classic_2, parked beside it.
## - A player sits at the wheel (cab door open, the driver seat's interact(), as the host does): the van's
##   driver_peer_id is its peer and the player is seated there; getting up gives the wheel back.
## - With cargo staged on the van, moving it across the gate's line outward starts a trip with that order (OUT,
##   and out in the TripsView); back across it closes the trip.
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
			+ " it seats a driver, starts a trip across the gate and its copy follows the host's")
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
	_check_parked(level, van)
	await _check_tracked(level, van)
	await _check_second_van(level, fleet)
	await _check_seat(level, van)
	await _check_crossing(level, van)
	_free_level(level)
	await process_frame


## Parked past the gate's line, rear doors out of the shed, nose away from it, on the ground, no trip.
func _check_parked(level: CompanyRoot, van: VehicleBody3D) -> void:
	var trips: CompanyTrips = level.trips
	var outward: Vector3 = -level.shed.global_basis.z
	_expect(trips != null and trips.gate.side_of(van.global_position) == TripGate.OUTSIDE
		and trips.gate.distance(van.global_position) > CompanyShed.WALL_THICKNESS + CompanyFleet.PARK_GAP_M,
		"The van parks past the gate's line (%.2f m out)" % trips.gate.distance(van.global_position))
	var rear: Vector3 = van.to_global(Vector3(0.0, 1.0, 4.6))
	_expect(not level.shed.holds(rear) and trips.gate.distance(rear) > CompanyShed.WALL_THICKNESS,
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
			== TripGate.OUTSIDE, "...parked beside it, %.2f m apart, past the gate's line too" % apart)
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
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	trips.book.add(Order.make(&"o_fleet", "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0,
		products))
	trips.book.mark_packed(&"o_fleet", &"box_fleet")
	trips.stage_cargo(&"van_classic", [&"o_fleet"], [&"box_fleet"])
	var exit: Vector3 = CompanyFleet.exit_of(level.shed, level.net.company)
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
