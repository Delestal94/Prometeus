extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_day_close_orders.gd
##
## The day's end for the customers' orders in the company mode (D-0851; rules 2, 4 (the part that fits), 6 to 8
## and 10 of docs/expansion-distritos/diseno/clientes.md): order_day_close.gd (OrderDayClose),
## company_orders_net.gd (order_closed, abandon(), close_day(), fail_returned()), company_trips.gd (day_open,
## DAY_CLOSED), day_cycle.gd (the close in CLOSING, is_day_closed(), the 20:00 notice) and
## company_day_orders.gd (the poll in CLOSING).
## - OrderDayClose on a plain book: abandoned() names the late orders a window past due that are not out on the
##   road nor carried by a vehicle (on_road); closing_plan() fails the late, out and past-due ones and cancels
##   those in their window, or fails everything when the day was closed early; closed orders are in neither;
##   close_day() applies the plan;
## - a day that closes at 20:00 (solo host, the day cycle, a CompanyTrips and the orders step by hand): an order
##   late, one in its window, one that lapses while the last vehicle is out (CLOSING keeps expiring orders but
##   none comes in) and one that came back undelivered end failed -3, cancelled 0, failed -3 and failed -3
##   (50 to 41, none of them paid); a vehicle that crosses after 20:00 is refused with DAY_CLOSED and the day
##   does not wait for it; the 20:00 notice is told once; SUMMARY comes the poll after the close; the next day
##   opens with an empty book; a customer gives up on a late order a window past due (-3) in OPERATING too,
##   unless a trip carries it;
## - the same day closed early (close_early()) fails everything left (all -3), and the next day, closed at
##   20:00, cancels the order in its window again (the early flag is the day's);
## - the book events: order_closed with a bad shape (unknown order, closed one, `delivered` or `open` as state, a
##   missing or extra key, cancelling a late order) is refused by the host without spending a seq;
## - a host and a client as ENet peers: the same close reaches the client as events, both books end equal, the
##   reputation changes on the host only, and the client can't close, abandon or publish anything.
## Expected in the log: CompanyNet's error for each event the host refuses to publish ("could not apply its
## own"), Godot's for the forged _apply_event ("RPC '_apply_event' is not allowed").

const PORT: int = 24703
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const START_TICK: int = 9_000_000
const ABANDONED_COST: float = -3.0
const OPEN_MIN: int = CompanyTuning.DAY_END_MIN

var _failures: int = 0
var _now: int = START_TICK
var _products: Dictionary = {}
var _zone: StringName = &""
var _notices: Array[String] = []
var _host: Peer
var _client: Peer


## One peer of the network part: its side, CompanyNet, company, and what it applied.
class Peer:
	extends RefCounted
	var side: Node
	var net: CompanyNet
	var state: Node
	var kinds: Array[StringName] = []
	var refusals: Array = []


## A solo host: a company, CompanyNet, the clock, the day cycle and the trips out of its shed.
class World:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var clock: GameClock
	var cycle: DayCycle
	var trips: CompanyTrips
	var closed: Array = []
	var refused: Array = []
	var returned: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_load_catalogs()
	var bus: Node = root.get_node_or_null(^"EventBus")
	if bus == null:
		push_error("EventBus autoload missing")
		quit(1)
		return
	bus.connect(&"depot_notice", func(text: String) -> void: _notices.append(text))
	_check_book_rules()
	_check_twenty_hundred()
	_check_early_close()
	_check_event_shapes()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: at the day's end the late orders fail (-3), those in their window are cancelled, an early close"
			+ " fails them all, a vehicle can't leave after 20:00, and the host's events give every peer the same book")
	quit(_failures)


func _load_catalogs() -> void:
	var hen := load("res://data/products/hen.tres") as ProductDefinition
	_products = {hen.id: hen} if hen != null else {}
	for zone: ZoneDefinition in CompanyCatalog.load_all().zones():
		if zone.is_open_at_start() and _zone == &"":
			_zone = zone.id
	_expect(_products.has(&"hen") and _zone != &"", "The catalogs load (hen, zone '%s')" % _zone)


