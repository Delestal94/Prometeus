extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_bandwidth_budget.gd
##
## Bandwidth budgets of the company mode (D-2002; the numbers are in docs/rendimiento-pc.md): what
## the host sends one client, with D-2002's 4 players and with the full crew
## (NetworkManager.MAX_PLAYERS, 8), in three cases (tests/company_bandwidth_cases.gd, CASES, holds
## the cases and their constants):
## - shed (D-2002.1, D-2002.3): the whole crew works in the shed. 24 KB/s;
## - trip (D-2002.2): one company vehicle drives out with TRIP_RIDERS aboard while the rest works in
##   the shed, still near it (within CompanyTuning.CELL_LOAD_RADIUS cells: the shed's clients get
##   the vehicle and its load too). 40 KB/s;
## - far (D-2002.2): CompanyTuning.VEHICLES_FAR_MAX vehicles out (2), TRIP_RIDERS aboard each (at
##   most all but SHED_STAYS players), past CELL_UNLOAD_RADIUS cells from the shed (CompanyInterest
##   sends them only to their riders) but near each other, on one road (each rider gets
##   both). 64 KB/s.
## Aboard a vehicle: a driver and a passenger who tends a box (roles-tripulacion.md §2.3-2.4, "Ruta
## 1-2"; a lone driver tends his own) and a full load (its definition's cargo_slots). A case's
## number is its worst client: the host in the shed or aboard any vehicle, every client
## (CASES.worst()). Every case must fit its budget with 4 players (MEASURED_CREW); the full crew
## where FULL_CREW_FITS says it does (the shed, far), else its over_budget line and culprits are printed,
## not failed. The crowded trips (CROWDED_RIDERS aboard, the design's ceiling, one player left in
## the shed) are printed only.
## - Model (tests/bandwidth_model.gd, the framing test_net_bandwidth_budget counts with): the real
##   company world (company_root.tscn, solo) is opened and every MultiplayerSynchronizer in it
##   counted at the interval the world leaves it on: the shed's own once (the host's), a parked
##   vehicle at its NetRestThrottle's rest (waited for: is_resting()), and the player's once per
##   crew member (the host's own, the other clients' relayed by the host): on foot at the shed's
##   pose rate (CompanyRoot.join_crew(), CompanyTuning.SHED_POSE_RATE_HZ: player_pose_rate), seated
##   aboard (Player.net_in_vehicle, a seat: the driver and the passenger with the box on the lap) at
##   the rate the world gives a seated rider (player_ride.gd apply_pose_rate(), SEATED_POSE_RATE_HZ:
##   rider_pose_rate; standing in a bay, the game's). The fleet's vehicle (CompanyFleet,
##   World/Vehicles) is driven across the shed's gate and back by code with a full load staged: its
##   synchronizer at the rate it sends while it moves (CompanyTuning.FLEET_POSE_INTERVAL_SEC, not
##   its scene's), and the real trip_started and trip_closed the host's CompanyTripsView publishes.
##   The load is package.tscn's synchronizer (BoxToPackage.PACKAGE_SCENE): the tended boxes moving,
##   each publishing its care_state (the largest real one publish_care() leaves, of any trap) at the
##   company's rate (BoxToPackage.tune()), an ON_CHANGE delta; the rest riding still at the rest
##   interval. While vehicles are out, each player in the shed carries a box loading the next one,
##   moving (D-2002.4, the caveats of auditor-red on D-2002.2). Floats as 64-bit and ints as 32-bit
##   (a pose in motion, a clock past 33 s) and a datagram at Steam's ceiling around every packet. On
##   top, the business events (CompanyNet's _apply_event, reliable, sized the same way) of a busy
##   line: every player does a business action a second (aboard, a delivery) plus the host's own
##   rules, each the size of the largest real units_moved the root publishes (a drop and a take
##   through CompanyNet), in a datagram of its own; and a trip event a second per vehicle out (the
##   larger real one: a ceiling, a trip sends two). Far, CompanyInterest's keepalive: a client in
##   the shed gets every hidden body for its pulse, each client in the shed on its own clock, and a
##   pulse wakes a box riding still for the riders as many times as a real box's NetRestThrottle
##   wakes for WorldCellInterest.pulse_visibility() (none since D-2002.4). Nothing in the world
##   sends a property of more than 64 bytes every tick.
## - Measured, every case: that many ENet peers on localhost in this process (a SceneMultiplayer
##   each), a real player per peer on every side (player.tscn, joined to the crew as the company
##   world does it, standing still; a rider's owner sends as one, net_in_vehicle) and a CompanyNet;
##   out of the shed, the vehicles out (their definition's scene at the fleet's interval), their
##   loads (package.tscn; the tended ones publish the measured care_state) and the boxes carried in
##   the shed on every side, the host's reaching the clients that see them as CompanyInterest
##   decides. The host publishes real units_moved at the busy rate; read as the network overlay reads LAN (NetStats,
##   N-216). Every client stays under its own model's ceiling and, where held, the worst under the
##   budget; the worst got over half of its model's data (it did flow; skipped under two frames of
##   the fastest pose), and every client applies every event. Trip events and the keepalive are only
##   in the model. If a session of 4 players doesn't come up on localhost it fails; the full crew's
##   is then only printed as skipped.
## - The late-join snapshot of the furnished shed, a one-off burst, is printed.
## Prints `COMPANY_BW key=value` lines.

const MODEL := preload("res://tests/bandwidth_model.gd")
const CASES := preload("res://tests/company_bandwidth_cases.gd")
const RIDE := preload("res://scripts/gameplay/player/player_ride.gd")
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const TRAPS_DIR: String = "res://data/traps"
## A seat a rider's owner says it sits on (Player.seat_node_path): only whether it is empty counts.
const SEAT_PATH: NodePath = ^"Seat"
## The company saves here (the root saves on leaving), never in the game's slot.
const SAVE_DIR: String = "user://test_company_bandwidth_budget"
const PREFIX: String = "COMPANY_BW"
const KB: float = CASES.KB
## The ids a trip carries late in the game ("d100_o01", "box_1000"): as long as the real ones get.
const LATE_DAY: int = 100
const LATE_BOX: int = 1000
## As test_net_bandwidth_budget: a property sent every tick is a pose or a flag.
const MAX_ALWAYS_PROPERTY_BYTES: int = 64
## What a drop and a take move (a hand holds CompanyTuning.HAND_MAX_UNITS).
const UNITS: int = 3
## The host's port of the first measured case; the next ones take the next ports (none of them
## used by another test: the suite runs in parallel).
const PORT: int = 24701
const CONNECT_SECONDS: float = 10.0
## Path caches confirmed and the player's appearance sent before the count starts.
const WARMUP_SECONDS: float = 1.0
const MEASURE_SECONDS: float = 3.0
## Most physics frames the parked fleet takes to rest (its settle_seconds is half a second).
const PARK_FRAMES: int = 300
## A peer id the keepalive's pulse is shown to (_pulse_wakes()): nobody's, the box only counts wakes.
const PULSE_PEER: int = 77

