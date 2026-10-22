extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_orders_world.gd
##
## The company world plays the day's orders (D-0813.1: company_root.gd, company_day_orders.gd, over
## CompanyNet.orders of D-0813; day_cycle.gd and order_book.gd for the pruning):
## - CompanyDayOrders.open_zones() keeps the zones no gate closes and one whose every gate the company
##   opened, not the rest; OrderBook.prune_closed() drops the delivered, failed and cancelled orders and
##   keeps the open, packed, out and late ones in their order;
## - solo, a world (CompanyRoot's business side) has an "orders" step on its business tick after
##   "day_cycle" and plans its day at the OPENING from the company's day seed
##   (CompanyState.day_seed(CompanySeed.ORDERS)): the plan is OrderGenerator's for that seed; a second
##   OPENING event of the same day (a freeze toggle) plans nothing again; the world loaded again from the
##   interrupted day it saved plans the very same orders, a company with another seed others; with the
##   clock at the last arrival the orders step brings the whole plan into the shared book and the
##   EventBus autoload tells order_added once per order, in order; in CLOSING and SUMMARY the step
##   brings nothing in;
## - a host and a client world as ENet peers in one process, the host's day fast-forwarded an hour at a
##   time on the test's own ticks: after every hour the client has the host's book, and at 19:50 the
##   whole plan is in both books, the orders past due late; each world tells its own EventBus (a stand-in
##   per peer) order_added once per order, in the host's order, and nothing for an expiry or for a
##   snapshot sent again;
## - the next day's OPENING drops the closed orders on both peers alike (three closed by hand on both
##   books, as the events of D-0815.b and D-0302 will) and keeps every other order of the day before; the
##   new day's orders come in on top, the same on both, each told once on each peer.

const PORT: int = 24683
const DIR: String = "user://test_company_orders_world"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const SEED: int = 813001
## Test ticks per game hour at the clock's own pace (GameClock.DEFAULT_SPEED: 90 real seconds).
const HOUR_MSEC: int = roundi(CompanyTuning.SECONDS_PER_GAME_HOUR * 1000.0)
const WAIT_SECONDS: float = 5.0

var _failures: int = 0
## The test's own ticks for the host's clock and day (_ticks()): real time stopped at _base_msec and
## moved on by hand.
var _base_msec: int = 0
var _skip_msec: int = 0


## A stand-in EventBus for one peer: the signals CompanyRoot touches, and the orders it was told.
class PeerBus extends Node:
	signal order_added(order_id: StringName)
	signal company_day_summary(day: int, summary: Dictionary)
	signal company_day_started(day: int)

	var added: Array[StringName] = []

	func _init() -> void:
		order_added.connect(func(id: StringName) -> void: added.append(id))


## CompanyRoot's business side only (as test_company_host_leaves' LiveDayRoot): CompanyNet, the clock,
## the day and, on the host, the business tick, with the day opened; `bus` stands in for EventBus when set.
class OrdersRoot extends CompanyRoot:
	var bus: Node = null

	func _ready() -> void:
		_start_company(company_state)
		_open_company_day.call_deferred()

	func _event_bus() -> Node:
		return bus if bus != null else super()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	RpcGuard.reset()
	_check_open_zones()
	_check_prune()
	await _check_solo()
	await _check_network()
	RpcGuard.reset()
	_clean()
	if _failures == 0:
		print("PASS: the company world plans the day's orders from its seed, brings them in on the business tick"
			+ " into every peer's book, tells each once on every peer and drops the closed ones at the next day")
	quit(_failures)


