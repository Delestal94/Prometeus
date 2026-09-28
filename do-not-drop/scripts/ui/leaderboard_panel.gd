class_name LeaderboardPanel
extends Control

signal closed
var _close_button: Button
var _entries: VBoxContainer
var _delivery_button: Button
var _endless_button: Button
var _mode: StringName = &"delivery"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func open() -> void:
	_refresh()
	show()
	_delivery_button.grab_focus.call_deferred()


func close() -> void:
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	UiTheme.apply(self)
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.06, 0.08, 0.92)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(680, 520), 26)
	column.add_theme_constant_override("separation", 10)
	UiTheme.title(column, tr("UI_LEAD_TITLE"), 36)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	_delivery_button = UiTheme.button(tabs, "Entrega", false, Vector2(170, 44))
	_delivery_button.pressed.connect(_set_mode.bind(&"delivery"))
	_endless_button = UiTheme.button(tabs, "Endless", false, Vector2(170, 44))
	_endless_button.pressed.connect(_set_mode.bind(&"endless"))
	_entries = VBoxContainer.new()
	_entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entries.add_theme_constant_override("separation", 8)
	column.add_child(_entries)
	_close_button = UiTheme.button(column, tr("UI_BACK"), false, Vector2(0, 48))
	_close_button.pressed.connect(close)
	_refresh_entries()


func _refresh() -> void:
	if _entries != null:
		_refresh_entries()


func _set_mode(mode: StringName) -> void:
	_mode = mode
	_refresh_entries()
	(_delivery_button if mode == &"delivery" else _endless_button).grab_focus()


func _refresh_entries() -> void:
	for child: Node in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	_delivery_button.disabled = false
	_endless_button.disabled = false
	_delivery_button.text = "●  ENTREGA" if _mode == &"delivery" else "Entrega"
	_endless_button.text = "●  ENDLESS" if _mode == &"endless" else "Endless"
	var rank: int = 1
	for entry: Dictionary in RunManager.leaderboard:
		if StringName(entry.get("mode", &"delivery")) != _mode:
			continue
		var crew: int = maxi(int(entry.get("crew_size", 1)), 1)
		var crew_text: String = "1 jugador" if crew == 1 else "%d jugadores" % crew
		var line := HBoxContainer.new()
		line.name = "Rank%d" % rank
		line.tooltip_text = tr("UI_LEAD_ROW") % [rank, int(entry.get("score", 0)), String(entry.get("mode", "delivery")), String(entry.get("date", ""))]
		line.add_theme_constant_override("separation", 12)
		_entries.add_child(line)
		var rank_label: Label = UiTheme.chip(line, "%d" % rank, UiTheme.YELLOW, 18)
		rank_label.get_parent().custom_minimum_size.x = 44
		var score: Label = UiTheme.label(line, "%d pts" % int(entry.get("score", 0)), 21, UiTheme.INK, true)
		score.custom_minimum_size.x = 155
		var crew_label: Label = UiTheme.label(line, crew_text, 16, UiTheme.MUTED)
		crew_label.custom_minimum_size.x = 130
		var date: Label = UiTheme.label(line, format_date(String(entry.get("date", ""))), 16, UiTheme.MUTED)
		date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rank += 1
	if rank == 1:
		var empty_text: String = tr("UI_LEAD_EMPTY") if _mode == &"delivery" else "Todavía no hay partidas Endless registradas."
		UiTheme.label(_entries, empty_text, 18, UiTheme.MUTED)


static func format_date(iso_date: String) -> String:
	var parts: PackedStringArray = iso_date.split("-")
	if parts.size() != 3:
		return iso_date if not iso_date.is_empty() else "Sin fecha"
	return "%s/%s/%s" % [parts[2], parts[1], parts[0]]
