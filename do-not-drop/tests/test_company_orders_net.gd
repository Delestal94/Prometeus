extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_orders_net.gd
##
## The day's customer orders over the network (D-0813, scripts/core/company/company_orders_net.gd
## through CompanyNet; contract docs/expansion-distritos/diseno/red-autoridad.md, "Fuera de las 20"):
## - solo (offline): plan_day() draws the day's orders from the seed (OrderGenerator), oldest first: the
##   same seed plans the same orders, another seed others, and the plan never leaves the host; poll()
##   publishes nothing before the first arrival, then one order_added per order that came in, in the
##   plan's order, and one order_expired per order past its due_min (LATE, late_from open), each order
##   once, in small events;
## - the host refuses to publish (false, no seq spent, the book unchanged) an order_added with a
##   malformed order (a key missing or extra, an id that isn't text, empty or too long, a product outside
##   the catalog or a path, qty 0 or a float, an item with another key, a repeated product, four products
##   or none, items that aren't an Array, an unknown or repeated requirement, due at its creation, a float
##   minute, negative pay, a state other than open, a book field) or with extra data, or one already in
##   the book; and an order_expired of an unknown order, before its order is due, with a float minute,
##   with extra data or of an order already late; plan() leaves out an order already in the book;
## - the book travels as the snapshot's "orders" part: a client takes the host's; a part that doesn't fit
##   (not a Dictionary, now_min missing or a float, an extra key, orders not an Array, over MAX_ORDERS,
##   an id twice, a bad book field, an unknown key or state) is refused and changes nothing; an empty
##   book and a delivered order with every book field fit;
## - with a host, a client and a late joiner as ENet peers in one process: the host's polls reach the
##   client in order, with equal books after each; the client can't write the book: publish() and poll()
##   do nothing there, an order_added request is dropped in silence and a forged _apply_event is dropped
##   by the host; a malformed or duplicate order_added, or an order_expired of an unknown order or before
##   its order is due, that reaches the client is not applied, and the client takes the host's snapshot
##   back; a peer that joins late holds what reaches it before its snapshot, gets the host's book from it
##   and follows the next events; the three end with the same book, seq and kinds, every order late.
## Expected in the log: CompanyNet's error for each event the host refuses to publish ("could not apply
## its own"), Godot's for the forged _apply_event ("RPC '_apply_event' is not allowed") and CompanyNet's
## warning for each event the client refuses ("does not fit this peer's state").

const PORT: int = 24681
const SEED: int = 20261022
const PLAYERS: int = 2
const PRODUCTS_DIR: String = "res://data/products/"
const REQUIREMENTS_DIR: String = "res://data/order_requirements/"
## Bytes an order event's data may take (var_to_bytes): one order of up to three products.
const EVENT_BYTES_MAX: int = 1024
const LAST_MINUTE: int = CompanyTuning.MINUTES_PER_DAY - 1

var _failures: int = 0
var _products: Dictionary = {}
var _requirements: Dictionary = {}
var _zones: Array[ZoneDefinition] = []
var _host: Peer
var _client: Peer
var _late: Peer


## One peer: its side of the session, its CompanyNet and what it heard.
class Peer:
	extends RefCounted
	var side: Node
	var net: CompanyNet
	var seqs: Array[int] = []
	var kinds: Array[StringName] = []
	var refusals: Array = []
	var restored: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_load_catalogs()
	var solo: CompanyNet = _check_solo()
	_check_snapshot_part(solo)
	solo.free()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: the host plans and publishes the day's orders, every peer applies them in order,"
			+ " bad or duplicate events are refused, the client can't write the book, late joiners get it")
	quit(_failures)


