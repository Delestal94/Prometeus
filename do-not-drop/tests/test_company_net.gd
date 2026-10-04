extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_net.gd
##
## Business events of the company mode (D-2003, scripts/core/company/company_net.gd; contract
## docs/expansion-distritos/diseno/red-autoridad.md), with a host and a client as two ENet
## peers in one process, each CompanyNet on its own SceneMultiplayer:
## - a joining client (wait_for_snapshot(), as CompanyRoot does on a client) holds event 1
##   without applying it until the snapshot is in, then applies what came after it;
## - the client asks to take 3 units from a pallet: nothing changes on it until the host's
##   event comes back, then both inventories hold them in hands:<client>; storing them in a
##   shelf slot moves them on both;
## - asking for more than the station holds is refused with not_enough, to the client only,
##   and nothing changes anywhere; so are bad data (unknown product, a path for one, qty 0,
##   over a pallet, a float qty, no station: bad_data), an unknown station (no_station), a
##   far one (out_of_reach), another product in hand (hands_busy), the hand's limit
##   (hands_full), storing what isn't in hand (not_enough), in another product's slot
##   (wrong_product) or in a full one (no_room);
## - a request without an int rid, of an unknown kind or with nested data is dropped in
##   silence, and a `peer` field doesn't change who acts: the sender does;
## - the host's own request takes the same path and hears its own refusal locally, also when
##   the host makes it while handling another peer's RPC (the units land in hands:1 and that
##   peer hears nothing);
## - a request made from Inventory.stock_changed (mid-apply) is refused and starts no event,
##   and an event that can't be published refuses its request with bad_data;
## - a client can't send an event (the host drops a forged _apply_event) and an old or
##   repeated seq changes nothing on the client;
## - 100 events in a row (host and client requests mixed) leave Inventory.to_dict() equal;
## - a skipped seq makes the client hold what comes and ask for a snapshot; the host lets one
##   request through per 5 s per peer; while it waits the client asks again every 5 s
##   (poll_snapshot()); resume_after_snapshot() applies what was held after it;
## - product ids match the catalog exactly (HEN is not hen);
## - solo (offline), a request applies at once and a refusal is heard at once.
## Expected errors in the log: the forged event ("RPC '_apply_event' is not allowed": Godot's
## authority check dropping it) and the two refused mid-apply requests (CompanyNet's own).

const PORT: int = 24633

var _failures: int = 0
var _host_net: CompanyNet
var _client_net: CompanyNet
var _client_id: int = 0
## [rid, reason] the client heard, in order.
var _client_refusals: Array = []
var _host_refusals: Array = []
var _client_events: int = 0
## Peers the host let a snapshot request through for, and what a D-2004 snapshot would carry
## (the host's stock and seq when the first one came in).
var _snapshot_asks: Array[int] = []
var _snapshot: Dictionary = {}
var _snapshot_seq: int = -1
var _positions: Dictionary = {}
var _host_poke: Poke


## A game node with an RPC of its own (an Interactable's request_interact, say): the host's
## handler runs on_poke while the client's RPC is being handled.
class Poke:
	extends Node
	var on_poke: Callable = Callable()

	@rpc("any_peer", "call_remote", "reliable")
	func poke() -> void:
		if on_poke.is_valid():
			on_poke.call()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_check_helpers()
	_check_solo()

	var host_side := Node.new()
	host_side.name = "HostSide"
	root.add_child(host_side)
	var client_side := Node.new()
	client_side.name = "ClientSide"
	root.add_child(client_side)
	set_multiplayer(SceneMultiplayer.new(), host_side.get_path())
	set_multiplayer(SceneMultiplayer.new(), client_side.get_path())
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 2) == OK
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_expect(up, "The test hosts and joins an ENet session on localhost:%d" % PORT)
	host_side.multiplayer.multiplayer_peer = server
	client_side.multiplayer.multiplayer_peer = client
	_host_net = _add_net(host_side)
	_client_net = _add_net(client_side)
	_host_poke = _add_poke(host_side)
	var client_poke: Poke = _add_poke(client_side)
	var connected: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().size() == 1 \
			and client_side.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if connected:
		_client_id = client_side.multiplayer.get_unique_id()
		_setup()
		await _check_join_waits_for_snapshot()
		await _check_take_and_store()
		await _check_refusals()
		await _check_silent_drops()
		await _check_host_requests()
		await _check_request_inside_rpc(client_poke)
		await _check_no_request_mid_apply()
		await _check_forged_and_old_events()
		await _check_hundred_events()
		await _check_gap_and_snapshot()

	client.close()
	server.close()
	await process_frame
	set_multiplayer(null, host_side.get_path())
	set_multiplayer(null, client_side.get_path())
	host_side.free()
	client_side.free()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: CompanyNet requests checked by the host, events in order on both peers,"
			+ " refusals to the requester, 100 events equal, gaps ask for a snapshot")
	quit(_failures)


