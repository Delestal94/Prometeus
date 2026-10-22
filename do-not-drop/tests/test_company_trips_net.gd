extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_trips_net.gd
##
## The company vehicles out of the shed on every peer (expansion D-0302.2.a,
## scripts/gameplay/districts/company_trips_view.gd; contract
## docs/expansion-distritos/diseno/red-autoridad.md, row 19): the host's CompanyTrips decides, its
## CompanyTripsView publishes each fact through CompanyNet (trip_started, trip_refused,
## trip_closed) and every peer's view applies it with the same code.
## - Solo (an offline CompanyNet is the host): a trip that starts is one trip_started event and the
##   host's own view shows the vehicle out with its trip, orders, boxes and minute, the same count
##   as CompanyTrips; `changed` fires once per event, after it is applied. Coming back is one
##   trip_closed with the failed order, and the view's trip_closed signal carries it.
## - Malformed data (missing or extra keys, an empty or non-id order, a bad minute, a vehicle
##   already out or not out, a trip id that isn't the vehicle's) is refused by apply_trip() and by
##   the snapshot part, and changes nothing; a client can't publish a trip event.
## - Two ENet peers in one process, then a third that joins late (each with its CompanyNet and
##   CompanyTripsView on its own SceneMultiplayer; only the host has a CompanyTrips): a trip the
##   host starts reaches the client's view with its orders; its close empties the client's view
##   and the failed list arrives (the view's trip_closed); with VEHICLES_FAR_MAX (2) out, a third
##   vehicle that crosses is refused and counts as out on the client (trips_out() 3, trip ""),
##   until it is back (one trip_closed with trip "", no trip_closed signal); a peer that joins with
##   vehicles out gets them from the snapshot, with `changed` once and no trip_closed; a
##   trip_started published while it still waits for that snapshot is held and dropped (the snapshot
##   has it) and one published right after the snapshot is applied once after it: no vehicle twice.
## - The host never sends what its own view would refuse (auditor-red on D-0302.2.a): DispatchZone
##   hands a vehicle at most CompanyTrips.MAX_CARGO boxes (the rest keep waiting); stage_cargo()
##   with 65 orders and boxes keeps 64 (one warning) and that vehicle is out on the host's view as
##   on CompanyTrips; a vehicle id too long stages nothing. The view, handed a trip with ids that
##   don't fit, sends the ones that do (one warning); with MAX_OUT vehicles out, or for the close of
##   a trip never sent, it sends nothing (a warning each). No error is logged anywhere in the test.
## - A view that leaves the tree unhooks itself and its snapshot part.
## Expected in the log: the six warnings above (cargo cut, id too long, ids left out, the close never
## sent, over MAX_OUT and its return), and the engine's leak notes at exit, as in test_company_trips.

const PORT: int = 24673
const MINUTE: int = 600
## Where the test's gate lies and the two sides of it (out is -Z).
const GATE_ORIGIN: Vector3 = Vector3(0.0, 0.0, -4.0)
const INSIDE: Vector3 = Vector3(0.0, 0.0, -2.0)
const OUTSIDE: Vector3 = Vector3(0.0, 0.0, -7.0)

var _failures: int = 0
var _host_net: CompanyNet
var _host_view: CompanyTripsView
var _host_trips: CompanyTrips
var _client_net: CompanyNet
var _client_view: CompanyTripsView
var _late_net: CompanyNet
var _late_view: CompanyTripsView
## Per view: how many `changed`, and every trip_closed [trip, vehicle, failed].
var _changes: Dictionary = {}
var _closed: Dictionary = {}
var _catcher := LogCatcher.new()


