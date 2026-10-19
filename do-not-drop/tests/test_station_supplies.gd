extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_station_supplies.gd
##
## Supplies of a packing table (expansion D-0718, station_supplies.gd):
## - a table starts fully stocked (SUPPLY_CAPACITY) and every kind has a capacity;
## - take() uses units up and refuses, changing nothing, past what is left;
## - the dispenser, seal() and pad() use up boxes, tape and padding, and refuse with none left;
## - a refused step (broke wallet) does not use up stock;
## - low_kinds() flags what is at or under SUPPLY_LOW_RATIO; restock() / restock_all() refill
##   for free (no money moves);
## - the stock travels in to_dict() / from_dict(), also through JSON; an old save without it
##   comes back full.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_stock()
	_test_dispenser(state)
	_test_tape(state)
	_test_pad(state)
	_test_low_and_restock(state)
	_test_save()
	state.reset()
	if _failures == 0:
		print("PASS: packing table supplies run out and are restocked")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_stock() -> void:
	var supplies: StationSupplies = StationSupplies.full()
	for kind: StringName in CompanyTuning.SUPPLY_CAPACITY:
		_expect(supplies.count(kind) == CompanyTuning.SUPPLY_CAPACITY[kind], "%s starts full" % kind)
	for size: StringName in BoxDispenser.SIZES:
		_expect(StationSupplies.is_kind(StationSupplies.box_kind(size)), "%s box is tracked" % size)
	_expect(not StationSupplies.is_kind(&"glue"), "unknown kind is not tracked")
	var tape: int = supplies.count(StationSupplies.TAPE)
	_expect(supplies.take(StationSupplies.TAPE, 3), "take 3 tape")
	_expect(supplies.count(StationSupplies.TAPE) == tape - 3, "3 tape gone")
	_expect(not supplies.take(StationSupplies.TAPE, tape), "cannot take more than is left")
	_expect(supplies.count(StationSupplies.TAPE) == tape - 3, "refused take changes nothing")
	_expect(not supplies.take(&"glue"), "unknown kind refused")
	_expect(not supplies.take(StationSupplies.TAPE, 0), "taking 0 refused")


func _test_dispenser(state: Node) -> void:
	state.new_company("Boxes")
	state.earn(1000, &"test")
	var table: PackingStation = PackingStation.make(&"s1")
	var kind: StringName = StationSupplies.box_kind(&"S")
	var capacity: int = CompanyTuning.SUPPLY_CAPACITY[kind]
	for i: int in capacity:
		_expect(BoxDispenser.dispense(table, &"S", state), "S box %d dispensed" % i)
		table.take_box()
	_expect(table.supplies.count(kind) == 0, "all S boxes used")
	var money: int = state.money
	_expect(not BoxDispenser.can_dispense(table, &"S", state), "no S box left")
	_expect(not BoxDispenser.dispense(table, &"S", state), "dispenser refuses without stock")
	_expect(not table.has_box() and state.money == money, "nothing changed without stock")
	_expect(BoxDispenser.dispense(table, &"M", state), "another size still works")
	_expect(table.supplies.restock(kind) == capacity, "restock returns the units added")
	table.take_box()
	_expect(BoxDispenser.dispense(table, &"S", state), "dispenses again after restocking")


func _test_tape(state: Node) -> void:
	state.new_company("Tape")
	state.earn(1000, &"test")
	var table: PackingStation = PackingStation.make(&"s2")
	var rolls: int = CompanyTuning.SUPPLY_CAPACITY[StationSupplies.TAPE]
	for i: int in rolls:
		table.start_box(&"S")
		_expect(table.seal(state), "seal %d" % i)
		table.take_box()
	_expect(table.supplies.count(StationSupplies.TAPE) == 0, "all tape used")
	table.start_box(&"S")
	var money: int = state.money
	_expect(not table.seal(state), "seal refused without tape")
	_expect(not table.is_sealed() and state.money == money, "nothing changed without tape")
	table.supplies.restock(StationSupplies.TAPE)
	_expect(table.seal(state), "seal works after restocking")
	var tape: int = table.supplies.count(StationSupplies.TAPE)
	_expect(not table.seal(state), "second seal refused")
	_expect(table.supplies.count(StationSupplies.TAPE) == tape, "a refused seal keeps the tape")
	# A broke wallet does not use up a roll either.
	var poor: PackingStation = PackingStation.make(&"s3")
	poor.start_box(&"S")
	state.new_company("Broke")
	state.spend(state.money, &"test")
	_expect(not poor.seal(state), "broke wallet cannot seal")
	_expect(poor.supplies.count(StationSupplies.TAPE) == rolls, "no tape used when it cannot pay")


