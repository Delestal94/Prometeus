class_name CompanySlotsPage
extends VBoxContainer
## The main menu's "Modo Empresa" page (D-1904): the saved companies and a new one.
##
## Three views inside the menu card, one at a time:
##   - LIST: "Nueva empresa", one row per saved company (CompanySave.list_slots(): name, day, money,
##     date and a chip per modifier on, its text on focus) with "Opciones" and "Borrar" (pressed twice),
##     and "Abrir sala para amigos" to play it hosting a room instead of solo.
##   - NEW: the company's name and its modifiers (D-1919, diseno/dificultad.md §3: chosen here, under
##     the name, off by default).
##   - OPTIONS: a saved company's modifiers, written to its file before it opens
##     (CompanySave.write_options()); never with the company open.
##
## It starts nothing itself: play_requested(slot, host) tells the menu which slot the company world
## takes (CompanyRoot.launch_slot). Before that it leaves CompanyState ready: off, so the world loads
## the slot; or, for a new company, on with its name and modifiers, so the world saves its day 1 to
## the new slot (CompanySave.new_slot_id()). The state is a parameter (the /root/CompanyState
## autoload by default) and the folder too, so a --script test can use its own (N-919).

signal play_requested(slot: String, host: bool)
## "Volver" on the list: the menu goes back to its Play page.
signal closed

enum View { LIST, NEW, OPTIONS }

const COMPANY_STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")
## Each modifier's label, description and chip (strings_ui.csv).
const OPTION_TEXT: Dictionary = {
	"assisted_packing": ["UI_COMPANY_OPT_ASSISTED_PACKING", "UI_COMPANY_OPT_ASSISTED_PACKING_DESC",
		"UI_COMPANY_OPT_ASSISTED_PACKING_SHORT"],
	"calm_days": ["UI_COMPANY_OPT_CALM_DAYS", "UI_COMPANY_OPT_CALM_DAYS_DESC", "UI_COMPANY_OPT_CALM_DAYS_SHORT"],
}
const NAME_MAX_LENGTH: int = 24
## The list scrolls past this height: the card has to fit a 720p screen with its title and "Volver".
const LIST_MAX_HEIGHT: int = 300

## CompanyState (the autoload's script); null takes /root/CompanyState on _ready().
var state: Node
var save_dir: String = CompanySave.SAVE_DIR
var view: View = View.LIST

var _views: Dictionary = {}
var _host_toggle: CheckBox
var _new_button: Button
var _rows: VBoxContainer
var _empty_label: Label
var _name_field: LineEdit
var _new_toggles: Dictionary = {}
var _create_button: Button
var _options_title: Label
var _options_toggles: Dictionary = {}
var _options_save: Button
## The slot OPTIONS is editing.
var _options_slot: String = ""
## Slot of the "Borrar" pressed once: the next press deletes it.
var _armed_delete: String = ""


func _ready() -> void:
	if state == null:
		state = get_node_or_null(^"/root/CompanyState")
	add_theme_constant_override("separation", 10)
	_build_list()
	_build_new()
	_build_options()
	refresh()
	_show(View.LIST, false)


## Shows the list with fresh slots and focuses its first choice (the menu calls it on arrival).
func open() -> void:
	refresh()
	_show(View.LIST)


## Esc / B and "Volver": a form goes back to the list (true); on the list it is the menu's (false).
func back() -> bool:
	if view == View.LIST:
		return false
	_show(View.LIST)
	return true


## The saved companies, as the list shows them (a test reads it too).
func slots() -> Array[Dictionary]:
	return CompanySave.list_slots(save_dir)


## Rebuilds the rows from the folder.
func refresh() -> void:
	_armed_delete = ""
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var listed: Array[Dictionary] = slots()
	_empty_label.visible = listed.is_empty()
	for entry: Dictionary in listed:
		_add_row(entry)


## The "Jugar" button of a slot's row (null when it is not listed).
func play_button(slot: String) -> Button:
	return _rows.get_node_or_null(NodePath("Slot_%s/Play" % slot.validate_node_name())) as Button