func _check_open_zones() -> void:
	var zones: Array[ZoneDefinition] = CompanyCatalog.load_all().zones()
	var state: Node = _new_state()
	state.call(&"new_company", "Zones SRL", SEED)
	var ids: Array = CompanyDayOrders.open_zones(zones, state).map(func(z: ZoneDefinition) -> StringName: return z.id)
	_expect(ids == [&"centro", &"parque_industrial"], "A new company's zones are the ungated ones (got %s)" % [ids])
	var campo: ZoneDefinition = CompanyCatalog.load_all().zone(&"campo")
	# Straight into the list: open_gate() tells EventBus, which a state out of the tree can't reach.
	(state.get(&"opened_gates") as Array).append_array(campo.gates)
	ids = CompanyDayOrders.open_zones(zones, state).map(func(z: ZoneDefinition) -> StringName: return z.id)
	_expect(ids == [&"campo", &"centro", &"parque_industrial"],
		"...and campo joins once its gates are open, the rest still out (got %s)" % [ids])
	state.free()


func _check_prune() -> void:
	var book := OrderBook.new()
	var states: Array[StringName] = [&"open", &"delivered", &"packed", &"failed", &"out", &"cancelled", &"late"]
	for index: int in range(states.size()):
		book.add(_fresh_order(StringName("p%d" % index), 500 + index))
	book.mark_packed(&"p1", &"b1")
	book.mark_out(&"p1", &"t1")
	book.mark_delivered(&"p1", 100, true)
	book.mark_packed(&"p2", &"b2")
	book.mark_failed(&"p3")
	book.mark_packed(&"p4", &"b4")
	book.mark_out(&"p4", &"t4")
	book.cancel(&"p5")
	book.expire_one(&"p6", 1000)
	var seen: Array = []
	for index: int in range(states.size()):
		seen.append(book.state_of(StringName("p%d" % index)))
	_expect(seen == states, "The book holds one order in each state (%s)" % [seen])
	var gone: Array[StringName] = book.prune_closed()
	var kept: Array = (book.to_dict()["orders"] as Array).map(func(o: Dictionary) -> StringName: return o["id"])
	_expect(gone == [&"p1", &"p3", &"p5"] and kept == [&"p0", &"p2", &"p4", &"p6"],
		"prune_closed() drops the delivered, failed and cancelled orders and keeps the rest in order (gone %s, kept %s)"
		% [gone, kept])
	_expect(book.prune_closed().is_empty() and book.size() == 4, "...and a second prune drops nothing")
	book.free()


# --- Solo ---


