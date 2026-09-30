extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/unlock_profile/tests/test_unlock_profile.gd
##
## The unlock_profile module on its own (docs/modulos.md), with a game-like
## subclass defined here: a fresh profile has the starter unlock; the next
## reward and its progress follow the rules' stat thresholds; counting up to
## a threshold grants and announces the unlock once; the file keeps the
## game's fields and comes back through the hooks; an older file is granted
## what it already earned and rewritten at the current version; seen flags
## return true once; reset empties everything.

var _failures: int = 0


class GameProfile extends UnlockProfile:
	var wins: int = 0
	var points: int = 0
	var favourite: String = "blue"
	var migrated_from: int = -1

	func _init() -> void:
		storage_path = "user://unlock_profile_module.json"
		profile_version = 3
		unlock_rules = {
			&"hat": {"title": "UNLOCK_HAT", "wins": 1, "points": 0},
			&"cape": {"title": "UNLOCK_CAPE", "wins": 2, "points": 50},
			&"crown": {"title": "UNLOCK_CROWN", "wins": 5, "points": 400},
		}

	func _stat(stat_name: StringName) -> int:
		return wins if stat_name == &"wins" else points

	func _profile_fields() -> Dictionary:
		return {"wins": wins, "points": points, "favourite": favourite}

	func _read_profile(parsed: Dictionary, version: int) -> void:
		wins = int(parsed.get("wins", 0))
		points = int(parsed.get("points", 0))
		favourite = String(parsed.get("favourite", "blue"))
		migrated_from = version

	func _reset_fields() -> void:
		wins = 0
		points = 0
		favourite = "blue"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path: String = "user://test_unlock_profile_module.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var profile := GameProfile.new()
	root.add_child(profile)
	await process_frame
	_expect(profile.storage_path == path,
		"Under a test script the profile uses a test file (got %s)" % profile.storage_path)
	_expect(profile.is_unlocked(&"starter_kit") and not profile.is_unlocked(&"hat"),
		"A fresh profile has only the starter unlock")
	var next: Dictionary = profile.next_unlock_progress()
	_expect(next.get("id") == &"hat" and is_zero_approx(float(next.get("progress", 1.0))),
		"The nearest reward is the hat (got %s)" % [next])
	var earned: Array = []
	profile.unlock_earned.connect(func(id: StringName, title: String) -> void: earned.append([id, title]))
	profile.wins = 1
	profile.points = 30
	var granted: Array[StringName] = profile.announce_new_unlocks()
	_expect(granted == [&"hat"] and earned == [[&"hat",
		"UNLOCK_HAT"]], "Reaching a threshold grants and announces once (got %s)" % [earned])
	next = profile.next_unlock_progress()
	_expect(next.get("id") == &"cape" and int(next.get("current_wins", -1)) == 1
		and int(next.get("target_points", -1)) == 50
		and is_equal_approx(float(next.get("progress", 0.0)), 0.5),
		"Progress is the slowest stat's share (got %s)" % [next])
	_expect(profile.announce_new_unlocks().is_empty(), "Nothing new is granted twice")
	_expect(profile.mark_tip_seen(&"first_box") and not profile.mark_tip_seen(&"first_box"),
		"A seen flag returns true once")
	profile.favourite = "red"
	profile.save_profile()
	profile.free()

	var again := GameProfile.new()
	root.add_child(again)
	await process_frame
	_expect(again.wins == 1 and again.points == 30 and again.favourite == "red",
		"The game's fields come back from the file")
	_expect(again.is_unlocked(&"hat") and again.seen_tips.has(&"first_box"), "Unlocks and seen flags come back")
	_expect(again.migrated_from == 3, "The file's version is handed to the hook (got %d)" % again.migrated_from)
	again.free()

	# An older file whose stats already earn the cape: granted on load, rewritten.
	SafeJson.write(path, {"version": 1, "unlocked": {"starter_kit": true}, "wins": 3, "points": 90})
	var old := GameProfile.new()
	root.add_child(old)
	await process_frame
	_expect(old.is_unlocked(&"hat") and old.is_unlocked(&"cape") and not old.is_unlocked(&"crown"),
		"An older profile is granted what it already earned")
	var rewritten: Dictionary = SafeJson.read(path, {})
	_expect(int(rewritten.get("version", 0)) == 3 and bool(rewritten.get("unlocked", {}).get("cape", false)),
		"The old file is rewritten at the current version with the grants")
	old.reset_profile()
	_expect(old.wins == 0 and not old.is_unlocked(&"hat") and old.is_unlocked(&"starter_kit"),
		"Reset empties the profile")
	old.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures == 0:
		print("PASS: the profile grants, saves, migrates and resets on the module alone")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
