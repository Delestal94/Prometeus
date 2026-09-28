extends PanelContainer
## The card for the box in your hands or at your seat: which box and how it's
## doing, the one thing to do now in big letters (CareGuide), the animated
## strip showing the button for it (CarePromptView), and the secondary keys
## underneath. Same cream sticker look as the rest of the HUD (UiTheme), not
## the engine's grey panel it replaced.

const CareGuide = preload("res://scripts/ui/hud/care_guide.gd")
const CarePromptView = preload("res://scripts/ui/hud/care_prompt_view.gd")
const UiThemeScript = preload("res://scripts/ui/ui_theme.gd")
const WIDTH: float = 340.0
## Every step keeps the same height, footer or not: the card is centred on
## the screen's edge and would otherwise jump as the steps change.
const MIN_HEIGHT: float = 330.0
## Warm for "something to do now", readable on cream (UiTheme.ORANGE isn't).
const URGENT_ORANGE: Color = Color("c26a00")
const STATE_TEXTS: Array[String] = ["OK", "EN RIESGO", "ARRUINADA"]
## Headline colours per step: what needs doing now reads warm, all-good cool.
const STEP_COLORS: Dictionary = {&"collect": URGENT_ORANGE, &"sequence": URGENT_ORANGE,
	&"tool": UiThemeScript.INK, &"release": UiThemeScript.RED, &"hold": UiThemeScript.INK,
	&"lost": UiThemeScript.MUTED, &"idle": UiThemeScript.INK}

var icon: TextureRect
var name_label: Label
var state_chip: Label
var integrity_bar: ProgressBar
var step_title: Label
var step_detail: Label
var prompt_view: CarePromptView
var footer: HFlowContainer
var current_step: StringName = &""
var _trap_name: String = ""
var _footer_items: PackedStringArray = []


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, MIN_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiThemeScript.surface_style(16))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(names)
	name_label = UiThemeScript.title(names, "", 20)
	integrity_bar = UiThemeScript.bar(names, UiThemeScript.MINT, 10)
	state_chip = UiThemeScript.chip(header, "OK", UiThemeScript.MINT, 16)
	# As wide as its longest word, so the integrity bar never changes length.
	state_chip.get_parent().size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(state_chip.get_parent() as Control).custom_minimum_size.x = 84
	state_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rule := ColorRect.new()
	rule.color = Color(UiThemeScript.INK, 0.15)
	rule.custom_minimum_size.y = 2
	column.add_child(rule)
	step_title = UiThemeScript.title(column, "", 26)
	step_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_title.custom_minimum_size.x = WIDTH - 32
	prompt_view = CarePromptView.new()
	prompt_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(prompt_view)
	step_detail = UiThemeScript.label(column, "", 16, UiThemeScript.MUTED)
	step_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_detail.custom_minimum_size.x = WIDTH - 32
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(push)
	# Key + action pairs that wrap between pairs, never inside one.
	footer = HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", 14)
	footer.add_theme_constant_override("v_separation", 6)
	footer.alignment = FlowContainer.ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)


## A different box (or none).
func reset() -> void:
	prompt_view.reset()
	current_step = &""


## One frame. `step` from CareGuide.next_step(); `view_data` for the
## animated strip; `footer_items` as "KEY  action" pairs.
func update(trap_name: String, state: int, integrity: float, step: Dictionary, view_data: Dictionary,
		footer_items: PackedStringArray) -> void:
	if trap_name != _trap_name:
		_trap_name = trap_name
		icon.texture = UiThemeScript.trap_icon(trap_name)
		name_label.text = trap_name.to_upper()
	var clamped: int = clampi(state, 0, 2)
	var colorblind: bool = _colorblind()
	var state_color: Color = UiThemeScript.state_color(clamped, colorblind)
	state_chip.text = STATE_TEXTS[clamped]
	((state_chip.get_parent() as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat).bg_color = state_color
	integrity_bar.value = clampf(integrity, 0.0, 100.0)
	(integrity_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = state_color
	current_step = StringName(step.get("step", &"idle"))
	step_title.text = String(step.get("title", ""))
	step_title.add_theme_color_override("font_color", STEP_COLORS.get(current_step, UiThemeScript.INK))
	step_detail.text = String(step.get("detail", ""))
	step_detail.visible = not step_detail.text.is_empty()
	prompt_view.show_step(current_step, view_data)
	if footer_items != _footer_items:
		_footer_items = footer_items
		_build_footer(footer_items)


func _build_footer(items: PackedStringArray) -> void:
	for child: Node in footer.get_children():
		child.queue_free()
	for item: String in items:
		var parts: PackedStringArray = item.split("  ", false, 1)
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 6)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_child(pair)
		var cap := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = UiThemeScript.INK
		style.set_corner_radius_all(6)
		style.content_margin_left = 7
		style.content_margin_right = 7
		style.content_margin_top = 1
		style.content_margin_bottom = 2
		style.shadow_color = Color(UiThemeScript.INK, 0.35)
		style.shadow_offset = Vector2(0, 2)
		style.shadow_size = 1
		cap.add_theme_stylebox_override("panel", style)
		pair.add_child(cap)
		UiThemeScript.title(cap, parts[0], 16, UiThemeScript.PAPER)
		if parts.size() > 1:
			UiThemeScript.label(pair, parts[1], 16, UiThemeScript.INK)


func _colorblind() -> bool:
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	return settings != null and bool(settings.get(&"colorblind_palette"))
