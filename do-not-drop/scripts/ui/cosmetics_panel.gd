class_name CosmeticsPanel
extends Control
## "Make your character" (N-506): the real character on a lit stage on the
## left (turn it by dragging or with the right stick), and on the right the
## choices as picture cards in tabs -- face, uniform and, from the main menu,
## the truck. Every pick is saved at once (UnlockManager) and reaches the local
## player live (player.gd follows progress_changed; face, uniform and nickname
## replicate from there), so the same screen serves the depot's lockers:
## DepotPanel opens it in Mode.DEPOT, without the truck (that's the workshop).
## Full keyboard and gamepad; the cards update in place, so the stage is never
## rebuilt and keeps the turn the player gave it.

const Catalog = preload("res://scripts/core/face_catalog.gd")
const NICKNAME = preload("res://scripts/core/nickname.gd")
const PLAYER_SCRIPT = preload("res://scripts/gameplay/player/player.gd")
const CharacterPreview = preload("res://scripts/ui/customize/character_preview.gd")
const Swatch = preload("res://scripts/ui/customize/customize_swatch.gd")

signal closed

enum Mode { MENU, DEPOT }
enum Page { FACE, UNIFORM, TRUCK }

## Card heights by kind: faces are small and many, shirts and vans few and big
## (and room for a two-line "earned at..." under them).
const CARD_HEIGHT: Dictionary = {
	"preset": 100, "eyes": 92, "mouth": 92, "uniform": 206, "truck": 156, "paint": 156,
}
## The picture's height in each kind of card: the same in every card of a
## kind, whatever its text, so a row's pictures line up.
const SWATCH_HEIGHT: Dictionary = {
	"preset": 66, "eyes": 56, "mouth": 56, "uniform": 128, "truck": 84, "paint": 84,
}

## Picked before the panel enters the tree.
var mode: Mode = Mode.MENU
var page: Page = Page.FACE
var preview: CharacterPreview
var _nickname_edit: LineEdit
var _random_button: Button
var _done_button: Button
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
## Every card, with metas "kind" (eyes, mouth, uniform, truck, paint) and "choice".
var _cards: Array[Button] = []
## Cards per page in reading order, and their grids' column counts, for focus.
var _page_grids: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_sync()


func open() -> void:
	_sync()
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	focus_first()


## Focus on the picked card of the open page (the depot shows the panel
## itself, with its own opening sound, and only asks for this).
func focus_first() -> void:
	_focus_page.call_deferred()


func close() -> void:
	_commit_nickname()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	UiTheme.apply(self)
	var veil := ColorRect.new()
	veil.color = Color(UiTheme.BACKDROP, 0.82 if mode == Mode.DEPOT else 0.96)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	for edge: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	_build_header(outer)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)
	_build_stage(columns)
	_build_editor(columns)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(footer)
	_done_button = UiTheme.button(footer, tr("UI_DONE"), true, Vector2(200, 50))
	_done_button.name = "Done"
	_done_button.pressed.connect(close)
	_show_page(page, true)
	_wire_focus()


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	parent.add_child(header)
	var title: Label = UiTheme.title(header, tr("UI_DEPOT_LOCKERS") if mode == Mode.DEPOT else tr("UI_COSM_TITLE"),
			34, UiTheme.PAPER)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var saved: Label = UiTheme.label(header, tr("UI_COSM_AUTOSAVE"), 15, Color(UiTheme.PAPER, 0.72))
	saved.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## The character, the name the newspaper uses, and a dice roll for the face.
