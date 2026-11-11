extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_day_close_screen.gd
##
## The closing screen of a company day with its milestones, wages and tomorrow (expansion D-1905,
## day_summary_panel.gd + day_close_report.gd), checked on the numbers in the tree (no screenshot):
## - prefixed ledger reasons are named: `milestone:<id>` "Hito: <name>", `day_event:<id>` "Evento: <name>",
##   `wages` "Sueldos"; a name without a translation key shows its id;
## - "Hitos del día" lists the milestones the ledger paid that day and the ones heard during the day
##   (milestone_reached), each once; the heard ones are forgotten when the screen closes;
## - "Sueldos pagados" has one row per employee (its name, or its level's name, and the wage of the entry or of
##   the level's table), and their total; entries with no wage are skipped;
## - one "Mañana:" line per day event announced for tomorrow;
## - a day without any of it hides the three parts, so the old closing screen is unchanged;
## - DayCloseReport.extras() reads the employees of CompanyNet's company, and CompanyRoot passes it to the panel;
## - both languages have every key.

const KEYS: Array[String] = [
	"UI_FINANCE_REASON_WAGES", "UI_DAYCLOSE_MILESTONES", "UI_DAYCLOSE_WAGES", "UI_DAYCLOSE_TOMORROW",
	"UI_DAYCLOSE_REASON_MILESTONE", "UI_DAYCLOSE_REASON_EVENT",
]

var _failures: int = 0


class FakeCompany:
	extends RefCounted
	var employees: Array[Dictionary] = []


class FakeNet:
	extends RefCounted
	var company: Object = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_keys()
	_test_report()
	await _test_panel()
	await _test_quiet_day()
	_test_root_wiring()
	if _failures == 0:
		print("PASS: the day's closing screen lists milestones, wages and tomorrow")
	quit(_failures)


func _test_keys() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")


func _test_report() -> void:
	_expect(DaySummaryPanel.reason_name("milestone:first_earnings") == "Hito: first_earnings",
		"a milestone prize is named Hito (got %s)" % DaySummaryPanel.reason_name("milestone:first_earnings"))
	_expect(DaySummaryPanel.reason_name("day_event:inspection") == "Evento: inspection", "a day event is named Evento")
	_expect(DaySummaryPanel.reason_name("wages") == "Sueldos", "wages have their name")
	_expect(DaySummaryPanel.reason_name("rent") == "Alquiler del galpón", "plain reasons keep their name")
	var rows: Array = DayCloseReport.wage_rows([
		{"level": &"novice"}, {"name": "Rita", "level": &"expert"}, {"name": "Paga fija", "wage": 75},
		{"level": &"nobody"}, "broken",
	])
	_expect(rows.size() == 3, "three employees with a wage (got %d)" % rows.size())
	var novice: int = EmployeeLevels.wage_for(&"novice")
	var expert: int = EmployeeLevels.wage_for(&"expert")
	_expect(novice > 0 and expert > novice, "the table pays the levels")
	if rows.size() == 3:
		_expect(rows[0] == ["Empleado novato", novice], "a nameless employee shows its level (got %s)" % [rows[0]])
		_expect(rows[1] == ["Rita", expert], "a named employee shows its name and level wage")
		_expect(rows[2] == ["Paga fija", 75], "the entry's own wage wins")
	_expect(DayCloseReport.wages_total(rows) == novice + expert + 75, "wages add up")
	var summary: Dictionary = {"income_by_reason": {"milestone:deliveries_25": 300, "order_paid": 500,
		"milestone:first_earnings": 150}}
	var reached: Array[String] = DayCloseReport.milestones(summary, ["clean_week", "first_earnings"])
	var expected: Array[String] = ["deliveries_25", "first_earnings", "clean_week"]
	_expect(reached == expected,
		"paid milestones biggest first, then the heard ones, each once (got %s)" % [reached])
	var lines: Array[String] = DayCloseReport.tomorrow_lines(["market", ""])
	_expect(lines.size() == 1 and lines[0] == "Mañana: market", "one Mañana line per event (got %s)" % [lines])
	var net := FakeNet.new()
	_expect(DayCloseReport.extras(null, 3)["employees"].is_empty(), "no net, no employees")
	_expect(DayCloseReport.extras(net, 3)["employees"].is_empty(), "no company, no employees")
	var company := FakeCompany.new()
	company.employees = [{"level": &"regular"}]
	net.company = company
	var extras: Dictionary = DayCloseReport.extras(net, 3)
	_expect(extras["employees"] == [{"level": &"regular"}], "extras carries the company's employees")
	extras["employees"][0]["level"] = &"expert"
	_expect(company.employees[0]["level"] == &"regular", "extras is a copy")


