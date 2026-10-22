extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_supplier_order_net.gd
##
## The supplier order in the company's world and over the network (expansion D-0603.b.2:
## company_supplier_net.gd, supplier_board.gd, supplier_board_point.gd, the request mode of
## supplier_order_panel.gd; contract docs/expansion-distritos/diseno/red-autoridad.md):
## - CompanySupplierNet alone: an order of the catalog is one supplier_ordered {order_day, lines, peer}
##   and applying it puts it in the calendar for the next day (one pallet for 24 units); an unknown
##   product, one the supplier does not sell, 0 or 241 units, units as text or no line is bad_data; a
##   closed day is day_closed, a short wallet no_funds and a day's truck past MAX_DAY_QTY too_much, and
##   none of them changes the calendar; an event that does not fit (keys, duplicates, units) is refused
##   by apply() and changes nothing; applying one drops the days before its order_day; the snapshot
##   part comes back equal and a malformed one is refused, the calendar as it was;
## - the save: CompanyState keeps the calendar (supplier_calendar) through CompanySave's JSON, and a
##   malformed one loads as an empty calendar;
## - solo on the real root: the first day brings the first truck (DefaultShed.first_order) and nothing
##   else; the board by the dock has its point and prompt and using it opens the order screen, whose rows
##   (and focus) an event does not rebuild while it is open; one pallet
##   (24 units) ordered with Order is in the calendar of the next day, in the company's save copy too,
##   the cart is empty and the screen says so; on that day the truck comes; with no money the host refuses
##   the request (no_funds) and nothing changes; leaving the root saves the calendar;
## - two ENet peers and a late joiner in one process (each its own CompanyNet and company; the client
##   with a SupplierBoard): the client's Order is a request, the screen waits, the host applies it
##   and both calendars carry it, and the client's screen shows it ordered with the cart empty; when the
##   host's wallet is short (the client's copy still covers it) the host refuses, the client's screen
##   shows why with its cart as it was, and no calendar changes; a peer that joins late gets the calendar
##   in the snapshot and sees the same truck.

const PORT: int = 24676
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_supplier_order_net"
const STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")
const KEYS: Array[String] = [
	"UI_SUPPLIER_SENT", "UI_SUPPLIER_DAY_CLOSED", "UI_SUPPLIER_TOO_MUCH", "UI_SUPPLIER_NAME_DISTRIBUIDORA_CENTRAL",
	"WORLD_SHED_USE_SUPPLIER",
]
const DAY: int = 5

var _failures: int = 0


class Wallet:
	extends RefCounted
	var money: int = 0
	var day: int = 3

	func can_afford(amount: int) -> bool:
		return amount <= money


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_test_keys()
	_test_helper()
	_test_save()
	await _test_root()
	await _test_peers()
	if _failures == 0:
		print("PASS: supplier orders go through the host and every peer's calendar, by event and snapshot")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _test_keys() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")


## A helper with two products the supplier sells and one it does not.
func _helper() -> CompanySupplierNet:
	var lamp := ProductDefinition.new()
	lamp.id = &"lamp"
	lamp.buy_price = 50
	var vase := ProductDefinition.new()
	vase.id = &"vase"
	vase.buy_price = 20
	var other := ProductDefinition.new()
	other.id = &"other"
	other.buy_price = 5
	var seller := SupplierDefinition.new()
	seller.id = &"s"
	seller.products = [&"lamp", &"vase"]
	var helper := CompanySupplierNet.new()
	helper.supplier = seller
	helper.products = {&"lamp": lamp, &"vase": vase, &"other": other}
	return helper