var _failures: int = 0
## The host's tended boxes of the case being measured (_add_trip_bodies()), which publish care_state.
var _tended: Array[DeliveryPackage] = []
var _sync_mtu: int = 1350
var _product: StringName = &""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	_product = _first_product()
	_expect(_product != &"", "There is a product in %s to move" % CompanyAsk.PRODUCTS_DIR)
	var scene_multiplayer := root.multiplayer as SceneMultiplayer
	if scene_multiplayer != null:
		_sync_mtu = scene_multiplayer.max_sync_packet_size
	var full_crew: int = int(root.get_node(^"/root/NetworkManager").get(&"MAX_PLAYERS"))
	_expect(full_crew >= CASES.MEASURED_CREW,
		"NetworkManager.MAX_PLAYERS is read (got %d)" % full_crew)
	var world: Dictionary = await _open_world()
	world.mtu = _sync_mtu
	if not _print_world(world):
		_clean()
		quit(maxi(_failures, 1))
		return
	var crews: Array[int] = [CASES.MEASURED_CREW]
	if full_crew > CASES.MEASURED_CREW:
		crews.append(full_crew)
	var cases: Array[Dictionary] = []
	for kind: String in ["shed", "trip", "far"]:
		for crew: int in crews:
			var layout: Dictionary = CASES.case_layout(kind, crew, CASES.TRIP_RIDERS,
				CASES.SHED_STAYS)
			layout.model = CASES.worst(world, layout)
			_report(world, layout)
			cases.append(layout)
	for kind: String in ["trip", "far"]:
		for crew: int in crews:
			_report_crowded(world, CASES.case_layout(kind, crew, CASES.CROWDED_RIDERS,
				CASES.CROWDED_STAYS))
	for index: int in range(cases.size()):
		var layout: Dictionary = cases[index]
		layout.measured = await _measure_enet(world, layout, PORT + index)
		if not (layout.measured as Dictionary).is_empty():
			_report_measured(layout)
	for layout: Dictionary in cases:
		_check_measured(world, layout)
	_clean()
	if _failures == 0:
		var parts: PackedStringArray = []
		for layout: Dictionary in cases:
			var measured: Dictionary = layout.measured
			parts.append("%s %d: model %.1f, ENet %s%s" % [layout.kind, layout.crew,
				float(layout.model.total) / KB,
				"skipped" if measured.is_empty() else "%.1f" % (float(measured.per_client) / KB),
				"" if layout.held else " (over, not held)"])
		print("PASS: the company mode's bandwidth budgets hold, KB/s a client (%s)"
			% "; ".join(parts))
	quit(_failures)


## The company world as --mode=company opens it, solo (the host): its synchronizers
## (_synchronizers()), its events' sizes (_event_sizes()), its late-join snapshot and a trip's
## pieces (_ride()), then closed again with CompanyState reset. {syncs, events, snapshot_bytes,
## snapshot_raw, ride}.
func _open_world() -> Dictionary:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = SAVE_DIR
	var opened: Array = []
	root.add_child(level)
	# The day opens deferred (CompanyRoot._open_company_day()): its events are caught here.
	level.net.event_applied.connect(func(seq: int, kind: StringName, data: Dictionary) -> void:
		opened.append([seq, kind, data]))
	current_scene = level
	await process_frame
	await _wait_parked(level)
	var found: Dictionary = {
		"syncs": _synchronizers(level),
		"events": _event_sizes(level.net, level.player.global_position, opened),
	}
	var snapshot: Dictionary = CompanyNet.pack_snapshot(level.net.snapshot())
	var compressed: int = 0
	for chunk: PackedByteArray in snapshot.get("chunks", []):
		compressed += chunk.size()
	found.snapshot_bytes = compressed
	found.snapshot_raw = int(snapshot.get("size", 0))
	found.ride = await _ride(level)
	level.queue_free()
	current_scene = null
	await process_frame
	state.call(&"reset")
	return found


## Physics frames until every vehicle of the fleet rests (its NetRestThrottle.is_resting(): parked, it
## sends at its rest interval; D-2002.4, instead of a fixed count of ticks), at most PARK_FRAMES.
func _wait_parked(level: CompanyRoot) -> void:
	var throttles: Array[NetRestThrottle] = []
	if level.fleet != null:
		for van: Node3D in level.fleet.vehicles():
			var throttle := van.get_node_or_null(^"NetRestThrottle") as NetRestThrottle
			if throttle != null:
				throttles.append(throttle)
	var frames: int = 0
	while frames < PARK_FRAMES and throttles.any(func(t: NetRestThrottle) -> bool: return not t.is_resting()):
		await physics_frame
		frames += 1
	_expect(not throttles.is_empty() and throttles.all(func(t: NetRestThrottle) -> bool: return t.is_resting()),
		"The fleet's parked vehicles rest (NetRestThrottle.is_resting()) within %d frames" % PARK_FRAMES)
	_line("parked_rest", "after %d physics frames" % frames)


