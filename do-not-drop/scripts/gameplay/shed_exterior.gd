class_name ShedExterior
extends Node3D
## Draws the outside of the shed for its stage (expansion D-0936): a sign on top of the dock wall
## and the paved yard in front of the dock, from ShedExteriorPlan. Grey-box stand-in made of boxes;
## the final sign and yard models are a pending art task (docs/expansion-distritos/arte-pendiente).
## Only draws: no collision (the yard is where the vehicles park, and nothing here blocks the
## walkable shed), no state and no RPC. CompanyShed builds one per redraw and frees it with itself.

const SIGN_DEPTH: float = 0.25
const SIGN_POST: float = 0.2
const SLAB_THICKNESS: float = 0.1
const STRIPE_WIDTH: float = 0.18
const STRIPE_COLOR: Color = Color(0.85, 0.80, 0.30)
const LAMP_HEIGHT: float = 3.2
const LAMP_COLOR: Color = Color(1.0, 0.92, 0.78)
const POST_COLOR: Color = Color(0.25, 0.25, 0.27)
const SIGN_TEXT_COLOR: Color = Color(0.97, 0.95, 0.88)


## Builds the outside of a shed of `stage` whose floor is `floor_m` metres (X x Z), centred on the
## origin, with the dock on the +Z wall and `wall_height` as the shed's wall height.
static func build(stage: int, floor_m: Vector2, wall_height: float) -> ShedExterior:
	var exterior := ShedExterior.new()
	exterior.name = "Exterior"
	exterior._draw(stage, floor_m, wall_height)
	return exterior


func _draw(stage: int, floor_m: Vector2, wall_height: float) -> void:
	var front: float = floor_m.y * 0.5 + CompanyShed.WALL_THICKNESS
	_draw_sign(stage, floor_m, wall_height, front)
	_draw_yard(stage, floor_m, front)


func _draw_sign(stage: int, floor_m: Vector2, wall_height: float, front: float) -> void:
	var data: Dictionary = ShedExteriorPlan.variant(stage)
	var size: Vector2 = ShedExteriorPlan.sign_size(stage, floor_m.x)
	var centre_y: float = wall_height + size.y * 0.5 + 0.1
	var board := _box("Sign", Vector3(size.x, size.y, SIGN_DEPTH),
		Vector3(0.0, centre_y, front - CompanyShed.WALL_THICKNESS * 0.5), data["sign_color"])
	add_child(board)
	for side: float in [-1.0, 1.0]:
		var x: float = side * (size.x * 0.5 - SIGN_POST)
		add_child(_box("SignPost", Vector3(SIGN_POST, 0.2, SIGN_DEPTH), Vector3(x, wall_height + 0.05,
			front - CompanyShed.WALL_THICKNESS * 0.5), POST_COLOR))
	var label := Label3D.new()
	label.name = "SignText"
	label.text = tr(String(data["key"]))
	label.font_size = 96
	label.pixel_size = size.y * 0.55 / 96.0
	label.modulate = SIGN_TEXT_COLOR
	label.outline_size = 0
	label.position = Vector3(0.0, centre_y, front - CompanyShed.WALL_THICKNESS * 0.5 + SIGN_DEPTH * 0.5 + 0.01)
	add_child(label)


func _draw_yard(stage: int, floor_m: Vector2, front: float) -> void:
	var data: Dictionary = ShedExteriorPlan.variant(stage)
	var depth: float = ShedExteriorPlan.yard_depth(stage)
	var width: float = floor_m.x + 2.0 * CompanyShed.WALL_THICKNESS
	var centre_z: float = front + depth * 0.5
	add_child(_box("Yard", Vector3(width, SLAB_THICKNESS, depth),
		Vector3(0.0, -SLAB_THICKNESS * 0.5 - 0.01, centre_z), data["yard_color"]))
	if bool(data["stripes"]):
		var lanes: int = 3
		for i: int in lanes:
			var x: float = (float(i) + 0.5) / float(lanes) * width - width * 0.5
			add_child(_box("Stripe", Vector3(STRIPE_WIDTH, 0.01, depth - 1.0),
				Vector3(x, 0.005, centre_z), STRIPE_COLOR))
	for x: float in ShedExteriorPlan.lamp_xs(stage, floor_m.x):
		var post_z: float = front + 0.3
		add_child(_box("LampPost", Vector3(0.12, LAMP_HEIGHT, 0.12), Vector3(x, LAMP_HEIGHT * 0.5, post_z), POST_COLOR))
		add_child(_box("LampHead", Vector3(0.4, 0.12, 0.4), Vector3(x, LAMP_HEIGHT + 0.06, post_z), LAMP_COLOR))


## A visual-only box (no body, no collision).
static func _box(box_name: String, size: Vector3, centre: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = DepotKit.flat(color)
	instance.mesh = mesh
	instance.position = centre
	return instance
