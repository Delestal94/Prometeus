extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_supplier_choice.gd
##
## Choosing the supplier of an order, logic and network (expansion D-0621.b: supplier_schedule.gd,
## company_supplier_net.gd, supplier_order_cart.gd, supplier_board.gd; the board's screen is apart):
## - the calendar keeps a truck per (day, supplier), each with its supplier's arrival and wait
##   (use_suppliers: mercado 07:30-09:30, importadora 14:00-15:00), while the default supplier's truck,
##   the one the shed draws, keeps CompanyTuning's times and the calls that name no supplier (place,
##   ordered_for, truck_state, pallets_for, upcoming_days) see only it: another supplier's order does not
##   bring it; suppliers_on() lists a day's trucks earliest first; pallet ids stay "d<day>_<product>_<n>"
##   for the default one and are "d<day>-<supplier>-<product>_<n>" for the others, unique, read back by
##   SupplierIds.pallet_supplier(), the longest of the catalog fits CompanyPallets.id_ok; a bad supplier id
##   or bad times change nothing;
##   to_dict() of a default-only calendar is the old form, the others go under `suppliers`, the JSON round
##   trip keeps them, an old calendar loads as the default truck's and broken supplier entries are skipped;
##   copy_from() keeps the receiver's times; day_count() counts trucks; forget_before() drops every
##   supplier's past days;
## - the cart prices at its supplier's price_factor (hen 35 is 32 at mercado; milk 25 is 28 at panaderia);
## - CompanySupplierNet with the real catalog: five sellers, the default first; the request names the
##   supplier (request_data) and the host checks it exists and sells each product (else bad_data) and that
##   the wallet covers that supplier's prices (a wallet of 330 buys 10 hens at mercado, not at central);
##   with no supplier the order is the default one's (compat); the event carries the supplier and applying
##   it fills that truck only; MAX_DAY_QTY is per truck; apply() refuses a bad supplier or extra keys and
##   takes an event without one as the default's; a calendar with MAX_SUPPLIERS other trucks takes no
##   new supplier (too_much);
## - the snapshot part round-trips with `suppliers`, a malformed one is refused, fit() cuts suppliers and
##   days past the limits to what a client takes; CompanyState keeps the other trucks through the save;
## - solo on the real root: the five suppliers and their times are on the truck's calendar, an order from
##   mercado lands in its truck (and in the save copy) and the drawn truck does not come for it (D-0621.c);
## - two ENet peers and a late joiner: the client's board orders from mercado (request with the supplier),
##   both calendars carry it in mercado's truck and the screen settles as ordered, also when a resync covers
##   the event; a product the supplier does not sell is refused; the late joiner gets every truck and the
##   same states and poses.
## Expected in the log: the engine's leak notes at exit.

const PORT: int = 24693
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_supplier_choice"
const STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")
const CENTRAL: StringName = SupplierSchedule.DEFAULT_SUPPLIER
const MERCADO: StringName = &"mercado_del_campo"
const PANADERIA: StringName = &"panaderia_mayorista"
const IMPORTADORA: StringName = &"importadora_express"
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
	_test_calendar()
	_test_ids_and_dict()
	_test_cart_prices()
	_test_check()
	_test_snapshot()
	_test_save()
	await _test_root()
	await _test_peers()
	if _failures == 0:
		print("PASS: an order names its supplier, goes in its truck and travels by event, snapshot and save")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _catalog() -> CompanyCatalog:
	return CompanyCatalog.load_all()


func _helper() -> CompanySupplierNet:
	var helper := CompanySupplierNet.new()
	helper.load_catalog(_catalog())
	return helper


# --- The calendar ---