## Prints what the world gave the model and checks it is all there; false when the cases can't be
## counted (no player, no vehicle).
func _print_world(world: Dictionary) -> bool:
	var syncs: Dictionary = world.syncs
	var events: Dictionary = world.events
	var ride: Dictionary = world.ride
	_line("mtu", str(_sync_mtu))
	_line("player_synchronizers", ", ".join(PackedStringArray(syncs.player_names)))
	_line("shed_synchronizers", ", ".join(PackedStringArray(syncs.shed_names))
		if not syncs.shed_names.is_empty() else "none")
	_line("event_bytes", "%d (%s); largest of any kind %d (%s)" % [
		events.busy_bytes, events.busy_kind, events.largest_bytes, events.largest_kind])
	_line("snapshot_bytes", "%d compressed, %d raw, once per late join" % [
		world.snapshot_bytes, world.snapshot_raw])
	_expect(not syncs.player.is_empty(),
		"The local player's synchronizer is found in the company world")
	_expect(int(events.busy_bytes) > 0,
		"A drop and a take publish real units_moved events (got %d B)" % events.busy_bytes)
	if syncs.player.is_empty() or ride.is_empty():
		return false
	var on_foot: float = CASES.fastest(syncs.player)
	var aboard: float = CASES.fastest(ride.player)
	_line("player_pose_rate", "%.1f/s (every %.4f s; CompanyTuning.SHED_POSE_RATE_HZ %d)" % [
		1.0 / on_foot, on_foot, CompanyTuning.SHED_POSE_RATE_HZ])
	var standing: float = CASES.fastest(ride.standing)
	_line("rider_pose_rate", ("%.1f/s seated (every %.4f s; CompanyTuning.SEATED_POSE_RATE_HZ %d), %.1f/s"
		+ " standing in a bay (player.tscn's own)") % [1.0 / aboard, aboard,
			CompanyTuning.SEATED_POSE_RATE_HZ, 1.0 / standing])
	_line("vehicle_synchronizer", "%s %d B every %.4f s moving (parked: every %.3f s)" % [
		ride.vehicle[2], ride.vehicle[1], ride.vehicle[0], ride.parked_interval])
	_line("box_synchronizer", ("Package/MultiplayerSynchronizer %d B every %.4f s moving, every"
		+ " %.3f s riding still (settles in %.2f s); %d boxes a vehicle (cargo_slots)") % [
			ride.box_entry, ride.box_interval, ride.box_rest, ride.box_settle, ride.cargo])
	_line("trip_event_bytes", "%d, the larger of %s (%d orders and boxes)" % [
		ride.trip_bytes, ", ".join(PackedStringArray(ride.trip_kinds)), ride.cargo])
	_line("keepalive", ("a hidden body every %.0f s for %.2f s or two of its intervals"
		+ " (CompanyInterest); a pulse wakes a box riding still %d times (on: %s)")
		% [ride.keepalive, ride.pulse, ride.pulse_wakes, ride.pulse_wake_on])
	_line("care_state", ("%d B a tended box (%s), %.0f deltas/s each (ON_CHANGE, reliable; %.0f/s in a"
		+ " delivery)") % [ride.care_bytes, ride.care_kind, ride.care_hz, CASES.CARE_PUBLISH_HZ])
	_expect(int(ride.care_bytes) > 0, "A tended box publishes a care_state (got %d B)" % ride.care_bytes)
	_expect(standing < on_foot, "Standing in a vehicle's bay, a player sends its pose more often than on"
		+ " foot (%.4f < %.4f s)" % [standing, on_foot])
	_expect(is_equal_approx(aboard, RIDE.pose_interval(CompanyTuning.SEATED_POSE_RATE_HZ)),
		"Seated, a player sends at CompanyTuning.SEATED_POSE_RATE_HZ (every %.4f s)" % aboard)
	var delivery_van: Node = (load(String(ride.scene)) as PackedScene).instantiate()
	var own: float = (delivery_van.get_node(CompanyFleet.SYNC_PATH) as MultiplayerSynchronizer).replication_interval
	delivery_van.free()
	var driven: float = ride.vehicle[0]
	_expect(is_equal_approx(driven, CompanyTuning.FLEET_POSE_INTERVAL_SEC) and own < driven,
		("Driven, the fleet's vehicle sends every CompanyTuning.FLEET_POSE_INTERVAL_SEC (%.4f s); its scene"
		+ " keeps its own for a delivery (%.4f s)") % [ride.vehicle[0], own])
	_expect(float(ride.vehicle[0]) < float(ride.parked_interval),
		"Driven, the fleet's vehicle sends at its full rate, not its rest's (%.4f < %.3f s)"
		% [ride.vehicle[0], ride.parked_interval])
	_expect(int(ride.vehicle[1]) > 0 and int(ride.box_entry) > 0,
		"The vehicle and a box send a pose every tick (%d B, %d B)"
		% [ride.vehicle[1], ride.box_entry])
	var kinds: Array = [CompanyTripsView.STARTED, CompanyTripsView.CLOSED]
	_expect(int(ride.trip_bytes) > 0 and ride.trip_kinds == kinds,
		"Out and back through the gate, the trip starts and closes (%s)" % str(ride.trip_kinds))
	return true


# --- The world's pieces ----------------------------------------------------------


## Every MultiplayerSynchronizer in the company world: the local player's (one per crew member), the
## fleet's vehicles' (parked) and the rest (the shed's, the host's). {player, vehicles, shed:
## [[interval, entry bytes, name]], player_names, shed_names (the vehicles' too)}. A synchronizer
## with nothing sent every tick only sends ON_CHANGE deltas: listed, not counted.
func _synchronizers(level: CompanyRoot) -> Dictionary:
	var found: Dictionary = {
		"player": [], "vehicles": [], "shed": [], "player_names": [], "shed_names": [],
	}
	for node: Node in level.find_children("*", "MultiplayerSynchronizer", true, false):
		var sync := node as MultiplayerSynchronizer
		var on_player: bool = level.player != null and level.player.is_ancestor_of(sync)
		var on_vehicle: bool = level.fleet != null and level.fleet.is_ancestor_of(sync)
		var entry: Array = _sync_entry(sync, ("Player/%s" % level.player.get_path_to(sync)
			if on_player else str(level.get_path_to(sync))))
		found["player_names" if on_player else "shed_names"].append("%s %s" % [entry[2], (
			"%d B every %.3f s" % [entry[1], entry[0]] if int(entry[1]) > 0 else "ON_CHANGE only")])
		if int(entry[1]) > 0:
			found["player" if on_player else ("vehicles" if on_vehicle else "shed")].append(entry)
	return found


## [interval, entry bytes, `sync_name`] of what `sync` sends every tick, each always-sent property
## checked against MAX_ALWAYS_PROPERTY_BYTES; 0 bytes when it sends only ON_CHANGE deltas.
func _sync_entry(sync: MultiplayerSynchronizer, sync_name: String) -> Array:
	var sizes: Dictionary = MODEL.always_properties(sync, true)
	var bytes: int = 0
	for path: NodePath in sizes:
		_expect(int(sizes[path]) <= MAX_ALWAYS_PROPERTY_BYTES,
			"%s %s is sent every tick at %d bytes: make it ON_CHANGE"
			% [sync_name, path, sizes[path]])
		bytes += int(sizes[path])
	return [MODEL.interval(sync), MODEL.SYNC_ENTRY_HEADER + bytes if bytes > 0 else 0, sync_name]


