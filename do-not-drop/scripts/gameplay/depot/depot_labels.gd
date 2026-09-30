class_name DepotLabels
extends RefCounted
## Text and signage for the depot: Label3D captions, paint on the floor,
## hanging signs and the flat arrows drawn on floors and signs. Stateless --
## every function takes the node to hang its result from.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")

## Hanging signs: caption size, and how long an arrow drawn on one is.
const SIGN_FONT_SIZE: int = 64
const SIGN_PIXEL: float = 0.0065
const SIGN_ARROW: float = 0.5
const SIGN_GAP: float = 0.18


static func text(parent: Node, value: String, at: Vector3, yaw: float, font_size: int, colour: Color,
		font: Font, pixel: float, outline: int) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font = font
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = colour
	label.outline_size = outline
	label.outline_modulate = Layout.INK
	label.position = at
	label.rotation.y = yaw
	label.double_sided = false
	parent.add_child(label)
	return label


## Paint on the floor, lying flat. yaw 0 reads for someone walking toward -Z
## (toward the door); -PI/2 for someone walking toward +X.
static func floor_text(parent: Node, value: String, at: Vector3, yaw: float, font_size: int, colour: Color) -> Label3D:
	# Clear of the painted lines (top at FLOOR_TOP + 0.006) and the workshop's
	# floor (+0.01): closer, the words flickered in and out of them.
	var label := text(parent, value, Vector3(at.x, Layout.FLOOR_TOP + 0.014, at.z), 0.0, font_size, colour,
		Layout.DISPLAY_FONT, 0.012, 0)
	label.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5)
	label.no_depth_test = false
	label.shaded = true
	return label


## Shrinks a label's font until its widest line fits `max_width` metres:
## captions come from the translation table, and a longer word in one
## language ran off the sign, poster or screen it was written on.
static func fit_label(label: Label3D, max_width: float) -> void:
	var font: Font = label.font if label.font != null else Layout.BODY_FONT
	var measured: float = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.font_size).x * label.pixel_size
	if measured > max_width and measured > 0.0:
		label.font_size = maxi(int(floor(label.font_size * max_width / measured)), 8)


## A flat arrow along `xform`'s +X: `length` long, `width` across the head,
## `thickness` deep along its Z.
static func arrow_shape(kit: DepotKit, xform: Transform3D, length: float, width: float, thickness: float,
		material: Material) -> void:
	var head_length: float = length * 0.45
	var shaft := BoxMesh.new()
	shaft.size = Vector3(length - head_length + 0.02, width * 0.36, thickness)
	kit.add_mesh(shaft, xform * Transform3D(Basis.IDENTITY, Vector3((0.02 - head_length) * 0.5, 0.0, 0.0)),
		material, false)
	var head := PrismMesh.new()
	head.size = Vector3(width, head_length, thickness)
	var head_at := Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3((length - head_length) * 0.5, 0.0, 0.0))
	kit.add_mesh(head, xform * head_at, material, false)


## An arrow painted on the floor at `at`, pointing along `direction`. Returns
## the guide it draws: {"caption", "at", "direction"} in depot space.
static func paint_arrow(kit: DepotKit, caption: String, at: Vector3, direction: Vector3, colour: Color,
		lift: float = 0.0) -> Dictionary:
	var flat := Basis(direction, Vector3.UP.cross(direction), Vector3.UP)
	arrow_shape(kit, Transform3D(flat, Vector3(at.x, Layout.FLOOR_TOP + 0.004 + lift, at.z)), 1.1, 0.62, 0.006,
		DepotKit.flat(colour, 0.7))
	return {"caption": caption, "at": Vector3(at.x, 0.0, at.z), "direction": direction}