# --- OrderDayClose on a plain book ---


func _check_book_rules() -> void:
	var book := OrderBook.new()
	book.add(_order(&"in_window", 600, 1300))
	book.add(_order(&"packed", 600, 1300))
	book.mark_packed(&"packed", &"box_1")
	book.add(_order(&"late", 600, 900))
	book.add(_order(&"late_packed", 600, 900))
	book.mark_packed(&"late_packed", &"box_2")
	book.add(_order(&"out", 600, 900))
	book.mark_packed(&"out", &"box_3")
	book.mark_out(&"out", &"trip_1")
	book.add(_order(&"unmarked", 600, 1000))
	book.add(_order(&"done", 600, 900))
	book.mark_packed(&"done", &"box_4")
	book.mark_out(&"done", &"trip_2")
	book.mark_delivered(&"done", 100, true, 800)
	book.add(_order(&"gone", 600, 900))
	book.mark_failed(&"gone")
	book.expire(1001)
	_expect(book.state_of(&"late") == Order.STATE_LATE and book.state_of(&"in_window") == Order.STATE_OPEN
		and book.state_of(&"out") == Order.STATE_LATE and book.get_order(&"out")["late_from"] == Order.STATE_OUT,
		"The book is set: late, in its window, out and late from the road")
	book.add(_order(&"fresh", 600, 1010))
	var limit: int = 900 + CompanyTuning.ORDER_ABANDON_MIN
	_expect(OrderDayClose.abandoned(book, limit).is_empty(), "Nobody is given up on at the limit minute")
	var gone: Array[StringName] = OrderDayClose.abandoned(book, limit + 1)
	_expect(gone == [&"late", &"late_packed"],
		"One minute later the late ones off the road are given up on, the one late from the road is not (got %s)"
		% [gone])
	var carried: Callable = func(id: StringName) -> bool: return id == &"late_packed"
	_expect(OrderDayClose.abandoned(book, limit + 1, carried) == [&"late"],
		"...except the one a vehicle carries (on_road)")
	_expect(book.state_of(&"late") == Order.STATE_LATE, "abandoned() changes nothing")

	var plan: Dictionary = OrderDayClose.closing_plan(book, 1005, false)
	_expect(plan["failed"] == [&"late", &"late_packed", &"out", &"unmarked"]
		and plan["cancelled"] == [&"in_window", &"packed", &"fresh"],
		"At 1005 the late, the out and the one past due though nobody marked it fail; the rest in their window"
		+ " are cancelled (got %s)" % [plan])
	var early: Dictionary = OrderDayClose.closing_plan(book, 1005, true)
	_expect(early["cancelled"].is_empty() and early["failed"].size() == 7,
		"Closed early everything left fails, none is cancelled (got %s)" % [early])
	_expect(not early["failed"].has(&"done") and not early["failed"].has(&"gone"),
		"...and the closed orders are in neither list")
	var applied: Dictionary = OrderDayClose.close_day(book, 1005, false)
	_expect(applied == plan and book.state_of(&"late") == Order.STATE_FAILED
		and book.state_of(&"in_window") == Order.STATE_CANCELLED and book.state_of(&"out") == Order.STATE_FAILED
		and book.state_of(&"done") == Order.STATE_DELIVERED and book.open_orders().is_empty(),
		"close_day() applies the plan: nothing is left to deliver")
	book.free()


# --- A day that closes at 20:00 ---


