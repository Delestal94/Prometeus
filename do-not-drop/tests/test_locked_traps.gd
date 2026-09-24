extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_locked_traps.gd
##
## Liquid, Explosive and Hostile are unlocks (UnlockManager.UNLOCKS), but the
## depot used to shelve all seven traps from the very first run. Now:
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
	var locked: Array = (unlocks.call(&"locked_traps") as Array).map(func(id: StringName) -> String: return String(id))
	locked.sort()
	_expect(locked == ["explosive", "hostile", "liquid"], "A fresh profile has the three new traps locked (got %s)" % str(locked))

	var kinds: Array = await _shelved_kinds()
	_expect(kinds.size() == 8 and not (kinds.has("liquid") or kinds.has("explosive") or kinds.has("hostile")),
		"Solo with a fresh profile: only the four starting traps, two of each (got %s)" % str(kinds))

	unlocks.unlocked[&"liquid_trap"] = true
	kinds = await _shelved_kinds()
	_expect(kinds.count("liquid") == 2 and kinds.size() == 10, "Unlocking Liquid puts both of its boxes on the shelves (got %s)" % str(kinds))

	# Online: the host's list, not this profile's (which has everything but
	# Liquid locked here).
	network.world_seed = 77
	network.world_locked_traps = [&"hostile"]
	kinds = await _shelved_kinds()
	_expect(kinds.size() == 12 and not kinds.has("hostile") and kinds.has("explosive"),
		"Online, the host's locked list decides what's shelved (got %s)" % str(kinds))

	network.world_seed = original_seed
	network.world_locked_traps = []
	unlocks.call(&"reset_profile")
	if _failures == 0:
		print("PASS: locked traps stay off the depot's shelves, and online the host's profile decides")
	quit(_failures)


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
