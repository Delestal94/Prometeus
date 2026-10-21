extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_control_hints.gd
##
## The help texts print the controls the player has now, not fixed keys (N-966.4,
## control_hints.gd, hud_prompts.gd, options_panel.gd, options_controls_section.gd):
## - defaults: the keyboard names read WASD, W/S, A/D, E, Q...; on the gamepad the
##   left stick and A; a text is its translation filled with those names;
## - a rebound key (walk_forward to an arrow, interact to another key) or gamepad
##   input changes the text and names the new control, the old one is gone; walking
##   off the left stick on the pad lists the buttons instead of "Left stick";
## - the summary of Options is written again whenever the bindings are refreshed
##   (the `refreshed` signal): rebinding from the rows, swapping, "put it back";
##   a bug here left the summary promising the old key after a remap;
## - every action of the options screen can be rebound to a free key and gamepad
##   input (InputMap and label follow) and put back; the summary names the new
##   control for the actions it lists and stays the same for the others;
## - the shared settings are restored at the end (reset_to_defaults).
##
## - the care card (PlayerCargoCare.control_names, N-977.5) names the rebound drop,
##   next-tool and walk keys, and the tutorial's driver page the rebound pedals.
##
## The row-by-row remap itself is test_options_controls.gd; this one is about what
## the texts say afterwards.

const FREE_KEY: int = KEY_F13
const FREE_PAD: String = "b15"
## Actions whose control the keyboard summary of Options (options_panel.gd) names.
const SUMMARY_KEYS: Array[StringName] = [
	&"walk_forward", &"drive_left", &"walk_backward", &"drive_right", &"sprint", &"interact", &"jump",
	&"package_drop", &"drive_accelerate", &"drive_brake", &"drive_handbrake", &"drive_horn",
	&"drive_shift_up", &"drive_shift_down", &"phone_toggle", &"ui_ping", &"use_card", &"crew_panel",
]
## ...and the gamepad one (no package_drop).
const SUMMARY_PAD: Array[StringName] = [
	&"drive_left", &"drive_right", &"walk_forward", &"walk_backward", &"sprint", &"interact", &"jump",
	&"drive_accelerate", &"drive_brake", &"drive_handbrake", &"drive_horn",
	&"drive_shift_up", &"drive_shift_down", &"phone_toggle", &"ui_ping", &"use_card", &"crew_panel",
]

var _failures: int = 0
var _settings: Node
var _hints: GDScript
var _section_script: GDScript
var _options_script: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = root.get_node("GameSettings")
	_hints = load("res://scripts/ui/control_hints.gd")
	_section_script = load("res://scripts/ui/options_controls_section.gd")
	_options_script = load("res://scripts/ui/options_panel.gd")
	_settings.reset_to_defaults()
	_settings.using_gamepad = false

	_test_defaults()
	_test_rebound_keys()
	_test_rebound_pad()
	await _test_summary_follows()
	await _test_every_action()
	_test_care_names()

	_settings.using_gamepad = false
	_settings.reset_to_defaults()
	if _failures == 0:
		print("PASS: help texts name the rebound keys and buttons, and the options summary follows")
	quit(_failures)


# --- Defaults ----------------------------------------------------------------------------------


