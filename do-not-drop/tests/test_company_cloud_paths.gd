extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_cloud_paths.gd
##
## Company save in Steam Auto-Cloud (expansion D-2010, merges D-0237):
## - CompanySave.SAVE_DIR is user://saves/company and every slot file it builds
##   lives right under it (the folder Auto-Cloud syncs, see
##   docs/marketing/estado-steam.md "Guardado en la nube");
## - every "user://..." written in code (not in comments) in the expansion's
##   scripts is under that folder or in EXCLUDED with its reason, so a new
##   expansion file outside the cloud list can't slip in unnoticed;
## - the scan catches a path outside the list (a line kept inside this test)
##   and ignores one that only appears in a comment.

const CLOUD_DIR: String = "user://saves/company"
const EXPANSION_DIRS: Array[String] = [
	"res://scripts/core/company/",
	"res://scripts/gameplay/business/",
	"res://scripts/gameplay/districts/",
	"res://scripts/gameplay/fleet/",
]
const EXPANSION_FILES: Array[String] = [
	"res://scripts/gameplay/company_root.gd",
	"res://scripts/gameplay/company_shed.gd",
	"res://scripts/gameplay/shed_builder.gd",
]
## "user://" prefixes that are on purpose not synced, with the reason. Empty
## today: add one here (and to the exclusions in estado-steam.md) when needed.
const EXCLUDED: Dictionary = {}

const CompanySaveScript := preload("res://scripts/core/company/company_save.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_save_dir()
	_test_expansion_paths()
	_test_scan_catches_outside_path()
	if _failures == 0:
		print("OK test_company_cloud_paths")
	quit(_failures)


func _test_save_dir() -> void:
	_expect(
		CompanySaveScript.SAVE_DIR == CLOUD_DIR,
		"CompanySave.SAVE_DIR is %s (got %s)" % [CLOUD_DIR, CompanySaveScript.SAVE_DIR]
	)
	for slot: String in ["default", "Mi Empresa 2", "../escape"]:
		var path: String = CompanySaveScript.path_for(slot)
		_expect(
			path.get_base_dir() == CLOUD_DIR,
			"Slot %s is saved right under %s (got %s)" % [slot, CLOUD_DIR, path]
		)


func _test_expansion_paths() -> void:
	var scripts: Array[String] = []
	for dir: String in EXPANSION_DIRS:
		_collect_scripts(dir, scripts)
	for file: String in EXPANSION_FILES:
		if FileAccess.file_exists(file):
			scripts.append(file)
	_expect(scripts.has("res://scripts/core/company/company_save.gd"), "company_save.gd is scanned")
	var found: Array[String] = []
	for script: String in scripts:
		var text: String = FileAccess.get_file_as_string(script)
		for path: String in _user_paths_in(text):
			found.append(path)
			_expect(
				_allowed(path),
				"%s writes %s, outside %s and not in EXCLUDED" % [script, path, CLOUD_DIR]
			)
	_expect(found.has(CLOUD_DIR), "The scan finds CompanySave's own folder (got %s)" % [found])


func _test_scan_catches_outside_path() -> void:
	var text: String = 'const LOG := "user://company_log"\n## Old saves lived in "user://old_place".\n'
	var paths: Array[String] = _user_paths_in(text)
	_expect(paths == ["user://company_log"], "Only the path in code is found (got %s)" % [paths])
	_expect(
		not _allowed(paths[0] if not paths.is_empty() else ""),
		"A path outside the cloud folder is caught"
	)
	_expect(_allowed(CLOUD_DIR + "/slot.json"), "A file inside the cloud folder passes")
	_expect(
		not _allowed("user://saves/company_backup"),
		"A sibling folder with the same prefix is caught"
	)


func _allowed(path: String) -> bool:
	if path == CLOUD_DIR or path.begins_with(CLOUD_DIR + "/"):
		return true
	for prefix: String in EXCLUDED:
		if path.begins_with(prefix):
			return true
	return false


## The "user://..." string literals in code; anything after a `#` outside a
## string (comments and doc comments) is cut first.
func _user_paths_in(text: String) -> Array[String]:
	var paths: Array[String] = []
	var regex := RegEx.create_from_string('"(user://[^"]*)"')
	for line: String in text.split("\n"):
		for result: RegExMatch in regex.search_all(_strip_comment(line)):
			paths.append(result.get_string(1))
	return paths


func _strip_comment(line: String) -> String:
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if quote != "":
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
		elif character == '"' or character == "'":
			quote = character
		elif character == "#":
			return line.substr(0, index)
		index += 1
	return line


func _collect_scripts(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect_scripts(dir_path.path_join(sub), into)
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			into.append(dir_path.path_join(file))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