## Starts a saved company: the state goes off, so the world loads the slot.
func play_slot(slot: String) -> void:
	if state != null:
		state.call(&"reset")
	play_requested.emit(slot, _host_toggle.button_pressed)


## The NEW form's "Crear y jugar": a company on with its name and modifiers, in a free slot.
func create_company() -> void:
	var title: String = _name_field.text.strip_edges()
	if title.is_empty():
		title = tr("UI_COMPANY_SLOTS_DEFAULT_NAME")
	var slot: String = CompanySave.new_slot_id(save_dir)
	if state != null:
		state.call(&"reset")
		state.call(&"new_company", title)
		state.set(&"options", COMPANY_STATE_SCRIPT.sanitize_options(_toggle_values(_new_toggles)))
	play_requested.emit(slot, _host_toggle.button_pressed)


## Opens OPTIONS for a saved slot, its toggles as the file has them.
func edit_options(slot: String) -> void:
	for entry: Dictionary in slots():
		if entry["slot"] != slot:
			continue
		_options_slot = slot
		_options_title.text = tr("UI_COMPANY_SLOTS_OPTIONS_TITLE") % entry["name"]
		for key: String in _options_toggles:
			(_options_toggles[key] as CheckBox).button_pressed = bool((entry["options"] as Dictionary).get(key, false))
		_show(View.OPTIONS)
		return


## OPTIONS' "Guardar": the toggles go to the slot's file, back to the list.
func save_options() -> bool:
	var saved: bool = CompanySave.write_options(_toggle_values(_options_toggles), _options_slot, save_dir)
	if not saved:
		UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.ERROR)
	refresh()
	_show(View.LIST)
	return saved


## "Borrar": the first press only arms it (its text asks), the second removes the slot.
func press_delete(slot: String) -> void:
	if _armed_delete != slot:
		refresh()
		_armed_delete = slot
		var button := _rows.get_node_or_null(NodePath("Slot_%s/Actions/Delete" % slot.validate_node_name())) as Button
		if button != null:
			button.text = tr("UI_COMPANY_SLOTS_DELETE_CONFIRM")
			button.grab_focus()
		return
	CompanySave.delete(slot, save_dir)
	refresh()
	_new_button.grab_focus()


func _build_list() -> void:
	var page: VBoxContainer = _add_view(View.LIST)
	_host_toggle = _check_box(page, tr("UI_COMPANY_SLOTS_HOST"), false)
	_host_toggle.name = "HostToggle"
	_new_button = UiTheme.button(page, tr("UI_COMPANY_SLOTS_NEW"), true)
	_new_button.name = "NewCompany"
	_new_button.pressed.connect(_show.bind(View.NEW))
	_empty_label = UiTheme.label(page, tr("UI_COMPANY_SLOTS_EMPTY"), 15, UiTheme.INK)
	_empty_label.name = "Empty"
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 0
	page.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	_rows.resized.connect(func() -> void:
		scroll.custom_minimum_size.y = minf(_rows.size.y, LIST_MAX_HEIGHT))
	scroll.add_child(_rows)
	_back(page)


func _build_new() -> void:
	var page: VBoxContainer = _add_view(View.NEW)
	UiTheme.label(page, tr("UI_COMPANY_SLOTS_NAME"), 15, UiTheme.INK)
	_name_field = UiTheme.line_edit(page, tr("UI_COMPANY_SLOTS_DEFAULT_NAME"))
	_name_field.name = "NameField"
	_name_field.max_length = NAME_MAX_LENGTH
	_name_field.text_submitted.connect(func(_text: String) -> void: create_company())
	_new_toggles = _option_toggles(page)
	_create_button = UiTheme.button(page, tr("UI_COMPANY_SLOTS_CREATE"), true)
	_create_button.name = "Create"
	_create_button.pressed.connect(create_company)
	_back(page)


func _build_options() -> void:
	var page: VBoxContainer = _add_view(View.OPTIONS)
	_options_title = UiTheme.label(page, "", 17, UiTheme.INK)
	_options_title.name = "OptionsTitle"
	_options_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_toggles = _option_toggles(page)
	_options_save = UiTheme.button(page, tr("UI_COMPANY_SLOTS_SAVE"), true)
	_options_save.name = "Save"
	_options_save.pressed.connect(save_options)
	_back(page)


