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
##   in the wallet, empty when the money does not reach them; ordered_units() sums the day's orders.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_solo_arrivals()
	_test_ordered_units()
	_test_suggested()
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
