extends Control
class_name TutorialPanel

signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(620, 0), 28)
	UiTheme.title(column, tr("UI_HOW_TO_PLAY"), 38)
	UiTheme.tag(column, tr("UI_TUT_TAG"), UiTheme.YELLOW, -1.0, 14)
	var text := UiTheme.label(column, tr("UI_TUT_BODY"), 17, UiTheme.INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var back := UiTheme.button(column, tr("UI_TUT_GOT_IT"), true)
	back.pressed.connect(close)

func open() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	show()

func close() -> void:
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