## Errors and warnings logged while the test runs.
class LogCatcher extends Logger:
	var _mutex := Mutex.new()
	var _errors: Array[String] = []
	var _warnings: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		var text: String = "%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function]
		if error_type == Logger.ERROR_TYPE_WARNING:
			_warnings.append(text)
		else:
			_errors.append(text)
		_mutex.unlock()

	## [errors, warnings] since the last call.
	func take() -> Array:
		_mutex.lock()
		var out: Array = [_errors.duplicate(), _warnings.duplicate()]
		_errors.clear()
		_warnings.clear()
		_mutex.unlock()
		return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	OS.add_logger(_catcher)
	await _check_solo()
	_check_bad_data()
	await _check_big_cargo()
	_check_never_refused()
	await _check_peers()
	var logged: Array = _catcher.take()
	OS.remove_logger(_catcher)
	_expect(logged[0].is_empty(), "No error is logged (got %s)" % [logged[0]])
	if _failures == 0:
		print("PASS: the host's trips out reach every peer by event and a late joiner by snapshot")
	quit(_failures)


## A side with its CompanyNet and CompanyTripsView, both attached. `with_trips` adds the host's
## CompanyTrips with its gate, followed by the view.
func _new_side(side: Node, with_trips: bool) -> Dictionary:
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	side.add_child(net)
	var view := CompanyTripsView.new()
	view.name = "TripsView"
	side.add_child(view)
	_expect(view.attach(net), "%s: the view attaches to its CompanyNet" % side.name)
	_expect(not view.attach(net), "%s: ...only once (the snapshot part is taken)" % side.name)
	_changes[view] = 0
	_closed[view] = []
	view.changed.connect(func() -> void: _changes[view] += 1)
	view.trip_closed.connect(func(trip: StringName, vehicle: StringName, failed: Array[StringName]) -> void:
		_closed[view].append([trip, vehicle, failed]))
	var parts: Dictionary = {"net": net, "view": view}
	if with_trips:
		var trips := CompanyTrips.new()
		trips.name = "CompanyTrips"
		side.add_child(trips)
		trips.setup(GATE_ORIGIN, 4.0)
		trips.minute_now = func() -> int: return MINUTE
		view.follow(trips)
		parts["trips"] = trips
	return parts


## `ids` PACKED in `trips`' own book, each in a box named box_<id>.
func _packed(trips: CompanyTrips, ids: Array[StringName]) -> void:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	for id: StringName in ids:
		trips.book.add(Order.make(id, "Ana", &"centro", &"house_1",
			[{"product": &"hen", "qty": 1}], 0, products))
		trips.book.mark_packed(id, StringName("box_" + str(id)))


## `vehicle` leaves through the gate with `orders` staged (none: it just crosses).
func _leave(trips: CompanyTrips, vehicle: StringName, orders: Array[StringName]) -> void:
	if not orders.is_empty():
		var boxes: Array[StringName] = []
		for order: StringName in orders:
			boxes.append(StringName("box_" + str(order)))
		trips.stage_cargo(vehicle, orders, boxes)
	trips.track(vehicle, INSIDE)
	trips.track(vehicle, OUTSIDE)


func _come_back(trips: CompanyTrips, vehicle: StringName) -> void:
	trips.track(vehicle, OUTSIDE)
	trips.track(vehicle, INSIDE)


