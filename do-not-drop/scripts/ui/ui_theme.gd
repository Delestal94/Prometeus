class_name UiTheme
extends RefCounted
## The one place the interface's colours, fonts and widgets are defined.
##
## Every screen builds from here, so a change to the brand is a change to
## this file (docs/direccion-visual.md section 3).
##
## Look (2026-09-23): "shipping label". Cream cards with a thick ink outline
## and a hard offset shadow, like a sticker slapped on a box; coloured tape
## strips for headings; chunky buttons that sink when pressed; a rounded,
## heavy display face (Lilita One) for titles and numbers and Nunito for
## everything else. Playful because the game is about a van losing its
## cargo; professional because it is one consistent system -- one palette,
## one outline weight, one corner radius, one type scale.
##
## A RefCounted with static members on purpose: nothing here has state worth
## a node in the tree. Fonts and the Theme are built once and cached.

# --- Palette ----------------------------------------------------------------
## Names kept from the old dark theme so every caller still compiles; the
## roles moved: panels are cream now, so text on them is INK.
const INK: Color = Color("1e2235")        # outlines, text on cards, shadows
const PAPER: Color = Color("fff6e6")      # card fill; light text over the 3D view
const MUTED: Color = Color("857a6e")      # secondary text on cream
const MINT: Color = Color("2dd4a3")       # go / OK / primary action
const YELLOW: Color = Color("ffc93c")     # tape, money, warnings
const RED: Color = Color("ff5e5b")        # danger, ruined, errors
const SKY: Color = Color("4cc9f0")        # info, focus ring, network
const ORANGE: Color = Color("ff9f1c")     # at risk
const GRAPE: Color = Color("9b5de5")      # special: Steam, records, events
const CARDBOARD: Color = Color("e0a867")  # the brand's box colour
const WHITE: Color = Color("fffdf8")
## Text on cards, and the old names still used by a few callers.
const TEXT: Color = INK
const BORDER: Color = INK
const SURFACE: Color = WHITE
const BACKDROP: Color = Color("16324f")

const CORNER_RADIUS: int = 16
const OUTLINE: int = 3
const SHADOW: int = 6
const BUTTON_HEIGHT: int = 50

const DISPLAY_FONT_PATH: String = "res://assets/fonts/LilitaOne-Regular.ttf"
const BODY_FONT_PATH: String = "res://assets/fonts/Nunito-Variable.ttf"
## OpenType tag 'wght' as the integer FontVariation expects.
const WGHT: int = 0x77676874

static var _display_font: Font
static var _body_fonts: Dictionary = {}
static var _theme: Theme


# --- Fonts & theme ----------------------------------------------------------

## Lilita One: titles, numbers, buttons -- the voice of the brand.
static func display_font() -> Font:
	if _display_font == null:
		_display_font = load(DISPLAY_FONT_PATH)
	return _display_font


## Nunito at a given weight (400 regular ... 900 black).
static func body_font(weight: int = 700) -> Font:
	if not _body_fonts.has(weight):
		var variation := FontVariation.new()
		variation.base_font = load(BODY_FONT_PATH)
		variation.variation_opentype = {WGHT: weight}
		_body_fonts[weight] = variation
	return _body_fonts[weight]


## The shared Theme: Nunito Bold everywhere by default, ink text. Set it on
## each screen's root Control; every child inherits it.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = body_font(700)
		_theme.default_font_size = 17
		for type_name: String in ["Label", "Button", "LineEdit", "CheckBox", "RichTextLabel"]:
			_theme.set_color("font_color", type_name, INK)
		_theme.set_color("default_color", "RichTextLabel", INK)
	return _theme


static func apply(control: Control) -> void:
	control.theme = theme()


# --- Cards ------------------------------------------------------------------

## A cream sticker card. Returns the column to fill, not the panel itself:
## every caller wants to append to it.
static func panel(parent: Node, minimum_size: Vector2 = Vector2.ZERO, padding: int = 22, fill: Color = PAPER) -> VBoxContainer:
	var container := PanelContainer.new()
	container.custom_minimum_size = minimum_size
	container.add_theme_stylebox_override("panel", surface_style(padding, fill))
	parent.add_child(container)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	container.add_child(column)
	return column


