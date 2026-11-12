extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_door.gd
##
## The customer's door in the company world (D-0340, D-0815.b, D-0817.b): company_door.gd (CompanyDoor, added by
## CompanyRoot), delivery_house.gd (DeliveryHouse.door_check), company_orders_net.gd (order_delivered) and
## company_trips.gd (active_trips()).
## - the real solo company_root.tscn: houses of Centro (HouseMap.instance(), as the cells put them) entering the tree
##   get the root's door; a van loaded by the board with three boxes leaves the yard (trip_started); the player takes
##   each box off the van's rack and rings: an empty-handed ring changes nothing (no seq, the house takes boxes
##   afterwards), a box of another house's order and a box at a house with no order out are handed back
##   (wrong_package_offered, still in the hands); the right box settles its order: OrderSettlement through the door,
##   DELIVERED with the host's stars in the shared book and in the trips' book, recorded on the Trip, the box consumed
##   and its units gone from package:<box>, the events order_delivered then wallet_moved (order_paid, then tip), the
##   money moved by exactly what was paid, EventBus.order_delivered heard; one house takes two orders in a row; a box
##   missing a product pays less than the order (penalty `wrong`), costs reputation and the customer reacts angry
##   (5, 3 and 1 stars cheer, shrug and fume with a translated line); the van comes back with nothing failed and no
##   order charged the -3 of a failed one;
## - order_delivered's shape: the host publishes none for an unknown order, one already delivered, stars 0, an unknown
##   or repeated penalty, a missing or extra key, a float pay, a reputation out of range (no seq);
## - a host and a client as ENet peers, each with its CompanyNet, trips view, door and a house of Centro: a box rung
##   at the host's house leaves both books equal (DELIVERED, the host's stars), the same money and last ledger
##   entries, the same reputation (it travels absolute) and the box's units gone on both; the client hears
##   EventBus.order_delivered and its house's customer reacts with the same line; a client's door settles nothing.
## Expected in the log: CompanyNet's error for each malformed order_delivered the host refuses ("could not apply its
## own").

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_door"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const HEN: ProductDefinition = preload("res://data/products/hen.tres")
const BREAD: ProductDefinition = preload("res://data/products/sourdough.tres")
const PORT: int = 24761
const ZONE: StringName = &"centro"

var _failures: int = 0
var _delivered_heard: Array[StringName] = []
var _host: Peer
var _client: Peer


## Something that rings a doorbell holding `carried_package` (DoorbellPoint reads only that).
class Hands:
	extends Node3D
	var carried_package: Node = null


## One peer of the network part.
class Peer:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var view: CompanyTripsView
	var trips: CompanyTrips
	var door: CompanyDoor
	var house: DeliveryHouse
	var kinds: Array[StringName] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	var bus: Node = root.get_node_or_null(^"EventBus")
	if bus != null:
		bus.connect(&"order_delivered", func(order_id: StringName) -> void: _delivered_heard.append(order_id))
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	for _frame: int in 4:
		await process_frame
	await physics_frame
	var door := level.get_node_or_null(NodePath(CompanyDoor.NODE_NAME)) as CompanyDoor
	_expect(door != null and level.trips != null and level.player != null,
		"The solo root has its door, its trips and its player")
	if door != null and level.trips != null and level.player != null:
		await _play_world(level, door)
		_check_shapes(level)
	level.queue_free()
	current_scene = null
	await process_frame
	state.call(&"reset")
	_clean()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: the customer's door settles the order it was dispatched for, hands back the rest, pays through"
			+ " the wallet's events and gives every peer the same book, money, stars and reputation")
	quit(_failures)


# --- The real world ---