func _check_solo() -> void:
	var side := Node.new()
	side.name = "SoloSide"
	root.add_child(side)
	var parts: Dictionary = _new_side(side, true)
	var net: CompanyNet = parts["net"]
	var view: CompanyTripsView = parts["view"]
	var trips: CompanyTrips = parts["trips"]
	var kinds: Array[StringName] = []
	net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		kinds.append(kind))
	# `changed` comes once CompanyNet is done applying the event: a listener may request or publish.
	var busy: Array[bool] = []
	view.changed.connect(func() -> void: busy.append(net._applying))
	await process_frame
	_expect(view.is_host() and view.trips_out() == 0 and view.vehicles_out().is_empty(),
		"Solo, the view is the host's and nothing is out")
	_expect(net.snapshot().get(CompanyTripsView.SNAPSHOT_KEY) == [],
		"The snapshot carries the trips out, none yet")
	_packed(trips, [&"o1", &"o2"])
	_leave(trips, &"van", [&"o1", &"o2"])
	_expect(kinds == [CompanyTripsView.STARTED] and net.seq == 1,
		"A trip that starts is one trip_started event (got %s, seq %d)" % [kinds, net.seq])
	var shown: Dictionary = view.trip_of(&"van")
	var trip: Trip = trips.trip_of(&"van")
	_expect(trip != null and shown.get("trip") == trip.id and shown.get("orders") == [&"o1", &"o2"]
		and shown.get("boxes") == [&"box_o1", &"box_o2"] and shown.get("minute") == MINUTE,
		"The host's view shows the van's trip, orders, boxes and minute (got %s)" % [shown])
	_expect(view.trips_out() == trips.trips_out() and view.vehicles_out() == [&"van"]
		and view.is_out(&"van") and _changes[view] == 1,
		"...the same count as CompanyTrips, `changed` once (changes %d)" % _changes[view])
	shown["orders"].append(&"forged")
	_expect(view.trip_of(&"van")["orders"].size() == 2, "trip_of() hands out a copy")
	_expect(trip != null and trip.deliver(&"o1", trips.book, 90, true, MINUTE), "o1 is delivered")
	_come_back(trips, &"van")
	_expect(kinds == [CompanyTripsView.STARTED, CompanyTripsView.CLOSED] and view.trips_out() == 0,
		"Coming back is one trip_closed and the view is empty (got %s)" % [kinds])
	_expect(_closed[view] == [[trip.id, &"van", [&"o2"]]] and _changes[view] == 2,
		"...the view's trip_closed carries the failed order (got %s)" % [_closed[view]])
	_expect(busy == [false, false], "`changed` never fires while CompanyNet applies (got %s)" % [busy])
	side.free()


func _check_bad_data() -> void:
	var view := CompanyTripsView.new()
	var good: Dictionary = {
		"trip": &"trip_1", "vehicle": &"van", "orders": [&"o1"], "boxes": [&"box_o1"], "minute": 480,
	}
	var bad: Array[Dictionary] = [
		{"trip": &"trip_1", "vehicle": &"van", "orders": [&"o1"], "boxes": []},
		good.merged({"extra": 1}),
		good.merged({"orders": []}, true),
		good.merged({"orders": [3]}, true),
		good.merged({"orders": "o1"}, true),
		good.merged({"boxes": [&""]}, true),
		good.merged({"minute": -1}, true),
		good.merged({"minute": 480.0}, true),
		good.merged({"trip": &""}, true),
		good.merged({"vehicle": "x".repeat(CompanyTripsView.MAX_ID_LENGTH + 1)}, true),
	]
	for data: Dictionary in bad:
		_expect(not view.apply_trip(CompanyTripsView.STARTED, data), "A malformed trip_started is refused: %s" % [data])
	_expect(view.trips_out() == 0, "...and nothing is out")
	_expect(not view.apply_trip(&"units_moved", good), "Another kind is not the view's")
	_expect(view.apply_trip(CompanyTripsView.STARTED, good), "A good trip_started applies")
	_expect(not view.apply_trip(CompanyTripsView.STARTED, good.merged({"trip": &"trip_2"}, true))
		and not view.apply_trip(CompanyTripsView.REFUSED, {"vehicle": &"van", "minute": 480}),
		"A vehicle already out can't start a trip or be refused again")
	var closed: Dictionary = {"trip": &"trip_1", "vehicle": &"van", "failed": [&"o1"], "minute": 500}
	_expect(not view.apply_trip(CompanyTripsView.CLOSED, closed.merged({"trip": &"trip_9"}, true))
		and not view.apply_trip(CompanyTripsView.CLOSED, closed.merged({"trip": &""}, true))
		and not view.apply_trip(CompanyTripsView.CLOSED, closed.merged({"vehicle": &"bike"}, true))
		and not view.apply_trip(CompanyTripsView.CLOSED, closed.merged({"failed": [7]}, true)),
		"A trip_closed of another trip, of a vehicle not out or with bad ids is refused")
	_expect(view.trips_out() == 1, "...and the van is still out")
	_expect(not view.apply_trip(CompanyTripsView.REFUSED, {"vehicle": &"bike"})
		and not view.apply_trip(CompanyTripsView.REFUSED, {"vehicle": &"bike", "minute": 1, "trip": &""}),
		"A malformed trip_refused is refused")
	var snapshot: Variant = view._take_snapshot_part()
	var before: int = view.trips_out()
	_expect(not view._put_snapshot_part({}) and not view._put_snapshot_part([good, good])
		and not view._put_snapshot_part([good.merged({"orders": [&"o1"], "trip": &""}, true)])
		and not view._put_snapshot_part([{"vehicle": &"van"}]) and view.trips_out() == before,
		"A snapshot part that isn't a list of trips out (repeated vehicle, refused with orders) is refused")
	var too_many: Array = []
	for index: int in range(CompanyTripsView.MAX_OUT + 1):
		too_many.append(good.merged({"vehicle": StringName("van_%d" % index)}, true))
	_expect(not view._put_snapshot_part(too_many), "...as is one over MAX_OUT vehicles")
	_expect(view._put_snapshot_part(snapshot) and view.trip_of(&"van")["trip"] == &"trip_1",
		"The view's own snapshot part goes back in")
	view.free()