func _add_net(side: Node) -> CompanyNet:
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	side.add_child(net)
	return net


func _add_poke(side: Node) -> Poke:
	var poke := Poke.new()
	poke.name = "Poke"
	side.add_child(poke)
	return poke


## Both peers start from the same stock (as a supplier event or a snapshot would leave it);
## only the host knows the stations and where each player stands.
func _setup() -> void:
	_positions = {1: Vector3(0.0, 0.0, 1.0), _client_id: Vector3(0.5, 0.0, 0.5)}
	_host_net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	_host_net.player_origin = func(peer: int) -> Variant: return _positions.get(peer)
	for net: CompanyNet in [_host_net, _client_net]:
		net.inventory.receive(&"hen", 10, &"pallet:p1")
		net.inventory.receive(&"puppy", 5, &"pallet:p2")
		net.inventory.receive(&"hen", 120, &"dock")
	_client_net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		_client_refusals.append([rid, reason]))
	_host_net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		_host_refusals.append([rid, reason]))
	_client_net.event_applied.connect(func(_seq: int, _kind: StringName, _data: Dictionary) -> void:
		_client_events += 1)
	_host_net.snapshot_requested.connect(_on_snapshot_requested)


static func _stations() -> Dictionary:
	return {
		&"pallet_hen": {"location": &"pallet:p1", "spot": Vector3(0.0, 0.0, 0.0)},
		&"pallet_puppy": {"location": &"pallet:p2", "spot": Vector3(1.0, 0.0, 0.0)},
		&"slot_hen": {
			"location": &"shelf:a_0", "spot": Vector3(0.0, 0.0, 2.0),
			"accepts": &"hen", "capacity": 4,
		},
		&"slot_puppy": {
			"location": &"shelf:a_1", "spot": Vector3(0.4, 0.0, 2.0),
			"accepts": &"puppy", "capacity": 4,
		},
		&"dock": {"location": &"dock", "spot": Vector3(-1.0, 0.0, 0.0)},
		&"bin": {"location": &"cart:c1", "spot": Vector3(-1.0, 0.0, 1.0)},
		&"far": {"location": &"pallet:p9", "spot": Vector3(80.0, 0.0, 0.0)},
	}


func _on_snapshot_requested(peer: int) -> void:
	_snapshot_asks.append(peer)
	if _snapshot_seq < 0:
		_snapshot = _host_net.inventory.to_dict()
		_snapshot_seq = _host_net.seq


func _check_helpers() -> void:
	_expect(CompanyNet.hands_location(7) == &"hands:7", "A peer's hands are hands:<peer>")
	_expect(CompanyNet.product_exists(&"hen") and not CompanyNet.product_exists(&"unicorn"),
		"Product ids are checked against data/products/")
	_expect(not CompanyNet.product_exists(&"../products/hen"), "A path is never a product id")
	_expect(not CompanyNet.product_exists(&"HEN") and not CompanyNet.product_exists(&"hen.tres"),
		"A product id matches the catalog's file name exactly (case included, no extension)")
	_expect(CompanyNet.within_reach(Vector3.ZERO, Vector3(4.0, 0.0, 0.0))
		and not CompanyNet.within_reach(Vector3.ZERO, Vector3(5.0, 0.0, 0.0))
		and CompanyNet.within_reach(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), 1.0),
		"Reach is Interactable.REMOTE_REACH plus the slack, measured to the spot")
	_expect(CompanyTuning.HAND_MAX_UNITS >= 3, "A hand holds at least the 3 units of the test")


