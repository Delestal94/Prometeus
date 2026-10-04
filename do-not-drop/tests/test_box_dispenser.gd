extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_dispenser.gd
##
## Box dispenser (expansion D-0702, box_dispenser.gd):
## - dispense() opens an empty box of the chosen size on a free table and charges BOX_COST;
## - it refuses (changing nothing) with an unknown size, a table that already has a box,
##   a wallet that does not cover the box, or a null table or wallet;
## - every offered size exists in BOX_CELLS and BOX_COST.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_sizes()
	_test_dispense(state)
	_test_refusals(state)
	state.reset()
	if _failures == 0:
		print("PASS: dispenser opens a paid box of the chosen size on a free table")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_sizes() -> void:
	for size: StringName in BoxDispenser.SIZES:
		_expect(CompanyTuning.BOX_CELLS.has(size), "%s has cells" % size)
		_expect(BoxDispenser.cost_of(size) >= 0, "%s has a cost" % size)
	_expect(BoxDispenser.cost_of(&"XXL") == -1, "unknown size has no cost")


func _test_dispense(state: Node) -> void:
	state.new_company("Test")
	state.earn(100, &"test")
	var before: int = state.money
	var table: PackingStation = PackingStation.make(&"t1")
	_expect(BoxDispenser.dispense(table, &"L", state), "L box is dispensed")
	_expect(table.has_box(), "box is open on the table")
	_expect(table.box.box_size == &"L", "box has the chosen size")
	_expect(state.money == before - CompanyTuning.BOX_COST[&"L"], "box was charged")
	_expect(state.ledger_total(BoxDispenser.REASON) == -CompanyTuning.BOX_COST[&"L"], "ledger knows why")


func _test_refusals(state: Node) -> void:
	state.new_company("Test")
	state.earn(100, &"test")
	var table: PackingStation = PackingStation.make(&"t2")
	var before: int = state.money
	_expect(not BoxDispenser.dispense(table, &"XXL", state), "unknown size refused")
	_expect(not table.has_box() and state.money == before, "nothing changed for unknown size")
	_expect(BoxDispenser.dispense(table, &"S", state), "S box dispensed")
	var after_first: int = state.money
	_expect(not BoxDispenser.dispense(table, &"M", state), "second box on a busy table refused")
	_expect(state.money == after_first, "no charge for the refused box")
	var poor: PackingStation = PackingStation.make(&"t3")
	state.new_company("Poor")
	state.spend(state.money, &"test")
	_expect(not BoxDispenser.dispense(poor, &"S", state), "broke wallet refused")
	_expect(not poor.has_box(), "no box without paying")
	_expect(not BoxDispenser.dispense(null, &"S", state), "null table refused")
	_expect(not BoxDispenser.dispense(poor, &"S", null), "null wallet refused")