func _test_calendar() -> void:
	var s := SupplierSchedule.new()
	s.use_suppliers(_catalog().all(CompanyCatalog.SUPPLIERS))
	_expect(s.arrival_minute_of(MERCADO) == 7 * 60 + 30 and s.departure_minute_of(MERCADO) == 9 * 60 + 30,
		"mercado's truck comes at 07:30 and waits until 09:30")
	_expect(s.arrival_minute_of(IMPORTADORA) == 14 * 60 and s.departure_minute_of(IMPORTADORA) == 15 * 60,
		"importadora's truck comes at 14:00 and waits until 15:00")
	_expect(s.arrival_minute_of(CENTRAL) == SupplierSchedule.arrival_minute()
		and s.departure_minute_of(CENTRAL) == SupplierSchedule.departure_minute(),
		"the default truck keeps CompanyTuning's times")
	_expect(s.arrival_minute_of(&"ghost") == SupplierSchedule.arrival_minute(), "a supplier never handed over too")
	_expect(not s.set_times(&"Bad-Id", 600, 30) and not s.set_times(&"x", -1, 30) and not s.set_times(&"x", 1440, 30)
		and not s.set_times(&"x", 600, 0) and s.arrival_minute_of(&"x") == SupplierSchedule.arrival_minute(),
		"bad times or ids are refused")
	_expect(s.set_times(&"x", 600, 30) and s.departure_minute_of(&"x") == 630, "good ones are kept")
	_expect(s.place(4, [{"product": &"hen", "qty": 5}]) and s.place(4, [{"product": &"hen", "qty": 10}], MERCADO)
		and s.place(4, [{"product": &"milk_canister", "qty": 3}], PANADERIA), "three trucks booked for day 5")
	_expect(s.ordered_for(5) == {&"hen": 5} and s.ordered_for(5, CENTRAL) == {&"hen": 5},
		"the default truck carries only its order (got %s)" % [s.ordered_for(5)])
	_expect(s.ordered_for(5, MERCADO) == {&"hen": 10} and s.ordered_for(5, PANADERIA) == {&"milk_canister": 3},
		"each supplier's truck carries its own")
	_expect(s.has_delivery(5) and s.has_delivery(5, MERCADO) and not s.has_delivery(5, IMPORTADORA),
		"has_delivery() per supplier")
	_expect(s.suppliers_on(5) == [PANADERIA, MERCADO, CENTRAL],
		"suppliers_on() goes by arrival (got %s)" % [s.suppliers_on(5)])
	_expect(s.truck_state(5, 6 * 60, PANADERIA) == SupplierSchedule.STATE_PENDING
		and s.truck_state(5, 7 * 60, PANADERIA) == SupplierSchedule.STATE_AT_DOCK
		and s.truck_state(5, 8 * 60, PANADERIA) == SupplierSchedule.STATE_AT_DOCK
		and s.truck_state(5, 8 * 60 + 30, PANADERIA) == SupplierSchedule.STATE_LEFT, "panaderia: 07:00 to 08:30")
	_expect(s.truck_state(5, 8 * 60, MERCADO) == SupplierSchedule.STATE_AT_DOCK
		and s.truck_state(5, 9 * 60 + 30, MERCADO) == SupplierSchedule.STATE_LEFT, "mercado: 07:30 to 09:30")
	_expect(s.truck_state(5, 8 * 60) == SupplierSchedule.STATE_PENDING
		and s.truck_state(5, 9 * 60) == SupplierSchedule.STATE_AT_DOCK, "the default truck keeps 08:30")
	_expect(s.place(6, [{"product": &"puppy", "qty": 2}], MERCADO) and not s.has_delivery(7)
		and s.truck_state(7, 9 * 60) == SupplierSchedule.STATE_NONE
		and not SupplierTruck.pose(s, 7, 9 * 60.0)["present"],
		"another supplier's order does not bring the drawn (default) truck")
	_expect(s.day_count() == 4 and s.upcoming_days(0) == [5] and s.upcoming_days(0, MERCADO) == [5, 7],
		"day_count() counts trucks, upcoming_days() is the default truck's (got %d)" % s.day_count())
	var before: Dictionary = s.to_dict()
	for bad: StringName in [&"Bad-Id", &"", &"a-b", StringName("a".repeat(SupplierIds.MAX_LENGTH + 1))]:
		_expect(not s.place(4, [{"product": &"hen", "qty": 1}], bad) and s.to_dict() == before,
			"place() refuses the supplier id '%s'" % bad)
	s.clear_day(5, MERCADO)
	_expect(not s.has_delivery(5, MERCADO) and s.has_delivery(5) and s.has_delivery(7, MERCADO),
		"clear_day() drops one supplier's day")
	s.forget_before(6)
	_expect(s.day_count() == 1 and s.has_delivery(7, MERCADO), "forget_before() drops every supplier's past days")


