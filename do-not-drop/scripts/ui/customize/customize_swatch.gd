extends Control
## The picture on a customisation card (N-506), drawn in code so it follows
## the face sheets and the palette with nothing to keep in sync: a patch of
## skin with the eyes (and their brows) or the mouth on it, a whole round face
## (a ready-made one: choice is its eyes, mouth its mouth), a T-shirt in a
## uniform's colour, or a van in a paint.

const Catalog = preload("res://scripts/core/face_catalog.gd")
## The rounded character's skin (sm_char_player_rounded.glb), so white eyes
## read as they do on the head.
const SKIN: Color = Color("f2c4a3")
const SKIN_EDGE: Color = Color("dfa684")

enum Kind { EYES, MOUTH, SHIRT, VAN, FACE }

var kind: Kind = Kind.EYES
var choice: StringName = &""
## FACE only: the mouth on the face (choice holds the eyes).
var mouth: StringName = &""
## SHIRT / VAN fill. A SHIRT with several colours is drawn in bands (the
## automatic team colour: whichever the host hands out).
var colors: Array[Color] = []


## Swatch.new().setup(...): what to draw. Returns itself to chain.
func setup(swatch_kind: Kind, id: StringName = &"", fill: Array[Color] = []) -> Control:
	kind = swatch_kind
	choice = id
	colors = fill
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 64)
	queue_redraw()
	return self


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	match kind:
		Kind.EYES, Kind.MOUTH:
			_draw_face()
		Kind.FACE:
			_draw_whole_face()
		Kind.SHIRT:
			_draw_shirt()
		Kind.VAN:
			_draw_van()


func _draw_face() -> void:
	var region: Rect2 = Catalog.THUMB_MOUTH if kind == Kind.MOUTH else Catalog.THUMB_EYES
	# The patch of skin keeps the sheet's proportions, as big as the card allows.
	var scale: float = minf(size.x / region.size.x, size.y / region.size.y)
	var area := Rect2(Vector2.ZERO, region.size * scale)
	area.position = (size - area.size) * 0.5
	var skin := StyleBoxFlat.new()
	skin.bg_color = SKIN
	skin.border_color = SKIN_EDGE
	skin.set_border_width_all(2)
	skin.set_corner_radius_all(int(minf(area.size.y * 0.32, 18.0)))
	skin.anti_aliasing = true
	draw_style_box(skin, area.grow(4.0))
	var layers: PackedStringArray = PackedStringArray(["mouth"]) if kind == Kind.MOUTH \
			else PackedStringArray(["brows", "eyes"])
	for layer: String in layers:
		var sheet: Texture2D = Catalog.texture(layer, choice)
		if sheet != null:
			draw_texture_rect_region(sheet, area, region)
	if choice == &"none":
		# "Nothing here", said on purpose: a bare patch reads as a broken card.
		var centre: Vector2 = area.get_center()
		var radius: float = area.size.y * 0.24
		var faint := Color(UiTheme.INK, 0.3)
		draw_arc(centre, radius, 0.0, TAU, 32, faint, 3.0, true)
		var slash := Vector2(radius, -radius).normalized() * radius
		draw_line(centre - slash, centre + slash, faint, 3.0, true)


## A round head with brows, eyes and mouth, as on the character.
func _draw_whole_face() -> void:
	var region: Rect2 = Catalog.THUMB_FACE
	var radius: float = minf(size.x, size.y) * 0.5 - 2.0
	var centre: Vector2 = size * 0.5
	draw_circle(centre, radius + 2.0, SKIN_EDGE, true, -1.0, true)
	draw_circle(centre, radius, SKIN, true, -1.0, true)
	# The features fill most of the circle, a touch high like on the head.
	var tall: float = radius * 1.7
	var area := Rect2(Vector2.ZERO, Vector2(tall * region.size.x / region.size.y, tall))
	area.position = centre - area.size * 0.5 - Vector2(0.0, radius * 0.04)
	for layer: Array in [["brows", choice], ["eyes", choice], ["mouth", mouth]]:
		var sheet: Texture2D = Catalog.texture(layer[0], layer[1])
		if sheet != null:
			draw_texture_rect_region(sheet, area, region)


## A boxy tee seen from the front: sleeves, collar, an ink outline.
func _draw_shirt() -> void:
	var h: float = minf(size.y * 0.92, size.x * 0.92 / 1.15)
	var w: float = h * 1.15
	var o := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)
	var points := PackedVector2Array()
	for p: Vector2 in [Vector2(0.30, 0.04), Vector2(0.42, 0.04), Vector2(0.50, 0.14), Vector2(0.58, 0.04),
			Vector2(0.70, 0.04), Vector2(0.98, 0.24), Vector2(0.86, 0.44), Vector2(0.76, 0.38),
			Vector2(0.76, 0.96), Vector2(0.24, 0.96), Vector2(0.24, 0.38), Vector2(0.14, 0.44),
			Vector2(0.02, 0.24)]:
		points.append(o + Vector2(p.x * w, p.y * h))
	var fill: Array[Color] = colors if not colors.is_empty() else [UiTheme.WHITE]
	if fill.size() == 1:
		draw_colored_polygon(points, fill[0])
	else:
		# Bands: clip each vertical strip of the tee against its outline.
		var band: float = w / fill.size()
		for index: int in fill.size():
			var strip := PackedVector2Array([o + Vector2(band * index, 0), o + Vector2(band * (index + 1), 0),
					o + Vector2(band * (index + 1), h), o + Vector2(band * index, h)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(points, strip):
				draw_colored_polygon(piece, fill[index])
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, UiTheme.INK, 2.5, true)


## A side-on delivery van: box, cab, window, two wheels.
func _draw_van() -> void:
	var h: float = minf(size.y * 0.8, size.x * 0.92 / 1.9)
	var w: float = h * 1.9
	var o := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)
	var paint: Color = colors[0] if not colors.is_empty() else UiTheme.WHITE
	var body := StyleBoxFlat.new()
	body.bg_color = paint
	body.border_color = UiTheme.INK
	body.set_border_width_all(2)
	body.anti_aliasing = true
	body.set_corner_radius_all(int(h * 0.1))
	draw_style_box(body, Rect2(o + Vector2(0, h * 0.08), Vector2(w * 0.68, h * 0.7)))
	body.corner_radius_top_right = int(h * 0.3)
	draw_style_box(body, Rect2(o + Vector2(w * 0.64, h * 0.28), Vector2(w * 0.34, h * 0.5)))
	var glass := StyleBoxFlat.new()
	glass.bg_color = UiTheme.SKY.lightened(0.45)
	glass.border_color = UiTheme.INK
	glass.set_border_width_all(2)
	glass.corner_radius_top_right = int(h * 0.18)
	glass.anti_aliasing = true
	draw_style_box(glass, Rect2(o + Vector2(w * 0.74, h * 0.34), Vector2(w * 0.17, h * 0.18)))
	for x: float in [0.2, 0.8]:
		var centre: Vector2 = o + Vector2(w * x, h * 0.8)
		draw_circle(centre, h * 0.15, UiTheme.INK, true, -1.0, true)
		draw_circle(centre, h * 0.06, Color("c9ccd3"), true, -1.0, true)
