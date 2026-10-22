extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_picking_cart_net.gd
##
## The picking cart between two carts and over the wire (expansion D-0610.c: CompanyShed.cart_can_stand,
## CompanyCarts, PickingCartUse, CompanyNet units_take / units_store / cart_push):
## - two carts never overlap: a shed with a second cart 2 m east of the first refuses to push the first
##   into it (blocked, no event, both stay); the floor check takes the cart's own spot as free for itself
##   and as taken for any other cart; once the second rolls away the first goes through, and the two
##   centres never end closer than CompanyTuning.CART_SPACING_M;
## - with a host and a client as ENet peers in one process (each with its CompanyNet and a CompanyShed
##   following it, the client starting from the host's snapshot): the client takes 4 hens and 2 lamps
##   from the shelves and stores them on the cart with its own requests; both peers hold the same units
##   and draw the same cart (spot, product of each slot, where each cube stands) after each step;
## - the client's 7th unit is refused with no_room, only the client hears it, nothing moves anywhere;
## - the host works the cart for the client (PickingCartUse with the client's peer id, as CompanyRoot does
##   when the client uses a cart point): unload into the client's hands and a push, both reach the client;
## - the client's own cart_push rolls the cart one step and both peers draw it there; from 40 m it is
##   refused with out_of_reach, a NaN direction is dropped and an unknown cart is no_station, only the
##   client hears it and the cart stays;
## - every event reaches the client in order (its seqs have no gap or repeat) and the total of units
##   never changes.

const PORT: int = 24681
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const HEN: StringName = &"hen"
const LAMP: StringName = &"antique_lamp"
const CART: StringName = &"cart_1"
const CART_2: StringName = &"cart_2"
const HEN_SHELF: StringName = &"shelf_2_slot0"
const LAMP_SHELF: StringName = &"shelf_1_slot1"

var _failures: int = 0
## Where each peer's player stands (its reach origin), as the host's CompanyNet.player_origin answers.
var _origin: Dictionary = {}
var _host: Peer
var _client: Peer


## One peer: its side of the session, its CompanyNet and CompanyShed, its company and what it heard.
class Peer:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var shed: CompanyShed
	var seqs: Array[int] = []
	var refusals: Array = []
	var restored: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	await _check_two_carts()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: two picking carts never overlap, and a client loads, unloads and pushes one over ENet"
			+ " with the host deciding and both peers drawing the same cart")
	quit(_failures)


# --- Two carts ---


