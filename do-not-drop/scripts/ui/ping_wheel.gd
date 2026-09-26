class_name PingWheel
extends CanvasLayer
## Local-only radial picker. Networking remains owned by PlayerInteraction.

const RADIUS: float = 150.0
const DEAD_ZONE: float = 42.0

var selected_index: int = 0
var _root: Control
var _items: Array[PanelContainer] = []


func _ready() -> void:
	layer = 110
	_build()
	hide_wheel()


func show_wheel() -> void:
	selected_index = 0
	_refresh_selection()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)


func hide_wheel() -> void:
	if _root != null:
		_root.visible = false


func selected_label() -> String:
	return String(PingCatalog.OPTIONS[selected_index]["label"])


func select_from_pointer(pointer: Vector2) -> void:
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	select_from_vector(pointer - center)


func select_from_vector(direction: Vector2) -> void:
	var index: int = index_for_vector(direction)
	if index == selected_index:
		return
	selected_index = index
	_refresh_selection()


static func index_for_vector(direction: Vector2) -> int:
	if direction.length() < DEAD_ZONE:
		return 0
	var normalized: Vector2 = direction.normalized()
	var best_index: int = 0
	var best_dot: float = -INF
	for index: int in PingCatalog.OPTIONS.size():
		var option_direction := Vector2.RIGHT.rotated(-PI * 0.5 + TAU * float(index) / float(PingCatalog.OPTIONS.size()))
		var score: float = normalized.dot(option_direction)
		if score > best_dot:
			best_dot = score
			best_index = index
	return best_index


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.05, 0.05, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var title := Label.new()
	title.text = "PING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override(&"font", load(UiTheme.DISPLAY_FONT_PATH))
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", UiTheme.PAPER)
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-80.0, -14.0)
	title.size = Vector2(160.0, 28.0)
	_root.add_child(title)
	for index: int in PingCatalog.OPTIONS.size():
		var option: Dictionary = PingCatalog.OPTIONS[index]
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_preset(Control.PRESET_CENTER)
		var direction := Vector2.RIGHT.rotated(-PI * 0.5 + TAU * float(index) / float(PingCatalog.OPTIONS.size()))
		panel.position = direction * RADIUS - Vector2(74.0, 23.0)
		panel.size = Vector2(148.0, 46.0)
		var label := Label.new()
		label.text = "%s  %s" % [option["icon"], option["label"]]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override(&"font", load(UiTheme.DISPLAY_FONT_PATH))
		label.add_theme_font_size_override(&"font_size", 18)
		panel.add_child(label)
		_root.add_child(panel)
		_items.append(panel)
	_refresh_selection()


func _refresh_selection() -> void:
	for index: int in _items.size():
		var option: Dictionary = PingCatalog.OPTIONS[index]
		var style := StyleBoxFlat.new()
		style.bg_color = option["color"] if index == selected_index else Color(UiTheme.INK, 0.86)
		style.border_color = UiTheme.PAPER if index == selected_index else UiTheme.MUTED
		style.set_border_width_all(3 if index == selected_index else 1)
		style.set_corner_radius_all(8)
		_items[index].add_theme_stylebox_override(&"panel", style)
		var label: Label = _items[index].get_child(0) as Label
		label.add_theme_color_override(&"font_color", UiTheme.INK if index == selected_index else UiTheme.PAPER)