func _load_catalogs() -> void:
	for file: String in CompanyCatalog.tres_files(PRODUCTS_DIR):
		var def := load(PRODUCTS_DIR + file) as ProductDefinition
		if def != null:
			_products[def.id] = def
	for file: String in CompanyCatalog.tres_files(REQUIREMENTS_DIR):
		var req := load(REQUIREMENTS_DIR + file) as OrderRequirement
		if req != null:
			_requirements[req.id] = req
	for zone: ZoneDefinition in CompanyCatalog.load_all().zones():
		if zone.is_open_at_start():
			_zones.append(zone)
	_expect(_products.size() >= 4 and _requirements.size() == 6 and not _zones.is_empty(),
		"The catalogs load (%d products, %d requirements, %d zones open)"
		% [_products.size(), _requirements.size(), _zones.size()])


# --- Solo ---


func _check_solo() -> CompanyNet:
	var net := CompanyNet.new()
	net.name = "SoloNet"
	root.add_child(net)
	var events: Array = []
	net.event_applied.connect(func(seq: int, kind: StringName, data: Dictionary) -> void:
		events.append([seq, kind, data]))
	var count: int = net.orders.plan_day(SEED, 1, PLAYERS, _zones, _products, _requirements)
	var plan: Array[Dictionary] = net.orders.planned()
	_expect(count == OrderRhythm.orders_for_day(PLAYERS) and plan.size() == count,
		"The host plans the day's %d orders (planned %d)" % [OrderRhythm.orders_for_day(PLAYERS), plan.size()])
	if plan.size() < 6:
		return net
	var twin := CompanyOrdersNet.new()
	twin.plan_day(SEED, 1, PLAYERS, _zones, _products, _requirements)
	_expect(twin.planned() == plan, "The same seed plans the same orders")
	twin.plan_day(SEED + 1, 1, PLAYERS, _zones, _products, _requirements)
	_expect(twin.planned() != plan, "Another seed plans other orders")
	_expect(_arrival_sorted(plan), "The plan goes oldest first")

	var book: OrderBook = net.orders.book
	var first: int = int(plan[0]["created_min"])
	_expect(net.orders.poll(net, first - 1) == 0 and net.seq == 0 and book.size() == 0,
		"Nothing comes in before the first arrival (seq %d, %d orders)" % [net.seq, book.size()])
	var at_first: int = _arrived(plan, first)
	_expect(net.orders.poll(net, first) == at_first and net.seq == at_first and book.size() == at_first,
		"At the first arrival %d order(s) come in (seq %d, book %d)" % [at_first, net.seq, book.size()])
	_expect(not events.is_empty() and events[0][1] == CompanyOrdersNet.ADDED
		and events[0][2].get("order", {}).get("id") == plan[0]["id"]
		and book.state_of(plan[0]["id"]) == Order.STATE_OPEN,
		"...the first one as an open order_added (%s)" % [events.slice(0, 1)])

	var last: int = int(plan[plan.size() - 1]["created_min"])
	var due_by_last: int = _due_before(plan, last)
	var sent: int = net.orders.poll(net, last)
	_expect(book.size() == count and net.orders.planned().is_empty(),
		"By the last arrival every planned order is in the book (%d of %d)" % [book.size(), count])
	_expect(sent == count - at_first + due_by_last,
		"...with one order_added each and one order_expired per order already past due (%d events, %d due)"
		% [sent, due_by_last])
	_expect(_ids_of(events, CompanyOrdersNet.ADDED) == _plan_ids(plan),
		"The order_added events follow the plan's order")
	var more: int = net.orders.poll(net, LAST_MINUTE)
	var expired: Array = _ids_of(events, CompanyOrdersNet.EXPIRED)
	var all_late: bool = true
	for order: Dictionary in plan:
		var stored: Dictionary = book.get_order(order["id"])
		all_late = all_late and stored.get("state") == Order.STATE_LATE and stored.get("late_from") == Order.STATE_OPEN
	_expect(more == count - due_by_last and expired.size() == count and all_late,
		"At the end of the day every order expired once, LATE from open (%d events, %d expired)"
		% [more, expired.size()])
	_expect(net.orders.poll(net, LAST_MINUTE) == 0, "A second poll at the same minute sends nothing")
	for event: Array in events:
		var size: int = var_to_bytes(event[2]).size()
		_expect(size <= EVENT_BYTES_MAX, "An order event is small (%d bytes: %s)" % [size, event[2]])
	_expect(net.orders.poll(null, LAST_MINUTE) == 0 and twin.poll(net, LAST_MINUTE) == 0,
		"poll() through no CompanyNet, or one whose orders are another's, sends nothing")
	twin = null
	_check_host_refusals(net, plan)
	return net