## A trip's pieces, from the real world: the player's synchronizers aboard (Player.net_in_vehicle,
## as _synchronizers() lists them), the fleet's first vehicle driven out with a full load
## (_drive_out()), a box's synchronizer (_box()) and CompanyInterest's keepalive. {player, vehicle,
## parked_interval, trip_bytes, trip_kinds, box_entry, box_interval, box_rest, box_settle, scene,
## cargo, keepalive, pulse}; {} when the world has no vehicle.
func _ride(level: CompanyRoot) -> Dictionary:
	var player := level.player as Player
	player.net_in_vehicle = true
	RIDE.apply_pose_rate(player)
	var standing: Array = _synchronizers(level).player
	# The riders of the cases sit (a driver, a passenger with the box on the lap): D-2002.4's rate.
	player.seat_node_path = SEAT_PATH
	RIDE.apply_pose_rate(player)
	var aboard: Array = _synchronizers(level).player
	player.seat_node_path = NodePath()
	player.net_in_vehicle = false
	RIDE.apply_pose_rate(player)
	var vans: Array[Node3D] = []
	if level.fleet != null:
		vans = level.fleet.vehicles()
	_expect(not vans.is_empty() and level.trips != null and level.interest != null,
		"The company world has its fleet's vehicle (World/Vehicles), its trips and its interest")
	if vans.is_empty() or level.trips == null or level.interest == null:
		return {}
	var van: Node3D = vans[0]
	var definition: VehicleDefinition = level.fleet.catalog.vehicle(StringName(van.name))
	_expect(definition != null and definition.cargo_slots > 0,
		"%s is a vehicle with a load" % van.name)
	if definition == null:
		return {}
	var ride: Dictionary = await _drive_out(level, van, definition.cargo_slots)
	ride.merge(_box())
	ride.merge(await _care_and_pulse())
	ride.player = aboard
	ride.standing = standing
	ride.scene = van.scene_file_path
	ride.cargo = definition.cargo_slots
	ride.keepalive = level.interest.keepalive_sec
	ride.pulse = level.interest.keepalive_pulse_sec
	return ride


## `van` with a full load staged (`cargo` orders of LATE_DAY, each in its box) driven across the
## shed's gate and back by code, as test_company_fleet does (frozen, moved: CompanyTrips watches
## where it is), then parked again. {vehicle: its synchronizer while it moved ([interval, entry,
## name]), parked_interval: before, trip_bytes: the larger trip event as _apply_event carries it,
## trip_kinds: the kinds published}.
func _drive_out(level: CompanyRoot, van: Node3D, cargo: int) -> Dictionary:
	var trips: CompanyTrips = level.trips
	var products: Dictionary = {
		_product: load(CompanyAsk.PRODUCTS_DIR.path_join("%s.tres" % _product)),
	}
	var orders: Array[StringName] = []
	var boxes: Array[StringName] = []
	for index: int in range(cargo):
		orders.append(StringName("%so%02d" % [OrderGenerator.id_prefix(LATE_DAY), index + 1]))
		boxes.append(StringName(CompanyTableNet.BOX_ID_PREFIX + str(LATE_BOX + index)))
		trips.book.add(Order.make(orders[index], "Ana", &"centro", &"centro_house_1",
			[{"product": _product, "qty": 1}], 0, products))
		trips.book.mark_packed(orders[index], boxes[index])
	trips.stage_cargo(StringName(van.name), orders, boxes)
	var sync := van.get_node(CompanyFleet.SYNC_PATH) as MultiplayerSynchronizer
	var found: Dictionary = {
		"parked_interval": MODEL.interval(sync), "trip_bytes": 0, "trip_kinds": [],
	}
	var listen: Callable = func(seq: int, kind: StringName, data: Dictionary) -> void:
		if CompanyTripsView.EVENT_KINDS.has(kind):
			found.trip_kinds.append(kind)
			found.trip_bytes = maxi(int(found.trip_bytes), MODEL.rpc_size([seq, kind, data], true))
	level.net.event_applied.connect(listen)
	var parked: Transform3D = van.global_transform
	var exit: Vector3 = CompanyFleet.exit_of(level.shed, level.net.company)
	var outward: Vector3 = -level.shed.global_basis.z
	await _put(van, exit - outward)
	await _put(van, CompanyFleet.gate_of(level.shed, level.net.company) + outward * 3.0)
	await _wait_kind(found.trip_kinds, CompanyTripsView.STARTED)
	found.vehicle = _sync_entry(sync, "World/Vehicles/%s/%s" % [van.name, CompanyFleet.SYNC_PATH])
	await _put(van, exit - outward)
	await _wait_kind(found.trip_kinds, CompanyTripsView.CLOSED)
	van.global_transform = parked
	await physics_frame
	await physics_frame
	level.net.event_applied.disconnect(listen)
	return found


## Physics frames until `kind` is in `kinds` (at most 300: a slow runner needs more than the two
## frames _put() gives the gate; the caller's check then reports what is missing).
func _wait_kind(kinds: Array, kind: StringName) -> void:
	for _frame: int in range(300):
		if kinds.has(kind):
			return
		await physics_frame


## Moves the (frozen) van and lets the gate look at it.
func _put(van: Node3D, at: Vector3) -> void:
	van.global_position = Vector3(at.x, van.global_position.y, at.z)
	await physics_frame
	await physics_frame


## A box's synchronizer, as the company's sealed boxes have it (BoxToPackage.PACKAGE_SCENE):
## {box_entry, box_interval (moving), box_rest and box_settle (its NetRestThrottle's)}.
func _box() -> Dictionary:
	var box: Node = BoxToPackage.PACKAGE_SCENE.instantiate()
	var sync := box.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var entry: Array = _sync_entry(sync, "Package/MultiplayerSynchronizer")
	var throttle: Node = box.get_node(^"NetRestThrottle")
	var found: Dictionary = {
		"box_entry": int(entry[1]), "box_interval": float(entry[0]),
		"box_rest": float(throttle.get(&"rest_interval")),
		"box_settle": float(throttle.get(&"settle_seconds")),
	}
	box.free()
	return found


