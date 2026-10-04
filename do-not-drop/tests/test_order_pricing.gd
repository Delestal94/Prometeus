extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_pricing.gd
##
## Order price (expansion D-0502, order_pricing.gd):
## - ten orders priced against the average order of docs/expansion-distritos/diseno/economia.md
##   (2 units sold at 80 + shipping 40 Centro / 60 Campo = 200 / 220, 210 on average);
## - quote() breaks the price into goods, shipping, requirements and urgency, and its
##   total matches the pay Order.make() stores plus the same bonuses;
## - urgency is reported apart from the other requirements; unknown ids add nothing;
## - the condition bonus needs the minimum quality, and settle() adds it to the
##   late-adjusted payout.

var _failures: int = 0
var _products: Dictionary = {}
var _catalog: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var def := ProductDefinition.new()
	def.id = &"avg"
	def.buy_price = 50
	_products[&"avg"] = def
	for file in DirAccess.get_files_at("res://data/order_requirements"):
		if file.ends_with(".tres"):
			var req: OrderRequirement = load("res://data/order_requirements/" + file)
			_catalog[req.id] = req
	_test_ten_orders()
	_test_breakdown()
	_test_condition()
	quit(_failures)


func _test_ten_orders() -> void:
	var total: int = 0
	for i in 10:
		var zone: StringName = &"centro" if i % 2 == 0 else &"campo"
		var items := [{"product": &"avg", "qty": 2}]
		var quote := OrderPricing.quote(items, zone, [], _products, _catalog)
		var order := Order.make(&"o%d" % i, "C", zone, &"h", items, 0, _products)
		_expect(quote["total"] == order["pay"], "order %d: quote equals the pay Order.make stores" % i)
		_expect(quote["goods"] == 160, "order %d: 2 units sell for 160" % i)
		total += int(quote["total"])
	_expect(total == 2100, "ten average orders bring 2100, 210 each (got %d)" % total)


func _test_breakdown() -> void:
	var items := [{"product": &"avg", "qty": 2}]
	var plain := OrderPricing.quote(items, &"centro", [], _products, _catalog)
	_expect(plain["shipping"] == 40 and plain["total"] == 200, "centro: 160 + 40")
	_expect(plain["requirements"] == 0 and plain["urgency"] == 0, "no requirement, no bonus")
	var urgent := OrderPricing.quote(items, &"centro", [&"urgent"], _products, _catalog)
	_expect(urgent["urgency"] == 60 and urgent["requirements"] == 0, "urgent +30 % of 200 is urgency")
	_expect(urgent["total"] == 260, "urgent order pays 260")
	var both := OrderPricing.quote(items, &"centro", [&"fragile", &"urgent"], _products, _catalog)
	_expect(both["requirements"] == 30 and both["urgency"] == 69, "fragile 30, then urgent 30 % of 230")
	_expect(both["total"] == 299, "fragile and urgent pay 299 (got %d)" % both["total"])
	_expect(both["total"] == both["goods"] + both["shipping"] + both["requirements"] + both["urgency"], "parts add up")
	var unknown := OrderPricing.quote(items, &"nowhere", [&"nope"], _products, _catalog)
	_expect(unknown["total"] == 160, "unknown zone and requirement add nothing")
	_expect(OrderPricing.with_requirements(200, [&"urgent"], _catalog) == 260, "with_requirements applies the bonus")


func _test_condition() -> void:
	_expect(OrderPricing.condition_bonus(200, 89.9) == 0, "below 90 no bonus")
	_expect(OrderPricing.condition_bonus(200, 90.0) == 20, "90 earns +10 %")
	var order := Order.make(
		&"o", "C", &"centro", &"h", [{"product": &"avg", "qty": 2}], 0, _products
	)
	var due: int = int(order["due_min"])
	_expect(OrderPricing.settle(order, due, 100.0) == 220, "on time and well packed: 220")
	_expect(OrderPricing.settle(order, due, 50.0) == 200, "on time, poorly packed: 200")
	_expect(OrderPricing.settle(order, due + 1, 50.0) == 150, "late: -25 %")
	_expect(OrderPricing.settle(order, due + 1, 95.0) == 165, "late but well packed: 150 + 15")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
