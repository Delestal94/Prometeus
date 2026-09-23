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

var _volume_slider: HSlider
var _sensitivity_slider: HSlider
var _music_slider: HSlider
var _effects_slider: HSlider
var _voice_slider: HSlider
var _fov_slider: HSlider
var _shake_slider: HSlider
var _hud_scale_slider: HSlider
var _invert_check: CheckBox
var _fullscreen_check: CheckBox
var _controls_label: Label
var _binding_buttons: Dictionary = {}
var _listening_action: StringName = &""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()
	GameSettings.input_device_changed.connect(_on_input_device_changed)


func _build() -> void:
	UiTheme.apply(self)
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column: VBoxContainer = UiTheme.panel(center, Vector2(480, 0), 30)
	column.add_theme_constant_override("separation", 16)
	UiTheme.title(column, "Opciones", 36)

	_volume_slider = UiTheme.slider_row(column, "Volumen general", 0.0, 1.0, 0.05, GameSettings.master_volume)
	_volume_slider.value_changed.connect(func(value: float) -> void: GameSettings.master_volume = value)

	_music_slider = UiTheme.slider_row(column, "Volumen de la música", 0.0, 1.0, 0.05, GameSettings.music_volume)
	_music_slider.value_changed.connect(func(value: float) -> void: GameSettings.music_volume = value)
	_effects_slider = UiTheme.slider_row(column, "Volumen de efectos", 0.0, 1.0, 0.05, GameSettings.effects_volume)
	_effects_slider.value_changed.connect(func(value: float) -> void: GameSettings.effects_volume = value)
	_voice_slider = UiTheme.slider_row(column, "Volumen de voces/pings", 0.0, 1.0, 0.05, GameSettings.voice_volume)
	_voice_slider.value_changed.connect(func(value: float) -> void: GameSettings.voice_volume = value)
	_fov_slider = UiTheme.slider_row(column, "Campo de visión", 65.0, 100.0, 1.0, GameSettings.preferred_fov)
	_fov_slider.value_changed.connect(func(value: float) -> void: GameSettings.preferred_fov = value)
	_shake_slider = UiTheme.slider_row(column, "Sacudida de cámara", 0.0, 1.0, 0.05, GameSettings.camera_shake_scale)
	_shake_slider.value_changed.connect(func(value: float) -> void: GameSettings.camera_shake_scale = value)

	_sensitivity_slider = UiTheme.slider_row(column, "Sensibilidad de la mirada", 0.2, 3.0, 0.05, GameSettings.look_sensitivity)
	_sensitivity_slider.value_changed.connect(func(value: float) -> void: GameSettings.look_sensitivity = value)

	# Live: opened from the pause menu, the HUD behind the dim resizes as the
	# slider moves, so there's no guessing what 80% looks like.
	_hud_scale_slider = UiTheme.slider_row(column, "Tamaño del HUD", GameSettings.HUD_SCALE_MIN, GameSettings.HUD_SCALE_MAX, 0.05, GameSettings.hud_scale, true)
	_hud_scale_slider.value_changed.connect(func(value: float) -> void: GameSettings.hud_scale = value)

	_invert_check = UiTheme.check_box(column, "Invertir eje Y", GameSettings.invert_look_y)
	_invert_check.toggled.connect(func(pressed: bool) -> void: GameSettings.invert_look_y = pressed)

	_fullscreen_check = UiTheme.check_box(column, "Pantalla completa  (F11)", GameSettings.fullscreen)
	_fullscreen_check.toggled.connect(func(pressed: bool) -> void: GameSettings.fullscreen = pressed)

	UiTheme.tag(column, "CONTROLES", UiTheme.MINT, -1.5, 15)
	_controls_label = UiTheme.label(column, "", 14, UiTheme.MUTED)
	_refresh_controls()
	for pair: Array in [[&"interact", "Interactuar"], [&"ui_ping", "Ping"], [&"drive_horn", "Bocina"]]:
		var row := HBoxContainer.new()
		column.add_child(row)
		UiTheme.label(row, String(pair[1]), 16, UiTheme.PAPER).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bind: Button = UiTheme.button(row, GameSettings.binding_label(pair[0]), false, Vector2(150, 38))
		bind.pressed.connect(func(action: StringName = pair[0]) -> void: _listen_for_key(action))
		_binding_buttons[pair[0]] = bind

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back: Button = UiTheme.button(actions, "Volver", true)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(close)
	UiTheme.button(actions, "Restablecer", false).pressed.connect(_reset)