## Solo is a session of one: the same checks, applied and refused at once.
func _check_solo() -> void:
	var solo := CompanyNet.new()
	solo.name = "SoloCompanyNet"
	root.add_child(solo)
	solo.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	solo.player_origin = func(_peer: int) -> Variant: return Vector3(0.0, 0.0, 1.0)
	solo.inventory.receive(&"hen", 5, &"pallet:p1")
	var events: Array[int] = []
	var refusals: Array = []
	solo.event_applied.connect(func(seq: int, _kind: StringName, _data: Dictionary) -> void:
		events.append(seq))
	solo.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		refusals.append([rid, reason]))
	_expect(solo.is_host(), "Offline, this peer is the host of a session of one")
	solo.request(&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 3})
	var hands: StringName = CompanyNet.hands_location(1)
	_expect(solo.inventory.count(&"hen", hands) == 3 and solo.seq == 1 and events == [1],
		"Solo, a take applies at once as event 1 (hands %d, seq %d, events %s)"
		% [solo.inventory.count(&"hen", hands), solo.seq, events])
	var rid: int = solo.request(
		&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 3})
	_expect(refusals == [[rid, CompanyNet.REASON_NOT_ENOUGH]] and solo.seq == 1,
		"Solo, taking more than is left is refused at once with not_enough (got %s)" % [refusals])
	solo.stations = Callable()
	rid = solo.request(&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 1})
	_expect(refusals.size() == 2 and refusals[1] == [rid, CompanyNet.REASON_NO_STATION],
		"With no stations known, every station is unknown (got %s)" % [refusals])
	solo.free()


## The client's world is up before the snapshot that matches the host: it holds what comes.
func _check_join_waits_for_snapshot() -> void:
	_client_net.wait_for_snapshot()
	var client_stock: Dictionary = _client_net.inventory.to_dict()
	var take: Dictionary = {"station": &"dock", "product": &"hen", "qty": 1}
	_host_net.request(&"units_take", take)
	var at_one: Dictionary = _host_net.inventory.to_dict()
	_host_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 1})
	var sentinel: int = _client_net.request(
		&"units_take", {"station": &"nowhere", "product": &"hen", "qty": 1})
	await _await_refusal(sentinel)
	_expect(_client_net.seq == 0 and _client_net.inventory.to_dict() == client_stock
		and _client_net.awaiting_snapshot() and _client_events == 0,
		"A joining client holds event 1 without applying it (seq %d, %d events applied)"
		% [_client_net.seq, _client_events])
	_expect(_snapshot_asks.is_empty(),
		"...and doesn't ask for a snapshot at once: the host sends one when it is ready")
	# D-2004's part, played here: the snapshot the host had at event 1.
	_client_net.inventory.from_dict(at_one)
	_client_net.resume_after_snapshot(1)
	_expect(_client_net.seq == 2 and _host_net.seq == 2 and _client_events == 1 and _same()
		and not _client_net.awaiting_snapshot(),
		"After the snapshot of event 1 the held event 2 is applied (client seq %d)"
		% _client_net.seq)


func _check_take_and_store() -> void:
	var start: int = _host_net.seq
	var start_events: int = _client_events
	var before: Dictionary = _client_net.inventory.to_dict()
	var rid: int = _client_net.request(
		&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 3})
	_expect(rid > 0, "The client's request gets an id (got %d)" % rid)
	_expect(_client_net.inventory.to_dict() == before,
		"The client changes nothing before the host's event comes back (rule 1)")
	var hands: StringName = CompanyNet.hands_location(_client_id)
	var arrived: bool = await _wait_for(func() -> bool:
		return _client_net.inventory.count(&"hen", hands) == 3)
	_expect(arrived, "The host's event puts 3 hens in the client's hands, on the client")
	_expect(_host_net.inventory.count(&"hen", hands) == 3
		and _host_net.inventory.count(&"hen", &"pallet:p1") == 7
		and _client_net.inventory.count(&"hen", &"pallet:p1") == 7,
		"...and on the host, both pallets left with 7 (host %d, client %d)"
		% [_host_net.inventory.count(&"hen", &"pallet:p1"),
			_client_net.inventory.count(&"hen", &"pallet:p1")])
	_expect(_host_net.seq == start + 1 and _client_net.seq == start + 1
		and _client_events == start_events + 1,
		"It is event %d on both (host %d, client %d)" % [start + 1, _host_net.seq, _client_net.seq])
	_client_net.request(&"units_store", {"station": &"slot_hen", "product": &"hen", "qty": 3})
	arrived = await _wait_for(func() -> bool:
		return _client_net.inventory.count(&"hen", &"shelf:a_0") == 3)
	_expect(arrived and _host_net.inventory.count(&"hen", &"shelf:a_0") == 3
		and _host_net.inventory.count(&"hen", hands) == 0
		and _client_net.inventory.count(&"hen", hands) == 0,
		"Storing them moves the 3 hens from the hands to the shelf slot on both")
	_expect(_same(), "Host and client hold the same stock after take and store")