func _test_panel() -> void:
	var panel := DaySummaryPanel.new()
	root.add_child(panel)
	await process_frame
	panel.note_milestone(&"clean_week")
	panel.note_milestone(&"clean_week")
	var summary: Dictionary = {
		"day": 9, "income": 450, "costs": 180, "profit": 270, "opening": 1000, "closing": 1270,
		"income_by_reason": {"order_paid": 300, "milestone:first_earnings": 150},
		"cost_by_reason": {"wages": 180},
	}
	var extras: Dictionary = {
		"employees": [{"name": "Rita", "wage": 60}, {"name": "Tito", "wage": 120}],
		"tomorrow": ["market"],
	}
	panel.open(summary, [], 0, extras)
	_expect(panel.visible, "the panel opens")
	var income_row: Node = panel.find_child("Row_milestone_first_earnings", true, false)
	_expect(income_row != null, "the milestone prize has its income row")
	var milestones := panel.find_child("Milestones", true, false) as Control
	_expect(milestones != null and milestones.visible, "the milestones part shows")
	_expect(_label(panel, "Milestone_first_earnings") != null and _label(panel, "Milestone_clean_week") != null,
		"it lists the paid and the heard milestone")
	var wages := panel.find_child("Wages", true, false) as Control
	_expect(wages != null and wages.visible, "the wages part shows")
	var wage_total := wages.find_child("Total", true, false) as Label if wages != null else null
	_expect(wage_total != null and wage_total.text.contains("$180"), "the wages total is $180")
	var tito := wages.find_child("Wage_1", true, false) if wages != null else null
	_expect(tito != null and (tito.get_child(0) as Label).text == "Tito"
		and (tito.get_node(^"Amount") as Label).text == "$120", "Tito's row shows his wage")
	var tomorrow := panel.find_child("Tomorrow", true, false) as VBoxContainer
	_expect(tomorrow != null and tomorrow.visible and tomorrow.get_child_count() == 1
		and (tomorrow.get_child(0) as Label).text == "Mañana: market", "one Mañana line")
	panel.close()
	await process_frame
	panel.open(summary, [], 0, {})
	_expect(_label(panel, "Milestone_clean_week") == null, "a heard milestone is forgotten after the close")
	_expect(_label(panel, "Milestone_first_earnings") != null, "the paid one still comes from the ledger")
	panel.queue_free()
	await process_frame


func _test_quiet_day() -> void:
	var panel := DaySummaryPanel.new()
	root.add_child(panel)
	await process_frame
	panel.open({"day": 2, "income_by_reason": {"order_paid": 80}, "cost_by_reason": {"rent": 50}})
	var extras_box := panel.find_child("Extras", true, false) as Control
	var tomorrow := panel.find_child("Tomorrow", true, false) as Control
	_expect(extras_box != null and not extras_box.visible, "no milestones and no wages: the part hides")
	_expect(tomorrow != null and not tomorrow.visible, "no events tomorrow: no Mañana line")
	panel.queue_free()
	await process_frame


func _test_root_wiring() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/gameplay/company_root.gd")
	_expect(source.contains("DayCloseReport.extras(net, day)"), "CompanyRoot passes the extras to the panel")


func _label(panel: Node, node_name: String) -> Label:
	return panel.find_child(node_name, true, false) as Label


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