func _test_helper() -> void:
	var helper: CompanySupplierNet = _helper()
	var wallet := Wallet.new()
	wallet.money = 2000
	var data: Dictionary = CompanySupplierNet.request_data([{"product": &"lamp", "qty": 24}])
	_expect(data == {"lamp": 24}, "The request is one flat key per product (got %s)" % [data])
	var ask: Dictionary = helper.check(wallet, data.merged({"rid": 1}), 7, false)
	_expect(ask.get("reason") == &"" and ask.get("kind") == CompanySupplierNet.ORDERED
		and ask.get("data") == {"order_day": 3, "lines": [{"product": "lamp", "qty": 24}], "peer": 7},
		"An order of the catalog is one supplier_ordered with the day and who asked (got %s)" % [ask])
	_expect(helper.schedule.day_count() == 0, "Checking writes nothing")
	_expect(helper.apply(ask["data"]) and helper.schedule.ordered_for(4) == {&"lamp": 24}
		and helper.schedule.pallets_for(4).size() == 1,
		"Applying it puts one pallet in the calendar for the next day (%s)" % [helper.schedule.to_dict()])
	var before: Dictionary = helper.schedule.to_dict()
	var bad: Array[Dictionary] = [
		{"ghost": 3}, {"other": 3}, {"lamp": 0}, {"lamp": SupplierOrderCart.MAX_LINE_QTY + 1}, {"lamp": "5"}, {},
		{"lamp": 2.0},
	]
	for wrong: Dictionary in bad:
		var refusal: Dictionary = helper.check(wallet, wrong.merged({"rid": 2}), 7, false)
		_expect(refusal == {"reason": CompanySupplierNet.REASON_BAD_DATA}, "%s is bad_data (got %s)" % [wrong, refusal])
	_expect(helper.check(wallet, {"lamp": 1, "rid": 3}, 7, true) == {"reason": CompanySupplierNet.REASON_DAY_CLOSED},
		"A closed day takes no order")
	wallet.money = 49
	_expect(helper.check(wallet, {"lamp": 1, "rid": 4}, 7, false) == {"reason": CompanySupplierNet.REASON_NO_FUNDS},
		"A short wallet is no_funds")
	wallet.money = 1000000
	for _order: int in range(9):
		helper.apply({"order_day": 3, "lines": [{"product": "lamp", "qty": SupplierOrderCart.MAX_LINE_QTY}], "peer": 1})
	_expect(helper.schedule.ordered_for(4)[&"lamp"] == 24 + 9 * SupplierOrderCart.MAX_LINE_QTY,
		"Orders of one day add up")
	var full: Dictionary = helper.check(wallet, {"lamp": SupplierOrderCart.MAX_LINE_QTY, "rid": 5}, 7, false)
	_expect(full == {"reason": CompanySupplierNet.REASON_TOO_MUCH},
		"Past MAX_DAY_QTY the truck is too full (%s)" % [full])
	before = helper.schedule.to_dict()
	var broken: Array[Dictionary] = [
		{"order_day": 3, "lines": [{"product": "lamp", "qty": 1}]},
		{"order_day": 3, "lines": [{"product": "lamp", "qty": 1}], "peer": 1, "extra": 1},
		{"order_day": -1, "lines": [{"product": "lamp", "qty": 1}], "peer": 1},
		{"order_day": 3, "lines": [], "peer": 1},
		{"order_day": 3, "lines": [{"product": "vase", "qty": 1}, {"product": "vase", "qty": 1}], "peer": 1},
		{"order_day": 3, "lines": [{"product": "vase", "qty": 0}], "peer": 1},
		{"order_day": 3, "lines": [{"product": "", "qty": 1}], "peer": 1},
		{"order_day": 3, "lines": [{"product": "lamp", "qty": SupplierOrderCart.MAX_LINE_QTY}], "peer": 1},
		{"order_day": "3", "lines": [{"product": "vase", "qty": 1}], "peer": 1},
	]
	for event: Dictionary in broken:
		_expect(not helper.apply(event) and helper.schedule.to_dict() == before, "apply() refuses %s" % [event])
	_expect(helper.apply({"order_day": 4, "lines": [{"product": "vase", "qty": 2}], "peer": 1})
		and helper.schedule.ordered_for(5) == {&"vase": 2} and helper.schedule.has_delivery(4),
		"An order of day 4 keeps day 4's truck and adds day 5's")
	_expect(helper.apply({"order_day": 5, "lines": [{"product": "vase", "qty": 1}], "peer": 1})
		and not helper.schedule.has_delivery(4) and helper.schedule.upcoming_days(0) == [5, 6],
		"Applying one drops the days before its order_day (got %s)" % [helper.schedule.upcoming_days(0)])
	var part: Dictionary = helper.to_dict()
	var copy := CompanySupplierNet.new()
	_expect(copy.put_snapshot(part) and copy.schedule.to_dict() == part, "The snapshot part comes back equal")
	var wrong_parts: Array = [
		"x", {}, {"deliveries": {"x": {"vase": 1}}}, {"deliveries": {"6": {"vase": 0}}},
		{"deliveries": {"6": {"vase": "1"}}}, {"deliveries": {"6": {}}}, {"deliveries": {"0": {"vase": 1}}},
		{"deliveries": {"6": {"vase": CompanySupplierNet.MAX_DAY_QTY + 1}}},
	]
	var many: Dictionary = {}
	for day: int in range(1, CompanySupplierNet.MAX_DAYS + 2):
		many[str(day)] = {"vase": 1}
	wrong_parts.append({"deliveries": many})
	for wrong_part: Variant in wrong_parts:
		_expect(not copy.put_snapshot(wrong_part) and copy.schedule.to_dict() == part,
			"A malformed snapshot part is refused and changes nothing (%s)" % [str(wrong_part).left(60)])


