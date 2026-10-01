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
## Cells of the pictogram atlas (DepotKit.PICTOGRAMS), row by row.
const ICON_HELMET: int = 0
const ICON_VEST: int = 1
const ICON_SPEED: int = 2
const ICON_EXIT: int = 3
const ICON_EXTINGUISHER: int = 4
const ICON_FIRST_AID: int = 5
const ICON_MEETING: int = 6
const ICON_FORKLIFT: int = 7
const ICON_HANDS: int = 8
const ICON_NO_SMOKING: int = 9
const ICON_ELECTRIC: int = 10
const ICON_EVACUATION: int = 11
const ICON_WRENCH: int = 12
const ICON_OPEN_BOX: int = 13
const ICON_HANGER: int = 14
const ICON_PHONE: int = 15
## The zone-coloured tab's share of a hanging sign's width.
const TAB_SHARE: float = 0.25


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


## An arrow painted on the floor at `at`, pointing along `direction`. `length`
## is its size (the head's width follows it); `lift` raises it over the paint
## already there (the walkways' white edges). It is one flat opaque piece in the
## same finish as the floor's paint (the detail grain, shadows), not a see-through
## box: a translucent one drew without the floor's grain and read as hovering.
## Returns the guide it draws: {"caption", "at", "direction"} in depot space.
static func paint_arrow(kit: DepotKit, caption: String, at: Vector3, direction: Vector3, colour: Color,
		lift: float = 0.0, length: float = 1.1) -> Dictionary:
	# Along the floor: a place's station is up in the air, and an arrow aimed at it pitched
	# its tip up and its tail into the concrete (it read as hovering, half sunk).
	var heading := Vector3(direction.x, 0.0, direction.z).normalized()
	var flat := Basis(heading, Vector3.UP, heading.cross(Vector3.UP))
	kit.add_mesh(flat_arrow_mesh(length, length * 0.5636), Transform3D(flat,
			Vector3(at.x, Layout.FLOOR_TOP + ARROW_PAINT_HEIGHT + lift, at.z)),
			DepotKit.detailed(colour, "plaster", 1.5, 0.7), false)
	return {"caption": caption, "at": Vector3(at.x, 0.0, at.z), "direction": heading}


## Height of a painted arrow over the floor's slab at lift 0: over the bay's slab (4 mm).
const ARROW_PAINT_HEIGHT: float = 0.007
static var _flat_arrows: Dictionary = {}


## The arrow as a single flat piece in the XZ plane, pointing along +X, facing up:
## a shaft and a triangular head, as arrow_shape() makes them, with nothing to
## overlap or fight with itself.
static func flat_arrow_mesh(length: float, width: float) -> ArrayMesh:
	var key: String = "%.3f|%.3f" % [length, width]
	if _flat_arrows.has(key):
		return _flat_arrows[key]
	var head_length: float = length * 0.45
	var neck: float = length * 0.5 - head_length
	var half_shaft: float = width * 0.18
	var half_head: float = width * 0.5
	var tail: float = -length * 0.5
	# Clockwise seen from above (+Y): Godot's front faces. Points are (x, z).
	var triangles: Array[Vector2] = [
		Vector2(tail, -half_shaft), Vector2(neck, -half_shaft), Vector2(tail, half_shaft),
		Vector2(neck, -half_shaft), Vector2(neck, half_shaft), Vector2(tail, half_shaft),
		Vector2(neck, -half_head), Vector2(length * 0.5, 0.0), Vector2(neck, half_head),
	]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for point: Vector2 in triangles:
		tool.add_vertex(Vector3(point.x, 0.0, point.y))
	var mesh: ArrayMesh = tool.commit()
	_flat_arrows[key] = mesh
	return mesh