## A tended box's care_state and what a keepalive pulse does to a box riding still, from real boxes
## (package.tscn in the tree, each trap of TRAPS_DIR): {care_bytes: the largest state
## PackageRescue.publish_care() leaves as a tended box has it (a crisis prompt, a tool at work),
## floats as 64-bit; care_kind: its trap; care_sample: that state; care_hz: how often a company box
## publishes it (BoxToPackage.tune()); pulse_wakes: how many times a pulse to one peer, on and off,
## wakes its resting NetRestThrottle; pulse_wake_on: whether showing it does}.
func _care_and_pulse() -> Dictionary:
	var found: Dictionary = {"care_bytes": 0, "care_kind": "", "care_sample": {}, "care_hz": 0.0,
		"pulse_wakes": 0, "pulse_wake_on": false}
	var files: PackedStringArray = DirAccess.get_files_at(TRAPS_DIR)
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var box := BoxToPackage.PACKAGE_SCENE.instantiate() as DeliveryPackage
		box.trap_definition = load(TRAPS_DIR.path_join(file)) as TrapDefinition
		box.freeze = true
		root.add_child(box)
		var kind: StringName = box.trap_definition.id
		box.care.message = box.care.crisis_prompt(kind)
		box.care.work_tool = &"tape"
		box.care.work = 0.37
		PackageRescue.publish_care(box)
		var state: Variant = _worst_floats(box.care_state)
		var bytes: int = MODEL.encoded_size(state)
		if bytes > int(found.care_bytes):
			found.care_bytes = bytes
			found.care_kind = String(kind)
			found.care_sample = state
		# A company box publishes it as BoxToPackage builds it.
		BoxToPackage.tune(box)
		found.care_hz = 1.0 / PackageRescue.care_publish_interval(box)
		box.free()
	var still := BoxToPackage.PACKAGE_SCENE.instantiate() as RigidBody3D
	still.freeze = true
	root.add_child(still)
	var throttle := still.get_node(^"NetRestThrottle") as NetRestThrottle
	var sync := still.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	for show: bool in [true, false]:
		while not throttle.is_resting():
			await physics_frame
		_pulse(sync, show)
		if not throttle.is_resting():
			found.pulse_wakes = int(found.pulse_wakes) + 1
			found.pulse_wake_on = bool(found.pulse_wake_on) or show
	still.free()
	return found


## What WorldCellInterest (CompanyInterest) does to `sync` for a keepalive pulse to PULSE_PEER, on or off.
func _pulse(sync: MultiplayerSynchronizer, show: bool) -> void:
	# Solo, SceneMultiplayer has no such peer to update and says so: only the throttle's answer counts here.
	Engine.print_error_messages = false
	WorldCellInterest.pulse_visibility(sync, PULSE_PEER, show)
	Engine.print_error_messages = true


