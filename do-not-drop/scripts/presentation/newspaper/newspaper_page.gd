class_name NewspaperPage
extends Control
## The next-day newspaper as a page (N-606.2): "El Eco de {town}", the front
## page story, up to three more from different sections and a classified.
## It draws what NewsDesk.read() says, in this peer's language, and asks for
## nothing else: `finished` tells whoever shows it (HudNewspaper) that the
## player is done reading. The scene-in-3D version (N-606.3) puts this same
## page on the Boss's paper.
##
## Laid out for 1280x720 with anchors and containers only: the sheet takes the
## width of the window up to MAX_SHEET_WIDTH and its stories scroll if some
## language or window doesn't leave room, with the button always in view.

signal finished

const NEWS_DESK = preload("res://scripts/presentation/newspaper/news_desk.gd")
const NEWSPRINT: Color = Color("f4ecd3")
const SHEET_MARGIN: int = 40
const MAX_SHEET_WIDTH: int = 1140
const ENTRANCE_SECONDS: float = 0.3

var paper: Dictionary = {}
var sheet: PanelContainer
var continue_button: Button
var _margin: MarginContainer


func _ready() -> void:
	name = "NewspaperPage"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_fit_margins)
	_build()


## Shows `new_paper`; false (and nothing drawn) when it can't be read.
func show_paper(new_paper: Dictionary) -> bool:
	if not NEWS_DESK.is_valid(new_paper):
		return false
	paper = new_paper
	if is_inside_tree():
		_build()
	return true


func _build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if paper.is_empty():
		return
	var veil := ColorRect.new()
	veil.color = Color(UiTheme.BACKDROP, 0.9)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(_margin)
	sheet = PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	_margin.add_child(sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	sheet.add_child(column)
	_masthead(column)
	_rule(column, 4)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	column.add_child(scroll)
	var stories := VBoxContainer.new()
	stories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stories.add_theme_constant_override("separation", 14)
	scroll.add_child(stories)
	_front(stories, NEWS_DESK.read(paper["front"]), (paper.get("stories", []) as Array).is_empty())
	var secondary: Array = paper.get("stories", [])
	if not secondary.is_empty():
		_rule(stories, 2)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		stories.add_child(row)
		for index: int in secondary.size():
			if index > 0:
				var divider := ColorRect.new()
				divider.color = UiTheme.INK
				divider.custom_minimum_size.x = 2
				row.add_child(divider)
			_secondary(row, NEWS_DESK.read(secondary[index]))
	if not (paper.get("filler", {}) as Dictionary).is_empty():
		_classified(stories, NEWS_DESK.read(paper["filler"]))
	_footer(column)
	_fit_margins()
	_enter.call_deferred()


func _fit_margins() -> void:
	if _margin == null:
		return
	var side: int = maxi(SHEET_MARGIN, roundi((size.x - MAX_SHEET_WIDTH) * 0.5))
	for edge: String in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + edge, side)


func _sheet_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = UiTheme.surface_style(26, NEWSPRINT)
	style.set_corner_radius_all(6)
	return style


func _rule(parent: Node, thickness: int) -> void:
	var line := ColorRect.new()
	line.color = UiTheme.INK
	line.custom_minimum_size.y = thickness
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _masthead(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var extra: Label = UiTheme.tag(row, tr("HUD_NEWS_EXTRA"), UiTheme.RED, -4.0, 20)
	extra.add_theme_color_override("font_color", UiTheme.WHITE)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	row.add_child(titles)
	var title: Label = UiTheme.title(titles, tr("HUD_NEWS_MASTHEAD") % String(paper.get("town", "")), 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var motto: Label = UiTheme.label(titles, tr("HUD_NEWS_MOTTO"), 15, UiTheme.MUTED)
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	motto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var edition: Label = UiTheme.label(row, tr("HUD_NEWS_EDITION"), 13, UiTheme.MUTED)
	edition.custom_minimum_size.x = 170
	edition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	edition.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _section_tag(parent: Node, text: String, font_size: int = 14) -> void:
	UiTheme.tag(parent, text, UiTheme.YELLOW, 0.0, font_size)


## A paper with nothing under the front page prints it bigger.
func _front(parent: Node, story: Dictionary, alone: bool = false) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.name = "Front"
	parent.add_child(box)
	_section_tag(box, String(story.get("section_text", "")), 15)
	_wrapped(box, String(story.get("headline", "")), 52 if alone else 40, UiTheme.INK, true)
	_wrapped(box, String(story.get("body", "")), 28 if alone else 22, UiTheme.INK, false)


func _secondary(parent: Node, story: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	box.name = "Story_" + String(story.get("id", ""))
	parent.add_child(box)
	_section_tag(box, String(story.get("section_text", "")), 13)
	_wrapped(box, String(story.get("headline", "")), 24, UiTheme.INK, true)
	_wrapped(box, String(story.get("body", "")), 17, UiTheme.INK, false)


func _classified(parent: Node, story: Dictionary) -> void:
	var frame := PanelContainer.new()
	frame.name = "Classified"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.WHITE, 0.6)
	style.border_color = UiTheme.INK
	style.set_border_width_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", style)
	parent.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	frame.add_child(box)
	_section_tag(box, String(story.get("section_text", "")), 13)
	_wrapped(box, String(story.get("headline", "")), 21, UiTheme.INK, true)
	_wrapped(box, String(story.get("body", "")), 16, UiTheme.INK, false)


func _wrapped(parent: Node, text: String, font_size: int, color: Color, display: bool) -> Label:
	var label: Label = UiTheme.label(parent, text, font_size, color, display)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 120
	if not display:
		label.add_theme_font_override("font", UiTheme.body_font(600))
	return label


func _footer(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	continue_button = UiTheme.button(row, tr("HUD_NEWS_CONTINUE"), true, Vector2(220, 48))
	continue_button.name = "Continue"
	continue_button.pressed.connect(close)


## A short toss onto the screen, skipped when the player turned shakes off.
func _enter() -> void:
	if not is_inside_tree() or sheet == null:
		return
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	continue_button.grab_focus()
	if GameSettings.camera_shake_scale <= 0.0:
		return
	sheet.pivot_offset = sheet.size * 0.5
	sheet.scale = Vector2(0.92, 0.92)
	sheet.rotation_degrees = -2.0
	sheet.modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sheet, "scale", Vector2.ONE, ENTRANCE_SECONDS)
	tween.tween_property(sheet, "rotation_degrees", 0.0, ENTRANCE_SECONDS)
	tween.tween_property(sheet, "modulate:a", 1.0, ENTRANCE_SECONDS * 0.6)


func close() -> void:
	if not visible:
		return
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_pause")):
		close()
		get_viewport().set_input_as_handled()
