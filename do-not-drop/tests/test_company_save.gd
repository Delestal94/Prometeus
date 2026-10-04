extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_save.gd
##
## Company save file (expansion D-0206, company_save.gd over SafeJson):
## - save -> load_into returns the same company (CompanyState.to_dict equal),
##   the file carries "version": 1 and lives under the slot's filename-safe path;
## - a missing slot reports MISSING and leaves the state alone;
## - a corrupt file (bad JSON, or JSON that is not a save) never breaks: CORRUPT,
##   a new company with defaults, and the file quarantined to .bad;
## - a v1 save climbs a test-only v1 -> v2 migration that adds a field with its
##   default, without losing the rest; a missing migration step does not load;
## - a save from a newer build is TOO_NEW: not loaded and left untouched;
## - a stray .tmp left by a cut mid-write is ignored (the real file wins).

const DIR: String = "user://test_company_save"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	_expect(state != null, "CompanyState autoload exists")
	if state == null:
		quit(1)
		return
	_clean()
	_test_round_trip(state)
	_test_missing(state)
	_test_corrupt(state)
	_test_not_a_save(state)
	_test_migration(state)
	_test_too_new(state)
	_test_stray_tmp(state)
	state.reset()
	_clean()
	if _failures == 0:
		print("PASS: company save round-trips, survives corrupt files and stray .tmp, migrates v1 -> v2")
	quit(_failures)


func _test_round_trip(state: Node) -> void:
	_fill(state)
	var before: Dictionary = state.to_dict()
	_expect(CompanySave.save(state, "slot A", DIR), "save writes the slot")
	var path: String = CompanySave.path_for("slot A", DIR)
	_expect(path.begins_with(DIR + "/") and path.ends_with(".json"), "slot path is inside the folder (got %s)" % path)
	_expect(CompanySave.path_for("a/b:c", DIR).get_file() == "a_b_c.json", "slot names are filename-safe")
	_expect(CompanySave.path_for("", DIR).get_file() == "company.json", "an empty slot falls back to the default")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(raw is Dictionary and int(raw.get("version", 0)) == CompanySave.VERSION, "file carries version 1")
	state.reset()
	var result: CompanySave.LoadResult = CompanySave.load_into(state, "slot A", DIR)
	_expect(result == CompanySave.LoadResult.LOADED, "load_into reports LOADED (got %d)" % result)
	_expect(state.is_active(), "loaded company is active")
	_expect(_same(state.to_dict(), before), "round trip keeps every field")
	_expect(not FileAccess.file_exists(path + ".tmp"), "no .tmp left after a save")


func _test_missing(state: Node) -> void:
	state.reset()
	var result: CompanySave.LoadResult = CompanySave.load_into(state, "nobody", DIR)
	_expect(result == CompanySave.LoadResult.MISSING, "missing slot reports MISSING (got %d)" % result)
	_expect(not state.is_active(), "missing slot leaves the state alone")


func _test_corrupt(state: Node) -> void:
	var path: String = CompanySave.path_for("broken", DIR)
	_write(path, "{\"version\": 1, \"company\": {\"money\": 9")
	state.reset()
	var result: CompanySave.LoadResult = CompanySave.load_into(state, "broken", DIR)
	_expect(result == CompanySave.LoadResult.CORRUPT, "bad JSON reports CORRUPT (got %d)" % result)
	_expect(state.is_active() and state.money == CompanyTuning.STARTING_MONEY, "bad JSON gives a new company")
	_expect(FileAccess.file_exists(path + ".bad") and not FileAccess.file_exists(path), "bad JSON is quarantined")


func _test_not_a_save(state: Node) -> void:
	var path: String = CompanySave.path_for("stranger", DIR)
	_write(path, "{\"hello\": \"world\"}")
	state.reset()
	var result: CompanySave.LoadResult = CompanySave.load_into(state, "stranger", DIR)
	_expect(result == CompanySave.LoadResult.CORRUPT, "JSON without version reports CORRUPT (got %d)" % result)
	_expect(state.is_active() and state.day == CompanyTuning.STARTING_DAY, "not-a-save gives a new company")
	_expect(FileAccess.file_exists(path + ".bad"), "not-a-save is quarantined too")