func _test_ids_and_dict() -> void:
	var s := SupplierSchedule.new()
	s.place(4, [{"product": &"hen", "qty": 30}])
	s.place(4, [{"product": &"hen", "qty": 30}], MERCADO)
	var ids: Dictionary = {}
	for pallet: Dictionary in s.pallets_for(5) + s.pallets_for(5, MERCADO):
		ids[String(pallet["id"])] = SupplierIds.pallet_supplier(pallet["id"])
		_expect(CompanyPallets.id_ok(pallet["id"]), "pallet id %s fits the book" % pallet["id"])
	_expect(ids.size() == 4 and ids.get("d5_hen_1") == CENTRAL and ids.get("d5_hen_2") == CENTRAL
		and ids.get("d5-mercado_del_campo-hen_1") == MERCADO and ids.get("d5-mercado_del_campo-hen_2") == MERCADO,
		"pallet ids are unique and say whose truck (got %s)" % [ids])
	var catalog: CompanyCatalog = _catalog()
	for supplier: StringName in catalog.ids(CompanyCatalog.SUPPLIERS):
		_expect(SupplierIds.ok(supplier), "%s is an id the calendar takes" % supplier)
		for product: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
			var longest: String = String(SupplierIds.pallet_prefix(supplier, 99999, product)) + "_100"
			_expect(CompanyPallets.id_ok(longest), "the longest pallet id fits (%s)" % longest)
	var old_form := SupplierSchedule.new()
	old_form.place(2, [{"product": &"hen", "qty": 1}])
	_expect(old_form.to_dict().keys() == ["deliveries"], "a default-only calendar writes the old form")
	var data: Dictionary = s.to_dict()
	var others: Variant = data.get("suppliers")
	_expect(data["deliveries"] == {"5": {"hen": 30}} and others == {"mercado_del_campo": {"5": {"hen": 30}}},
		"the other trucks go under suppliers (got %s)" % [data])
	var back: SupplierSchedule = SupplierSchedule.from_dict(JSON.parse_string(JSON.stringify(data)))
	_expect(back.to_dict() == data and back.ordered_for(5, MERCADO) == {&"hen": 30}, "JSON round trip")
	var old: SupplierSchedule = SupplierSchedule.from_dict({"deliveries": {"3": {"hen": 2}}})
	_expect(old.ordered_for(3) == {&"hen": 2} and old.day_count() == 1, "an old calendar is the default truck's")
	var junk: SupplierSchedule = SupplierSchedule.from_dict({"deliveries": {}, "suppliers": {
		"Bad-Id": {"3": {"hen": 1}}, "distribuidora_central": {"3": {"hen": 9}}, "ok_one": "no",
		"fine": {"x": {"hen": 1}, "4": {"hen": 2, "puppy": 0}}}})
	_expect(junk.day_count() == 1 and junk.ordered_for(4, &"fine") == {&"hen": 2} and junk.ordered_for(3).is_empty(),
		"broken supplier entries are skipped (got %s)" % [junk.to_dict()])
	_expect(SupplierSchedule.from_dict({"suppliers": 7}).day_count() == 0, "wrong type loads empty")
	var other := SupplierSchedule.new()
	other.set_times(MERCADO, 100, 10)
	other.copy_from(s)
	_expect(other.arrival_minute_of(MERCADO) == 100 and other.ordered_for(5, MERCADO) == {&"hen": 30},
		"copy_from() brings the trucks and keeps the receiver's times")


