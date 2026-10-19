extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_options_controls.gd
##
## The keyboard and gamepad remapping of the options screen (N-966.1/.2/.3,
## game_settings.gd, pad_binding.gd, options_controls_section.gd):
## - inventory: every action the player presses is rebindable and has a
##   shipped key, a row (key button + "put it back" button) and a text in both
##   languages; the camera/dev/pause actions are not offered;
## - every Input Map action of the project with a keyboard key is either
##   rebindable or on an explicit not-offered list (a new key action fails here);
## - the keys of the not-offered actions (R, C, F-keys...) are refused as reserved;
## - the interaction events follow the actions only (no hard-coded E / Q / T);
## - the shipped keys do not clash with each other (W is walk forward and
##   accelerate, but never in the same context);
## - every action can be rebound: the InputMap gets exactly that key, keeps its
##   mouse / gamepad events, and the label follows;
## - a key another action uses in a shared context is swapped (the other gets
##   the old key); a swap that cannot be clean, a reserved key (Esc, F11) or an
##   unknown action changes nothing; an action in another context keeps the key;
## - "put it back" per action restores the shipped key (care_work: back to the
##   mouse only), swapping back if needed;
## - the bindings survive a restart (the file is read back into the InputMap),
##   and reset_to_defaults() puts them all back;
## - the options screen: a row waits for a key, takes it even if it is a key
##   focus navigation would swallow (Tab), shows the swap notice, Esc cancels;
## - gamepad (N-966.3): a button and a stick / trigger direction per action. The
##   shipped codes are project.godot's; every action rebinds to a free button or
##   axis (InputMap gets exactly that gamepad event, keeps its keyboard / mouse
##   ones, the label names it); an input another action uses in a shared context
##   is swapped (a stick direction too), refused when it cannot be clean, and
##   the inputs of pause / restart / the look stick / the shutter are reserved;
##   "put it back" restores the shipped input (none for voice_talk); it is saved
##   in settings.cfg, read back into the InputMap, and bad codes in a hand-edited
##   file are dropped; reset_to_defaults() clears them;
## - the gamepad on the options screen: each row has a pad button beside its key
##   (focus moves between them with the d-pad / stick), waiting takes B as a
##   button (Start or Esc cancel, so does a timeout: nobody is left stuck), a
##   stick drift or a push right after the wait began is ignored, and the swap /
##   refusal lines name the button.

const CSV_PATH: String = "res://translations/strings_ui.csv"
## Every action the player presses (project.godot) that Options must offer.
const EXPECTED: Array[StringName] = [
	&"interact", &"ui_ping", &"drive_horn", &"look_back", &"use_card", &"voice_talk", &"sprint",
	&"drive_shift_up", &"drive_shift_down",
	&"walk_forward", &"walk_backward", &"drive_left", &"drive_right", &"jump",
	&"drive_accelerate", &"drive_brake", &"drive_handbrake",
	&"package_drop", &"package_open", &"care_work", &"care_tool_next", &"phone_toggle", &"crew_panel",
	&"spectate_toggle",
]
## Left out on purpose: mouse look, camera/dev toggles, pause, restart. The ones
## with a keyboard key are reserved: nothing can be rebound onto that key.
const NOT_OFFERED: Array[StringName] = [
	&"look_left", &"look_right", &"look_up", &"look_down", &"look_center", &"ui_pause", &"run_restart",
	&"dev_camera_toggle", &"toggle_net_stats",
]

var _failures: int = 0
var _settings: Node
## Loaded at run time: the script names the GameSettings autoload, which a preload would not see.
var _section_script: GDScript
var _options_script: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = root.get_node("GameSettings")
	_section_script = load("res://scripts/ui/options_controls_section.gd")
	_options_script = load("res://scripts/ui/options_panel.gd")
	_settings.reset_to_defaults()

	_test_inventory()
	_test_defaults()
	_test_rebind_each()
	_test_persistence()
	_test_per_action_reset()
	_test_conflicts()
	_test_reserved_keys()
	_test_interaction_follows_actions()
	_test_pad_defaults()
	_test_pad_rebind_each()
	_test_pad_persistence()
	_test_pad_conflicts()
	_test_pad_reset()
	await _test_panel()
	await _test_panel_pad()

	_settings.reset_to_defaults()
	if _failures == 0:
		print("PASS: every player action rebinds, keyboard and gamepad (swap, reset, saved)")
	quit(_failures)


# --- Inventory -------------------------------------------------------------------------------


func _test_inventory() -> void:
	var texts: Dictionary = _csv_keys()
	var rows: Array[StringName] = []
	for group: Dictionary in _section_script.GROUPS:
		_expect(texts.has(group["title"]), "Group title %s is in strings_ui.csv" % group["title"])
		for pair: Array in group["rows"]:
			rows.append(pair[0])
			_expect(texts.has(pair[1]), "Row text %s is in strings_ui.csv (es + en)" % pair[1])
	for action: StringName in EXPECTED:
		_expect(InputMap.has_action(action), "%s exists in the Input Map" % action)
		_expect(action in _settings.REBINDABLE_ACTIONS, "%s is rebindable" % action)
		_expect(_settings.DEFAULT_KEY_BINDINGS.has(action), "%s has a shipped key entry" % action)
		_expect(action in rows, "%s has a row in the options screen" % action)
	_expect(_settings.REBINDABLE_ACTIONS.size() == EXPECTED.size() and rows.size() == EXPECTED.size(),
		"Nothing is offered beyond the inventory (got %d rebindable, %d rows)"
		% [_settings.REBINDABLE_ACTIONS.size(), rows.size()])
	for action: StringName in NOT_OFFERED:
		_expect(action not in _settings.REBINDABLE_ACTIONS, "%s is not offered for rebinding" % action)
	var bare: Array[StringName] = []
	# The actions project.godot defines (the engine's own ui_accept, ui_text_* ... are also in the
	# Input Map, and also in ProjectSettings, so the file is what tells them apart).
	var project_file := ConfigFile.new()
	_expect(project_file.load("res://project.godot") == OK, "project.godot can be read")
	var project_actions: PackedStringArray = project_file.get_section_keys("input") \
			if project_file.has_section("input") else PackedStringArray()
	_expect(project_actions.size() > 20, "project.godot lists the project's actions (got %d)" % project_actions.size())
	for action: StringName in InputMap.get_actions():
		if not String(action) in project_actions:
			continue
		var has_key: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			has_key = has_key or event is InputEventKey
		if has_key and action not in _settings.REBINDABLE_ACTIONS and action not in NOT_OFFERED:
			bare.append(action)
	_expect(bare.is_empty(), "Every action with a keyboard key is rebindable or listed as not offered (missing: %s)"
		% str(bare))
	for key: String in ["UI_OPT_BIND_SWAPPED", "UI_OPT_BIND_BLOCKED", "UI_OPT_BIND_RESERVED",
			"UI_OPT_BIND_DEFAULT", "UI_OPT_BIND_DEFAULT_HINT", "UI_OPT_BIND_RIGHT_CLICK",
			"UI_OPT_OPAQUE_GEL", "UI_OPT_OPAQUE_GEL_HINT",
			"UI_OPT_BIND_PAD_SWAPPED", "UI_OPT_BIND_PAD_BLOCKED", "UI_OPT_BIND_PAD_RESERVED",
			"UI_OPT_BIND_KEY_TIP", "UI_OPT_BIND_PAD_TIP", "UI_OPT_PRESS_PAD", "UI_OPT_PRESS_PAD_HINT",
			"UI_OPT_PAD_NONE", "UI_OPT_PAD_BUTTON", "UI_OPT_PAD_AXIS"]:
		_expect(texts.has(key), "%s is in strings_ui.csv" % key)