func _build_stage(parent: HBoxContainer) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	card.size_flags_stretch_ratio = 0.8
	card.add_theme_stylebox_override("panel", UiTheme.surface_style(14))
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	var stage := Control.new()
	stage.name = "Stage"
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(0, 280)
	stage.clip_contents = true
	column.add_child(stage)
	stage.add_child(_backdrop())
	preview = CharacterPreview.new()
	preview.name = "CharacterPreview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(preview)
	var tag_row := HBoxContainer.new()
	tag_row.position = Vector2(10, 10)
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(tag_row)
	UiTheme.tag(tag_row, tr("UI_COSM_PREVIEW_TAG"), UiTheme.YELLOW, -2.0, 13)
	# On a pill of paper: over a mint shirt bare text gets lost.
	var pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(UiTheme.PAPER, 0.9)
	pill_style.set_corner_radius_all(99)
	pill_style.content_margin_left = 12
	pill_style.content_margin_right = 12
	pill_style.content_margin_top = 3
	pill_style.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", pill_style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_bottom = -8
	stage.add_child(pill)
	var hint: Label = UiTheme.label(pill, tr("UI_COSM_ROTATE_HINT"), 13, UiTheme.MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_nickname(column)
	_random_button = UiTheme.button(column, tr("UI_COSM_RANDOM"), false, Vector2(0, 44))
	_random_button.name = "Randomize"
	_random_button.tooltip_text = tr("UI_COSM_RANDOM_HINT")
	_random_button.pressed.connect(_randomize_face)


## Soft light in the middle of the stage, a little darker at the edges.
func _backdrop() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color("fffaf1"))
	gradient.set_color(1, Color("efdcc0"))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.42)
	texture.fill_to = Vector2(1.15, 1.1)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## What the next-day newspaper calls you (N-606.1): up to 16 characters, saved
## when you press Enter or leave the field; empty, the game picks a funny one.
func _build_nickname(parent: VBoxContainer) -> void:
	var label: Label = UiTheme.label(parent, tr("UI_COSM_NICKNAME").to_upper(), 13, UiTheme.MUTED, true)
	label.tooltip_text = tr("UI_COSM_NICKNAME_HINT")
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_nickname_edit = UiTheme.line_edit(parent, tr("UI_COSM_NICKNAME_PLACEHOLDER"))
	_nickname_edit.name = "NicknameEdit"
	_nickname_edit.tooltip_text = tr("UI_COSM_NICKNAME_HINT")
	_nickname_edit.max_length = NICKNAME.MAX_LENGTH
	_nickname_edit.text_submitted.connect(func(_text: String) -> void:
		_commit_nickname()
		_nickname_edit.release_focus())
	_nickname_edit.focus_exited.connect(_commit_nickname)


func _build_editor(parent: HBoxContainer) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiTheme.surface_style(20))
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	column.add_child(bar)
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.INK, 0.12)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var pages: Array[Page] = [Page.FACE, Page.UNIFORM]
	if mode == Mode.MENU:
		pages.append(Page.TRUCK)
	for each: Page in pages:
		_tabs.append(_tab_button(bar, each))
		var scroll := ScrollContainer.new()
		scroll.name = "Page_%s" % Page.keys()[each].to_lower()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.follow_focus = true
		_style_scrollbar(scroll.get_v_scroll_bar())
		column.add_child(scroll)
		var contents := VBoxContainer.new()
		contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		contents.add_theme_constant_override("separation", 8)
		scroll.add_child(contents)
		_pages.append(scroll)
		_page_grids[each] = []
		match each:
			Page.FACE: _build_face_page(contents)
			Page.UNIFORM: _build_uniform_page(contents)
			Page.TRUCK: _build_truck_page(contents)


## A tab: muted text, ink with an ink underline when it's the open one.
func _tab_button(bar: HBoxContainer, which: Page) -> Button:
	var labels: Dictionary = {Page.FACE: "UI_COSM_FACE", Page.UNIFORM: "UI_COSM_UNIFORM", Page.TRUCK: "UI_TRUCK"}
	var tab := Button.new()
	tab.name = "Tab_%s" % Page.keys()[which].to_lower()
	tab.text = tr(labels[which])
	tab.toggle_mode = true
	tab.add_theme_font_override("font", UiTheme.display_font())
	UiTheme.register_font_size(tab, 22, &"font_size", bar)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.draw_center = false
		style.border_width_bottom = 4
		style.border_color = UiTheme.INK if state.contains("pressed") else (
				Color(UiTheme.INK, 0.22) if state == "hover" else Color(UiTheme.INK, 0.0))
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 6
		style.content_margin_bottom = 10
		tab.add_theme_stylebox_override(state, style)
	tab.add_theme_stylebox_override("focus", UiTheme.focus_ring())
	tab.add_theme_color_override("font_color", UiTheme.MUTED)
	for state: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		tab.add_theme_color_override(state, UiTheme.INK)
	tab.pressed.connect(func() -> void: _show_page(which))
	UiTheme.UI_SOUNDS.bind_button(tab)
	bar.add_child(tab)
	return tab