func _test_cart_prices() -> void:
	var catalog: CompanyCatalog = _catalog()
	var defs: Dictionary = {}
	for id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		defs[id] = catalog.product(id)
	var cart := SupplierOrderCart.new()
	cart.products = defs
	_expect(cart.unit_price(&"hen") == 35, "with no supplier a hen is at list price")
	cart.supplier = catalog.supplier(MERCADO)
	cart.add(&"hen", 10)
	_expect(cart.unit_price(&"hen") == 32 and cart.total() == 320 and cart.lines()[0]["unit_price"] == 32,
		"at mercado (x0.90) a hen is 32 and 10 cost 320 (got %d)" % cart.total())
	cart.supplier = catalog.supplier(PANADERIA)
	_expect(cart.unit_price(&"milk_canister") == 28, "at panaderia (x1.10) milk is 28")
	_expect(SupplierOrderCart.unit_cost(&"ghost", defs, catalog.supplier(MERCADO)) == 0, "an unknown product costs 0")


# --- CompanySupplierNet ---


func _test_check() -> void:
	var helper: CompanySupplierNet = _helper()
	var mercado: SupplierDefinition = helper.seller(MERCADO)
	_expect(helper.supplier != null and helper.supplier.id == CENTRAL and helper.suppliers.size() == 5
		and helper.sellers()[0] == helper.supplier, "the catalog's five sellers, the default first")
	_expect(mercado != null and mercado.id == MERCADO and helper.seller(CENTRAL) == helper.supplier
		and helper.seller(&"ghost") == null, "seller() by id")
	_expect(helper.truck_of(helper.supplier) == CENTRAL and helper.truck_of(null) == CENTRAL
		and helper.truck_of(mercado) == MERCADO, "truck_of()")
	_expect(helper.schedule.arrival_minute_of(MERCADO) == 7 * 60 + 30, "load_catalog() hands the times to the calendar")
	var lines: Array = [{"product": &"hen", "qty": 10}]
	_expect(CompanySupplierNet.request_data(lines, MERCADO) == {"hen": 10, "supplier": "mercado_del_campo"}
		and CompanySupplierNet.request_data(lines) == {"hen": 10}, "the request names the supplier")
	_expect(CompanySupplierNet.request_data([{"product": "supplier", "qty": 1}]).is_empty(),
		"no product named supplier")
	var many: Array = []
	for index: int in range(CompanySupplierNet.MAX_LINES):
		many.append({"product": "p%d" % index, "qty": 1})
	var full: Dictionary = CompanySupplierNet.request_data(many, MERCADO)
	_expect(RpcGuard.dict_ok(full.merged({"rid": 9})), "MAX_LINES lines, the supplier and the rid fit a request")
	many.append({"product": "one_more", "qty": 1})
	_expect(CompanySupplierNet.request_data(many, MERCADO).is_empty(), "...one more line does not")
	var wallet := Wallet.new()
	wallet.money = 330
	var ask: Dictionary = helper.check(wallet, {"supplier": "mercado_del_campo", "hen": 10, "rid": 1}, 7, false)
	_expect(ask.get("reason") == &"" and ask.get("data") == {"order_day": 3, "lines": [{"product": "hen", "qty": 10}],
		"peer": 7, "supplier": "mercado_del_campo"}, "10 hens from mercado: one supplier_ordered (got %s)" % [ask])
	_expect(helper.check(wallet, {"supplier": "distribuidora_central", "hen": 10, "rid": 2}, 7, false)
		== {"reason": CompanySupplierNet.REASON_NO_FUNDS}, "...at central's prices 330 is short")
	_expect(helper.check(wallet, {"hen": 10, "rid": 3}, 7, false) == {"reason": CompanySupplierNet.REASON_NO_FUNDS},
		"...and so with no supplier named (central, compat)")
	wallet.money = 260
	var milk: Dictionary = helper.check(wallet, {"milk_canister": 10, "rid": 4}, 7, false)
	_expect(milk.get("reason") == &"" and milk["data"]["supplier"] == String(CENTRAL),
		"no supplier: the default truck at list price (got %s)" % [milk])
	_expect(helper.check(wallet, {"supplier": "panaderia_mayorista", "milk_canister": 10, "rid": 5}, 7, false)
		== {"reason": CompanySupplierNet.REASON_NO_FUNDS}, "panaderia's dearer milk is short")
	wallet.money = 100000
	for wrong: Variant in ["importadora_express", "ghost", 5, "Bad-Id", "", "a-b"]:
		_expect(helper.check(wallet, {"supplier": wrong, "hen": 1, "rid": 6}, 7, false)
			== {"reason": CompanySupplierNet.REASON_BAD_DATA}, "supplier %s for a hen is bad_data" % [wrong])
	_expect(helper.apply(ask["data"]) and helper.schedule.ordered_for(4, MERCADO) == {&"hen": 10}
		and not helper.schedule.has_delivery(4), "applying it fills mercado's truck, not the default one")
	for _order: int in range(10):
		helper.apply({"order_day": 3, "lines": [{"product": "hen", "qty": SupplierOrderCart.MAX_LINE_QTY}], "peer": 1,
			"supplier": String(CENTRAL)})
	_expect(helper.schedule.ordered_for(4) == {&"hen": CompanySupplierNet.MAX_DAY_QTY}, "the default truck is full")
	_expect(helper.check(wallet, {"hen": 1, "rid": 7}, 7, false) == {"reason": CompanySupplierNet.REASON_TOO_MUCH}
		and helper.check(wallet, {"supplier": "mercado_del_campo", "hen": 1, "rid": 8}, 7, false).get("reason") == &"",
		"MAX_DAY_QTY is per truck")
	var before: Dictionary = helper.schedule.to_dict()
	var line: Array = [{"product": "hen", "qty": 1}]
	for event: Dictionary in [
		{"order_day": 3, "lines": line, "peer": 1, "supplier": "a-b"},
		{"order_day": 3, "lines": line, "peer": 1, "supplier": 5},
		{"order_day": 3, "lines": line, "peer": 1, "extra": 1},
		{"order_day": 3, "lines": line, "peer": 1, "supplier": "mercado_del_campo", "extra": 1},
	]:
		_expect(not helper.apply(event) and helper.schedule.to_dict() == before, "apply() refuses %s" % [event])
	_expect(helper.apply({"order_day": 3, "lines": [{"product": "puppy", "qty": 2}], "peer": 1})
		and helper.schedule.ordered_for(4).get(&"puppy") == 2, "an event without a supplier is the default truck's")
	var crowded: CompanySupplierNet = _helper()
	for index: int in range(CompanySupplierNet.MAX_SUPPLIERS):
		crowded.schedule.place(3, [{"product": &"hen", "qty": 1}], StringName("x%d" % index))
	_expect(crowded.check(wallet, {"supplier": "mercado_del_campo", "hen": 1, "rid": 9}, 7, false)
		== {"reason": CompanySupplierNet.REASON_TOO_MUCH}
		and crowded.check(wallet, {"hen": 1, "rid": 10}, 7, false).get("reason") == &"",
		"with MAX_SUPPLIERS other trucks no new supplier fits; the default truck still does")


