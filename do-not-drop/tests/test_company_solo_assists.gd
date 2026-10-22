extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_solo_assists.gd
##
## Solo-mode assists of the company (expansion D-0151, roles-tripulacion.md §6.2):
## - orders that make it in (D-0151.2): with a crew of one no order arrives at or after
##   SOLO_ORDER_LAST_ARRIVAL_MIN (15:00) and the count stays 8; with two some do arrive after 15:00;
##   the same seed gives the same minutes, and 0 players counts as 1;
## - the suggested supplier order (D-0151.3, SupplierOrderCart.suggested): units ordered today minus
##   the stock per product, nothing for a product the stock covers or the supplier does not sell,
##   trimmed from the product with the fewest units ordered until it leaves the rent and the reserve
##   in the wallet, empty when the money does not reach them; ordered_units() sums the day's orders;
## - the automatic order at the close (D-0151.3b, SupplierAutoOrder + SupplierAutoOrderHook), on a host with a
##   real CompanyNet, GameClock and DayCycle: a day whose orders the stock does not cover leaves exactly one
##   order for tomorrow in the SupplierSchedule with the suggested units (cancelled orders do not count) when
##   the day goes to CLOSING, by close_early() and by the 20:00 transition alike, and the wallet is not charged
##   then; it is the supplier_ordered every peer applies, with AUTO_PEER, so auto_units() tells it; an order for
##   tomorrow already sent, or a suggestion that is empty (stock covers it), adds nothing; a repeated CLOSING
##   event, or send() again, does not double it; two days in a row order only the second day's own orders (the
##   book keeps the whole session's, the hook notes the ids that came in since the last OPENING); a client's
##   hook (a fake peer connected as client 2, no socket) does nothing;
## - the day summary's line "automatic supplier order: N units" (DaySummaryPanel) shows with N > 0, hides at 0.

const STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")

var _failures: int = 0
var _now: int = 0


## A peer that is connected as client 2: not the server, so CompanyNet.is_host() is false. No socket.
class FakeClientPeer:
	extends MultiplayerPeerExtension

	func _poll() -> void:
		pass

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED

	func _get_unique_id() -> int:
		return 2

	func _is_server() -> bool:
		return false

	func _get_available_packet_count() -> int:
		return 0

	func _get_max_packet_size() -> int:
		return 1024

	func _get_packet_peer() -> int:
		return 1

	func _get_packet_channel() -> int:
		return 0

	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _get_packet_script() -> PackedByteArray:
		return PackedByteArray()

	func _put_packet_script(_buffer: PackedByteArray) -> Error:
		return OK

	func _set_target_peer(_peer: int) -> void:
		pass

	func _set_transfer_channel(_channel: int) -> void:
		pass

	func _get_transfer_channel() -> int:
		return 0

	func _set_transfer_mode(_mode: MultiplayerPeer.TransferMode) -> void:
		pass

	func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _set_refuse_new_connections(_enable: bool) -> void:
		pass

	func _is_refusing_new_connections() -> bool:
		return false

	func _is_server_relay_supported() -> bool:
		return false

	func _disconnect_peer(_peer: int, _force: bool) -> void:
		pass

	func _close() -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_solo_arrivals()
	_test_ordered_units()
	_test_suggested()
	_test_auto_order_rule()
	_test_auto_order_close_early()
	_test_auto_order_at_20()
	_test_auto_order_not_needed()
	_test_auto_order_already_sent()
	_test_auto_order_two_days()
	_test_auto_order_client()
	_test_summary_line()
	quit(_failures)


