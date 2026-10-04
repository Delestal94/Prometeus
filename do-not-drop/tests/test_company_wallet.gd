extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_wallet.gd
##
## Company wallet (expansion D-0501, CompanyState.earn/spend/charge + ledger):
## - earn() adds money and records day, minute, signed amount, reason and balance;
## - spend() refuses what the wallet does not cover and changes nothing;
## - charge() goes through into the red (rent, penalties);
## - zero or negative amounts are ignored;
## - the ledger entries add up to the balance change, ledger_total() sums by reason;
## - the ledger keeps only the last LEDGER_MAX movements;
## - the ledger survives to_dict() -> from_dict() (also through JSON), and new_company()
##   and reset() clear it.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_earn_spend(state)
	_test_charge_and_ignored(state)
	_test_sum_matches_balance(state)
	_test_cap(state)
	_test_round_trip(state)
	state.reset()
	if _failures == 0:
		print("PASS: wallet earns, spends, charges, keeps a capped ledger that saves and loads")
	quit(_failures)


func _test_earn_spend(state: Node) -> void:
	state.new_company("Wallet Co")
	state.clock_minutes = 600
	_expect(state.ledger.is_empty(), "a new company has an empty ledger")
	_expect(state.earn(80, &"order_paid"), "earn() accepts a positive amount")
	_expect(state.money == 580, "money 500 + 80 (got %d)" % state.money)
	var entry: Dictionary = state.ledger[0]
	_expect(entry["amount"] == 80 and entry["reason"] == "order_paid" and entry["balance"] == 580,
		"entry has amount, reason and balance")
	_expect(entry["day"] == 1 and entry["minute"] == 600, "entry has day and game minute")
	_expect(state.can_afford(580) and not state.can_afford(581), "can_afford is exact")
	_expect(not state.spend(581, &"supplier"), "spend() refuses more than the wallet has")
	_expect(state.money == 580 and state.ledger.size() == 1, "a refused spend changes nothing")
	_expect(state.spend(580, &"supplier") and state.money == 0, "spend() can empty the wallet")
	_expect(state.ledger[1]["amount"] == -580, "a spend is recorded negative")


func _test_charge_and_ignored(state: Node) -> void:
	state.new_company()
	_expect(state.charge(CompanyTuning.RENT_PER_DAY * 6, &"rent"), "charge() goes through")
	_expect(state.money == -100, "charge() leaves the balance in the red (got %d)" % state.money)
	var size: int = state.ledger.size()
	_expect(not state.earn(0, &"x") and not state.earn(-5, &"x"), "earn() ignores zero and negative")
	_expect(not state.spend(0, &"x") and not state.spend(-5, &"x"), "spend() ignores zero and negative")
	_expect(not state.charge(0, &"x") and not state.charge(-5, &"x"), "charge() ignores zero and negative")
	_expect(not state.can_afford(1), "nothing is affordable in the red")
	_expect(state.ledger.size() == size and state.money == -100, "ignored amounts record nothing")


func _test_sum_matches_balance(state: Node) -> void:
	state.new_company()
	state.earn(210, &"order_paid")
	state.spend(100, &"supplier")
	state.earn(30, &"order_paid")
	state.charge(100, &"rent")
	var sum: int = 0
	for entry: Dictionary in state.ledger:
		sum += int(entry["amount"])
	_expect(CompanyTuning.STARTING_MONEY + sum == state.money, "movements add up to the balance")
	_expect(state.ledger.back()["balance"] == state.money, "last entry balance is the money")
	_expect(state.ledger_total(&"order_paid") == 240, "ledger_total sums one reason")
	_expect(state.ledger_total(&"rent") == -100, "ledger_total of a charge is negative")
	_expect(state.ledger_total(&"nothing") == 0, "ledger_total of an unknown reason is 0")


func _test_cap(state: Node) -> void:
	state.new_company()
	for i: int in CompanyTuning.LEDGER_MAX + 25:
		state.earn(1, &"tick")
	_expect(state.ledger.size() == CompanyTuning.LEDGER_MAX, "ledger is capped (got %d)" % state.ledger.size())
	_expect(state.ledger.back()["balance"] == state.money, "the newest movement is kept")
	_expect(state.money == CompanyTuning.STARTING_MONEY + CompanyTuning.LEDGER_MAX + 25,
		"the cap drops history, never money")


func _test_round_trip(state: Node) -> void:
	state.new_company("Save Co")
	state.earn(50, &"order_paid")
	state.charge(20, &"penalty")
	var before: Array = state.ledger.duplicate(true)
	var text: String = JSON.stringify(state.to_dict())
	state.reset()
	_expect(state.ledger.is_empty(), "reset() clears the ledger")
	_expect(state.from_dict(JSON.parse_string(text)), "company loads from JSON")
	_expect(state.ledger.size() == 2 and state.ledger[0]["amount"] == 50 and state.ledger[1]["amount"] == -20,
		"ledger comes back through JSON")
	_expect(typeof(state.ledger[0]["amount"]) == TYPE_INT or is_equal_approx(state.ledger[0]["amount"], 50.0),
		"amount is numeric after JSON")
	_expect(state.ledger.size() == before.size() and state.ledger[1]["reason"] == "penalty", "reason survives")
	state.from_dict({"money": 5, "ledger": "junk"})
	_expect(state.ledger.is_empty(), "a malformed ledger loads empty")
	state.new_company()
	_expect(state.ledger.is_empty(), "new_company() clears the ledger")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: " + message)
		_failures += 1