func _play_world(level: CompanyRoot, door: CompanyDoor) -> void:
	var net: CompanyNet = level.net
	var trips: CompanyTrips = level.trips
	var dispatch := level.get_node(^"Dispatch") as CompanyDispatch
	var homes: Array[HouseSpot] = HouseMap.load_default().in_zone(ZONE)
	level.day_cycle.call(&"_transition", DayCycle.Phase.OPERATING)
	level.clock.start(600.0)
	var house_a: DeliveryHouse = _add_house(level, homes[0])
	var house_b: DeliveryHouse = _add_house(level, homes[1])
	var house_c: DeliveryHouse = _add_house(level, homes[2])
	_expect(door.house(homes[0].id) == house_a and house_a.door_check.is_valid() and house_c.door_check.is_valid(),
		"Houses entering the tree get the root's door")
	var one: Dictionary = _order(&"d_one", homes[0].id, [{"product": &"hen", "qty": 1}])
	var two: Dictionary = _order(&"d_two", homes[0].id,
		[{"product": &"hen", "qty": 1}, {"product": &"sourdough", "qty": 1}])
	var three: Dictionary = _order(&"d_three", homes[1].id, [{"product": &"hen", "qty": 1}])
	for order: Dictionary in [one, two, three]:
		_expect(net.publish(CompanyOrdersNet.ADDED, {"order": order}), "Order %s comes in" % order["id"])
	var boxes: Array[StringName] = []
	var packages: Dictionary = {}
	for order: Dictionary in [one, two, three]:
		var package: DeliveryPackage = _box(level, order["id"])
		packages[order["id"]] = package
		boxes.append(package.package_id)
		dispatch._order_of[package.package_id] = order["id"]
	var van_body: Node3D = level.fleet.vehicles()[0]
	var van := StringName(van_body.name)
	trips.stage_cargo(van, [&"d_one", &"d_two", &"d_three"], boxes)
	dispatch._on_loaded(van, boxes)
	trips.gate.departed.emit(van)
	var trip: Trip = trips.trip_of(van)
	_expect(trip != null and net.orders.book.state_of(&"d_one") == Order.STATE_OUT
		and (packages[&"d_one"] as DeliveryPackage).is_loaded,
		"The van leaves with the three boxes on its rack and the orders out (trip %s, %s)"
		% [trip, net.orders.book.state_of(&"d_one")])
	if trip == null:
		return
	var player: Player = level.player as Player
	var rep_start: float = float(net.company.get(&"reputation"))

	# An empty-handed ring changes nothing.
	var seq: int = net.seq
	house_a.doorbell.interact(player)
	_expect(net.seq == seq and not house_a.delivered and net.orders.book.state_of(&"d_one") == Order.STATE_OUT,
		"An empty-handed ring changes nothing (seq %d to %d, delivered %s)" % [seq, net.seq, house_a.delivered])

	# The third box: handed back at the wrong house and at a house with no order, taken at its own.
	var box_three: DeliveryPackage = packages[&"d_three"]
	_take(box_three, player)
	_expect(player.carried_package == box_three and not box_three.is_loaded,
		"The player takes the third box off the van's rack")
	var refusals: Array = []
	house_a.wrong_package_offered.connect(func(label: String) -> void: refusals.append(label))
	house_c.wrong_package_offered.connect(func(label: String) -> void: refusals.append(label))
	house_a.doorbell.interact(player)
	house_c.doorbell.interact(player)
	_expect(refusals.size() == 2 and player.carried_package == box_three and net.seq == seq
		and net.orders.book.state_of(&"d_three") == Order.STATE_OUT,
		"Another house's order and a house with no order hand the box back (refusals %d, seq %d)"
		% [refusals.size(), net.seq - seq])
	await _deliver(level, house_b, box_three, &"d_three", trip)

	# One house, two orders in a row.
	_take(packages[&"d_one"], player)
	await _deliver(level, house_a, packages[&"d_one"], &"d_one", trip)
	_expect(_reaction(house_a) == &"happy" or _reaction(house_a) == &"inspect",
		"...a clean delivery: the customer cheers or shrugs (got %s)" % _reaction(house_a))
	_take(packages[&"d_two"], player)
	var money: int = int(net.company.get(&"money"))
	var rep_before: float = float(net.company.get(&"reputation"))
	var settled: Dictionary = await _deliver(level, house_a, packages[&"d_two"], &"d_two", trip)
	_expect(int(settled.get("paid", -1)) < int(two["pay"]) and (settled.get("kinds", []) as Array).has(
		OrderPenalties.KIND_WRONG) and int(net.company.get(&"money")) == money + int(settled.get("paid", 0)),
		"The box missing a product pays less than the order (%s of %d, %s)"
		% [settled.get("paid"), two["pay"], settled.get("kinds")])
	_expect(_reaction(house_a) == &"grab_head", "...and the customer reacts angry (got %s)" % _reaction(house_a))
	_expect(float(net.company.get(&"reputation")) < rep_before,
		"...and it costs reputation (%.1f to %.1f)" % [rep_before, float(net.company.get(&"reputation"))])
	_check_reactions(house_a.house_index)

	trips.gate.returned.emit(van)
	_expect(trips.trip_of(van) == null and trip.failed_ids.is_empty()
		and net.orders.book.state_of(&"d_one") == Order.STATE_DELIVERED,
		"The van comes back with nothing failed (failed %s)" % [trip.failed_ids])
	_expect(float(net.company.get(&"reputation")) >= rep_start - 1.0,
		"...no order cost the -3 of a failed one (reputation %.1f to %.1f)"
		% [rep_start, float(net.company.get(&"reputation"))])