func _section(parent: VBoxContainer, title: String, caption: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 8)
	row.add_child(margin)
	UiTheme.title(margin, title, 21)
	if not caption.is_empty():
		var note: Label = UiTheme.label(row, caption, 14, UiTheme.MUTED)
		note.size_flags_vertical = Control.SIZE_SHRINK_END
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _grid(parent: VBoxContainer, which: Page, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)
	(_page_grids[which] as Array).append(grid)
	return grid


## Fills a short last row with empty cells, so its cards keep the width of the
## rows above (a grid only has as many columns as its longest row needs).
func _pad(grid: GridContainer) -> void:
	while grid.get_child_count() % grid.columns != 0:
		var cell := Control.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(cell)


## A thin ink thumb on no track, instead of the engine's grey bar.
func _style_scrollbar(bar: VScrollBar) -> void:
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 6
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color(UiTheme.INK, 0.22 if state == "grabber" else 0.4)
		thumb.set_corner_radius_all(4)
		bar.add_theme_stylebox_override(state, thumb)


func _build_face_page(contents: VBoxContainer) -> void:
	_section(contents, tr("UI_COSM_PRESETS"), tr("UI_COSM_PRESETS_HINT"))
	var presets: GridContainer = _grid(contents, Page.FACE, 8)
	for each: Dictionary in Catalog.PRESETS:
		var face: Control = Swatch.new().setup(Swatch.Kind.FACE, each.eyes)
		face.set(&"mouth", each.mouth)
		_card(presets, "preset", each.id, face, tr(String(each.title)))
	_section(contents, tr("UI_COSM_EYES"), tr("UI_COSM_FACE_HINT"))
	# Eight across: every eye and every mouth on screen at once, no scrolling.
	var eyes: GridContainer = _grid(contents, Page.FACE, 8)
	for id: StringName in Catalog.EYES:
		_card(eyes, "eyes", id, Swatch.new().setup(Swatch.Kind.EYES, id), tr(String(Catalog.EYES[id])))
	_section(contents, tr("UI_COSM_MOUTH"), "")
	var mouths: GridContainer = _grid(contents, Page.FACE, 8)
	for id: StringName in Catalog.MOUTHS:
		_card(mouths, "mouth", id, Swatch.new().setup(Swatch.Kind.MOUTH, id), tr(String(Catalog.MOUTHS[id])))


func _build_uniform_page(contents: VBoxContainer) -> void:
	_section(contents, tr("UI_COSM_YOUR_UNIFORM"),
			tr("UI_DEPOT_UNIFORM_HINT") if mode == Mode.DEPOT else tr("UI_COSM_UNIFORM_HINT"))
	# Two by two, big: few uniforms, and the shirt is the point.
	var grid: GridContainer = _grid(contents, Page.UNIFORM, 2)
	for choice: Dictionary in UnlockManager.cosmetic_choices():
		var id: StringName = choice["id"]
		var fill: Array[Color] = []
		if UnlockManager.cosmetic_is_auto(id):
			fill.assign(PLAYER_SCRIPT.PLAYER_COLORS.slice(0, 4))
		else:
			fill.append(UnlockManager.cosmetic_color(id))
		_card(grid, "uniform", id, Swatch.new().setup(Swatch.Kind.SHIRT, id, fill), tr(String(choice["title"])),
				_lock_text(choice))
	_pad(grid)


