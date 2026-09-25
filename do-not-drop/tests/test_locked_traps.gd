extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_locked_traps.gd
##
## Only Fragile and Balance begin unlocked. The rest follow the profile curve:
##   - a trap the profile hasn't unlocked stays off the shelves, both boxes;
##   - unlocking it puts it back;
##   - online, the list is the host's (NetworkManager.world_locked_traps,
##     handed over with the seed), whatever this player's own profile says --
##     every peer has to shelve the same replicated boxes.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var original_seed: int = int(network.world_seed)

	unlocks.call(&"reset_profile")
	var expected_curve := {
		&"growing_weight_trap": [1, 0],
		&"noisy_trap": [2, 100],
		&"liquid_trap": [4, 250],
		&"explosive_trap": [8, 750],
		&"hostile_trap": [13, 1500],
	}
	for unlock_id: StringName in expected_curve:
		var rule: Dictionary = unlocks.call(&"requirements", unlock_id)
		var expected: Array = expected_curve[unlock_id]
		_expect(int(rule.get("deliveries", -1)) == expected[0] and int(rule.get("score", -1)) == expected[1],
			"%s uses the gradual delivery/score threshold" % unlock_id)
	var locked: Array = (unlocks.call(&"locked_traps") as Array).map(func(id: StringName) -> String: return String(id))
	locked.sort()
	_expect(locked == ["explosive", "growing_weight", "hostile", "liquid", "noisy"], "A fresh profile starts with only Fragile and Balance (got %s)" % str(locked))

	var kinds: Array = await _shelved_kinds()
	_expect(kinds.size() == 4 and kinds.count("fragile") == 2 and kinds.count("balance") == 2,
		"Solo with a fresh profile: two starter traps, two boxes each (got %s)" % str(kinds))
	var five_player_locked: Array = unlocks.call(&"locked_traps", 5)
	var available_boxes: int = (unlocks.TRAP_DIFFICULTY_ORDER.size() - five_player_locked.size()) * unlocks.BOXES_PER_TRAP
	_expect(available_boxes >= 4, "Four starter boxes cover the maximum four delivery houses")
	var shortage: Array[StringName] = [&"growing_weight", &"noisy", &"liquid", &"explosive", &"hostile"]
	var recovered: Array = unlocks.call(&"_ensure_trap_capacity", shortage, 5)
	_expect(not recovered.has(&"growing_weight") and recovered.has(&"noisy"),
		"If stock is short, the lowest-difficulty missing trap is released first")

	unlocks.unlocked[&"growing_weight_trap"] = true
	kinds = await _shelved_kinds()
	_expect(kinds.count("growing_weight") == 2 and kinds.size() == 6, "Unlocking Growing Weight puts both of its boxes on the shelves (got %s)" % str(kinds))

	_test_v2_profile_migration()

	# Online: the host's list, not this profile's (which has everything but
	# Hostile locked here).
	network.world_seed = 77
	network.world_locked_traps = [&"hostile"]
	kinds = await _shelved_kinds()
	_expect(kinds.size() == 12 and not kinds.has("hostile") and kinds.has("explosive"),
		"Online, the host's locked list decides what's shelved (got %s)" % str(kinds))

	network.world_seed = original_seed
	network.world_locked_traps = []
	unlocks.call(&"reset_profile")
	if _failures == 0:
		print("PASS: gradual trap unlocks, profile migration and depot capacity")
	quit(_failures)


func _test_v2_profile_migration() -> void:
	var path := "user://locked_traps_v2_profile.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": 2,
		"total_score": 800,
		"successful_deliveries": 8,
		"completed_runs": 9,
		"unlocked": {"starter_kit": true, "sky_uniform": true},
	}))
	file = null
	var migrated := preload("res://scripts/core/unlock_manager.gd").new()
	migrated.storage_path = path
	migrated.load_profile()
	_expect(migrated.is_unlocked(&"growing_weight_trap"), "A v2 profile receives Growing Weight retroactively")
	_expect(migrated.is_unlocked(&"noisy_trap"), "A v2 profile receives Noisy retroactively")
	_expect(migrated.is_unlocked(&"liquid_trap") and migrated.is_unlocked(&"explosive_trap"), "A v2 profile receives every new threshold it already meets")
	_expect(not migrated.is_unlocked(&"hostile_trap"), "Migration does not grant thresholds the profile has not reached")
	_expect(migrated.is_unlocked(&"sky_uniform"), "Migration never removes an existing unlock")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(saved is Dictionary and int(saved.get("version", 0)) == 3, "The migrated profile is persisted as version 3")
	migrated.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Trap ids of every box the level ends up with, sorted.
func _shelved_kinds() -> Array:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var kinds: Array = []
	for package: Node in level.get(&"packages"):
		kinds.append(String(package.get(&"trap_definition").get(&"id")))
	var in_group: int = get_nodes_in_group(&"cargo").size()
	_expect(in_group == kinds.size(), "Withheld boxes are gone from the level, not just from its list (%d in the group, %d kept)" % [in_group, kinds.size()])
	kinds.sort()
	level.queue_free()
	await process_frame
	await process_frame
	return kinds


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