func _check_refusals() -> void:
	var stock: Dictionary = _host_net.inventory.to_dict()
	var seq: int = _host_net.seq
	var rid: int = _client_net.request(
		&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 20})
	var reason: StringName = await _await_refusal(rid)
	_expect(reason == CompanyNet.REASON_NOT_ENOUGH,
		"Taking 20 from a pallet with 7 is refused with not_enough (got %s)" % reason)
	_expect(_host_refusals.is_empty(), "The refusal goes to the requester only")
	_expect(_host_net.inventory.to_dict() == stock and _client_net.inventory.to_dict() == stock,
		"A refused request changes nothing on either side")
	var max_qty: int = CompanyTuning.PALLET_MAX_UNITS
	var cases: Array = [
		[{"station": &"pallet_hen", "product": &"unicorn", "qty": 1}, CompanyNet.REASON_BAD_DATA,
			"an unknown product"],
		[{"station": &"pallet_hen", "product": "../products/hen", "qty": 1},
			CompanyNet.REASON_BAD_DATA, "a path for a product"],
		[{"station": &"pallet_hen", "product": &"hen", "qty": 0}, CompanyNet.REASON_BAD_DATA,
			"qty 0"],
		[{"station": &"pallet_hen", "product": &"hen", "qty": max_qty + 1},
			CompanyNet.REASON_BAD_DATA, "more than a pallet holds"],
		[{"station": &"pallet_hen", "product": &"hen", "qty": 2.0}, CompanyNet.REASON_BAD_DATA,
			"a float qty"],
		[{"product": &"hen", "qty": 1}, CompanyNet.REASON_BAD_DATA, "no station"],
		[{"station": &"nowhere", "product": &"hen", "qty": 1}, CompanyNet.REASON_NO_STATION,
			"an unknown station"],
		[{"station": &"far", "product": &"hen", "qty": 1}, CompanyNet.REASON_OUT_OF_REACH,
			"a station across the yard"],
	]
	for case: Array in cases:
		rid = _client_net.request(&"units_take", case[0])
		reason = await _await_refusal(rid)
		_expect(reason == case[1], "Taking with %s is refused with %s (got %s)"
			% [case[2], case[1], reason])
	# Hand rules: one product at a time, up to the hand's limit; store only what is held,
	# in a slot for that product with room.
	_client_net.request(&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 2})
	var hands: StringName = CompanyNet.hands_location(_client_id)
	await _wait_for(func() -> bool: return _client_net.inventory.count(&"hen", hands) == 2)
	var over: int = CompanyTuning.HAND_MAX_UNITS - 1
	var hand_cases: Array = [
		[&"units_take", {"station": &"pallet_puppy", "product": &"puppy", "qty": 1},
			CompanyNet.REASON_HANDS_BUSY, "another product while holding hens"],
		[&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": over},
			CompanyNet.REASON_HANDS_FULL, "past the hand's limit"],
		[&"units_store", {"station": &"slot_hen", "product": &"hen", "qty": 3},
			CompanyNet.REASON_NOT_ENOUGH, "storing 3 while holding 2"],
		[&"units_store", {"station": &"slot_puppy", "product": &"hen", "qty": 1},
			CompanyNet.REASON_WRONG_PRODUCT, "storing hens in the puppy slot"],
		[&"units_store", {"station": &"slot_hen", "product": &"hen", "qty": 2},
			CompanyNet.REASON_NO_ROOM, "storing 2 in a slot of 4 that holds 3"],
	]
	stock = _host_net.inventory.to_dict()
	seq = _host_net.seq
	for case: Array in hand_cases:
		rid = _client_net.request(case[0], case[1])
		reason = await _await_refusal(rid)
		_expect(reason == case[2], "%s is refused with %s (got %s)" % [case[3], case[2], reason])
	_expect(_host_net.inventory.to_dict() == stock and _client_net.inventory.to_dict() == stock
		and _host_net.seq == seq and _client_net.seq == seq,
		"No refused request changed the stock or spent a seq")
	_client_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 2})
	_expect(await _wait_for(func() -> bool: return _client_net.inventory.count(&"hen", hands) == 0),
		"The client's hands are empty again")


