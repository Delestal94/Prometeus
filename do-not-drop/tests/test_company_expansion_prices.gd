extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_expansion_prices.gd
##
## Shed expansion prices of the company shop (expansion D-0514, data/shop/):
## - three expansions at 800, 2000 and 5000 (economia.md section 4), one per stage 1 to 3,
##   each a valid expansion item with a name in both languages;
## - the shop price is the same number as WarehouseStages.price_for(stage), so the two ways of
##   upgrading never disagree;
## - each step costs 2 to 3 times the previous one (the scale rule);
## - the shop sells them in order: stage 2 is refused before stage 1, and buying all three charges
##   7800 with motive shop and leaves the shed at the last stage;
## - a refusal (not enough money) charges nothing.

const DIR: String = "res://data/shop"
const PRICES: Dictionary = {1: 800, 2: 2000, 3: 5000}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var items: Dictionary = {}
	for stage: int in PRICES:
		var key := StringName("expansion_%d" % stage)
		var item: ShopItem = load("%s/%s.tres" % [DIR, key]) as ShopItem
		_expect(item != null, "%s loads" % key)
		if item == null:
			continue
		items[stage] = item
		_expect(item.is_valid(), "%s is valid" % key)
		_expect(item.id == key and item.kind == &"expansion" and item.stage == stage,
			"%s is stage %d" % [key, stage])
		_expect(item.price == PRICES[stage], "%s costs %s" % [key, PRICES[stage]])
		_expect(item.price == WarehouseStages.price_for(stage), "%s matches WarehouseStages" % key)
		_expect(tr(CompanyShop.name_key(item)) != CompanyShop.name_key(item), "%s has a name" % key)
		_expect(CompanyShop.find(key) != null, "%s is on sale" % key)
	if items.size() == PRICES.size():
		for stage: int in [2, 3]:
			var ratio: float = float(items[stage].price) / float(items[stage - 1].price)
			_expect(ratio >= 2.0 and ratio <= 3.0,
				"stage %d costs 2-3x stage %d (%.2f)" % [stage, stage - 1, ratio])
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	if items.size() == PRICES.size():
		state.new_company("Expansion Co")
		state.money = 900
		var skipped: Dictionary = CompanyShop.buy(state, items[2])
		_expect(not skipped["ok"] and skipped["key"] == CompanyShop.WRONG_STAGE,
			"stage 2 needs stage 1 first")
		_expect(CompanyShop.buy(state, items[1])["ok"] and state.money == 100, "stage 1 charges 800")
		var poor: Dictionary = CompanyShop.buy(state, items[2])
		_expect(not poor["ok"] and poor["key"] == CompanyShop.CANNOT_AFFORD, "stage 2 needs 2000")
		_expect(state.money == 100 and state.warehouse_stage == 1, "a refusal charges nothing")
		state.money = 7000
		_expect(CompanyShop.buy(state, items[2])["ok"] and CompanyShop.buy(state, items[3])["ok"],
			"the last two go in order")
		_expect(state.money == 0 and state.warehouse_stage == 3, "7800 in all, shed at the last stage")
		_expect(state.ledger_total(&"shop") == -7800, "the ledger says shop")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