func _check_two_carts() -> void:
	var defaults: DefaultShed = DefaultShed.load_default()
	var spots_before: Array[Vector2] = defaults.cart_spots.duplicate()
	var apart: float = 2.0
	defaults.cart_spots.append(defaults.cart_spots[0] + Vector2(apart / CompanyTuning.WAREHOUSE_GRID_M, 0.0))
	var state := DefaultShed.ScratchState.new()
	defaults.apply_to(state)
	var net := CompanyNet.new()
	net.name = "TwoCartsNet"
	net.company = state
	net.inventory = state.stock()
	root.add_child(net)
	var shed := CompanyShed.new()
	shed.name = "TwoCartsShed"
	root.add_child(shed)
	shed.follow(net)
	shed.rebuild(state, net.inventory)
	net.stations = shed.station_for
	var refusals: Array = []
	net.request_rejected.connect(func(_rid: int, reason: StringName) -> void: refusals.append(reason))
	await process_frame

	var first: PickingCartView = shed.cart_views.get(CART) as PickingCartView
	var second: PickingCartView = shed.cart_views.get(CART_2) as PickingCartView
	_expect(first != null and second != null, "A shed with two cart spots draws cart_1 and cart_2")
	if first == null or second == null:
		defaults.cart_spots = spots_before
		for node: Node in [shed, net]:
			node.free()
		return
	_expect(is_equal_approx(second.position.x - first.position.x, apart),
		"cart_2 stands %.1f m east of cart_1 (%s, %s)" % [apart, first.position, second.position])
	_expect(shed.cart_can_stand(first.position, CART) and not shed.cart_can_stand(first.position, CART_2)
		and not shed.cart_can_stand(first.position),
		"cart_1's spot is free for cart_1 and taken for cart_2 or a new cart")
	var east: Vector3 = second.position + Vector3(CompanyTuning.CART_PUSH_STEP_M, 0.0, 0.0)
	_expect(shed.cart_can_stand(east, CART_2), "The floor east of cart_2 is free (%s)" % east)

	# cart_1 pushed east, into cart_2: refused, nothing moves.
	var seq: int = net.seq
	net.player_origin = func(_peer: int) -> Variant: return first.global_position + Vector3(-1.2, 1.5, 0.0)
	net.request_for(1, CompanyCarts.PUSH, {"cart": CART, "dir": Vector3.RIGHT})
	_expect(refusals == [CompanyCarts.REASON_BLOCKED] and net.seq == seq,
		"Pushing cart_1 into cart_2 is refused with blocked and spends no seq (%s)" % [refusals])
	_expect(net.carts.count() == 0 and second.position.x - first.position.x == apart,
		"Both carts stay where they were")

	# cart_2 rolls away, then cart_1 goes through.
	net.player_origin = func(_peer: int) -> Variant: return second.global_position + Vector3(-1.2, 1.5, 0.0)
	net.request_for(1, CompanyCarts.PUSH, {"cart": CART_2, "dir": Vector3.RIGHT})
	_expect(net.seq == seq + 1 and second.position.is_equal_approx(east), "cart_2 rolls one step east (%s)"
		% second.position)
	net.player_origin = func(_peer: int) -> Variant: return first.global_position + Vector3(-1.2, 1.5, 0.0)
	net.request_for(1, CompanyCarts.PUSH, {"cart": CART, "dir": Vector3.RIGHT})
	var gap: float = Vector2(second.position.x - first.position.x, second.position.z - first.position.z).length()
	_expect(net.seq == seq + 2 and gap >= CompanyTuning.CART_SPACING_M,
		"Then cart_1 rolls east too and keeps %.1f m from cart_2 (gap %.2f)" % [CompanyTuning.CART_SPACING_M, gap])

	defaults.cart_spots = spots_before
	for node: Node in [shed, net]:
		node.free()


# --- Over ENet ---


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 2) == OK
	_expect(up, "The test hosts an ENet session on localhost:%d" % PORT)
	_host.side.multiplayer.multiplayer_peer = server
	# What CompanyRoot does on the host: the company with its default shed, then the world.
	_host.state.call(&"new_company", "Cart SRL")
	DefaultShed.load_default().apply_to(_host.state)
	_add_world(_host)
	_host.net.inventory = _host.state.call(&"stock")
	_host.shed.rebuild(_host.state, _host.net.inventory)
	_host.net.stations = _host.shed.station_for
	_host.net.player_origin = func(peer: int) -> Variant: return _origin.get(peer)
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_client.side.multiplayer.multiplayer_peer = client
	_add_world(_client)
	_client.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return _client.side.multiplayer.get_peers().has(1) and _host.side.multiplayer.get_peers().size() == 1)
	_expect(up and connected, "The client connects to the host")
	if connected:
		await _play()
	client.close()
	server.close()
	await process_frame
	for peer: Peer in [_host, _client]:
		set_multiplayer(null, peer.side.get_path())
		peer.side.free()
		peer.state.free()


