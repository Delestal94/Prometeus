extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/run_log/tests/test_run_log.gd
##
## The run_log module on its own (docs/modulos.md): a record is written as
## JSON under the log folder with the stem given (or the date and time), a
## taken name gets "_2", the file reads back whole, and past max_files the
## oldest names are pruned. Under a test script the folder is a test one.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var log := RunLog.new()
	root.add_child(log)
	await process_frame
	_expect(log.directory == "user://test_run_log",
		"Under a test script the log uses a test folder (got %s)" % log.directory)
	var folder: String = ProjectSettings.globalize_path(log.directory)
	if DirAccess.dir_exists_absolute(folder):
		for file_name: String in DirAccess.get_files_at(log.directory):
			DirAccess.remove_absolute(folder.path_join(file_name))
	var path: String = log.save_record({"score": 12, "boxes": [1, 2]}, "2026-01-02_03-04-05")
	_expect(path == "user://test_run_log/2026-01-02_03-04-05.json" and log.last_file == path,
		"The record is written under the stem (got %s)" % path)
	var back: Variant = SafeJson.read(path, {})
	_expect(back is Dictionary and int(back.get("score", 0)) == 12 and back.get("boxes", []).size() == 2,
		"It reads back whole")
	var second: String = log.save_record({"score": 1}, "2026-01-02_03-04-05")
	_expect(second.ends_with("_2.json"), "A taken name gets a suffix (got %s)" % second)
	var dated: String = log.save_record({"score": 2})
	_expect(dated.get_file().length() == "2026-01-02_03-04-05.json".length(),
		"Without a stem the file is named by date and time (got %s)" % dated.get_file())
	_expect(RunLog.file_stem({"year": 2026,
		"month": 9, "day": 30, "hour": 15, "minute": 4, "second": 9}) == "2026-09-30_15-04-09",
		"The stem is sortable and safe for Windows")
	log.max_files = 2
	log.save_record({"score": 3}, "2026-01-09_00-00-00")
	var names: PackedStringArray = DirAccess.get_files_at(log.directory)
	_expect(names.size() == 2 and not names.has("2026-01-02_03-04-05.json"),
		"Past max_files the oldest names go (kept %s)" % [names])
	for file_name: String in DirAccess.get_files_at(log.directory):
		DirAccess.remove_absolute(folder.path_join(file_name))
	log.free()
	if _failures == 0:
		print("PASS: run records are written, named and pruned on the module alone")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
