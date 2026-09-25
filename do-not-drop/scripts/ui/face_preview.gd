extends Control
## Same feature textures as CharacterFace, composed on a front-facing 2D head.
const Catalog = preload("res://scripts/presentation/face_catalog.gd")
var eyes_id: StringName = Catalog.DEFAULT_EYES
var mouth_id: StringName = Catalog.DEFAULT_MOUTH
var shirt_color: Color = Color("f4c562")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_expression(eyes: StringName, mouth: StringName) -> void:
	eyes_id = Catalog.valid_eyes(eyes)
	mouth_id = Catalog.valid_mouth(mouth)
	queue_redraw()

func _draw() -> void:
	var diameter: float = minf(size.x * 0.85, size.y * 0.84)
	var center := Vector2(size.x * 0.5, size.y * 0.45)
	var radius: float = diameter * 0.5
	draw_circle(center + Vector2(0, radius * 0.95), radius * 0.58, shirt_color, true, -1, true)
	draw_circle(center + Vector2(0, 5), radius, Color("dbc1a0"), true, -1, true)
	draw_circle(center, radius, Color("f2c4a3"), true, -1, true)
	draw_arc(center, radius, 0, TAU, 96, Color("dba987"), 2.0, true)
	# Match the angular patch's coverage on the actual ellipsoidal head.
	var features := Rect2(center - Vector2(diameter * 0.44, diameter * 0.37), Vector2(diameter * 0.88, diameter * 0.74))
	draw_texture_rect(Catalog.texture("eyes", eyes_id), features, false)
	draw_texture_rect(Catalog.texture("mouth", mouth_id), features, false)
