extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_nickname.gd
##
## The player's nickname (N-606.1, scripts/core/nickname.gd):
## - what a nickname may be: trimmed, single spaces, no control characters,
##   brackets or braces, at most 16 characters; empty gets a funny one from the
##   seed, as a line to translate, the same for the same seed;
## - the funny names are all in the table in both languages;
## - it is part of the profile (unlock_manager.gd): typed, clamped, saved,
##   loaded, and forgotten on reset;
## - the appearance panel has a field for it that saves on Enter or leaving it
##   and is reachable from the face options by focus (cosmetics_panel.gd);
## - it travels with the appearance: the player's PlayerNickname is replicated on
##   spawn and on change, and cleans whatever a remote peer writes.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var nickname_script: GDScript = load("res://scripts/core/nickname.gd")
	var max_length: int = int(nickname_script.get("MAX_LENGTH"))
	_expect(max_length == 16, "A nickname is at most 16 characters (got %d)" % max_length)
	var clean: Callable = func(text: String) -> String: return nickname_script.call(&"clean", text)
	_expect(clean.call("  Turbo  ") == "Turbo", "Edges are trimmed")
	_expect(clean.call("Manos   de    Manteca") == "Manos de Manteca", "Runs of spaces become one")
	_expect(clean.call("a\tb\nc") == "abc", "Control characters are dropped (got %s)" % clean.call("a\tb\nc"))
	_expect(clean.call("[b]Hi[/b] {a} <x> 5%") == "bHi/b a x 5",
			"Brackets, braces, angle brackets and percents are dropped (got %s)" % clean.call("[b]Hi[/b] {a} <x> 5%"))
	_expect(clean.call("12345678901234567890") == "1234567890123456",
			"Longer than 16 is cut (got %s)" % clean.call("12345678901234567890"))
	_expect(clean.call("Ñandú Ñu") == "Ñandú Ñu", "Accents are kept")
	_expect(clean.call("               ") == "", "Only spaces is empty")
	_expect(clean.call("abc def ghi jkl mno") == "abc def ghi jkl",
			"The cut doesn't leave a trailing space (got '%s')" % clean.call("abc def ghi jkl mno"))

	var resolved: Variant = nickname_script.call(&"resolve", "Turbo", 5)
	_expect(resolved is String and resolved == "Turbo", "A typed nickname travels as text")
	var funny: Variant = nickname_script.call(&"resolve", "  ", 5)
	_expect(funny is Array and (funny as Array).size() == 1 and String((funny as Array)[0]).begins_with("UI_NICK_"),
			"An empty one travels as a funny name's key (got %s)" % str(funny))
	_expect(funny == nickname_script.call(&"resolve", "", 5), "The same seed gets the same funny name")
	var kinds: Dictionary = {}
	for seed_value: int in range(1, 200):
		kinds[nickname_script.call(&"auto_key", seed_value)] = true
	_expect(kinds.size() >= 20, "Seeds spread over the funny names (%d of 24)" % kinds.size())
	_expect(nickname_script.call(&"display", "", 5) != String((funny as Array)[0]),
			"display() translates the funny name")
	_check_table(nickname_script)

	await _check_profile()
	await _check_panel()
	await _check_player()
	if _failures == 0:
		print("PASS: nicknames are cleaned, funny when empty, saved, typed in the panel and replicated with the player")
	quit(_failures)


func _check_table(nickname_script: GDScript) -> void:
	var keys: Array = nickname_script.get("AUTO_KEYS")
	_expect(keys.size() == 24, "There are 24 funny names (got %d)" % keys.size())
	var file := FileAccess.open("res://translations/strings_ui.csv", FileAccess.READ)
	var table: Dictionary = {}
	file.get_csv_line()
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() >= 3:
			table[line[0]] = [line[1], line[2]]
	var seen: Dictionary = {}
	for key: String in keys:
		_expect(table.has(key), "%s is in the table" % key)
		if not table.has(key):
			continue
		for language: int in 2:
			var name_text: String = table[key][language]
			_expect(not name_text.is_empty() and name_text.length() <= 16,
					"%s is a name of up to 16 characters in language %d (got '%s')" % [key, language, name_text])
			_expect(nickname_script.call(&"clean", name_text) == name_text,
					"%s survives being cleaned (%s)" % [key, name_text])
		seen[table[key][0]] = true
	_expect(seen.size() == keys.size(), "No two funny names are the same")