static func surface_style(padding: int = 22, fill: Color = PAPER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = INK
	style.set_border_width_all(OUTLINE)
	style.set_corner_radius_all(CORNER_RADIUS)
	# The hard offset shadow is the "sticker" in the look: no blur, pure ink.
	style.shadow_color = INK
	style.shadow_size = 1
	style.shadow_offset = Vector2(0, SHADOW)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = int(padding * 0.8)
	style.content_margin_bottom = int(padding * 0.8) + 2
	style.anti_aliasing = true
	return style


static func label(parent: Node, text: String, font_size: int, color: Color = INK, display: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	if display:
		node.add_theme_font_override("font", display_font())
	parent.add_child(node)
	return node


## A big display-face heading.
static func title(parent: Node, text: String, font_size: int, color: Color = INK) -> Label:
	return label(parent, text, font_size, color, true)


## A strip of coloured tape with a short caps label: section headings,
## modes, states. `tilt` in degrees -- tape is never stuck on quite straight.
static func tag(parent: Node, text: String, color: Color = YELLOW, tilt: float = -2.0, font_size: int = 14) -> Label:
	var holder := PanelContainer.new()
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	holder.add_theme_stylebox_override("panel", style)
	_add_tilted(parent, holder, tilt)
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", display_font())
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", INK)
	holder.add_child(node)
	return node


## A rounded pill with a value in it (time, money, players).
static func chip(parent: Node, text: String, color: Color = WHITE, font_size: int = 16) -> Label:
	var holder := PanelContainer.new()
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(99)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	holder.add_theme_stylebox_override("panel", style)
	parent.add_child(holder)
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", display_font())
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", INK)
	holder.add_child(node)
	return node


## The game's logo, built from type so it scales and localises: "TAKE MY"
## over "PACKAGE" on a strip of yellow tape, both slightly off-kilter.
static func logo(parent: Node, size: int = 64) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -int(size * 0.18))
	parent.add_child(column)
	var top_holder := MarginContainer.new()
	_add_tilted(column, top_holder, -3.0)
	_logo_line(top_holder, "TAKE MY", size, PAPER)
	var tape := PanelContainer.new()
	tape.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = YELLOW
	style.border_color = INK
	style.set_border_width_all(OUTLINE)
	style.set_corner_radius_all(6)
	style.shadow_color = INK
	style.shadow_size = 1
	style.shadow_offset = Vector2(0, SHADOW)
	style.content_margin_left = int(size * 0.22)
	style.content_margin_right = int(size * 0.22)
	style.content_margin_top = int(size * 0.02)
	style.content_margin_bottom = int(size * 0.06)
	tape.add_theme_stylebox_override("panel", style)
	_add_tilted(column, tape, -2.0)
	_logo_line(tape, "PACKAGE", int(size * 1.1), INK, false)
	return column


static func _logo_line(parent: Node, text: String, size: int, color: Color, outlined: bool = true) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", display_font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if outlined:
		node.add_theme_color_override("font_outline_color", INK)
		node.add_theme_constant_override("outline_size", maxi(8, size / 6))
		node.add_theme_color_override("font_shadow_color", INK)
		node.add_theme_constant_override("shadow_offset_x", 0)
		node.add_theme_constant_override("shadow_offset_y", maxi(4, size / 12))
		node.add_theme_constant_override("shadow_outline_size", maxi(8, size / 6))
	parent.add_child(node)
	return node


## Adds `child` to `parent` rotated by `degrees` around its own centre.
## Containers reset a child's rotation every time they lay it out, so the
## tilted piece sits inside a plain Control that only reserves its space (and
## keeps reserving the right amount when the text inside changes).
static func _add_tilted(parent: Node, child: Control, degrees: float) -> void:
	if is_zero_approx(degrees):
		parent.add_child(child)
		return
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.size_flags_horizontal = child.size_flags_horizontal
	parent.add_child(wrapper)
	wrapper.add_child(child)
	child.rotation_degrees = degrees
	var sync: Callable = func() -> void:
		var needed: Vector2 = child.get_combined_minimum_size()
		wrapper.custom_minimum_size = needed
		child.size = needed
		child.pivot_offset = needed * 0.5
	child.minimum_size_changed.connect(sync)
	sync.call()


# --- Buttons & inputs -------------------------------------------------------

## Chunky sticker buttons. `primary` is mint; the rest are white. Pressing
## sinks the button onto its own shadow; focus (gamepad) gets a sky ring.
static func button(parent: Node, text: String, primary: bool = false, minimum_size: Vector2 = Vector2(0, BUTTON_HEIGHT), color: Color = Color.TRANSPARENT) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = minimum_size
	node.add_theme_font_override("font", display_font())
	node.add_theme_font_size_override("font_size", 21)
	var fill: Color = color if color.a > 0.0 else (MINT if primary else WHITE)
	var normal: StyleBoxFlat = _button_style(fill, SHADOW)
	node.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = _button_style(fill.lightened(0.14), SHADOW)
	node.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = _button_style(fill.darkened(0.06), 1)
	pressed.content_margin_top += SHADOW - 1
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("hover_pressed", pressed)
	# Focus is its own look, not hover's: a gamepad user has no cursor, so
	# "where am I" has to be visible without one.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = SKY
	focus.set_border_width_all(4)
	focus.set_corner_radius_all(CORNER_RADIUS + 4)
	focus.set_expand_margin_all(5)
	focus.expand_margin_bottom = 5 + SHADOW
	node.add_theme_stylebox_override("focus", focus)
	var disabled: StyleBoxFlat = _button_style(Color(fill, 0.45), 2)
	disabled.border_color = Color(INK, 0.4)
	node.add_theme_stylebox_override("disabled", disabled)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		node.add_theme_color_override(state, INK)
	node.add_theme_color_override("font_disabled_color", Color(INK, 0.4))
	parent.add_child(node)
	return node


static func _button_style(fill: Color, shadow: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = INK
	style.set_border_width_all(OUTLINE)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.shadow_color = INK
	style.shadow_size = 1
	style.shadow_offset = Vector2(0, shadow)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	style.anti_aliasing = true
	return style


## Text floating over the 3D view with no card behind it (prompts, pings,
## banners): a thick ink outline keeps it readable against a bright sky.
static func floating_label(parent: Node, text: String, font_size: int, color: Color, width: float, top: float) -> Label:
	var node: Label = label(parent, text, font_size, color, true)
	node.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	node.offset_left = -width * 0.5
	node.offset_right = width * 0.5
	node.offset_top = top
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_color_override("font_outline_color", INK)
	node.add_theme_constant_override("outline_size", 10)
	node.add_theme_color_override("font_shadow_color", INK)
	node.add_theme_constant_override("shadow_offset_y", 3)
	node.add_theme_constant_override("shadow_outline_size", 10)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## A text field that matches the buttons next to it.
static func line_edit(parent: Node, placeholder: String) -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.custom_minimum_size.y = BUTTON_HEIGHT
	node.add_theme_font_size_override("font_size", 17)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.8))
	node.add_theme_color_override("caret_color", INK)
	var style := StyleBoxFlat.new()
	style.bg_color = WHITE
	style.border_color = INK
	style.set_border_width_all(OUTLINE)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	node.add_theme_stylebox_override("normal", style)
	var focus: StyleBoxFlat = style.duplicate()
	focus.border_color = SKY
	focus.set_border_width_all(4)
	node.add_theme_stylebox_override("focus", focus)
	parent.add_child(node)
	return node