## Rings `at` with `box` in the player's hands and checks the order settled everywhere. Returns settle()'s result.
func _deliver(level: CompanyRoot, at: DeliveryHouse, box: DeliveryPackage, order_id: StringName,
		trip: Trip) -> Dictionary:
	var net: CompanyNet = level.net
	var door := level.get_node(NodePath(CompanyDoor.NODE_NAME)) as CompanyDoor
	var player: Player = level.player as Player
	var money: int = int(net.company.get(&"money"))
	var ledger_size: int = (net.company.get(&"ledger") as Array).size()
	var seq: int = net.seq
	var location: StringName = CompanyTableNet.package_location(box.package_id)
	var events: Array = []
	var note := func(_seq: int, kind: StringName, data: Dictionary) -> void: events.append([kind, data])
	net.event_applied.connect(note)
	var results: Array = []
	var heard := func(id: StringName, result: Dictionary) -> void: results.append([id, result])
	door.settled.connect(heard)
	at.doorbell.interact(player)
	net.event_applied.disconnect(note)
	door.settled.disconnect(heard)
	await process_frame
	var result: Dictionary = results[0][1] if results.size() == 1 else {}
	_expect(results.size() == 1 and results[0][0] == order_id and bool(result.get("ok", false)),
		"%s: the door settles it (got %s)" % [order_id, results])
	var shared: Dictionary = net.orders.book.get_order(order_id)
	_expect(shared.get("state") == Order.STATE_DELIVERED and int(shared.get("stars", 0)) == int(result.get("stars", -1))
		and int(shared.get("paid", -1)) == int(result.get("paid", -2)),
		"%s: DELIVERED in the shared book with the door's stars and pay (got %s)" % [order_id, shared])
	_expect(level.trips.book.state_of(order_id) == Order.STATE_DELIVERED and order_id in trip.delivered_ids,
		"%s: delivered in the trips' book and recorded on the trip" % order_id)
	_expect(player.carried_package == null and box.consumed and net.inventory.contents_at(location).is_empty(),
		"%s: the box was handed over (hands empty, consumed, %s empty)" % [order_id, location])
	var kinds: Array = events.map(func(event: Array) -> StringName: return event[0])
	var expected: Array = [CompanyOrdersNet.DELIVERED]
	if int(result.get("paid", 0)) > 0:
		expected.append(CompanyNet.WALLET)
	if int(result.get("tip", 0)) > 0:
		expected.append(CompanyNet.WALLET)
	_expect(kinds == expected and net.seq == seq + expected.size(),
		"%s: order_delivered, then the wallet's movements (got %s)" % [order_id, kinds])
	var reasons: Array = (net.company.get(&"ledger") as Array).slice(ledger_size).map(
		func(entry: Dictionary) -> String: return str(entry.get("reason")))
	var paid_reasons: Array = []
	if int(result.get("paid", 0)) > 0:
		paid_reasons.append("order_paid")
	if int(result.get("tip", 0)) > 0:
		paid_reasons.append("tip")
	_expect(int(net.company.get(&"money")) == money + int(result.get("paid", 0)) + int(result.get("tip", 0))
		and reasons == paid_reasons,
		"%s: the money moved by what was paid, with its ledger lines (%d to %s, %s)"
		% [order_id, money, net.company.get(&"money"), reasons])
	_expect(_delivered_heard.has(order_id), "%s: EventBus.order_delivered was heard" % order_id)
	return result


## The three reactions (D-0817.b): 5 stars cheer, 3 shrug, 1 angry, each with its scene and a line.
func _check_reactions(house_index: int) -> void:
	var scenes: Array = []
	for stars: int in [5, 3, 1]:
		var shown: Dictionary = CompanyDoor.reaction_of({"stars": stars, "penalties": []}, house_index, 7)
		_expect(not String(shown["line"]).is_empty() and tr(shown["line"]) != String(shown["line"]),
			"%d stars: the customer says a translated line (%s)" % [stars, shown["line"]])
		scenes.append(shown["scene"])
	_expect(scenes == [DeliveryHouse.OUTCOME_OK, DeliveryHouse.OUTCOME_AT_RISK, DeliveryHouse.OUTCOME_RUINED],
		"...and plays cheer, shrug and angry at the door (got %s)" % [scenes])