func _check_solo() -> void:
	var state_a: Node = _new_state()
	state_a.call(&"new_company", "Orders SRL", SEED)
	var a: OrdersRoot = await _solo_root(state_a)
	var steps: Array[StringName] = a.business_tick.tick.step_names()
	_expect(steps == [&"day_cycle", &"orders"], "The business tick polls the orders after the day (got %s)" % [steps])
	var plan_a: Array[Dictionary] = a.net.orders.planned()
	var twin := CompanyOrdersNet.new()
	twin.plan_day(int(state_a.call(&"day_seed", CompanySeed.ORDERS, 1)), 1, 1,
		CompanyDayOrders.open_zones(CompanyCatalog.load_all().zones(), state_a), _products(),
		CompanyDayOrders.requirements(), state_a)
	_expect(a.day_cycle.phase() == DayCycle.Phase.OPENING and plan_a.size() == OrderRhythm.orders_for_day(1)
		and plan_a == twin.planned(),
		"Solo, the OPENING plans the day's %d orders from the company's day seed (planned %d)"
		% [OrderRhythm.orders_for_day(1), plan_a.size()])
	a.net.orders.plan([])
	var toggle: Dictionary = {"day": 1, "phase": "OPENING", "frozen": true, "lag": 0.0, "frozen_at": 480.0}
	_expect(a.net.publish(CompanyNet.DAY_PHASE, toggle) and a.net.orders.planned().is_empty(),
		"A second OPENING event of the same day (the shed freezing) plans nothing again")
	a.net.orders.plan(plan_a)
	a.queue_free()
	await process_frame
	_expect(CompanySave.was_interrupted(CompanySave.DEFAULT_SLOT, DIR), "Leaving the world saved day 1 as interrupted")

	var state_b: Node = _new_state()
	var b: OrdersRoot = await _solo_root(state_b)
	_expect(int(state_b.get(&"company_seed")) == SEED and b.net.orders.planned() == plan_a,
		"The interrupted day loaded again plans the very same orders (seed %s)" % state_b.get(&"company_seed"))
	var bus: Node = root.get_node(^"/root/EventBus")
	var told: Array[StringName] = []
	var listen: Callable = func(id: StringName) -> void: told.append(id)
	bus.connect(&"order_added", listen)
	b.clock.start(float(CompanyTuning.ORDER_LAST_ARRIVAL_MIN))
	b.call(&"_poll_orders")
	bus.disconnect(&"order_added", listen)
	var ids: Array = plan_a.map(func(o: Dictionary) -> StringName: return o["id"])
	_expect(b.net.orders.planned().is_empty() and b.net.orders.book.size() == plan_a.size(),
		"With the clock at the last arrival the orders step brings the whole plan in (%d in the book)"
		% b.net.orders.book.size())
	_expect(told == ids, "...and EventBus tells order_added once per order, in order (got %s)" % [told])
	b.net.orders.plan([_fresh_order(&"late_comer", 600)])
	for next: DayCycle.Phase in [DayCycle.Phase.OPERATING, DayCycle.Phase.CLOSING, DayCycle.Phase.SUMMARY]:
		b.day_cycle.call(&"_transition", next)
		if next != DayCycle.Phase.OPERATING:
			b.call(&"_poll_orders")
			_expect(b.net.orders.planned().size() == 1 and not b.net.orders.book.has(&"late_comer"),
				"In %s the orders step brings nothing in" % b.day_cycle.phase_name())
	b.queue_free()
	await process_frame

	var state_c: Node = _new_state()
	state_c.call(&"new_company", "Orders SRL", SEED + 1)
	var c: OrdersRoot = await _solo_root(state_c)
	_expect(c.net.orders.planned() != plan_a and not c.net.orders.planned().is_empty(),
		"A company with another seed plans other orders")
	c.queue_free()
	await process_frame
	for state: Node in [state_a, state_b, state_c]:
		state.free()


## A solo world on `state`, saving in DIR, its business tick stopped (the test runs the orders step
## itself), once its day is open.
func _solo_root(state: Node) -> OrdersRoot:
	var level := OrdersRoot.new()
	level.name = "SoloRoot"
	level.company_state = state
	level.save_dir = DIR
	level.dev_args = PackedStringArray()
	root.add_child(level)
	level.business_tick.set_process(false)
	await process_frame
	await process_frame
	return level


# --- Network ---


func _check_network() -> void:
	var host_side := _side("HostSide")
	var client_side := _side("ClientSide")
	var server := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 2) == OK
	host_side.multiplayer.multiplayer_peer = server
	var host_state: Node = _new_state()
	host_state.call(&"new_company", "Host SRL", SEED)
	var host_bus := PeerBus.new()
	var host := _peer_root(host_state, host_bus)
	host_side.add_child(host)
	_base_msec = Time.get_ticks_msec()
	host.clock.ticks = _ticks
	host.day_cycle.ticks = _ticks
	host.business_tick.set_process(false)
	var client := ENetMultiplayerPeer.new()
	up = up and client.create_client("127.0.0.1", PORT) == OK
	client_side.multiplayer.multiplayer_peer = client
	var client_state: Node = _new_state()
	var client_bus := PeerBus.new()
	var guest := _peer_root(client_state, client_bus)
	client_side.add_child(guest)
	var connected: bool = await _wait_for(func() -> bool:
		return client_side.multiplayer.get_peers().has(1) and host_side.multiplayer.get_peers().size() == 1)
	_expect(up and connected, "The client connects to the host on localhost:%d" % PORT)
	if connected:
		var client_id: int = client_side.multiplayer.get_unique_id()
		host.net.send_snapshot(client_id)
		_expect(await _synced(host, guest) and host.day_cycle.phase() == DayCycle.Phase.OPENING,
			"The client takes the host's snapshot of the opened day")
		host.business_tick.set_process(true)
		await _play_day_one(host, guest, host_bus, client_bus, client_id)
		await _play_day_two(host, guest, host_bus, client_bus)
	guest.queue_free()
	host.queue_free()
	await process_frame
	client.close()
	server.close()
	await process_frame
	for side: Node in [host_side, client_side]:
		set_multiplayer(null, side.get_path())
		side.free()
	for node: Node in [host_state, client_state, host_bus, client_bus]:
		node.free()