func _test_snapshot() -> void:
	var helper: CompanySupplierNet = _helper()
	helper.apply({"order_day": 3, "lines": [{"product": "hen", "qty": 4}], "peer": 1, "supplier": "mercado_del_campo"})
	helper.apply({"order_day": 3, "lines": [{"product": "hen", "qty": 2}], "peer": 1, "supplier": String(CENTRAL)})
	var part: Dictionary = helper.to_dict()
	var copy := CompanySupplierNet.new()
	_expect(part.has("suppliers") and copy.put_snapshot(part) and copy.schedule.to_dict() == part,
		"the snapshot part comes back equal, with the other trucks")
	var day: Dictionary = {"5": {"hen": 1}}
	var crowd: Dictionary = {}
	for index: int in range(CompanySupplierNet.MAX_SUPPLIERS + 1):
		crowd["x%d" % index] = day
	var wrong_parts: Array = [
		{"deliveries": {}, "suppliers": {"distribuidora_central": day}},
		{"deliveries": {}, "suppliers": {"Bad-Id": day}},
		{"deliveries": {}, "suppliers": {"m": {"0": {"hen": 1}}}},
		{"deliveries": {}, "suppliers": {"m": {"5": {"hen": CompanySupplierNet.MAX_DAY_QTY + 1}}}},
		{"deliveries": {}, "suppliers": "x"},
		{"deliveries": {}, "suppliers": {"m": day}, "extra": 1},
		{"suppliers": {"m": day}},
		{"deliveries": {}, "suppliers": crowd},
	]
	for wrong: Dictionary in wrong_parts:
		_expect(not copy.put_snapshot(wrong) and copy.schedule.to_dict() == part,
			"a malformed part is refused and changes nothing (%s)" % str(wrong).left(70))
	var oversized: Dictionary = {}
	var days: Dictionary = {}
	for index: int in range(2, CompanySupplierNet.MAX_DAYS + 4):
		days[str(index)] = {"hen": CompanySupplierNet.MAX_DAY_QTY + 5}
	for index: int in range(CompanySupplierNet.MAX_SUPPLIERS + 3):
		oversized["s%02d" % index] = days
	var big: SupplierSchedule = SupplierSchedule.from_dict({"deliveries": days, "suppliers": oversized})
	_expect(not CompanySupplierNet.new().put_snapshot(big.to_dict()), "an oversized calendar is no snapshot part")
	var cut: int = CompanySupplierNet.fit(big)
	_expect(cut > 0 and (big.to_dict()["suppliers"] as Dictionary).size() == CompanySupplierNet.MAX_SUPPLIERS
		and big.upcoming_days(0, &"s00").size() == CompanySupplierNet.MAX_DAYS
		and big.ordered_for(2, &"s00") == {&"hen": CompanySupplierNet.MAX_DAY_QTY}
		and not big.has_delivery(2, StringName("s%02d" % CompanySupplierNet.MAX_SUPPLIERS)),
		"fit() keeps the first MAX_SUPPLIERS suppliers, MAX_DAYS days each, units down to MAX_DAY_QTY")
	_expect(CompanySupplierNet.new().put_snapshot(big.to_dict()), "...and a client takes what is left")