## Malformed order_delivered: the host publishes none.
func _check_shapes(level: CompanyRoot) -> void:
	var net: CompanyNet = level.net
	var good: Dictionary = {
		"order": &"d_one", "package_id": &"box_d_one", "paid": 10, "tip": 0, "stars": 3, "quality": 100,
		"intact": true, "penalties": [], "reputation": 50.0,
	}
	var seq: int = net.seq
	var cases: Array = [
		[{"order": &"nobody"}, "an unknown order"],
		[{}, "an order already delivered"],
		[{"stars": 0}, "stars 0"],
		[{"penalties": [&"unicorn"]}, "an unknown penalty"],
		[{"penalties": [&"late", &"late"]}, "a repeated penalty"],
		[{"paid": 10.5}, "a float pay"],
		[{"reputation": 101.0}, "a reputation out of range"],
	]
	for case: Array in cases:
		_expect(not net.publish(CompanyOrdersNet.DELIVERED, good.merged(case[0], true)) and net.seq == seq,
			"The host publishes no order_delivered with %s" % case[1])
	var missing: Dictionary = good.duplicate()
	missing.erase("tip")
	var extra: Dictionary = good.merged({"minute": 5})
	_expect(not net.publish(CompanyOrdersNet.DELIVERED, missing) and not net.publish(CompanyOrdersNet.DELIVERED, extra)
		and net.seq == seq, "...nor with a key missing or an extra one")


# --- Host and client ---


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 2) == OK
	_host.side.multiplayer.multiplayer_peer = server
	_add_net(_host, true)
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_client.side.multiplayer.multiplayer_peer = client
	_add_net(_client, false)
	_client.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return _client.side.multiplayer.get_peers().has(1) and _host.side.multiplayer.get_peers().size() == 1)
	_expect(up and connected, "The client connects to the host on localhost:%d" % PORT)
	if connected:
		await _play_network()
	client.close()
	server.close()
	await process_frame
	for peer: Peer in [_host, _client]:
		set_multiplayer(null, peer.side.get_path())
		peer.side.free()


func _play_network() -> void:
	var spot: HouseSpot = HouseMap.load_default().in_zone(ZONE)[0]
	for peer: Peer in [_host, _client]:
		peer.house = HouseMap.load_default().instance(spot)
		peer.side.add_child(peer.house)
	var net: CompanyNet = _host.net
	var order: Dictionary = _order(&"n_one", spot.id, [{"product": &"hen", "qty": 1}])
	var box := PackedBox.new(&"M")
	box.place(HEN, Vector3i.ZERO)
	box.taped = true
	box.label_order_id = &"n_one"
	var package: DeliveryPackage = BoxToPackage.build(box, {&"hen": HEN})
	# Only the host has this box (no box_sealed made it): its synchronizer reaches nobody.
	(package.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).public_visibility = false
	_host.side.add_child(package)
	package.freeze = true
	var location: StringName = CompanyTableNet.package_location(package.package_id)
	net.inventory.receive(&"hen", 1, location)
	net.company.set(&"clock_minutes", 600)
	net.company.set(&"reputation", 47.0)
	_host.net.send_snapshot(_client.side.multiplayer.get_unique_id())
	_expect(await _wait_for(_same_seq) and _client.net.inventory.count(&"hen", location) == 1,
		"The client gets the host's snapshot, the box's unit in it")
	net.publish(CompanyOrdersNet.ADDED, {"order": order})
	_host.trips.book.add(order)
	_host.trips.book.mark_packed(&"n_one", package.package_id)
	_host.trips.stage_cargo(&"van_1", [&"n_one"], [package.package_id])
	_host.trips.track(&"van_1", Vector3(0, 0, -2))
	_host.trips.track(&"van_1", Vector3(0, 0, -6))
	_expect(await _wait_for(_same_seq) and _client.net.orders.book.state_of(&"n_one") == Order.STATE_OUT,
		"The order is out on both books (client %s)" % _client.net.orders.book.state_of(&"n_one"))

	var packed: PackedBox = CompanyDoor.packed_box_of(package)
	_expect(not bool(_client.door.settle(&"n_one", packed, [], package.package_id)["ok"])
		and _client.net.orders.book.state_of(&"n_one") == Order.STATE_OUT,
		"A client's door settles nothing")
	var heard: int = _delivered_heard.size()
	var hands := Hands.new()
	_host.side.add_child(hands)
	hands.carried_package = package
	_host.house.doorbell.interact(hands)
	_expect(await _wait_for(_same_seq) and _same_book()
		and _client.net.orders.book.state_of(&"n_one") == Order.STATE_DELIVERED,
		"The host's door settles it: both books are equal, DELIVERED (client %s)"
		% _client.net.orders.book.state_of(&"n_one"))
	var stars: int = int(_client.net.orders.book.get_order(&"n_one").get("stars", 0))
	_expect(stars >= CompanyTuning.STARS_MIN and stars == int(net.orders.book.get_order(&"n_one").get("stars", -1)),
		"...with the host's stars on the client (%d)" % stars)
	var host_ledger: Array = _host.state.get(&"ledger")
	var client_ledger: Array = _client.state.get(&"ledger")
	_expect(int(_host.state.get(&"money")) == int(_client.state.get(&"money")) and not client_ledger.is_empty()
		and client_ledger.back() == host_ledger.back(),
		"...the same money and last ledger entry (host %s, client %s)"
		% [_host.state.get(&"money"), _client.state.get(&"money")])
	_expect(is_equal_approx(float(_host.state.get(&"reputation")), float(_client.state.get(&"reputation")))
		and float(_host.state.get(&"reputation")) > 47.0,
		"...the same reputation, the host's after a clean delivery (host %.2f, client %.2f)"
		% [float(_host.state.get(&"reputation")), float(_client.state.get(&"reputation"))])
	_expect(net.inventory.count(&"hen", location) == 0 and _client.net.inventory.count(&"hen", location) == 0,
		"...and the box's unit is gone on both")
	_expect(_delivered_heard.slice(heard).count(&"n_one") == 2,
		"Both peers told EventBus.order_delivered (got %s)" % [_delivered_heard.slice(heard)])
	var expected: Dictionary = CompanyDoor.reaction_of(
		{"stars": stars, "penalties": []}, _client.house.house_index, _session_seed())
	_expect(_client.house.reaction.last_line == tr(expected["line"]) and not String(expected["line"]).is_empty()
		and _client.house.reaction.last_line == _host.house.reaction.last_line,
		"The customer reacts on the client too, with the host's line (got '%s')" % _client.house.reaction.last_line)
	hands.free()
	if is_instance_valid(package):
		package.free()