func _check_twenty_hundred() -> void:
	var world: World = _new_world("Veinte SRL", 24000)
	var net: CompanyNet = world.net
	var book: OrderBook = net.orders.book
	_open_day(world)
	_expect(world.cycle.phase() == DayCycle.Phase.OPERATING and not world.cycle.is_day_closed()
		and world.trips.departure_verdict(&"van_1")["ok"],
		"Day 1 is OPERATING, open to leave (got %s)" % world.cycle.phase_name())
	var a: Dictionary = _order(&"d1_a", 600, 1100)
	var b: Dictionary = _order(&"d1_b", 1110, 1350)
	var c: Dictionary = _order(&"d1_c", 1000, 1230)
	var d: Dictionary = _order(&"d1_d", 700, 1300)
	var e: Dictionary = _order(&"d1_e", 1210, 1450)
	net.orders.plan([a, b, c, d, e])
	var start_rep: float = _reputation(world)

	_tick(world, 650)
	_expect(book.has(&"d1_a") and not book.has(&"d1_c"), "A comes in at 10:50, C not yet")
	_tick(world, 1105)
	_expect(book.state_of(&"d1_a") == Order.STATE_LATE and book.state_of(&"d1_c") == Order.STATE_OPEN
		and book.has(&"d1_d") and not book.has(&"d1_b"),
		"At 18:25 A is late, C and D are in their window, B not in yet")
	_tick(world, 1150)
	_expect(book.state_of(&"d1_b") == Order.STATE_OPEN, "B comes in at 19:10")

	# D goes out at 19:50 with its box: the vehicle's own book (CompanyTrips) marks it out.
	world.trips.book.add(d)
	world.trips.book.mark_packed(&"d1_d", &"box_d")
	world.trips.stage_cargo(&"van_1", [&"d1_d"], [&"box_d"])
	_tick(world, 1190)
	world.trips.track(&"van_1", Vector3(0, 0, -2))
	world.trips.track(&"van_1", Vector3(0, 0, -6))
	_expect(world.trips.trips_out() == 1 and world.trips.carries(&"d1_d")
		and world.cycle.phase() == DayCycle.Phase.OPERATING,
		"At 19:50 a vehicle leaves with D (trips out %d)" % world.trips.trips_out())

	_tick(world, 1200)
	_expect(world.cycle.phase() == DayCycle.Phase.CLOSING and world.cycle.is_day_closed(),
		"At 20:00 the day is CLOSING (got %s)" % world.cycle.phase_name())
	_expect(_notices.count(tr("UI_COMPANY_DAY_CLOSING_ROAD")) == 1
		and tr("UI_COMPANY_DAY_CLOSING_ROAD") != "UI_COMPANY_DAY_CLOSING_ROAD",
		"...and the notice \"only what is already on the road\" is told once (got %s)" % [_notices])
	_tick(world, 1215)
	_expect(not book.has(&"d1_e") and net.orders.planned().size() == 1,
		"In CLOSING no new order comes in: E (due 20:10) stays in the plan")

	# A vehicle that crosses after 20:00 is refused and the day doesn't wait for it.
	var verdict: Dictionary = world.trips.departure_verdict(&"van_2")
	_expect(not verdict["ok"] and verdict["key"] == CompanyTrips.DAY_CLOSED
		and CompanyTrips.DAY_CLOSED == "UI_COMPANY_GATE_DAY_CLOSED"
		and tr(CompanyTrips.DAY_CLOSED) != CompanyTrips.DAY_CLOSED,
		"Leaving after 20:00 is refused with DAY_CLOSED and a text (got %s)" % [verdict])
	world.trips.book.add(a)
	world.trips.book.mark_packed(&"d1_a", &"box_a")
	world.trips.stage_cargo(&"van_2", [&"d1_a"], [&"box_a"])
	world.trips.track(&"van_2", Vector3(0, 0, -2))
	world.trips.track(&"van_2", Vector3(0, 0, -6))
	_expect(world.trips.trip_of(&"van_2") == null and world.trips.is_out(&"van_2")
		and world.trips.trips_out() == 1 and world.refused.size() == 1
		and world.refused[0][1]["key"] == CompanyTrips.DAY_CLOSED,
		"A vehicle that crosses anyway starts no trip, is told why, and doesn't count in trips_out() (%d)"
		% world.trips.trips_out())
	_expect(world.trips.departure_verdict(&"van_2")["ok"], "...and a vehicle already out is not refused twice")
	_expect(world.trips.book.state_of(&"d1_a") == Order.STATE_PACKED, "...its order stays packed")

	_tick(world, 1232)
	_expect(book.state_of(&"d1_c") == Order.STATE_LATE and world.cycle.phase() == DayCycle.Phase.CLOSING,
		"At 20:32 C lapses while D's vehicle is still out: CLOSING keeps expiring orders")
	world.trips.track(&"van_2", Vector3(0, 0, -2))
	_expect(world.returned == [&"van_2"] and world.trips.trips_out() == 1 and not world.trips.is_out(&"van_2"),
		"The refused vehicle comes back (refused_returned) and the trip is the only one out")
	_expect(world.cycle.phase() == DayCycle.Phase.CLOSING and book.state_of(&"d1_b") == Order.STATE_OPEN,
		"...so the day still waits for D's trip, B still open")

	# D comes back at 20:50 without delivering: -3 at once, and the day's orders close next.
	var before: float = _reputation(world)
	_tick(world, 1250, false)
	world.trips.track(&"van_1", Vector3(0, 0, -2))
	_expect(world.closed.size() == 1 and world.closed[0] == [&"d1_d"] and world.trips.trips_out() == 0,
		"D's vehicle is back with D undelivered (closed %s)" % [world.closed])
	_expect(book.state_of(&"d1_d") == Order.STATE_FAILED
		and is_equal_approx(_reputation(world), before + ABANDONED_COST),
		"...D fails in the shared book, -3 (reputation %.1f to %.1f)" % [before, _reputation(world)])
	var seq: int = net.seq
	world.cycle.poll()
	_expect(world.cycle.phase() == DayCycle.Phase.CLOSING and book.open_orders().is_empty(),
		"The poll with no trip out closes the day's orders and the day stays CLOSING (got %s)"
		% world.cycle.phase_name())
	_expect(book.state_of(&"d1_a") == Order.STATE_FAILED and book.state_of(&"d1_b") == Order.STATE_CANCELLED
		and book.state_of(&"d1_c") == Order.STATE_FAILED and book.state_of(&"d1_d") == Order.STATE_FAILED,
		"A fails, B is cancelled, C fails, D failed (got %s %s %s %s)" % [book.state_of(&"d1_a"),
		book.state_of(&"d1_b"), book.state_of(&"d1_c"), book.state_of(&"d1_d")])
	_expect(is_equal_approx(_reputation(world), start_rep + 3.0 * ABANDONED_COST) and net.seq == seq + 3,
		"...three failures at -3 and a free cancellation: reputation %.1f to %.1f in %d events"
		% [start_rep, _reputation(world), net.seq - seq])
	_expect(world.state.get(&"money") == 24000 and not _paid_for_orders(world),
		"...and no order paid anything (money %s)" % world.state.get(&"money"))
	world.cycle.poll()
	_expect(world.cycle.phase() == DayCycle.Phase.SUMMARY and world.cycle.summary["day"] == 1,
		"SUMMARY comes the poll after (got %s)" % world.cycle.phase_name())
	_expect(world.trips.departure_verdict(&"van_3")["key"] == CompanyTrips.DAY_CLOSED,
		"In SUMMARY nobody leaves either")
	_expect(world.cycle.next_day() and world.cycle.current_day() == 2 and book.size() == 0,
		"Day 2 opens with an empty book (%d orders)" % book.size())

	_check_abandon_in_operating(world)
	world.side.free()