## `value` with every float as one that needs 64 bits (MODEL.encoded_size()'s worst case), nested.
static func _worst_floats(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return 0.1
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in value:
				out[key] = _worst_floats(value[key])
			return out
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(_worst_floats(item))
			return items
	return value


# --- Reports ------------------------------------------------------------------


## `layout`'s model: its worst client against the budget (a failure where held, else over_budget
## printed), its culprits, and what each kind of client of that arrangement gets (in the shed,
## aboard each vehicle; far, the shed's keepalive pulses: the cost decisiones/2026-10-21 asks for).
func _report(world: Dictionary, layout: Dictionary) -> void:
	var case: Dictionary = layout.model
	var key: String = CASES.key(layout)
	var over: bool = float(case.total) > float(layout.budget)
	_line(key, ("per_client_kbps=%.1f of %.0f host_upload_kbps=%.1f framing_kbps=%.1f"
		+ " datagrams_s=%.0f keepalive_kbps=%.2f worst=%s%s") % [float(case.total) / KB,
		float(layout.budget) / KB, float(case.upload) / KB, float(case.framing) / KB,
		float(case.datagrams), float(case.keepalive) / KB, CASES.who(layout, case),
		" over_budget" if over else ""])
	_line(key + "_culprits", CASES.culprit_text(case.culprits, case.culprits.size()))
	var places: Array = case.places
	var seen: Dictionary = {}
	for client: int in range(1, places.size()):
		var where: String = CASES.place_name(int(places[client]))
		if not seen.has(where):
			var other: Dictionary = CASES.client_case(world, layout, places, client)
			seen[where] = "%s %.1f (keepalive %.2f)" % [where, float(other.total) / KB,
				float(other.keepalive) / KB]
	_line(key + "_clients", ", ".join(PackedStringArray(seen.values())))
	var title: String = CASES.title(layout)
	if over:
		_line("over_budget", "%s: %.1f KB/s of %.0f%s; first culprit %s" % [title,
			float(case.total) / KB, float(layout.budget) / KB,
			"" if layout.held else " (printed, not held: FULL_CREW_FITS)", case.culprits[0][0]])
	elif not layout.held:
		_line("note", "%s fits now: set FULL_CREW_FITS[\"%s\"] so the test holds it"
			% [title, layout.kind])
	if layout.held:
		_expect(not over, "With %s the host sends each client at most %.0f KB/s (model %.1f KB/s)"
			% [title, float(layout.budget) / KB, float(case.total) / KB])


## A crowded case (CROWDED_RIDERS aboard), printed only: the design allows it, the budgets are set
## for TRIP_RIDERS.
func _report_crowded(world: Dictionary, layout: Dictionary) -> void:
	var case: Dictionary = CASES.worst(world, layout)
	var over: bool = float(case.total) > float(layout.budget)
	_line("crowded_%s" % CASES.key(layout), "per_client_kbps=%.1f of %.0f%s worst=%s; first culprits"
		% [float(case.total) / KB, float(layout.budget) / KB, " (over)" if over else "",
			CASES.who(layout, case)] + " " + CASES.culprit_text(case.culprits, 3))


# --- Real events ----------------------------------------------------------------


## The events of a busy shed, from what the root really publishes: the day's opening (`opened`, its
## day_phase and clock_anchor) and a drop and a take of UNITS through CompanyNet (_drop_and_take()).
## Each sized as _apply_event carries it. {busy_bytes, busy_kind: the largest units_moved,
## largest_bytes, largest_kind: of any kind (the day's phases are rare)}.
func _event_sizes(net: CompanyNet, feet: Vector3, opened: Array) -> Dictionary:
	var seen: Array = opened.duplicate()
	seen.append_array(_drop_and_take(net, feet))
	var sizes: Dictionary = {"busy_bytes": 0, "busy_kind": "", "largest_bytes": 0, "largest_kind": ""}
	for event: Array in seen:
		var bytes: int = MODEL.rpc_size(event, true)
		if bytes > int(sizes.largest_bytes):
			sizes.largest_bytes = bytes
			sizes.largest_kind = String(event[1])
		if event[1] == &"units_moved" and bytes > int(sizes.busy_bytes):
			sizes.busy_bytes = bytes
			sizes.busy_kind = "units_moved%s" % (" with pos" if (event[2] as Dictionary).has("pos") else "")
	return sizes


## The host drops UNITS of _product at `feet` and takes them back, through CompanyNet's own checks
## and _publish (the hands are filled first, as a take from a shelf would). [seq, kind, data] of
## each event, as event_applied gave it.
func _drop_and_take(net: CompanyNet, feet: Vector3) -> Array:
	var seen: Array = []
	var listen: Callable = func(seq: int, kind: StringName, data: Dictionary) -> void:
		seen.append([seq, kind, data])
	net.event_applied.connect(listen)
	var hands: StringName = CompanyNet.hands_location(net.multiplayer.get_unique_id())
	_busy_step(net, hands, feet, true)
	_busy_step(net, hands, feet, false)
	net.event_applied.disconnect(listen)
	_expect(seen.size() == 2, "A drop and a take each publish one units_moved (got %d)" % seen.size())
	return seen


## One busy event on the host: UNITS from its hands onto the floor at `feet` (`drop`), or back from
## that bundle (CompanyNet takes a floor bundle as its own station).
func _busy_step(net: CompanyNet, hands: StringName, feet: Vector3, drop: bool) -> void:
	if drop:
		var held: int = net.inventory.count(_product, hands)
		if held < UNITS:
			net.inventory.receive(_product, UNITS - held, hands)
		net.drop(_product, UNITS, feet)
		return
	for bundle: Variant in net.floor_bundles.to_dict():
		net.request(&"units_take", {"station": StringName(bundle), "product": _product, "qty": UNITS})
		return


# --- Measured on ENet ------------------------------------------------------------


## `layout`'s crew as ENet peers on localhost, one SceneMultiplayer each under its own side node,
## the host on `port`, arranged as the model's worst (_count_traffic()). {} when the session didn't
## come up: a failure with MEASURED_CREW, only printed as skipped with the full crew.
func _measure_enet(world: Dictionary, layout: Dictionary, port: int) -> Dictionary:
	var crew: int = layout.crew
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	var sides: Array[Node] = []
	var peers: Array[ENetMultiplayerPeer] = []
	var problem: String = ""
	for index: int in range(crew):
		var side := Node.new()
		side.name = "Peer%d" % index
		root.add_child(side)
		set_multiplayer(SceneMultiplayer.new(), side.get_path())
		sides.append(side)
		var peer := ENetMultiplayerPeer.new()
		peers.append(peer)
		var made: Error = (
			peer.create_server(port, crew) if index == 0 else peer.create_client("127.0.0.1", port))
		if made != OK:
			problem = "ENet peer %d doesn't start on localhost:%d (error %d)" % [index, port, made]
			break
		side.multiplayer.multiplayer_peer = peer
		var net := CompanyNet.new()
		net.name = "CompanyNet"
		side.add_child(net)
	var up: bool = false
	if problem.is_empty():
		up = await _wait_for(func() -> bool:
			if sides[0].multiplayer.get_peers().size() != crew - 1:
				return false
			for index: int in range(1, crew):
				if peers[index].get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
					return false
			return true, CONNECT_SECONDS)
	if problem.is_empty() and not up:
		problem = "%d ENet peers don't connect on localhost in %.0f s" % [crew, CONNECT_SECONDS]
	# The full crew's session is many peers in one process: on a busy runner it may not come up in
	# time. Then it's only printed (the model above still counts it).
	if crew > CASES.MEASURED_CREW and not problem.is_empty():
		_line("enet_%s" % CASES.key(layout), "skipped (%s)" % problem)
	else:
		_expect(problem.is_empty(), problem)
	var result: Dictionary = {}
	if up:
		result = await _count_traffic(world, layout, sides, peers)
	# The players go while their sessions are still up (they ask for their peer's id every frame),
	# once nothing is sent any more and what was on its way has landed.
	for side: Node in sides:
		for node: Node in side.find_children("*", "MultiplayerSynchronizer", true, false):
			(node as MultiplayerSynchronizer).public_visibility = false
	await _wait_seconds(0.3)
	for side: Node in sides:
		var world_node: Node = side.get_node_or_null(^"World")
		if world_node != null:
			world_node.free()
	await process_frame
	for index: int in range(peers.size() - 1, -1, -1):
		if peers[index].get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			peers[index].close()
	await process_frame
	for side: Node in sides:
		set_multiplayer(null, side.get_path())
		side.free()
	floor_body.free()
	return result


## Players on every side (its owner's authority, standing on one floor: players don't collide with
## each other), the vehicles out and their loads (_add_trip_bodies()), a warm-up, then the riders'
## owners send as riders (net_in_vehicle) and MEASURE_SECONDS of the busy rate of events. {clients:
## [{index, total (B/s, IP and UDP included), enet (what the overlay shows: ENet's count), datagrams
## (a second)}], worst: the index of the client that got the most, per_client, per_client_enet and
## datagrams: its, host_sent (B/s, the overlay's out on the host), events (sent), events_seen
## (applied, all clients), seconds, fps}.
func _count_traffic(
	world: Dictionary, layout: Dictionary, sides: Array[Node], peers: Array[ENetMultiplayerPeer]
) -> Dictionary:
	var crew: int = sides.size()
	var places: Array = layout.model.places
	var ids: Array[int] = []
	for side: Node in sides:
		ids.append(side.multiplayer.get_unique_id())
	var player_scene := load(CompanyRoot.PLAYER_SCENE) as PackedScene
	for side: Node in sides:
		var world_node := Node3D.new()
		world_node.name = "World"
		side.add_child(world_node)
		for index: int in range(crew):
			var player := player_scene.instantiate() as Player
			player.name = "Player_%d" % ids[index]
			player.position = Vector3(2.0 * index - crew, 0.1, 0.0)
			player.rotation.y = 0.37 + index
			player.set_multiplayer_authority(ids[index])
			# As the company world takes every player in: the shed's pose rate (D-2002.3).
			CompanyRoot.join_crew(player)
			world_node.add_child(player)
	_tended.clear()
	var gated: Array[MultiplayerSynchronizer] = _add_trip_bodies(world, layout, sides, ids)
	var host_net := sides[0].get_node(^"CompanyNet") as CompanyNet
	var hands: StringName = CompanyNet.hands_location(CompanyNet.HOST_ID)
	var applied: Array[int] = [0]
	for index: int in range(1, crew):
		var net := sides[index].get_node(^"CompanyNet") as CompanyNet
		# Every client holds what the host's hands will hold, as a snapshot would have said.
		net.inventory.receive(_product, UNITS, hands)
		net.event_applied.connect(func(_seq: int, _kind: StringName, _data: Dictionary) -> void:
			applied[0] += 1)
	await _wait_seconds(WARMUP_SECONDS)
	# Nothing moves from here on: what the players send doesn't depend on their processing (the
	# same bytes with 4 players either way), and crew * crew full players in one process would hold
	# the frame rate under their sync rate (8: 61 fps, a send every other frame at best). A rider's
	# owner sends at the rate the world gives a rider.
	for side: Node in sides:
		for child: Node in side.get_node(^"World").get_children():
			child.process_mode = Node.PROCESS_MODE_DISABLED
	for index: int in range(crew):
		if int(places[index]) >= 0:
			var rider := sides[index].get_node(NodePath("World/Player_%d" % ids[index])) as Player
			rider.net_in_vehicle = true
			rider.seat_node_path = SEAT_PATH
			RIDE.apply_pose_rate(rider)
	var feet: Vector3 = (sides[0].get_node(NodePath("World/Player_%d" % ids[0])) as Node3D).global_position
	var rate: float = crew * CASES.ACTIONS_PER_PLAYER_PER_SECOND + CASES.HOST_EVENTS_PER_SECOND
	# KB/s as the network overlay reads them on LAN (N-216: NetStats, ENet's host counters), a
	# NetStats per peer; the datagrams from the same counters, for IP and UDP.
	var stats: Array[NetStats] = []
	for peer: ENetMultiplayerPeer in peers:
		stats.append(NetStats.new())
		stats.back().sample(peer, ids, Time.get_ticks_usec())
		peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	var start: int = Time.get_ticks_usec()
	var sent: int = 0
	var frames: int = 0
	while Time.get_ticks_usec() - start < int(MEASURE_SECONDS * 1e6):
		frames += 1
		var due: int = floori((Time.get_ticks_usec() - start) / 1e6 * rate)
		while sent < due:
			# A drop, then the take back: both units_moved, as _event_sizes() sized them.
			_busy_step(host_net, hands, feet, sent % 2 == 0)
			sent += 1
		_publish_care(world, Time.get_ticks_usec() - start)
		await process_frame
	var now: int = Time.get_ticks_usec()
	var seconds: float = (now - start) / 1e6
	var host_sent: float = float(stats[0].sample(peers[0], ids, now).out_kbps) * KB
	var clients: Array = []
	var worst: Dictionary = {}
	for index: int in range(1, crew):
		var enet: float = float(stats[index].sample(peers[index], ids, now).in_kbps) * KB
		var datagrams: float = (
			peers[index].host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS) / seconds)
		clients.append({"index": index, "enet": enet, "datagrams": datagrams,
			"total": enet + datagrams * MODEL.IP_UDP_HEADER})
		if worst.is_empty() or float(clients.back().total) > float(worst.total):
			worst = clients.back()
	await _wait_for(func() -> bool: return applied[0] >= sent * (crew - 1), CONNECT_SECONDS)
	for sync: MultiplayerSynchronizer in gated:
		for id: int in ids:
			sync.set_visibility_for(id, false)
	return {
		"clients": clients, "worst": worst.index, "per_client": worst.total,
		"per_client_enet": worst.enet, "datagrams": worst.datagrams, "host_sent": host_sent,
		"events": sent, "events_seen": applied[0], "seconds": seconds, "fps": frames / seconds,
	}


