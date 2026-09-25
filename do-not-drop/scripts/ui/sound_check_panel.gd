extends Control
## "Sonidos del juego", from the options screen: every sound in the game,
## one row each, to track down the one that grates (playtest 2026-09-25).
## Each row says whether it's playing right now, and mutes it or plays it
## alone ("Solo"). Mutes last until the game is closed; SoundAudit
## (presentation/sound_audit.gd) does the muting.
##
## Opened over a paused game, the sounds keep playing while this is open,
## so standing where the noise is, a mute is heard the moment it's toggled.

signal closed

const Audit = preload("res://scripts/presentation/sound_audit.gd")
const REFRESH_SECONDS: float = 0.4

var _list: VBoxContainer
var _empty_note: Label
var _rows: Dictionary = {}
var _refresh_wait: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()


func _build() -> void:
	UiTheme.apply(self)
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(720, 0), 26)
	column.add_theme_constant_override("separation", 12)
	UiTheme.title(column, "Sonidos del juego", 32)
	var help: Label = UiTheme.label(column, "Silenciá uno por uno hasta que deje de sonar lo que molesta. Mientras esta pantalla está abierta el juego sigue sonando aunque esté en pausa. Lo que silencies queda así hasta cerrar el juego.", 15, UiTheme.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 660

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_empty_note = UiTheme.label(_list, "No hay sonidos cargados. Abrí esta pantalla desde la pausa, jugando, parado donde se escucha el ruido.", 15, UiTheme.MUTED)
	_empty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back: Button = UiTheme.button(actions, "Volver", true)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(close)
	UiTheme.button(actions, "Silenciar todos", false).pressed.connect(func() -> void:
		Audit.mute_all(get_tree())
		_refresh())
	UiTheme.button(actions, "Activar todos", false).pressed.connect(func() -> void:
		Audit.unmute_all(get_tree())
		_refresh())


func open() -> void:
	Audit.play_through_pause(get_tree(), true)
	_refresh()
	show()
	var first: Control = _first_focusable()
	if first != null:
		first.grab_focus()


func close() -> void:
	Audit.play_through_pause(get_tree(), false)
	hide()
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_wait -= delta
	if _refresh_wait <= 0.0:
		_refresh_wait = REFRESH_SECONDS
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


## One row per sound found; rows update in place (the list is rebuilt only
## when sounds appear or go, so focus isn't lost every refresh).
func _refresh() -> void:
	# Players that appeared since opening keep playing through the pause too.
	Audit.play_through_pause(get_tree(), true)
	var groups: Array[Dictionary] = Audit.groups(get_tree())
	var keys: Array = groups.map(func(group: Dictionary) -> String: return group.key)
	if keys != _rows.keys():
		_rebuild(groups)
	_empty_note.visible = groups.is_empty()
	for group: Dictionary in groups:
		var row: Dictionary = _rows[group.key]
		var muted: bool = Audit.is_muted(group.key)
		var state: Label = row.state
		if muted:
			state.text = "silenciado"
			state.add_theme_color_override("font_color", UiTheme.MUTED)
		elif int(group.playing) > 0:
			state.text = "SONANDO" if int(group.playing) == 1 else "SONANDO ×%d" % int(group.playing)
			state.add_theme_color_override("font_color", UiTheme.RED)
		else:
			state.text = "en espera"
			state.add_theme_color_override("font_color", UiTheme.MUTED)
		(row.mute as CheckBox).set_pressed_no_signal(muted)


func _rebuild(groups: Array[Dictionary]) -> void:
	for key: String in _rows:
		(_rows[key].root as Node).queue_free()
	_rows.clear()
	for group: Dictionary in groups:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		_list.add_child(line)
		var state: Label = UiTheme.label(line, "", 13, UiTheme.MUTED)
		state.custom_minimum_size.x = 110
		var name_label: Label = UiTheme.label(line, String(group.label), 16, UiTheme.INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = "Bus: %s" % group.bus
		UiTheme.label(line, String(group.bus), 12, UiTheme.MUTED).custom_minimum_size.x = 70
		var mute: CheckBox = UiTheme.check_box(line, "Silenciar", false)
		mute.toggled.connect(func(pressed: bool, key: String = group.key) -> void:
			Audit.set_muted(get_tree(), key, pressed)
			_refresh())
		var solo: Button = UiTheme.button(line, "Solo", false, Vector2(80, 36))
		solo.pressed.connect(func(key: String = group.key) -> void:
			Audit.solo(get_tree(), key)
			_refresh())
		_rows[group.key] = {"root": line, "state": state, "mute": mute}


func _first_focusable() -> Control:
	for key: String in _rows:
		return _rows[key].mute as Control
	return null
