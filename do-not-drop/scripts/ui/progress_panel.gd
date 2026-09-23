extends Control
class_name ProgressPanel

signal closed
var _summary: Label
var _list: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()
	UnlockManager.progress_changed.connect(_refresh)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(560, 0), 28)
	UiTheme.title(column, "Progreso", 38)
	UiTheme.tag(column, "PERFIL LOCAL", UiTheme.SKY, 1.0, 14)
	_summary = UiTheme.label(column, "", 17, UiTheme.MUTED)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	column.add_child(_list)
	var back := UiTheme.button(column, "Volver", true)
	back.pressed.connect(close)

func open() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh()
	show()

func close() -> void:
	hide()
	closed.emit()

func _refresh() -> void:
	if _summary == null:
		return
	var summary := UnlockManager.progress_summary()
	_summary.text = "%d entregas exitosas  ·  %d puntos acumulados  ·  %d partidas" % [summary["deliveries"], summary["score"], summary["runs"]]
	for child: Node in _list.get_children():
		child.queue_free()
	for unlock_id: StringName in UnlockManager.UNLOCKS:
		var rule := UnlockManager.requirements(unlock_id)
		var got := UnlockManager.is_unlocked(unlock_id)
		var line := UiTheme.label(_list, "%s  %s\n%d entregas + %d pts" % ["✓" if got else "○", rule["title"], rule["deliveries"], rule["score"]], 17, UiTheme.MINT if got else UiTheme.MUTED)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
