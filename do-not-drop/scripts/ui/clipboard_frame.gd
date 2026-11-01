extends Control
class_name ClipboardFrame
## The clipboard raised, as its owner sees it (expansion D-1902, diseno/portapapeles.md §2): a board with a
## wooden edge over the bottom two thirds of the screen, the shed still in sight above it, a row of tabs (one
## per sheet), the sheet itself and a foot with the keys.
##
## It only draws: CompanyClipboard decides which sheet shows and when it goes up or down. Each sheet is a
## panel with its own task (StockPanel, SupplierOrderPanel) in its embedded mode, added with add_sheet() and
## reparented under sheet_host(). A sheet not listed yet (set_listed(), Employees until milestone 8) has no tab:
## there are no greyed-out tabs. Tabs are clicked with the mouse; the keyboard and the gamepad change sheet with
## the clipboard's actions (the tabs take no focus, so the focus stays in the sheet).
##
## The foot names the keys from the input map as the player has it now (keyboard or gamepad,
## `GameSettings.using_gamepad` read by path: this compiles in --script tests, N-919), never fixed text:
## the clipboard's actions are not in GameSettings' rebind list, so ControlHints would not know them.

## A tab was clicked.
signal sheet_picked(id: StringName)

## The board's wooden edge and its fill.
const WOOD: Color = Color("8a5a2b")
const WOOD_EDGE: int = 10
## Gamepad buttons the foot names (the rest show their index).
const PAD_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓", JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
}

var _order: Array[StringName] = []
var _titles: Dictionary = {}
var _sheets: Dictionary = {}
var _listed: Dictionary = {}
var _current: StringName = &""

var _tabs: HBoxContainer
var _tab_buttons: Dictionary = {}
var _host: Control
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(self)
	_build()
	hide()


## Adds a sheet: `id`, its tab's `title` (already translated) and the panel drawn for it, which is moved
## under sheet_host(). Listed from the start unless `listed` is false.
func add_sheet(id: StringName, title: String, sheet: Control, listed: bool = true) -> void:
	if _sheets.has(id):
		return
	_order.append(id)
	_titles[id] = title
	_sheets[id] = sheet
	_listed[id] = listed
	if sheet.get_parent() != null:
		sheet.reparent(_host, false)
	else:
		_host.add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.hide()
	_redraw_tabs()


## Lists or unlists a sheet (a sheet that does not exist yet in the game has no tab).
func set_listed(id: StringName, listed: bool) -> void:
	if _sheets.has(id):
		_listed[id] = listed
		_redraw_tabs()


## The listed sheets, in tab order.
func sheet_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _order:
		if bool(_listed[id]):
			out.append(id)
	return out


func has_sheet(id: StringName) -> bool:
	return sheet_ids().has(id)


## The sheet the tabs mark ("" before any).
func current() -> StringName:
	return _current


## Marks `id`'s tab. Showing the panel is its owner's (CompanyClipboard asks the board). False when it is
## not listed.
func mark(id: StringName) -> bool:
	if not has_sheet(id):
		return false
	_current = id
	_redraw_tabs()
	return true


## The listed sheet `step` tabs away from the current one, wrapping around ("" without sheets).
func neighbour(step: int) -> StringName:
	var ids: Array[StringName] = sheet_ids()
	if ids.is_empty():
		return &""
	var at: int = ids.find(_current)
	if at < 0:
		return ids[0]
	return ids[posmod(at + step, ids.size())]


func sheet_host() -> Control:
	return _host


func tab_button(id: StringName) -> Button:
	return _tab_buttons.get(id)


## The text of the foot.
func hint_text() -> String:
	return _hint.text if _hint != null else ""


## Rewrites the foot for the keyboard or the gamepad: `keyboard` / `pad` are [text_key, actions].
func set_hint(keyboard: Array, pad: Array) -> void:
	var gamepad: bool = using_gamepad()
	var spec: Array = pad if gamepad else keyboard
	var names: Array = []
	for action: Variant in spec[1]:
		names.append(action_label(StringName(action), gamepad))
	var text: String = tr(String(spec[0]))
	_hint.text = text % names if text.count("%s") == names.size() else text


## True when the player plays with a gamepad now (GameSettings by path; false without it).
func using_gamepad() -> bool:
	var settings: Node = get_node_or_null(^"/root/GameSettings") if is_inside_tree() else null
	return settings != null and bool(settings.get(&"using_gamepad"))


## The first key (or gamepad button) of `action` in the input map, "?" when it has none.
static func action_label(action: StringName, pad: bool) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event: InputEvent in InputMap.action_get_events(action):
		if pad and event is InputEventJoypadButton:
			var button: int = (event as InputEventJoypadButton).button_index
			return String(PAD_NAMES.get(button, str(button)))
		if not pad and event is InputEventKey:
			var key := event as InputEventKey
			# The physical key's name (the US layout's): the display server's layout lookup is not there headless.
			var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
	return "?"


func _build() -> void:
	var board := PanelContainer.new()
	board.name = "Board"
	board.anchor_left = 0.08
	board.anchor_right = 0.92
	board.anchor_top = 1.0 / 3.0
	board.anchor_bottom = 1.0
	board.offset_bottom = -12
	var style: StyleBoxFlat = UiTheme.surface_style(16)
	style.border_color = WOOD
	style.set_border_width_all(WOOD_EDGE)
	board.add_theme_stylebox_override("panel", style)
	add_child(board)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	board.add_child(column)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 10)
	column.add_child(_tabs)
	_host = Control.new()
	_host.name = "Sheet"
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.mouse_filter = Control.MOUSE_FILTER_PASS
	# A sheet taller than the board (big text scale) is cut, never drawn over the tabs or the foot.
	_host.clip_contents = true
	column.add_child(_host)
	_hint = UiTheme.label(column, "", 15, UiTheme.MUTED)
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## One tab per listed sheet; the current one reads "[ Title ]" besides its colour.
func _redraw_tabs() -> void:
	for child: Node in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()
	for id: StringName in sheet_ids():
		var on: bool = id == _current
		var title: String = String(_titles[id])
		var button: Button = UiTheme.button(_tabs, ("[ %s ]" % title) if on else title, on, Vector2(150, 40))
		button.name = "Tab_%s" % id
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: sheet_picked.emit(id))
		_tab_buttons[id] = button