## The host keeps and sends only what its view takes: a zone with 65 boxes hands 64, stage_cargo()
## with 65 keeps 64, and the vehicle is out on the view as on CompanyTrips, with no error.
func _check_big_cargo() -> void:
	_catcher.take()
	var zone := DispatchZone.new()
	var many_boxes: Array = []
	var many_orders: Array = []
	for index: int in range(CompanyTrips.MAX_CARGO + 1):
		many_boxes.append(StringName("box_b%d" % index))
		many_orders.append(StringName("b%d" % index))
	zone.from_dict({"boxes": many_boxes, "orders": many_orders})
	var side := Node.new()
	side.name = "CargoSide"
	root.add_child(side)
	var parts: Dictionary = _new_side(side, true)
	var view: CompanyTripsView = parts["view"]
	var trips: CompanyTrips = parts["trips"]
	await process_frame
	_expect(zone.load_into(trips, &"van_zone") == CompanyTrips.MAX_CARGO and zone.boxes().size() == 1,
		"The dispatch zone hands at most MAX_CARGO (%d) boxes; the rest keeps waiting (left %d)"
		% [CompanyTrips.MAX_CARGO, zone.boxes().size()])
	_expect(_catcher.take()[1].is_empty(), "...with no warning: nothing was cut")
	var orders: Array[StringName] = []
	var boxes: Array[StringName] = []
	orders.assign(many_orders)
	boxes.assign(many_boxes)
	_packed(trips, orders)
	trips.stage_cargo(&"van_big", orders, boxes)
	var cut: Array = _catcher.take()
	_expect(cut[1].size() == 1, "stage_cargo() with 65 orders and boxes warns once (got %s)" % [cut[1]])
	_leave(trips, &"van_big", [])
	var trip: Trip = trips.trip_of(&"van_big")
	_expect(trip != null and trip.order_ids.size() == CompanyTrips.MAX_CARGO
		and trip.box_ids.size() == CompanyTrips.MAX_CARGO,
		"...and the trip leaves with 64 of each (got %s)" % [trip.order_ids.size() if trip != null else -1])
	_expect(view.is_out(&"van_big") and view.is_out(&"van_big") == trips.is_out(&"van_big")
		and view.trip_of(&"van_big").get("orders", []).size() == CompanyTrips.MAX_CARGO,
		"The big trip is out on the host's view as on CompanyTrips")
	_come_back(trips, &"van_big")
	_expect(not view.is_out(&"van_big") and not trips.is_out(&"van_big"), "...and back on both")
	trips.stage_cargo(StringName("v".repeat(CompanyTrips.MAX_ID_LENGTH + 1)), [&"b64"], [&"box_b64"])
	var long_id: Array = _catcher.take()
	_expect(long_id[1].size() == 1 and trips.trips_out() == 0,
		"A vehicle id too long stages nothing, with one warning (got %s)" % [long_id[1]])
	_expect(cut[0].is_empty() and long_id[0].is_empty(), "No error on the way")
	side.free()