func _test_save() -> void:
	_clean()
	var schedule := SupplierSchedule.new()
	schedule.place(2, [{"product": &"hen", "qty": 30}])
	schedule.place(2, [{"product": &"glass_tower", "qty": 6}], IMPORTADORA)
	var state: Node = STATE_SCRIPT.new()
	state.new_company("Saved")
	state.supplier_calendar = schedule.to_dict()
	_expect(CompanySave.save(state, "slot", DIR), "the company saves")
	var loaded: Node = STATE_SCRIPT.new()
	CompanySave.load_into(loaded, "slot", DIR)
	var back: SupplierSchedule = SupplierSchedule.from_dict(loaded.supplier_calendar)
	_expect(back.ordered_for(3) == {&"hen": 30} and back.ordered_for(3, IMPORTADORA) == {&"glass_tower": 6},
		"every truck comes back from the save (got %s)" % [loaded.supplier_calendar])
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
	var net: CompanyNet = level.net
	var schedule: SupplierSchedule = level.supplier_schedule
	_expect(net.supplier.suppliers.size() == 5 and net.supplier.supplier.id == CENTRAL
		and schedule.arrival_minute_of(IMPORTADORA) == 14 * 60, "the root's calendar knows the five suppliers' times")
	_expect(level.supplier_board.cart.supplier == net.supplier.supplier, "the board starts on the default supplier")
	var rid: int = net.request(CompanySupplierNet.ORDER, {"supplier": String(MERCADO), "hen": 10})
	_expect(rid > 0 and schedule.ordered_for(2, MERCADO) == {&"hen": 10} and schedule.ordered_for(2).is_empty(),
		"an order from mercado lands in its truck (got %s)" % [schedule.to_dict()])
	_expect(SupplierSchedule.from_dict(state.get(&"supplier_calendar")).ordered_for(2, MERCADO) == {&"hen": 10},
		"...and in the company's save copy")
	state.set(&"day", 2)
	level.clock.start(float(schedule.arrival_minute_of(MERCADO)) + 10.0)
	level.supplier_truck.refresh()
	_expect(not level.supplier_truck.visible, "the drawn truck does not come for mercado's order (D-0621.c)")
	level.free()
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
	var defs: Dictionary = net.supplier.load_catalog(_catalog())
	var parts: Dictionary = {"side": side, "net": net, "company": company}
	if with_board:
		var board := SupplierBoard.new()
		board.name = "SupplierBoard"
		side.add_child(board)
		board.setup(net, net.supplier.supplier, defs)
		parts["board"] = board
	return parts


