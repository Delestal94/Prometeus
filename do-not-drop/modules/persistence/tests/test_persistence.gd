extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/persistence/tests/test_persistence.gd
##
## The persistence module on its own (docs/modulos.md): SafeJson writes a
## file whole (a truncated file is quarantined as .bad and the fallback
## comes back, a .bak left by an interrupted write is recovered), and
## UserDataMigration copies named files from an older save folder once,
## never over newer data, never again after its marker.

const DIR: String = "user://test_persistence"
const STORE: String = DIR + "/store.json"

var _failures: int = 0


func _initialize() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_test_safe_json()
	_test_migration()
	_cleanup()
	if _failures == 0:
		print("PASS: SafeJson survives truncated files and UserDataMigration copies once")
	quit(_failures)


func _test_safe_json() -> void:
	_expect(SafeJson.write(STORE, {"score": 12, "names": ["a", "b"]}), "A dictionary is written")
	var back: Variant = SafeJson.read(STORE, {})
	_expect(back is Dictionary and int(back.get("score", 0)) == 12 and back.get("names", []).size() == 2,
		"It reads back whole (got %s)" % [back])
	_expect(not FileAccess.file_exists(STORE + ".tmp") and not FileAccess.file_exists(STORE + ".bak"),
		"No .tmp or .bak is left behind a clean write")
	var truncated := FileAccess.open(STORE, FileAccess.WRITE)
	truncated.store_string("{\"score\": 12, \"nam")
	truncated.close()
	var recovered: Variant = SafeJson.read(STORE, {"score": 0})
	_expect(recovered is Dictionary and int(recovered.get("score", -1)) == 0,
		"A truncated file yields the fallback (got %s)" % [recovered])
	_expect(FileAccess.file_exists(STORE + ".bad") and not FileAccess.file_exists(STORE),
		"The bad file is quarantined as .bad")
	var wrong_type: Variant = SafeJson.read(STORE, [])
	_expect(wrong_type is Array, "A missing file yields the fallback's type (got %s)" % [typeof(wrong_type)])
	SafeJson.write(STORE, [1, 2, 3])
	var list: Variant = SafeJson.read(STORE, {})
	_expect(list is Dictionary, "Data of another type than the fallback is treated as corrupt (got %s)" % [list])
	# A crash between rotating the old file to .bak and renaming .tmp leaves
	# only the .bak: the next read gets it back.
	SafeJson.write(STORE, {"kept": true})
	DirAccess.rename_absolute(ProjectSettings.globalize_path(STORE), ProjectSettings.globalize_path(STORE + ".bak"))
	var from_backup: Variant = SafeJson.read(STORE, {})
	_expect(from_backup is Dictionary and bool(from_backup.get("kept", false)),
		"A stranded .bak is recovered (got %s)" % [from_backup])
	var fallback := {"nested": [1]}
	var copy: Variant = SafeJson.read(DIR + "/missing.json", fallback)
	(copy as Dictionary)["nested"].append(2)
	_expect(fallback["nested"].size() == 1, "The fallback is copied, not handed back to be mutated")


func _test_migration() -> void:
	var base: String = ProjectSettings.globalize_path(DIR)
	var legacy: String = base.path_join("Old Name")
	var target: String = base.path_join("New Name")
	DirAccess.make_dir_recursive_absolute(legacy)
	_write(legacy.path_join("settings.cfg"), "old settings")
	_write(legacy.path_join("scores.json"), "[1]")
	_write(legacy.path_join("ignored.txt"), "not listed")
	var files := PackedStringArray(["settings.cfg", "scores.json"])
	UserDataMigration.migrate_between(legacy, target, files)
	_expect(_read(target.path_join("settings.cfg")) == "old settings", "Listed files come over")
	_expect(_read(target.path_join("scores.json")) == "[1]", "Every listed file comes over")
	_expect(not FileAccess.file_exists(target.path_join("ignored.txt")), "Unlisted files stay behind")
	_expect(FileAccess.file_exists(target.path_join(UserDataMigration.MARKER_NAME)), "A marker records the migration")
	DirAccess.remove_absolute(target.path_join("settings.cfg"))
	UserDataMigration.migrate_between(legacy, target, files)
	_expect(not FileAccess.file_exists(target.path_join("settings.cfg")),
		"After the marker nothing is copied again (a reset stays reset)")
	var newer: String = base.path_join("Newer")
	DirAccess.make_dir_recursive_absolute(newer)
	_write(newer.path_join("settings.cfg"), "newer settings")
	UserDataMigration.migrate_between(legacy, newer, files)
	_expect(_read(newer.path_join("settings.cfg")) == "newer settings", "Existing newer data is never overwritten")
	var fresh: String = base.path_join("Fresh")
	UserDataMigration.migrate_between(base.path_join("Missing"), fresh, files)
	_expect(FileAccess.file_exists(fresh.path_join(UserDataMigration.MARKER_NAME)),
		"With no legacy folder the marker is still written")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _cleanup() -> void:
	var base: String = ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(base):
		_remove_tree(base)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