## Day 2 of `world`: a customer gives up on a late order a window past due, in OPERATING, unless a vehicle carries it.
func _check_abandon_in_operating(world: World) -> void:
	var net: CompanyNet = world.net
	var book: OrderBook = net.orders.book
	_tick(world, 480)
	_now += 5000
	world.cycle.poll()
	net.orders.plan([_order(&"d2_f", 480, 700), _order(&"d2_g", 480, 700)])
	world.trips.book.add(_order(&"d2_g", 480, 700))
	world.trips.book.mark_packed(&"d2_g", &"box_g")
	world.trips.stage_cargo(&"van_1", [&"d2_g"], [&"box_g"])
	world.trips.track(&"van_1", Vector3(0, 0, -2))
	world.trips.track(&"van_1", Vector3(0, 0, -6))
	var before: float = _reputation(world)
	_tick(world, 701)
	_expect(book.state_of(&"d2_f") == Order.STATE_LATE and world.cycle.phase() == DayCycle.Phase.OPERATING,
		"Day 2: F and G are late at 11:41")
	_tick(world, 700 + CompanyTuning.ORDER_ABANDON_MIN)
	_expect(book.state_of(&"d2_f") == Order.STATE_LATE, "...a customer waits the whole extra window")
	_tick(world, 700 + CompanyTuning.ORDER_ABANDON_MIN + 1)
	_expect(book.state_of(&"d2_f") == Order.STATE_FAILED and book.state_of(&"d2_g") == Order.STATE_LATE
		and is_equal_approx(_reputation(world), before + ABANDONED_COST),
		"...then gives up on F (-3) in OPERATING, but not on G, which a vehicle carries (reputation %.1f to %.1f)"
		% [before, _reputation(world)])