func _check_profile() -> void:
	var profile_script: GDScript = load("res://scripts/core/unlock_manager.gd")
	var profile: Node = profile_script.new()
	profile.set(&"storage_path", "user://nickname_test.json")
	profile.call(&"reset_profile")
	_expect(String(profile.get(&"nickname")) == "", "A new profile has no nickname")
	profile.call(&"set_nickname", "  Turbo [x] ")
	_expect(String(profile.get(&"nickname")) == "Turbo x",
			"The profile keeps the cleaned nickname (got '%s')" % profile.get(&"nickname"))
	profile.call(&"set_nickname", "12345678901234567890")
	_expect(String(profile.get(&"nickname")).length() == 16, "The profile clamps it to 16")
	profile.call(&"set_nickname", "Ana")
	var restored: Node = profile_script.new()
	restored.set(&"storage_path", "user://nickname_test.json")
	restored.call(&"load_profile")
	_expect(String(restored.get(&"nickname")) == "Ana",
			"The nickname survives save and load (got '%s')" % restored.get(&"nickname"))
	var file := FileAccess.open("user://nickname_test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 4, "nickname": "Muy largo y con {cosas} [raras]\n"}))
	file.close()
	restored.call(&"load_profile")
	_expect(String(restored.get(&"nickname")) == "Muy largo y con",
			"A saved nickname is cleaned when loaded (got '%s')" % restored.get(&"nickname"))
	file = FileAccess.open("user://nickname_test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 3, "selected_cosmetic": "mint_uniform"}))
	file.close()
	restored.call(&"load_profile")
	_expect(String(restored.get(&"nickname")) == "", "An older profile has no nickname")
	var changes: Array = []
	profile.connect(&"progress_changed", func() -> void: changes.append(1))
	profile.call(&"set_nickname", "Ana")
	_expect(changes.is_empty(), "Setting the same nickname changes nothing")
	profile.call(&"set_nickname", "Beto")
	_expect(changes.size() == 1, "A new nickname tells the listeners once")
	profile.call(&"reset_profile")
	_expect(String(profile.get(&"nickname")) == "", "Resetting the profile forgets the nickname")
	profile.free()
	restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://nickname_test.json"))
	await process_frame


func _check_panel() -> void:
	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	unlocks.call(&"reset_profile")
	var panel: Control = load("res://scripts/ui/cosmetics_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var edit: LineEdit = panel.find_child("NicknameEdit", true, false) as LineEdit
	_expect(edit != null, "The appearance panel has a nickname field")
	if edit == null:
		panel.queue_free()
		return
	_expect(edit.max_length == 16, "The field takes 16 characters")
	_expect(edit.placeholder_text == tr("UI_COSM_NICKNAME_PLACEHOLDER"), "An empty field says a funny one is given")
	edit.text = "  Turbo  "
	edit.text_submitted.emit(edit.text)
	_expect(String(unlocks.get(&"nickname")) == "Turbo",
			"Enter saves the nickname (got '%s')" % unlocks.get(&"nickname"))
	_expect(edit.text == "Turbo", "The field shows it as it was cleaned (got '%s')" % edit.text)
	edit.text = "Ana"
	edit.focus_exited.emit()
	_expect(String(unlocks.get(&"nickname")) == "Ana", "Leaving the field saves it")
	edit.text = "Beto"
	panel.call(&"close")
	_expect(String(unlocks.get(&"nickname")) == "Beto", "Closing the panel saves it")
	var eyes: Button = panel.find_child("Eyes_classic", true, false) as Button
	_expect(eyes != null and edit.get_node(edit.focus_neighbor_bottom) == eyes,
			"Down from the field reaches the first eyes")
	_expect(eyes != null and eyes.get_node(eyes.focus_neighbor_top) == edit, "Up from the first eyes reaches the field")
	var face_buttons: Array = panel.find_children("Eyes_*", "Button", true, false)
	_expect(face_buttons.size() >= 4, "The eyes are in a grid under it")
	for index: int in mini(4, face_buttons.size()):
		_expect((face_buttons[index] as Button).get_node((face_buttons[index] as Button).focus_neighbor_top) == edit,
				"Every button of the first row goes up to the field")
	panel.queue_free()
	unlocks.call(&"reset_profile")
	await process_frame


func _check_player() -> void:
	var scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")
	var player: Node3D = scene.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	player.set_physics_process(false)
	var component: Node = player.get_node_or_null(^"PlayerNickname")
	_expect(component != null, "The player carries a nickname component")
	var profile: Node = root.get_node(^"/root/UnlockManager")
	profile.call(&"set_nickname", "Beto")
	_expect(String(component.get(&"nickname")) == "Beto",
			"The local player follows their profile's nickname (got '%s')" % component.get(&"nickname"))
	profile.call(&"reset_profile")
	component.set(&"nickname", "  Ana [x] {town} ")
	_expect(String(component.get(&"nickname")) == "Ana x town",
			"The player cleans what it is given, like a remote peer's (got '%s')" % component.get(&"nickname"))
	component.set(&"nickname", "x".repeat(40))
	_expect(String(component.get(&"nickname")).length() == 16, "The player's nickname is at most 16 characters")
	var reader: GDScript = load("res://scripts/gameplay/player/player_nickname.gd")
	_expect(reader.call(&"of", player) == "x".repeat(16) and reader.call(&"of", null) == ""
			and reader.call(&"of", root) == "",
			"PlayerNickname.of() reads a player's nickname, and is empty for anything else")
	var sync: MultiplayerSynchronizer = player.get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var config: SceneReplicationConfig = sync.replication_config
	var path: NodePath = NodePath("PlayerNickname:nickname")
	_expect(config.has_property(path), "The nickname is replicated with the appearance")
	if config.has_property(path):
		_expect(config.property_get_spawn(path), "It is sent when the player spawns, so late joiners have it")
		_expect(config.property_get_replication_mode(path) == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
				"It is sent when it changes, not every tick")
	var face_path: NodePath = NodePath(".:face_eyes")
	_expect(config.property_get_replication_mode(path) == config.property_get_replication_mode(face_path),
			"It travels the same way as the face")
	player.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
