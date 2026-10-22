extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_slots.gd
##
## Company save slots (expansion D-0235, company_save.gd list_slots / delete / new_slot_id):
## - three slots saved with different names, days and money are listed with their
##   slot, name, day, money and a saved_at > 0;
## - the list is ordered by saved_at descending (ties by slot) and reading it moves
##   no file;
## - delete() removes the slot with its .bak / .tmp / .bad and the list shrinks to 2,
##   then to 0; deleting a slot that is not there is true;
## - a slot whose only file is <slot>.json.bak (a cut write) is listed;
## - JSON that is not a save, a loose .tmp and a .bad are not listed;
## - a save from a newer build is listed with its version;
## - new_slot_id() is "company" in an empty folder, then "company_2", "company_3"...;
## - a missing folder lists nothing.

const DIR: String = "user://test_company_slots"

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
	_test_empty()
	_test_create_list_delete(state)
	_test_odd_files()
	_test_new_slot_id()
	state.reset()
	_clean()
	if _failures == 0:
		print("PASS: company slots are created, listed (newest first), deleted and named")
	quit(_failures)


func _test_empty() -> void:
	_expect(CompanySave.list_slots("user://test_company_slots_nowhere").is_empty(), "a missing folder lists nothing")
	_expect(CompanySave.list_slots(DIR).is_empty(), "an empty folder lists nothing")
	_expect(CompanySave.delete("nobody", DIR), "deleting a slot that is not there is true")
	_expect(CompanySave.new_slot_id(DIR) == "company", "an empty folder hands out the default slot")


func _test_create_list_delete(state: Node) -> void:
	var specs: Array[Dictionary] = [
		{"slot": "alpha", "name": "Alpha Post", "day": 3, "money": 500},
		{"slot": "beta", "name": "Beta Freight", "day": 12, "money": 4200},
		{"slot": "gamma", "name": "Gamma Express", "day": 1, "money": 90},
	]
	for spec: Dictionary in specs:
		state.new_company(spec["name"])
		state.day = spec["day"]
		state.money = spec["money"]
		_expect(CompanySave.save(state, spec["slot"], DIR), "save creates slot %s" % spec["slot"])
	var listed: Array[Dictionary] = CompanySave.list_slots(DIR)
	_expect(listed.size() == 3, "three slots are listed (got %d)" % listed.size())
	for spec: Dictionary in specs:
		var entry: Dictionary = _find(listed, spec["slot"])
		_expect(not entry.is_empty(), "slot %s is listed" % spec["slot"])
		_expect(entry.get("name") == spec["name"], "%s keeps its name (got %s)" % [spec["slot"], entry.get("name")])
		_expect(entry.get("day") == spec["day"], "%s keeps its day (got %s)" % [spec["slot"], entry.get("day")])
		_expect(entry.get("money") == spec["money"], "%s keeps its money (got %s)" % [spec["slot"], entry.get("money")])
		_expect(int(entry.get("saved_at", 0)) > 0, "%s has a saved_at date" % spec["slot"])
		_expect(entry.get("interrupted") == false, "%s is not interrupted" % spec["slot"])
		_expect(entry.get("version") == CompanySave.VERSION, "%s carries the save version" % spec["slot"])
	# A listed slot loads back by the name the list gives.
	state.reset()
	var result: CompanySave.LoadResult = CompanySave.load_into(state, "beta", DIR)
	_expect(result == CompanySave.LoadResult.LOADED and state.company_name == "Beta Freight", "listed slot loads back")

	# Order: newest first, ties by slot name.
	_set_saved_at("alpha", 2000)
	_set_saved_at("beta", 1000)
	_set_saved_at("gamma", 3000)
	_expect(_slots(CompanySave.list_slots(DIR)) == ["gamma", "alpha", "beta"], "ordered by saved_at descending")
	_set_saved_at("beta", 3000)
	_expect(_slots(CompanySave.list_slots(DIR)) == ["beta", "gamma", "alpha"], "ties break by slot ascending")
	_expect(_files().size() == 3, "listing moves no file (got %s)" % [_files()])

	# Delete one together with its leftovers.
	var beta_path: String = CompanySave.path_for("beta", DIR)
	_write(beta_path + ".bak", "{}")
	_write(beta_path + ".tmp", "{")
	_write(beta_path + ".bad", "{")
	_expect(CompanySave.delete("beta", DIR), "delete reports the slot gone")
	for suffix: String in ["", ".bak", ".tmp", ".bad"]:
		_expect(not FileAccess.file_exists(beta_path + suffix), "beta%s is removed" % suffix)
	_expect(_slots(CompanySave.list_slots(DIR)) == ["gamma", "alpha"], "two slots are left after one delete")
	_expect(CompanySave.delete("beta", DIR), "deleting it again is still true")
	_expect(CompanySave.delete("alpha", DIR) and CompanySave.delete("gamma", DIR), "the others are deleted")
	_expect(CompanySave.list_slots(DIR).is_empty(), "no slot is left")
	_expect(_files().is_empty(), "no file is left (got %s)" % [_files()])