static func check_box(parent: Node, text: String, pressed: bool) -> CheckBox:
	var node := CheckBox.new()
	node.text = text
	node.button_pressed = pressed
	node.add_theme_font_size_override("font_size", 16)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		node.add_theme_color_override(state, INK)
	node.add_theme_stylebox_override("focus", _focus_ring())
	node.add_theme_icon_override("unchecked", _box_icon(false))
	node.add_theme_icon_override("checked", _box_icon(true))
	parent.add_child(node)
	return node


## Toggles drawn in code, so there's no texture to keep in sync with the
## palette: an ink-outlined white box when off, a mint box with an ink
## check-block when on.
static func _box_icon(checked: bool) -> ImageTexture:
	var size: int = 24
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y: int in size:
		for x: int in size:
			var edge: bool = x < 3 or y < 3 or x >= size - 3 or y >= size - 3
			if edge:
				image.set_pixel(x, y, INK)
			elif checked and x >= 7 and y >= 7 and x < size - 7 and y < size - 7:
				image.set_pixel(x, y, INK)
			else:
				image.set_pixel(x, y, MINT if checked else WHITE)
	return ImageTexture.create_from_image(image)


static func _focus_ring() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = SKY
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_expand_margin_all(4)
	return style


## A chunky progress bar: ink-outlined track, coloured fill.
static func bar(parent: Node, color: Color, height: int = 14) -> ProgressBar:
	var node := ProgressBar.new()
	node.custom_minimum_size.y = height
	node.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color("e8dcc8")
	background.border_color = INK
	background.set_border_width_all(2)
	background.set_corner_radius_all(height)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.border_color = INK
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(height)
	node.add_theme_stylebox_override("background", background)
	node.add_theme_stylebox_override("fill", fill)
	parent.add_child(node)
	return node