func _test_save() -> void:
	_clean()
	var schedule := SupplierSchedule.new()
	schedule.place(2, [{"product": &"hen", "qty": 30}])
	var state: Node = STATE_SCRIPT.new()
	state.new_company("Saved")
	state.supplier_calendar = schedule.to_dict()
	_expect(CompanySave.save(state, "slot", DIR), "The company saves")
	var loaded: Node = STATE_SCRIPT.new()
	CompanySave.load_into(loaded, "slot", DIR)
	var back: SupplierSchedule = SupplierSchedule.from_dict(loaded.supplier_calendar)
	_expect(back.ordered_for(3) == {&"hen": 30},
		"The calendar comes back from the save (got %s)" % [loaded.supplier_calendar])
	var data: Dictionary = state.to_dict()
	data["supplier_calendar"] = "broken"
	_expect(loaded.from_dict(data) and SupplierSchedule.from_dict(loaded.supplier_calendar).day_count() == 0,
		"A malformed calendar loads as an empty one")
	data["supplier_calendar"] = {"deliveries": {"a": 5, "4": {"hen": -2}}}
	_expect(loaded.from_dict(data) and SupplierSchedule.from_dict(loaded.supplier_calendar).day_count() == 0,
		"...and so do bad days and units")
	state.free()
	loaded.free()
	_clean()


# --- Solo, the real root ---


func _test_root() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var net: CompanyNet = level.net
	var schedule: SupplierSchedule = level.supplier_schedule
	_expect(net != null and net.supplier.schedule == schedule, "The truck's calendar is CompanyNet's")
	var first: Dictionary = {}
	for line: Dictionary in DefaultShed.load_default().first_order:
		first[StringName(line["product"])] = int(line["qty"])
	_expect(schedule.ordered_for(CompanyTuning.STARTING_DAY) == first and schedule.upcoming_days(0) == [1],
		"Day 1 brings the first truck and nothing else is on the way (got %s)" % [schedule.to_dict()])
	var point: SupplierBoardPoint = level.shed.supplier_point
	_expect(point != null and point.is_inside_tree() and point.get_prompt() == tr("WORLD_SHED_USE_SUPPLIER")
		and point.get_prompt() != "WORLD_SHED_USE_SUPPLIER", "The board by the dock has its point and prompt")
	_expect(point != null and level.shed.holds(point.global_position), "...inside the shed")
	var board: SupplierBoard = level.supplier_board
	if point == null or board == null or level.player == null:
		level.free()
		return
	point.interact(level.player)
	_expect(board.is_open() and board.panel.visible, "Using the board opens the order screen")
	# 24 sourdough cost 480: a new company (STARTING_MONEY 500) can pay for a pallet of it.
	var product: StringName = &"sourdough"
	for _press: int in range(24):
		board.panel.more(product)
	_expect(board.cart.qty(product) == 24 and board.cart.pallet_count() == 1, "24 units make one pallet")
	var plus: Button = board.panel.more_button(product)
	var seq: int = net.seq
	level.clock.start(float(CompanyTuning.DAY_START_MIN) + 5.0)
	_expect(net.seq > seq and board.panel.more_button(product) == plus and board.cart.qty(product) == 24,
		"An event while the screen is open keeps its rows (and the focus) and the cart")
	seq = net.seq
	_expect(board.panel.confirm() == 1, "Order asks the host for one pallet")
	_expect(net.seq == seq + 1 and schedule.ordered_for(2) == {product: 24},
		"The host applied it: the truck of day 2 brings it (got %s)" % [schedule.to_dict()])
	_expect(board.cart.is_empty() and not board.panel.is_waiting()
		and board.panel.status_text() == SupplierOrderPanel.reason_text("UI_SUPPLIER_ORDERED", [1, 2]),
		"The cart is empty and the screen says so (got '%s')" % board.panel.status_text())
	_expect(SupplierSchedule.from_dict(state.get(&"supplier_calendar")).ordered_for(2) == {product: 24},
		"The company keeps the calendar for the save")
	# The next day the truck comes.
	state.set(&"day", 2)
	level.clock.start(float(SupplierSchedule.arrival_minute()) + 10.0)
	level.supplier_truck.refresh()
	_expect(level.supplier_truck.visible, "On day 2 the truck is at the dock")
	# No money: the host refuses and nothing changes.
	state.set(&"money", 0)
	var refusals: Array = []
	net.request_rejected.connect(func(rid: int, reason: StringName) -> void: refusals.append([rid, reason]))
	var before: Dictionary = schedule.to_dict()
	seq = net.seq
	var rid: int = net.request(CompanySupplierNet.ORDER, {String(product): 24})
	_expect(refusals == [[rid, CompanySupplierNet.REASON_NO_FUNDS]] and schedule.to_dict() == before and net.seq == seq,
		"A short wallet is refused (no_funds) and nothing changes (got %s)" % [refusals])
	board.panel.more(product)
	_expect(board.panel.confirm() == 0 and board.panel.order_button().disabled, "...and Order stays off")
	board.close()
	_expect(not board.is_open(), "The screen closes")
	level.free()
	var saved: Node = STATE_SCRIPT.new()
	CompanySave.load_into(saved, CompanySave.DEFAULT_SLOT, DIR)
	_expect(SupplierSchedule.from_dict(saved.supplier_calendar).ordered_for(2) == {product: 24},
		"Leaving the root saves the calendar (got %s)" % [saved.supplier_calendar])
	saved.free()
	state.call(&"reset")
	_clean()


