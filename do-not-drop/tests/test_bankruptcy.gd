extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_bankruptcy.gd
##
## Bankruptcy (expansion D-0510, bankruptcy.gd):
## - bankrupt only below zero (0 is fine);
## - the next day opens with 60 % of the orders while in the red, all of them otherwise;
## - rounded, never below 1 for a day that has orders, and 0 stays 0;
## - paying the rent into the red (FixedCosts.settle) is what makes it bankrupt;
## - no company, no bankruptcy.

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
	state.reset()
	if _failures == 0:
		print("PASS: bankruptcy opens the next day with fewer orders")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
