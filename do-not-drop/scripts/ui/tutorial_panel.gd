extends Control
class_name TutorialPanel

signal closed
const TutorialData = preload("res://scripts/ui/tutorial_catalog.gd")

var _back_button: Button
var _previous_button: Button
var _next_button: Button
var _page_title: Label
var _page_body: RichTextLabel
var _page_number: Label
var _icon: TextureRect
var _glyph: Label
var _pages: Array[Dictionary] = []
var _page_index: int = 0

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
	var column: VBoxContainer = UiTheme.panel(center, Vector2(760, 540), 28)
	UiTheme.title(column, tr("UI_HOW_TO_PLAY"), 38)
	UiTheme.tag(column, tr("UI_TUT_TAG"), UiTheme.YELLOW, -1.0, 14)
	var content := HBoxContainer.new()
	content.custom_minimum_size = Vector2(0, 330)
	content.tooltip_text = tr("UI_TUT_BODY")
	content.add_theme_constant_override(&"separation", 24)
	column.add_child(content)
	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size.x = 170
	icon_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_child(icon_holder)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(128, 128)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_holder.add_child(_icon)
	_glyph = Label.new()
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.add_theme_font_override(&"font", UiTheme.display_font())
	_glyph.add_theme_font_size_override(&"font_size", 100)
	_glyph.add_theme_color_override(&"font_color", UiTheme.ORANGE)
	_glyph.custom_minimum_size = Vector2(128, 128)
	icon_holder.add_child(_glyph)
	var page_column := VBoxContainer.new()
	page_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(page_column)
	_page_title = UiTheme.title(page_column, "", 28)
	_page_body = RichTextLabel.new()
	_page_body.bbcode_enabled = true
	_page_body.fit_content = false
	_page_body.scroll_active = false
	_page_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_body.add_theme_font_override(&"normal_font", UiTheme.body_font())
	_page_body.add_theme_font_size_override(&"normal_font_size", 18)
	_page_body.add_theme_color_override(&"default_color", UiTheme.INK)
	page_column.add_child(_page_body)
	_page_number = UiTheme.label(page_column, "", 14, UiTheme.MUTED)
	_page_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override(&"separation", 10)
	column.add_child(navigation)
	_previous_button = UiTheme.button(navigation, tr("UI_TUT_PREVIOUS"))
	_previous_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_previous_button.add_theme_color_override(&"font_disabled_color", UiTheme.MUTED)
	_previous_button.pressed.connect(_change_page.bind(-1))
	_next_button = UiTheme.button(navigation, tr("UI_TUT_NEXT"), true)
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button.add_theme_color_override(&"font_disabled_color", UiTheme.MUTED)
	_next_button.pressed.connect(_change_page.bind(1))
	_back_button = UiTheme.button(navigation, tr("UI_TUT_GOT_IT"))
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.pressed.connect(close)
	GameSettings.input_device_changed.connect(func(_gamepad: bool) -> void: _rebuild_pages())

func open() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rebuild_pages()
	_page_index = 0
	_refresh_page()
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_next_button.grab_focus.call_deferred()

func close() -> void:
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_page_up"):
		_change_page(-1)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_page_down"):
		_change_page(1)
		get_viewport().set_input_as_handled()


func page_titles() -> PackedStringArray:
	var titles := PackedStringArray()
	for page: Dictionary in _pages:
		titles.append(String(page["title"]))
	return titles


func _rebuild_pages() -> void:
	_pages = [
		_page(tr("UI_TUT_OBJECTIVE_TITLE"), tr("UI_TUT_OBJECTIVE_BODY"), "⌂"),
		_page(tr("UI_TUT_DRIVER_TITLE"), tr("UI_TUT_DRIVER_BODY")
				% UiTheme.keycaps(tr("UI_TUT_DRIVER_CONTROL") % GameSettings.prompt("W/S", "RT/LT")), "▰"),
		_page(tr("UI_TUT_PASSENGER_TITLE"), tr("UI_TUT_PASSENGER_BODY")
				% UiTheme.keycaps(tr("UI_TUT_PASSENGER_CONTROL") % [
					GameSettings.prompt(tr("UI_TUT_LEFT_CLICK"), "RT"),
					GameSettings.prompt("T", tr("UI_TUT_DPAD_DOWN"))]), "☺"),
	]
	for trap_id: StringName in TutorialData.available_traps(UnlockManager):
		var data: Dictionary = TutorialData.card(trap_id)
		_pages.append({
			"title": String(data["title"]),
			"body": tr("UI_TUT_TRAP_BODY") % [data["breaks"], data["action"],
					UiTheme.keycaps("%s  %s" % [TutorialData.control(data), data["control_label"]])],
			"glyph": String(data["glyph"]),
			"texture": UiTheme.trap_icon(String(data["title"])),
		})
	_pages.append(_page(tr("UI_TUT_REWARDS_TITLE"), tr("UI_TUT_REWARDS_BODY"), "$"))
	_page_index = clampi(_page_index, 0, maxi(_pages.size() - 1, 0))
	if visible:
		_refresh_page()


func _page(title: String, body: String, glyph: String) -> Dictionary:
	return {"title": title, "body": body, "glyph": glyph, "texture": null}


func _change_page(offset: int) -> void:
	if _pages.is_empty():
		return
	_page_index = clampi(_page_index + offset, 0, _pages.size() - 1)
	_refresh_page()
	(_back_button if _page_index == _pages.size() - 1 else _next_button).grab_focus()


func _refresh_page() -> void:
	if _pages.is_empty():
		return
	var page: Dictionary = _pages[_page_index]
	_page_title.text = String(page["title"])
	_page_body.text = String(page["body"])
	_page_number.text = "%d / %d" % [_page_index + 1, _pages.size()]
	var texture: Texture2D = page.get("texture") as Texture2D
	_icon.texture = texture
	_icon.visible = texture != null
	_glyph.text = String(page["glyph"])
	_glyph.visible = texture == null
	_previous_button.disabled = _page_index == 0
	_next_button.disabled = _page_index == _pages.size() - 1
