class_name RouteProps
extends RefCounted
## Build primitives for the route's own set pieces (start line and sign, the
## goal arch, house numbers): boxes, route boards and floating labels, each
## hung from the node it's given. Materials are shared by colour.

## One material per colour, for the whole session.
static var _materials: Dictionary = {}

const RouteScript = preload("res://scripts/gameplay/route/route.gd")
const SIGN_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const SIGN_BOARD_SIZE := Vector2(4.6, 1.4)


static func box(parent: Node3D, node_name: String, size: Vector3, location: Vector3, color: Color,
		solid: bool = false) -> Node3D:
	return box_at(parent, node_name, size, Transform3D(Basis.IDENTITY, location), color, solid)


static func box_at(parent: Node3D, node_name: String, size: Vector3, transform_: Transform3D, color: Color,
		solid: bool = false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.name = node_name
	root.transform = transform_
	parent.add_child(root)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = material(color)
	root.add_child(mesh)
	if solid:
		var body := root as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 6
		var collider := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collider.shape = box_shape
		body.add_child(collider)
	return root


## A route board: the first caption line is the big title, the rest a
## smaller message wrapped to the board's width, both in the game's cartoon
## display font. The post stands behind the board (text faces +Z), so it
## never shows through the face.
## `ground_y` is the terrain height under it, in the parent's space.
static func sign(parent: Node3D, node_name: String, caption: String, location: Vector3, ground_y: float,
		accent: Color) -> void:
	var board_center_y: float = ground_y + 2.65
	var board_top: float = board_center_y + SIGN_BOARD_SIZE.y * 0.5
	box(parent, node_name + "Post", Vector3(0.16, board_top - 0.1 - ground_y, 0.16),
			location + Vector3(0.0, ground_y + (board_top - 0.1 - ground_y) * 0.5, -0.15), RouteScript.CONCRETE, true)
	box(parent, node_name + "Board", Vector3(SIGN_BOARD_SIZE.x, SIGN_BOARD_SIZE.y, 0.12),
			location + Vector3(0.0, board_center_y, 0.0), Color("263b3e"))
	box(parent, node_name + "Stripe", Vector3(SIGN_BOARD_SIZE.x, 0.10, 0.13),
			location + Vector3(0.0, board_top - 0.05, 0.0), accent)
	var lines: PackedStringArray = caption.split(RouteScript.NEWLINE, false, 1)
	var title: String = lines[0]
	var message: String = lines[1].replace(" -- ", " · ") if lines.size() > 1 else ""
	var face_z: float = 0.075
	if message.is_empty():
		_sign_text(parent, node_name + "Title", title, location + Vector3(0.0, board_center_y - 0.03, face_z), 84,
				RouteScript.MARKING)
	else:
		_sign_text(parent, node_name + "Title", title, location + Vector3(0.0, board_center_y + 0.26, face_z), 76,
				RouteScript.MARKING)
		_sign_text(parent, node_name + "Text", message, location + Vector3(0.0, board_center_y - 0.26, face_z), 44,
				accent.lerp(RouteScript.MARKING, 0.35))


static func _sign_text(parent: Node3D, node_name: String, text: String, location: Vector3, font_size: int,
		color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = SIGN_FONT
	label.font_size = font_size
	label.pixel_size = 0.0055
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color("16252a")
	# Wraps inside the board with a margin instead of running off its edges.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = (SIGN_BOARD_SIZE.x - 0.4) / label.pixel_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = location
	parent.add_child(label)


static func label(parent: Node3D, node_name: String, caption: String, location: Vector3, pixel_size: float,
		color: Color, face_camera: bool = false) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = caption
	label.position = location
	label.font_size = 48
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 4
	label.outline_modulate = Color("1e3035")
	# Free-floating labels (house numbers) turn to the camera around Y: the
	# road bends, so a fixed facing read backwards ("1 ASAC") from half the
	# approaches. Text printed on a board must not -- it would swing out in
	# front of its own board and get cut by it ("SAL...erpentea").
	if face_camera:
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	parent.add_child(label)


static func material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		# Back faces culled: double-sided, the underside of every flat marking
		# z-fought the terrain a few millimetres below it (flicker) and box
		# sides shadowed themselves in fine stripes.
		_materials[color] = material
	return _materials[color] as StandardMaterial3D