## Mirrors the actual input map (project.godot), per device, so the list
## never promises a gamepad button to someone holding a mouse.
func _refresh_controls() -> void:
	if _controls_label == null:
		return
	if GameSettings.using_gamepad:
		_controls_label.text = "A pie: stick izq. caminar  ·  stick der. mirar  ·  A interactuar  ·  X saltar\nManejando: RT acelerar  ·  LT frenar  ·  X freno de mano  ·  B bocina  ·  A bajarte\nPasajero: RT (mantener) cuidar el paquete  ·  stick izq. secuencias\nLB celular  ·  RB sacar foto  ·  D-pad arriba ping  ·  Clic stick der. centrar vista\nStart pausa  ·  mantener Y reiniciar"
	else:
		_controls_label.text = "A pie: WASD caminar  ·  Mouse mirar  ·  E interactuar  ·  Espacio saltar  ·  Q soltar\nManejando: W/S acelerar y frenar  ·  A/D girar  ·  Espacio freno de mano  ·  H bocina  ·  E bajarte\nPasajero: Click izq. (mantener) cuidar el paquete  ·  WASD secuencias\nF celular  ·  Click sacar foto  ·  Click rueda ping  ·  C centrar vista\nEsc pausa  ·  mantener R reiniciar  ·  F11 pantalla completa"


func _on_input_device_changed(_gamepad: bool) -> void:
	_refresh_controls()


func _listen_for_key(action: StringName) -> void:
	_listening_action = action
	(_binding_buttons[action] as Button).text = "Presioná una tecla…"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not _listening_action.is_empty():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode != KEY_ESCAPE:
			GameSettings.bind_key(_listening_action, event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
			(_binding_buttons[_listening_action] as Button).text = GameSettings.binding_label(_listening_action)
			_listening_action = &""
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _reset() -> void:
	GameSettings.reset_to_defaults()
	_sync_from_settings()


## Pulls every control back in line with GameSettings -- after a reset, or
## when F11 flipped fullscreen behind the panel's back.
func _sync_from_settings() -> void:
	_volume_slider.set_value_no_signal(GameSettings.master_volume)
	_volume_slider.value_changed.emit(GameSettings.master_volume)
	_music_slider.set_value_no_signal(GameSettings.music_volume)
	_music_slider.value_changed.emit(GameSettings.music_volume)
	_effects_slider.set_value_no_signal(GameSettings.effects_volume)
	_effects_slider.value_changed.emit(GameSettings.effects_volume)
	_voice_slider.set_value_no_signal(GameSettings.voice_volume)
	_voice_slider.value_changed.emit(GameSettings.voice_volume)
	_fov_slider.set_value_no_signal(GameSettings.preferred_fov)
	_fov_slider.value_changed.emit(GameSettings.preferred_fov)
	_shake_slider.set_value_no_signal(GameSettings.camera_shake_scale)
	_shake_slider.value_changed.emit(GameSettings.camera_shake_scale)
	_sensitivity_slider.set_value_no_signal(GameSettings.look_sensitivity)
	_sensitivity_slider.value_changed.emit(GameSettings.look_sensitivity)
	_hud_scale_slider.set_value_no_signal(GameSettings.hud_scale)
	_hud_scale_slider.value_changed.emit(GameSettings.hud_scale)
	_invert_check.set_pressed_no_signal(GameSettings.invert_look_y)
	_fullscreen_check.set_pressed_no_signal(GameSettings.fullscreen)
	for action: StringName in _binding_buttons:
		(_binding_buttons[action] as Button).text = GameSettings.binding_label(action)


## Shown over a paused game as often as over the menu, so it has to keep
## working while the tree is paused.
func open() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_from_settings()
	_refresh_controls()
	show()
	# The first control, not the first Button: CheckBox counts as a Button,
	# so that used to land a gamepad player below both sliders.
	_volume_slider.grab_focus()


func close() -> void:
	hide()
	closed.emit()