## The vehicles out of `layout` and their loads on every side, the same names everywhere (the host's
## the authority): the vehicle's definition scene and package.tscn, frozen, with no NetRestThrottle
## (a vehicle out moves; a tended box moves, the rest of the load rides at its rest interval). On
## the host each one's synchronizer reaches only the clients that see it as CompanyInterest decides:
## its riders (every vehicle: they ride near each other) and, near, the shed's. Returns the host's
## synchronizers it gated.
func _add_trip_bodies(
	world: Dictionary, layout: Dictionary, sides: Array[Node], ids: Array[int]
) -> Array[MultiplayerSynchronizer]:
	var ride: Dictionary = world.ride
	var riders: Array = layout.riders
	var places: Array = layout.model.places
	var gated: Array[MultiplayerSynchronizer] = []
	if riders.is_empty():
		return gated
	var van_scene := load(String(ride.scene)) as PackedScene
	for side_index: int in range(sides.size()):
		var world_node: Node = sides[side_index].get_node(^"World")
		for vehicle: int in range(riders.size()):
			var bodies: Array[Node3D] = []
			var van := van_scene.instantiate() as Node3D
			van.name = "Vehicle_%d" % vehicle
			van.position = Vector3(10.0 * vehicle, 0.7, 12.0)
			if van is RigidBody3D:
				(van as RigidBody3D).freeze = true
			# As CompanyFleet._make() sets it (the scene's own is a delivery truck's).
			(van.get_node(CompanyFleet.SYNC_PATH) as MultiplayerSynchronizer).replication_interval = float(
				ride.vehicle[0])
			bodies.append(van)
			var tended: int = CASES.cargo(ride, riders.slice(vehicle, vehicle + 1), 1).x
			for slot: int in range(int(ride.cargo)):
				var box := BoxToPackage.PACKAGE_SCENE.instantiate() as RigidBody3D
				box.name = "Package_%d_%d" % [vehicle, slot]
				box.freeze = true
				box.position = Vector3(10.0 * vehicle + slot, 0.4, 17.0)
				box.get_node(^"NetRestThrottle").free()
				var box_sync := box.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
				box_sync.replication_interval = (
					float(ride.box_interval) if slot < tended else float(ride.box_rest))
				bodies.append(box)
			for body: Node3D in bodies:
				world_node.add_child(body)
				if side_index > 0:
					continue
				var slot_index: int = bodies.find(body)
				if slot_index >= 1 and slot_index <= tended:
					_tended.append(body as DeliveryPackage)
				var sync := body.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
				sync.public_visibility = false
				for client: int in range(1, sides.size()):
					var sees: bool = int(places[client]) >= 0 or bool(layout.near)
					sync.set_visibility_for(ids[client], sees)
				gated.append(sync)
		# A box in the hands of each player in the shed, loading (CASES.loading()), moving.
		for index: int in range(CASES.loading(layout, places)):
			var carried := BoxToPackage.PACKAGE_SCENE.instantiate() as RigidBody3D
			carried.name = "Loading_%d" % index
			carried.freeze = true
			carried.position = Vector3(index - 4.0, 0.4, -6.0)
			carried.get_node(^"NetRestThrottle").free()
			var carried_sync := carried.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
			carried_sync.replication_interval = float(ride.box_interval)
			world_node.add_child(carried)
			if side_index > 0:
				continue
			carried_sync.public_visibility = false
			for client: int in range(1, sides.size()):
				carried_sync.set_visibility_for(ids[client], int(places[client]) < 0 or bool(layout.near))
			gated.append(carried_sync)
	return gated