func _test_solo_arrivals() -> void:
	_expect(OrderRhythm.last_arrival_min(1) == CompanyTuning.SOLO_ORDER_LAST_ARRIVAL_MIN, "solo: last arrival 15:00")
	_expect(OrderRhythm.last_arrival_min(2) == CompanyTuning.ORDER_LAST_ARRIVAL_MIN, "duo: last arrival 19:00")
	var late_duo: int = 0
	for seed_value in 200:
		var solo := OrderRhythm.arrival_minutes(seed_value, 1)
		_expect(solo.size() == 8, "solo keeps its 8 orders")
		_expect(solo == OrderRhythm.arrival_minutes(seed_value, 1), "solo: same seed, same minutes")
		_expect(solo == OrderRhythm.arrival_minutes(seed_value, 0), "0 players counts as 1")
		for minute in solo:
			_expect(minute >= CompanyTuning.DAY_START_MIN, "solo: no arrival before opening")
			_expect(minute < CompanyTuning.SOLO_ORDER_LAST_ARRIVAL_MIN, "solo: no arrival from 15:00 on")
		for minute in OrderRhythm.arrival_minutes(seed_value, 2):
			if minute >= CompanyTuning.SOLO_ORDER_LAST_ARRIVAL_MIN:
				late_duo += 1
	_expect(late_duo > 0, "with 2 players orders still come in after 15:00 (%d)" % late_duo)
	var squeezed := OrderRhythm.arrival_minutes(7, 1, 3)
	_expect(squeezed.size() == 3 and squeezed.max() < CompanyTuning.SOLO_ORDER_LAST_ARRIVAL_MIN,
		"an explicit count is squeezed too")


func _test_ordered_units() -> void:
	var orders: Array = [
		{"items": [{"product": &"lamp", "qty": 2}, {"product": &"vase", "qty": 1}]},
		{"items": [{"product": &"lamp", "qty": 3}]},
		{},
	]
	_expect(SupplierOrderCart.ordered_units(orders) == {&"lamp": 5, &"vase": 1}, "ordered_units sums the day")
	_expect(SupplierOrderCart.ordered_units([]).is_empty(), "no orders, nothing ordered")


func _test_suggested() -> void:
	var products: Dictionary = {
		&"lamp": _product(&"lamp", 10),
		&"vase": _product(&"vase", 5),
		&"mug": _product(&"mug", 2),
	}
	var ordered: Dictionary = {&"lamp": 6, &"vase": 4, &"mug": 3, &"ghost": 9}
	var stock: Dictionary = {&"lamp": 1, &"mug": 5}
	# lamp 5 (50), vase 4 (20); mug covered by stock; ghost not in the catalog.
	var rich := SupplierOrderCart.suggested(ordered, stock, 1000, products)
	_expect(rich == {&"lamp": 5, &"vase": 4}, "suggested = ordered - stock: %s" % rich)
	var seller := SupplierDefinition.new()
	seller.id = &"s"
	seller.products = [&"lamp"]
	_expect(SupplierOrderCart.suggested(ordered, stock, 1000, products, seller) == {&"lamp": 5},
		"only what the supplier sells")
	# Budget 255 - 100 rent - 100 reserve = 55: 70 is 15 over; vase (4 ordered < 6) loses 3 units first.
	var tight := SupplierOrderCart.suggested(ordered, stock, 255, products)
	_expect(tight == {&"lamp": 5, &"vase": 1}, "trimmed from the least ordered product: %s" % tight)
	# Budget 30: vase goes, then lamp loses 2 units (40 over after vase).
	var poor := SupplierOrderCart.suggested(ordered, stock, 230, products)
	_expect(poor == {&"lamp": 3}, "trimmed into the next product: %s" % poor)
	var total: int = 0
	for id: StringName in poor:
		total += SupplierPurchase.cost(id, poor[id], products)
	_expect(total <= 230 - CompanyTuning.RENT_PER_DAY - CompanyTuning.SOLO_ORDER_CASH_RESERVE, "respects the reserve")
	_expect(SupplierOrderCart.suggested(ordered, stock, 150, products).is_empty(), "no money past the reserve, nothing")
	var capped := SupplierOrderCart.suggested({&"lamp": 999}, {}, 99999, products)
	_expect(capped == {&"lamp": SupplierOrderCart.MAX_LINE_QTY}, "a line stays under MAX_LINE_QTY")
	var cart := SupplierOrderCart.new()
	cart.products = products
	for id: StringName in rich:
		_expect(cart.set_qty(id, rich[id]), "the suggested lines load into the cart (%s)" % id)
	_expect(cart.total() == 70, "the loaded cart costs what was suggested")


