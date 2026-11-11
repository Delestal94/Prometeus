extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_vehicle_prices.gd
##
## Vehicle prices of the company shop (expansion D-0512, data/shop/vehicle_*.tres):
## - one valid vehicle item per fleet vehicle, with the prices of economia.md section 4
##   and flota.md (bike 250, cart 900, 4x4 2500, boat 5000, plane 12000, extra van 1500);
## - bike < cart < 4x4 < boat < plane, each step 2 to 3.6 times the previous (the scale rule);
## - they stay out of the shop (enabled = false) until their vehicle exists, and buying one
##   still charges the price and adds a {vehicle: fleet_key} entry to the fleet;
## - every item has a name in both languages.

const DIR: String = "res://data/shop"
const PRICES: Dictionary = {
	&"van": 1500, &"bike": 250, &"cart": 900, &"offroad": 2500, &"boat": 5000, &"plane": 12000,
}
const LADDER: Array[StringName] = [&"bike", &"cart", &"offroad", &"boat", &"plane"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var by_key: Dictionary = {}
	for key: StringName in PRICES:
		var item: ShopItem = load("%s/vehicle_%s.tres" % [DIR, key]) as ShopItem
		_expect(item != null, "vehicle_%s loads" % key)
		if item == null:
			continue
		by_key[key] = item
		_expect(item.is_valid(), "vehicle_%s is valid" % key)
		_expect(item.kind == &"vehicle" and item.grant_key == key, "vehicle_%s grants %s" % [key, key])
		_expect(item.price == PRICES[key], "vehicle_%s costs %s" % [key, PRICES[key]])
		_expect(not item.enabled, "vehicle_%s stays out of the shop until its vehicle exists" % key)
		_expect(CompanyShop.find(item.id) == null, "vehicle_%s is not listed" % key)
		_expect(tr(CompanyShop.name_key(item)) != CompanyShop.name_key(item), "vehicle_%s has a name" % key)
	if by_key.size() == PRICES.size():
		for i: int in range(1, LADDER.size()):
			var ratio: float = float(by_key[LADDER[i]].price) / float(by_key[LADDER[i - 1]].price)
			_expect(ratio >= 2.0 and ratio <= 3.6, "%s costs 2-3.6x %s (%.2f)" % [LADDER[i], LADDER[i - 1], ratio])
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Prices Co")
	state.money = 1000
	var bike: ShopItem = by_key.get(&"bike")
	if bike != null:
		var bought: Dictionary = CompanyShop.buy(state, bike)
		_expect(bought["ok"] and state.money == 750, "buying the bike charges 250")
		_expect(state.fleet.has({"vehicle": &"bike"}), "the bike joins the fleet")
		_expect(state.ledger_total(&"shop") == -250, "the ledger says shop")
		_expect(CompanyShop.buy(state, bike)["ok"], "a second bike can be bought")
		var plane: ShopItem = by_key.get(&"plane")
		var refused: Dictionary = CompanyShop.buy(state, plane)
		_expect(not refused["ok"] and refused["key"] == CompanyShop.CANNOT_AFFORD, "the plane needs 12000")
		_expect(state.money == 500, "a refusal charges nothing")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