# --- Closed early ---


func _check_early_close() -> void:
	var world: World = _new_world("Temprano SRL", 1000)
	var net: CompanyNet = world.net
	var book: OrderBook = net.orders.book
	_open_day(world)
	net.orders.plan([_order(&"d1_a", 600, 1100), _order(&"d1_b", 1110, 1350), _order(&"d1_c", 1000, 1230)])
	var start_rep: float = _reputation(world)
	_tick(world, 1150)
	_expect(book.size() == 3 and book.state_of(&"d1_a") == Order.STATE_LATE, "Three orders in, A late at 19:10")
	_expect(world.cycle.close_early() and world.cycle.phase() == DayCycle.Phase.CLOSING,
		"The host closes the day early (got %s)" % world.cycle.phase_name())
	_tick(world, 1155)
	_expect(book.open_orders().is_empty() and is_equal_approx(_reputation(world), start_rep + 3.0 * ABANDONED_COST),
		"Closed early everything not delivered fails, the ones in their window too: 3 x -3 (reputation %.1f to %.1f)"
		% [start_rep, _reputation(world)])
	_expect(book.state_of(&"d1_b") == Order.STATE_FAILED and book.state_of(&"d1_c") == Order.STATE_FAILED,
		"...B and C failed, not cancelled")
	world.cycle.poll()
	_expect(world.cycle.phase() == DayCycle.Phase.SUMMARY, "...and SUMMARY follows (got %s)" % world.cycle.phase_name())
	_expect(world.cycle.next_day() and book.size() == 0, "Day 2 opens with an empty book")

	# The next day closes at 20:00: the early flag was day 1's.
	_tick(world, 480)
	_now += 5000
	world.cycle.poll()
	net.orders.plan([_order(&"d2_e", 1000, 1350)])
	_tick(world, 1100)
	_tick(world, 1200)
	_expect(world.cycle.phase() == DayCycle.Phase.CLOSING and book.state_of(&"d2_e") == Order.STATE_OPEN,
		"Day 2: at 20:00 E is in its window")
	var rep: float = _reputation(world)
	_tick(world, 1201)
	_expect(book.state_of(&"d2_e") == Order.STATE_CANCELLED and is_equal_approx(_reputation(world), rep),
		"...and a day closed at 20:00 cancels it for free again (the early flag is the day's)")
	world.side.free()


# --- Events ---


