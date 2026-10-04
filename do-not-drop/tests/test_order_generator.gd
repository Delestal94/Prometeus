extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_generator.gd
##
## Day order generator (expansion D-0801, order_generator.gd):
## - the same seed, crew and zones give the same orders; another seed, others;
## - one order per arrival minute of OrderRhythm, sorted, all valid (Order.validate);
## - only the unlocked zones appear, and a zone without deliveries never does;
## - fragile and cold products bring their requirement; "urgent" halves the window
##   and every requirement raises the pay over the plain sum;
## - max_items caps the distinct products; every product and zone exists.

var _failures: int = 0
var _products: Dictionary = {}
var _reqs: Dictionary = {}
var _zones: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_load_catalogs()
	_test_determinism()
	_test_validity_and_arrival()
	_test_zones()
	_test_requirements()
	_test_max_items()
	_test_empty_inputs()
	quit(_failures)


func _load_catalogs() -> void:
	for file in DirAccess.get_files_at("res://data/products"):
		if file.ends_with(".tres"):
			var def: ProductDefinition = load("res://data/products/" + file)
			_products[def.id] = def
	for file in DirAccess.get_files_at("res://data/order_requirements"):
		if file.ends_with(".tres"):
			var req: OrderRequirement = load("res://data/order_requirements/" + file)
			_reqs[req.id] = req
	for file in DirAccess.get_files_at("res://data/zones"):
		if file.ends_with(".tres"):
			var zone: ZoneDefinition = load("res://data/zones/" + file)
			_zones[zone.id] = zone


func _open() -> Array[ZoneDefinition]:
	var out: Array[ZoneDefinition] = []
	out.append(_zones[&"centro"])
	out.append(_zones[&"campo"])
	return out


func _day(day_seed: int, players: int = 3) -> Array[Dictionary]:
	return OrderGenerator.generate_day(day_seed, 1, players, _open(), _products, _reqs)


func _test_determinism() -> void:
	var first := _day(7)
	var again := _day(7)
	_expect(first == again, "same seed, same orders")
	_expect(_day(7) != _day(8), "another seed, other orders")
	_expect(_day(7, 2) != _day(7, 4), "crew size changes the day")


func _test_validity_and_arrival() -> void:
	var minutes := OrderRhythm.arrival_minutes(7, 3)
	var orders := _day(7)
	_expect(orders.size() == minutes.size(), "one order per arrival minute")
	var ids: Dictionary = {}
	for index in orders.size():
		var order: Dictionary = orders[index]
		_expect(Order.validate(order).is_empty(), "order %s is valid" % order["id"])
		_expect(int(order["created_min"]) == minutes[index], "created at its arrival minute")
		_expect(order["state"] == Order.STATE_OPEN, "starts open")
		ids[order["id"]] = true
		for item: Dictionary in order["items"]:
			_expect(_products.has(item["product"]), "product exists")
	_expect(ids.size() == orders.size(), "ids are unique")


func _test_zones() -> void:
	var seen: Dictionary = {}
	for seed_value in 40:
		for order in _day(seed_value):
			seen[order["zone"]] = true
	_expect(seen.has(&"centro") and seen.has(&"campo"), "both open zones get orders")
	_expect(seen.size() == 2, "only the open zones appear")
	var only_depot: Array[ZoneDefinition] = []
	only_depot.append(_zones[&"parque_industrial"])
	_expect(
		OrderGenerator.generate_day(1, 1, 3, only_depot, _products, _reqs).is_empty(),
		"a zone without deliveries gives no orders"
	)


func _test_requirements() -> void:
	var fragile_seen := 0
	var urgent_seen := 0
	for seed_value in 60:
		for order in _day(seed_value):
			var reqs: Array = order["requirements"]
			var plain := 0
			for item: Dictionary in order["items"]:
				var def: ProductDefinition = _products[item["product"]]
				plain += def.get_sell_price() * int(item["qty"])
				if def.fragile:
					_expect(&"fragile" in reqs, "fragile product brings the fragile requirement")
					fragile_seen += 1
			plain += int(Order.SHIPPING_FEE.get(order["zone"], 0))
			var window: int = int(order["due_min"]) - int(order["created_min"])
			if &"urgent" in reqs:
				urgent_seen += 1
				_expect(window == CompanyTuning.ORDER_WINDOW_MIN / 2, "urgent halves the window")
			else:
				_expect(window == CompanyTuning.ORDER_WINDOW_MIN, "normal window is 4 h")
			if reqs.is_empty():
				_expect(int(order["pay"]) == plain, "no requirement, plain pay")
			else:
				_expect(int(order["pay"]) > plain, "a requirement raises the pay")
	_expect(fragile_seen > 0, "some fragile product was ordered")
	_expect(urgent_seen > 0, "some urgent order appeared")


func _test_max_items() -> void:
	for seed_value in 30:
		for order in OrderGenerator.generate_day(seed_value, 1, 4, _open(), _products, _reqs, 1):
			_expect(order["items"].size() == 1, "max_items 1 gives single-product orders")
	var widest := 0
	for seed_value in 30:
		for order in _day(seed_value):
			widest = maxi(widest, order["items"].size())
	_expect(widest == CompanyTuning.ORDER_ITEMS_MAX, "orders reach 3 distinct products")


func _test_empty_inputs() -> void:
	_expect(OrderGenerator.generate_day(1, 1, 3, _open(), {}, _reqs).is_empty(), "no products, no orders")
	var none: Array[ZoneDefinition] = []
	_expect(OrderGenerator.generate_day(1, 1, 3, none, _products, _reqs).is_empty(), "no zones, no orders")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
