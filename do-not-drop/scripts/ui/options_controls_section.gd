class_name OptionsControlsSection
extends VBoxContainer
## The key and gamepad bindings of the options screen (N-966): one row per action
## the player presses, grouped by where it is used (on foot, driving, crew), each
## with the key and the gamepad button (or stick / trigger direction) it has now
## and a button to put both back on the shipped inputs.
##
## The groups start collapsed so the options don't grow by two dozen rows; a
## header opens its group. Rebinding is GameSettings' job (rebind_key /
## reset_binding): it swaps a key another action already uses (in a context
## they share) and refuses what it can't swap cleanly; this section only says
## which of the two happened, in a line under the row that was edited.
##
## While a row waits for its key it reads _input, before the focus navigation
## eats keys like the arrows, Tab or Space. Esc (or B on a gamepad) cancels.
##
## A row that waits for a gamepad input takes the next button or stick / trigger
## push, B included, so B can't also be "cancel": Start or Esc cancel instead, a
## click elsewhere does too, and so does a few seconds of nothing, so nobody is
## left stuck waiting with only a pad in hand.

## Each row is [action, text key]. Actions shared between contexts say so in
## their text (left / right also strafe on foot).
const GROUPS: Array[Dictionary] = [
	{"id": &"foot", "title": "UI_OPT_BIND_GROUP_FOOT", "rows": [
		[&"walk_forward", "UI_OPT_BIND_WALK_FORWARD"], [&"walk_backward", "UI_OPT_BIND_WALK_BACK"],
		[&"drive_left", "UI_OPT_BIND_LEFT"], [&"drive_right", "UI_OPT_BIND_RIGHT"],
		[&"jump", "UI_OPT_BIND_JUMP"], [&"sprint", "UI_OPT_BIND_SPRINT"],
		[&"interact", "UI_OPT_BIND_INTERACT"],
		[&"package_drop", "UI_OPT_BIND_PACKAGE_DROP"], [&"package_open", "UI_OPT_BIND_PACKAGE_OPEN"],
		[&"care_work", "UI_OPT_BIND_CARE_WORK"], [&"care_tool_next", "UI_OPT_BIND_CARE_TOOL_NEXT"],
		[&"use_card", "UI_OPT_BIND_USE_CARD"], [&"phone_toggle", "UI_OPT_BIND_PHONE"],
	]},
	{"id": &"drive", "title": "UI_OPT_BIND_GROUP_DRIVE", "rows": [
		[&"drive_accelerate", "UI_OPT_BIND_ACCELERATE"], [&"drive_brake", "UI_OPT_BIND_BRAKE"],
		[&"drive_handbrake", "UI_OPT_BIND_HANDBRAKE"], [&"drive_horn", "UI_OPT_BIND_HORN"],
		[&"look_back", "UI_OPT_BIND_LOOK_BACK"],
		[&"drive_shift_up", "UI_OPT_BIND_SHIFT_UP"], [&"drive_shift_down", "UI_OPT_BIND_SHIFT_DOWN"],
	]},
	{"id": &"crew", "title": "UI_OPT_BIND_GROUP_CREW", "rows": [
		[&"ui_ping", "UI_OPT_BIND_PING"], [&"voice_talk", "UI_OPT_BIND_VOICE_TALK"],
		[&"crew_panel", "UI_OPT_BIND_CREW"], [&"spectate_toggle", "UI_OPT_BIND_SPECTATE"],
	]},
]
const PAD_BINDING = preload("res://scripts/core/pad_binding.gd")
const KEY_BUTTON_SIZE: Vector2 = Vector2(118, 38)
const PAD_BUTTON_SIZE: Vector2 = Vector2(118, 38)
const RESET_BUTTON_SIZE: Vector2 = Vector2(84, 38)
## A wait for a gamepad input gives up after this long (seconds).
const PAD_WAIT_SECONDS: float = 6.0
## Pushes right after the wait starts are ignored: the stick that was moving the
## focus down to the row is still settling.
const PAD_GRACE_SECONDS: float = 0.3

## action -> the button that shows (and rebinds) its key.
var buttons: Dictionary = {}
## action -> the button that shows (and rebinds) its gamepad input.
var pad_buttons: Dictionary = {}
## action -> the "put it back" button.
var reset_buttons: Dictionary = {}
var _notes: Dictionary = {}
var _boxes: Dictionary = {}
var _headers: Dictionary = {}
var _label_keys: Dictionary = {}
var _listening: StringName = &""
## What the row that waits waits for: a gamepad input (true) or a key (false).
var _listening_pad: bool = false
var _pad_wait_left: float = 0.0


func _ready() -> void:
	set_process_input(false)
	set_process(false)