func _check_event_shapes() -> void:
	var world: World = _new_world("Eventos SRL", 1000)
	var net: CompanyNet = world.net
	var book: OrderBook = net.orders.book
	_expect(net.publish(CompanyOrdersNet.ADDED, {"order": _order(&"o_late", 100, 200)})
		and net.publish(CompanyOrdersNet.ADDED, {"order": _order(&"o_open", 100, 900)})
		and net.publish(CompanyOrdersNet.ADDED, {"order": _order(&"o_done", 100, 900)}),
		"Three orders come in")
	net.publish(CompanyOrdersNet.EXPIRED, {"order": &"o_late", "minute": 201})
	book.mark_packed(&"o_done", &"box_x")
	book.mark_out(&"o_done", &"trip_x")
	book.mark_delivered(&"o_done", 100, true, 300)
	var seq: int = net.seq
	var rep: float = _reputation(world)
	var cases: Array = [
		[{"order": &"nobody", "state": &"failed"}, "an unknown order"],
		[{"order": &"o_done", "state": &"failed"}, "an order already delivered"],
		[{"order": &"o_open", "state": &"delivered"}, "a state of `delivered`"],
		[{"order": &"o_open", "state": &"open"}, "a state of `open`"],
		[{"order": &"o_open", "state": "unicorn"}, "an unknown state"],
		[{"order": &"o_open", "state": 1}, "a state that is not text"],
		[{"order": &"o_open"}, "no state"],
		[{"state": &"failed"}, "no order"],
		[{"order": &"o_open", "state": &"failed", "minute": 5}, "an extra key"],
		[{"order": &"o_late", "state": &"cancelled"}, "cancelling a late order"],
	]
	for case: Array in cases:
		_expect(not net.publish(CompanyOrdersNet.CLOSED, case[0]) and net.seq == seq and book.size() == 3,
			"The host doesn't publish an order_closed with %s" % case[1])
	_expect(book.state_of(&"o_late") == Order.STATE_LATE and book.state_of(&"o_open") == Order.STATE_OPEN
		and is_equal_approx(_reputation(world), rep), "...nothing changed, no reputation lost")
	_expect(net.publish(CompanyOrdersNet.CLOSED, {"order": &"o_open", "state": &"cancelled"})
		and book.state_of(&"o_open") == Order.STATE_CANCELLED and is_equal_approx(_reputation(world), rep),
		"A cancelled order goes through, at no cost (publish() alone never touches the reputation)")
	_expect(not net.publish(CompanyOrdersNet.CLOSED, {"order": &"o_open", "state": &"failed"}),
		"...and a closed order can't be closed again")
	_expect(net.orders.fail_returned(net, [&"nobody", &"o_open", &"o_done", &"o_late"]) == 1
		and book.state_of(&"o_late") == Order.STATE_FAILED
		and is_equal_approx(_reputation(world), rep + ABANDONED_COST),
		"fail_returned() fails only the live order of a list, -3 once")
	world.side.free()


# --- Host and client ---


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 2) == OK
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
		await _play_network()
	client.close()
	server.close()
	await process_frame
	for peer: Peer in [_host, _client]:
		set_multiplayer(null, peer.side.get_path())
		peer.side.free()


