extends Control
class_name CompanyPauseMenu
## The company's pause menu (expansion D-1909, with D-0253.a): Continue, Close the day, Options,
## Back to menu and Quit, over a dimmed world.
##
## CompanySoloPause opens it with Esc (ui_pause). Alone the world and the day's clock stop (a real
## pause); with anyone else in the session the world goes on and this is only a menu (soft), as the
## delivery HUD's pause does. The mouse is free while it is open, so the player takes no input.
##
## "Close the day" is DayClose.button(): on the host while the day is OPERATING it asks its
## confirmation and then DayClose.close() sends CLOSING; on a client it is off with "The host closes
## the day" under it. While leaving would lose the day (DayClose.exit_warning(), host in OPERATING or
## CLOSING) the warning sits over the two exits and each of them asks first. The state is read again
## every frame it is shown, so a day that changes phase under an open menu redraws it.
##
## Gamepad first: one focus column; ui_cancel / ui_pause go back from a confirmation and otherwise
## close the menu (CompanySoloPause routes them here through back()).

## Continue was pressed (or back() with nothing to go back from): the owner resumes.
signal resume_requested
## The host confirmed the close: DayClose.close() already ran (true when the day went to CLOSING).
signal day_closed(ok: bool)

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const EXIT_ANYWAY_KEY: String = "UI_COMPANY_EXIT_ANYWAY"
const PAUSE_BODY_KEY: String = "UI_COMPANY_PAUSE_BODY"
const SOFT_BODY_KEY: String = "UI_COMPANY_SOFT_PAUSE_BODY"
const EXIT_MENU: StringName = &"menu"
const EXIT_QUIT: StringName = &"quit"
## Loaded by path, not by class: OptionsPanel names autoloads, and this menu is compiled before they
## exist in a --script test (lesson N-919).
const OPTIONS_PANEL_PATH: String = "res://scripts/ui/options_panel.gd"

## The day this menu closes and warns about; null outside a company day (the button stays off).
var day_cycle: DayCycle = null
## How an exit is carried out, as Callable(kind: StringName); unset, the real one (main menu or
## quitting the game). A test drives it to see which exit was taken without leaving the scene.
var exit_action: Callable = Callable()

var _real: bool = false
## The confirmation being asked: &"" none, &"close" the day, or an exit kind.
var _asking: StringName = &""

var _title: Label
var _body: Label
var _main: VBoxContainer
var _continue_button: Button
var _close_button: Button
var _close_hint: Label
var _options_button: Button
var _warning: Label
var _menu_button: Button
var _quit_button: Button
var _confirm: VBoxContainer
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button
var _options: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiTheme.apply(self)
	_build()
	hide()


## Shows the menu: `real` when the world is stopped (alone), false when it goes on (soft).
func open(real: bool) -> void:
	_real = real
	_asking = &""
	_title.text = tr("HUD_PAUSED") if real else tr("HUD_MENU_TITLE")
	_body.text = tr(PAUSE_BODY_KEY) if real else tr(SOFT_BODY_KEY)
	refresh()
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_continue_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	if _options != null and _options.visible:
		_options.call(&"close")
	_asking = &""
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()


func is_open() -> bool:
	return visible


## True while the options screen is up over the menu (it takes Esc itself).
func options_open() -> bool:
	return _options != null and _options.visible


## Esc / B: out of a confirmation back to the menu, else asks the owner to resume.
func back() -> void:
	if _asking != &"":
		_ask(&"")
		return
	resume_requested.emit()


## Redraws the close button, its hint, the warning and which view is up from the day as it is now.
func refresh() -> void:
	var state: Dictionary = DayClose.button(day_cycle)
	_close_button.text = String(state["text"])
	_close_button.disabled = not bool(state["enabled"])
	# Godot's focus moves land on a disabled button too: off, it leaves the column.
	var focusable: bool = not _close_button.disabled
	if focusable != (_close_button.focus_mode != Control.FOCUS_NONE):
		_close_button.focus_mode = Control.FOCUS_ALL if focusable else Control.FOCUS_NONE
		_link_main_focus()
	_close_hint.text = String(state["hint"])
	_close_hint.visible = not _close_hint.text.is_empty()
	var warning: String = DayClose.exit_warning(day_cycle)
	_warning.text = warning
	_warning.visible = not warning.is_empty()
	# A close asked for when the day can no longer close (it reached 20:00 meanwhile) is dropped.
	if _asking == &"close" and _close_button.disabled:
		_ask(&"")
	_main.visible = _asking == &""
	_confirm.visible = _asking != &""


func _process(_delta: float) -> void:
	if not visible:
		return
	refresh()
	# The ping wheel captures the mouse when released under a soft menu: the cursor stays free (and
	# so the player takes no input) while the menu is up.
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- What the tests and the gamepad read ---------------------------------------------------------

func is_real() -> bool:
	return _real


## &"" with no confirmation up, &"close" for the day's, or the exit kind (EXIT_MENU / EXIT_QUIT).
func asking() -> StringName:
	return _asking


func continue_button() -> Button:
	return _continue_button


func close_day_button() -> Button:
	return _close_button


func close_day_hint() -> String:
	return _close_hint.text if _close_hint.visible else ""


func exit_warning_text() -> String:
	return _warning.text if _warning.visible else ""


func menu_button() -> Button:
	return _menu_button


func quit_button() -> Button:
	return _quit_button


func confirm_text() -> String:
	return _confirm_text.text if _confirm.visible else ""


func confirm_yes_button() -> Button:
	return _confirm_yes


func confirm_no_button() -> Button:
	return _confirm_no


func title_text() -> String:
	return _title.text


# --- Actions -------------------------------------------------------------------------------------

