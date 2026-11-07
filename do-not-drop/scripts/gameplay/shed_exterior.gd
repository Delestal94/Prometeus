class_name ShedExterior
extends Node3D
## Draws the outside of the shed for its stage (expansion D-0936): a sign on top of the dock wall and the paved yard
## in front of the dock, from ShedExteriorPlan. The sign, the yard's paint and the lamps are the models of
## assets/tools/build_depot_props.py (group shed_exterior); the slab is a box here, so it always measures what the
## plan says, and the name is a Label3D, so it follows the language.
## Only draws: no collision (the yard is where the vehicles park, and nothing here blocks the
## walkable shed), no state and no RPC. CompanyShed builds one per redraw and frees it with itself.

const SIGN_DEPTH: float = 0.25
const SIGN_FONT_SIZE: int = 96
const SIGN_TEXT_COLOR: Color = Color(0.97, 0.95, 0.88)
## The name's capitals take about this share of the font size, so its line fills its area's height.
const SIGN_TEXT_HEIGHT: float = 0.85
const SLAB_THICKNESS: float = 0.1
## Under the floor and the road (y = 0), far enough that the road laid over the bigger yards never flickers with it.
const SLAB_TOP: float = -0.03
const LAMP_HEIGHT: float = 3.2
const LAMP_COLOR: Color = Color(1.0, 0.92, 0.78)
const LAMP_POST_OFFSET: float = 0.3
## Warm pool on the yard under each lamp's head, instead of a real light per lamp (DepotKit.light_pool).
const LAMP_POOL_COLOR: Color = Color(0.20, 0.15, 0.08)
const LAMP_POOL_SIZE: float = 4.4
const LAMP_POOL_REACH: float = 1.1
const LAMP_POOL_HEIGHT: float = 0.02


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
	var fit: float = ShedExteriorPlan.sign_size(stage, floor_m.x).x / (data["sign"] as Vector2).x
	var wall_middle: float = front - CompanyShed.WALL_THICKNESS * 0.5
	var board := _model("Sign", "sm_env_shed_sign_%s" % data["model"], Vector3(0.0, wall_height, wall_middle))
	board.scale.x = fit
	add_child(board)
	var area: Rect2 = data["text"]
	var label := Label3D.new()
	label.name = "SignText"
	label.text = tr(String(data["key"]))
	UiTheme.label_3d(label, SIGN_FONT_SIZE)
	label.pixel_size = _fitted_pixel(label, area.size * Vector2(fit, 1.0))
	label.modulate = SIGN_TEXT_COLOR
	label.outline_size = 0
	label.position = Vector3(area.get_center().x * fit, wall_height + area.get_center().y,
		wall_middle + SIGN_DEPTH * 0.5 + 0.01)
	add_child(label)


## Metres per font pixel that fit `label`'s text in one line inside `area` (metres): as tall as the area
## lets it, narrower if the language's name would run off the sign.
static func _fitted_pixel(label: Label3D, area: Vector2) -> float:
	var wide: float = label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	return minf(area.y * SIGN_TEXT_HEIGHT / float(label.font_size), area.x / maxf(wide, 1.0))


func _draw_yard(stage: int, floor_m: Vector2, front: float) -> void:
	var data: Dictionary = ShedExteriorPlan.variant(stage)
	var depth: float = ShedExteriorPlan.yard_depth(stage)
	var centre_z: float = front + depth * 0.5
	var slab := BoxMesh.new()
	slab.size = Vector3(floor_m.x + 2.0 * CompanyShed.WALL_THICKNESS, SLAB_THICKNESS, depth)
	slab.material = DepotKit.detailed(data["yard_color"], data["detail"], CompanyShed.FLOOR_SLAB_M)
	var yard := MeshInstance3D.new()
	yard.name = "Yard"
	yard.mesh = slab
	yard.position = Vector3(0.0, SLAB_TOP - SLAB_THICKNESS * 0.5, centre_z)
	yard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(yard)
	var marks := _model("YardMarks", "sm_env_shed_yard_%s" % data["model"], Vector3(0.0, 0.0, centre_z))
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marks)
	for x: float in ShedExteriorPlan.lamp_xs(stage, floor_m.x):
		_add_lamp(Vector3(x, 0.0, front + LAMP_POST_OFFSET))


func _add_lamp(at: Vector3) -> void:
	add_child(_model("LampPost", "sm_env_shed_lamp_post", at), true)
	var head := _model("LampHead", "sm_env_shed_lamp_head", at)
	head.material_override = DepotKit.glow(LAMP_COLOR)
	add_child(head, true)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * LAMP_POOL_SIZE
	plane.material = DepotKit.light_pool(LAMP_POOL_COLOR)
	var pool := MeshInstance3D.new()
	pool.name = "LampPool"
	pool.mesh = plane
	pool.position = at + Vector3(0.0, LAMP_POOL_HEIGHT, LAMP_POOL_REACH)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool, true)


## A model of the depot's folder on a node of its own (no body, no collision).
static func _model(node_name: String, model_name: String, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = DepotKit.merged_mesh(DepotKit.depot_model(model_name))
	instance.position = at
	return instance