## A labelled slider row, with the current value spelled out.
static func slider_row(parent: Node, text: String, minimum: float, maximum: float, step: float, value: float, percent: bool = false) -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var header := HBoxContainer.new()
	row.add_child(header)
	var caption: Label = label(header, text, 16, INK)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout: Label = label(header, "", 18, INK, true)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 26
	var track := StyleBoxFlat.new()
	track.bg_color = Color("e8dcc8")
	track.border_color = INK
	track.set_border_width_all(2)
	track.set_corner_radius_all(8)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var filled: StyleBoxFlat = track.duplicate()
	filled.bg_color = MINT
	slider.add_theme_stylebox_override("grabber_area", filled)
	var filled_hover: StyleBoxFlat = filled.duplicate()
	filled_hover.bg_color = MINT.lightened(0.12)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled_hover)
	slider.add_theme_icon_override("grabber", _knob(false))
	slider.add_theme_icon_override("grabber_highlight", _knob(true))
	slider.add_theme_stylebox_override("focus", _focus_ring())
	row.add_child(slider)
	var refresh: Callable = func(current: float) -> void:
		readout.text = "%d%%" % roundi(current * 100.0) if percent or maximum <= 1.0 else "%.2f" % current
	refresh.call(value)
	slider.value_changed.connect(refresh)
	return slider


static func _knob(highlight: bool) -> ImageTexture:
	var size: int = 26
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := Vector2(size, size) * 0.5
	for y: int in size:
		for x: int in size:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(centre)
			if d <= size * 0.5 - 0.5:
				image.set_pixel(x, y, INK if d > size * 0.5 - 3.5 else (YELLOW if highlight else WHITE))
	return ImageTexture.create_from_image(image)


# --- Rich text helpers ------------------------------------------------------

## "KEY  action   ·   KEY  action" (the format every hint line uses) turned
## into BBCode with each key drawn as a little ink keycap.
static func keycaps(line: String, on_dark: bool = false) -> String:
	var items: PackedStringArray = []
	for item: String in line.split("   ·   "):
		var parts: PackedStringArray = item.split("  ", false, 1)
		if parts.size() == 2:
			# Keycaps invert on a dark pill so they stay visible on it.
			var cap: Color = PAPER if on_dark else INK
			var glyph: Color = INK if on_dark else PAPER
			items.append("[bgcolor=#%s][color=#%s] %s [/color][/bgcolor] %s" % [cap.to_html(false), glyph.to_html(false), parts[0], parts[1]])
		else:
			items.append(item)
	var separator: String = "   [color=#%s]•[/color]   " % (PAPER if on_dark else MUTED).to_html(false)
	return separator.join(items)


## Trap display name (as the HUD receives it) -> its icon, if there is one.
static func trap_icon(display_name: String) -> Texture2D:
	var ids: Dictionary = {"FRÁGIL": "fragile", "EQUILIBRIO": "balance", "PESO CRECIENTE": "growing_weight", "RUIDOSO": "noisy"}
	var id: String = ids.get(display_name.to_upper(), "")
	if id.is_empty():
		return null
	return load("res://assets/ui/icons/tx_ui_trap_%s_256.png" % id)