## The host's own events that don't fit are not published: no seq, the book as it was.
func _check_host_refusals(net: CompanyNet, plan: Array[Dictionary]) -> void:
	var fresh: Dictionary = _fresh_order(&"d1_extra", 600)
	var hen: Dictionary = {"product": &"hen", "qty": 1}
	var four: Array = []
	for product: StringName in _products.keys().slice(0, 4):
		four.append({"product": product, "qty": 1})
	var bad_orders: Array = [
		[_without(fresh, "pay"), "no pay"],
		[_with(fresh, "tip", 3), "an extra key"],
		[_with(fresh, "id", 7), "an id that isn't text"],
		[_with(fresh, "id", ""), "an empty id"],
		[_with(fresh, "id", "x".repeat(CompanyOrdersNet.MAX_TEXT + 1)), "an id over MAX_TEXT"],
		[_with(fresh, "items", [{"product": &"unicorn", "qty": 1}]), "a product outside the catalog"],
		[_with(fresh, "items", [{"product": "../products/hen", "qty": 1}]), "a path for a product"],
		[_with(fresh, "items", [{"product": &"hen", "qty": 0}]), "qty 0"],
		[_with(fresh, "items", [{"product": &"hen", "qty": 1.0}]), "a float qty"],
		[_with(fresh, "items", [{"product": &"hen", "qty": 1, "gift": true}]), "an item with another key"],
		[_with(fresh, "items", [hen, hen]), "a repeated product"],
		[_with(fresh, "items", four), "four products"],
		[_with(fresh, "items", []), "no product"],
		[_with(fresh, "items", "hen"), "items that aren't an Array"],
		[_with(fresh, "requirements", [&"teleport"]), "an unknown requirement"],
		[_with(fresh, "requirements", [&"cold", &"cold"]), "a repeated requirement"],
		[_with(fresh, "due_min", fresh["created_min"]), "due at its creation"],
		[_with(fresh, "created_min", 600.0), "a float minute"],
		[_with(fresh, "pay", -1), "negative pay"],
		[_with(fresh, "state", Order.STATE_LATE), "a state other than open"],
		[_with(fresh, "box_id", &"box_1"), "a book field"],
		["d1_extra", "an order that isn't a Dictionary"],
	]
	var book: OrderBook = net.orders.book
	var before: Dictionary = book.to_dict()
	var seq: int = net.seq
	for case: Array in bad_orders:
		_expect(not net.publish(CompanyOrdersNet.ADDED, {"order": case[0]}) and net.seq == seq
			and book.to_dict() == before,
			"The host doesn't publish an order_added with %s (seq %d)" % [case[1], net.seq])
	_expect(not net.publish(CompanyOrdersNet.ADDED, {"order": fresh, "rid": 1}) and net.seq == seq,
		"...nor one with extra data")
	_expect(not net.publish(CompanyOrdersNet.ADDED, {"order": plan[0]}) and net.seq == seq
		and book.to_dict() == before,
		"...nor one of an order already in the book")
	_expect(net.publish(CompanyOrdersNet.ADDED, {"order": fresh}) and net.seq == seq + 1
		and book.state_of(&"d1_extra") == Order.STATE_OPEN,
		"The same order as it should be goes through (seq %d)" % net.seq)
	before = book.to_dict()
	seq = net.seq
	var due: int = int(fresh["due_min"])
	var bad_expiries: Array = [
		[{"order": &"nobody", "minute": LAST_MINUTE}, "of an unknown order"],
		[{"order": &"d1_extra", "minute": due}, "before its order is due"],
		[{"order": &"d1_extra", "minute": float(due + 1)}, "with a float minute"],
		[{"order": &"d1_extra", "minute": due + 1, "rid": 1}, "with extra data"],
		[{"order": plan[0]["id"], "minute": LAST_MINUTE}, "of an order already late"],
		[{"order": 7, "minute": LAST_MINUTE}, "with an id that isn't text"],
	]
	for case: Array in bad_expiries:
		_expect(not net.publish(CompanyOrdersNet.EXPIRED, case[0]) and net.seq == seq and book.to_dict() == before,
			"The host doesn't publish an order_expired %s" % case[1])
	_expect(net.publish(CompanyOrdersNet.EXPIRED, {"order": &"d1_extra", "minute": due + 1})
		and book.state_of(&"d1_extra") == Order.STATE_LATE,
		"An order_expired one minute after the order is due goes through")
	_expect(net.orders.plan([plan[0], _fresh_order(&"d1_later", 700)]) == 1
		and net.orders.planned()[0]["id"] == &"d1_later",
		"plan() leaves out an order already in the book (planned %s)" % [_plan_ids(net.orders.planned())])
	net.orders.plan([])