func _test_migration(state: Node) -> void:
	# A v1 file as an older build wrote it: no "equipment" yet in this made-up history.
	var company: Dictionary = {"company_name": "Old Co", "money": 1234, "day": 7, "opened_gates": ["gate_coast"]}
	_write(CompanySave.path_for("old", DIR), JSON.stringify({"version": 1, "company": company}))
	var migrations: Dictionary = {1: _v1_to_v2}
	state.reset()
	var result: CompanySave.LoadResult = CompanySave.load_into(state, "old", DIR, migrations, 2)
	_expect(result == CompanySave.LoadResult.LOADED, "v1 save loads through the v1 -> v2 migration (got %d)" % result)
	_expect(state.money == 1234 and state.day == 7 and state.company_name == "Old Co", "migration keeps the old data")
	_expect(state.is_gate_open(&"gate_coast"), "migration keeps opened gates")
	_expect(state.equipment == [&"chains"], "migration adds its field with the default (got %s)" % [state.equipment])
	var migrated: Dictionary = CompanySave.migrate(company, 1, migrations, 2)
	_expect(not company.has("equipment") and migrated.has("equipment"), "migrate does not touch its input")
	_expect(CompanySave.migrate(company, 1, {}, 2).is_empty(), "a missing migration step returns empty")
	state.reset()
	var no_step: CompanySave.LoadResult = CompanySave.load_into(state, "old", DIR, {}, 2)
	_expect(no_step == CompanySave.LoadResult.CORRUPT, "a v1 save without its migration does not load as-is")


func _test_too_new(state: Node) -> void:
	var path: String = CompanySave.path_for("future", DIR)
	var text: String = JSON.stringify({"version": CompanySave.VERSION + 1, "company": {"money": 1}})
	_write(path, text)
	state.reset()
	var result: CompanySave.LoadResult = CompanySave.load_into(state, "future", DIR)
	_expect(result == CompanySave.LoadResult.TOO_NEW, "newer save reports TOO_NEW (got %d)" % result)
	_expect(not state.is_active(), "newer save is not loaded")
	_expect(FileAccess.get_file_as_string(path) == text, "newer save is left untouched")


func _test_stray_tmp(state: Node) -> void:
	_fill(state)
	_expect(CompanySave.save(state, "cut", DIR), "save before the cut")
	var path: String = CompanySave.path_for("cut", DIR)
	_write(path + ".tmp", "{\"version\": 1, \"company\": {\"mon")
	state.reset()
	var result: CompanySave.LoadResult = CompanySave.load_into(state, "cut", DIR)
	_expect(result == CompanySave.LoadResult.LOADED and state.money == 777, "a stray .tmp is ignored")
	state.money = 888
	_expect(CompanySave.save(state, "cut", DIR), "saving over a stray .tmp works")
	state.reset()
	CompanySave.load_into(state, "cut", DIR)
	_expect(state.money == 888, "the new save replaced the old one (got %d)" % state.money)


func _fill(state: Node) -> void:
	state.new_company("Acme")
	state.money = 777
	state.day = 4
	state.clock_minutes = 600
	state.reputation = 61.5
	state.district_reputation = {&"centro": 70.0}
	state.open_gate(&"gate_coast")
	state.equipment = [&"chains"] as Array[StringName]
	state.fleet = [{"vehicle": "van", "plate": "AB123"}] as Array[Dictionary]
	state.employees = [{"name": "Rita", "role": "packer"}] as Array[Dictionary]
	state.milestones_done = [&"first_day"] as Array[StringName]
	state.layout = [{"piece": "shelf", "x": 2, "y": 3}] as Array[Dictionary]
	var stock: Inventory = state.stock()
	stock.receive(&"books", 5, &"shelf_1")
	state.store_stock(stock)


static func _v1_to_v2(company: Dictionary) -> Dictionary:
	var next: Dictionary = company.duplicate(true)
	if not next.has("equipment"):
		next["equipment"] = ["chains"]
	return next


## Same after a JSON trip: both sides go through JSON once (ids become String,
## ints in nested entries become float), then their sorted text is compared.
func _same(a: Dictionary, b: Dictionary) -> bool:
	return _canonical(a) == _canonical(b)


static func _canonical(value: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		dir.remove(file_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
