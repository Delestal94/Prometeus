extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_bankruptcy.gd
##
## Bankruptcy (expansion D-0510, bankruptcy.gd):
## - bankrupt only below zero (0 is fine);
## - the next day opens with 60 % of the orders while in the red, all of them otherwise;
## - rounded, never below 1 for a day that has orders, and 0 stays 0;
## - paying the rent into the red (FixedCosts.settle) is what makes it bankrupt;
## - no company, no bankruptcy;
## - OrderGenerator.generate_day with the company: in the red it returns orders_for_day(usual)
##   orders (60 %, rounded), a solvent or null company the usual ones, identical to the call
##   without a company; same seed and money, same orders;
## - Bankruptcy.opening_notice is "" at 0 money or more and UI_COMPANY_BANKRUPT_WARNING below zero,
##   and opening_text shows the share filled in;
## - CompanyRoot shows that notice (EventBus.depot_notice) when the day opens in the red.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Broke Co")
	_expect(not Bankruptcy.is_bankrupt(state), "starting money is not bankrupt")
	_expect(Bankruptcy.orders_for_day(10, state) == 10, "a healthy company keeps all its orders")
	state.money = 0
	_expect(not Bankruptcy.is_bankrupt(state), "0 in the wallet is not the red")
	state.money = -1
	_expect(Bankruptcy.is_bankrupt(state), "below zero is bankrupt")
	_expect(is_equal_approx(Bankruptcy.order_share(state), CompanyTuning.BANKRUPT_ORDER_SHARE), "60 % share")
	_expect(Bankruptcy.orders_for_day(10, state) == 6, "10 orders become 6")
	_expect(Bankruptcy.orders_for_day(7, state) == 4, "7 orders round to 4")
	_expect(Bankruptcy.orders_for_day(1, state) == 1, "never below 1")
	_expect(Bankruptcy.orders_for_day(0, state) == 0, "no orders stays no orders")
	state.money = 30
	FixedCosts.settle(state)
	_expect(Bankruptcy.is_bankrupt(state), "the rent into the red makes it bankrupt")
	state.money = 500
	_expect(Bankruptcy.orders_for_day(10, state) == 10, "back in the black, back to all the orders")
	_expect(not Bankruptcy.is_bankrupt(null) and Bankruptcy.orders_for_day(10, null) == 10, "no company, nothing")
	_test_generated_orders(state)
	_test_opening_notice(state)
	state.reset()
	if _failures == 0:
		print("PASS: bankruptcy opens the next day with fewer orders")
	quit(_failures)


func _catalog(dir: String) -> Dictionary:
	var out: Dictionary = {}
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			var res: Resource = load(dir + "/" + file)
			out[res.get("id")] = res
	return out


func _test_generated_orders(state: Node) -> void:
	var products := _catalog("res://data/products")
	var reqs := _catalog("res://data/order_requirements")
	var zones: Array[ZoneDefinition] = [load("res://data/zones/centro.tres"), load("res://data/zones/campo.tres")]
	var usual: int = OrderRhythm.orders_for_day(3)
	state.money = 500
	var plain := OrderGenerator.generate_day(7, 1, 3, zones, products, reqs)
	var solvent := OrderGenerator.generate_day(
		7, 1, 3, zones, products, reqs, CompanyTuning.ORDER_ITEMS_MAX, state)
	var no_company := OrderGenerator.generate_day(
		7, 1, 3, zones, products, reqs, CompanyTuning.ORDER_ITEMS_MAX, null)
	_expect(plain.size() == usual, "no company: the usual count")
	_expect(solvent == plain and no_company == plain, "solvent or null company: the same orders as before")
	state.money = -1
	var red := OrderGenerator.generate_day(7, 1, 3, zones, products, reqs, CompanyTuning.ORDER_ITEMS_MAX, state)
	_expect(red.size() == Bankruptcy.orders_for_day(usual, state), "in the red: orders_for_day(usual)")
	_expect(red.size() == roundi(usual * CompanyTuning.BANKRUPT_ORDER_SHARE) and red.size() < usual, "60 % of 12")
	state.money = -5000
	_expect(red == OrderGenerator.generate_day(
		7, 1, 3, zones, products, reqs, CompanyTuning.ORDER_ITEMS_MAX, state), "same seed and red, same orders")
	for order in red:
		_expect(Order.validate(order).is_empty(), "an order of a bankrupt day is valid")
	state.money = 500


func _test_opening_notice(state: Node) -> void:
	state.money = 0
	_expect(Bankruptcy.opening_notice(state) == "", "no notice at 0")
	_expect(Bankruptcy.opening_text(state) == "", "no text at 0")
	state.money = -1
	_expect(Bankruptcy.opening_notice(state) == "UI_COMPANY_BANKRUPT_WARNING", "notice key in the red")
	var text: String = Bankruptcy.opening_text(state)
	_expect(not text.is_empty() and "%d" not in text, "the text is filled in")
	_expect(Bankruptcy.opening_notice(null) == "", "no company, no notice")
	state.money = 500


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
