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
var _impact_effects_check: CheckBox
var _hud_scale_slider: HSlider
var _control_help_option: OptionButton
var _colorblind_check: CheckBox
var _menu_text_option: OptionButton
var _sound_subtitles_check: CheckBox
var _invert_check: CheckBox
var _fullscreen_check: CheckBox
var _quality_slider: HSlider
var _controls_label: Label
var _language_option: OptionButton
var _binding_buttons: Dictionary = {}
## Every sound in the game, to mute one by one (sound_check_panel.gd).
var _sound_check: Control
var _listening_action: StringName = &""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()
	GameSettings.input_device_changed.connect(_on_input_device_changed)
	GameSettings.language_changed.connect(_on_language_changed)


func _build() -> void:
	UiTheme.apply(self)
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Options now exceed 720p once accessibility controls are included. Keep
	# every row and the action buttons reachable instead of clipping the lower
	# half of the panel on the minimum supported window size.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 18)
	scroll.add_child(padding)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	padding.add_child(center)

	var column: VBoxContainer = UiTheme.panel(center, Vector2(480, 0), 30)
	column.add_theme_constant_override("separation", 16)
	UiTheme.title(column, tr("UI_OPTIONS"), 36)
	var language_row := HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 12)
	column.add_child(language_row)
	var language_label: Label = UiTheme.label(language_row, tr("UI_OPT_LANGUAGE"), 16, UiTheme.PAPER)
	language_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_language_option = OptionButton.new()
	_language_option.name = "LanguageOption"
	_language_option.add_item(tr("UI_LANGUAGE_SPANISH"))
	_language_option.add_item(tr("UI_LANGUAGE_ENGLISH"))
	_language_option.select(GameSettings.SUPPORTED_LANGUAGES.find(GameSettings.language))
	_language_option.custom_minimum_size = Vector2(170, 40)
	language_row.add_child(_language_option)
	UiTheme.register_font_size(_language_option, 16)
	_language_option.item_selected.connect(func(index: int) -> void:
		GameSettings.set_language(GameSettings.SUPPORTED_LANGUAGES[index]))

	_volume_slider = UiTheme.slider_row(column, tr("UI_OPT_MASTER_VOLUME"), 0.0, 1.0, 0.05, GameSettings.master_volume)
	_volume_slider.value_changed.connect(func(value: float) -> void: GameSettings.master_volume = value)

	_music_slider = UiTheme.slider_row(column, tr("UI_OPT_MUSIC_VOLUME"), 0.0, 1.0, 0.05, GameSettings.music_volume)
	_music_slider.value_changed.connect(func(value: float) -> void: GameSettings.music_volume = value)
	_effects_slider = UiTheme.slider_row(column, tr("UI_OPT_EFFECTS_VOLUME"), 0.0, 1.0, 0.05, GameSettings.effects_volume)
	_effects_slider.value_changed.connect(func(value: float) -> void: GameSettings.effects_volume = value)
	_voice_slider = UiTheme.slider_row(column, tr("UI_OPT_VOICE_VOLUME"), 0.0, 1.0, 0.05, GameSettings.voice_volume)
	_voice_slider.value_changed.connect(func(value: float) -> void: GameSettings.voice_volume = value)
	var sounds: Button = UiTheme.button(column, tr("UI_OPT_SOUND_CHECK"), false, Vector2(0, 40))
	sounds.pressed.connect(_open_sound_check)
	_fov_slider = UiTheme.slider_row(column, tr("UI_OPT_FOV"), 65.0, 100.0, 1.0, GameSettings.preferred_fov)
	_fov_slider.value_changed.connect(func(value: float) -> void: GameSettings.preferred_fov = value)
	_shake_slider = UiTheme.slider_row(column, tr("UI_OPT_SHAKE"), 0.0, 1.0, 0.05, GameSettings.camera_shake_scale)
	_shake_slider.value_changed.connect(func(value: float) -> void: GameSettings.camera_shake_scale = value)
	_impact_effects_check = UiTheme.check_box(column, tr("UI_OPT_IMPACT_EFFECTS"), GameSettings.impact_effects)
	_impact_effects_check.toggled.connect(func(pressed: bool) -> void: GameSettings.impact_effects = pressed)

	_sensitivity_slider = UiTheme.slider_row(column, tr("UI_OPT_SENSITIVITY"), 0.2, 3.0, 0.05, GameSettings.look_sensitivity)
	_sensitivity_slider.value_changed.connect(func(value: float) -> void: GameSettings.look_sensitivity = value)

	# Live: opened from the pause menu, the HUD behind the dim resizes as the
	# slider moves, so there's no guessing what 80% looks like.
	_hud_scale_slider = UiTheme.slider_row(column, tr("UI_OPT_HUD_SIZE"), GameSettings.HUD_SCALE_MIN, GameSettings.HUD_SCALE_MAX, 0.05, GameSettings.hud_scale, true)
	_hud_scale_slider.value_changed.connect(func(value: float) -> void: GameSettings.hud_scale = value)
	var help_row := HBoxContainer.new()
	help_row.add_theme_constant_override("separation", 12)
	column.add_child(help_row)
	UiTheme.label(help_row, tr("UI_OPT_CONTROL_HELP"), 16, UiTheme.PAPER).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_control_help_option = OptionButton.new()
	_control_help_option.add_item(tr("UI_OPT_HELP_ALWAYS"), GameSettings.ControlHelp.ALWAYS)
	_control_help_option.add_item(tr("UI_OPT_HELP_BEGINNING"), GameSettings.ControlHelp.BEGINNING)
	_control_help_option.add_item(tr("UI_OPT_HELP_NEVER"), GameSettings.ControlHelp.NEVER)
	_control_help_option.select(GameSettings.control_help_mode)
	_control_help_option.custom_minimum_size = Vector2(170, 40)
	help_row.add_child(_control_help_option)
	UiTheme.register_font_size(_control_help_option, 16)
	_control_help_option.item_selected.connect(func(index: int) -> void:
		GameSettings.control_help_mode = _control_help_option.get_item_id(index))

	_colorblind_check = UiTheme.check_box(column, tr("UI_OPT_COLORBLIND"), GameSettings.colorblind_palette)
	_colorblind_check.toggled.connect(func(pressed: bool) -> void: GameSettings.colorblind_palette = pressed)

	var text_row := HBoxContainer.new()
	text_row.add_theme_constant_override("separation", 12)
	column.add_child(text_row)
	UiTheme.label(text_row, tr("UI_OPT_MENU_TEXT_SIZE"), 16, UiTheme.PAPER).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_text_option = OptionButton.new()
	_menu_text_option.add_item("100 %", 100)
	_menu_text_option.add_item("125 %", 125)
	_menu_text_option.add_item("150 %", 150)
	_menu_text_option.select(_menu_text_scale_index())
	_menu_text_option.custom_minimum_size = Vector2(130, 40)
	text_row.add_child(_menu_text_option)
	UiTheme.register_font_size(_menu_text_option, 16)
	_menu_text_option.item_selected.connect(func(index: int) -> void:
		GameSettings.menu_text_scale = float(_menu_text_option.get_item_id(index)) / 100.0)

	_sound_subtitles_check = UiTheme.check_box(column, tr("UI_OPT_SOUND_SUBTITLES"), GameSettings.sound_subtitles)
	_sound_subtitles_check.toggled.connect(func(pressed: bool) -> void: GameSettings.sound_subtitles = pressed)

	_invert_check = UiTheme.check_box(column, tr("UI_OPT_INVERT_Y"), GameSettings.invert_look_y)
	_invert_check.toggled.connect(func(pressed: bool) -> void: GameSettings.invert_look_y = pressed)

	_fullscreen_check = UiTheme.check_box(column, tr("UI_OPT_FULLSCREEN"), GameSettings.fullscreen)
	_fullscreen_check.toggled.connect(func(pressed: bool) -> void: GameSettings.fullscreen = pressed)

	# Graphics quality (world_quality.gd, tareas de Nacho N-205): the readout
	# names the level instead of showing 0-2.
	_quality_slider = UiTheme.slider_row(column, tr("UI_OPT_QUALITY"), WorldQuality.Level.LOW, WorldQuality.Level.HIGH, 1.0, GameSettings.graphics_quality)
	var quality_readout := (_quality_slider.get_parent().get_child(0) as HBoxContainer).get_child(1) as Label
	var name_quality := func(value: float) -> void: quality_readout.text = WorldQuality.NAMES[int(value)]
	name_quality.call(_quality_slider.value)
	_quality_slider.value_changed.connect(func(value: float) -> void:
		GameSettings.graphics_quality = int(value)
		name_quality.call(value))

	UiTheme.tag(column, tr("UI_OPT_CONTROLS_TITLE"), UiTheme.MINT, -1.5, 15)
	_controls_label = UiTheme.label(column, "", 14, UiTheme.MUTED)
	_refresh_controls()
	for pair: Array in [[&"interact", tr("UI_OPT_BIND_INTERACT")], [&"ui_ping", tr("UI_OPT_BIND_PING")], [&"drive_horn", tr("UI_OPT_BIND_HORN")], [&"look_back", tr("UI_OPT_BIND_LOOK_BACK")], [&"use_card", tr("UI_OPT_BIND_USE_CARD")]]:
		var row := HBoxContainer.new()
		column.add_child(row)
		UiTheme.label(row, String(pair[1]), 16, UiTheme.INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bind: Button = UiTheme.button(row, GameSettings.binding_label(pair[0]), false, Vector2(150, 38))
		bind.pressed.connect(func(action: StringName = pair[0]) -> void: _listen_for_key(action))
		_binding_buttons[pair[0]] = bind

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back: Button = UiTheme.button(actions, tr("UI_BACK"), true)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(close)
	UiTheme.button(actions, tr("UI_OPT_RESET"), false).pressed.connect(_reset)


func _open_sound_check() -> void:
	if _sound_check == null:
		_sound_check = preload("res://scripts/ui/sound_check_panel.gd").new()
		_sound_check.name = "SoundCheck"
		add_child(_sound_check)
		_sound_check.connect(&"closed", func() -> void: _volume_slider.grab_focus())
	_sound_check.call(&"open")


## Mirrors the actual input map (project.godot), per device, so the list
## never promises a gamepad button to someone holding a mouse.
func _refresh_controls() -> void:
	if _controls_label == null:
		return
	if GameSettings.using_gamepad:
		_controls_label.text = tr("UI_OPT_CONTROLS_PAD")
	else:
		_controls_label.text = tr("UI_OPT_CONTROLS_KEYS")


func _on_input_device_changed(_gamepad: bool) -> void:
	_refresh_controls()


func _on_language_changed(_locale: String) -> void:
	_rebuild_for_language.call_deferred()


func _rebuild_for_language() -> void:
	var was_visible: bool = visible
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_binding_buttons.clear()
	_sound_check = null
	_listening_action = &""
	_build()
	visible = was_visible
	if was_visible:
		_language_option.grab_focus.call_deferred()


func _listen_for_key(action: StringName) -> void:
	_listening_action = action
	(_binding_buttons[action] as Button).text = tr("UI_OPT_PRESS_KEY")


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
	_impact_effects_check.set_pressed_no_signal(GameSettings.impact_effects)
	_sensitivity_slider.set_value_no_signal(GameSettings.look_sensitivity)
	_sensitivity_slider.value_changed.emit(GameSettings.look_sensitivity)
	_hud_scale_slider.set_value_no_signal(GameSettings.hud_scale)
	_hud_scale_slider.value_changed.emit(GameSettings.hud_scale)
	_control_help_option.select(GameSettings.control_help_mode)
	_colorblind_check.set_pressed_no_signal(GameSettings.colorblind_palette)
	_menu_text_option.select(_menu_text_scale_index())
	_sound_subtitles_check.set_pressed_no_signal(GameSettings.sound_subtitles)
	_invert_check.set_pressed_no_signal(GameSettings.invert_look_y)
	_fullscreen_check.set_pressed_no_signal(GameSettings.fullscreen)
	_quality_slider.set_value_no_signal(GameSettings.graphics_quality)
	_quality_slider.value_changed.emit(GameSettings.graphics_quality)
	_language_option.select(GameSettings.SUPPORTED_LANGUAGES.find(GameSettings.language))
	for action: StringName in _binding_buttons:
		(_binding_buttons[action] as Button).text = GameSettings.binding_label(action)


func _menu_text_scale_index() -> int:
	return GameSettings.MENU_TEXT_SCALES.find(GameSettings.menu_text_scale)


## Shown over a paused game as often as over the menu, so it has to keep
## working while the tree is paused.
func open() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_from_settings()
	_refresh_controls()
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	# The first control, not the first Button: CheckBox counts as a Button,
	# so that used to land a gamepad player below both sliders.
	_volume_slider.grab_focus()


func close() -> void:
	if _sound_check != null and _sound_check.visible:
		_sound_check.call(&"close")
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	closed.emit()