func _play_network() -> void:
	var id: int = _client.side.multiplayer.get_unique_id()
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"peer_level_ready"):
		network.emit_signal(&"peer_level_ready", id)
	else:
		_host.net.send_snapshot(id)
	_expect(await _wait_for(_same_seq), "The client gets the host's snapshot")
	var net: CompanyNet = _host.net
	var orders: Array[Dictionary] = [
		_order(&"n_late", 100, 600), _order(&"n_window", 100, 1300), _order(&"n_returned", 100, 1300),
		_order(&"n_lapsing", 100, 1300),
	]
	for order: Dictionary in orders:
		net.publish(CompanyOrdersNet.ADDED, {"order": order})
	net.publish(CompanyOrdersNet.EXPIRED, {"order": &"n_late", "minute": 601})
	_expect(await _wait_for(_same_seq) and _same_book(), "Both peers have the host's four orders, A late")
	var host_rep: float = _reputation_of(_host)
	var client_rep: float = _reputation_of(_client)

	_expect(_client.net.orders.close_day(_client.net, 1250, false) == 0
		and _client.net.orders.abandon(_client.net, 99999, Callable()) == 0
		and _client.net.orders.fail_returned(_client.net, [&"n_window"]) == 0
		and not _client.net.publish(CompanyOrdersNet.CLOSED, {"order": &"n_window", "state": &"failed"}),
		"A client can't close, abandon, fail or publish anything")
	var heard: int = _client.refusals.size()
	_client.net.request(CompanyOrdersNet.CLOSED, {"order": &"n_window", "state": &"failed"})
	# Godot drops the forged event (authority-only RPC) and logs an error: expected.
	_client.net._apply_event.rpc_id(1, net.seq + 1, CompanyOrdersNet.CLOSED, {"order": &"n_window", "state": &"failed"})
	var sentinel: int = _client.net.request(&"units_take", {"station": &"nowhere", "product": &"hen", "qty": 1})
	var answered: bool = await _wait_for(func() -> bool: return _reason(_client, sentinel) != &"")
	_expect(answered and _client.refusals.size() == heard + 1
		and _host.net.orders.book.state_of(&"n_window") == Order.STATE_OPEN
		and _client.net.orders.book.state_of(&"n_window") == Order.STATE_OPEN,
		"An order_closed request or forged event changes no book (heard %s)" % [_client.refusals.slice(heard)])

	# One order comes back undelivered, then the day ends at 20:50.
	_expect(net.orders.fail_returned(net, [&"n_returned"]) == 1, "The host fails the order a vehicle brought back")
	var sent: int = net.orders.close_day(net, 1250, false)
	_expect(sent == 3 and await _wait_for(_same_seq) and _same_book(),
		"The host closes the other three (%d events) and the client has the same book" % sent)
	var states: Array = []
	for order_id: StringName in [&"n_late", &"n_window", &"n_returned", &"n_lapsing"]:
		states.append(_client.net.orders.book.state_of(order_id))
	# n_lapsing was due at 1300: still in its window at 1250.
	_expect(states == [Order.STATE_FAILED, Order.STATE_CANCELLED, Order.STATE_FAILED, Order.STATE_CANCELLED],
		"...failed, cancelled, failed, cancelled (got %s)" % [states])
	_expect(is_equal_approx(_reputation_of(_host), host_rep + 2.0 * ABANDONED_COST)
		and is_equal_approx(_reputation_of(_client), client_rep),
		"The reputation fell 2 x -3 on the host (%.1f to %.1f) and did not move on the client (%.1f)"
		% [host_rep, _reputation_of(_host), _reputation_of(_client)])
	_expect(_client.kinds.count(CompanyOrdersNet.CLOSED) == 4 and _host.kinds.count(CompanyOrdersNet.CLOSED) == 4,
		"Every close reached the client as one order_closed event (client %d, host %d)"
		% [_client.kinds.count(CompanyOrdersNet.CLOSED), _host.kinds.count(CompanyOrdersNet.CLOSED)])
	_expect(net.orders.close_day(net, 1251, false) == 0 and net.orders.abandon(net, 5000, Callable()) == 0,
		"A second close finds nothing to close")

	# A client that missed the events gets the closed book from the snapshot.
	_client.net.orders.put_snapshot({"orders": [], "now_min": 0})
	_expect(_host.net.send_snapshot(id) and await _wait_for(_same_book),
		"A snapshot brings the closed orders to a peer that missed them")


# --- Helpers ---


