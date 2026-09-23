extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_legacy_user_data.gd

var _failures: int = 0


func _initialize() -> void:
	# Scratch folders under user://, never the real settings or leaderboard.
	var root_dir: String = ProjectSettings.globalize_path("user://test_legacy_user_data")
	_remove_tree(root_dir)
	var legacy: String = root_dir.path_join("Do Not Drop")
	var target: String = root_dir.path_join("Take My Package")
	DirAccess.make_dir_recursive_absolute(legacy)
	_write(legacy.path_join("settings.cfg"), "[player]\nmaster_volume=0.3\n")
	_write(legacy.path_join("leaderboard.json"), "[{\"score\": 900}]")

	LegacyUserData.migrate_between(legacy, target)
	_expect(_read(target.path_join("settings.cfg")).contains("master_volume=0.3"), "Settings are carried over from the old folder")
	_expect(_read(target.path_join("leaderboard.json")).contains("900"), "Leaderboard is carried over from the old folder")
	_expect(FileAccess.file_exists(legacy.path_join("settings.cfg")), "Old files are copied, not moved")

	# A reset after migrating must stick: the old file must not come back.
	DirAccess.remove_absolute(target.path_join("settings.cfg"))
	LegacyUserData.migrate_between(legacy, target)
	_expect(not FileAccess.file_exists(target.path_join("settings.cfg")), "Migration runs only once")

	# Newer data in the new folder always wins over the old folder.
	var fresh: String = root_dir.path_join("Fresh")
	DirAccess.make_dir_recursive_absolute(fresh)
	_write(fresh.path_join("settings.cfg"), "[player]\nmaster_volume=0.8\n")
	LegacyUserData.migrate_between(legacy, fresh)
	_expect(_read(fresh.path_join("settings.cfg")).contains("master_volume=0.8"), "Existing new-folder data is never overwritten")

	# First launch ever (no old folder) just leaves the marker behind.
	var brand_new: String = root_dir.path_join("BrandNew")
	LegacyUserData.migrate_between(root_dir.path_join("Missing"), brand_new)
	_expect(not FileAccess.file_exists(brand_new.path_join("settings.cfg")), "No old folder means nothing is copied")

	_remove_tree(root_dir)
	if _failures == 0:
		print("PASS: legacy save folder carries settings and leaderboard over once, never overwriting")
	quit(_failures)


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