## One row per slot: "Jugar" with the name and the day's numbers, then chips and the two actions.
func _add_row(entry: Dictionary) -> void:
	var slot: String = entry["slot"]
	var row := VBoxContainer.new()
	row.name = "Slot_%s" % slot.validate_node_name()
	row.add_theme_constant_override("separation", 6)
	_rows.add_child(row)
	var too_new: bool = int(entry["version"]) > CompanySave.VERSION
	var details: String = tr("UI_COMPANY_SLOTS_TOO_NEW") if too_new else tr("UI_COMPANY_SLOTS_DETAILS") % [
		int(entry["day"]), int(entry["money"]), _date_text(int(entry["saved_at"]))]
	var play: Button = UiTheme.button(row, "%s\n%s" % [entry["name"], details], false, Vector2(0, 64))
	play.name = "Play"
	play.add_theme_font_size_override("font_size", 17)
	play.disabled = too_new
	play.pressed.connect(play_slot.bind(slot))
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	var on: PackedStringArray = []
	for key: String in OPTION_TEXT:
		if bool((entry["options"] as Dictionary).get(key, false)):
			var chip: Label = UiTheme.chip(actions, tr(OPTION_TEXT[key][2]), UiTheme.MINT, 13)
			chip.get_parent().name = "Chip_%s" % key
			on.append(tr(OPTION_TEXT[key][0]))
	# The chips are small: the button says them in full when it has the focus (and on hover).
	play.tooltip_text = ", ".join(on)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	var options: Button = _small_button(actions, tr("UI_OPTIONS"))
	options.name = "Options"
	options.disabled = too_new
	options.pressed.connect(edit_options.bind(slot))
	var delete: Button = _small_button(actions, tr("UI_COMPANY_SLOTS_DELETE"))
	delete.name = "Delete"
	delete.pressed.connect(press_delete.bind(slot))


## A checkbox per modifier with its description under it, all off.
func _option_toggles(page: VBoxContainer) -> Dictionary:
	var toggles: Dictionary = {}
	for key: String in OPTION_TEXT:
		var toggle: CheckBox = _check_box(page, tr(OPTION_TEXT[key][0]), false)
		toggle.name = "Option_%s" % key
		toggles[key] = toggle
		var description: Label = UiTheme.label(page, tr(OPTION_TEXT[key][1]), 14, UiTheme.MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return toggles


func _toggle_values(toggles: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for key: String in toggles:
		values[key] = (toggles[key] as CheckBox).button_pressed
	return values


func _show(next: View, focus: bool = true) -> void:
	view = next
	for key: View in _views:
		(_views[key] as Control).visible = key == next
	if next == View.NEW:
		_name_field.text = ""
		for toggle: CheckBox in _new_toggles.values():
			toggle.button_pressed = false
	if not focus:
		return
	match next:
		View.LIST:
			_new_button.grab_focus()
		View.NEW:
			_name_field.grab_focus()
		View.OPTIONS:
			(_options_toggles.values()[0] as CheckBox).grab_focus()


func _add_view(key: View) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "View%s" % View.keys()[key].capitalize()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_views[key] = box
	return box


func _back(page: VBoxContainer) -> void:
	var button: Button = _small_button(page, tr("UI_BACK"))
	button.name = "Back"
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size.x = 140
	button.pressed.connect(func() -> void:
		if not back():
			closed.emit())


func _check_box(parent: Node, text: String, pressed: bool) -> CheckBox:
	var toggle: CheckBox = UiTheme.check_box(parent, text, pressed)
	UiTheme.UI_SOUNDS.bind_button(toggle)
	return toggle


func _small_button(parent: Node, text: String) -> Button:
	var button: Button = UiTheme.button(parent, text, false, Vector2(0, 40))
	button.add_theme_font_size_override("font_size", 16)
	return button


## The local date and time a slot was last saved, "01/11 14:30" ("" for none).
static func _date_text(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var when: Dictionary = Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%02d/%02d %02d:%02d" % [when["day"], when["month"], when["hour"], when["minute"]]
