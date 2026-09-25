extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_crew_campaign_save.gd
##
## S-105 campaign persistence: safe JSON keeps money, pending supplies and
## per-colour merit/cards; corrupt data is quarantined and falls back safely.

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
	crew.merit[2] = 9
	crew.cards[2] = crew.Card.REVOTE
	_expect(crew.save_campaign(), "A valid campaign is written successfully")
	_expect(FileAccess.file_exists(_path), "The campaign file exists after saving")
	_expect(not FileAccess.file_exists(_path + ".tmp"), "The temporary file is gone after the atomic rename")

	var file := FileAccess.open(_path, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	var players: Dictionary = raw.get("players", {})
	_expect(int(raw.get("version", 0)) == 1, "The campaign uses schema version 1 (got %s)" % raw.get("version"))
	_expect(players.has("yellow") and players.has("coral"), "Players are stored by stable colour keys (got %s)" % [players.keys()])
	_expect(not players.has("1") and not players.has("2"), "Transient peer ids are not JSON player keys")

	var loaded: Node = script.new()
	loaded.campaign_path = _path
	loaded.load_campaign()
	_expect(int(loaded.team_money) == 180, "Loading restores team money (got $%d)" % int(loaded.team_money))
	_expect(bool(loaded.supplies.get(&"padding", false)), "Loading restores a pending supply")
	_expect(int(loaded.merit.get(1, 0)) == 42, "Loading restores merit for the current yellow player")
	_expect(int(loaded.cards.get(1, -1)) == loaded.Card.RESCUE, "Loading restores the yellow player's card")
	loaded.call(&"_apply_saved_player", 6)
	_expect(int(loaded.merit.get(6, 0)) == 42,
		"A changed peer id with the same colour restores the same merit (got %d)" % int(loaded.merit.get(6, 0)))
	_expect(int(loaded.cards.get(6, -1)) == loaded.Card.RESCUE,
		"A changed peer id with the same colour restores the same card")

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