func _play() -> void:
	var id: int = _client.side.multiplayer.get_unique_id()
	_host.net.send_snapshot(id)
	var joined: bool = await _wait_for(func() -> bool:
		return not _client.restored.is_empty() and _client.net.seq == _host.net.seq)
	_expect(joined, "The client gets the host's snapshot (restored %s)" % [_client.restored])
	await process_frame
	_expect(_view(_client) != null, "The client's shed draws the cart from the snapshot")
	if _view(_client) == null:
		return
	_same("after the snapshot")
	var units: int = _host.net.inventory.total_units()
	var hands: StringName = CompanyNet.hands_location(id)
	var on_cart: StringName = _view(_host).cart.location()

	# The client fills the cart with its own requests: 4 hens and 2 lamps.
	_expect(await _client_asks(&"units_take", HEN_SHELF, HEN, 4) == &"", "The client takes 4 hens from the shelf")
	_expect(await _client_asks(&"units_store", on_cart, HEN, 4) == &"", "... and stores them on the cart")
	_expect(await _client_asks(&"units_take", LAMP_SHELF, LAMP, 2) == &"", "The client takes 2 lamps")
	_expect(await _client_asks(&"units_store", on_cart, LAMP, 2) == &"", "... and stores them on the cart")
	_expect(_host.net.inventory.count(HEN, on_cart) == 4 and _host.net.inventory.count(LAMP, on_cart) == 2
		and _host.net.inventory.contents_at(hands).is_empty(), "The host's cart holds 4 hens and 2 lamps")
	_expect(_view(_client).slot_products() == [LAMP, LAMP, HEN, HEN, HEN, HEN],
		"The client draws six cubes sorted by product (%s)" % [_view(_client).slot_products()])
	_same("after loading six")

	# The 7th unit: refused, only the client hears it.
	_expect(await _client_asks(&"units_take", HEN_SHELF, HEN, 1) == &"", "The client takes one more hen")
	var seq: int = _host.net.seq
	var host_heard: int = _host.refusals.size()
	_expect(await _client_asks(&"units_store", on_cart, HEN, 1) == CompanyNet.REASON_NO_ROOM,
		"The client's 7th unit is refused with no_room")
	_expect(_host.net.seq == seq and _host.refusals.size() == host_heard
		and _view(_host).cart.count(_host.net.inventory) == 6 and _host.net.inventory.count(HEN, hands) == 1,
		"Only the client heard it and nothing moved")
	_expect(await _client_asks(&"units_store", HEN_SHELF, HEN, 1) == &"", "The client puts the hen back")
	_same("after the refused 7th")

	# The host works the cart for the client, as CompanyRoot does when the client uses a cart point.
	_origin[id] = _view(_host).global_position + Vector3(-1.2, 1.5, 0.0)
	_expect(PickingCartUse.use(_host.net, _view(_host), PickingCartPoint.ACTION_LOAD, id, _origin[id])
		== PickingCartUse.RESULT_UNLOADED and await _synced(), "The host unloads the cart into the client's hands")
	_expect(_client.net.inventory.count(LAMP, hands) == 2 and _view(_client).slot_products() == [HEN, HEN, HEN, HEN],
		"The client holds the two lamps and draws four hens (%s)" % [_view(_client).slot_products()])
	var spot: Vector3 = _view(_host).position
	var step: Vector3 = Vector3(CompanyTuning.CART_PUSH_STEP_M, 0.0, 0.0)
	_expect(PickingCartUse.use(_host.net, _view(_host), PickingCartPoint.ACTION_PUSH, id, _origin[id])
		== PickingCartUse.RESULT_PUSHED and await _synced(), "The host pushes the cart for the client")
	_expect(_view(_client).position.is_equal_approx(spot + step), "The client's cart rolled one step east (%s)"
		% _view(_client).position)
	_same("after the host's push")

	# The client's own push.
	_origin[id] = _view(_host).global_position + Vector3(-1.2, 1.5, 0.0)
	_expect(await _client_asks(CompanyCarts.PUSH, &"", &"", 0, {"cart": CART, "dir": Vector3(1.0, 0.0, 0.0)}) == &"",
		"The client pushes the cart itself")
	_expect(_view(_client).position.is_equal_approx(spot + step * 2.0)
		and (_client.net.carts.position_of(CART) as Vector3).is_equal_approx(spot + step * 2.0),
		"Both peers have the cart two steps east (%s)" % _view(_client).position)
	await create_timer(PickingCartView.SLIDE_SECONDS + 0.15).timeout
	_same("after the client's push")

	# The client's bad pushes: only it hears, the cart stays.
	seq = _host.net.seq
	host_heard = _host.refusals.size()
	_origin[id] = _view(_host).global_position + Vector3(40.0, 1.5, 0.0)
	_expect(await _client_asks(CompanyCarts.PUSH, &"", &"", 0, {"cart": CART, "dir": Vector3.LEFT})
		== CompanyNet.REASON_OUT_OF_REACH, "From 40 m the client's push is refused with out_of_reach")
	_origin[id] = _view(_host).global_position + Vector3(-1.2, 1.5, 0.0)
	_expect(await _client_asks(CompanyCarts.PUSH, &"", &"", 0, {"cart": &"cart_9", "dir": Vector3.RIGHT})
		== CompanyCarts.REASON_NO_STATION, "An unknown cart is no_station")
	_client.net.request(CompanyCarts.PUSH, {"cart": CART, "dir": Vector3(NAN, 0.0, 0.0)})
	for _frame: int in 10:
		await process_frame
	_expect(_host.net.seq == seq and _host.refusals.size() == host_heard
		and _view(_client).position.is_equal_approx(spot + step * 2.0),
		"None of them moved the cart or spent a seq, and the host heard none (%s)" % [_host.refusals])
	_same("after the bad pushes")

	_expect(_host.net.inventory.total_units() == units, "The total of units never changed (%d, was %d)"
		% [_host.net.inventory.total_units(), units])
	var expected: Array[int] = []
	for number: int in range(_client.seqs.front() if not _client.seqs.is_empty() else 1, _host.net.seq + 1):
		expected.append(number)
	_expect(_client.seqs == expected and _client.net.seq == _host.net.seq,
		"The client applied every event after its snapshot in order (%s)" % [_client.seqs])


