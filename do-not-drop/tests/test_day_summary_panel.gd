extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_day_summary_panel.gd
##
## Closing screen of a company day (expansion D-0508.2, day_summary_panel.gd):
## - its numbers are DaySummary.build()'s: income and costs per reason, totals, profit and the
##   opening and closing balance, read back from the labels in the tree;
## - reasons come out biggest first, a reason with no translation shows its own id, and a list
##   longer than MAX_ROWS folds its tail into one "other" row without losing money;
## - a quiet day shows "nothing" in both lists; the truncated warning shows only when asked;
## - Continue (and ui_cancel) hides the panel and emits `continued`; opening grabs focus on the
##   button so a gamepad can close it;
## - both languages have every finance_* key the panel and the known ledger reasons use.

const PANEL: String = "res://scripts/ui/day_summary_panel.gd"
const KEYS: Array[String] = [
	"finance_title", "finance_day", "finance_income", "finance_costs", "finance_none",
	"finance_total", "finance_profit", "finance_balance", "finance_truncated", "finance_continue",
	"finance_reason_order_paid", "finance_reason_tip", "finance_reason_placeable_sell",
	"finance_reason_supplier", "finance_reason_boxes", "finance_reason_packaging",
	"finance_reason_rent", "finance_reason_placeable_buy", "finance_reason_warehouse_expand",
	"finance_reason_penalty", "finance_reason_other",
]

var _failures: int = 0
var _continued: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	TranslationServer.set_locale("es")
	_test_keys()
	await _test_numbers(state)
	_test_rows()
	await _test_quiet_and_close()
	state.reset()
	if _failures == 0:
		print("PASS: day summary panel shows the closing numbers")
	quit(_failures)


func _test_keys() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")


func _make_panel() -> Control:
	var panel: Control = (load(PANEL) as GDScript).new()
	root.add_child(panel)
	return panel


func _test_numbers(state: Node) -> void:
	state.new_company("Panel Co")
	state.day = 2
	state.earn(300, &"order_paid")
	state.earn(30, &"tip")
	state.charge(80, &"supplier")
	state.charge(100, &"rent")
	state.charge(5, &"mystery_fee")
	var summary: Dictionary = DaySummary.build(state, 2)
	var panel: Control = _make_panel()
	panel.open(summary)
	await process_frame
	_expect(panel.visible, "open() shows the panel")
	_expect(_amount(panel, "Row_order_paid") == "$300", "order_paid row shows $300")
	_expect(_amount(panel, "Row_tip") == "$30", "tip row shows $30")
	_expect(_amount(panel, "Row_supplier") == "$80", "supplier row shows $80")
	_expect(_amount(panel, "Row_rent") == "$100", "rent row shows $100")
	var shown: Label = _find(panel, "Row_mystery_fee").get_child(0) as Label
	_expect(shown.text == "mystery_fee", "a reason without a key shows its id, not an empty label")
	_expect(_find(panel, "Row_rent").get_child(0).text == "Alquiler del galpón", "rent is translated")
	var totals: Array[String] = []
	for node: Node in panel.find_children("Total", "Label", true, false):
		totals.append((node as Label).text)
	_expect(totals == ["Total  $330", "Total  $185"], "totals are income 330 and costs 185: %s" % [totals])
	var profit: Label = _find(panel, "Profit") as Label
	_expect(profit.text == "Ganancia  +$145", "profit reads +$145: %s" % profit.text)
	_expect(profit.get_theme_color(&"font_color") == UiTheme.MINT, "a profit is mint")
	var balance: Label = _find(panel, "Balance") as Label
	var opening: int = int(summary["opening"])
	_expect(balance.text.contains("$%d" % opening) and balance.text.contains("$%d" % (opening + 145)),
			"balance line has opening and closing: %s" % balance.text)
	_expect(not (_find(panel, "Truncated") as Label).visible, "no truncated warning on a normal day")
	var losing: Dictionary = summary.duplicate(true)
	losing["profit"] = -20
	losing["truncated"] = true
	panel.refresh(losing)
	await process_frame
	_expect((_find(panel, "Profit") as Label).text == "Ganancia  -$20", "a loss reads -$20")
	_expect((_find(panel, "Profit") as Label).get_theme_color(&"font_color") == UiTheme.RED, "a loss is red")
	_expect((_find(panel, "Truncated") as Label).visible, "truncated shows its warning")
	panel.queue_free()


func _test_rows() -> void:
	var panel_class: GDScript = load(PANEL)
	var many: Dictionary = {}
	for i: int in 12:
		many["r%02d" % i] = 10 + i
	var rows: Array = panel_class.rows(many)
	_expect(rows.size() == panel_class.MAX_ROWS, "12 reasons fold into %d rows" % panel_class.MAX_ROWS)
	_expect(rows[0] == ["r11", 21], "biggest first")
	_expect(rows[rows.size() - 1][0] == "other", "the last row is the folded tail")
	var sum: int = 0
	for row: Array in rows:
		sum += int(row[1])
	var expected: int = 0
	for key: String in many:
		expected += int(many[key])
	_expect(sum == expected, "folding keeps the money: %d vs %d" % [sum, expected])
	_expect(panel_class.rows({"a": 1, "b": 2}).size() == 2, "a short list is not folded")
	_expect(panel_class.rows({}).is_empty(), "no reasons, no rows")
	_expect(panel_class.money(-5) == "-$5" and panel_class.money(0) == "$0", "money formats negatives")


func _test_quiet_and_close() -> void:
	var panel: Control = _make_panel()
	panel.continued.connect(func() -> void: _continued += 1)
	panel.open({"day": 4})
	await process_frame
	_expect(_find(panel, "None") != null, "a quiet day says nothing happened")
	_expect(panel.find_children("Row_*", "HBoxContainer", true, false).is_empty(), "no rows on a quiet day")
	var button: Button = panel.find_children("*", "Button", true, false)[0] as Button
	_expect(button.has_focus(), "the Continue button has focus after open()")
	button.pressed.emit()
	_expect(not panel.visible and _continued == 1, "Continue hides the panel and emits continued")
	panel.open({})
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	panel._unhandled_input(cancel)
	_expect(not panel.visible and _continued == 2, "ui_cancel closes it too")
	panel.queue_free()


func _find(parent: Node, node_name: String) -> Node:
	var found: Array[Node] = parent.find_children(node_name, "", true, false)
	return found[0] if not found.is_empty() else null


func _amount(panel: Node, row: String) -> String:
	var node: Node = _find(panel, row)
	return (_find(node, "Amount") as Label).text if node != null else "<missing>"


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