func _test_defaults() -> void:
	var walk: StringName = _hints.WALK
	var accelerate_brake: Array[StringName] = [&"drive_accelerate", &"drive_brake"]
	var steer: Array[StringName] = [&"drive_left", &"drive_right"]
	_expect(_hints.name_of(walk, false) == "WASD",
		"Walking reads WASD by default (got %s)" % _hints.name_of(walk, false))
	_expect(_hints.name_of(accelerate_brake, false) == "W/S",
		"Accelerate / brake read W/S (got %s)" % _hints.name_of(accelerate_brake, false))
	_expect(_hints.name_of(steer, false) == "A/D", "Steering reads A/D (got %s)" % _hints.name_of(steer, false))
	_expect(_hints.name_of(&"interact", false) == "E" and _hints.name_of(&"package_drop", false) == "Q",
		"Interact is E and drop is Q (got %s / %s)"
		% [_hints.name_of(&"interact", false), _hints.name_of(&"package_drop", false)])
	_expect(_hints.name_of(walk, true) == tr("UI_TUT_LEFT_STICK"),
		"On the gamepad walking is the left stick (got %s)" % _hints.name_of(walk, true))
	_expect(_hints.name_of(steer, true) == tr("UI_TUT_LEFT_STICK"),
		"...and so is steering (got %s)" % _hints.name_of(steer, true))
	_expect(_hints.name_of(&"interact", true) == tr("UI_OPT_PAD_A"),
		"Interact is A on the gamepad (got %s)" % _hints.name_of(&"interact", true))

	var on_foot: String = _hints.line("HUD_KEYS_ON_FOOT", [walk, &"jump", &"interact", &"package_drop"], false)
	var expected: String = tr("HUD_KEYS_ON_FOOT") % ["WASD", _settings.key_label(&"jump"), "E", "Q"]
	_expect(on_foot == expected and on_foot.contains("WASD") and on_foot.contains("E"),
		"The on-foot line is its translation filled with WASD, jump, E, Q (got %s)" % on_foot)
	var driver: String = _hints.line("HUD_KEYS_DRIVER",
		[accelerate_brake, steer, &"drive_handbrake", &"drive_horn", &"interact"], false)
	_expect(driver.contains("W/S") and driver.contains("A/D"), "The driver line names W/S and A/D (got %s)" % driver)
	_expect(_hints.line("HUD_KEYS_ON_FOOT", [], false) == tr("HUD_KEYS_ON_FOOT"),
		"A text without specs comes back as its translation")
	# hint() picks the device in hand.
	_settings.using_gamepad = false
	var keyboard_text: String = _hints.hint("HUD_KEY_PHONE", [&"phone_toggle"], "HUD_PAD_PHONE", [&"phone_toggle"])
	_expect(keyboard_text == tr("HUD_KEY_PHONE") % _settings.key_label(&"phone_toggle"),
		"hint() gives the keyboard text with a keyboard in hand (got %s)" % keyboard_text)
	_settings.using_gamepad = true
	var pad_text: String = _hints.hint("HUD_KEY_PHONE", [&"phone_toggle"], "HUD_PAD_PHONE", [&"phone_toggle"])
	_expect(pad_text == tr("HUD_PAD_PHONE") % _settings.pad_label(&"phone_toggle"),
		"...and the gamepad text with a gamepad in hand (got %s)" % pad_text)
	_settings.using_gamepad = false


# --- The care card ------------------------------------------------------------------------------


func _test_care_names() -> void:
	_settings.reset_to_defaults()
	_settings.using_gamepad = false
	var care: GDScript = load("res://scripts/gameplay/player/player_cargo_care.gd")
	var keys: Dictionary = care.control_names(false, "E", _settings)
	_expect(keys["drop"] == "Q" and keys["tool_next"] == "X" and keys["sides"] == "WASD" and keys["swing"] == "A / D",
		"The care card keeps the shipped names by default (got %s)" % keys)
	_expect(keys["walk"][Vector2.UP] == "W" and keys["walk"][Vector2.RIGHT] == "D", "...and W/D on the caps")
	_settings.rebind_key(&"package_drop", FREE_KEY)
	_settings.rebind_key(&"care_tool_next", KEY_F14)
	_settings.rebind_key(&"drive_left", KEY_LEFT)
	keys = care.control_names(false, "E", _settings)
	_expect(keys["drop"] == _settings.key_label(&"package_drop") and keys["drop"] != "Q",
		"A rebound drop key reaches the care card (got %s)" % keys["drop"])
	_expect(keys["tool_next"] == _settings.key_label(&"care_tool_next") and keys["tool_next"] != "X",
		"...and the next-tool key (got %s)" % keys["tool_next"])
	_expect(keys["walk"][Vector2.LEFT] == _settings.key_label(&"drive_left") and keys["swing"].begins_with(
		_settings.key_label(&"drive_left")) and not String(keys["sides"]).contains("WASD"),
		"...and a rebound walk key reaches the caps and the text (got %s / %s)" % [keys["swing"], keys["sides"]])
	var pad: Dictionary = care.control_names(true, "A", _settings)
	_expect(pad["drop"] == _settings.pad_label(&"package_drop"), "On the pad the drop button is read from the bindings")
	_settings.reset_to_defaults()


# --- Rebinding changes the text ----------------------------------------------------------------


