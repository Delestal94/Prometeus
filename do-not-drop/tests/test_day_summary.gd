extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_day_summary.gd
##
## Day summary (expansion D-0508, day_summary.gd), over the company wallet's ledger:
## - income and costs of a day are the ledger movements of that day split by sign, each by reason;
## - profit is income minus costs, and opening plus profit is the closing balance;
## - other days' movements do not leak in, and a quiet day shows the wallet unchanged;
## - the numbers match what CompanyState.ledger_total says per reason;
## - truncated warns when the ledger is full and its oldest entries may belong to the day.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_day(state)
	_test_quiet_and_empty(state)
	_test_truncated(state)
	_test_sorting()
	state.reset()
	if _failures == 0:
		print("PASS: day summary adds up the ledger")
	quit(_failures)


func _test_day(state: Node) -> void:
	state.new_company("Summary Co")
	var start: int = state.money
	state.day = 1
	state.earn(50, &"order_paid")
	state.day = 2
	state.earn(200, &"order_paid")
	state.earn(30, &"tip")
	state.charge(80, &"supplier")
	state.charge(5, &"boxes")
	state.earn(100, &"order_paid")
	state.charge(15, &"supplier")
	state.day = 3
	state.charge(40, &"rent")
	var summary: Dictionary = DaySummary.build(state, 2)
	_expect(summary["income"] == 330 and summary["costs"] == 100, "day 2 income 330, costs 100")
	_expect(summary["profit"] == 230, "profit is 230")
	_expect(summary["income_by_reason"]["order_paid"] == 300, "orders paid 300")
	_expect(summary["income_by_reason"]["tip"] == 30, "tips 30")
	_expect(summary["cost_by_reason"]["supplier"] == 95, "supplier 95 (two charges)")
	_expect(summary["cost_by_reason"]["boxes"] == 5, "boxes 5")
	_expect(not summary["cost_by_reason"].has("rent"), "day 3 rent stays out")
	_expect(summary["opening"] == start + 50, "opened with day 1's money")
	_expect(summary["closing"] == summary["opening"] + summary["profit"], "opening plus profit is closing")
	_expect(
		summary["cost_by_reason"]["supplier"] == -state.ledger_total(&"supplier"),
		"matches ledger_total"
	)
	_expect(not summary["truncated"], "a short ledger is not truncated")
	var day3: Dictionary = DaySummary.build(state, 3)
	_expect(day3["costs"] == 40 and day3["income"] == 0 and day3["profit"] == -40, "a losing day")


func _test_quiet_and_empty(state: Node) -> void:
	state.new_company("Quiet Co")
	state.day = 4
	var summary: Dictionary = DaySummary.build(state, 9)
	_expect(summary["profit"] == 0 and summary["opening"] == state.money, "a quiet day keeps the money")
	_expect(summary["closing"] == state.money, "closing is the wallet")
	var none: Dictionary = DaySummary.build(null, 1)
	_expect(none["income"] == 0 and none["costs"] == 0, "no company, empty summary")


func _test_truncated(state: Node) -> void:
	state.new_company("Long Co")
	state.day = 5
	for i in CompanyTuning.LEDGER_MAX + 10:
		state.earn(1, &"order_paid")
	_expect(state.ledger.size() == CompanyTuning.LEDGER_MAX, "ledger is capped")
	_expect(DaySummary.build(state, 5)["truncated"], "a full ledger still on day 5 may be missing entries")
	_expect(DaySummary.build(state, 4)["truncated"], "a day older than the ledger is gone too")
	state.day = 6
	state.earn(1, &"tip")
	_expect(not DaySummary.build(state, 6)["truncated"], "day 6 starts after the oldest entry")


func _test_sorting() -> void:
	var sorted: Array[String] = DaySummary.sorted_reasons({"b": 5, "a": 5, "c": 9, "d": 1})
	_expect(sorted == ["c", "a", "b", "d"], "biggest first, ties by name")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