## Hanging sign, one design for every zone (N-319): a shipping label. A dark
## INK plate on two cables, the caption in PAPER on both faces, and at the left
## a tab in the zone's colour (a quarter of the sign) with a round slot for the
## zone's pictogram -- an empty disc until the pictogram atlas exists -- and a
## dashed tear line between the two. An arrow in the caption ("← ESTANTES",
## "CAMIÓN → PORTÓN") is drawn as a shape, not a glyph, and only on the front
## face (the one `yaw` turns toward +Z): read from behind it would point the
## wrong way, so the back just names the place. A sign hung under another stops
## its cables at `cable_top`. `colour` is the zone's colour (the tab), `ink` the
## caption's; `size` scales the whole sign (1.0 is the size they all used to be);
## `icon` is the zone's pictogram (an ICON_* cell of the atlas; none keeps the empty disc).
## Every caption label is in the "depot_sign" group, tagged with the whole
## caption and its face (test_depot_signage).
static func hanging_sign(parent: Node, kit: DepotKit, caption: String, at: Vector3, yaw: float, colour: Color,
		cable_top: float = Layout.CEILING - 0.25, ink: Color = Layout.PAPER, size: float = 1.0,
		icon: int = -1) -> void:
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
	# The tab is a quarter of the sign, the caption sits in the rest.
	var height: float = 0.6 * size
	var body: float = content + 0.5 * size
	var width: float = maxf(body / (1.0 - TAB_SHARE), height * 2.0)
	var tab: float = width * TAB_SHARE
	var body_centre: float = tab * 0.5
	var tab_at: Vector3 = at + basis * Vector3(-width * 0.5 + tab * 0.5, 0.0, 0.0)
	kit.box_xf(Vector3(width, height, 0.06), Transform3D(basis, at), DepotKit.flat(Layout.INK, 0.7))
	kit.box_xf(Vector3(tab, height, 0.07), Transform3D(basis, tab_at), DepotKit.unlit(colour))
	kit.box_xf(Vector3(width + 0.08, 0.05, 0.08), Transform3D(basis, at + Vector3(0.0, height * 0.5 + 0.025, 0.0)),
			DepotKit.flat(Color("3b4c53"), 0.5, 0.4))
	# The pictogram in the tab, on both faces (ink on the light tabs, paper on the dark ones).
	var slot: float = minf(tab, height) * 0.36
	if icon >= 0:
		var tint: Color = Layout.INK if colour.get_luminance() > 0.55 else Layout.PAPER
		pictogram(kit, icon, Transform3D(basis, tab_at + basis * Vector3(0.0, 0.0, 0.039)), slot * 2.0, tint)
		pictogram(kit, icon, Transform3D(basis * Basis(Vector3.UP, PI), tab_at + basis * Vector3(0.0, 0.0, -0.039)),
				slot * 2.0, tint)
	else:
		var face_turn: Basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
		kit.cylinder(slot, 0.078, Transform3D(face_turn, tab_at), DepotKit.flat(Layout.PAPER, 0.6), 16)
	# The tear line: short dashes where the tab meets the body.
	for dash: int in range(5):
		var y: float = (dash - 2) * height * 0.17
		kit.box_xf(Vector3(0.012, height * 0.09, 0.066), Transform3D(basis,
				at + basis * Vector3(-width * 0.5 + tab, y, 0.0)), DepotKit.flat(Layout.PAPER, 0.7))
	for side: float in [-0.4, 0.4]:
		var cable_at: Vector3 = at + basis * Vector3(side * width, 0.0, 0.0)
		var cable_mid := Vector3(cable_at.x, (cable_top + at.y + height * 0.5) * 0.5, cable_at.z)
		kit.box_xf(Vector3(0.015, cable_top - at.y - height * 0.5, 0.015), Transform3D(Basis.IDENTITY, cable_mid),
			DepotKit.flat(Color("263238"), 0.6))
	var cursor: float = body_centre - content * 0.5
	for index: int in range(tokens.size()):
		var centre: float = cursor + widths[index] * 0.5
		if tokens[index] is String:
			_sign_label(parent, tokens[index], at + basis * Vector3(centre, 0.0, 0.037), yaw, ink, caption, true, pixel)
		else:
			var turn := Basis(Vector3.BACK, PI if int(tokens[index]) < 0 else 0.0)
			arrow_shape(kit, Transform3D(basis * turn, at + basis * Vector3(centre, 0.0, 0.038)), SIGN_ARROW * size,
				0.34 * size, 0.012, DepotKit.unlit(ink))
		cursor += widths[index] + gap
	_sign_label(parent, "  ·  ".join(words), at + basis * Vector3(body_centre, 0.0, -0.037), yaw + PI, ink, caption,
			false, pixel)


## A pictogram from the atlas: a `size` square facing +Z of `xform`, tinted `colour`,
## folded into the kit's shared pictogram batch.
static func pictogram(kit: DepotKit, cell: int, xform: Transform3D, size: float, colour: Color = Layout.PAPER) -> void:
	var u0: float = (cell % 4) * 0.25
	var v0: float = (cell / 4) * 0.25
	var half: float = size * 0.5
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector2] = [Vector2(-half, half), Vector2(half, half), Vector2(half, -half),
			Vector2(-half, -half)]
	var uvs: Array[Vector2] = [Vector2(u0, v0), Vector2(u0 + 0.25, v0), Vector2(u0 + 0.25, v0 + 0.25),
			Vector2(u0, v0 + 0.25)]
	tool.set_color(colour)
	tool.set_normal(Vector3.BACK)
	for index: int in [0, 1, 2, 0, 2, 3]:
		tool.set_uv(uvs[index])
		tool.add_vertex(Vector3(corners[index].x, corners[index].y, 0.0))
	kit.add_mesh(tool.commit(), xform, DepotKit.pictograms(), false)


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