func _play_day_one(host: OrdersRoot, guest: OrdersRoot, host_bus: PeerBus, client_bus: PeerBus,
		client_id: int) -> void:
	var plan: Array[Dictionary] = host.net.orders.planned()
	_expect(plan.size() == OrderRhythm.orders_for_day(1) and guest.net.orders.planned().is_empty(),
		"The host plans %d orders and the plan stays on the host" % plan.size())
	for hour: int in range(9, 20):
		var now: int = await _advance(host, guest, HOUR_MSEC)
		_expect_books(host, guest, "at %02d:%02d" % [now / 60, now % 60])
	var last: int = await _advance(host, guest, HOUR_MSEC * 5 / 6)
	var book: OrderBook = host.net.orders.book
	var late: int = plan.filter(func(o: Dictionary) -> bool: return int(o["due_min"]) < last).size()
	var late_in_book: int = 0
	for order: Dictionary in book.to_dict()["orders"]:
		late_in_book += 1 if order["state"] == Order.STATE_LATE else 0
	_expect(host.net.orders.planned().is_empty() and book.size() == plan.size() and late_in_book == late,
		"At %d the whole plan is in the host's book, the %d past due late (%d orders, %d late)"
		% [last, late, book.size(), late_in_book])
	_expect_books(host, guest, "at the end of the day")
	var ids: Array = plan.map(func(o: Dictionary) -> StringName: return o["id"])
	_expect(host_bus.added == ids and client_bus.added == ids,
		"Each peer told order_added once per order, in the host's order, none for an expiry (host %d, client %d of %d)"
		% [host_bus.added.size(), client_bus.added.size(), ids.size()])
	var restores: Array[int] = []
	guest.net.company_state_restored.connect(func(seq: int) -> void: restores.append(seq))
	host.net.send_snapshot(client_id)
	var back: bool = await _wait_for(func() -> bool: return restores.size() == 1)
	_expect(back and client_bus.added == ids and restores == [host.net.seq],
		"A snapshot sent again tells nothing (told %d, restored %s)" % [client_bus.added.size(), restores])
	_expect_books(host, guest, "after the snapshot")