func _test_rebound_keys() -> void:
	_settings.reset_to_defaults()
	_settings.using_gamepad = false
	var walk: StringName = _hints.WALK
	var specs: Array = [walk, &"jump", &"interact", &"package_drop"]
	var before: String = _hints.line("HUD_KEYS_ON_FOOT", specs, false)
	var result: Dictionary = _settings.rebind_key(&"walk_forward", KEY_UP)
	_expect(result["status"] == _settings.BIND_OK, "walk_forward rebinds to Up (got %s)" % result)
	result = _settings.rebind_key(&"interact", FREE_KEY)
	_expect(result["status"] == _settings.BIND_OK, "interact rebinds to a free key (got %s)" % result)
	var after: String = _hints.line("HUD_KEYS_ON_FOOT", specs, false)
	_expect(after != before, "The on-foot line changed after the remap (got %s)" % after)
	_expect(after.contains(_settings.key_label(&"interact")) and _settings.key_label(&"interact") != "E",
		"...and names the new interact key %s (got %s)" % [_settings.key_label(&"interact"), after])
	_expect(after.contains(_settings.key_label(&"walk_forward")) and not after.contains("WASD"),
		"...and walking no longer reads WASD (got %s)" % after)
	var expected_walk: String = _hints.name_of(walk, false)
	_expect(expected_walk.contains(_settings.key_label(&"walk_forward")) and expected_walk.contains("A")
			and expected_walk.contains("S") and expected_walk.contains("D"),
		"The walk name holds the new key and the other three (got %s)" % expected_walk)
	_expect(_hints.name_of([&"drive_accelerate", &"drive_brake"], false) == "W/S",
		"Driving keys are another context and keep W/S")
	_expect(_hints.name_of(&"interact", false) == _settings.key_label(&"interact"),
		"name_of(interact) follows the remap")
	_settings.reset_to_defaults()
	_expect(_hints.line("HUD_KEYS_ON_FOOT", specs, false) == before, "reset_to_defaults() brings the old text back")


func _test_rebound_pad() -> void:
	_settings.reset_to_defaults()
	_settings.using_gamepad = true
	var walk: StringName = _hints.WALK
	var specs: Array = [walk, &"interact"]
	var before: String = _hints.line("HUD_PAD_PASSENGER", specs, true)
	_expect(before.contains(tr("UI_TUT_LEFT_STICK")), "The pad text starts with the left stick (got %s)" % before)
	var result: Dictionary = _settings.rebind_pad(&"interact", FREE_PAD)
	_expect(result["status"] == _settings.BIND_OK, "interact rebinds to a free pad button (got %s)" % result)
	var after: String = _hints.line("HUD_PAD_PASSENGER", specs, true)
	_expect(after != before and after.contains(_settings.pad_label(&"interact"))
			and _settings.pad_label(&"interact") != tr("UI_OPT_PAD_A"),
		"The pad text names the new button %s (got %s)" % [_settings.pad_label(&"interact"), after])
	# One walking direction off the stick: the group no longer reads "Left stick".
	result = _settings.rebind_pad(&"walk_forward", "b16")
	_expect(result["status"] == _settings.BIND_OK, "walk_forward rebinds to a pad button (got %s)" % result)
	var walk_name: String = _hints.name_of(walk, true)
	_expect(walk_name != tr("UI_TUT_LEFT_STICK") and walk_name.contains(_settings.pad_label(&"walk_forward")),
		"Walking off the stick lists its inputs (got %s)" % walk_name)
	_settings.using_gamepad = false
	_settings.reset_to_defaults()
	_expect(_hints.line("HUD_PAD_PASSENGER", specs, true) == before, "reset_to_defaults() restores the pad text")


# --- The summary of Options -----------------------------------------------------------------------


func _test_summary_follows() -> void:
	_settings.reset_to_defaults()
	_settings.using_gamepad = false
	var options: Control = _options_script.new()
	root.add_child(options)
	await process_frame
	options.call(&"open")
	var label: Label = options.get(&"_controls_label")
	var section: Node = options.find_child("ControlsSection", true, false)
	_expect(label != null and section != null, "Options has the summary label and the controls section")
	if label == null or section == null:
		options.queue_free()
		return
	var start: String = label.text
	_expect(start.contains("WASD") and not start.contains("%s"),
		"The summary starts with WASD and no placeholder left (got %s)" % start)

	# The signal is what rewrites it: emitting it by hand makes the label follow the settings.
	_settings.rebind_key(&"interact", FREE_KEY)
	_expect(label.text == start, "The label only changes when the section refreshes (test setup)")
	var emitted: Array[int] = [0]
	section.connect(&"refreshed", func() -> void: emitted[0] += 1)
	section.call(&"refresh")
	_expect(emitted[0] == 1, "refresh() emits `refreshed` (got %d)" % emitted[0])
	_expect(label.text != start and label.text.contains(_settings.key_label(&"interact")),
		"...and the summary names the new interact key (got %s)" % label.text)

	# From the rows: a key taken, a swap, "put it back".
	section.call(&"apply_key", &"walk_forward", KEY_UP)
	_expect(label.text.contains(_settings.key_label(&"walk_forward")) and not label.text.contains("WASD"),
		"A key taken from the row is in the summary at once (got %s)" % label.text)
	section.call(&"apply_key", &"sprint", FREE_KEY)  # swap: interact gets sprint's old key
	_expect(label.text.contains(_settings.key_label(&"interact")) and _settings.bound_key(&"interact") == KEY_SHIFT,
		"A swap updates both controls in the summary (got %s)" % label.text)
	var reset: Button = section.find_child("Reset_walk_forward", true, false)
	_expect(reset != null, "walk_forward has its 'put it back' button")
	if reset != null:
		reset.pressed.emit()
	_expect(_settings.is_binding_default(&"walk_forward"), "'Put it back' restores walk_forward (test setup)")
	_expect(label.text.contains("WASD"), "...and the summary reads WASD again (got %s)" % label.text)

	# The panel's own reset and the gamepad version.
	options.call(&"_reset")
	_expect(label.text == start, "The panel's reset writes the original summary back (got %s)" % label.text)
	_settings.using_gamepad = true
	section.call(&"refresh")
	var pad_start: String = label.text
	_expect(pad_start != start and pad_start.contains(tr("UI_TUT_LEFT_STICK")),
		"With a gamepad in hand the summary is the pad one (got %s)" % pad_start)
	section.call(&"apply_pad", &"interact", FREE_PAD)
	_expect(label.text.contains(_settings.pad_label(&"interact")) and label.text != pad_start,
		"A pad input taken from the row is in the summary (got %s)" % label.text)
	_settings.using_gamepad = false
	options.call(&"_reset")
	options.queue_free()
	await process_frame