# --- Helpers ---


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	peer.state = (load(STATE_SCRIPT) as GDScript).new()
	peer.state.name = side_name + "State"
	root.add_child(peer.state)
	peer.state.call(&"reset")
	return peer


## The world of one peer, as CompanyRoot builds it: CompanyNet and the shed following it.
func _add_world(peer: Peer) -> void:
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.side.add_child(peer.net)
	peer.shed = CompanyShed.new()
	peer.shed.name = "Shed"
	peer.side.add_child(peer.shed)
	peer.shed.follow(peer.net)
	peer.net.event_applied.connect(func(seq: int, _kind: StringName, _data: Dictionary) -> void:
		peer.seqs.append(seq))
	peer.net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		peer.refusals.append([rid, reason]))
	peer.net.company_state_restored.connect(func(seq: int) -> void: peer.restored.append(seq))


## The client asks `kind` standing at the station (units: {station, product, qty}; a push: `data`).
## &"" once the host's event reached it, else the refusal it heard; &"lost" when nothing came back.
func _client_asks(kind: StringName, station: StringName, product: StringName, qty: int,
		data: Dictionary = {}) -> StringName:
	var id: int = _client.side.multiplayer.get_unique_id()
	var ask: Dictionary = data
	if ask.is_empty():
		ask = {"station": station, "product": product, "qty": qty}
		var found: Dictionary = _host.shed.station_for(station)
		if found.has("spot"):
			_origin[id] = found["spot"]
	var seq: int = _host.net.seq
	var rid: int = _client.net.request(kind, ask)
	if rid == 0:
		return &"no_request"
	var done: bool = await _wait_for(func() -> bool:
		return _heard(rid) != &"" or (_host.net.seq > seq and _client.net.seq == _host.net.seq))
	if not done:
		return &"lost"
	return _heard(rid)


func _heard(rid: int) -> StringName:
	for entry: Array in _client.refusals:
		if entry[0] == rid:
			return entry[1]
	return &""


func _synced() -> bool:
	return await _wait_for(func() -> bool: return _client.net.seq == _host.net.seq)


func _view(peer: Peer) -> PickingCartView:
	return peer.shed.cart_views.get(CART) as PickingCartView


## What a peer draws of the cart: its spot, the product on each slot and where each cube stands in its frame.
func _cart_look(peer: Peer) -> Array:
	var view: PickingCartView = _view(peer)
	if view == null:
		return []
	var cubes: Array[Vector3] = []
	for unit: MeshInstance3D in view.shown_units():
		cubes.append(unit.position)
	return [view.position, view.slot_products(), cubes]


func _same(when: String) -> void:
	_expect(_cart_look(_client) == _cart_look(_host),
		"The client draws the host's cart %s: %s vs %s" % [when, _cart_look(_client), _cart_look(_host)])
	_expect(_client.net.inventory.to_dict() == _host.net.inventory.to_dict()
		and _client.net.carts.to_dict() == _host.net.carts.to_dict(), "... and holds the same units and spot %s" % when)


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
