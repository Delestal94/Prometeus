extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_machine_prices.gd
##
## Machine prices of the company shop (expansion D-0513, data/shop/):
## - label reader 600, conveyor belt 1500 and packing machine 4000 (economia.md section 4),
##   each a valid machine item that grants its own equipment key and has a name in both languages;
## - each step costs 2 to 3 times the previous one (the scale rule);
## - the label reader is on sale; the conveyor and the packer stay out of the shop
##   (enabled = false) until their machine exists, but buying one by code still charges the
##   price and adds the key to the company's equipment;
## - a refusal (not enough money) charges nothing.

const DIR: String = "res://data/shop"
const PRICES: Dictionary = {&"label_reader": 600, &"conveyor": 1500, &"packer": 4000}
const LADDER: Array[StringName] = [&"label_reader", &"conveyor", &"packer"]
const ON_SALE: Array[StringName] = [&"label_reader"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var by_key: Dictionary = {}
	for key: StringName in PRICES:
		var item: ShopItem = load("%s/%s.tres" % [DIR, key]) as ShopItem
		_expect(item != null, "%s loads" % key)
		if item == null:
			continue
		by_key[key] = item
		_expect(item.is_valid(), "%s is valid" % key)
		_expect(item.id == key and item.kind == &"machine" and item.grant_key == key, "%s grants itself" % key)
		_expect(item.price == PRICES[key], "%s costs %s" % [key, PRICES[key]])
		_expect(tr(CompanyShop.name_key(item)) != CompanyShop.name_key(item), "%s has a name" % key)
		var listed: bool = CompanyShop.find(key) != null
		_expect(listed == ON_SALE.has(key), "%s is %s" % [key, "on sale" if ON_SALE.has(key) else "off the shelf"])
	if by_key.size() == PRICES.size():
		for i: int in range(1, LADDER.size()):
			var ratio: float = float(by_key[LADDER[i]].price) / float(by_key[LADDER[i - 1]].price)
			_expect(ratio >= 2.0 and ratio <= 3.0, "%s costs 2-3x %s (%.2f)" % [LADDER[i], LADDER[i - 1], ratio])
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Prices Co")
	state.money = 2000
	var conveyor: ShopItem = by_key.get(&"conveyor")
	var packer: ShopItem = by_key.get(&"packer")
	if conveyor != null and packer != null:
		var refused: Dictionary = CompanyShop.buy(state, packer)
		_expect(not refused["ok"] and refused["key"] == CompanyShop.CANNOT_AFFORD, "the packer needs 4000")
		_expect(state.money == 2000 and not state.equipment.has(&"packer"), "a refusal charges nothing")
		var bought: Dictionary = CompanyShop.buy(state, conveyor)
		_expect(bought["ok"] and state.money == 500, "buying the conveyor charges 1500")
		_expect(state.equipment.has(&"conveyor"), "the conveyor joins the equipment")
		_expect(state.ledger_total(&"shop") == -1500, "the ledger says shop")
		_expect(CompanyShop.buy(state, conveyor)["key"] == CompanyShop.ALREADY_OWNED, "it is bought once")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
