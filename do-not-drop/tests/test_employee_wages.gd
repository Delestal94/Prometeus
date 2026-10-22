extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_employee_wages.gd
##
## Wage table of the company's employees (expansion D-0515, data/employees/):
## - novice 60, regular 90 and expert 130 a day, doing 0.5 / 0.7 / 1.0 of a player;
## - the levels come cheapest first, each one valid and with a name in both languages;
## - a better level costs more and does more;
## - a novice pays for itself: one more order a day (margin 102, economia.md) beats its 60 wage;
## - an unknown level has no wage.

const WAGES: Dictionary = {&"novice": 60, &"regular": 90, &"expert": 130}
const OUTPUT: Dictionary = {&"novice": 0.5, &"regular": 0.7, &"expert": 1.0}
const ORDER_MARGIN: int = 102

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var levels: Array[EmployeeLevel] = EmployeeLevels.levels()
	_expect(levels.size() == WAGES.size(), "three levels ship (%d)" % levels.size())
	var ids: Array[StringName] = []
	for level: EmployeeLevel in levels:
		ids.append(level.id)
		_expect(level.is_valid(), "%s is valid" % level.id)
		_expect(WAGES.has(level.id), "%s is a known level" % level.id)
		_expect(EmployeeLevels.wage_for(level.id) == WAGES.get(level.id, -1), "%s wage" % level.id)
		_expect(is_equal_approx(level.output, OUTPUT.get(level.id, -1.0)), "%s output" % level.id)
		var key: String = EmployeeLevels.name_key(level)
		_expect(tr(key) != key, "%s has a name" % level.id)
	_expect(ids == [&"novice", &"regular", &"expert"] as Array[StringName], "cheapest first: %s" % [ids])
	for i: int in range(1, levels.size()):
		_expect(levels[i].wage > levels[i - 1].wage, "%s costs more than %s" % [levels[i].id, levels[i - 1].id])
		_expect(levels[i].output > levels[i - 1].output, "%s does more than %s" % [levels[i].id, levels[i - 1].id])
	_expect(EmployeeLevels.wage_for(&"novice") < ORDER_MARGIN, "a novice pays for itself with one more order a day")
	_expect(EmployeeLevels.wage_for(&"intern") == 0 and EmployeeLevels.find(&"intern") == null, "unknown level")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