## The book as the snapshot's "orders" part, checked on the way in.
func _check_snapshot_part(host: CompanyNet) -> void:
	var data: Dictionary = host.snapshot()
	var part: Variant = data.get(CompanyOrdersNet.SNAPSHOT_KEY)
	_expect(part is Dictionary and part == host.orders.book.to_dict() and host.orders.book.size() > 0,
		"The snapshot carries the host's book under %s" % CompanyOrdersNet.SNAPSHOT_KEY)
	var client := CompanyNet.new()
	_expect(client.apply_snapshot(data) and client.orders.book.to_dict() == host.orders.book.to_dict(),
		"A client takes the host's book from the snapshot")
	if not part is Dictionary or (part["orders"] as Array).is_empty():
		client.free()
		return
	var good: Dictionary = part
	var one: Dictionary = good["orders"][0]
	var many: Array = []
	for i: int in range(CompanyOrdersNet.MAX_ORDERS + 1):
		many.append(_with(one, "id", StringName("o_%d" % i)))
	var bad_parts: Array = [
		[7, "not a Dictionary"],
		[_without(good, "now_min"), "no now_min"],
		[_with(good, "now_min", 3.0), "a float now_min"],
		[_with(good, "seq", 1), "an extra key"],
		[_with(good, "orders", {}), "orders that aren't an Array"],
		[_with(good, "orders", many), "more than MAX_ORDERS orders"],
		[_with(good, "orders", [one, one]), "an id twice"],
		[_with(good, "orders", [_with(one, "quality", 101)]), "quality over 100"],
		[_with(good, "orders", [_with(one, "intact", "yes")]), "intact that isn't a bool"],
		[_with(good, "orders", [_with(one, "late_from", &"lost")]), "an unknown late_from"],
		[_with(good, "orders", [_with(one, "box_id", 3)]), "a box_id that isn't text"],
		[_with(good, "orders", [_with(one, "paid", -5)]), "a negative paid"],
		[_with(good, "orders", [_with(one, "rating", 5)]), "an unknown key"],
		[_with(good, "orders", [_with(one, "state", &"teleported")]), "an unknown state"],
	]
	var before: Dictionary = client.orders.book.to_dict()
	for case: Array in bad_parts:
		_expect(not client.orders.put_snapshot(case[0]) and client.orders.book.to_dict() == before,
			"A snapshot part with %s is refused and changes nothing" % case[1])
	var delivered: Dictionary = one.duplicate(true)
	delivered.merge({"state": Order.STATE_DELIVERED, "box_id": &"box_3", "trip_id": &"trip_1",
		"quality": 80, "paid": 30, "intact": true}, true)
	_expect(client.orders.put_snapshot({"orders": [delivered], "now_min": 900})
		and client.orders.book.state_of(one["id"]) == Order.STATE_DELIVERED
		and client.orders.book.box_of(one["id"]) == &"box_3",
		"A delivered order with every book field fits")
	_expect(client.orders.put_snapshot({"orders": [], "now_min": 0}) and client.orders.book.size() == 0,
		"An empty book fits (a day with no order yet)")
	client.free()


