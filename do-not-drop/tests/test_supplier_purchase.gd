extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_supplier_purchase.gd
##
## Supplier purchase cost (expansion D-0503, SupplierPurchase):
## - cost() is units x buy_price; unknown products and qty <= 0 cost 0;
## - receiving a pallet puts its units in the inventory and charges its cost
##   to CompanyState with reason &"supplier" (ledger_total reflects it);
## - an invalid, unknown or already received pallet charges nothing;
## - can_order() checks the whole order against the wallet;
## - a pallet that never arrives costs nothing; receiving past the balance
##   goes into the red.

var _failures: int = 0
var _products: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	var def := ProductDefinition.new()
	def.id = &"lamp"
	def.buy_price = 50
	_products = {&"lamp": def}
	_test_cost()
	_test_receive(state)
	_test_can_order_and_red(state)
	state.reset()
	if _failures == 0:
		print("PASS: receiving a pallet charges units x buy price to the supplier ledger")
	quit(_failures)


func _test_cost() -> void:
	_expect(SupplierPurchase.cost(&"lamp", 10, _products) == 500, "10 lamps cost 500")
	_expect(SupplierPurchase.cost(&"lamp", 0, _products) == 0, "zero units cost 0")
	_expect(SupplierPurchase.cost(&"nope", 5, _products) == 0, "unknown product costs 0")
	var pallet := Pallet.make(&"p1", &"lamp", 24)
	_expect(SupplierPurchase.pallet_cost(pallet, _products) == 1200, "a full pallet costs 1200")


func _test_receive(state: Node) -> void:
	state.new_company("Supplier Co")
	var inv := Inventory.new()
	var money: int = state.money
	var pallet := Pallet.make(&"p1", &"lamp", 10)
	_expect(SupplierPurchase.receive(state, inv, pallet, _products), "receive succeeds")
	_expect(state.money == money - 500, "wallet drops by 500")
	_expect(state.ledger_total(&"supplier") == -500, "ledger records -500 as supplier")
	_expect(inv.count(&"lamp", Pallet.location(&"p1")) == 10, "units sit on the pallet")
	_expect(not SupplierPurchase.receive(state, inv, pallet, _products), "second receive refused")
	_expect(state.money == money - 500, "refused receive charges nothing")
	var unknown := Pallet.make(&"p2", &"nope", 3)
	_expect(not SupplierPurchase.receive(state, inv, unknown, _products), "unknown product refused")
	_expect(inv.count(&"nope", Pallet.location(&"p2")) == 0, "unknown product not stocked")
	_expect(not SupplierPurchase.receive(state, inv, {}, _products), "invalid pallet refused")
	_expect(state.money == money - 500, "nothing else charged")


func _test_can_order_and_red(state: Node) -> void:
	state.new_company("Supplier Co")
	state.money = 500
	var orders: Array = [Pallet.make(&"a", &"lamp", 6), Pallet.make(&"b", &"lamp", 6)]
	_expect(not SupplierPurchase.can_order(state, orders, _products), "500 does not cover 300 + 300")
	_expect(SupplierPurchase.can_order(state, orders.slice(0, 1), _products), "300 is covered")
	_expect(state.money == 500, "ordering alone costs nothing")
	var inv := Inventory.new()
	state.money = 100
	_expect(SupplierPurchase.receive(state, inv, orders[0], _products), "delivery goes through")
	_expect(state.money == -200, "balance goes into the red")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