## The view, handed what CompanyTrips never stages, still sends only what it takes.
func _check_never_refused() -> void:
	_catcher.take()
	var view := CompanyTripsView.new()
	var trip := Trip.new()
	trip.id = &"trip_odd"
	trip.vehicle_id = &"van_odd"
	trip.depart_min = MINUTE
	trip.order_ids.assign([&"o_ok", StringName("o".repeat(CompanyTripsView.MAX_ID_LENGTH + 1))])
	for index: int in range(CompanyTripsView.MAX_ITEMS + 6):
		trip.box_ids.append(StringName("box_%d" % index))
	view._on_trip_started(trip)
	var odd: Array = _catcher.take()
	_expect(view.is_out(&"van_odd") and view.trip_of(&"van_odd")["orders"] == [&"o_ok"]
		and view.trip_of(&"van_odd")["boxes"].size() == CompanyTripsView.MAX_ITEMS and odd[1].size() == 1,
		"A trip with ids that don't fit goes out with those that do, one warning (got %s)" % [odd[1]])
	var never_sent := Trip.new()
	never_sent.id = &"trip_ghost"
	never_sent.vehicle_id = &"van_ghost"
	var none: Array[StringName] = []
	view._on_trip_closed(never_sent, none)
	var ghost: Array = _catcher.take()
	_expect(ghost[1].size() == 1 and view.trips_out() == 1, "The close of a trip never sent sends nothing")
	for index: int in range(CompanyTripsView.MAX_OUT - 1):
		view._on_departure_refused(StringName("van_r%d" % index), {})
	_expect(view.trips_out() == CompanyTripsView.MAX_OUT and _catcher.take()[1].is_empty(),
		"Up to MAX_OUT (%d) vehicles out, every one is sent" % CompanyTripsView.MAX_OUT)
	view._on_departure_refused(&"van_over", {})
	view._on_refused_returned(&"van_over")
	var over: Array = _catcher.take()
	_expect(over[1].size() == 2 and view.trips_out() == CompanyTripsView.MAX_OUT and not view.is_out(&"van_over"),
		"One more is not sent, nor is its return: a warning each (got %s)" % [over[1]])
	_expect(odd[0].is_empty() and ghost[0].is_empty() and over[0].is_empty(), "...and no error")
	view.free()