func _test_peers() -> void:
	var host: Dictionary = _side("HostSide", false)
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 3) == OK, "the test hosts an ENet session on localhost:%d" % PORT)
	(host["side"] as Node).multiplayer.multiplayer_peer = server
	var host_net: CompanyNet = host["net"]
	var client: Dictionary = _side("ClientSide", true)
	var client_peer := ENetMultiplayerPeer.new()
	_expect(client_peer.create_client("127.0.0.1", PORT) == OK, "the client starts joining")
	(client["side"] as Node).multiplayer.multiplayer_peer = client_peer
	var client_net: CompanyNet = client["net"]
	client_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host_net.multiplayer.get_peers().size() == 1 and client_net.multiplayer.get_peers().has(1))
	_expect(connected, "the client connects to the host")
	if connected:
		_expect(host_net.send_snapshot(client_net.multiplayer.get_unique_id()), "the host sends the snapshot")
		var joined: bool = await _wait_for(func() -> bool: return not client_net.awaiting_snapshot())
		_expect(joined, "the client joins")
		await _check_board_order(host_net, client)
		await _check_resync(host_net, client)
		await _check_refused(client_net)
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


## The client's board, on mercado (what the board's screen will set, D-0621.b tablero), orders 10 hens.
func _check_board_order(host_net: CompanyNet, client: Dictionary) -> void:
	var client_net: CompanyNet = client["net"]
	var board: SupplierBoard = client["board"]
	board.cart.supplier = client_net.supplier.seller(MERCADO)
	_expect(board.open(), "the client opens the order screen")
	for _press: int in range(10):
		board.panel.more(&"hen")
	_expect(board.cart.total() == 320 and board.panel.confirm() == 1 and board.panel.is_waiting(),
		"10 hens at mercado's price (320) are sent and the screen waits")
	var arrived: bool = await _wait_for(func() -> bool: return not board.panel.is_waiting())
	_expect(arrived and host_net.supplier.schedule.ordered_for(DAY + 1, MERCADO) == {&"hen": 10}
		and host_net.supplier.schedule.ordered_for(DAY + 1).is_empty(),
		"the host put it in mercado's truck (got %s)" % [host_net.supplier.schedule.to_dict()])
	_expect(client_net.supplier.schedule.to_dict() == host_net.supplier.schedule.to_dict(), "...and so did the client")
	_expect(board.cart.is_empty()
		and board.panel.status_text() == SupplierOrderPanel.reason_text("UI_SUPPLIER_ORDERED", [1, DAY + 1]),
		"the client's screen shows it ordered (got '%s')" % board.panel.status_text())