# --- Helpers ---


## A house of the map standing in the world, put in the tree as the Centro cells do (HouseMap.instance()).
func _add_house(level: CompanyRoot, spot: HouseSpot) -> DeliveryHouse:
	var house: DeliveryHouse = HouseMap.load_default().instance(spot)
	level.get_node(^"World").add_child(house)
	return house


## A sealed box for `order_id` (one hen) under World/Packages with its unit at package:<box>. Returns its package.
func _box(level: CompanyRoot, order_id: StringName) -> DeliveryPackage:
	var box := PackedBox.new(&"M")
	box.place(HEN, Vector3i.ZERO)
	box.taped = true
	box.label_order_id = order_id
	var package: DeliveryPackage = BoxToPackage.build(box, {&"hen": HEN})
	level.packages.add_child(package)
	package.freeze = true
	package.global_position = CompanyDispatch.area_of(level.shed).get_center()
	level.net.inventory.receive(&"hen", 1, CompanyTableNet.package_location(package.package_id))
	return package


## The player takes `box` (off the rack) through its pickup point, as the interact key does.
func _take(box: DeliveryPackage, player: Player) -> void:
	(box.get_node(^"InteractionArea") as Interactable).interact(player)


func _reaction(house: DeliveryHouse) -> StringName:
	return house.reaction.last_action if house.reaction != null else &""


func _order(id: StringName, house: StringName, items: Array) -> Dictionary:
	var products: Dictionary = {&"hen": HEN, &"sourdough": BREAD}
	return Order.normalize(Order.make(id, "Ana", ZONE, house, items, 480, products, [], 1300))


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node3D.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	return peer


func _add_net(peer: Peer, host: bool) -> void:
	peer.state = (load(STATE_SCRIPT) as GDScript).new()
	peer.state.call(&"reset")
	peer.state.call(&"new_company", peer.side.name)
	peer.side.add_child(peer.state)
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.side.add_child(peer.net)
	peer.view = CompanyTripsView.new()
	peer.view.name = "TripsView"
	peer.side.add_child(peer.view)
	peer.view.attach(peer.net)
	if host:
		peer.trips = CompanyTrips.new()
		peer.trips.name = "CompanyTrips"
		peer.side.add_child(peer.trips)
		peer.trips.setup(Vector3(0, 0, -4), 2.0)
		peer.view.follow(peer.trips)
	peer.door = CompanyDoor.add_to(peer.side, peer.net, peer.trips)
	peer.net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		peer.kinds.append(kind))


func _same_seq() -> bool:
	return _client.net.seq == _host.net.seq and not _client.net.awaiting_snapshot()


func _same_book() -> bool:
	return _client.net.orders.book.to_dict() == _host.net.orders.book.to_dict()


func _session_seed() -> int:
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	var value: Variant = network.get(&"world_seed") if network != null else 0
	return int(value) if value is int else 0


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
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
		push_error("FAIL: " + description)
		_failures += 1