# --- Two peers and a late joiner ---


func _side(side_name: String, with_board: bool) -> Dictionary:
	var side := Node.new()
	side.name = side_name
	root.add_child(side)
	set_multiplayer(SceneMultiplayer.new(), side.get_path())
	var company: Node = STATE_SCRIPT.new()
	company.name = "Company"
	company.new_company("Test")
	company.day = DAY
	company.money = 10000
	side.add_child(company)
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	net.company = company
	side.add_child(net)
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	var defs: Dictionary = {}
	for id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		defs[id] = catalog.product(id)
	var seller: SupplierDefinition = catalog.supplier(&"distribuidora_central")
	net.supplier.products = defs
	net.supplier.supplier = seller
	var parts: Dictionary = {"side": side, "net": net, "company": company}
	if with_board:
		var board := SupplierBoard.new()
		board.name = "SupplierBoard"
		side.add_child(board)
		board.setup(net, seller, defs)
		parts["board"] = board
	return parts


func _test_peers() -> void:
	var host: Dictionary = _side("HostSide", false)
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 3) == OK, "The test hosts an ENet session on localhost:%d" % PORT)
	(host["side"] as Node).multiplayer.multiplayer_peer = server
	var host_net: CompanyNet = host["net"]
	var client: Dictionary = _side("ClientSide", true)
	var client_peer := ENetMultiplayerPeer.new()
	_expect(client_peer.create_client("127.0.0.1", PORT) == OK, "The client starts joining")
	(client["side"] as Node).multiplayer.multiplayer_peer = client_peer
	var client_net: CompanyNet = client["net"]
	client_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host_net.multiplayer.get_peers().size() == 1 and client_net.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if connected:
		_expect(host_net.send_snapshot(client_net.multiplayer.get_unique_id()), "The host sends the snapshot")
		var joined: bool = await _wait_for(func() -> bool: return not client_net.awaiting_snapshot())
		_expect(joined, "The client joins")
		await _check_client_orders(host, client)
		await _check_client_refused(host, client)
		await _check_late_join(host_net)
	client_peer.close()
	server.close()
	await process_frame
	for side_name: String in ["HostSide", "ClientSide", "LateSide"]:
		var side: Node = root.get_node_or_null(side_name)
		if side != null:
			set_multiplayer(null, side.get_path())
			side.free()
	RpcGuard.reset()


