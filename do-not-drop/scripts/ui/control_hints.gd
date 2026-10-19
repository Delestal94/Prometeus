extends RefCounted
## The names of the controls that the static help texts print (N-966.4): the
## cheat sheet, the options summary, the phone hint. Every key and button comes
## from the action as the player has it now (GameSettings.key_label /
## pad_label), so a rebound control reads right; what no one can rebind (the
## mouse, the right stick, Start, the shutter) stays written in the text itself.
##
## A text has one "%s" per control, in order, and a spec for each: an action,
## WALK (the four that walk, "WASD" by default) or an Array of actions (written
## "W/S", or "Stick izq." when they all sit on the left stick).

## The four actions that walk, in the order WASD reads them.
const WALK: StringName = &"@walk"
const WALK_ACTIONS: Array[StringName] = [
	&"walk_forward", &"drive_left", &"walk_backward", &"drive_right",
]
## Gamepad codes of the left stick (pad_binding.gd): axis 0 sideways, axis 1 up / down.
const LEFT_STICK: Array[String] = ["a0-", "a0+", "a1-", "a1+"]
const JOIN: String = "/"


## `text_key` filled with the names of `specs` (keyboard or gamepad).
static func line(text_key: String, specs: Array, pad: bool) -> String:
	var text: String = TranslationServer.translate(text_key)
	if specs.is_empty():
		return text
	var names: Array[String] = []
	for spec: Variant in specs:
		names.append(name_of(spec, pad))
	return text % names


## The text of the device in hand: the keyboard's with its specs, or the
## gamepad's with its own (a half rarely names the same controls as the other).
static func hint(keyboard_key: String, keyboard_specs: Array,
		pad_key: String, pad_specs: Array) -> String:
	if GameSettings.using_gamepad:
		return line(pad_key, pad_specs, true)
	return line(keyboard_key, keyboard_specs, false)


## One spec as the player reads it.
static func name_of(spec: Variant, pad: bool) -> String:
	if spec is Array:
		return _group(spec as Array, pad, false)
	var action: StringName = StringName(spec)
	if action == WALK:
		return _group(WALK_ACTIONS, pad, true)
	return GameSettings.pad_label(action) if pad else GameSettings.key_label(action)


## Several actions as one name. On the keyboard "W/S" ("WASD" when `glued` and
## every key is one character); on the gamepad the left stick when that is
## where all of them are, their names joined otherwise.
static func _group(actions: Array, pad: bool, glued: bool) -> String:
	if pad:
		var on_stick: bool = true
		for action: Variant in actions:
			on_stick = on_stick and GameSettings.bound_pad(StringName(action)) in LEFT_STICK
		if on_stick:
			return TranslationServer.translate("UI_TUT_LEFT_STICK")
	var names: PackedStringArray = []
	var single: bool = true
	for action: Variant in actions:
		var label: String = name_of(action, pad)
		single = single and label.length() == 1
		names.append(label)
	return ("" if glued and single else JOIN).join(names)
