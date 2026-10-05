extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_packaging_supplies.gd
##
## Packing supplies cost (expansion D-0504, PackagingSupplies):
## - padding charges FILL_COST_PER_CELL for the cells really padded (capped by free cells);
## - taping charges TAPE_COST once; a taped box is not charged again;
## - label and stamps charge their tuning price (0 today) and refuse repeats / empty values;
## - a step the wallet cannot cover changes neither box nor balance;
## - everything lands in the ledger as &"packaging", apart from the &"boxes" of the dispenser;
## - used_cost() matches what was charged.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_pad(state)
	_test_tape_label_stamp(state)
	_test_poor_wallet(state)
	state.reset()
	if _failures == 0:
		print("PASS: padding and tape are charged as packaging supplies")
	quit(_failures)


func _test_pad(state: Node) -> void:
	state.new_company("Packing Co")
	var box := PackedBox.new(&"S")
	var money: int = state.money
	var per_cell: int = CompanyTuning.FILL_COST_PER_CELL
	_expect(PackagingSupplies.fill_cost(5) == 5 * per_cell, "fill_cost is cells x price")
	_expect(PackagingSupplies.fill_cost(-3) == 0, "negative cells cost 0")
	_expect(PackagingSupplies.pad(box, 3, state) == 3, "pads 3 cells")
	_expect(state.money == money - 3 * per_cell, "3 cells charged")
	_expect(state.ledger_total(&"packaging") == -3 * per_cell, "ledger records packaging")
	# S has 2x2x2 = 8 cells: only 5 remain free, so asking for 20 pads and pays 5.
	_expect(PackagingSupplies.pad(box, 20, state) == 5, "padding is capped by free cells")
	_expect(state.money == money - 8 * per_cell, "only padded cells charged")
	_expect(PackagingSupplies.pad(box, 1, state) == 0, "a full box takes no more padding")
	_expect(state.money == money - 8 * per_cell, "full box charges nothing")
	_expect(PackagingSupplies.pad(null, 1, state) == 0, "null box ignored")
	_expect(PackagingSupplies.used_cost(box) == 8 * per_cell, "used_cost counts the padding")


func _test_tape_label_stamp(state: Node) -> void:
	state.new_company("Packing Co")
	var box := PackedBox.new(&"M")
	var money: int = state.money
	_expect(PackagingSupplies.tape(box, state), "tape succeeds")
	_expect(box.taped, "box is taped")
	_expect(state.money == money - CompanyTuning.TAPE_COST, "tape charged")
	_expect(not PackagingSupplies.tape(box, state), "second tape refused")
	_expect(state.money == money - CompanyTuning.TAPE_COST, "second tape charges nothing")
	_expect(PackagingSupplies.label(box, &"order_1", state), "label succeeds")
	_expect(box.label_order_id == &"order_1", "label set")
	_expect(not PackagingSupplies.label(box, &"", state), "empty order id refused")
	_expect(PackagingSupplies.stamp(box, &"fragile", state), "stamp succeeds")
	_expect(not PackagingSupplies.stamp(box, &"fragile", state), "repeated stamp refused")
	_expect(not PackagingSupplies.stamp(box, &"", state), "empty stamp refused")
	_expect(box.stamps.size() == 1, "one stamp on the box")
	var expected: int = CompanyTuning.TAPE_COST + CompanyTuning.LABEL_COST + CompanyTuning.STAMP_COST
	_expect(PackagingSupplies.used_cost(box) == expected, "used_cost sums tape, label and stamp")
	_expect(state.money == money - expected, "balance matches used_cost")
	_expect(state.ledger_total(&"packaging") == -expected, "ledger matches used_cost")


func _test_poor_wallet(state: Node) -> void:
	state.new_company("Packing Co")
	state.money = 2
	var box := PackedBox.new(&"S")
	_expect(PackagingSupplies.pad(box, 3, state) == 0, "3 cells do not fit in 2 coins")
	_expect(box.grid.is_empty(), "box untouched")
	_expect(state.money == 2, "balance untouched")
	_expect(PackagingSupplies.pad(box, 2, state) == 2, "2 cells fit in 2 coins")
	_expect(state.money == 0, "wallet emptied")
	_expect(not PackagingSupplies.tape(box, state), "no money, no tape")
	_expect(not box.taped, "box stays untaped")
	_expect(PackagingSupplies.pad(box, 1, null) == 0, "null wallet ignored")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		_failures += 1