func _csv_keys() -> Dictionary:
	var found: Dictionary = {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	while file != null and not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() >= 3 and not line[1].is_empty() and not line[2].is_empty():
			found[line[0]] = true
	return found


# --- Defaults --------------------------------------------------------------------------------


func _test_defaults() -> void:
	for action: StringName in EXPECTED:
		var shipped: int = int(_settings.DEFAULT_KEY_BINDINGS[action])
		if shipped == KEY_NONE:
			_expect(_keys_of(action).is_empty(), "%s ships without a keyboard key" % action)
		else:
			_expect(_keys_of(action) == [shipped],
				"%s ships on %s (got %s)" % [action, OS.get_keycode_string(shipped), str(_keys_of(action))])
		_expect(_settings.is_binding_default(action), "%s starts at its default" % action)
		_expect(_settings.binding_conflicts(action, _settings.bound_key(action)).is_empty(),
			"The shipped key of %s clashes with nothing in its context" % action)
	_expect(_settings.bound_key(&"walk_forward") == _settings.bound_key(&"drive_accelerate"),
		"Walking and driving share W by default (different contexts)")
	_expect(_settings.binding_label(&"care_work") == tr("UI_OPT_BIND_RIGHT_CLICK"),
		"care_work reads as the right mouse button without a key")
	_expect(_non_key_count(&"care_work") > 0, "care_work keeps its mouse / gamepad events")


# --- Rebinding every action --------------------------------------------------------------------


func _free_key(index: int) -> int:
	return KEY_F13 + index


func _test_rebind_each() -> void:
	var non_key_before: Dictionary = {}
	for action: StringName in EXPECTED:
		non_key_before[action] = _non_key_count(action)
	for i: int in EXPECTED.size():
		var action: StringName = EXPECTED[i]
		var key: int = _free_key(i)
		var result: Dictionary = _settings.rebind_key(action, key)
		_expect(result["status"] == _settings.BIND_OK, "%s rebinds to a free key (got %s)" % [action, result])
		_expect(_keys_of(action) == [key], "%s has exactly the new key in the Input Map (got %s)"
			% [action, str(_keys_of(action))])
		_expect(_non_key_count(action) == non_key_before[action], "%s keeps its mouse / gamepad events" % action)
		_expect(_settings.binding_label(action) == OS.get_keycode_string(key), "%s label follows the key" % action)
		_expect(not _settings.is_binding_default(action), "%s no longer counts as default" % action)
		_expect(int(_settings.key_bindings[action]) == key, "%s is stored in key_bindings" % action)
	_expect(InputMap.has_action(&"jump") and not _keys_of(&"jump").has(KEY_SPACE),
		"The old key left the Input Map when jump was rebound")


# --- Persistence -------------------------------------------------------------------------------


func _test_persistence() -> void:
	var config := ConfigFile.new()
	_expect(config.load(_settings.save_path) == OK, "The bindings were written to disk")
	var saved: Dictionary = config.get_value("player", "key_bindings", {})
	for i: int in EXPECTED.size():
		_expect(int(saved.get(EXPECTED[i], -1)) == _free_key(i), "%s is in the saved file" % EXPECTED[i])
	# "Restart": forget everything in memory without touching the file, then read it back.
	_settings.set("_loading", true)
	_settings.key_bindings = _settings.DEFAULT_KEY_BINDINGS.duplicate()
	_settings.set("_loading", false)
	_expect(_keys_of(&"jump") == [KEY_SPACE], "The memory wipe put the shipped keys back (test setup)")
	_settings.call("_load")
	for i: int in EXPECTED.size():
		var action: StringName = EXPECTED[i]
		_expect(_keys_of(action) == [_free_key(i)], "%s comes back from the file into the Input Map (got %s)"
			% [action, str(_keys_of(action))])
		_expect(int(_settings.key_bindings[action]) == _free_key(i), "%s comes back into key_bindings" % action)
	# An older file without the new actions falls back to their shipped keys.
	var old_file := ConfigFile.new()
	old_file.load(_settings.save_path)
	old_file.set_value("player", "key_bindings", {&"interact": KEY_F20})
	old_file.save(_settings.save_path)
	_settings.call("_load")
	_expect(_keys_of(&"interact") == [KEY_F20] and _keys_of(&"jump") == [KEY_SPACE],
		"A file that only knows the old actions keeps them and ships the rest")
	# A hand-edited file can't leave an action with a shipped key without any.
	old_file.set_value("player", "key_bindings", {&"jump": KEY_NONE})
	old_file.save(_settings.save_path)
	_settings.call("_load")
	_expect(_keys_of(&"jump") == [KEY_SPACE], "A zeroed key in the file falls back to the shipped one")


# --- Reset per action ----------------------------------------------------------------------------


func _test_per_action_reset() -> void:
	for i: int in EXPECTED.size():
		_settings.rebind_key(EXPECTED[i], _free_key(i))
	for action: StringName in EXPECTED:
		var shipped: int = int(_settings.DEFAULT_KEY_BINDINGS[action])
		var before_others: Dictionary = {}
		for other: StringName in EXPECTED:
			if other != action:
				before_others[other] = _settings.bound_key(other)
		var result: Dictionary = _settings.reset_binding(action)
		_expect(result["status"] == _settings.BIND_OK, "Resetting %s works (got %s)" % [action, result])
		_expect(_settings.is_binding_default(action), "%s is back at its default" % action)
		if shipped == KEY_NONE:
			_expect(_keys_of(action).is_empty(), "%s lost its keyboard key and keeps the mouse" % action)
			_expect(_non_key_count(action) > 0, "%s still has its mouse / gamepad events" % action)
		else:
			_expect(_keys_of(action) == [shipped], "%s is back on its key in the Input Map (got %s)"
				% [action, str(_keys_of(action))])
		for other: StringName in before_others:
			_expect(_settings.bound_key(other) == before_others[other],
				"Resetting %s leaves %s alone" % [action, other])
	var config := ConfigFile.new()
	config.load(_settings.save_path)
	var saved: Dictionary = config.get_value("player", "key_bindings", {})
	_expect(int(saved.get(&"jump", -1)) == KEY_SPACE and int(saved.get(&"care_work", -1)) == KEY_NONE,
		"The reset is saved too")
	# reset_to_defaults() takes everything back at once.
	for i: int in EXPECTED.size():
		_settings.rebind_key(EXPECTED[i], _free_key(i))
	_settings.reset_to_defaults()
	for action: StringName in EXPECTED:
		_expect(_settings.is_binding_default(action), "reset_to_defaults() restores %s" % action)
		var shipped: int = int(_settings.DEFAULT_KEY_BINDINGS[action])
		_expect(_keys_of(action) == ([] if shipped == KEY_NONE else [shipped]),
			"reset_to_defaults() restores %s in the Input Map" % action)


# --- Conflicts -----------------------------------------------------------------------------------


func _test_conflicts() -> void:
	_settings.reset_to_defaults()
	# Same context: a swap.
	var result: Dictionary = _settings.rebind_key(&"sprint", KEY_E)
	_expect(result["status"] == _settings.BIND_SWAPPED and result["other"] == &"interact",
		"Sprint onto Interact's key swaps them (got %s)" % result)
	_expect(_keys_of(&"sprint") == [KEY_E] and _keys_of(&"interact") == [KEY_SHIFT],
		"...and the Input Map has the swap (sprint %s, interact %s)"
		% [str(_keys_of(&"sprint")), str(_keys_of(&"interact"))])
	_expect(_settings.binding_label(&"interact") == OS.get_keycode_string(KEY_SHIFT), "...and the labels follow")
	result = _settings.reset_binding(&"sprint")
	_expect(result["status"] == _settings.BIND_SWAPPED and _settings.is_binding_default(&"sprint")
		and _settings.is_binding_default(&"interact"),
		"Resetting sprint swaps back with the action that took its key (got %s)" % result)
	# Walking vs jumping share the on-foot context; driving keeps its own keys.
	result = _settings.rebind_key(&"walk_forward", KEY_SPACE)
	_expect(result["status"] == _settings.BIND_SWAPPED and result["other"] == &"jump",
		"Walk forward onto Jump's key swaps them (got %s)" % result)
	_expect(_keys_of(&"jump") == [KEY_W] and _keys_of(&"walk_forward") == [KEY_SPACE],
		"...on foot, W jumps and Space walks")
	_expect(_keys_of(&"drive_accelerate") == [KEY_W] and _keys_of(&"drive_handbrake") == [KEY_SPACE],
		"...while the driving keys did not move")
	_settings.reset_to_defaults()
	# A different context may share the key.
	result = _settings.rebind_key(&"spectate_toggle", KEY_Q)
	_expect(result["status"] == _settings.BIND_OK and _keys_of(&"package_drop") == [KEY_Q],
		"Spectate may share Q with Drop package (never in the same context)")
	_settings.reset_to_defaults()
	# Not clean: nothing changes.
	var before: Dictionary = _settings.key_bindings.duplicate()
	result = _settings.rebind_key(&"jump", KEY_Q)
	_expect(result["status"] == _settings.BIND_BLOCKED,
		"Jump onto Q is refused: Drop package would land on Space, taken by the handbrake (got %s)" % result)
	result = _settings.rebind_key(&"drive_left", KEY_W)
	_expect(result["status"] == _settings.BIND_BLOCKED,
		"Steering onto W is refused: two actions use it (got %s)" % result)
	result = _settings.rebind_key(&"care_work", KEY_E)
	_expect(result["status"] == _settings.BIND_BLOCKED and result["other"] == &"interact",
		"care_work has no key to hand back, so taking Interact's key is refused (got %s)" % result)
	result = _settings.rebind_key(&"jump", KEY_ESCAPE)
	_expect(result["status"] == _settings.BIND_RESERVED, "Esc is reserved")
	result = _settings.rebind_key(&"jump", _settings.fullscreen_key)
	_expect(result["status"] == _settings.BIND_RESERVED, "The fullscreen key is reserved")
	result = _settings.rebind_key(&"jump", KEY_NONE)
	_expect(result["status"] == _settings.BIND_INVALID, "No key is not a binding")
	result = _settings.rebind_key(&"ui_pause", KEY_P)
	_expect(result["status"] == _settings.BIND_INVALID, "Pause is not rebindable")
	result = _settings.rebind_key(&"jump", KEY_SPACE)
	_expect(result["status"] == _settings.BIND_OK, "Rebinding to the key it already has is a no-op")
	_expect(_settings.key_bindings == before, "Refused rebinds changed nothing (bindings)")
	_expect(_keys_of(&"jump") == [KEY_SPACE] and _keys_of(&"package_drop") == [KEY_Q]
		and _keys_of(&"drive_left") == [KEY_A] and _keys_of(&"interact") == [KEY_E],
		"...nor the Input Map")


func _test_reserved_keys() -> void:
	_settings.reset_to_defaults()
	var before: Dictionary = _settings.key_bindings.duplicate()
	# R restart, C look center, F-keys dev camera / net stats, Esc pause: all refused.
	for action: StringName in [&"run_restart", &"look_center", &"dev_camera_toggle", &"toggle_net_stats", &"ui_pause"]:
		for key: int in _keys_of(action):
			var result: Dictionary = _settings.rebind_key(&"jump", key)
			_expect(result["status"] == _settings.BIND_RESERVED,
				"The key of %s (%s) is reserved (got %s)" % [action, OS.get_keycode_string(key), result])
	_expect(_keys_of(&"run_restart") == [KEY_R] and _keys_of(&"look_center") == [KEY_C],
		"...and R / C are what the project ships for restart / look center")
	_expect(_settings.key_bindings == before and _keys_of(&"jump") == [KEY_SPACE],
		"Reserved keys changed nothing")
	var section: Node = _section_script.new()
	root.add_child(section)
	section.call(&"build")
	var shown: Dictionary = section.call(&"apply_key", &"jump", KEY_R)
	_expect(shown["status"] == _settings.BIND_RESERVED and not str(section.call(&"note_text", &"jump")).is_empty(),
		"Taking R shows the reserved notice under the row")
	section.queue_free()
	# The care tool key is a normal binding now.
	_expect(&"care_tool_next" in _settings.REBINDABLE_ACTIONS and _keys_of(&"care_tool_next") == [KEY_X],
		"care_tool_next ships on X and is rebindable")


## N-966: an action moved to another key must not keep answering on the old one.
func _test_interaction_follows_actions() -> void:
	_settings.reset_to_defaults()
	var interaction: Node = load("res://scripts/gameplay/player/player_interaction.gd").new()
	_expect(interaction.is_interact_event(_key_event(KEY_E)) and interaction.is_drop_event(_key_event(KEY_Q))
		and interaction.is_open_event(_key_event(KEY_T)), "E / Q / T interact, drop and open by default")
	# Interact moves away, then walking takes E: pressing E must walk, not interact.
	_settings.rebind_key(&"interact", KEY_F13)
	var result: Dictionary = _settings.rebind_key(&"walk_forward", KEY_E)
	_expect(result["status"] == _settings.BIND_OK, "Walk forward takes the freed E (got %s)" % result)
	_expect(not interaction.is_interact_event(_key_event(KEY_E)), "E no longer interacts once walk_forward has it")
	_expect(interaction.is_interact_event(_key_event(KEY_F13)), "...Interact answers on its new key")
	_settings.rebind_key(&"package_drop", KEY_F14)
	_settings.rebind_key(&"package_open", KEY_F15)
	_expect(not interaction.is_drop_event(_key_event(KEY_Q)) and interaction.is_drop_event(_key_event(KEY_F14)),
		"Drop follows its rebound key, not Q")
	_expect(not interaction.is_open_event(_key_event(KEY_T)) and interaction.is_open_event(_key_event(KEY_F15)),
		"Open follows its rebound key, not T")
	interaction.free()
	_settings.reset_to_defaults()


# --- Gamepad: defaults, rebinding, persistence, conflicts, reset (N-966.3) ---------------------------


## A free gamepad input per action: buttons 15..34, then the spare axes 6..
func _free_pad(index: int) -> String:
	return "b%d" % (15 + index) if index < 20 else "a%d+" % (6 + index - 20)


func _test_pad_defaults() -> void:
	_settings.reset_to_defaults()
	var with_pad: int = 0
	for action: StringName in EXPECTED:
		var shipped: String = _pad_script().default_code(action)
		_expect(_pad_script().codes_in_map(action) == ([shipped] if not shipped.is_empty() else []),
			"%s has its project.godot gamepad input in the Input Map (%s, got %s)"
			% [action, shipped, str(_pad_script().codes_in_map(action))])
		_expect(_settings.bound_pad(action) == shipped and _settings.is_pad_binding_default(action),
			"%s starts on its shipped gamepad input" % action)
		with_pad += 0 if shipped.is_empty() else 1
	_expect(with_pad >= 20, "Most actions ship with a gamepad input (got %d)" % with_pad)
	_expect(_settings.bound_pad(&"interact") == "b0" and _settings.bound_pad(&"drive_left") == "a0-"
		and _settings.bound_pad(&"drive_accelerate") == "a5+" and _settings.bound_pad(&"voice_talk") == "",
		"A is interact, the left stick drives, RT accelerates, voice_talk has no gamepad input")
	_expect(_settings.pad_label(&"interact") == tr("UI_OPT_PAD_A")
			and _settings.pad_label(&"drive_left") == tr("UI_OPT_PAD_LSTICK_LEFT")
		and _settings.pad_label(&"voice_talk") == tr("UI_OPT_PAD_NONE"), "...and the labels name them")
	# The shipped pairs that share an input are not conflicts.
	_expect(_settings.pad_conflicts(&"sprint", "b7").is_empty() and _settings.pad_conflicts(&"look_back",
			"b7").is_empty(),
		"Sprint and look back share the stick click as shipped without a conflict")
	_expect(_pad_script().is_reserved("b6", &"jump") and _pad_script().is_reserved("a3-", &"jump")
		and not _pad_script().is_reserved("a5+", &"drive_accelerate"),
		"Start and the look stick are reserved, but an action may keep the input it ships with")
	# binding_label follows the device in hand.
	_settings.using_gamepad = true
	_expect(_settings.binding_label(&"interact") == tr("UI_OPT_PAD_A")
			and _settings.binding_label(&"voice_talk") == _settings.key_label(&"voice_talk"),
		"binding_label names the gamepad input with a gamepad in hand (and the key when there is none)")
	_settings.using_gamepad = false
	_expect(_settings.binding_label(&"interact") == _settings.key_label(&"interact"),
			"...and the key with the keyboard")


func _test_pad_rebind_each() -> void:
	_settings.reset_to_defaults()
	var keys_before: Dictionary = {}
	var others_before: Dictionary = {}
	for action: StringName in EXPECTED:
		keys_before[action] = _keys_of(action)
		others_before[action] = _non_pad_count(action)
	for i: int in EXPECTED.size():
		var action: StringName = EXPECTED[i]
		var code: String = _free_pad(i)
		var result: Dictionary = _settings.rebind_pad(action, code)
		_expect(result["status"] == _settings.BIND_OK, "%s rebinds to a free gamepad input %s (got %s)" % [action,
				code, result])
		_expect(_pad_script().codes_in_map(action) == [code], "%s has exactly %s as a gamepad input (got %s)"
			% [action, code, str(_pad_script().codes_in_map(action))])
		_expect(_keys_of(action) == keys_before[action] and _non_pad_count(action) == others_before[action],
			"%s keeps its keyboard and mouse events" % action)
		_expect(_settings.bound_pad(action) == code and not _settings.is_pad_binding_default(action),
			"%s reports the new gamepad input" % action)
		_expect(_settings.pad_label(action) == _pad_script().label(code), "%s label follows" % action)
	# The events are real events: a button and an axis direction.
	var button_event: InputEvent = _pad_event(&"interact")
	_expect(button_event is InputEventJoypadButton and (button_event as InputEventJoypadButton).button_index == 15,
		"A button code is an InputEventJoypadButton")
	var axis_event: InputEvent = _pad_event(EXPECTED[20])
	_expect(axis_event is InputEventJoypadMotion and (axis_event as InputEventJoypadMotion).axis == 6
		and (axis_event as InputEventJoypadMotion).axis_value == 1.0, "An axis code is an InputEventJoypadMotion")
	_expect(_pad_script().label("b15") == tr("UI_OPT_PAD_BUTTON") % 15
			and _pad_script().label("a6+") == tr("UI_OPT_PAD_AXIS") % [6, "+"],
		"Inputs without a name read as Button 15 / Axis 6+")
	# Keyboard and gamepad rebinds do not disturb each other.
	_settings.rebind_key(&"jump", KEY_F13)
	_expect(_settings.bound_pad(&"jump") == _free_pad(EXPECTED.find(&"jump")),
			"A key rebind leaves the gamepad input alone")
	_settings.rebind_pad(&"jump", "b3")
	_expect(_settings.bound_pad(&"jump") == _free_pad(EXPECTED.find(&"jump")),
			"Y (restart) is refused, so nothing moved")
	_settings.reset_to_defaults()


func _test_pad_persistence() -> void:
	_settings.reset_to_defaults()
	_settings.rebind_pad(&"phone_toggle", "b15")
	_settings.rebind_pad(&"care_tool_next", "a6+")
	var config := ConfigFile.new()
	_expect(config.load(_settings.save_path) == OK, "The gamepad bindings were written to disk")
	var saved: Dictionary = config.get_value("player", "pad_bindings", {})
	_expect(String(saved.get(&"phone_toggle", "")) == "b15" and String(saved.get(&"care_tool_next", "")) == "a6+",
		"The moved inputs are in the saved file (got %s)" % str(saved))
	_expect(saved.size() == 2, "...and only what differs from project.godot (got %d entries)" % saved.size())
	# "Restart": forget everything in memory without touching the file, then read it back.
	_settings.set("_loading", true)
	_settings.pad_bindings = {}
	_settings.set("_loading", false)
	_expect(_pad_script().codes_in_map(&"phone_toggle") == ["b9"],
			"The memory wipe put the shipped inputs back (test setup)")
	_settings.call("_load")
	_expect(_pad_script().codes_in_map(&"phone_toggle") == ["b15"]
			and _pad_script().codes_in_map(&"care_tool_next") == ["a6+"],
		"The moved inputs come back from the file into the Input Map")
	_expect(_settings.bound_pad(&"phone_toggle") == "b15" and _settings.bound_pad(&"jump") == "b2",
		"...and what was not moved stays shipped")
	# A hand-edited file: bad codes, unknown actions and shipped values are dropped.
	var edited := ConfigFile.new()
	edited.load(_settings.save_path)
	edited.set_value("player", "pad_bindings", {&"jump": "b99", &"interact": "zzz", &"sprint": "b7", &"nothing": "b1",
		&"use_card": "a6-"})
	edited.save(_settings.save_path)
	_settings.call("_load")
	_expect(_pad_script().codes_in_map(&"jump") == ["b2"] and _pad_script().codes_in_map(&"interact") == ["b0"]
		and _pad_script().codes_in_map(&"sprint") == ["b7"], "Bad codes in the file fall back to the shipped inputs")
	_expect(_pad_script().codes_in_map(&"use_card") == ["a6-"]
			and _pad_script().codes_in_map(&"phone_toggle") == ["b9"],
		"...a good code is kept, and an action missing from the file ships")
	_expect(_settings.pad_bindings.size() == 1, "...and nothing else is stored (got %s)" % str(_settings.pad_bindings))
	# A file from before the gamepad remap has no entry at all.
	edited.erase_section_key("player", "pad_bindings")
	edited.save(_settings.save_path)
	_settings.set("_loading", true)
	_settings.pad_bindings = {}
	_settings.set("_loading", false)
	_settings.call("_load")
	_expect(_pad_script().codes_in_map(&"use_card") == ["b13"] and _settings.pad_bindings.is_empty(),
		"A file without gamepad bindings ships every action on its own input")
	_settings.reset_to_defaults()
	_expect(_pad_script().codes_in_map(&"use_card") == ["b13"] and _settings.pad_bindings.is_empty(),
		"reset_to_defaults() clears the gamepad bindings")


func _test_pad_conflicts() -> void:
	_settings.reset_to_defaults()
	# A button another action uses is swapped.
	var result: Dictionary = _settings.rebind_pad(&"use_card", "b14")
	_expect(result["status"] == _settings.BIND_SWAPPED and result["other"] == &"care_tool_next",
		"Use card onto the d-pad right swaps with Switch care tool (got %s)" % result)
	_expect(_pad_script().codes_in_map(&"use_card") == ["b14"]
			and _pad_script().codes_in_map(&"care_tool_next") == ["b13"],
		"...and the Input Map has the swap")
	result = _settings.reset_pad_binding(&"use_card")
	_expect(result["status"] == _settings.BIND_SWAPPED and _settings.is_pad_binding_default(&"use_card")
		and _settings.is_pad_binding_default(&"care_tool_next") and _settings.pad_bindings.is_empty(),
		"Resetting use card swaps back (got %s) and leaves nothing stored" % result)
	# A stick direction another action uses is swapped too: the button goes to the stick action.
	result = _settings.rebind_pad(&"use_card", "a0+")
	_expect(result["status"] == _settings.BIND_SWAPPED and result["other"] == &"drive_right",
		"Use card onto stick right swaps with the steering (got %s)" % result)
	_expect(_pad_script().codes_in_map(&"use_card") == ["a0+"] and _pad_script().codes_in_map(&"drive_right") == ["b13"]
		and _keys_of(&"drive_right") == [KEY_D], "...steering right is now the d-pad left, and keeps D on the keyboard")
	_settings.reset_to_defaults()
	# Two actions on one input: refused, nothing changes.
	var before: Dictionary = _settings.pad_bindings.duplicate()
	result = _settings.rebind_pad(&"jump", "a4+")
	_expect(result["status"] == _settings.BIND_BLOCKED,
			"Jump onto LT is refused: Tend the package would land on X, used by the handbrake (got %s)" % result)
	result = _settings.rebind_pad(&"sprint", "b0")
	_expect(result["status"] == _settings.BIND_BLOCKED and result["other"] == &"interact",
		"Sprint onto A is refused: Interact would land on the stick click, taken by Look back (got %s)" % result)
	result = _settings.rebind_pad(&"voice_talk", "b0")
	_expect(result["status"] == _settings.BIND_BLOCKED, "voice_talk has no input to hand back, so taking A is refused")
	for reserved: String in ["b6", "b3", "b8", "a2-", "a3+", "a5+", "b10"]:
		result = _settings.rebind_pad(&"jump", reserved)
		_expect(result["status"] == _settings.BIND_RESERVED, "%s is reserved (got %s)" % [reserved, result])
	_expect(_settings.rebind_pad(&"jump", "")["status"] == _settings.BIND_INVALID
		and _settings.rebind_pad(&"jump", "b99")["status"] == _settings.BIND_INVALID
		and _settings.rebind_pad(&"ui_pause",
				"b15")["status"] == _settings.BIND_INVALID, "Bad codes and unknown actions are invalid")
	_expect(_settings.rebind_pad(&"jump", "b2")["status"] == _settings.BIND_OK,
			"Rebinding to the input it already has is a no-op")
	_expect(_settings.pad_bindings == before and _pad_script().codes_in_map(&"jump") == ["b2"]
		and _pad_script().codes_in_map(&"interact") == ["b0"] and _pad_script().codes_in_map(&"sprint") == ["b7"],
		"Refused rebinds changed nothing")
	# The shipped sharing is allowed back: moving the horn away and back keeps drop on B.
	_settings.rebind_pad(&"drive_horn", "b15")
	result = _settings.reset_pad_binding(&"drive_horn")
	_expect(result["status"] == _settings.BIND_OK and _pad_script().codes_in_map(&"drive_horn") == ["b1"]
		and _pad_script().codes_in_map(&"package_drop") == ["b1"],
		"The horn goes back to B, shared with drop as shipped (got %s)" % result)
	_settings.reset_to_defaults()


func _test_pad_reset() -> void:
	_settings.reset_to_defaults()
	var others_before: Dictionary = {}
	for action: StringName in EXPECTED:
		others_before[action] = _non_pad_count(action)
	for i: int in EXPECTED.size():
		_settings.rebind_pad(EXPECTED[i], _free_pad(i))
	for action: StringName in EXPECTED:
		var shipped: String = _pad_script().default_code(action)
		var result: Dictionary = _settings.reset_pad_binding(action)
		_expect(result["status"] == _settings.BIND_OK, "Resetting the gamepad input of %s works (got %s)" % [action,
				result])
		_expect(_settings.is_pad_binding_default(action), "%s is back at its gamepad default" % action)
		_expect(_pad_script().codes_in_map(action) == ([shipped] if not shipped.is_empty() else []),
			"%s is back on %s in the Input Map (got %s)" % [action, shipped, str(_pad_script().codes_in_map(action))])
		_expect(_non_pad_count(action) == others_before[action], "%s keeps its keyboard and mouse events" % action)
	_expect(_settings.pad_bindings.is_empty(),
			"Nothing is stored once everything is back (got %s)" % str(_settings.pad_bindings))
	_expect(_pad_script().codes_in_map(&"voice_talk").is_empty(), "voice_talk goes back to no gamepad input")
	for i: int in EXPECTED.size():
		_settings.rebind_pad(EXPECTED[i], _free_pad(i))
	_settings.reset_to_defaults()
	for action: StringName in EXPECTED:
		_expect(_settings.is_pad_binding_default(action),
				"reset_to_defaults() restores the gamepad input of %s" % action)


# --- The options screen ----------------------------------------------------------------------------


func _test_panel() -> void:
	_settings.reset_to_defaults()
	var options: Control = _options_script.new()
	root.add_child(options)
	await process_frame
	options.call(&"open")
	var opaque_gel := options.find_child("OpaqueGelCheck", true, false) as CheckBox
	_expect(opaque_gel != null, "Options exposes the opaque-gel accessibility preference")
	if opaque_gel != null:
		opaque_gel.set_pressed(true)
		_expect(bool(_settings.get(&"opaque_gel")) and bool(_settings.call(&"uses_opaque_gel")),
			"the accessibility checkbox applies the opaque material preference")
		opaque_gel.set_pressed(false)
	var section: Node = options.find_child("ControlsSection", true, false)
	_expect(section != null, "The options screen has the controls section")
	if section == null:
		options.queue_free()
		return
	for action: StringName in EXPECTED:
		var bind: Button = section.find_child("Bind_" + String(action), true, false)
		var reset: Button = section.find_child("Reset_" + String(action), true, false)
		_expect(bind != null and reset != null, "%s has its key button and its 'put it back' button" % action)
		if bind != null and reset != null:
			_expect(bind.text == _settings.binding_label(action), "%s shows its key (got %s)" % [action, bind.text])
			_expect(reset.disabled, "%s: 'put it back' is greyed out while at the default" % action)
	var buttons: Dictionary = options.get(&"_binding_buttons")
	_expect(buttons.size() == EXPECTED.size(), "The panel's button map covers every action (got %d)" % buttons.size())

	# The groups start collapsed and open from their header.
	_expect(not section.call(&"is_group_open", &"drive"), "The groups start collapsed")
	(section.find_child("Header_drive", true, false) as Button).pressed.emit()
	_expect(section.call(&"is_group_open", &"drive"), "A header opens its group")
	_expect((section.find_child("Header_drive", true, false) as Button).text.begins_with("[-]"),
		"...and says so")

	# Pressing a row waits for a key; Tab (which focus navigation would swallow) is taken.
	(buttons[&"package_open"] as Button).pressed.emit()
	_expect(section.call(&"is_listening") and (buttons[&"package_open"] as Button).text == tr("UI_OPT_PRESS_KEY"),
		"A row waits for a key and says so")
	root.push_input(_key_event(KEY_TAB))
	_expect(not section.call(&"is_listening"), "A key ends the wait")
	_expect(_keys_of(&"package_open") == [KEY_TAB] and _keys_of(&"crew_panel") == [KEY_T],
		"Open package took Tab (and handed crew_panel its T): got %s / %s"
		% [str(_keys_of(&"package_open")), str(_keys_of(&"crew_panel"))])
	_expect((buttons[&"package_open"] as Button).text == _settings.binding_label(&"package_open"),
		"The row shows the new key")
	_expect(not (section.find_child("Reset_package_open", true, false) as Button).disabled,
		"'Put it back' wakes up once the key differs")

	# A swap says so under the row, and the other row's button follows.
	(buttons[&"sprint"] as Button).pressed.emit()
	root.push_input(_key_event(KEY_E))
	_expect(not str(section.call(&"note_text", &"sprint")).is_empty(), "A swap shows a line under the edited row")
	_expect((buttons[&"interact"] as Button).text == _settings.binding_label(&"interact"),
		"...and the swapped row shows its new key")
	_expect(_settings.bound_key(&"interact") == KEY_SHIFT, "...which is the old key of the first one")
	# A refusal says so and leaves the screen in line with the settings.
	(buttons[&"drive_left"] as Button).pressed.emit()
	root.push_input(_key_event(KEY_W))
	_expect(not str(section.call(&"note_text", &"drive_left")).is_empty(), "A refusal shows a line too")
	_expect((buttons[&"drive_left"] as Button).text == _settings.binding_label(&"drive_left")
		and _settings.bound_key(&"drive_left") == KEY_A, "...and the row keeps its key")

	# Esc cancels the wait without closing the screen.
	var key_before: int = _settings.bound_key(&"phone_toggle")
	(buttons[&"phone_toggle"] as Button).pressed.emit()
	root.push_input(_key_event(KEY_ESCAPE))
	_expect(not section.call(&"is_listening") and _settings.bound_key(&"phone_toggle") == key_before
		and (buttons[&"phone_toggle"] as Button).text == _settings.binding_label(&"phone_toggle"),
		"Esc cancels the wait and restores the label")
	_expect(options.visible, "...without closing the options")

	# "Put it back" on a row, and the panel's own reset.
	(section.find_child("Reset_package_open", true, false) as Button).pressed.emit()
	_expect(_settings.is_binding_default(&"package_open") and _settings.is_binding_default(&"crew_panel")
		and (section.find_child("Reset_package_open", true, false) as Button).disabled,
		"The row's 'put it back' restores the key (and the swapped one) and greys itself out")
	options.call(&"_reset")
	for action: StringName in EXPECTED:
		_expect(_settings.is_binding_default(action), "The panel's reset restores %s" % action)
		_expect((buttons[action] as Button).text == _settings.binding_label(action), "...and its button follows")

	options.queue_free()
	await process_frame


func _test_panel_pad() -> void:
	_settings.reset_to_defaults()
	var options: Control = _options_script.new()
	root.add_child(options)
	await process_frame
	options.call(&"open")
	var section: Node = options.find_child("ControlsSection", true, false)
	_expect(section != null, "The options screen has the controls section (gamepad)")
	if section == null:
		options.queue_free()
		return
	section.call(&"set_group_open", &"foot", true)
	await process_frame
	await process_frame
	for action: StringName in EXPECTED:
		var pad: Button = section.find_child("Pad_" + String(action), true, false)
		_expect(pad != null, "%s has its gamepad button" % action)
		if pad != null:
			_expect(pad.text == _settings.pad_label(action), "%s shows its gamepad input (got %s)" % [action, pad.text])
	var keys: Dictionary = section.get(&"buttons")
	var pads: Dictionary = section.get(&"pad_buttons")
	_expect(pads.size() == EXPECTED.size(), "The section's gamepad button map covers every action")

	# The d-pad / stick walks along the row: key -> pad (and back), and the pad is focusable.
	var jump_key: Button = keys[&"jump"]
	var jump_pad: Button = pads[&"jump"]
	_expect(jump_pad.focus_mode == Control.FOCUS_ALL, "The gamepad button takes focus")
	_expect(jump_key.find_valid_focus_neighbor(SIDE_RIGHT) == jump_pad, "Right of the key button is the gamepad button")
	_expect(jump_pad.find_valid_focus_neighbor(SIDE_LEFT) == jump_key,
			"...and left of the gamepad button is the key button")

	# A button is taken, B included (it is not "cancel" while waiting for a gamepad input).
	jump_pad.pressed.emit()
	_expect(section.call(&"is_listening") and jump_pad.text == tr("UI_OPT_PRESS_PAD")
		and not str(section.call(&"note_text", &"jump")).is_empty(), "A row waits for a gamepad input and says so")
	root.push_input(_pad_button_event(1))
	_expect(not section.call(&"is_listening") and options.visible, "B ends the wait without closing the options")
	_expect(_settings.bound_pad(&"jump") == "b2", "...and the refused button changed nothing")
	# B is horn / drop (DRIVE / FOOT): jump (FOOT) overlaps drop, whose swap is blocked by the handbrake.
	_expect(str(section.call(&"note_text", &"jump")) == tr("UI_OPT_BIND_PAD_BLOCKED") % tr("UI_OPT_BIND_PACKAGE_DROP"),
		"The refusal names the other action and says button (got %s)" % section.call(&"note_text", &"jump"))
	# A free button, then a swap that is shown.
	(pads[&"phone_toggle"] as Button).pressed.emit()
	root.push_input(_pad_button_event(15))
	_expect(_settings.bound_pad(&"phone_toggle") == "b15"
			and (pads[&"phone_toggle"] as Button).text == _settings.pad_label(&"phone_toggle"),
		"A button press is taken and shown")
	_expect(not (section.find_child("Reset_phone_toggle", true, false) as Button).disabled, "'Put it back' wakes up")
	(pads[&"use_card"] as Button).pressed.emit()
	root.push_input(_pad_button_event(14))
	_expect(_settings.bound_pad(&"use_card") == "b14" and _settings.bound_pad(&"care_tool_next") == "b13"
		and (pads[&"care_tool_next"] as Button).text == _settings.pad_label(&"care_tool_next"),
		"A swap moves both buttons and the other row follows")
	_expect(str(section.call(&"note_text",
			&"use_card")) == tr("UI_OPT_BIND_PAD_SWAPPED") % tr("UI_OPT_BIND_CARE_TOOL_NEXT"),
		"...and says so under the edited row")

	# A stick push is taken as a direction, once it is clear and the wait is not brand new.
	(pads[&"care_tool_next"] as Button).pressed.emit()
	root.push_input(_pad_motion_event(6, 1.0))
	_expect(section.call(&"is_listening"), "A push right after the wait began is ignored")
	section.call(&"_process", 0.4)
	root.push_input(_pad_motion_event(6, 0.3))
	_expect(section.call(&"is_listening"), "Drift is ignored")
	root.push_input(_pad_motion_event(6, -1.0))
	_expect(not section.call(&"is_listening") and _settings.bound_pad(&"care_tool_next") == "a6-",
		"A clear stick push is taken with its direction (got %s)" % _settings.bound_pad(&"care_tool_next"))

	# Never stuck: Start cancels, Esc cancels, a click elsewhere cancels, and so does time.
	var before: String = _settings.bound_pad(&"jump")
	(pads[&"jump"] as Button).pressed.emit()
	root.push_input(_pad_button_event(6))
	_expect(not section.call(&"is_listening") and options.visible and _settings.bound_pad(&"jump") == before
		and jump_pad.text == _settings.pad_label(&"jump"), "Start cancels the wait without closing the options")
	(pads[&"jump"] as Button).pressed.emit()
	root.push_input(_key_event(KEY_ESCAPE))
	_expect(not section.call(&"is_listening") and options.visible, "Esc cancels a gamepad wait too")
	(pads[&"jump"] as Button).pressed.emit()
	section.call(&"_process", 2.0)
	_expect(section.call(&"is_listening"), "The wait goes on while there is time")
	section.call(&"_process", 5.0)
	_expect(not section.call(&"is_listening") and jump_pad.text == _settings.pad_label(&"jump"),
		"...and gives up after a few seconds, restoring the label")
	(pads[&"jump"] as Button).pressed.emit()
	options.call(&"close")
	_expect(not section.call(&"is_listening"), "Closing the options ends the wait")
	options.call(&"open")
	# Waiting for a key and for a gamepad input are not mixed up.
	(keys[&"jump"] as Button).pressed.emit()
	root.push_input(_pad_button_event(15))
	_expect(section.call(&"is_listening"), "A gamepad press does not answer a key wait")
	section.call(&"stop_listening")

	# One 'put it back' restores both the key and the gamepad input.
	_settings.rebind_key(&"phone_toggle", KEY_F13)
	section.call(&"refresh")
	var reset: Button = section.find_child("Reset_phone_toggle", true, false)
	_expect(not reset.disabled, "'Put it back' is on while the key or the gamepad input differs")
	reset.pressed.emit()
	_expect(_settings.is_binding_default(&"phone_toggle") and _settings.is_pad_binding_default(&"phone_toggle")
			and reset.disabled
		and (pads[&"phone_toggle"] as Button).text == _settings.pad_label(&"phone_toggle"),
		"...and restores both")
	_settings.rebind_pad(&"phone_toggle", "b15")
	section.call(&"refresh")
	_expect(not reset.disabled, "A moved gamepad input alone wakes it up")
	options.call(&"_reset")
	for action: StringName in EXPECTED:
		_expect(_settings.is_pad_binding_default(action)
				and (pads[action] as Button).text == _settings.pad_label(action),
			"The panel's reset restores the gamepad input of %s and its button follows" % action)
	_settings.using_gamepad = false
	options.queue_free()
	await process_frame



# --- Helpers -------------------------------------------------------------------------------------


func _key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode as Key
	event.keycode = keycode as Key
	event.pressed = true
	return event


## The physical keycodes of the keyboard events an action has.
func _keys_of(action: StringName) -> Array:
	var keys: Array = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append(int((event as InputEventKey).physical_keycode))
	return keys


func _pad_script() -> GDScript:
	return load("res://scripts/core/pad_binding.gd")


func _pad_event(action: StringName) -> InputEvent:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return event
	return null


func _pad_button_event(index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index as JoyButton
	event.pressed = true
	return event


func _pad_motion_event(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis as JoyAxis
	event.axis_value = value
	return event


func _non_pad_count(action: StringName) -> int:
	var count: int = 0
	for event: InputEvent in InputMap.action_get_events(action):
		if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			count += 1
	return count


func _non_key_count(action: StringName) -> int:
	var count: int = 0
	for event: InputEvent in InputMap.action_get_events(action):
		if not event is InputEventKey:
			count += 1
	return count


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
