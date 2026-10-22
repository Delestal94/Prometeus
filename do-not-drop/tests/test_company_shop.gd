extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_shop.gd
##
## Company shop (expansion D-0511, company_shop.gd + data/shop/):
## - the catalog loads valid items in file name order and finds them by id;
## - buying charges the price with reason shop (ledger entry) and grants the item
##   (machine -> equipment, vehicle -> fleet, expansion -> warehouse_stage);
## - refusals leave the company untouched: unknown item, already owned, missing
##   requirement, expansion out of order, not enough money, no company.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	var items: Array[ShopItem] = CompanyShop.items()
	_expect(items.size() >= 3, "the shop has its first items")
	var ids: Array[StringName] = []
	for item: ShopItem in items:
		ids.append(item.id)
		_expect(item.is_valid(), "%s is valid" % item.id)
		_expect(tr(item.display_key) != item.display_key, "%s has a name" % item.id)
	var expected: Array[StringName] = [
		&"expansion_1", &"expansion_2", &"expansion_3", &"label_reader", &"upgrade_1"]
	_expect(ids == expected, "file name order: %s" % [ids])
	_expect(CompanyShop.find(&"upgrade_1").price == 450, "upgrade 1 costs 450 (economia.md §4)")
	_expect(CompanyShop.find(&"nope") == null, "unknown id finds nothing")

	state.new_company("Shop Co")
	state.money = 2000
	var upgrade: ShopItem = CompanyShop.find(&"upgrade_1")
	_expect(CompanyShop.check(state, upgrade)["ok"], "can buy with money")
	var bought: Dictionary = CompanyShop.buy(state, upgrade)
	_expect(bought["ok"] and state.money == 1550, "buying charges 450")
	_expect(state.equipment.has(&"upgrade_1"), "the machine joins equipment")
	_expect(state.ledger_total(&"shop") == -450, "the ledger says shop")
	var again: Dictionary = CompanyShop.buy(state, upgrade)
	_expect(not again["ok"] and again["key"] == CompanyShop.ALREADY_OWNED, "no second copy of a machine")
	_expect(state.money == 1550, "a refusal charges nothing")

	var stage_item: ShopItem = CompanyShop.find(&"expansion_1")
	_expect(CompanyShop.buy(state, stage_item)["ok"] and state.warehouse_stage == 1, "expansion moves the stage")
	var stage_two := ShopItem.new()
	stage_two.id = &"expansion_3"
	stage_two.display_key = "X"
	stage_two.kind = &"expansion"
	stage_two.price = 10
	stage_two.stage = 3
	_expect(CompanyShop.check(state, stage_two)["key"] == CompanyShop.WRONG_STAGE, "expansions go in order")

	var gated := ShopItem.new()
	gated.id = &"gated"
	gated.display_key = "X"
	gated.kind = &"machine"
	gated.price = 10
	gated.grant_key = &"gated"
	gated.requires = &"nothing_yet"
	_expect(CompanyShop.check(state, gated)["key"] == CompanyShop.NEEDS_ITEM, "a requirement blocks it")

	var van := ShopItem.new()
	van.id = &"van_2"
	van.display_key = "X"
	van.kind = &"vehicle"
	van.price = 1500
	van.grant_key = &"van"
	state.money = 1499
	var poor: Dictionary = CompanyShop.buy(state, van)
	_expect(not poor["ok"] and poor["key"] == CompanyShop.CANNOT_AFFORD, "1499 does not buy 1500")
	_expect(state.fleet.is_empty(), "and nothing was granted")
	state.money = 3000
	CompanyShop.buy(state, van)
	CompanyShop.buy(state, van)
	var owned: Array = state.gate_owned()["vehicles"]
	_expect(state.fleet.size() == 3 and owned == [&"van", &"van"],
		"vehicles can be bought again, the first keeping the starting fleet (%s)" % [state.fleet])
	_expect(state.fleet[0].get("id") == CompanyTuning.STARTING_FLEET[0], "...the starting fleet's van ahead of them")
	state.money = 100000
	while state.fleet.size() < CompanyFleet.PLAYON_SLOTS:
		CompanyShop.buy(state, van)
	var full: Dictionary = CompanyShop.buy(state, van)
	_expect(not full["ok"] and full["key"] == CompanyShop.FLEET_FULL
		and state.fleet.size() == CompanyFleet.PLAYON_SLOTS,
		"a vehicle past the playon's slots is refused (FLEET_FULL), nothing granted")

	_expect(CompanyShop.check(null, upgrade)["key"] == CompanyShop.NO_COMPANY, "no company, no purchase")
	state.reset()
	if _failures == 0:
		print("PASS: company shop buys and refuses")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