# --- Network ---


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	_late = _make_peer("LateSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var late := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 3) == OK
	_host.side.multiplayer.multiplayer_peer = server
	_add_net(_host)
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_client.side.multiplayer.multiplayer_peer = client
	_add_net(_client)
	_client.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return _client.side.multiplayer.get_peers().has(1) and _host.side.multiplayer.get_peers().size() == 1)
	_expect(up and connected, "The client connects to the host on localhost:%d" % PORT)
	if connected:
		await _play(late)
	client.close()
	late.close()
	server.close()
	await process_frame
	for peer: Peer in [_host, _client, _late]:
		set_multiplayer(null, peer.side.get_path())
		peer.side.free()


func _play(late: ENetMultiplayerPeer) -> void:
	_expect(await _join(_client), "The client gets the host's snapshot (restored %s)" % [_client.restored])
	_host.net.orders.plan_day(SEED, 1, PLAYERS, _zones, _products, _requirements)
	var plan: Array[Dictionary] = _host.net.orders.planned()
	_expect(plan.size() >= 8 and _client.net.orders.planned().is_empty(),
		"The host plans %d orders and the plan stays on the host" % plan.size())
	if plan.size() < 8:
		return
	for index: int in [2, 5]:
		var minute: int = int(plan[index]["created_min"])
		var sent: int = _host.net.orders.poll(_host.net, minute)
		_expect(sent > 0 and await _synced([_client]),
			"The host's poll at minute %d (%d events) reaches the client (seq %d, host %d)"
			% [minute, sent, _client.net.seq, _host.net.seq])
		_expect_books([_client], "after the poll at minute %d" % minute)
	await _check_client_cannot_write()
	await _check_bad_events(plan)
	await _check_late_join(late)
	var rest: int = _host.net.orders.poll(_host.net, LAST_MINUTE)
	_expect(rest > 0 and await _synced([_client, _late]),
		"The end of the day (%d events) reaches both followers" % rest)
	_expect_books([_client, _late], "at the end of the day")
	var late_orders: int = 0
	for order: Dictionary in _late.net.orders.book.to_dict()["orders"]:
		late_orders += 1 if order.get("state") == Order.STATE_LATE else 0
	_expect(late_orders == plan.size() and _late.net.orders.book.size() == plan.size(),
		"Every order of the day is in every book, late (%d of %d)" % [late_orders, plan.size()])
	_check_seqs()


## The client has no way to write the book: nothing it does reaches the host's.
func _check_client_cannot_write() -> void:
	var seq: int = _host.net.seq
	var books: Array = [_host.net.orders.book.to_dict(), _client.net.orders.book.to_dict()]
	var order: Dictionary = _fresh_order(&"d1_client", 700)
	_expect(not _client.net.publish(CompanyOrdersNet.ADDED, {"order": order}),
		"publish() of an order_added is refused on a client")
	_expect(_client.net.orders.plan([order]) == 1 and _client.net.orders.poll(_client.net, LAST_MINUTE) == 0,
		"...and poll() sends nothing from a client, whatever it planned")
	_client.net.orders.plan([])
	var heard: int = _client.refusals.size()
	_client.net.request(CompanyOrdersNet.ADDED, {"id": &"d1_client"})
	_client.net.request(CompanyOrdersNet.EXPIRED, {"order": &"d1_o01", "minute": LAST_MINUTE})
	# Godot drops it (authority-only RPC) and logs an error: expected.
	_client.net._apply_event.rpc_id(1, seq + 1, CompanyOrdersNet.ADDED, {"order": order})
	var sentinel: int = _client.net.request(&"units_take", {"station": &"nowhere", "product": &"hen", "qty": 1})
	var answered: bool = await _wait_for(func() -> bool: return _reason(_client, sentinel) != &"")
	_expect(answered and _client.refusals.size() == heard + 1,
		"An order_added or order_expired request is dropped in silence (heard %s)" % [_client.refusals.slice(heard)])
	_expect(_host.net.seq == seq and _host.net.orders.book.to_dict() == books[0]
		and _client.net.orders.book.to_dict() == books[1],
		"...and neither it nor a forged _apply_event changed a book or spent a seq (seq %d)" % _host.net.seq)