func _build_truck_page(contents: VBoxContainer) -> void:
	_section(contents, tr("UI_TRUCK"), tr("UI_COSM_TRUCK_HINT"))
	var trucks: GridContainer = _grid(contents, Page.TRUCK, 3)
	for choice: Dictionary in UnlockManager.truck_choices():
		var id: StringName = choice["id"]
		var detail: String = _lock_text(choice)
		if detail.is_empty() and choice.has("detail"):
			detail = tr(String(choice["detail"]))
		var white: Array[Color] = [UiTheme.WHITE]
		_card(trucks, "truck", id, Swatch.new().setup(Swatch.Kind.VAN, id, white), tr(String(choice["title"])),
				detail, choice["available"])
	_pad(trucks)
	_section(contents, tr("UI_PAINT"), "")
	var paints: GridContainer = _grid(contents, Page.TRUCK, 3)
	for choice: Dictionary in UnlockManager.paint_choices():
		var id: StringName = choice["id"]
		var paint: Array[Color] = [choice["color"]]
		_card(paints, "paint", id, Swatch.new().setup(Swatch.Kind.VAN, id, paint), tr(String(choice["title"])),
				_lock_text(choice))
	_pad(paints)


func _lock_text(choice: Dictionary) -> String:
	if bool(choice["available"]):
		return ""
	var rule: Dictionary = UnlockManager.requirements(StringName(choice["unlock"]))
	return tr("UI_COSM_UNLOCK_AT") % [int(rule.get("deliveries", 0)), int(rule.get("score", 0))]


# --- Cards -------------------------------------------------------------------