## Hanging sign: a board on two cables with its caption on both faces. An
## arrow in the caption ("← ESTANTES", "CAMIÓN → PORTÓN") is drawn as a
## shape, not a glyph, and only on the front face (the one `yaw` turns toward
## +Z): read from behind it would point the wrong way, so the back just names
## the place. A sign hung under another stops its cables at `cable_top`.
## `size` scales the whole sign (N-319: each zone's own sign hangs smaller,
## over the zone; 1.0 is the size they all used to be).
## Every caption label is in the "depot_sign" group, tagged with the whole
## caption and its face (test_depot_signage).
static func hanging_sign(parent: Node, kit: DepotKit, caption: String, at: Vector3, yaw: float, colour: Color,
		cable_top: float = Layout.CEILING - 0.25, ink: Color = Layout.PAPER, size: float = 1.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var pixel: float = SIGN_PIXEL * size
	var tokens: Array = sign_tokens(caption)
	var words: PackedStringArray = []
	var widths: Array[float] = []
	var gap: float = SIGN_GAP * size
	var content: float = gap * (tokens.size() - 1)
	for token: Variant in tokens:
		var token_width: float = SIGN_ARROW * size
		if token is String:
			words.append(token)
			var measured: Vector2 = Layout.DISPLAY_FONT.get_string_size(
					token, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_FONT_SIZE)
			token_width = measured.x * pixel
		widths.append(token_width)
		content += token_width
	var width: float = content + 0.7 * size
	var height: float = 0.6 * size
	kit.box_xf(Vector3(width, height, 0.06), Transform3D(basis, at), DepotKit.flat(colour, 0.7))
	kit.box_xf(Vector3(width + 0.08, 0.06, 0.08), Transform3D(basis, at + Vector3(0.0, height * 0.5 + 0.03, 0.0)),
		DepotKit.flat(Color("e8ebe4"), 0.6))
	for side: float in [-0.4, 0.4]:
		var cable_at: Vector3 = at + basis * Vector3(side * width, 0.0, 0.0)
		var cable_mid := Vector3(cable_at.x, (cable_top + at.y + height * 0.5) * 0.5, cable_at.z)
		kit.box_xf(Vector3(0.015, cable_top - at.y - height * 0.5, 0.015), Transform3D(Basis.IDENTITY, cable_mid),
			DepotKit.flat(Color("263238"), 0.6))
	var cursor: float = -content * 0.5
	for index: int in range(tokens.size()):
		var centre: float = cursor + widths[index] * 0.5
		if tokens[index] is String:
			_sign_label(parent, tokens[index], at + basis * Vector3(centre, 0.0, 0.035), yaw, ink, caption, true, pixel)
		else:
			var turn := Basis(Vector3.BACK, PI if int(tokens[index]) < 0 else 0.0)
			arrow_shape(kit, Transform3D(basis * turn, at + basis * Vector3(centre, 0.0, 0.036)), SIGN_ARROW * size,
				0.34 * size, 0.012, DepotKit.unlit(ink))
		cursor += widths[index] + gap
	_sign_label(parent, "  ·  ".join(words), at + basis * Vector3(0.0, 0.0, -0.035), yaw + PI, ink, caption, false,
			pixel)


## "CAMIÓN → PORTÓN" -> ["CAMIÓN", 1, "PORTÓN"]: words, and -1 / 1 for
## arrows pointing left / right.
static func sign_tokens(caption: String) -> Array:
	var tokens: Array = []
	var word: String = ""
	for character: String in caption:
		if character != "←" and character != "→":
			word += character
			continue
		if not word.strip_edges().is_empty():
			tokens.append(word.strip_edges())
		tokens.append(-1 if character == "←" else 1)
		word = ""
	if not word.strip_edges().is_empty():
		tokens.append(word.strip_edges())
	return tokens


static func _sign_label(parent: Node, value: String, at: Vector3, yaw: float, ink: Color, caption: String,
		front: bool, pixel: float = SIGN_PIXEL) -> void:
	var label := text(parent, value, at, yaw, SIGN_FONT_SIZE, ink, Layout.DISPLAY_FONT, pixel, 10)
	label.add_to_group(&"depot_sign")
	label.set_meta(&"sign", caption)
	label.set_meta(&"front", front)