func _test_pad(state: Node) -> void:
	state.new_company("Pad")
	state.earn(1000, &"test")
	var table: PackingStation = PackingStation.make(&"s4")
	_expect(table.pad(2, state) == 0, "no box, no padding")
	table.start_box(&"M")
	_expect(table.pad(5, state) == 5, "pads 5 cells")
	var fill_cap: int = CompanyTuning.SUPPLY_CAPACITY[StationSupplies.FILL]
	_expect(table.supplies.count(StationSupplies.FILL) == fill_cap - 5, "5 padding used")
	table.supplies.take(StationSupplies.FILL, table.supplies.count(StationSupplies.FILL) - 2)
	var money: int = state.money
	_expect(table.pad(10, state) == 2, "padding is limited to what is left")
	_expect(table.supplies.count(StationSupplies.FILL) == 0, "padding ran out")
	_expect(state.money == money - 2 * CompanyTuning.FILL_COST_PER_CELL, "only 2 cells charged")
	_expect(table.pad(3, state) == 0, "nothing left to pad with")
	table.supplies.restock(StationSupplies.FILL)
	state.new_company("Broke")
	state.spend(state.money, &"test")
	var stock: int = table.supplies.count(StationSupplies.FILL)
	_expect(table.pad(3, state) == 0, "broke wallet pads nothing")
	_expect(table.supplies.count(StationSupplies.FILL) == stock, "no padding used when it cannot pay")


func _test_low_and_restock(state: Node) -> void:
	var supplies: StationSupplies = StationSupplies.full()
	_expect(supplies.low_kinds().is_empty(), "a full table is not low")
	supplies.take(StationSupplies.TAPE, supplies.count(StationSupplies.TAPE) - 2)
	supplies.take(StationSupplies.box_kind(&"XL"), 3)
	_expect(supplies.is_low(StationSupplies.TAPE), "2 of 10 tape is low")
	_expect(supplies.is_low(StationSupplies.box_kind(&"XL")), "no XL box is low")
	_expect(not supplies.is_low(StationSupplies.FILL), "padding is not low")
	_expect(supplies.low_kinds().size() == 2, "two kinds to restock")
	state.new_company("Free restock")
	var money: int = state.money
	var added: int = supplies.restock_all()
	_expect(added == 8 + 3, "restock_all adds what was missing")
	_expect(supplies.low_kinds().is_empty(), "nothing low after restocking")
	_expect(state.money == money, "restocking moves no money")
	_expect(supplies.restock(&"glue") == 0, "restocking an unknown kind adds nothing")
	_expect(supplies.restock(StationSupplies.TAPE) == 0, "restocking a full kind adds nothing")


func _test_save() -> void:
	var table: PackingStation = PackingStation.make(&"s5")
	table.supplies.take(StationSupplies.TAPE, 4)
	table.supplies.take(StationSupplies.box_kind(&"L"), 4)
	var json: String = JSON.stringify(table.to_dict())
	var back: PackingStation = PackingStation.from_dict(JSON.parse_string(json))
	_expect(back != null, "table comes back")
	_expect(back.supplies.count(StationSupplies.TAPE) == 6, "tape survives JSON")
	_expect(back.supplies.count(StationSupplies.box_kind(&"L")) == 0, "empty kind survives JSON")
	_expect(back.supplies.count(StationSupplies.FILL) == 30, "full kind survives JSON")
	var old: Dictionary = table.to_dict()
	old.erase("supplies")
	var legacy: PackingStation = PackingStation.from_dict(old)
	_expect(legacy.supplies.low_kinds().is_empty(), "a save without supplies comes back full")
	var wild: StationSupplies = StationSupplies.from_dict({"tape": 999, "fill": -5})
	_expect(wild.count(StationSupplies.TAPE) == 10, "over capacity is clamped")
	_expect(wild.count(StationSupplies.FILL) == 0, "negative is clamped to 0")
