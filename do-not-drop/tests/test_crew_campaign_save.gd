extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_crew_campaign_save.gd
##
## S-105 campaign persistence: safe JSON keeps money, pending supplies and
## per-colour merit/cards; corrupt data is quarantined and falls back safely.
## Since N-226.2 (CAMPAIGN_VERSION 2) a player's colour is the colour slot the
## host gave it, so the file keys players by slot ("0".."4"), and a new peer id
## in the same slot gets the same progress back. The slots are set by hand on
## the NetworkManager autoload (offline, nothing is sent) and restored after.
## N-923.2 (CAMPAIGN_VERSION 3): the accessory shop's inventory is saved by colour
## key ("accessories": {"mint": {owned, equipped}}), so it follows the colour to a
## new peer id; a version-2 file loads with no accessories and the next save is
## version 3; a reset campaign has none; hostile accessory data (unknown ids,
## doubled copies, wrong types, unknown colours, accessories in an old version)
## is dropped without crashing.

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
	crew.accessories.grant("mint", &"cap")
	crew.accessories.equip("mint", &"cap")
	crew.accessories.grant("yellow", &"hi_vis_vest")
	crew.accessories.grant("yellow", &"hard_hat")
	crew.accessories.equip("yellow", &"hard_hat")
	_expect(crew.save_campaign(), "A valid campaign is written successfully")
	_expect(FileAccess.file_exists(_path), "The campaign file exists after saving")
	_expect(not FileAccess.file_exists(_path + ".tmp"), "The temporary file is gone after the atomic rename")

	var file := FileAccess.open(_path, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	var players: Dictionary = raw.get("players", {})
	_expect(int(raw.get("version", 0)) == int(crew.CAMPAIGN_VERSION) and int(raw.get("version", 0)) == 3,
		"The campaign uses schema version 3 (got %s)" % raw.get("version"))
	_expect(players.has("0") and players.has("1") and players.size() == 2,
		"Players are stored by colour slot (got %s)" % [players.keys()])
	_expect(not players.has(str(JOINER)), "Transient peer ids are not JSON player keys")
	_expect(int(Dictionary(players.get("1", {})).get("merit", -1)) == 9,
		"The joiner's merit is saved under its slot (got %s)" % [players])

	var saved_accessories: Dictionary = raw.get("accessories", {})
	var yellow_entry: Dictionary = saved_accessories.get("yellow", {})
	_expect(saved_accessories.keys() == ["mint", "yellow"]
			and yellow_entry.get("owned", []) == ["hi_vis_vest", "hard_hat"]
			and yellow_entry.get("equipped", {}) == {"head": "hard_hat"},
		"Accessories are saved by colour key, owned and worn (got %s)" % [saved_accessories])
	_expect(not saved_accessories.has(str(JOINER)) and not saved_accessories.has("1"),
		"...never by peer id or slot number")

	var loaded: Node = script.new()
	loaded.campaign_path = _path
	loaded.load_campaign()
	_expect(loaded.accessories.to_dict() == crew.accessories.to_dict(),
		"Loading restores every accessory exactly as saved (got %s)" % [loaded.accessories.to_dict()])
	_expect(loaded.accessories.is_equipped("mint", &"cap") and loaded.accessories.is_equipped("yellow", &"hard_hat")
			and not loaded.accessories.is_equipped("yellow", &"hi_vis_vest"),
		"...and what each colour wears")
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

	_expect(loaded.accessories.owns(loaded.player_color_key(REJOINER), &"hi_vis_vest"),
		"A changed peer id in the same seat finds the same colour's accessories")

	_check_accessory_files(loaded)

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


## N-923.2: old versions, hostile data and reset, on the CrewProgression `crew`.
func _check_accessory_files(crew: Node) -> void:
	# A version-2 file (before accessories) loads without them, and with its money.
	_write(JSON.stringify({"version": 2, "team_money": 130, "players": {"0": {"merit": 11}}}))
	crew.accessories.grant("coral", &"cap")
	crew.load_campaign()
	_expect(crew.accessories.is_empty() and int(crew.team_money) == 130,
		"A version-2 campaign loads with no accessories and keeps its money (got %s)" % [crew.accessories.to_dict()])
	_expect(crew.save_campaign(), "The migrated campaign saves")
	var migrated: Dictionary = _read()
	_expect(int(migrated.get("version", 0)) == 3 and migrated.get("accessories", null) == {},
		"The next save is version 3 with an empty accessories table (got %s)" % [migrated])
	# Accessories in a file that claims to be version 2 are not a thing: ignored.
	_write(JSON.stringify({"version": 2, "accessories": {"mint": {"owned": ["cap"]}}}))
	crew.load_campaign()
	_expect(crew.accessories.is_empty(), "Accessories in a version-2 file are ignored")
	# Version 3 with garbage: nothing crashes, only what holds is kept.
	_write(JSON.stringify({"version": 3, "accessories": {
		"mint": {"owned": ["cap", "cap", "jetpack", 4], "equipped": {"head": "cap", "back": "hard_hat"}},
		"violet": {"owned": ["cap", "thermal_backpack"], "equipped": "none"},
		"chartreuse": {"owned": ["hi_vis_vest"]},
		"sky": 12}}))
	crew.load_campaign()
	_expect(crew.accessories.owned_by("mint") == [&"cap"] and crew.accessories.equipped_by("mint") == {&"head": &"cap"},
		"Unknown ids, repeats and misplaced worn items are dropped (got %s)" % [crew.accessories.to_dict()])
	_expect(crew.accessories.owned_by("violet") == [&"thermal_backpack"]
			and crew.accessories.owner_of(&"cap") == "mint",
		"One copy only, even in a doctored file")
	_expect(crew.accessories.owner_of(&"hi_vis_vest") == "", "A colour that does not exist owns nothing")
	for junk: Variant in ["text", 5, [1, 2], null]:
		_write(JSON.stringify({"version": 3, "accessories": junk}))
		crew.load_campaign()
		_expect(crew.accessories.is_empty(), "accessories of the wrong type (%s) loads as none" % [junk])
	# A new campaign wipes them, and the wipe is what gets saved.
	crew.accessories.grant("mint", &"cap")
	crew.reset_campaign(true)
	_expect(crew.accessories.is_empty() and _read().get("accessories", null) == {},
		"reset_campaign() removes every accessory, in memory and in the file")


func _write(text: String) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	return parsed if parsed is Dictionary else {}


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bad"]:
		var candidate: String = _path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
