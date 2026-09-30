extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_crew_campaign_save.gd
##
## S-105 campaign persistence: safe JSON keeps money, pending supplies and
## per-colour merit/cards; corrupt data is quarantined and falls back safely.
## Since N-226.2 (CAMPAIGN_VERSION 2) a player's colour is the colour slot the
## host gave it, so the file keys players by slot ("0".."4"), and a new peer id
## in the same slot gets the same progress back. The slots are set by hand on
## the NetworkManager autoload (offline, nothing is sent) and restored after.

## Peer ids the size ENet hands out: the one that saved and the one that comes
## back in the same seat with another id.
const JOINER: int = 2043517840
const REJOINER: int = 1873311209

var _failures: int = 0
var _path: String


func _initialize() -> void:
	_path = "user://crew_campaign_save_%d.json" % Time.get_ticks_usec()
	_cleanup()
	# Deferred: the NetworkManager autoload is in the tree by then.
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var old_slots: Dictionary = (network.get(&"_color_slots") as Dictionary).duplicate()
	# The host is slot 0 (mint), the joiner slot 1 (yellow).
	network.set(&"_color_slots", {1: 0, JOINER: 1})
	var script: Script = load("res://scripts/core/crew_progression.gd")
	var crew: Node = script.new()
	crew.campaign_path = _path
	crew.reset_campaign()
	crew.team_money = 180
	crew.supplies[&"padding"] = true
	crew.merit[1] = 42
	crew.cards[1] = crew.Card.RESCUE
	crew.dry_deliveries[1] = 2
	crew.merit[JOINER] = 9
	crew.cards[JOINER] = crew.Card.REVOTE
	_expect(crew.save_campaign(), "A valid campaign is written successfully")
	_expect(FileAccess.file_exists(_path), "The campaign file exists after saving")
	_expect(not FileAccess.file_exists(_path + ".tmp"), "The temporary file is gone after the atomic rename")

	var file := FileAccess.open(_path, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	var players: Dictionary = raw.get("players", {})
	_expect(int(raw.get("version", 0)) == int(crew.CAMPAIGN_VERSION) and int(raw.get("version", 0)) == 2,
		"The campaign uses schema version 2 (got %s)" % raw.get("version"))
	_expect(players.has("0") and players.has("1") and players.size() == 2,
		"Players are stored by colour slot (got %s)" % [players.keys()])
	_expect(not players.has(str(JOINER)), "Transient peer ids are not JSON player keys")
	_expect(int(Dictionary(players.get("1", {})).get("merit", -1)) == 9,
		"The joiner's merit is saved under its slot (got %s)" % [players])

	var loaded: Node = script.new()
	loaded.campaign_path = _path
	loaded.load_campaign()
	_expect(int(loaded.team_money) == 180, "Loading restores team money (got $%d)" % int(loaded.team_money))
	_expect(bool(loaded.supplies.get(&"padding", false)), "Loading restores a pending supply")
	_expect(int(loaded.merit.get(1, 0)) == 42, "Loading restores merit for the host (slot 0)")
	_expect(int(loaded.cards.get(1, -1)) == loaded.Card.RESCUE, "Loading restores the host's card")
	# Next session: the joiner comes back with another id, in the same slot.
	network.set(&"_color_slots", {1: 0, REJOINER: 1})
	loaded.call(&"_apply_saved_player", REJOINER)
	_expect(int(loaded.merit.get(REJOINER, 0)) == 9,
		"A changed peer id with the same colour restores the same merit (got %d)" % int(loaded.merit.get(REJOINER, 0)))
	_expect(int(loaded.cards.get(REJOINER, -1)) == loaded.Card.REVOTE,
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
	network.set(&"_color_slots", old_slots)
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