## A picture card: the swatch, its name, and under it a detail or what it
## takes to unlock. Picked: mint tint, ink border and a check badge.
func _card(grid: GridContainer, kind: String, id: StringName, swatch: Control, title: String,
		detail: String = "", available: bool = true) -> Button:
	if kind in ["uniform", "paint"]:
		available = detail.is_empty()
	var card := Button.new()
	card.name = kind.capitalize() + "_" + String(id)
	card.toggle_mode = true
	card.tooltip_text = title if detail.is_empty() else "%s — %s" % [title, detail]
	card.custom_minimum_size = Vector2(0, CARD_HEIGHT[kind])
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = not available
	card.set_meta(&"kind", kind)
	card.set_meta(&"choice", id)
	_style_card(card)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	swatch.custom_minimum_size.y = SWATCH_HEIGHT[kind]
	column.add_child(swatch)
	# One line, never broken mid-word: a name that doesn't fit ends in "…"
	# (the tooltip has it whole).
	var small: bool = kind in ["preset", "eyes", "mouth"]
	var name_label: Label = UiTheme.label(column, title, 13 if small else 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not detail.is_empty():
		var detail_label: Label = UiTheme.label(column, detail, 12, UiTheme.MUTED)
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Slack goes under the text: names sit right under same-size pictures, so
	# a row's names line up whatever the details below them.
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	if not available:
		swatch.modulate = Color(1, 1, 1, 0.45)
	for badge_name: String in ["Check", "Lock"]:
		var badge := CheckBadge.new()
		badge.name = badge_name
		badge.locked = badge_name == "Lock"
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -28
		badge.offset_top = 6
		badge.offset_right = -6
		badge.offset_bottom = 28
		card.add_child(badge)
		badge.visible = badge.locked and not available
	card.pressed.connect(_pick.bind(kind, id))
	UiTheme.UI_SOUNDS.bind_button(card)
	grid.add_child(card)
	_cards.append(card)
	return card


func _style_card(card: Button) -> void:
	var looks: Dictionary = {
		"normal": [UiTheme.WHITE, Color(UiTheme.INK, 0.14), 2],
		"hover": [UiTheme.WHITE, Color(UiTheme.INK, 0.45), 2],
		"pressed": [Color("e6f8f0"), UiTheme.INK, 3],
		"hover_pressed": [Color("e6f8f0"), UiTheme.INK, 3],
		"disabled": [Color("f6efe3"), Color(UiTheme.INK, 0.1), 2],
	}
	for state: String in looks:
		var look: Array = looks[state]
		var style := StyleBoxFlat.new()
		style.bg_color = look[0]
		style.border_color = look[1]
		style.set_border_width_all(look[2])
		style.set_corner_radius_all(14)
		style.anti_aliasing = true
		card.add_theme_stylebox_override(state, style)
	var ring: StyleBoxFlat = UiTheme.focus_ring()
	ring.set_corner_radius_all(18)
	card.add_theme_stylebox_override("focus", ring)


func _pick(kind: String, id: StringName) -> void:
	var changed: bool = false
	match kind:
		"preset":
			var face: Dictionary = Catalog.preset(id)
			changed = UnlockManager.select_eyes(face.eyes) and UnlockManager.select_mouth(face.mouth)
		"eyes": changed = UnlockManager.select_eyes(id)
		"mouth": changed = UnlockManager.select_mouth(id)
		"uniform": changed = UnlockManager.select_cosmetic(id)
		"truck": changed = UnlockManager.select_truck(id)
		"paint": changed = UnlockManager.select_paint(id)
	_sync()
	if changed and kind in ["preset", "eyes", "mouth", "uniform"]:
		preview.bounce()


## A face picked at random, never a blank one and never the one you have.
func _randomize_face() -> void:
	var eyes: Array = Catalog.EYES.keys().filter(func(id: StringName) -> bool:
		return id != &"none" and id != UnlockManager.selected_eyes)
	var mouths: Array = Catalog.MOUTHS.keys().filter(func(id: StringName) -> bool:
		return id != &"none" and id != UnlockManager.selected_mouth)
	UnlockManager.select_eyes(eyes.pick_random())
	UnlockManager.select_mouth(mouths.pick_random())
	_sync()
	preview.bounce()


## Everything shown from the saved profile: cards, nickname, the character.
func _sync() -> void:
	var selected: Dictionary = {
		"eyes": UnlockManager.selected_eyes, "mouth": UnlockManager.selected_mouth,
		"uniform": UnlockManager.selected_cosmetic, "truck": UnlockManager.selected_truck,
		"paint": UnlockManager.selected_paint,
	}
	for card: Button in _cards:
		var kind: String = card.get_meta(&"kind")
		var chosen: bool = selected.get(kind) == card.get_meta(&"choice")
		if kind == "preset":
			var face: Dictionary = Catalog.preset(card.get_meta(&"choice"))
			chosen = face.eyes == UnlockManager.selected_eyes and face.mouth == UnlockManager.selected_mouth
		card.set_pressed_no_signal(chosen)
		(card.get_node(^"Check") as CanvasItem).visible = chosen
	if is_instance_valid(_nickname_edit) and not _nickname_edit.has_focus():
		_nickname_edit.text = UnlockManager.nickname
	preview.show_look(_shirt_color(), UnlockManager.selected_eyes, UnlockManager.selected_mouth)


## The shirt the others will see: the automatic team colour is this peer's
## colour slot (PlayerColorSlot), not the catalogue's placeholder yellow.
func _shirt_color() -> Color:
	if UnlockManager.cosmetic_is_auto(UnlockManager.selected_cosmetic):
		var palette: Array[Color] = PLAYER_SCRIPT.PLAYER_COLORS
		return palette[PlayerColorSlot.slot(NetworkManager.local_id(), palette.size())]
	return UnlockManager.cosmetic_color()


func _commit_nickname() -> void:
	if not is_instance_valid(_nickname_edit) or not _nickname_edit.is_inside_tree():
		return
	UnlockManager.set_nickname(_nickname_edit.text)
	if _nickname_edit.text != UnlockManager.nickname:
		_nickname_edit.text = UnlockManager.nickname


# --- Pages and focus -----------------------------------------------------------

func _show_page(which: Page, instant: bool = false) -> void:
	page = which
	for index: int in _pages.size():
		var shown: bool = _page_of(index) == which
		_pages[index].visible = shown
		_tabs[index].set_pressed_no_signal(shown)
	preview.set_framing(CharacterPreview.Framing.FACE if which == Page.FACE else CharacterPreview.Framing.BODY,
			instant)
	_wire_focus()


## Pages and tabs are built in Page order, so a page's index is its value.
func _page_of(index: int) -> Page:
	return index as Page


## The card to land on in the open page: the picked one, else the first.
func _page_entry() -> Control:
	var first: Control = null
	for grid: GridContainer in _page_grids.get(page, []):
		for child: Node in grid.get_children():
			var card := child as Button
			if card == null or card.disabled:
				continue
			if card.button_pressed:
				return card
			if first == null:
				first = card
	return first if first != null else _done_button


func _focus_page() -> void:
	var entry: Control = _page_entry()
	if entry != null and entry.is_visible_in_tree():
		entry.grab_focus()


## Stage column (nickname, dice) left of the cards, tabs above them, Done below.
## Arrows move through each grid; up from a grid's top row goes to the row
## above it, or the tabs; down from the last row goes to Done.
func _wire_focus() -> void:
	if _done_button == null:
		return
	var grids: Array = _page_grids.get(page, [])
	var tab: Button = _tabs[int(page)]
	var entry: Control = _page_entry()
	_link(_nickname_edit, {&"focus_neighbor_right": entry, &"focus_neighbor_bottom": _random_button,
			&"focus_neighbor_top": tab})
	_link(_random_button, {&"focus_neighbor_right": entry, &"focus_neighbor_top": _nickname_edit,
			&"focus_neighbor_bottom": _done_button})
	_link(_done_button, {&"focus_neighbor_left": _random_button})
	for index: int in _tabs.size():
		_link(_tabs[index], {&"focus_neighbor_bottom": entry, &"focus_neighbor_left":
				_tabs[index - 1] if index > 0 else _nickname_edit,
				&"focus_neighbor_right": _tabs[index + 1] if index + 1 < _tabs.size() else _tabs[index]})
	for g: int in grids.size():
		var grid: GridContainer = grids[g]
		var cards: Array[Node] = _cards_in(grid)
		var columns: int = grid.columns
		for index: int in cards.size():
			var card: Control = cards[index]
			var column: int = index % columns
			var up: Control = cards[index - columns] if index >= columns else _row_above(grids, g, column, tab)
			var down: Control = cards[index + columns] if index + columns < cards.size() else _row_below(grids, g, column)
			_link(card, {
				&"focus_neighbor_left": cards[index - 1] if column > 0 else _nickname_edit,
				&"focus_neighbor_right": cards[index + 1] if column < columns - 1 and index + 1 < cards.size() else card,
				&"focus_neighbor_top": up,
				&"focus_neighbor_bottom": down,
			})


func _row_above(grids: Array, g: int, column: int, tab: Control) -> Control:
	if g == 0:
		return tab
	var cards: Array[Node] = _cards_in(grids[g - 1])
	var columns: int = (grids[g - 1] as GridContainer).columns
	var last_row: int = (cards.size() - 1) / columns * columns
	return cards[mini(last_row + column, cards.size() - 1)]


func _row_below(grids: Array, g: int, column: int) -> Control:
	if g + 1 >= grids.size():
		return _done_button
	var cards: Array[Node] = _cards_in(grids[g + 1])
	return cards[mini(column, cards.size() - 1)]


## The grid's cards, without the empty cells that pad its last row.
func _cards_in(grid: GridContainer) -> Array[Node]:
	return grid.get_children().filter(func(child: Node) -> bool: return child is Button)


func _link(control: Control, neighbors: Dictionary) -> void:
	if control == null:
		return
	for property: StringName in neighbors:
		var target: Control = neighbors[property]
		if target != null:
			control.set(property, control.get_path_to(target))


## The mint dot with a check on the picked card, or a padlock on a locked one.
class CheckBadge extends Control:
	var locked: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centre: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.5
		if locked:
			var body := Rect2(centre + Vector2(-radius * 0.62, -radius * 0.1), Vector2(radius * 1.24, radius * 0.95))
			draw_arc(centre + Vector2(0.0, -radius * 0.12), radius * 0.38, PI, TAU, 16, UiTheme.MUTED, 2.6, true)
			var shell := StyleBoxFlat.new()
			shell.bg_color = UiTheme.MUTED
			shell.set_corner_radius_all(3)
			draw_style_box(shell, body)
			return
		draw_circle(centre, radius, UiTheme.INK, true, -1.0, true)
		draw_circle(centre, radius - 2.0, UiTheme.MINT, true, -1.0, true)
		var tick := PackedVector2Array([centre + Vector2(-radius * 0.42, 0.0),
				centre + Vector2(-radius * 0.1, radius * 0.32), centre + Vector2(radius * 0.45, -radius * 0.3)])
		draw_polyline(tick, UiTheme.INK, 2.6, true)