## Builds the groups. Called by the panel once this node hangs under its column
## (so the font sizes follow the menu text scale of the panel).
func build() -> void:
	name = "ControlsSection"
	add_theme_constant_override("separation", 10)
	for group: Dictionary in GROUPS:
		_add_group(group)
	refresh()


func _add_group(group: Dictionary) -> void:
	var id: StringName = group["id"]
	var header: Button = UiTheme.button(self, "", false, Vector2(0, 40))
	header.name = "Header_" + String(id)
	header.pressed.connect(func() -> void: set_group_open(id, not is_group_open(id)))
	_headers[id] = header
	var box := VBoxContainer.new()
	box.name = "Group_" + String(id)
	box.add_theme_constant_override("separation", 8)
	box.visible = false
	add_child(box)
	_boxes[id] = box
	for pair: Array in group["rows"]:
		_add_row(box, pair[0], pair[1])
	_update_header(id)


func _add_row(parent: Control, action: StringName, text_key: String) -> void:
	_label_keys[action] = text_key
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 2)
	parent.add_child(holder)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	holder.add_child(row)
	var label: Label = UiTheme.label(row, tr(text_key), 16, UiTheme.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(130, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bind: Button = UiTheme.button(row, GameSettings.key_label(action), false, KEY_BUTTON_SIZE)
	bind.name = "Bind_" + String(action)
	bind.tooltip_text = tr("UI_OPT_BIND_KEY_TIP")
	bind.pressed.connect(func() -> void: start_listening(action))
	buttons[action] = bind
	var pad: Button = UiTheme.button(row, GameSettings.pad_label(action), false, PAD_BUTTON_SIZE)
	pad.name = "Pad_" + String(action)
	pad.tooltip_text = tr("UI_OPT_BIND_PAD_TIP")
	pad.pressed.connect(func() -> void: start_listening_pad(action))
	pad_buttons[action] = pad
	# The d-pad / stick walks along the row: key button -> gamepad button -> back.
	bind.focus_neighbor_right = bind.get_path_to(pad)
	pad.focus_neighbor_left = pad.get_path_to(bind)
	var reset: Button = UiTheme.button(row, tr("UI_OPT_BIND_DEFAULT"), false, RESET_BUTTON_SIZE)
	reset.name = "Reset_" + String(action)
	reset.tooltip_text = tr("UI_OPT_BIND_DEFAULT_HINT")
	UiTheme.register_font_size(reset, 14)
	reset.pressed.connect(func() -> void: _on_reset_pressed(action))
	reset_buttons[action] = reset
	var note: Label = UiTheme.label(holder, "", 14, UiTheme.INK)
	note.name = "Note_" + String(action)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.hide()
	_notes[action] = note


func is_group_open(id: StringName) -> bool:
	return _boxes.has(id) and (_boxes[id] as Control).visible


func set_group_open(id: StringName, open: bool) -> void:
	if not _boxes.has(id):
		return
	(_boxes[id] as Control).visible = open
	_update_header(id)


func _update_header(id: StringName) -> void:
	var title: String = ""
	for group: Dictionary in GROUPS:
		if group["id"] == id:
			title = tr(group["title"])
	var marker: String = "[-]" if is_group_open(id) else "[+]"
	(_headers[id] as Button).text = "%s %s" % [marker, title]


## The row's text (what the player reads), whatever language is on.
func action_label(action: StringName) -> String:
	return tr(String(_label_keys.get(action, ""))) if _label_keys.has(action) else String(action)


func is_listening() -> bool:
	return not _listening.is_empty()


## Waits for the next key for this action.
func start_listening(action: StringName) -> void:
	if not buttons.has(action):
		return
	_end_listening()
	_hide_notes()
	refresh()
	_begin_listening(action, false)
	(buttons[action] as Button).text = tr("UI_OPT_PRESS_KEY")


## Waits for the next gamepad button, or stick / trigger push, for this action.
func start_listening_pad(action: StringName) -> void:
	if not pad_buttons.has(action):
		return
	_end_listening()
	_hide_notes()
	refresh()
	_begin_listening(action, true)
	_pad_wait_left = PAD_WAIT_SECONDS
	(pad_buttons[action] as Button).text = tr("UI_OPT_PRESS_PAD")
	_show_note(action, tr("UI_OPT_PRESS_PAD_HINT"))


func _begin_listening(action: StringName, pad: bool) -> void:
	_listening = action
	_listening_pad = pad
	set_process_input(true)
	set_process(pad)


func stop_listening() -> void:
	_end_listening()
	_hide_notes()
	refresh()


func _end_listening() -> void:
	_listening = &""
	_listening_pad = false
	_pad_wait_left = 0.0
	set_process_input(false)
	set_process(false)


func _process(delta: float) -> void:
	if not _listening_pad:
		return
	_pad_wait_left -= delta
	if _pad_wait_left <= 0.0:
		stop_listening()


func _input(event: InputEvent) -> void:
	if _listening.is_empty() or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed:
		# A click outside the row that waits ends the wait; the click itself still
		# reaches what it hit. Clicking its own key button leaves it waiting.
		var own: Button = (pad_buttons if _listening_pad else buttons).get(_listening)
		if own == null or not own.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			stop_listening()
		return
	if _listening_pad:
		_input_pad(event)
		return
	if event.is_action_pressed(&"ui_cancel"):
		stop_listening()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var action: StringName = _listening
		_end_listening()
		apply_key(action, code)
		get_viewport().set_input_as_handled()


## The gamepad wait: Esc or Start cancel (B is a button like any other here),
## a button press or a clear stick push is taken.
func _input_pad(event: InputEvent) -> void:
	var cancel: bool = event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE
	cancel = cancel or event.is_action_pressed(&"ui_pause")
	if cancel:
		stop_listening()
		get_viewport().set_input_as_handled()
		return
	var code: String = ""
	if event is InputEventJoypadButton and event.pressed:
		code = PAD_BINDING.code_of(event)
	elif event is InputEventJoypadMotion \
			and absf((event as InputEventJoypadMotion).axis_value) >= PAD_BINDING.AXIS_THRESHOLD:
		if PAD_WAIT_SECONDS - _pad_wait_left < PAD_GRACE_SECONDS:
			get_viewport().set_input_as_handled()
			return
		code = PAD_BINDING.code_of(event)
	if code.is_empty():
		return
	var action: StringName = _listening
	_end_listening()
	apply_pad(action, code)
	get_viewport().set_input_as_handled()


## Binds the key (swapping or refusing as GameSettings decides) and shows what
## happened under the row. Returns GameSettings' result.
func apply_key(action: StringName, keycode: int) -> Dictionary:
	var result: Dictionary = GameSettings.rebind_key(action, keycode)
	refresh()
	_show_result(action, result, false)
	return result


## The same for a gamepad code (pad_binding.gd).
func apply_pad(action: StringName, code: String) -> Dictionary:
	var result: Dictionary = GameSettings.rebind_pad(action, code)
	refresh()
	_show_result(action, result, true)
	return result


## Both inputs of the row back on the shipped ones; the line under the row
## tells about whichever of the two needed a swap (or was refused).
func _on_reset_pressed(action: StringName) -> void:
	_end_listening()
	var result: Dictionary = GameSettings.reset_binding(action)
	var pad_result: Dictionary = GameSettings.reset_pad_binding(action)
	var pad_noted: bool = result.get("status", &"") in [GameSettings.BIND_OK, GameSettings.BIND_INVALID]
	refresh()
	_show_result(action, pad_result if pad_noted else result, pad_noted)


func _show_result(action: StringName, result: Dictionary, pad: bool) -> void:
	_hide_notes()
	var text: String = ""
	var other: String = action_label(result.get("other", &""))
	var status: StringName = result.get("status", &"")
	if status == GameSettings.BIND_SWAPPED:
		text = tr("UI_OPT_BIND_PAD_SWAPPED" if pad else "UI_OPT_BIND_SWAPPED") % other
	elif status == GameSettings.BIND_BLOCKED:
		text = tr("UI_OPT_BIND_PAD_BLOCKED" if pad else "UI_OPT_BIND_BLOCKED") % other
	elif status == GameSettings.BIND_RESERVED:
		text = tr("UI_OPT_BIND_PAD_RESERVED" if pad else "UI_OPT_BIND_RESERVED")
	_show_note(action, text)


func _hide_notes() -> void:
	for note: Label in _notes.values():
		note.hide()


func _show_note(action: StringName, text: String) -> void:
	_hide_notes()
	if text.is_empty() or not _notes.has(action):
		return
	var note: Label = _notes[action]
	note.text = text
	note.show()


## The text of the line under a row ("" while it is hidden).
func note_text(action: StringName) -> String:
	var note: Label = _notes.get(action)
	return note.text if note != null and note.visible else ""


## Every button back in line with GameSettings (after a reset, a rebind or a
## swap). A disabled "put it back" button can't keep a gamepad's focus, so the
## focus moves to the input button next to it (the pad's when a pad is in hand).
func refresh() -> void:
	for action: StringName in buttons:
		var waiting: bool = _listening == action
		if not (waiting and not _listening_pad):
			(buttons[action] as Button).text = GameSettings.key_label(action)
		if not (waiting and _listening_pad):
			(pad_buttons[action] as Button).text = GameSettings.pad_label(action)
		var reset: Button = reset_buttons[action]
		var at_default: bool = GameSettings.is_binding_default(action) and GameSettings.is_pad_binding_default(action)
		if at_default and reset.has_focus():
			var target: Button = pad_buttons[action] if GameSettings.using_gamepad else buttons[action]
			target.grab_focus()
		reset.disabled = at_default
