extends Control
class_name ProgressPanel

signal closed
const UNLOCK_REWARDS := {
	&"growing_weight_trap": {"text": "UI_REWARD_GROWING_WEIGHT", "trap": "PESO CRECIENTE", "glyph": "▣"},
	&"noisy_trap": {"text": "UI_REWARD_NOISY", "trap": "RUIDOSO", "glyph": "♫"},
	&"liquid_trap": {"text": "UI_REWARD_LIQUID", "glyph": "◒"},
	&"explosive_trap": {"text": "UI_REWARD_EXPLOSIVE", "glyph": "✦"},
	&"hostile_trap": {"text": "UI_REWARD_HOSTILE", "glyph": "◆"},
	&"violet_paint": {"text": "UI_REWARD_VIOLET_PAINT", "glyph": "●", "color": Color("7b52b9")},
	&"coral_uniform": {"text": "UI_REWARD_CORAL_UNIFORM", "glyph": "●", "color": Color("f47e6d")},
	&"sky_uniform": {"text": "UI_REWARD_SKY_UNIFORM", "glyph": "●", "color": Color("6db3d6")},
	&"agile_van": {"text": "UI_REWARD_AGILE_VAN", "glyph": "▰"},
}

var _summary: Label
var _list: VBoxContainer
var _new_campaign_button: Button
var _confirming_campaign_reset: bool = false

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
	var column: VBoxContainer = UiTheme.panel(center, Vector2(760, 620), 24)
	column.add_theme_constant_override("separation", 10)
	UiTheme.title(column, tr("UI_PROGRESS"), 38)
	UiTheme.tag(column, tr("UI_PROG_LOCAL_PROFILE"), UiTheme.SKY, 1.0, 14)
	_summary = UiTheme.label(column, "", 17, UiTheme.MUTED)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 430)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_new_campaign_button = UiTheme.button(actions, tr("UI_PROG_NEW_CAMPAIGN"), false)
	_new_campaign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_campaign_button.pressed.connect(_request_new_campaign)
	var back := UiTheme.button(actions, tr("UI_BACK"), true)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(close)

func open() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_campaign_confirmation()
	_refresh()
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_new_campaign_button.grab_focus.call_deferred()

func close() -> void:
	_reset_campaign_confirmation()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	closed.emit()

func _refresh() -> void:
	if _summary == null:
		return
	var summary := UnlockManager.progress_summary()
	_summary.text = tr("UI_PROG_SUMMARY") % [summary["deliveries"], summary["score"], summary["runs"]]
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for unlock_id: StringName in UnlockManager.UNLOCKS:
		var rule := UnlockManager.requirements(unlock_id)
		var got := UnlockManager.is_unlocked(unlock_id)
		_add_unlock_row(unlock_id, rule, got, summary)


func _add_unlock_row(unlock_id: StringName, rule: Dictionary, got: bool, summary: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "Unlock_%s" % unlock_id
	panel.tooltip_text = tr("UI_PROG_UNLOCK_LINE") % ["✓" if got else "○", tr(String(rule["title"])),
			rule["deliveries"], rule["score"]]
	panel.add_theme_stylebox_override("panel", UiTheme.surface_style(10, UiTheme.WHITE))
	_list.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var reward: Dictionary = UNLOCK_REWARDS.get(unlock_id, {"text": String(rule["title"]), "glyph": "◆"})
	var texture: Texture2D = UiTheme.trap_icon(String(reward.get("trap", "")))
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(52, 52)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
	else:
		var glyph_color: Color = reward.get("color", UiTheme.YELLOW)
		var glyph: Label = UiTheme.chip(row, String(reward.get("glyph", "◆")), glyph_color, 24)
		var glyph_holder: Control = glyph.get_parent() as Control
		glyph_holder.custom_minimum_size = Vector2(52, 52)
		glyph_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 3)
	row.add_child(content)
	var title: Label = UiTheme.label(content, "%s  %s" % ["✓" if got else "○", tr(String(rule["title"]))], 18,
			UiTheme.MINT if got else UiTheme.INK, true)
	title.name = "Title"
	var reward_label: Label = UiTheme.label(content, tr(String(reward["text"])), 15, UiTheme.MUTED)
	reward_label.name = "Reward"
	_add_requirement_bar(content, tr("UI_DELIVERIES"), int(summary["deliveries"]), int(rule["deliveries"]), got)
	_add_requirement_bar(content, tr("UI_POINTS"), int(summary["score"]), int(rule["score"]), got)


func _add_requirement_bar(parent: VBoxContainer, label_text: String, current: int, target: int, got: bool) -> void:
	var header := HBoxContainer.new()
	parent.add_child(header)
	var caption: Label = UiTheme.label(header, label_text, 13, UiTheme.MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.label(header, "%d / %d" % [mini(current, target), target], 13, UiTheme.MUTED)
	var bar: ProgressBar = UiTheme.bar(parent, UiTheme.MINT if got else UiTheme.SKY, 9)
	bar.name = "%sProgress" % label_text
	bar.value = 100.0 if got or target <= 0 else minf(float(current) / target, 1.0) * 100.0


func _request_new_campaign() -> void:
	if not _confirming_campaign_reset:
		_confirming_campaign_reset = true
		_new_campaign_button.text = tr("UI_PROG_CONFIRM_RESET")
		_new_campaign_button.grab_focus()
		return
	_confirming_campaign_reset = false
	if CrewProgression.reset_campaign(true):
		_new_campaign_button.text = tr("UI_PROG_RESET_DONE")
		_new_campaign_button.disabled = true
	else:
		_new_campaign_button.text = tr("UI_PROG_RESET_FAILED")
	_refresh()


func _reset_campaign_confirmation() -> void:
	_confirming_campaign_reset = false
	if _new_campaign_button != null:
		_new_campaign_button.text = tr("UI_PROG_NEW_CAMPAIGN")
		_new_campaign_button.disabled = false

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