func _check_peers() -> void:
	var host_side := Node.new()
	host_side.name = "HostSide"
	root.add_child(host_side)
	var client_side := Node.new()
	client_side.name = "ClientSide"
	root.add_child(client_side)
	set_multiplayer(SceneMultiplayer.new(), host_side.get_path())
	set_multiplayer(SceneMultiplayer.new(), client_side.get_path())
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 3) == OK, "The test hosts an ENet session on localhost:%d" % PORT)
	host_side.multiplayer.multiplayer_peer = server
	var host: Dictionary = _new_side(host_side, true)
	_host_net = host["net"]
	_host_view = host["view"]
	_host_trips = host["trips"]
	_packed(_host_trips, [&"o1", &"o2", &"o3", &"o4", &"o5", &"o6", &"o7"])
	var client_peer := ENetMultiplayerPeer.new()
	_expect(client_peer.create_client("127.0.0.1", PORT) == OK, "The client starts joining")
	client_side.multiplayer.multiplayer_peer = client_peer
	var client: Dictionary = _new_side(client_side, false)
	_client_net = client["net"]
	_client_view = client["view"]
	_client_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().size() == 1 and client_side.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if connected:
		_expect(_host_net.send_snapshot(client_side.multiplayer.get_unique_id()), "The host sends the snapshot")
		var joined: bool = await _wait_for(func() -> bool: return not _client_net.awaiting_snapshot())
		_expect(joined and _client_view.trips_out() == 0, "The client joins with nothing out")
		_expect(not _client_view.is_host() and not _client_net.publish(CompanyTripsView.REFUSED,
			{"vehicle": &"van_9", "minute": 1}) and _client_view.trips_out() == 0,
			"A client can't publish a trip event")
		await _check_trip_reaches_client()
		await _check_refused_reaches_client()
		var late_peer := ENetMultiplayerPeer.new()
		var late_side: Node = await _join_late(late_peer)
		if late_side != null:
			await _check_back_reaches_everyone()
		if late_side != null:
			late_peer.close()
	# The host's view leaves its world: snapshots go without its part.
	_host_view.free()
	_expect(_host_net.trips_view == null and not _host_net.snapshot().has(CompanyTripsView.SNAPSHOT_KEY),
		"A view that leaves the tree unhooks itself and its snapshot part")
	client_peer.close()
	server.close()
	await process_frame
	for side: Node in root.get_children():
		if side.name in [&"HostSide", &"ClientSide", &"LateSide"]:
			set_multiplayer(null, side.get_path())
			side.free()
	RpcGuard.reset()


func _check_trip_reaches_client() -> void:
	var changes: int = _changes[_client_view]
	_expect(changes == 1, "The client's snapshot fired `changed` once (got %d)" % changes)
	_leave(_host_trips, &"van_1", [&"o1", &"o2"])
	await _wait_seq(_client_net)
	var shown: Dictionary = _client_view.trip_of(&"van_1")
	var trip: Trip = _host_trips.trip_of(&"van_1")
	_expect(trip != null and shown.get("trip") == trip.id and shown.get("orders") == [&"o1", &"o2"]
		and shown.get("boxes") == [&"box_o1", &"box_o2"] and shown.get("minute") == MINUTE,
		"The host's trip reaches the client's view with its orders (got %s)" % [shown])
	_expect(_client_view.vehicles_out() == [&"van_1"] and _client_view.trips_out() == 1
		and _changes[_client_view] == changes + 1,
		"...one vehicle out, `changed` once more (got %d)" % _changes[_client_view])
	_expect(trip != null and trip.deliver(&"o2", _host_trips.book, 80, true, MINUTE), "o2 is delivered")
	_come_back(_host_trips, &"van_1")
	await _wait_seq(_client_net)
	_expect(_client_view.trips_out() == 0 and _client_view.trip_of(&"van_1").is_empty(),
		"Its close empties the client's view")
	_expect(trip != null and _closed[_client_view] == [[trip.id, &"van_1", [&"o1"]]],
		"...and the failed order arrives with the client's trip_closed (got %s)" % [_closed[_client_view]])


func _check_refused_reaches_client() -> void:
	_leave(_host_trips, &"van_1", [&"o3"])
	_leave(_host_trips, &"van_2", [&"o4"])
	_leave(_host_trips, &"van_3", [&"o5"])
	_expect(_host_trips.trips_out() == 3 and _host_trips.trip_of(&"van_3") == null,
		"On the host the third vehicle out was refused (out %d)" % _host_trips.trips_out())
	await _wait_seq(_client_net)
	var refused: Dictionary = _client_view.trip_of(&"van_3")
	_expect(_client_view.trips_out() == 3 and _client_view.is_out(&"van_3")
		and refused.get("trip") == &"" and refused.get("orders") == [],
		"...and on the client it counts as out, with no trip (out %d, got %s)" % [_client_view.trips_out(), refused])
	_expect(_client_view.vehicles_out() == [&"van_1", &"van_2", &"van_3"],
		"The client sees the three vehicles out in order (got %s)" % [_client_view.vehicles_out()])


