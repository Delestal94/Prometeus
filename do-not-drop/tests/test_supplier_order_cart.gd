extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_supplier_order_cart.gd
##
## Supplier order cart (expansion D-0603, SupplierOrderCart):
## - add / set_qty / remove keep units per product; unknown products, products the
##   supplier does not sell, qty < 1 and lines past MAX_LINE_QTY are refused unchanged;
## - lines() come in id order with unit price and cost; total() sums them;
## - pallet_count() splits at PALLET_MAX_UNITS;
## - submit() needs a non-empty cart and a wallet that covers the total, puts the order in
##   the schedule for the next day, empties the cart and charges nothing (D-0503 charges
##   on receipt); a refused submit leaves the cart and the schedule untouched;
## - ordering on day N makes the truck of day N + 1 carry that order's pallets.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	var cart := SupplierOrderCart.new()
	cart.supplier = seller
	cart.products = {&"lamp": lamp, &"vase": vase, &"other": other}
	_test_editing(cart)
	_test_totals(cart)
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_submit(cart, state)
	state.reset()
	if _failures == 0:
		print("PASS: the supplier cart totals, pallets and submits the next-day order")
	quit(_failures)


func _test_editing(cart: SupplierOrderCart) -> void:
	_expect(cart.is_empty(), "starts empty")
	_expect(cart.add(&"lamp", 3), "add 3 lamps")
	_expect(cart.add(&"lamp", 2) and cart.qty(&"lamp") == 5, "adding again sums")
	_expect(not cart.add(&"other", 1), "product the supplier does not sell refused")
	_expect(not cart.add(&"nope", 1), "unknown product refused")
	_expect(not cart.add(&"lamp", 0) and not cart.add(&"lamp", -2), "qty < 1 refused")
	_expect(not cart.add(&"lamp", SupplierOrderCart.MAX_LINE_QTY), "past the line cap refused")
	_expect(cart.qty(&"lamp") == 5, "refusals leave the line alone")
	_expect(cart.remove(&"lamp", 2) and cart.qty(&"lamp") == 3, "remove 2 leaves 3")
	_expect(cart.set_qty(&"vase", 4) and cart.qty(&"vase") == 4, "set_qty sets")
	_expect(not cart.set_qty(&"vase", -1), "negative set_qty refused")
	_expect(cart.set_qty(&"vase", 0) and cart.qty(&"vase") == 0, "set_qty 0 removes")
	_expect(not cart.remove(&"vase"), "removing a missing line refused")
	_expect(cart.remove(&"lamp", 99) and cart.is_empty(), "removing more than there is drops it")


func _test_totals(cart: SupplierOrderCart) -> void:
	cart.add(&"vase", 30)
	cart.add(&"lamp", 2)
	var lines: Array[Dictionary] = cart.lines()
	_expect(lines.size() == 2 and lines[0]["product"] == &"lamp", "lines come in id order")
	_expect(int(lines[0]["unit_price"]) == 50 and int(lines[0]["cost"]) == 100, "lamp line cost")
	_expect(cart.total() == 100 + 600, "total sums the lines")
	_expect(cart.pallet_count() == 3, "30 vases are 2 pallets, 2 lamps 1")
	_expect(cart.to_array().size() == 2, "to_array has the two lines")


func _test_submit(cart: SupplierOrderCart, state: Node) -> void:
	state.new_company("Cart Co")
	var schedule := SupplierSchedule.new()
	var money: int = state.money
	state.money = 10
	_expect(not cart.can_submit(state), "a poor wallet cannot submit")
	_expect(not cart.submit(state, schedule, 3), "poor wallet submit refused")
	_expect(not cart.is_empty() and not schedule.has_delivery(4), "refusal changes nothing")
	state.money = money
	_expect(cart.can_submit(state), "a covered cart can submit")
	_expect(not cart.submit(state, null, 3), "no schedule refused")
	_expect(cart.submit(state, schedule, 3), "submit works")
	_expect(cart.is_empty(), "submit empties the cart")
	_expect(state.money == money, "nothing is charged at order time")
	_expect(not schedule.has_delivery(3) and schedule.has_delivery(4), "it arrives the next day")
	var ordered: Dictionary = schedule.ordered_for(4)
	_expect(ordered.get(&"vase") == 30 and ordered.get(&"lamp") == 2, "the truck carries the order")
	_expect(schedule.pallets_for(4).size() == 3, "the truck brings 3 pallets")
	_expect(not cart.submit(state, schedule, 3), "an empty cart cannot submit")


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + label)
