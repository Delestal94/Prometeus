extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_generator.gd
##
## Day order generator (expansion D-0801, order_generator.gd):
## - the same seed, crew and zones give the same orders; another seed, others;
## - one order per arrival minute of OrderRhythm, sorted, all valid (Order.validate);
## - only the unlocked zones appear, and a zone without deliveries never does;
## - fragile and cold products bring their requirement; "urgent" halves the window
##   and every requirement raises the pay over the plain sum;
## - the first days (D-0812) cap orders at 2 products, later days at 3;
## - max_items caps the distinct products; every product and zone exists;
## - with order templates (D-0820.b) each order of a zone with a set matches one of its templates
##   (products, quantities, requirements), within the day's item cap, deterministically; a zone
##   without a set still draws at random;
## - with the fixed map (HouseMap, D-2016.2) every order names a house of its own zone on the map, the
##   same ones on every run, and the rest of each order (id, zone, products, minute) is the same as
##   without the map; a zone with no house on it keeps "<zone>_house_<n>".

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
	_test_early_days()
	_test_empty_inputs()
	_test_templates()
	_test_map_houses()
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
	return OrderGenerator.generate_day(day_seed, 4, players, _open(), _products, _reqs)


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


func _test_early_days() -> void:
	_expect(OrderGenerator.items_cap_for_day(1) == CompanyTuning.ORDER_ITEMS_EARLY_MAX, "day 1 cap is 2")
	_expect(OrderGenerator.items_cap_for_day(CompanyTuning.ORDER_EARLY_DAYS) == 2, "last early day cap is 2")
	_expect(OrderGenerator.items_cap_for_day(CompanyTuning.ORDER_EARLY_DAYS + 1) == 3, "later days cap is 3")
	var widest_early := 0
	for day in range(1, CompanyTuning.ORDER_EARLY_DAYS + 1):
		for seed_value in 30:
			for order in OrderGenerator.generate_day(seed_value, day, 4, _open(), _products, _reqs):
				widest_early = maxi(widest_early, order["items"].size())
				_expect(order["items"].size() >= 1, "early orders still have a product")
	_expect(widest_early == 2, "early days reach 2 products and never 3")
	var forced := OrderGenerator.generate_day(5, 1, 4, _open(), _products, _reqs, 3)
	var widest_forced := 0
	for seed_value in 30:
		for order in OrderGenerator.generate_day(seed_value, 1, 4, _open(), _products, _reqs, 3):
			widest_forced = maxi(widest_forced, order["items"].size())
	_expect(forced.size() > 0 and widest_forced == 3, "an explicit max_items overrides the day")


func _test_empty_inputs() -> void:
	_expect(OrderGenerator.generate_day(1, 1, 3, _open(), {}, _reqs).is_empty(), "no products, no orders")
	var none: Array[ZoneDefinition] = []
	_expect(OrderGenerator.generate_day(1, 1, 3, none, _products, _reqs).is_empty(), "no zones, no orders")


func _test_templates() -> void:
	var templates: Dictionary = {}
	for set_res in OrderTemplateCheck.load_sets():
		templates[set_res.zone] = set_res
	_expect(templates.has(&"centro") and templates.has(&"campo"), "sets for centro and campo load")
	var from_templates := 0
	for seed_value in 20:
		for day in [1, 4]:
			var cap: int = OrderGenerator.items_cap_for_day(day)
			var orders := OrderGenerator.generate_day(seed_value, day, 3, _open(), _products, _reqs, 0, null, templates)
			var again := OrderGenerator.generate_day(seed_value, day, 3, _open(), _products, _reqs, 0, null, templates)
			_expect(orders == again, "templates: same seed, same orders")
			for order in orders:
				var set_res: OrderTemplateSet = templates[order["zone"]]
				var found := false
				for template in set_res.templates:
					if template.items == order["items"] and template.requirements == order["requirements"]:
						found = true
				_expect(found, "order matches a template of its zone")
				from_templates += 1
				_expect((order["items"] as Array).size() <= cap, "template within the day's item cap")
	_expect(from_templates > 0, "orders were drawn from templates")
	var plain := OrderGenerator.generate_day(3, 4, 3, _open(), _products, _reqs)
	_expect(plain == _day(3), "no templates keeps the random draw")


func _test_map_houses() -> void:
	var houses: HouseMap = HouseMap.load_default()
	_expect(houses != null and not houses.in_zone(&"centro").is_empty(), "the fixed map has houses in Centro")
	for seed_value in [1, 7, 42]:
		var plain := OrderGenerator.generate_day(seed_value, 4, 4, _open(), _products, _reqs)
		var mapped := OrderGenerator.generate_day(seed_value, 4, 4, _open(), _products, _reqs, 0, null, {}, houses)
		var again := OrderGenerator.generate_day(seed_value, 4, 4, _open(), _products, _reqs, 0, null, {}, houses)
		_expect(mapped == again, "map houses are deterministic (seed %d)" % seed_value)
		_expect(mapped.size() == plain.size(), "the map changes no order count (seed %d)" % seed_value)
		for i in mapped.size():
			var house: HouseSpot = houses.spot(mapped[i]["house_id"])
			_expect(house != null and house.zone == mapped[i]["zone"],
				"%s names a map house of its zone (got %s)" % [mapped[i]["id"], mapped[i]["house_id"]])
			for key in ["id", "zone", "items", "created_min", "requirements"]:
				_expect(mapped[i][key] == plain[i][key], "%s keeps its %s with the map" % [mapped[i]["id"], key])
	var empty := HouseMap.new()
	for order in OrderGenerator.generate_day(3, 4, 3, _open(), _products, _reqs, 0, null, {}, empty):
		_expect(String(order["house_id"]).begins_with(String(order["zone"]) + "_house_"),
			"a zone with no map house keeps <zone>_house_<n> (got %s)" % order["house_id"])


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
