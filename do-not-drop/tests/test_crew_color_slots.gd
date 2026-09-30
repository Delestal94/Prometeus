extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_crew_color_slots.gd
##
## N-226.2: every colour reader and the campaign go by the colour slot the
## host hands out (NetworkManager.color_slot()), never by the peer id:
## - two sessions of five players with big random ENet/Steam-sized ids: the
##   host on slot 1, the joiners on 0, 2, 3, 4 in arrival order, both times; five
##   different colour names and suit colours, the same ones in the second session;
## - the campaign is saved by slot ("0".."7", version 2): what the third
##   player to arrive earned in the first session is what the third to arrive
##   finds in the second, under another peer id;
## - eight players: eight slots; slots 5..7 wear the colours of 0..2 again,
##   but each keeps its own campaign entry;
## - playing solo the host is slot 1, the same entry it has when hosting;
## - a version 1 file (by colour name, the host always "yellow") is read as
##   slots by the colour's index: the host's yellow stays slot 1; unknown keys
##   dropped.

var _failures: int = 0
var _path: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_path = "user://crew_color_slots_%d.json" % Time.get_ticks_usec()
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.call(&"leave_session")
	var crew: Node = load("res://scripts/core/crew_progression.gd").new()
	root.add_child(crew)
	await process_frame
	crew.set(&"campaign_path", _path)
	crew.call(&"reset_campaign")
	var keys: Array = crew.get(&"PLAYER_COLOR_KEYS")
	var palette: Array = load("res://scripts/gameplay/player/player.gd").get_script_constant_map()["PLAYER_COLORS"]
	var max_players: int = int(network.get(&"MAX_PLAYERS"))

	_expect(int(network.call(&"color_slot", 1)) == 1 and int(crew.call(&"player_slot", 1)) == 1,
		"Playing solo the host wears slot 1")

	var rng := RandomNumberGenerator.new()
	rng.seed = 2262
	# Session one: five players, the third earns merit.
	var first: Array[int] = _seat_crew(network, rng, 4)
	var first_slots: Array = first.map(func(id: int) -> int: return int(network.call(&"color_slot", id)))
	_expect(first_slots == [1, 0, 2, 3, 4],
		"Five players with big random ids: the host 1, the joiners 0, 2, 3, 4 (got %s)" % [first_slots])
	var names: Dictionary = {}
	var suits: Dictionary = {}
	for id: int in first:
		names[String(crew.call(&"player_color_key", id))] = true
		suits[palette[posmod(int(network.call(&"color_slot", id)), palette.size())]] = true
	_expect(names.size() == 5 and suits.size() == 5,
		"...five different colour names and suits (got %s)" % [names.keys()])
	var first_names: Array = first.map(func(id: int) -> String: return String(crew.call(&"player_color_key", id)))
	crew.call(&"award_action", first[2], &"test:slots:1", 25)
	crew.call(&"award_action", first[1], &"test:slots:2", 10)
	_expect(bool(crew.call(&"save_campaign")), "The campaign is saved")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path))
	var players: Dictionary = raw.get("players", {})
	_expect(int(raw.get("version", 0)) == 2, "The campaign is version 2 (got %s)" % raw.get("version"))
	_expect(players.has("1") and players.has("2") and not players.has("yellow") and not players.has(str(first[2])),
		"Players are kept by slot, not by colour name or peer id (got %s)" % [players.keys()])
	_expect(int((players.get("2", {}) as Dictionary).get("merit", 0)) == 25, "The third to arrive is slot 2's entry")
	network.call(&"leave_session")

	# Session two: other ids, same arrival order.
	var second: Array[int] = _seat_crew(network, rng, 4)
	var second_slots: Array = second.map(func(id: int) -> int: return int(network.call(&"color_slot", id)))
	var second_names: Array = second.map(func(id: int) -> String: return String(crew.call(&"player_color_key", id)))
	_expect(second[2] != first[2], "The second session has other peer ids")
	_expect(second_slots == first_slots and second_names == first_names,
		"Other ids, same slots and colours (got %s / %s)" % [second_slots, second_names])
	crew.call(&"load_campaign")
	for id: int in second:
		crew.call(&"_apply_saved_player", id)
	var merit: Dictionary = crew.get(&"merit")
	_expect(int(merit.get(second[2], 0)) == 25 and int(merit.get(second[1], 0)) == 10,
		"Each finds the merit of its slot under a new peer id (got %s)" % [merit])

	# Eight players: slots 5..7 share colours with 0..2, never an entry.
	var more: Array[int] = []
	for index: int in 3:
		var id: int = rng.randi_range(1_800_000_000, 2_147_483_647)
		network.call(&"_admit_peer", id)
		network.call(&"_on_peer_connected", id)
		more.append(id)
	var all_slots: Dictionary = {}
	for id: int in network.get(&"peer_ids"):
		all_slots[int(network.call(&"color_slot", id))] = true
	_expect(all_slots.size() == max_players, "Eight players, eight slots (got %s)" % [all_slots.keys()])
	var sixth: int = more[0]
	_expect(int(network.call(&"color_slot", sixth)) == 5
		and String(crew.call(&"player_color_key", sixth)) == String(keys[0]),
		"Slot 5 wears slot 0's colour again")
	crew.call(&"award_action", sixth, &"test:slots:3", 7)
	crew.call(&"_capture_current_players")
	var by_slot: Dictionary = crew.get(&"_saved_players_by_slot")
	_expect(int((by_slot.get("5", {}) as Dictionary).get("merit", 0)) == 7
		and int((by_slot.get("0", {}) as Dictionary).get("merit", 0)) == 10,
		"...but keeps its own campaign entry (got %s)" % [by_slot])
	network.call(&"leave_session")

	# A version 1 file, by colour name.
	var legacy := FileAccess.open(_path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": 1, "team_money": 150, "supplies": [], "players": {
		"yellow": {"merit": 42, "card": 0, "dry_deliveries": 1},
		"mint": {"merit": 7, "card": -1, "dry_deliveries": 0},
		"violet": {"merit": 3},
		"bogus": {"merit": 99},
	}}))
	legacy.close()
	crew.call(&"reset_campaign")
	crew.call(&"load_campaign")
	var migrated: Dictionary = crew.get(&"_saved_players_by_slot")
	_expect(int((migrated.get("1", {}) as Dictionary).get("merit", 0)) == 42
		and int((migrated.get("0", {}) as Dictionary).get("merit", 0)) == 7
		and int((migrated.get("4", {}) as Dictionary).get("merit", 0)) == 3,
		"Version 1: yellow (the host) -> slot 1, mint -> 0, violet -> 4 (got %s)" % [migrated])
	_expect(migrated.size() == 3, "An unknown key is dropped (got %s)" % [migrated.keys()])
	_expect(int((crew.get(&"merit") as Dictionary).get(1, 0)) == 42, "Solo, the host gets its old merit back")

	crew.queue_free()
	await process_frame
	_cleanup()
	if _failures == 0:
		print("PASS: colours and the campaign go by the host's slot: distinct, stable across sessions, migrated")
	quit(_failures)


## A crew of the host plus `count` joiners with big random ids, in order.
func _seat_crew(network: Node, rng: RandomNumberGenerator, count: int) -> Array[int]:
	var ids: Array[int] = [1]
	while ids.size() < count + 1:
		var id: int = rng.randi_range(1_800_000_000, 2_147_483_647)
		if ids.has(id):
			continue
		_expect(String(network.call(&"_admit_peer", id)).is_empty(), "Peer %d is admitted" % id)
		network.call(&"_on_peer_connected", id)
		ids.append(id)
	return ids


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bad"]:
		if FileAccess.file_exists(_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