func _test_auto_order_rule() -> void:
	var products: Dictionary = _catalog()
	var orders: Array = [
		{
			"id": &"a", "state": Order.STATE_OPEN,
			"items": [{"product": &"lamp", "qty": 6}, {"product": &"vase", "qty": 4}],
		},
		{"id": &"b", "items": [{"product": &"mug", "qty": 50}], "state": Order.STATE_CANCELLED},
		{"id": &"old", "items": [{"product": &"lamp", "qty": 70}], "state": Order.STATE_DELIVERED},
	]
	var kept: Array = SupplierAutoOrder.todays_orders(orders, {&"a": true, &"b": true})
	_expect(kept.size() == 1, "a cancelled order asked for nothing and an order of another day is not today's")
	var schedule := SupplierSchedule.new()
	var got := SupplierAutoOrder.lines(1000, schedule, kept, {&"lamp": 1}, products, null, 3)
	_expect(got == [{"product": &"lamp", "qty": 5}, {"product": &"vase", "qty": 4}], "rule lines: %s" % [got])
	_expect(SupplierAutoOrder.units_of(got) == 9, "units_of sums the lines")
	_expect(SupplierAutoOrder.lines(1000, null, kept, {}, products, null, 3).is_empty(), "no schedule, nothing")
	_expect(SupplierAutoOrder.lines(1000, schedule, kept, {}, products, null, 0).is_empty(), "no day, nothing")
	schedule.place(3, [{"product": &"lamp", "qty": 1}])
	_expect(SupplierAutoOrder.lines(1000, schedule, kept, {}, products, null, 3).is_empty(),
		"an order for tomorrow already there: nothing")
	_expect(not SupplierAutoOrder.lines(1000, schedule, kept, {}, products, null, 4).is_empty(),
		"...but the day after is free")
	var inventory := Inventory.new()
	inventory.receive(&"lamp", 2, &"shelf_a")
	inventory.receive(&"lamp", 3, &"shelf_b")
	inventory.receive(&"ghost", 9, &"shelf_a")
	_expect(SupplierAutoOrder.stock_units(inventory, products) == {&"lamp": 5},
		"stock is the catalog's units, anywhere")
	_expect(SupplierAutoOrder.stock_units(null, products).is_empty(), "no inventory, no stock")


## Day 1 asks for 6 lamps and 4 vases (a cancelled order for mugs too) and the shed holds 1 lamp.
func _closing_side(label: String, money: int = 1000) -> Dictionary:
	var state: Node = STATE_SCRIPT.new()
	state.call(&"reset")
	state.call(&"new_company", "Auto SRL")
	state.set(&"money", money)
	var side := Node.new()
	side.name = label
	root.add_child(side)
	side.add_child(state)
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	net.company = state
	side.add_child(net)
	var clock := GameClock.new()
	clock.name = "GameClock"
	clock.ticks = func() -> int: return _now
	side.add_child(clock)
	var cycle := DayCycle.new()
	cycle.name = "DayCycle"
	cycle.ticks = func() -> int: return _now
	side.add_child(cycle)
	_expect(clock.attach(net, state) and cycle.attach(net, clock, state), "%s: clock and cycle attach" % label)
	net.supplier.products = _closing_catalog()
	net.supplier.supplier = null
	var products: Dictionary = net.supplier.products
	net.inventory.receive(&"antique_lamp", 1, &"shelf_a")
	var hook: SupplierAutoOrderHook = SupplierAutoOrderHook.attach(side, net)
	_expect(hook != null, "%s: the hook attaches" % label)
	_expect(cycle.open_day(1), "%s: day 1 opens" % label)
	_now += roundi(CompanyTuning.OPENING_REAL_SECONDS * 1000.0) + 1000
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.OPERATING, "%s: day 1 is OPERATING" % label)
	_add_orders(net, "d1", {&"antique_lamp": 6, &"porcelain_vase": 4}, 20)
	return {"state": state, "net": net, "clock": clock, "cycle": cycle, "hook": hook, "side": side}


## The day's orders come in as order_added events (the hook sees them arrive), one per product, plus one
## cancelled order of `cancelled_mugs` mugs.
func _add_orders(net: CompanyNet, prefix: String, wanted: Dictionary, cancelled_mugs: int) -> void:
	var minute: int = 500
	for id: StringName in wanted:
		var order := Order.make(StringName("%s_%s" % [prefix, id]), "Ana", &"centro", &"centro_house_1",
			[{"product": id, "qty": wanted[id]}], minute, net.supplier.products)
		_expect(net.publish(CompanyOrdersNet.ADDED, {"order": order}), "%s: order of %s comes in" % [prefix, id])
		minute += 20
	var mugs := Order.make(StringName("%s_mug" % prefix), "Cai", &"centro", &"centro_house_3",
		[{"product": &"hen", "qty": cancelled_mugs}], minute, net.supplier.products)
	_expect(net.publish(CompanyOrdersNet.ADDED, {"order": mugs}), "%s: the mugs order comes in" % prefix)
	net.orders.book.cancel(StringName("%s_mug" % prefix))


