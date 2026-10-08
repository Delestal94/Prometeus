class_name GelProportionEditor
extends VBoxContainer
## The body-proportion controls shown by CosmeticsPanel (S-311.22).
## Owns only the current editing session; profile persistence arrives in S-311.23.

signal proportions_changed(proportions: GelBodyProportions)

const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")
const RandomButton := preload("res://scripts/gameplay/player/gel/gel_proportion_random_button.gd")
const HISTORY_LIMIT: int = 32

var proportions: GelBodyProportions

var _preset_picker: OptionButton
var _restore_button: Button
var _undo_button: Button
var _random_button: GelProportionRandomButton
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _focus_controls: Array[Control] = []
var _undo_stack: Array[Dictionary] = []
var _last_values: Dictionary = {}
var _selected_preset: StringName = &"delgada"
var _syncing: bool = false


func setup(value: GelBodyProportions) -> GelProportionEditor:
	proportions = value
	return self


func _ready() -> void:
	if proportions == null:
		proportions = GelBodyProportions.new()
	add_theme_constant_override("separation", 10)
	_build_actions()
	_build_sliders()
	_last_values = proportions.as_dictionary()
	_update_undo_button()


func focus_entry() -> Control:
	return _focus_controls[0] if not _focus_controls.is_empty() else self


func focus_last() -> Control:
	return _focus_controls[-1] if not _focus_controls.is_empty() else self


## Keeps vertical keyboard/gamepad traversal deterministic inside the scroll page.
func wire_focus(top: Control, bottom: Control, left: Control) -> void:
	for index: int in _focus_controls.size():
		var control: Control = _focus_controls[index]
		control.focus_neighbor_top = control.get_path_to(
			top if index == 0 else _focus_controls[index - 1]
		)
		control.focus_neighbor_bottom = control.get_path_to(
			bottom if index + 1 == _focus_controls.size() else _focus_controls[index + 1]
		)
		if control is HSlider:
			control.focus_neighbor_left = control.get_path_to(left)


func _build_actions() -> void:
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	add_child(preset_row)
	var preset_label: Label = UiTheme.label(preset_row, tr("UI_GEL_EDITOR_PRESET"), 14, UiTheme.MUTED, true)
	preset_label.custom_minimum_size.x = 118
	preset_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preset_picker = OptionButton.new()
	_preset_picker.name = "ProportionPreset"
	_preset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset_id: StringName in Presets.preset_ids():
		_preset_picker.add_item(tr(Presets.label_key(preset_id)))
		_preset_picker.set_item_metadata(_preset_picker.item_count - 1, preset_id)
	_preset_picker.item_selected.connect(_select_preset)
	UiTheme.UI_SOUNDS.bind_button(_preset_picker)
	preset_row.add_child(_preset_picker)
	_focus_controls.append(_preset_picker)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	_restore_button = UiTheme.button(actions, tr("UI_GEL_EDITOR_RESTORE"), false, Vector2(0, 42))
	_restore_button.name = "ProportionRestore"
	_restore_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_restore_button.pressed.connect(_restore_preset)
	_undo_button = UiTheme.button(actions, tr("UI_GEL_EDITOR_UNDO"), false, Vector2(0, 42))
	_undo_button.name = "ProportionUndo"
	_undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo_button.pressed.connect(_undo)
	_random_button = RandomButton.new()
	_random_button.name = "ProportionRandom"
	_random_button.proportions = proportions
	_random_button.custom_minimum_size = Vector2(0, 42)
	_random_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_random_button.proportions_randomized.connect(_randomized)
	actions.add_child(_random_button)
	UiTheme.UI_SOUNDS.bind_button(_random_button)
	_focus_controls.append(_restore_button)
	_focus_controls.append(_undo_button)
	_focus_controls.append(_random_button)


func _build_sliders() -> void:
	for definition: Dictionary in GelBodyProportions.parameter_definitions():
		var parameter_name: StringName = definition[&"name"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		var label: Label = UiTheme.label(row, tr(String(definition[&"label_key"])), 14)
		label.custom_minimum_size.x = 165
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var slider := HSlider.new()
		slider.name = "Proportion_%s" % parameter_name
		slider.min_value = float(definition[&"minimum"])
		slider.max_value = float(definition[&"maximum"])
		slider.step = 0.01
		slider.value = float(proportions.get(parameter_name))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.x = 190
		slider.tooltip_text = label.text
		slider.value_changed.connect(_slider_changed.bind(parameter_name))
		row.add_child(slider)
		var value_label: Label = UiTheme.label(row, "", 13, UiTheme.MUTED)
		value_label.custom_minimum_size.x = 48
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_sliders[parameter_name] = slider
		_value_labels[parameter_name] = value_label
		_focus_controls.append(slider)
		_update_value_label(parameter_name, slider.value)


func _select_preset(index: int) -> void:
	_selected_preset = _preset_picker.get_item_metadata(index)
	_apply_preset()


func _restore_preset() -> void:
	_apply_preset()


func _apply_preset() -> void:
	var before: Dictionary = _last_values.duplicate(true)
	_syncing = true
	var changed: bool = Presets.apply_preset(_selected_preset, proportions)
	_syncing = false
	if changed:
		_sync_sliders()
		_commit_change(before)


func _slider_changed(value: float, parameter_name: StringName) -> void:
	if _syncing:
		return
	var before: Dictionary = _last_values.duplicate(true)
	proportions.set(parameter_name, value)
	proportions.emit_changed()
	_update_value_label(parameter_name, value)
	_commit_change(before)


func _randomized(_value: GelBodyProportions) -> void:
	var before: Dictionary = _last_values.duplicate(true)
	_sync_sliders()
	_commit_change(before)


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var previous: Dictionary = _undo_stack.pop_back()
	_apply_values(previous)
	_last_values = proportions.as_dictionary()
	_update_undo_button()
	proportions_changed.emit(proportions)


func _commit_change(before: Dictionary) -> void:
	var current: Dictionary = proportions.as_dictionary()
	if current == before:
		return
	_undo_stack.append(before)
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.pop_front()
	_last_values = current
	_update_undo_button()
	proportions_changed.emit(proportions)


func _apply_values(values: Dictionary) -> void:
	_syncing = true
	for parameter_name: StringName in values:
		proportions.set(parameter_name, values[parameter_name])
	proportions.emit_changed()
	_syncing = false
	_sync_sliders()


func _sync_sliders() -> void:
	_syncing = true
	for parameter_name: StringName in _sliders:
		var value: float = float(proportions.get(parameter_name))
		(_sliders[parameter_name] as HSlider).set_value_no_signal(value)
		_update_value_label(parameter_name, value)
	_syncing = false


func _update_value_label(parameter_name: StringName, value: float) -> void:
	var definition: Dictionary = GelBodyProportions.definition_for(parameter_name)
	var percent: int = roundi((value - float(definition[&"default"])) * 100.0)
	(_value_labels[parameter_name] as Label).text = "%+d%%" % percent


func _update_undo_button() -> void:
	if _undo_button != null:
		_undo_button.disabled = _undo_stack.is_empty()