## Events from the host that don't fit the client's book: not applied there, and the host's snapshot
## puts the client back in step.
func _check_bad_events(plan: Array[Dictionary]) -> void:
	var open_id: StringName = &""
	for order: Dictionary in _host.net.orders.book.to_dict()["orders"]:
		if order.get("state") == Order.STATE_OPEN:
			open_id = order["id"]
	_expect(open_id != &"", "An order of the host's book is still open (%s)" % open_id)
	var created: int = int(_host.net.orders.book.get_order(open_id).get("created_min", 0))
	var cases: Array = [
		[CompanyOrdersNet.ADDED, {"order": _with(_fresh_order(&"d1_bad", 700), "items",
			[{"product": &"unicorn", "qty": 1}])}, "a malformed order_added"],
		[CompanyOrdersNet.ADDED, {"order": plan[0]}, "an order_added of an order already in the book"],
		[CompanyOrdersNet.EXPIRED, {"order": &"nobody", "minute": 900}, "an order_expired of an unknown order"],
		[CompanyOrdersNet.EXPIRED, {"order": open_id, "minute": created}, "an order_expired before its order is due"],
	]
	var id: int = _client.side.multiplayer.get_unique_id()
	for case: Array in cases:
		var before: Dictionary = _client.net.orders.book.to_dict()
		var restores: int = _client.restored.size()
		# A broken host: the event goes out numbered, though the host's own book never took it.
		_host.net.seq += 1
		_host.net._apply_event.rpc_id(id, _host.net.seq, case[0], case[1])
		# Its own request may already have brought a snapshot back: either shows it refused the event.
		var waiting: bool = await _wait_for(func() -> bool:
			return _client.net.awaiting_snapshot() or _client.restored.size() > restores)
		_expect(waiting and _client.net.orders.book.to_dict() == before,
			"%s that reaches the client is not applied: it waits for a snapshot" % case[2])
		_host.net.send_snapshot(id)
		var back: bool = await _wait_for(func() -> bool:
			return (not _client.net.awaiting_snapshot() and _client.net.seq == _host.net.seq
				and _client.restored.size() > restores))
		_expect(back, "...and the host's snapshot puts it back at seq %d (client %d)"
			% [_host.net.seq, _client.net.seq])
		_expect_books([_client], "after %s" % case[2])


## A third peer joins: the event that reaches it before its snapshot is held, the snapshot brings the book.
func _check_late_join(late: ENetMultiplayerPeer) -> void:
	var up: bool = late.create_client("127.0.0.1", PORT) == OK
	_late.side.multiplayer.multiplayer_peer = late
	_add_net(_late)
	_late.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return _late.side.multiplayer.get_peers().has(1) and _host.side.multiplayer.get_peers().size() == 2)
	_expect(up and connected, "A third peer connects late")
	if not connected:
		return
	var next: Array[Dictionary] = _host.net.orders.planned()
	var minute: int = int(next[0]["created_min"]) if not next.is_empty() else LAST_MINUTE
	var sent: int = _host.net.orders.poll(_host.net, minute)
	var held: bool = await _wait_for(func() -> bool: return sent > 0 and _late.net._held.size() == sent)
	_expect(held and _late.net.seq == 0 and _late.net.orders.book.size() == 0,
		"The late peer holds the %d event(s) that reach it before its snapshot, with no order yet" % sent)
	_expect(await _synced([_client]), "...while the client follows them")
	_expect(await _join(_late) and _late.restored == [_host.net.seq] and _late.seqs.is_empty(),
		"...then the snapshot brings it to the host's seq %d without applying them (restored %s)"
		% [_host.net.seq, _late.restored])
	_expect_books([_client, _late], "after the late peer's snapshot")


