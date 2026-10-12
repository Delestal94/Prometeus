extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_fixed_costs.gd
##
## Daily fixed costs (expansion D-0509, fixed_costs.gd):
## - the day's cost is the rent from CompanyTuning (100);
## - settle charges it with reason rent and a ledger entry, even into the red;
## - shortfall is what the wallet cannot cover (0 when it can);
## - no company, nothing charged.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_expect(FixedCosts.total_due() == CompanyTuning.RENT_PER_DAY, "the day costs the rent")
	_expect(FixedCosts.due().get(FixedCosts.REASON_RENT) == 100, "rent is 100")
	state.new_company("Rent Co")
	var start: int = state.money
	_expect(FixedCosts.shortfall(state) == 0, "starting money covers the rent")
	_expect(FixedCosts.settle(state) == 100, "settle returns the rent")
	_expect(state.money == start - 100, "the wallet paid it")
	_expect(state.ledger.back().get("reason") == "rent", "the ledger says rent")
	_expect(state.ledger.back().get("amount", 0) == -100 or state.ledger_total(&"rent") == -100, "rent is a cost")
	state.money = 30
	_expect(FixedCosts.shortfall(state) == 70, "30 in the wallet leaves 70 uncovered")
	_expect(FixedCosts.settle(state) == 100 and state.money == -70, "rent goes through into the red")
	state.money = -50
	_expect(FixedCosts.shortfall(state) == 100, "a negative balance owes the whole rent")
	_expect(FixedCosts.settle(null) == 0 and FixedCosts.shortfall(null) == 0, "no company, nothing charged")
	state.reset()
	if _failures == 0:
		print("PASS: fixed costs charge the rent")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