func _check_silent_drops() -> void:
	var stock: Dictionary = _host_net.inventory.to_dict()
	var seq: int = _host_net.seq
	var take: Dictionary = {"station": &"pallet_hen", "product": &"hen", "qty": 1}
	var string_rid: Dictionary = take.duplicate()
	string_rid["rid"] = "77"
	var nested: Dictionary = take.duplicate()
	nested["rid"] = 78
	nested["extra"] = [1, 2]
	_client_net._request.rpc_id(1, &"units_take", string_rid)
	_client_net._request.rpc_id(1, &"units_take", take)
	_client_net._request.rpc_id(1, &"money_granted", {"rid": 79})
	_client_net._request.rpc_id(1, &"units_take", nested)
	var sentinel: int = _client_net.request(
		&"units_take", {"station": &"nowhere", "product": &"hen", "qty": 1})
	await _await_refusal(sentinel)
	var heard: Array = _client_refusals.map(func(entry: Array) -> int: return int(entry[0]))
	_expect(not heard.has(77) and not heard.has(78) and not heard.has(79),
		"A request with no int rid, an unknown kind or nested data is dropped in silence (%s)"
		% [heard])
	_expect(_host_net.inventory.to_dict() == stock and _host_net.seq == seq,
		"...and changes nothing on the host")
	# The actor is whoever sent it: a peer field in data means nothing.
	var as_host: Dictionary = take.duplicate()
	as_host["peer"] = 1
	_client_net.request(&"units_take", as_host)
	var hands: StringName = CompanyNet.hands_location(_client_id)
	var moved: bool = await _wait_for(func() -> bool:
		return _client_net.inventory.count(&"hen", hands) == 1)
	_expect(moved and _host_net.inventory.count(&"hen", hands) == 1
		and _host_net.inventory.count(&"hen", CompanyNet.hands_location(1)) == 0,
		"A take that says peer 1 lands in the sender's hands, not the host's")
	_client_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 1})
	await _wait_for(func() -> bool: return _client_net.inventory.count(&"hen", hands) == 0)


func _check_host_requests() -> void:
	var hands: StringName = CompanyNet.hands_location(1)
	_host_net.request(&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 2})
	_expect(_host_net.inventory.count(&"hen", hands) == 2,
		"The host's own take applies at once on the host")
	_expect(await _wait_for(func() -> bool: return _client_net.inventory.count(&"hen", hands) == 2),
		"...and reaches the client as an event")
	var rid: int = _host_net.request(
		&"units_take", {"station": &"pallet_puppy", "product": &"puppy", "qty": 1})
	_expect(_host_refusals == [[rid, CompanyNet.REASON_HANDS_BUSY]],
		"The host hears its own refusal at once (got %s)" % [_host_refusals])
	_host_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 2})
	_expect(await _wait_for(func() -> bool: return _client_net.seq == _host_net.seq),
		"The client catches up with the host's events")
	_expect(_same(), "Host and client hold the same stock after the host's requests")


