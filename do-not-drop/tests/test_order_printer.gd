extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_printer.gd
##
## The order printer of the shed (expansion D-0805, order_printer.gd):
## - feed() prints one sheet per open or late order, in arrival order, once each; delivered,
##   failed and unknown entries print nothing and a second feed prints nothing new;
## - the tray holds PRINTER_TRAY_MAX sheets: when full the printer jams, the rest stay pending
##   and print as soon as a sheet is taken;
## - take() moves a sheet from the tray to a holder (at most SHEETS_IN_HAND_MAX), put_on_table()
##   leaves it on one table (one sheet per table, only the holder who has it), clear_table() frees it;
## - a sheet that was taken is never printed again;
## - to_dict() / from_dict() give back the same printer, even through JSON.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_feed()
	_test_jam()
	_test_hands_and_tables()
	_test_roundtrip()
	if _failures == 0:
		print("PASS: the order printer prints each order once and hands the sheet to a table")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _o(id: String, state: StringName = Order.STATE_OPEN) -> Dictionary:
	return {"id": id, "state": state}


func _test_feed() -> void:
	var p := OrderPrinter.new()
	var orders: Array = [
		_o("a"), _o("b", Order.STATE_LATE), _o("c", Order.STATE_DELIVERED),
		_o("d", Order.STATE_FAILED), {"x": 1}, 5,
	]
	var out := p.feed(orders)
	_expect(out == [&"a", &"b"], "prints open and late in order, got %s" % [out])
	_expect(p.tray() == [&"a", &"b"], "tray has both sheets")
	_expect(p.feed(orders).is_empty(), "a second feed prints nothing new")
	_expect(not p.is_jammed(), "two sheets do not jam")


func _test_jam() -> void:
	var p := OrderPrinter.new()
	var orders: Array = []
	for i in CompanyTuning.PRINTER_TRAY_MAX + 2:
		orders.append(_o("o%d" % i))
	p.feed(orders)
	_expect(p.tray().size() == CompanyTuning.PRINTER_TRAY_MAX, "the tray stops at its limit")
	_expect(p.is_jammed(), "full tray jams the printer")
	_expect(p.pending(orders).size() == 2, "the last two orders wait")
	_expect(p.take(&"o0", &"ana"), "taking a sheet frees room")
	_expect(not p.is_jammed(), "no longer jammed")
	_expect(p.feed(orders) == [&"o4"], "the next waiting order prints")
	_expect(not p.pending(orders).has(&"o0"), "a taken sheet is not pending again")


func _test_hands_and_tables() -> void:
	var p := OrderPrinter.new()
	var orders: Array = []
	for i in 4:
		orders.append(_o("o%d" % i))
	p.feed(orders)
	_expect(not p.take(&"nope", &"ana"), "cannot take a sheet that is not in the tray")
	for i in CompanyTuning.SHEETS_IN_HAND_MAX:
		_expect(p.take(StringName("o%d" % i), &"ana"), "ana takes sheet %d" % i)
	_expect(not p.take(&"o3", &"ana"), "hand limit reached")
	_expect(p.take(&"o3", &"beto"), "another person can still take one")
	_expect(not p.put_on_table(&"o0", &"beto", &"t1"), "only the holder can leave it")
	_expect(p.put_on_table(&"o0", &"ana", &"t1"), "ana leaves o0 on table 1")
	_expect(p.table_order(&"t1") == &"o0", "table 1 shows o0")
	_expect(not p.put_on_table(&"o1", &"ana", &"t1"), "one sheet per table")
	_expect(not p.put_on_table(&"o0", &"ana", &"t2"), "a sheet on a table is no longer carried")
	_expect(p.sheets_of(&"ana") == [&"o1", &"o2"], "ana keeps the rest")
	_expect(p.clear_table(&"t1") and p.table_order(&"t1") == &"", "clearing frees the table")
	_expect(not p.clear_table(&"t1"), "clearing an empty table says so")


func _test_roundtrip() -> void:
	var p := OrderPrinter.new()
	p.feed([_o("a"), _o("b"), _o("c")])
	p.take(&"a", &"ana")
	p.take(&"b", &"ana")
	p.put_on_table(&"b", &"ana", &"t1")
	var back := OrderPrinter.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	_expect(back.tray() == [&"c"], "tray survives")
	_expect(back.sheets_of(&"ana") == [&"a"], "carried survives")
	_expect(back.table_order(&"t1") == &"b", "table survives")
	_expect(back.feed([_o("a"), _o("b"), _o("c")]).is_empty(), "printed set survives")
	_expect(back.to_dict() == p.to_dict(), "same dictionary")