## A solo host world: a company with `money`, CompanyNet, the clock (the test's ticks, the day's own pace), the
## day cycle and the trips out of a gate at z = -4, wired as CompanyRoot does (day_open, trip_closed to
## fail_returned).
func _new_world(company_name: String, money: int) -> World:
	var world := World.new()
	world.side = Node.new()
	world.side.name = "World_" + company_name.replace(" ", "")
	root.add_child(world.side)
	world.state = (load(STATE_SCRIPT) as GDScript).new()
	world.state.call(&"reset")
	world.state.call(&"new_company", company_name)
	world.state.set(&"money", money)
	world.side.add_child(world.state)
	world.net = CompanyNet.new()
	world.net.name = "CompanyNet"
	world.net.company = world.state
	world.side.add_child(world.net)
	world.clock = GameClock.new()
	world.clock.name = "GameClock"
	world.clock.ticks = func() -> int: return _now
	world.side.add_child(world.clock)
	world.cycle = DayCycle.new()
	world.cycle.name = "DayCycle"
	world.cycle.ticks = func() -> int: return _now
	world.side.add_child(world.cycle)
	_expect(world.clock.attach(world.net, world.state) and world.cycle.attach(world.net, world.clock, world.state),
		"%s: the clock and the day cycle attach" % company_name)
	world.trips = CompanyTrips.new()
	world.trips.name = "CompanyTrips"
	world.side.add_child(world.trips)
	world.trips.setup(Vector3(0, 0, -4), 2.0)
	world.trips.minute_now = func() -> int: return floori(world.clock.minute_now())
	world.trips.day_open = func() -> bool: return not world.cycle.is_day_closed()
	world.trips.trip_closed.connect(func(_trip: Trip, failed: Array[StringName]) -> void:
		world.closed.append(failed)
		world.net.orders.fail_returned(world.net, failed))
	world.trips.departure_refused.connect(func(vehicle: StringName, reason: Dictionary) -> void:
		world.refused.append([vehicle, reason]))
	world.trips.refused_returned.connect(func(vehicle: StringName) -> void: world.returned.append(vehicle))
	world.cycle.trips_out = world.trips.trips_out
	world.side.set_process(false)
	return world


## Day 1 opens and is OPERATING at the clock's own pace, the test holding the ticks.
func _open_day(world: World) -> void:
	_expect(world.cycle.open_day(1), "The host opens day 1")
	_now += 5000
	world.cycle.poll()


## The clock reads `minute` now and the host does what its business tick does: the day cycle, then the orders step.
## `orders_too` false skips the orders step (and so the abandon sweep).
func _tick(world: World, minute: int, orders_too: bool = true) -> void:
	world.clock.start(float(minute))
	world.cycle.poll()
	if orders_too:
		CompanyDayOrders.poll(world.net, world.cycle, world.trips.carries)


func _reputation(world: World) -> float:
	return float(world.state.get(&"reputation"))


func _reputation_of(peer: Peer) -> float:
	return float(peer.state.get(&"reputation"))


## Did the wallet's ledger take any order_paid line?
func _paid_for_orders(world: World) -> bool:
	for entry: Dictionary in world.state.get(&"ledger"):
		if str(entry.get("reason", "")) == "order_paid":
			return true
	return false


func _order(id: StringName, created: int, due: int) -> Dictionary:
	var house := StringName("%s_house_1" % _zone)
	var items: Array = [{"product": &"hen", "qty": 1}]
	return Order.normalize(Order.make(id, "Ana", _zone, house, items, created, _products, [], due))


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	return peer


func _add_net(peer: Peer) -> void:
	peer.state = (load(STATE_SCRIPT) as GDScript).new()
	peer.state.call(&"reset")
	peer.state.call(&"new_company", peer.side.name)
	peer.side.add_child(peer.state)
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.side.add_child(peer.net)
	peer.net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		peer.kinds.append(kind))
	peer.net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		peer.refusals.append([rid, reason]))


func _same_seq() -> bool:
	return _client.net.seq == _host.net.seq


func _same_book() -> bool:
	return _client.net.orders.book.to_dict() == _host.net.orders.book.to_dict()


static func _reason(peer: Peer, rid: int) -> StringName:
	for entry: Array in peer.refusals:
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