## The host requests while handling another peer's RPC: the request is still the host's.
func _check_request_inside_rpc(client_poke: Poke) -> void:
	var rids: Array[int] = []
	_host_poke.on_poke = func() -> void:
		rids.append(_host_net.request(
			&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 1}))
		rids.append(_host_net.request(
			&"units_take", {"station": &"nowhere", "product": &"hen", "qty": 1}))
	var heard: int = _client_refusals.size()
	client_poke.poke.rpc_id(1)
	var done: bool = await _wait_for(func() -> bool: return rids.size() == 2)
	_host_poke.on_poke = Callable()
	var host_hands: StringName = CompanyNet.hands_location(1)
	var client_hands: StringName = CompanyNet.hands_location(_client_id)
	_expect(done and _host_net.inventory.count(&"hen", host_hands) == 1
		and _host_net.inventory.count(&"hen", client_hands) == 0,
		"A take the host makes inside the client's RPC lands in hands:1, not the client's")
	_expect(done and _host_refusals.has([rids[1], CompanyNet.REASON_NO_STATION]),
		"...and its refusal is the host's own (%s)" % [_host_refusals])
	var sentinel: int = _client_net.request(
		&"units_take", {"station": &"nowhere", "product": &"hen", "qty": 1})
	await _await_refusal(sentinel)
	_expect(_client_refusals.size() == heard + 1,
		"The client whose RPC was being handled hears no refusal of the host's (%s)"
		% [_client_refusals.slice(heard)])
	_expect(_client_net.inventory.count(&"hen", host_hands) == 1, "The client sees it in hands:1")
	_host_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 1})
	_expect(await _wait_for(func() -> bool: return _client_net.seq == _host_net.seq) and _same(),
		"Host and client hold the same stock after it")


## Inventory.stock_changed fires while an event is applied: a request made there would number
## its event before the one being applied, so it is refused and nothing nests.
func _check_no_request_mid_apply() -> void:
	var start: int = _host_net.seq
	var nested: Array[int] = []
	var listener: Callable = func(_product: StringName, _location: StringName) -> void:
		if nested.is_empty():
			nested.append(_host_net.request(
				&"units_take", {"station": &"dock", "product": &"hen", "qty": 1}))
			# Past request()'s guard, the event itself is refused: the request hears bad_data.
			_host_net._take_request(1, &"units_take",
				{"station": &"dock", "product": &"hen", "qty": 1, "rid": 991})
	_host_net.inventory.stock_changed.connect(listener)
	_host_net.request(&"units_take", {"station": &"dock", "product": &"hen", "qty": 1})
	_host_net.inventory.stock_changed.disconnect(listener)
	_expect(nested == [0] and _host_net.seq == start + 1,
		"A request from stock_changed is refused and starts no event (rid %s, %d events)"
		% [nested, _host_net.seq - start])
	_expect(_host_refusals.has([991, CompanyNet.REASON_BAD_DATA]),
		"An event that can't be published refuses its request with bad_data (%s)"
		% [_host_refusals])
	_host_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 1})
	_expect(await _wait_for(func() -> bool: return _client_net.seq == _host_net.seq) and _same(),
		"The client stays equal to the host")


func _check_forged_and_old_events() -> void:
	var stock: Dictionary = _host_net.inventory.to_dict()
	var seq: int = _host_net.seq
	var hands: StringName = CompanyNet.hands_location(_client_id)
	var forged: Dictionary = {"product": &"hen", "qty": 5, "from": &"dock", "to": hands}
	# Godot drops it (authority-only RPC) and logs an error: expected.
	_client_net._apply_event.rpc_id(1, seq + 1, &"units_moved", forged)
	var sentinel: int = _client_net.request(
		&"units_take", {"station": &"nowhere", "product": &"hen", "qty": 1})
	await _await_refusal(sentinel)
	_expect(_host_net.inventory.to_dict() == stock and _host_net.seq == seq,
		"An event a client sends changes nothing on the host")
	var client_events: int = _client_events
	_host_net._apply_event.rpc_id(_client_id, seq, &"units_moved", forged)
	_host_net._apply_event.rpc_id(_client_id, 1, &"units_moved", forged)
	_host_net.request(&"units_take", {"station": &"dock", "product": &"hen", "qty": 1})
	_host_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 1})
	_expect(await _wait_for(func() -> bool: return _client_net.seq == _host_net.seq),
		"The client applies the next real events")
	_expect(_client_events == client_events + 2 and _same(),
		"A repeated or old seq changes nothing on the client (%d events applied, expected %d)"
		% [_client_events - client_events, 2])