func _on_close_day() -> void:
	if not _close_button.disabled:
		_ask(&"close")


func _on_exit(kind: StringName) -> void:
	if DayClose.exit_loses_day(day_cycle):
		_ask(kind)
	else:
		_leave(kind)


func _on_confirm_yes() -> void:
	var kind: StringName = _asking
	_ask(&"")
	if kind == &"close":
		day_closed.emit(DayClose.close(day_cycle))
	elif kind != &"":
		_leave(kind)


func _ask(kind: StringName) -> void:
	_asking = kind
	if kind == &"close":
		_confirm_text.text = String(DayClose.button(day_cycle)["confirm"])
		_confirm_yes.text = tr(DayClose.BUTTON_KEY)
	elif kind != &"":
		_confirm_text.text = DayClose.exit_warning(day_cycle)
		_confirm_yes.text = tr(EXIT_ANYWAY_KEY)
	_main.visible = kind == &""
	_confirm.visible = kind != &""
	if kind == &"":
		_continue_button.grab_focus.call_deferred()
	else:
		# The safe answer has the focus: a stray A press goes back, it does not lose the day.
		_confirm_no.grab_focus.call_deferred()


func _leave(kind: StringName) -> void:
	if exit_action.is_valid():
		exit_action.call(kind)
		return
	var tree: SceneTree = get_tree()
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if kind == EXIT_QUIT:
		tree.quit()
		return
	# The company world marks its day interrupted as it closes (CompanyRoot): nothing to save here.
	var net: Node = get_node_or_null(^"/root/NetworkManager")
	if net != null and bool(net.call(&"is_online")):
		# Offline, a client's mirror would answer as the host until the scene goes (as
		# CompanyRoot._on_host_lost): the world stops first.
		if tree.current_scene != null:
			tree.current_scene.process_mode = Node.PROCESS_MODE_DISABLED
		net.call(&"leave_session")
	tree.change_scene_to_file.call_deferred(MAIN_MENU_SCENE)


# --- Building ------------------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(520, 0), 22)
	column.add_theme_constant_override("separation", 8)
	UiTheme.tag(column, tr("HUD_KICKER_PAUSE"))
	_title = UiTheme.title(column, "", 40)
	_body = UiTheme.label(column, "", 16, UiTheme.MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_main = VBoxContainer.new()
	_main.name = "Main"
	_main.add_theme_constant_override("separation", 8)
	column.add_child(_main)
	_continue_button = UiTheme.button(_main, tr("HUD_CONTINUE"), true)
	_continue_button.name = "Continue"
	_continue_button.pressed.connect(func() -> void: resume_requested.emit())
	_close_button = UiTheme.button(_main, tr(DayClose.BUTTON_KEY), false,
			Vector2(0, UiTheme.BUTTON_HEIGHT), UiTheme.YELLOW)
	_close_button.name = "CloseDay"
	_close_button.pressed.connect(_on_close_day)
	_close_hint = UiTheme.label(_main, "", 14, UiTheme.MUTED)
	_close_hint.name = "CloseDayHint"
	_options_button = UiTheme.button(_main, tr("UI_OPTIONS"))
	_options_button.name = "Options"
	_options_button.pressed.connect(_open_options)
	_warning = UiTheme.label(_main, "", 15, UiTheme.RED)
	_warning.name = "ExitWarning"
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_button = UiTheme.button(_main, tr("HUD_BACK_TO_MENU"))
	_menu_button.name = "BackToMenu"
	_menu_button.pressed.connect(_on_exit.bind(EXIT_MENU))
	_quit_button = UiTheme.button(_main, tr("UI_MENU_QUIT"))
	_quit_button.name = "Quit"
	_quit_button.pressed.connect(_on_exit.bind(EXIT_QUIT))

	_confirm = VBoxContainer.new()
	_confirm.name = "Confirm"
	_confirm.add_theme_constant_override("separation", 8)
	column.add_child(_confirm)
	_confirm_text = UiTheme.label(_confirm, "", 17)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_yes = UiTheme.button(_confirm, "", false, Vector2(0, UiTheme.BUTTON_HEIGHT), UiTheme.YELLOW)
	_confirm_yes.name = "Yes"
	_confirm_yes.pressed.connect(_on_confirm_yes)
	_confirm_no = UiTheme.button(_confirm, tr("UI_BACK"), true)
	_confirm_no.name = "No"
	_confirm_no.pressed.connect(_ask.bind(&""))
	_confirm.hide()

	_link_main_focus()
	_link_focus([_confirm_no, _confirm_yes])


func _link_main_focus() -> void:
	var chain: Array[Control] = [_continue_button]
	if _close_button.focus_mode != Control.FOCUS_NONE:
		chain.append(_close_button)
	chain.append_array([_options_button, _menu_button, _quit_button])
	_link_focus(chain)


func _open_options() -> void:
	if _options == null:
		_options = (load(OPTIONS_PANEL_PATH) as GDScript).new() as Control
		_options.name = "OptionsPanel"
		add_child(_options)
		_options.connect(&"closed", func() -> void: _options_button.grab_focus.call_deferred())
	_options.call(&"open")


## One focus column; a disabled button leaves it through its focus_mode (refresh()).
func _link_focus(chain: Array[Control]) -> void:
	for i: int in chain.size():
		var node: Control = chain[i]
		node.focus_neighbor_top = node.get_path_to(chain[maxi(i - 1, 0)])
		node.focus_neighbor_bottom = node.get_path_to(chain[mini(i + 1, chain.size() - 1)])
		node.focus_neighbor_left = node.get_path_to(node)
		node.focus_neighbor_right = node.get_path_to(node)