## Every follower applied the host's events once, in its order, from its first snapshot on.
func _check_seqs() -> void:
	_expect(_client.seqs == _host.seqs and _client.kinds == _host.kinds,
		"The client applied the host's %d events in order, none of the refused ones" % _host.seqs.size())
	var from: int = _late.restored[0] if not _late.restored.is_empty() else 0
	var after: Array[int] = []
	for seq: int in _host.seqs:
		if seq > from:
			after.append(seq)
	_expect(_late.seqs == after, "The late peer applied the host's events after its snapshot (%s)" % [_late.seqs])
	var counts: Dictionary = {}
	for kind: StringName in _host.kinds:
		counts[kind] = int(counts.get(kind, 0)) + 1
	_expect(counts.keys().size() == 2 and counts.has(CompanyOrdersNet.ADDED) and counts.has(CompanyOrdersNet.EXPIRED),
		"The host published only order events here (%s)" % [counts])


# --- Helpers ---


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	return peer


func _add_net(peer: Peer) -> void:
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.side.add_child(peer.net)
	peer.net.event_applied.connect(func(seq: int, kind: StringName, _data: Dictionary) -> void:
		peer.seqs.append(seq)
		peer.kinds.append(kind))
	peer.net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		peer.refusals.append([rid, reason]))
	peer.net.company_state_restored.connect(func(seq: int) -> void: peer.restored.append(seq))


## The host sends `peer` its snapshot as when that peer's world comes up
## (NetworkManager.peer_level_ready); true once it is in.
func _join(peer: Peer) -> bool:
	var id: int = peer.side.multiplayer.get_unique_id()
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"peer_level_ready"):
		network.emit_signal(&"peer_level_ready", id)
	else:
		_host.net.send_snapshot(id)
	return await _wait_for(func() -> bool: return not peer.restored.is_empty() and peer.net.seq == _host.net.seq)


func _synced(followers: Array) -> bool:
	return await _wait_for(_all_at_host_seq.bind(followers))


func _all_at_host_seq(followers: Array) -> bool:
	for peer: Peer in followers:
		if peer.net.seq != _host.net.seq:
			return false
	return true


func _expect_books(followers: Array, when: String) -> void:
	for peer: Peer in followers:
		_expect(peer.net.orders.book.to_dict() == _host.net.orders.book.to_dict(),
			"%s has the host's book %s (%d orders, host %d)"
			% [peer.side.name, when, peer.net.orders.book.size(), _host.net.orders.book.size()])


func _fresh_order(id: StringName, created: int) -> Dictionary:
	var items: Array = [{"product": &"hen", "qty": 1}]
	return Order.normalize(Order.make(id, "Ana", _zones[0].id, &"centro_house_1", items, created, _products))


static func _arrival_sorted(plan: Array[Dictionary]) -> bool:
	for index: int in range(1, plan.size()):
		if int(plan[index - 1]["created_min"]) > int(plan[index]["created_min"]):
			return false
	return true


static func _arrived(plan: Array[Dictionary], minute: int) -> int:
	return plan.filter(func(order: Dictionary) -> bool: return int(order["created_min"]) <= minute).size()


static func _due_before(plan: Array[Dictionary], minute: int) -> int:
	return plan.filter(func(order: Dictionary) -> bool: return int(order["due_min"]) < minute).size()


static func _plan_ids(plan: Array[Dictionary]) -> Array:
	return plan.map(func(order: Dictionary) -> StringName: return order["id"])


static func _ids_of(events: Array, kind: StringName) -> Array:
	var ids: Array = []
	for event: Array in events:
		if event[1] == kind:
			var order: Variant = event[2].get("order")
			ids.append(order["id"] if order is Dictionary else order)
	return ids


static func _reason(peer: Peer, rid: int) -> StringName:
	for entry: Array in peer.refusals:
		if int(entry[0]) == rid:
			return entry[1]
	return &""


static func _with(data: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy[key] = value
	return copy


static func _without(data: Dictionary, key: String) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy.erase(key)
	return copy


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