# --- Every action, one at a time ------------------------------------------------------------------


func _test_every_action() -> void:
	_settings.reset_to_defaults()
	_settings.using_gamepad = false
	var options: Control = _options_script.new()
	root.add_child(options)
	await process_frame
	options.call(&"open")
	var label: Label = options.get(&"_controls_label")
	var section: Node = options.find_child("ControlsSection", true, false)
	_expect(label != null and section != null, "Options has the summary label and the controls section (walk)")
	if label == null or section == null:
		options.queue_free()
		return
	var rows: int = 0
	for group: Dictionary in _section_script.GROUPS:
		for pair: Array in group["rows"]:
			var action: StringName = pair[0]
			rows += 1
			# Keyboard.
			_settings.using_gamepad = false
			section.call(&"refresh")
			var key_before: String = label.text
			var result: Dictionary = section.call(&"apply_key", action, FREE_KEY)
			_expect(result["status"] == _settings.BIND_OK, "%s takes a free key (got %s)" % [action, result])
			_expect(_keys_of(action) == [FREE_KEY], "%s has exactly the free key in the Input Map (got %s)"
				% [action, str(_keys_of(action))])
			var key_name: String = _settings.key_label(action)
			_expect(key_name == OS.get_keycode_string(FREE_KEY), "%s label follows (got %s)" % [action, key_name])
			if action in SUMMARY_KEYS:
				_expect(label.text.contains(key_name) and label.text != key_before,
					"The summary names the new key of %s (got %s)" % [action, label.text])
			else:
				_expect(label.text == key_before, "The summary does not change for %s, which it does not list" % action)
			section.call(&"_on_reset_pressed", action)
			_expect(_settings.is_binding_default(action) and label.text == key_before,
				"Putting %s back restores the key and the summary" % action)
			# Gamepad.
			_settings.using_gamepad = true
			section.call(&"refresh")
			var pad_before: String = label.text
			result = section.call(&"apply_pad", action, FREE_PAD)
			_expect(result["status"] == _settings.BIND_OK, "%s takes a free gamepad button (got %s)" % [action, result])
			_expect(_pad_codes(action) == [FREE_PAD], "%s has exactly %s on the pad in the Input Map (got %s)"
				% [action, FREE_PAD, str(_pad_codes(action))])
			var pad_name: String = _settings.pad_label(action)
			if action in SUMMARY_PAD:
				_expect(label.text.contains(pad_name) and label.text != pad_before,
					"The pad summary names the new button of %s (got %s)" % [action, label.text])
			else:
				_expect(label.text == pad_before, "The pad summary does not change for %s" % action)
			section.call(&"_on_reset_pressed", action)
			_expect(_settings.is_pad_binding_default(action) and label.text == pad_before,
				"Putting %s back restores the gamepad input and the summary" % action)
	_expect(rows >= 20, "The options groups list the actions (got %d rows)" % rows)
	_settings.using_gamepad = false
	options.call(&"_reset")
	options.queue_free()
	await process_frame


# --- Helpers -------------------------------------------------------------------------------------


func _keys_of(action: StringName) -> Array:
	var keys: Array = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append(int((event as InputEventKey).physical_keycode))
	return keys


func _pad_codes(action: StringName) -> Array:
	return load("res://scripts/core/pad_binding.gd").codes_in_map(action)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