func _check_client_orders(host: Dictionary, client: Dictionary) -> void:
	var host_net: CompanyNet = host["net"]
	var client_net: CompanyNet = client["net"]
	var board: SupplierBoard = client["board"]
	var ordered: Array = []
	board.panel.ordered.connect(func(lines: Array[Dictionary], arrival: int) -> void: ordered.append([lines, arrival]))
	_expect(board.open() and board.panel.visible, "The client opens the order screen")
	_expect(board.context()["can_act"] == true and board.context()["request"] is Callable,
		"On a client the screen may act: Order goes as a request")
	for _press: int in range(24):
		board.panel.more(&"hen")
	_expect(board.panel.confirm() == 1 and board.panel.is_waiting(), "The client's Order is sent and the screen waits")
	_expect(client_net.supplier.schedule.day_count() == 0, "...nothing is written on the client ahead of the host")
	var arrived: bool = await _wait_for(func() -> bool: return not board.panel.is_waiting())
	_expect(arrived and host_net.supplier.schedule.ordered_for(DAY + 1) == {&"hen": 24},
		"The host applied the client's order for day %d (got %s)" % [DAY + 1, host_net.supplier.schedule.to_dict()])
	_expect(client_net.supplier.schedule.to_dict() == host_net.supplier.schedule.to_dict()
		and client_net.seq == host_net.seq, "...and the client's calendar is the host's")
	_expect(board.cart.is_empty() and ordered.size() == 1 and ordered[0][1] == DAY + 1
		and board.panel.status_text() == SupplierOrderPanel.reason_text("UI_SUPPLIER_ORDERED", [1, DAY + 1]),
		"The client's screen shows it ordered, cart empty (got '%s')" % board.panel.status_text())


func _check_client_refused(host: Dictionary, client: Dictionary) -> void:
	var host_net: CompanyNet = host["net"]
	var client_net: CompanyNet = client["net"]
	var board: SupplierBoard = client["board"]
	(host["company"] as Node).set(&"money", 0)
	var before: Dictionary = host_net.supplier.schedule.to_dict()
	var seq: int = host_net.seq
	for _press: int in range(24):
		board.panel.more(&"hen")
	var total: int = board.cart.total()
	_expect(board.panel.confirm() == 1, "The client's copy covers it, so Order goes")
	var answered: bool = await _wait_for(func() -> bool: return not board.panel.is_waiting())
	_expect(answered and board.panel.status_text() == SupplierOrderPanel.reason_text("UI_SUPPLIER_NO_FUNDS", [total]),
		"The host refuses and the client's screen says why (got '%s')" % board.panel.status_text())
	_expect(board.cart.qty(&"hen") == 24, "...the cart is as it was")
	_expect(host_net.supplier.schedule.to_dict() == before and client_net.supplier.schedule.to_dict() == before
		and host_net.seq == seq and client_net.seq == seq, "...and no calendar changed")
	(host["company"] as Node).set(&"money", 10000)
	board.close()


func _check_late_join(host_net: CompanyNet) -> void:
	var late: Dictionary = _side("LateSide", false)
	var late_peer := ENetMultiplayerPeer.new()
	_expect(late_peer.create_client("127.0.0.1", PORT) == OK, "A late peer starts joining")
	(late["side"] as Node).multiplayer.multiplayer_peer = late_peer
	var late_net: CompanyNet = late["net"]
	late_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host_net.multiplayer.get_peers().size() == 2 and late_net.multiplayer.get_peers().has(1))
	_expect(connected, "The late peer connects")
	if not connected:
		late_peer.close()
		return
	_expect(host_net.snapshot().get(CompanySupplierNet.SNAPSHOT_KEY) == host_net.supplier.to_dict(),
		"The snapshot carries the calendar")
	_expect(host_net.send_snapshot(late_net.multiplayer.get_unique_id()), "The host sends it the snapshot")
	var joined: bool = await _wait_for(func() -> bool: return not late_net.awaiting_snapshot())
	_expect(joined and late_net.supplier.schedule.to_dict() == host_net.supplier.schedule.to_dict()
		and late_net.supplier.schedule.ordered_for(DAY + 1) == {&"hen": 24},
		"The late peer gets the calendar in the snapshot (got %s)" % [late_net.supplier.schedule.to_dict()])
	var minute: float = float(SupplierSchedule.arrival_minute()) + 10.0
	var on_host: Dictionary = SupplierTruck.pose(host_net.supplier.schedule, DAY + 1, minute, 0)
	var on_late: Dictionary = SupplierTruck.pose(late_net.supplier.schedule, DAY + 1, minute, 0)
	_expect(bool(on_host["present"]) and on_host == on_late, "...and sees the same truck at the dock")
	late_peer.close()


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
