extends RefCounted
## One gamepad input per action, as a short saved code (N-966.3): the pure part
## of the gamepad remapping, with no state. GameSettings keeps what the player
## chose (pad_bindings) and applies it to the Input Map; Options asks this file
## how an input is written, named and told apart from the others.
##
## A code is "b<index>" for a button ("b0" = A, "b7" = left stick click) or
## "a<axis><sign>" for one direction of an axis ("a0-" = left stick to the left,
## "a5+" = right trigger). "" is no gamepad input. The shipped code of an action
## is whatever project.godot gives it, read from ProjectSettings so a change
## there reaches everyone who never touched that action.

## Never moved by the player and never handed to another action: pause, restart,
## look center, the right stick that looks around, the primary package action and
## the phone shutter. An action may keep the code it ships with even when one of
## these ships with the same one (the right trigger accelerates and grabs).
const RESERVED_ACTIONS: Array[StringName] = [
	&"ui_pause", &"run_restart", &"look_center", &"look_left", &"look_right", &"look_up", &"look_down",
	&"package_action_primary", &"phone_shutter",
]
## What reads as a stick or trigger push, not as drift.
const AXIS_THRESHOLD: float = 0.6
const MAX_BUTTON: int = 63
const MAX_AXIS: int = 9

## Text keys by button index (JoyButton) and by "axis+sign".
const BUTTON_TEXT := {
	0: "UI_OPT_PAD_A", 1: "UI_OPT_PAD_B", 2: "UI_OPT_PAD_X", 3: "UI_OPT_PAD_Y",
	4: "UI_OPT_PAD_BACK", 5: "UI_OPT_PAD_GUIDE", 6: "UI_OPT_PAD_START",
	7: "UI_OPT_PAD_L3", 8: "UI_OPT_PAD_R3", 9: "UI_OPT_PAD_LB", 10: "UI_OPT_PAD_RB",
	11: "UI_OPT_PAD_DPAD_UP", 12: "UI_OPT_PAD_DPAD_DOWN", 13: "UI_OPT_PAD_DPAD_LEFT", 14: "UI_OPT_PAD_DPAD_RIGHT",
}
const AXIS_TEXT := {
	"0-": "UI_OPT_PAD_LSTICK_LEFT", "0+": "UI_OPT_PAD_LSTICK_RIGHT",
	"1-": "UI_OPT_PAD_LSTICK_UP", "1+": "UI_OPT_PAD_LSTICK_DOWN",
	"2-": "UI_OPT_PAD_RSTICK_LEFT", "2+": "UI_OPT_PAD_RSTICK_RIGHT",
	"3-": "UI_OPT_PAD_RSTICK_UP", "3+": "UI_OPT_PAD_RSTICK_DOWN",
	"4+": "UI_OPT_PAD_LT", "5+": "UI_OPT_PAD_RT",
}

## action -> shipped code, read once.
static var _defaults: Dictionary = {}


## The code of a gamepad event, "" for anything else (or a stick at rest).
static func code_of(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return "b%d" % (event as InputEventJoypadButton).button_index
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if is_zero_approx(motion.axis_value):
			return ""
		return "a%d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	return ""


## True when the code is written the way code_of() writes it.
static func is_valid(code: String) -> bool:
	if code.length() < 2:
		return false
	var body: String = code.substr(1)
	if code[0] == "b":
		return body.is_valid_int() and int(body) >= 0 and int(body) <= MAX_BUTTON
	if code[0] == "a":
		var sign_char: String = body[body.length() - 1]
		var axis: String = body.substr(0, body.length() - 1)
		return sign_char in ["+", "-"] and axis.is_valid_int() and int(axis) >= 0 and int(axis) <= MAX_AXIS
	return false


## A new event for the Input Map. It answers on every connected pad.
static func make_event(code: String) -> InputEvent:
	if not is_valid(code):
		return null
	if code[0] == "b":
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = int(code.substr(1)) as JoyButton
		return button
	var motion := InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = int(code.substr(1, code.length() - 2)) as JoyAxis
	motion.axis_value = 1.0 if code.ends_with("+") else -1.0
	return motion


## The codes the Input Map has for an action right now (several if a project
## ever gives one action two gamepad inputs).
static func codes_in_map(action: StringName) -> Array[String]:
	var found: Array[String] = []
	if not InputMap.has_action(action):
		return found
	for event: InputEvent in InputMap.action_get_events(action):
		var code: String = code_of(event)
		if not code.is_empty():
			found.append(code)
	return found


## What project.godot gives the action ("" when it has no gamepad input).
static func default_code(action: StringName) -> String:
	if not _defaults.has(action):
		var shipped: String = ""
		var setting: Variant = ProjectSettings.get_setting("input/" + String(action), null)
		if setting is Dictionary:
			for event: Variant in (setting as Dictionary).get("events", []):
				var code: String = code_of(event as InputEvent)
				if shipped.is_empty() and not code.is_empty():
					shipped = code
		_defaults[action] = shipped
	return String(_defaults[action])


## True when two actions ship on the same gamepad input (RB is both "shift up"
## and the phone shutter, the left stick click is both "sprint" and "look back"):
## they are never used at once, so sharing it is not a conflict.
static func ship_together(first: StringName, second: StringName) -> bool:
	var code: String = default_code(first)
	return not code.is_empty() and code == default_code(second)


## True when the code belongs to an action Options doesn't offer. The action
## that ships with that very code may keep it.
static func is_reserved(code: String, action: StringName) -> bool:
	if code.is_empty() or code == default_code(action):
		return false
	for reserved: StringName in RESERVED_ACTIONS:
		if code in codes_in_map(reserved):
			return true
	return false


## The name the player reads ("A", "LB", "Stick izq. ←"), in the language on.
static func label(code: String) -> String:
	if not is_valid(code):
		return TranslationServer.translate("UI_OPT_PAD_NONE")
	if code[0] == "b":
		var index: int = int(code.substr(1))
		if BUTTON_TEXT.has(index):
			return TranslationServer.translate(BUTTON_TEXT[index])
		return TranslationServer.translate("UI_OPT_PAD_BUTTON") % index
	var direction: String = code.substr(1)
	if AXIS_TEXT.has(direction):
		return TranslationServer.translate(AXIS_TEXT[direction])
	var axis: int = int(direction.substr(0, direction.length() - 1))
	return TranslationServer.translate("UI_OPT_PAD_AXIS") % [axis, direction.right(1)]