## The order's event is covered by a resync: the screen compares mercado's truck and settles as ordered.
func _check_resync(host_net: CompanyNet, client: Dictionary) -> void:
	var client_net: CompanyNet = client["net"]
	var board: SupplierBoard = client["board"]
	for _press: int in range(5):
		board.panel.more(&"hen")
	_expect(board.panel.confirm() == 1, "another order from mercado goes")
	client_net._start_waiting()
	var settled: bool = await _wait_for(func() -> bool: return not board.panel.is_waiting())
	_expect(settled and host_net.supplier.schedule.ordered_for(DAY + 1, MERCADO) == {&"hen": 15}
		and client_net.supplier.schedule.to_dict() == host_net.supplier.schedule.to_dict()
		and board.panel.status_text() == SupplierOrderPanel.reason_text("UI_SUPPLIER_ORDERED", [1, DAY + 1]),
		"a resync that covers it settles the screen as ordered (got '%s')" % board.panel.status_text())
	board.close()


## A client's order of a product the named supplier does not sell is refused, and nothing changes.
func _check_refused(client_net: CompanyNet) -> void:
	var refusals: Array = []
	var catch := func(rid: int, reason: StringName) -> void: refusals.append([rid, reason])
	client_net.request_rejected.connect(catch)
	var before: Dictionary = client_net.supplier.schedule.to_dict()
	var rid: int = client_net.request(CompanySupplierNet.ORDER, {"supplier": String(IMPORTADORA), "hen": 1})
	var answered: bool = await _wait_for(func() -> bool: return not refusals.is_empty())
	_expect(answered and refusals == [[rid, CompanySupplierNet.REASON_BAD_DATA]]
		and client_net.supplier.schedule.to_dict() == before,
		"importadora sells no hens: bad_data and no change (got %s)" % [refusals])
	client_net.request_rejected.disconnect(catch)
	# The default truck too, so the late joiner has both kinds.
	client_net.request(CompanySupplierNet.ORDER, {"supplier": String(CENTRAL), "puppy": 3})
	await _wait_for(func() -> bool: return client_net.supplier.schedule.has_delivery(DAY + 1))


func _check_late_join(host_net: CompanyNet) -> void:
	var late: Dictionary = _side("LateSide", false)
	var late_peer := ENetMultiplayerPeer.new()
	_expect(late_peer.create_client("127.0.0.1", PORT) == OK, "a late peer starts joining")
	(late["side"] as Node).multiplayer.multiplayer_peer = late_peer
	var late_net: CompanyNet = late["net"]
	late_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host_net.multiplayer.get_peers().size() == 2 and late_net.multiplayer.get_peers().has(1))
	_expect(connected, "the late peer connects")
	if not connected:
		late_peer.close()
		return
	_expect(host_net.send_snapshot(late_net.multiplayer.get_unique_id()), "the host sends it the snapshot")
	var joined: bool = await _wait_for(func() -> bool: return not late_net.awaiting_snapshot())
	var host_cal: SupplierSchedule = host_net.supplier.schedule
	var late_cal: SupplierSchedule = late_net.supplier.schedule
	_expect(joined and late_cal.to_dict() == host_cal.to_dict()
		and late_cal.ordered_for(DAY + 1, MERCADO) == {&"hen": 15} and late_cal.ordered_for(DAY + 1) == {&"puppy": 3},
		"the late peer gets every truck (got %s)" % [late_cal.to_dict()])
	var mercado_at: int = host_cal.arrival_minute_of(MERCADO) + 10
	_expect(late_cal.truck_state(DAY + 1, mercado_at, MERCADO) == SupplierSchedule.STATE_AT_DOCK
		and host_cal.truck_state(DAY + 1, mercado_at, MERCADO) == SupplierSchedule.STATE_AT_DOCK,
		"...mercado's truck is at the dock at the same minute on both")
	var minute: float = float(SupplierSchedule.arrival_minute()) + 10.0
	var on_host: Dictionary = SupplierTruck.pose(host_cal, DAY + 1, minute, 0)
	_expect(bool(on_host["present"]) and on_host == SupplierTruck.pose(late_cal, DAY + 1, minute, 0),
		"...and the drawn (default) truck is in the same pose")
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
