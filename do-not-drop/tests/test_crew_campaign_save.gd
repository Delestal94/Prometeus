extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_crew_campaign_save.gd
##
## S-105 campaign persistence: safe JSON keeps money, pending supplies and
## merit/cards per colour slot (version 2, N-226.2: "0".."7", the slot the host
## hands out; the host is always 1); a version 1 file, by colour name, is read
## as slots (the colour's index); corrupt data is quarantined and falls back safely.

var _failures: int = 0
var _path: String


func _initialize() -> void:
	_path = "user://crew_campaign_save_%d.json" % Time.get_ticks_usec()
	_cleanup()
	_run()


func _run() -> void:
	var script: Script = load("res://scripts/core/crew_progression.gd")
	var crew: Node = script.new()
	crew.campaign_path = _path
	crew.reset_campaign()
	crew.team_money = 180
	crew.supplies[&"padding"] = true
	crew.merit[1] = 42
	crew.cards[1] = crew.Card.RESCUE
	crew.dry_deliveries[1] = 2
	# Outside the tree: peer 10 falls back to slot 2 (posmod(10, MAX_PLAYERS)).
	crew.merit[10] = 9
	crew.cards[10] = crew.Card.REVOTE
	_expect(crew.save_campaign(), "A valid campaign is written successfully")
	_expect(FileAccess.file_exists(_path), "The campaign file exists after saving")
	_expect(not FileAccess.file_exists(_path + ".tmp"), "The temporary file is gone after the atomic rename")

	var file := FileAccess.open(_path, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	var players: Dictionary = raw.get("players", {})
	_expect(int(raw.get("version", 0)) == 2, "The campaign uses schema version 2 (got %s)" % raw.get("version"))
	_expect(players.has("1") and players.has("2"), "Players are stored by colour slot (got %s)" % [players.keys()])
	_expect(not players.has("10") and not players.has("yellow"), "Neither peer ids nor colour names are player keys")

	var loaded: Node = script.new()
	loaded.campaign_path = _path
	loaded.load_campaign()
	_expect(int(loaded.team_money) == 180, "Loading restores team money (got $%d)" % int(loaded.team_money))
	_expect(bool(loaded.supplies.get(&"padding", false)), "Loading restores a pending supply")
	_expect(int(loaded.merit.get(1, 0)) == 42, "Loading restores merit for the host's slot")
	_expect(int(loaded.cards.get(1, -1)) == loaded.Card.RESCUE, "Loading restores the host's card")
	# 18 falls back to slot 2 too: another peer id on the same slot.
	loaded.call(&"_apply_saved_player", 18)
	_expect(int(loaded.merit.get(18, 0)) == 9,
		"A changed peer id on the same slot restores the same merit (got %d)" % int(loaded.merit.get(18, 0)))
	_expect(int(loaded.cards.get(18, -1)) == loaded.Card.REVOTE,
		"A changed peer id on the same slot restores the same card")

	var legacy := FileAccess.open(_path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": 1, "team_money": 90, "supplies": [],
		"players": {"yellow": {"merit": 42, "card": loaded.Card.RESCUE}, "coral": {"merit": 9}, "red": {"merit": 1}}}))
	legacy.close()
	loaded.reset_campaign()
	loaded.load_campaign()
	_expect(int(loaded.merit.get(1, 0)) == 42 and int(loaded.cards.get(1, -1)) == loaded.Card.RESCUE,
		"A version 1 file: the host's colour (yellow) is still its slot, 1")
	loaded.call(&"_apply_saved_player", 2)
	_expect(int(loaded.merit.get(2, 0)) == 9, "...coral keeps its index, slot 2")

	var corrupt := FileAccess.open(_path, FileAccess.WRITE)
	corrupt.store_string("{\"team_money\":")
	corrupt.close()
	loaded.reset_campaign()
	loaded.load_campaign()
	_expect(int(loaded.team_money) == loaded.STARTING_MONEY,
		"Corrupt JSON falls back to the $100 starting wallet (got $%d)" % int(loaded.team_money))
	_expect(loaded.supplies.is_empty() and loaded.cards.is_empty(), "Corrupt JSON starts with an empty campaign")
	_expect(FileAccess.file_exists(_path + ".bad"), "Corrupt JSON is quarantined as .bad")

	crew.free()
	loaded.free()
	_cleanup()
	if _failures == 0:
		print("PASS: cooperative campaign saves safely by player colour and corrupt JSON falls back to defaults")
	quit(_failures)


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bad"]:
		var candidate: String = _path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