func _closing_catalog() -> Dictionary:
	return {
		&"antique_lamp": _product(&"antique_lamp", 10),
		&"porcelain_vase": _product(&"porcelain_vase", 5),
		&"hen": _product(&"hen", 2),
	}


func _test_auto_order_close_early() -> void:
	var parts: Dictionary = _closing_side("EarlySide")
	var net: CompanyNet = parts["net"]
	var cycle: DayCycle = parts["cycle"]
	var money: int = int(parts["state"].get(&"money"))
	var seq: int = net.seq
	_expect(net.supplier.schedule.day_count() == 0, "close_early: nothing ordered before the close")
	_expect(cycle.close_early() and cycle.phase() == DayCycle.Phase.CLOSING, "close_early: the day is CLOSING")
	var want: Dictionary = {&"antique_lamp": 5, &"porcelain_vase": 4}
	_expect(net.supplier.schedule.ordered_for(2) == want and net.supplier.schedule.day_count() == 1,
		"close_early: one order for tomorrow with the suggested units (got %s)" % [net.supplier.schedule.to_dict()])
	_expect(net.seq == seq + 2, "close_early: the phase event and the order event (seq +%d)" % (net.seq - seq))
	_expect(int(parts["state"].get(&"money")) == money, "close_early: nothing is charged at the close")
	_expect(net.supplier.auto_units(1) == 9, "close_early: auto_units tells 9 (got %d)" % net.supplier.auto_units(1))
	# A repeated CLOSING event (the shed freezing is one) or a second send() adds nothing.
	net.event_applied.emit(net.seq, CompanyNet.DAY_PHASE, {"day": 1, "phase": "CLOSING", "frozen": true})
	_expect(net.supplier.schedule.ordered_for(2) == want and (parts["hook"] as SupplierAutoOrderHook).send() == 0,
		"a repeated CLOSING does not double the order")
	_now += 1000
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.CLOSING and net.orders.book.open_orders().is_empty()
		and net.supplier.schedule.ordered_for(2) == want,
		"the poll with no trips out closes the day's orders (D-0851) and the day stays CLOSING")
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY and net.supplier.schedule.ordered_for(2) == want
		and not cycle.close_early(), "...nor does the summary, and a second close_early is refused")
	_free(parts)


func _test_auto_order_at_20() -> void:
	var parts: Dictionary = _closing_side("EightSide")
	var net: CompanyNet = parts["net"]
	var cycle: DayCycle = parts["cycle"]
	_expect((parts["clock"] as GameClock).start(float(CompanyTuning.DAY_END_MIN)), "20:00: the clock reads 20:00")
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.CLOSING, "20:00: the day is CLOSING")
	_expect(net.supplier.schedule.ordered_for(2) == {&"antique_lamp": 5, &"porcelain_vase": 4},
		"20:00: the same order as close_early (got %s)" % [net.supplier.schedule.to_dict()])
	cycle.poll()
	_expect(net.supplier.schedule.ordered_for(2) == {&"antique_lamp": 5, &"porcelain_vase": 4},
		"20:00: polling again does not double it")
	_free(parts)


func _test_auto_order_not_needed() -> void:
	var parts: Dictionary = _closing_side("CoveredSide")
	var net: CompanyNet = parts["net"]
	net.inventory.receive(&"antique_lamp", 10, &"shelf_a")
	net.inventory.receive(&"porcelain_vase", 10, &"shelf_a")
	(parts["cycle"] as DayCycle).close_early()
	_expect(net.supplier.schedule.day_count() == 0 and net.supplier.auto_units(1) == 0,
		"stock covers the day: no order (got %s)" % [net.supplier.schedule.to_dict()])
	_free(parts)
	var poor: Dictionary = _closing_side("PoorSide", 150)
	(poor["cycle"] as DayCycle).close_early()
	_expect((poor["net"] as CompanyNet).supplier.schedule.day_count() == 0,
		"money that does not pass the rent and the reserve: no order")
	_free(poor)