func _play_day_two(host: OrdersRoot, guest: OrdersRoot, host_bus: PeerBus, client_bus: PeerBus) -> void:
	# Two late orders and an open one (a third late one if none is open) close, as D-0815.b and D-0302
	# will by events: done by hand here, on both books alike.
	var late: Array[StringName] = []
	var open: Array[StringName] = []
	for order: Dictionary in host.net.orders.book.to_dict()["orders"]:
		(late if order["state"] == Order.STATE_LATE else open).append(order["id"])
	_expect(late.size() >= 3, "Day 1 left at least three late orders (%d)" % late.size())
	if late.size() < 3:
		return
	var closed: Array[StringName] = [late[0], late[1], open[0] if not open.is_empty() else late[2]]
	var kept: Array[StringName] = []
	for order: Dictionary in host.net.orders.book.to_dict()["orders"]:
		if not closed.has(order["id"]):
			kept.append(order["id"])
	for peer: OrdersRoot in [host, guest]:
		var book: OrderBook = peer.net.orders.book
		book.mark_delivered(closed[0], 100, true)
		book.mark_failed(closed[1])
		if not book.cancel(closed[2]):
			book.mark_failed(closed[2])
	_expect_books(host, guest, "with three orders closed by hand")
	_skip_msec += HOUR_MSEC / 4
	var summed: bool = await _wait_for(func() -> bool:
		return host.day_cycle.phase() == DayCycle.Phase.SUMMARY and guest.net.seq == host.net.seq)
	_expect(summed, "Past 20:00 the day closes on both peers (host %s)" % host.day_cycle.phase_name())
	_expect(host.day_cycle.next_day() and await _synced(host, guest), "The host opens day 2")
	var left: Array = (host.net.orders.book.to_dict()["orders"] as Array).map(
		func(o: Dictionary) -> StringName: return o["id"])
	_expect(left == kept, "Day 2's opening drops the three closed orders and keeps the rest of day 1 (%d of %d)"
		% [left.size(), kept.size() + 3])
	_expect_books(host, guest, "after day 2's opening")
	var plan: Array[Dictionary] = host.net.orders.planned()
	_expect(not plan.is_empty() and str(plan[0]["id"]).begins_with("d2_"), "Day 2 has its own plan")
	var told: int = host_bus.added.size()
	var now: int = await _advance(host, guest, HOUR_MSEC * 4)
	var arrived: Array = plan.filter(func(o: Dictionary) -> bool: return int(o["created_min"]) <= now).map(
		func(o: Dictionary) -> StringName: return o["id"])
	var book_ids: Array = (host.net.orders.book.to_dict()["orders"] as Array).map(
		func(o: Dictionary) -> StringName: return o["id"])
	_expect(not arrived.is_empty() and book_ids == kept + arrived,
		"By %d day 2's orders came in on top of what day 1 left (%d new)" % [now, arrived.size()])
	_expect_books(host, guest, "on day 2")
	_expect(host_bus.added.slice(told) == arrived and client_bus.added == host_bus.added,
		"...each told once on each peer (host %d, client %d)" % [host_bus.added.size(), client_bus.added.size()])


# --- Helpers ---


func _side(side_name: String) -> Node:
	var side := Node.new()
	side.name = side_name
	root.add_child(side)
	set_multiplayer(SceneMultiplayer.new(), side.get_path())
	return side


func _peer_root(state: Node, bus: PeerBus) -> OrdersRoot:
	var level := OrdersRoot.new()
	level.name = "CompanyRoot"
	level.company_state = state
	level.save_dir = DIR
	level.save_slot = "net"
	level.dev_args = PackedStringArray()
	level.bus = bus
	return level


## The host's ticks move `msec` on; once its business tick polled the orders at the new shed minute and
## the client applied every event, the minute polled.
func _advance(host: OrdersRoot, guest: OrdersRoot, msec: int) -> int:
	_skip_msec += msec
	var now: int = floori(host.day_cycle.shed_minute())
	var caught: bool = await _wait_for(func() -> bool:
		if host.day_cycle.phase() == DayCycle.Phase.OPENING or not host.net.orders.book.overdue(now).is_empty():
			return false
		for order: Dictionary in host.net.orders.planned():
			if int(order["created_min"]) <= now:
				return false
		return guest.net.seq == host.net.seq)
	_expect(caught, "The host's orders are in by %d and the client follows" % now)
	return now


func _synced(host: OrdersRoot, guest: OrdersRoot) -> bool:
	return await _wait_for(func() -> bool:
		return not guest.net.awaiting_snapshot() and guest.net.seq == host.net.seq)


func _expect_books(host: OrdersRoot, guest: OrdersRoot, when: String) -> void:
	_expect(guest.net.orders.book.to_dict() == host.net.orders.book.to_dict(),
		"The client has the host's book %s (%d orders, host %d)"
		% [when, guest.net.orders.book.size(), host.net.orders.book.size()])


func _ticks() -> int:
	return _base_msec + _skip_msec


func _new_state() -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.call(&"reset")
	return state


func _products() -> Dictionary:
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	var products: Dictionary = {}
	for id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		products[id] = catalog.product(id)
	return products


func _fresh_order(id: StringName, created: int) -> Dictionary:
	return Order.normalize(Order.make(id, "Ana", &"centro", &"centro_house_1", [{"product": &"hen", "qty": 1}],
		created, _products()))


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file: String in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _wait_for(done: Callable, seconds: float = WAIT_SECONDS) -> bool:
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
