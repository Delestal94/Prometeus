extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_safe_json.gd
## S-210: profile and leaderboard saves quarantine truncated JSON and recover
## with their defaults instead of crashing or keeping stale in-memory data.

const PROFILE_PATH := "user://safe_json_profile_test.json"
const LEADERBOARD_PATH := "user://safe_json_leaderboard_test.json"

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_cleanup(PROFILE_PATH)
	_cleanup(LEADERBOARD_PATH)
	_test_profile_recovery()
	_test_leaderboard_recovery()
	_cleanup(PROFILE_PATH)
	_cleanup(LEADERBOARD_PATH)
	if _failures == 0:
		print("PASS: truncated profile and leaderboard JSON is quarantined and reset safely")
	quit(_failures)


func _test_profile_recovery() -> void:
	_write_truncated(PROFILE_PATH)
	var profile := preload("res://scripts/core/unlock_manager.gd").new()
	profile.storage_path = PROFILE_PATH
	profile.total_score = 999
	profile.successful_deliveries = 9
	profile.unlocked[&"hostile_trap"] = true
	profile.load_profile()
	_expect(profile.total_score == 0 and profile.successful_deliveries == 0,
		"A truncated profile restores zero progress")
	_expect(profile.unlocked == {&"starter_kit": true},
		"A truncated profile restores only the starter unlock")
	_expect(FileAccess.file_exists(PROFILE_PATH + ".bad"),
		"The truncated profile is preserved as .bad")
	profile.free()


func _test_leaderboard_recovery() -> void:
	_write_truncated(LEADERBOARD_PATH)
	var manager: Node = root.get_node(^"/root/RunManager")
	var original_path: String = String(manager.get(&"save_path"))
	manager.set(&"save_path", LEADERBOARD_PATH)
	manager.set(&"leaderboard", [{"score": 999, "date": "test"}])
	manager.call(&"_load_leaderboard")
	_expect((manager.get(&"leaderboard") as Array).is_empty(),
		"A truncated leaderboard restores an empty ranking")
	_expect(FileAccess.file_exists(LEADERBOARD_PATH + ".bad"),
		"The truncated leaderboard is preserved as .bad")
	manager.set(&"save_path", original_path)


func _write_truncated(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"truncated\":")
	file.close()


func _cleanup(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bad"]:
		var candidate: String = path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