func _test_auto_order_already_sent() -> void:
	var parts: Dictionary = _closing_side("SentSide")
	var net: CompanyNet = parts["net"]
	_expect(net.supplier.apply({"order_day": 1, "lines": [{"product": "hen", "qty": 24}], "peer": 1}),
		"someone sent tomorrow's order")
	var seq: int = net.seq
	(parts["cycle"] as DayCycle).close_early()
	_expect(net.supplier.schedule.ordered_for(2) == {&"hen": 24} and net.supplier.auto_units(1) == 0
		and net.seq == seq + 1,
		"an order already sent: the close adds nothing (got %s)" % [net.supplier.schedule.to_dict()])
	_free(parts)


func _test_auto_order_client() -> void:
	var parts: Dictionary = _closing_side("ClientSide")
	var net: CompanyNet = parts["net"]
	var peer := FakeClientPeer.new()
	root.multiplayer.multiplayer_peer = peer
	_expect(not net.is_host(), "the net is a client's: connected, but not the server")
	var seq: int = net.seq
	net.event_applied.emit(seq, CompanyNet.DAY_PHASE, {"day": 1, "phase": "CLOSING", "frozen": false})
	var hook: SupplierAutoOrderHook = parts["hook"]
	_expect(net.supplier.schedule.day_count() == 0 and net.seq == seq and hook.send() == 0,
		"a client's hook orders nothing")
	root.multiplayer.multiplayer_peer = null
	_free(parts)


## Two days in a row: the book keeps day 1's orders, but day 2's order only counts day 2's.
func _test_auto_order_two_days() -> void:
	var parts: Dictionary = _closing_side("TwoDaysSide")
	var net: CompanyNet = parts["net"]
	var cycle: DayCycle = parts["cycle"]
	cycle.close_early()
	_expect(net.supplier.schedule.ordered_for(2) == {&"antique_lamp": 5, &"porcelain_vase": 4},
		"two days: day 1 orders for day 2")
	_now += 1000
	cycle.poll()  # D-0851: this poll closes day 1's orders; SUMMARY comes with the next one.
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY and cycle.next_day(), "two days: day 2 opens")
	_now += roundi(CompanyTuning.OPENING_REAL_SECONDS * 1000.0) + 1000
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.OPERATING and cycle.current_day() == 2, "two days: day 2 is OPERATING")
	_expect(net.orders.book.size() == 0, "two days: day 1's orders closed at its end and pruned at day 2's opening")
	net.inventory.receive(&"antique_lamp", 3, &"shelf_a")
	_add_orders(net, "d2", {&"antique_lamp": 6}, 15)
	cycle.close_early()
	# Day 2 asked 6 lamps with 1 + 3 = 4 in stock: 2, not day 1's 6 lamps and 4 vases again.
	_expect(net.supplier.schedule.ordered_for(3) == {&"antique_lamp": 2},
		"two days: day 2 orders only its own (got %s)" % [net.supplier.schedule.to_dict()])
	_expect(net.supplier.auto_units(2) == 2
		and net.supplier.schedule.ordered_for(2) == {&"antique_lamp": 5, &"porcelain_vase": 4},
		"two days: units told per day, day 2's truck untouched")
	_free(parts)


func _test_summary_line() -> void:
	var panel := DaySummaryPanel.new()
	root.add_child(panel)
	var summary: Dictionary = {"day": 1}
	panel.refresh(summary, [], 9)
	var found: Array[Node] = panel.find_children("AutoOrder", "Label", true, false)
	_expect(found.size() == 1, "the summary has its automatic order line")
	if found.size() == 1:
		var label: Label = found[0] as Label
		_expect(label.visible and label.text.contains("9"), "...shown with 9 units (got '%s')" % label.text)
		_expect(label.text != "UI_FINANCE_AUTO_ORDER", "...and translated")
		panel.refresh(summary, [], 0)
		_expect(not label.visible, "...hidden when the host sent none")
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		_expect(TranslationServer.translate("UI_FINANCE_AUTO_ORDER") != "UI_FINANCE_AUTO_ORDER",
			"%s has the line" % locale)
	TranslationServer.set_locale("es")
	panel.queue_free()


func _catalog() -> Dictionary:
	return {
		&"lamp": _product(&"lamp", 10),
		&"vase": _product(&"vase", 5),
		&"mug": _product(&"mug", 2),
	}


func _free(parts: Dictionary) -> void:
	(parts["side"] as Node).queue_free()


func _product(id: StringName, price: int) -> ProductDefinition:
	var def := ProductDefinition.new()
	def.id = id
	def.buy_price = price
	return def


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