func _check_hundred_events() -> void:
	# A fresh request budget for the client: this section alone sends 10.
	RpcGuard.forget_peer(_client_id)
	var start: int = _host_net.seq
	var client_events: int = _client_events
	var dock_take: Dictionary = {"station": &"dock", "product": &"hen", "qty": 1}
	var bin_store: Dictionary = {"station": &"bin", "product": &"hen", "qty": 1}
	for i: int in range(45):
		_host_net.request(&"units_take", dock_take)
		_host_net.request(&"units_store", bin_store)
		if i % 9 == 0:
			_client_net.request(&"units_take", dock_take)
			_client_net.request(&"units_store", bin_store)
	var done: bool = await _wait_for(func() -> bool:
		return _host_net.seq == start + 100 and _client_net.seq == _host_net.seq)
	_expect(done, "100 events in a row reach the client (host seq %d, client seq %d, from %d)"
		% [_host_net.seq, _client_net.seq, start])
	_expect(_client_events == client_events + 100,
		"The client applied each of them once (%d)" % (_client_events - client_events))
	_expect(_same(), "After 100 events Inventory.to_dict() is the same on host and client")


func _check_gap_and_snapshot() -> void:
	_snapshot_asks.clear()
	_snapshot_seq = -1
	var client_stock: Dictionary = _client_net.inventory.to_dict()
	var client_seq: int = _client_net.seq
	# An event this client never got (sent before its world was up): the next one skips it.
	_host_net.seq += 1
	_host_net.request(&"units_take", {"station": &"dock", "product": &"hen", "qty": 1})
	var asked: bool = await _wait_for(func() -> bool: return not _snapshot_asks.is_empty())
	_expect(asked and _snapshot_asks == [_client_id],
		"A skipped seq makes the client ask the host for a snapshot (%s)" % [_snapshot_asks])
	_expect(_client_net.inventory.to_dict() == client_stock and _client_net.seq == client_seq
		and _client_net.awaiting_snapshot(),
		"The event after the gap is held, not applied (client seq %d)" % _client_net.seq)
	# Sent while the client waits: held too.
	_host_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 1})
	_client_net.request(CompanyNet.SNAPSHOT_REQUEST)
	var sentinel: int = _client_net.request(
		&"units_take", {"station": &"nowhere", "product": &"hen", "qty": 1})
	await _await_refusal(sentinel)
	_expect(_snapshot_asks.size() == 1,
		"A second snapshot request within 5 s is dropped by the host (%d let through)"
		% _snapshot_asks.size())
	_expect(_client_net.inventory.to_dict() == client_stock,
		"Nothing is applied while the client waits for the snapshot")
	var later: int = Time.get_ticks_msec() + CompanyNet.SNAPSHOT_INTERVAL_MSEC
	_expect(_host_net.grant_snapshot(_client_id, later),
		"5 s later the host lets the next snapshot request through")
	# The client's own retry, on a clock the test drives (the host drops these: too soon).
	var clock: int = Time.get_ticks_msec() + 100000
	var interval: int = CompanyNet.SNAPSHOT_INTERVAL_MSEC
	_expect(_client_net.poll_snapshot(clock), "While it waits, the client asks again after 5 s")
	_expect(not _client_net.poll_snapshot(clock + interval - 1), "...not before 5 s more")
	_expect(_client_net.poll_snapshot(clock + interval), "...and again once they passed")
	# D-2004's part, played here: the snapshot the host had when asked, then what was held.
	_client_net.inventory.from_dict(_snapshot)
	_client_net.resume_after_snapshot(_snapshot_seq)
	_expect(_snapshot_seq == client_seq + 2 and _client_net.seq == _host_net.seq
		and not _client_net.awaiting_snapshot(),
		"After the snapshot (seq %d) the held event is applied (client seq %d, host %d)"
		% [_snapshot_seq, _client_net.seq, _host_net.seq])
	_expect(_same(), "After the snapshot and the held event the stock is the host's")
	_expect(not _client_net.poll_snapshot(clock + 10 * interval),
		"With the snapshot in, the client stops asking")


func _same() -> bool:
	return _host_net.inventory.to_dict() == _client_net.inventory.to_dict()


func _await_refusal(rid: int) -> StringName:
	await _wait_for(func() -> bool: return _refusal(rid) != &"")
	return _refusal(rid)


func _refusal(rid: int) -> StringName:
	for entry: Array in _client_refusals:
		if int(entry[0]) == rid:
			return entry[1]
	return &""


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