## A third peer joins with three vehicles out: the snapshot brings them. Null if it didn't connect.
func _join_late(late_peer: ENetMultiplayerPeer) -> Node:
	var late_side := Node.new()
	late_side.name = "LateSide"
	root.add_child(late_side)
	set_multiplayer(SceneMultiplayer.new(), late_side.get_path())
	_expect(late_peer.create_client("127.0.0.1", PORT) == OK, "A late peer starts joining")
	late_side.multiplayer.multiplayer_peer = late_peer
	var late: Dictionary = _new_side(late_side, false)
	_late_net = late["net"]
	_late_view = late["view"]
	_late_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return _host_net.multiplayer.get_peers().size() == 2 and late_side.multiplayer.get_peers().has(1))
	_expect(connected, "The late peer connects")
	if not connected:
		return null
	# Room for two more trips: van_4 leaves while the joiner waits, van_5 right after its snapshot.
	_host_trips.far_max = 5
	_leave(_host_trips, &"van_4", [&"o6"])
	var held: bool = await _wait_for(func() -> bool: return _late_net._held.has(_host_net.seq))
	_expect(held and _late_view.trips_out() == 0, "A trip_started reaching the joiner before its snapshot is held")
	_expect(_host_net.send_snapshot(late_side.multiplayer.get_unique_id()), "The host sends it the snapshot")
	_leave(_host_trips, &"van_5", [&"o7"])
	var joined: bool = await _wait_for(func() -> bool:
		return not _late_net.awaiting_snapshot() and _late_net.seq == _host_net.seq)
	var all_out: Array[StringName] = [&"van_1", &"van_2", &"van_3", &"van_4", &"van_5"]
	_expect(joined and _late_view.vehicles_out() == all_out and _late_view.trips_out() == 5
		and _late_view.trip_of(&"van_1") == _client_view.trip_of(&"van_1")
		and _late_view.trip_of(&"van_4") == _client_view.trip_of(&"van_4")
		and _late_view.trip_of(&"van_3").get("trip") == &"",
		"The late joiner gets the trips out from the snapshot and the one after it, each once (got %s)"
		% [_late_view.vehicles_out()])
	_expect(_changes[_late_view] == 2 and _closed[_late_view].is_empty(),
		"...with `changed` once for the snapshot and once for van_5, no trip_closed (changes %d)"
		% _changes[_late_view])
	await _wait_seq(_client_net)
	_expect(_client_view.vehicles_out() == all_out, "The first client sees the same five out")
	return late_side


func _check_back_reaches_everyone() -> void:
	var closed_before: int = _closed[_client_view].size()
	_come_back(_host_trips, &"van_3")
	await _wait_seq(_client_net)
	await _wait_seq(_late_net)
	_expect(_client_view.trips_out() == 4 and not _client_view.is_out(&"van_3")
		and _late_view.trips_out() == 4 and not _late_view.is_out(&"van_3"),
		"The refused vehicle back is in again on every peer (client %d, late %d)"
		% [_client_view.trips_out(), _late_view.trips_out()])
	_expect(_closed[_client_view].size() == closed_before and _closed[_late_view].is_empty(),
		"...with no trip_closed signal: it had no trip")
	for vehicle: StringName in [&"van_1", &"van_2", &"van_4", &"van_5"]:
		_come_back(_host_trips, vehicle)
	await _wait_seq(_client_net)
	await _wait_seq(_late_net)
	_expect(_client_view.trips_out() == 0 and _late_view.trips_out() == 0 and _host_view.trips_out() == 0
		and _host_trips.trips_out() == 0, "Everyone back: every view is empty")
	_expect(_closed[_late_view].size() == 4,
		"The late joiner heard the four trips close (got %s)" % [_closed[_late_view]])


## `net` has applied every event the host sent.
func _wait_seq(net: CompanyNet) -> void:
	var target: int = _host_net.seq
	var arrived: bool = await _wait_for(func() -> bool: return net.seq == target)
	_expect(arrived, "The peer received event %d (has %d)" % [target, net.seq])


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