func _test_odd_files() -> void:
	# Only a .bak: a cut write; load_into recovers it, so it is a company.
	var company: Dictionary = {"company_name": "", "day": 5, "money": 10}
	_write(CompanySave.path_for("cutwrite", DIR) + ".bak", JSON.stringify({"version": 1, "company": company}))
	# Not saves of ours.
	_write(CompanySave.path_for("stranger", DIR), "{\"hello\": \"world\"}")
	_write(CompanySave.path_for("broken", DIR), "{\"version\": 1, \"company\": {\"mon")
	_write(CompanySave.path_for("nocompany", DIR), JSON.stringify({"version": 1, "company": "x"}))
	_write(CompanySave.path_for("list", DIR), "[1, 2]")
	# Leftovers with no save beside them.
	_write(CompanySave.path_for("loose", DIR) + ".tmp", JSON.stringify({"version": 1, "company": company}))
	_write(CompanySave.path_for("quarantined", DIR) + ".bad", JSON.stringify({"version": 1, "company": company}))
	# A newer build's save.
	var future: String = JSON.stringify(
		{"version": CompanySave.VERSION + 1, "saved_at": 50, "company": {"company_name": "Future Co", "day": 9}}
	)
	_write(CompanySave.path_for("future", DIR), future)
	var before: Array[String] = _files()
	var listed: Array[Dictionary] = CompanySave.list_slots(DIR)
	_expect(_slots(listed).size() == 2, "only the real saves are listed (got %s)" % [_slots(listed)])
	var cut: Dictionary = _find(listed, "cutwrite")
	_expect(cut.get("name") == "cutwrite", "an unnamed company shows its slot as the name (got %s)" % cut.get("name"))
	_expect(cut.get("day") == 5 and cut.get("money") == 10, "the .bak-only slot is read")
	_expect(int(cut.get("saved_at", -1)) == 0, "a save without a date has saved_at 0")
	var newer: Dictionary = _find(listed, "future")
	_expect(newer.get("version") == CompanySave.VERSION + 1, "a newer save is listed with its version")
	_expect(newer.get("name") == "Future Co", "the newer save shows its name")
	_expect(_slots(listed)[0] == "future", "the dated save goes before the undated one")
	_expect(_files() == before, "listing odd files moves and quarantines nothing")
	for slot: String in ["cutwrite", "stranger", "broken", "nocompany", "list", "loose", "quarantined", "future"]:
		_expect(CompanySave.delete(slot, DIR), "cleanup deletes %s" % slot)
	_expect(_files().is_empty(), "cleanup leaves the folder empty (got %s)" % [_files()])


func _test_new_slot_id() -> void:
	_expect(CompanySave.new_slot_id(DIR) == "company", "free default slot is handed out")
	_write(CompanySave.path_for("company", DIR), JSON.stringify({"version": 1, "company": {}}))
	_expect(CompanySave.new_slot_id(DIR) == "company_2", "company_2 once company exists")
	_write(CompanySave.path_for("company_2", DIR) + ".bak", "{}")
	_expect(CompanySave.new_slot_id(DIR) == "company_3", "a .bak alone also holds its slot")
	CompanySave.delete("company", DIR)
	_expect(CompanySave.new_slot_id(DIR) == "company", "a freed default slot is handed out again")
	CompanySave.delete("company_2", DIR)
	_expect(_files().is_empty(), "new_slot_id test leaves the folder empty")


func _find(listed: Array[Dictionary], slot: String) -> Dictionary:
	for entry: Dictionary in listed:
		if entry.get("slot") == slot:
			return entry
	return {}


func _slots(listed: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in listed:
		out.append(String(entry.get("slot")))
	return out


## Rewrites "saved_at" in a slot's JSON by hand to force an order.
func _set_saved_at(slot: String, when: int) -> void:
	var path: String = CompanySave.path_for(slot, DIR)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary:
		_expect(false, "%s is readable" % slot)
		return
	(raw as Dictionary)["saved_at"] = when
	_write(path, JSON.stringify(raw))


func _files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		out.append(file_name)
	out.sort()
	return out


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