## The host's tended boxes publish the measured care_state (world.ride.care_sample, something in it
## changed) at world.ride.care_hz each, each on its own phase, `elapsed` µs into the count.
func _publish_care(world: Dictionary, elapsed: int) -> void:
	var every: float = 1.0 / maxf(float(world.ride.care_hz), 0.001)
	for index: int in range(_tended.size()):
		var box: DeliveryPackage = _tended[index]
		var due: int = floori((elapsed / 1e6 + index * every / maxf(_tended.size(), 1.0)) / every)
		if int(box.get_meta(&"care_published", -1)) != due:
			box.set_meta(&"care_published", due)
			var state: Dictionary = (world.ride.care_sample as Dictionary).duplicate(true)
			state["work"] = 0.1 + due * 1e-3
			box.care_state = state


func _report_measured(layout: Dictionary) -> void:
	var measured: Dictionary = layout.measured
	var places: Array = layout.model.places
	var over: bool = float(measured.per_client) > float(layout.budget)
	var ranges: Dictionary = {}
	for client: Dictionary in measured.clients:
		var where: String = CASES.place_name(int(places[int(client.index)]))
		var seen: Vector2 = ranges.get(where, Vector2(INF, 0.0))
		var total: float = client.total
		ranges[where] = Vector2(minf(seen.x, total), maxf(seen.y, total))
	var each: PackedStringArray = []
	for where: String in ranges:
		each.append("%s %.1f-%.1f" % [where, ranges[where].x / KB, ranges[where].y / KB])
	_line("enet_%s" % CASES.key(layout), ("per_client_kbps=%.1f (ENet %.1f + IP/UDP %.1f; a client"
		+ " %s) clients_kbps=%s datagrams_s=%.0f host_upload_kbps=%.1f events=%d seconds=%.2f"
		+ " fps=%.0f%s") % [float(measured.per_client) / KB, float(measured.per_client_enet) / KB,
			(float(measured.per_client) - float(measured.per_client_enet)) / KB,
			CASES.place_name(int(places[int(measured.worst)])), ", ".join(each),
			float(measured.datagrams), float(measured.host_sent) / KB, measured.events,
			measured.seconds, float(measured.fps), " over_budget" if over else ""])


## `layout`'s measurement against its budget (where held) and, client by client, against the model's
## ceiling for that client (CASES.client_case(); what the model counts on top, trip events and
## keepalive, isn't sent here). The check that the streams flowed needs two frames of the fastest
## pose: slower, the frame rate holds the sync rate down and it is only printed as skipped.
func _check_measured(world: Dictionary, layout: Dictionary) -> void:
	var measured: Dictionary = layout.measured
	var title: String = CASES.title(layout)
	if int(layout.crew) == CASES.MEASURED_CREW:
		_expect(not measured.is_empty(), "%s are measured on ENet" % title)
	if measured.is_empty():
		return
	var places: Array = layout.model.places
	if layout.held:
		_expect(float(measured.per_client) <= float(layout.budget),
			"Measured on ENet, %s: each client gets at most %.0f KB/s (got %.1f)"
			% [title, float(layout.budget) / KB, float(measured.per_client) / KB])
	for client: Dictionary in measured.clients:
		var ceiling: Dictionary = CASES.client_case(world, layout, places, int(client.index))
		_expect(float(client.total) <= float(ceiling.total),
			"%s: client %d (%s) stays under the model's ceiling (%.1f <= %.1f KB/s)" % [title,
				client.index, CASES.place_name(int(places[int(client.index)])),
				float(client.total) / KB, float(ceiling.total) / KB])
	var worst: Dictionary = CASES.client_case(world, layout, places, int(measured.worst))
	var model_data: float = float(worst.host) + float(worst.relayed) + float(worst.events_data)
	var fastest: float = CASES.fastest(world.syncs.player)
	if not (layout.riders as Array).is_empty():
		fastest = minf(fastest, CASES.fastest(world.ride.player))
	if float(measured.fps) < 2.0 / fastest:
		_line("enet_%s_flow_check" % CASES.key(layout),
			"skipped (%.0f fps, under %.0f: fewer sends than the game's)"
			% [float(measured.fps), 2.0 / fastest])
	else:
		_expect(float(measured.per_client_enet) >= 0.5 * model_data,
			"%s: the streams flowed, ENet counted over half the model's data (%.1f of %.1f KB/s)"
			% [title, float(measured.per_client_enet) / KB, model_data / KB])
	var events: int = measured.events
	var crew: int = layout.crew
	_expect(events > 0 and int(measured.events_seen) == events * (crew - 1),
		"%s: every client applied the host's %d events (applied %d of %d)"
		% [title, events, measured.events_seen, events * (crew - 1)])


# --- Helpers --------------------------------------------------------------------


func _first_product() -> StringName:
	var files: PackedStringArray = DirAccess.get_files_at(CompanyAsk.PRODUCTS_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres"):
			return StringName(file.get_basename())
	return &""


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _wait_seconds(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _line(key: String, value: String) -> void:
	print("%s %s=%s" % [PREFIX, key, value])


func _clean() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
