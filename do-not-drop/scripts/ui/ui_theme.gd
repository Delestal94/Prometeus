class_name UiTheme
extends RefCounted
## The one place the interface's colours and widgets are defined.
##
## Until now the same five colours and the same panel/label/button builders
## were copy-pasted into main_menu.gd and prototype_hud.gd, which
## docs/direccion-visual.md section 3 already flagged: two screens drifting
## apart one tweak at a time is how an interface stops looking like one
## product. Every screen builds from here instead, so a change to the brand
## is a change to this file.
##
## A RefCounted with static members on purpose: nothing here has state, and
## an autoload for four colours would be a node in the tree for no reason.

const INK: Color = Color("132a31")
const PAPER: Color = Color("edf2e8")
const MUTED: Color = Color("acc1bd")
const MINT: Color = Color("83e2ba")
const YELLOW: Color = Color("f4c562")
const RED: Color = Color("f47e6d")
const BORDER: Color = Color("365458")
const SURFACE: Color = Color("30474d")
const BACKDROP: Color = Color("0d1f24")

const CORNER_RADIUS: int = 8
const BUTTON_HEIGHT: int = 44


## A dark, bordered card. Returns the column to fill, not the panel itself:
## every caller wants to append to it, and none of them want to remember
## which of the two nodes that is.
static func panel(parent: Node, minimum_size: Vector2 = Vector2.ZERO, padding: int = 22) -> VBoxContainer:
	var container := PanelContainer.new()
	container.custom_minimum_size = minimum_size
	container.add_theme_stylebox_override("panel", surface_style(padding))
	parent.add_child(container)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	container.add_child(column)
	return column


static func surface_style(padding: int = 22) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.94)
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = int(padding * 0.8)
	style.content_margin_bottom = int(padding * 0.8)
	return style


static func label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node


static func button(parent: Node, text: String, primary: bool = false, minimum_size: Vector2 = Vector2(0, BUTTON_HEIGHT)) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = minimum_size
	node.add_theme_font_size_override("font_size", 18)
	var style := StyleBoxFlat.new()
	style.bg_color = MINT if primary else SURFACE
	style.set_corner_radius_all(5)
	style.content_margin_left = 18
	style.content_margin_right = 18
	node.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.bg_color = style.bg_color.lightened(0.12)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", hover)
	# Focus gets its own look rather than reusing hover: a gamepad user
	# moving through the menu has no cursor, so "where am I" has to be
	# visible without one.
	var focus: StyleBoxFlat = style.duplicate()
	focus.border_color = PAPER
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus", focus)
	var text_color: Color = INK if primary else PAPER
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, text_color)
	parent.add_child(node)
	return node


static func bar(parent: Node, color: Color) -> ProgressBar:
	var node := ProgressBar.new()
	node.custom_minimum_size.y = 8
	node.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color("2e454b")
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	node.add_theme_stylebox_override("background", background)
	node.add_theme_stylebox_override("fill", fill)
	parent.add_child(node)
	return node


## A labelled slider row, with the current value spelled out. Used by the
## options screen for volume and look sensitivity.
static func slider_row(parent: Node, text: String, minimum: float, maximum: float, step: float, value: float) -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var header := HBoxContainer.new()
	row.add_child(header)
	var caption: Label = label(header, text, 15, PAPER)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout: Label = label(header, "", 15, MINT)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 22
	row.add_child(slider)
	var refresh: Callable = func(current: float) -> void:
		readout.text = "%d%%" % roundi(current * 100.0) if maximum <= 1.0 else "%.2f" % current
	refresh.call(value)
	slider.value_changed.connect(refresh)
	return slider
