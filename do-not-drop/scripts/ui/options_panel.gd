extends Control
class_name OptionsPanel
## The options screen, built once and shown from both places a player would
## look for it: the main menu and the pause overlay.
##
## Every control writes straight into GameSettings, which applies and saves
## itself -- there is no "apply" button and no cancel, because a volume
## slider you have to confirm is a volume slider you can't hear while you
## drag it.

signal closed

var _sensitivity_slider: HSlider


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.035, 0.09, 0.11, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column: VBoxContainer = UiTheme.panel(center, Vector2(460, 0), 30)
	column.add_theme_constant_override("separation", 16)
	UiTheme.label(column, "OPCIONES", 28, UiTheme.PAPER)

	var volume: HSlider = UiTheme.slider_row(column, "Volumen general", 0.0, 1.0, 0.05, GameSettings.master_volume)
	volume.value_changed.connect(func(value: float) -> void: GameSettings.master_volume = value)

	_sensitivity_slider = UiTheme.slider_row(column, "Sensibilidad de la mirada", 0.2, 3.0, 0.05, GameSettings.look_sensitivity)
	_sensitivity_slider.value_changed.connect(func(value: float) -> void: GameSettings.look_sensitivity = value)

	var invert := CheckBox.new()
	invert.text = "Invertir eje Y"
	invert.button_pressed = GameSettings.invert_look_y
	invert.add_theme_color_override("font_color", UiTheme.PAPER)
	invert.add_theme_color_override("font_hover_color", UiTheme.PAPER)
	invert.add_theme_color_override("font_pressed_color", UiTheme.PAPER)
	invert.toggled.connect(func(pressed: bool) -> void: GameSettings.invert_look_y = pressed)
	column.add_child(invert)

	var fullscreen := CheckBox.new()
	fullscreen.text = "Pantalla completa"
	fullscreen.button_pressed = GameSettings.fullscreen
	fullscreen.add_theme_color_override("font_color", UiTheme.PAPER)
	fullscreen.add_theme_color_override("font_hover_color", UiTheme.PAPER)
	fullscreen.add_theme_color_override("font_pressed_color", UiTheme.PAPER)
	fullscreen.toggled.connect(func(pressed: bool) -> void: GameSettings.fullscreen = pressed)
	column.add_child(fullscreen)

	UiTheme.label(column, "Controles: WASD caminar  ·  Mouse mirar  ·  E interactuar  ·  Q soltar\nF celular  ·  Espacio saltar / freno de mano  ·  H bocina  ·  Esc pausa", 13, UiTheme.MUTED)

	UiTheme.button(column, "Volver", true).pressed.connect(close)


## Shown over a paused game as often as over the menu, so it has to keep
## working while the tree is paused.
func open() -> void:
	show()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child: Node in _buttons():
		child.grab_focus()
		break


func close() -> void:
	hide()
	closed.emit()


func _buttons() -> Array[Node]:
	return find_children("", "Button", true, false)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_pause"):
		close()
		get_viewport().set_input_as_handled()
