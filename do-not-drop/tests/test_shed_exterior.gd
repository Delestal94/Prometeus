extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_exterior.gd
##
## Outside of the shed per stage (expansion D-0936, ShedExteriorPlan and ShedExterior):
## - four variants, one per shed stage, each with its own sign text key that exists in both languages;
## - sign, yard and lamps only grow with the stage, and the sign never passes the wall it hangs on;
## - the lamp posts come in pairs inside the floor width and clear of the truck's lane;
## - ShedExterior draws sign, yard and lamps with no collision, and CompanyShed.rebuild() hangs one
##   exterior that follows the stage (a bigger stage gives a wider sign and a deeper yard);
## - the art (D-0936, build_depot_props.py group shed_exterior): each sign model loads and measures the plan's
##   width x height x 0.25 with its pivot at the centre of the base, on top of the wall, behind the plane of its name;
##   the name stays on the sign in both languages, also on a floor narrower than the sign; the yard's paint stays on
##   the slab and off the road that comes in at the dock; no two materials of a sign or a yard share a plane where
##   they overlap (they would flicker); the slab runs on under the dock wall, so no bare ground shows at its foot, and
##   the lamps stand on it; the lamp is 3.2 m on its base, with a glowing head, and every model is within the prop
##   budget.

const MAX_TRIS: int = 500
## The map's first road, over the bigger yards: the paint keeps out of its top (y = 0 and the slab is under it).
const ROAD_HALF_X: float = 6.0
const ROAD_START_Z: float = 11.0
## Faces closer than this along their normal draw as one plane (a depth buffer can't be asked for less).
const SAME_PLANE: float = 0.0003
## Overlap (m2) between two materials on one plane that a model may have: only what rounding leaves on a shared edge.
const OVERLAP_ALLOWED: float = 0.0001

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(ShedExteriorPlan.variant_count() == WarehouseStages.stage_count(), "one variant per stage")
	var last_sign: float = 0.0
	var last_yard: float = 0.0
	var last_lamps: int = -1
	var keys: Dictionary = {}
	for stage: int in ShedExteriorPlan.variant_count():
		var floor_m: Vector2 = WarehouseStages.floor_size_m(stage)
		var size: Vector2 = ShedExteriorPlan.sign_size(stage, floor_m.x)
		_expect(size.x <= floor_m.x and size.x > last_sign, "stage %d: wider sign that fits its wall" % stage)
		_expect(ShedExteriorPlan.yard_depth(stage) > last_yard, "stage %d: deeper yard" % stage)
		var xs: Array[float] = ShedExteriorPlan.lamp_xs(stage, floor_m.x)
		_expect(xs.size() >= last_lamps, "stage %d: no fewer lamps" % stage)
		for x: float in xs:
			_expect(absf(x) < floor_m.x * 0.5 and absf(x) >= ShedExteriorPlan.LAMP_CLEAR,
				"stage %d: lamp inside the width and clear of the dock gate's centre line" % stage)
		var key: StringName = ShedExteriorPlan.variant(stage)["key"]
		_expect(not keys.has(key), "stage %d: its own sign key" % stage)
		keys[key] = true
		_expect(tr(String(key)) != String(key), "stage %d: sign key %s is translated" % [stage, key])
		last_sign = size.x
		last_yard = ShedExteriorPlan.yard_depth(stage)
		last_lamps = xs.size()
	_expect(ShedExteriorPlan.variant(-5) == ShedExteriorPlan.variant(0), "a stage below 0 is the first variant")
	_expect(ShedExteriorPlan.variant(99) == ShedExteriorPlan.variant(3), "a stage above the last is the last variant")

	var widths: Array[float] = []
	var depths: Array[float] = []
	for stage: int in ShedExteriorPlan.variant_count():
		var exterior: ShedExterior = ShedExterior.build(
			stage, WarehouseStages.floor_size_m(stage), CompanyShed.WALL_HEIGHT)
		var board: MeshInstance3D = exterior.get_node_or_null(^"Sign")
		var yard: MeshInstance3D = exterior.get_node_or_null(^"Yard")
		_expect(board != null and yard != null, "stage %d draws a sign and a yard" % stage)
		_expect(exterior.get_node_or_null(^"SignText") != null, "stage %d: the sign has its text" % stage)
		_expect(_bodies_in(exterior) == 0, "stage %d: the exterior has no collision" % stage)
		if board != null and yard != null:
			widths.append(board.mesh.get_aabb().size.x * board.scale.x)
			depths.append((yard.mesh as BoxMesh).size.z)
			_expect(is_equal_approx(board.position.y, CompanyShed.WALL_HEIGHT),
				"stage %d: the sign stands on the wall" % stage)
			var floor_z: float = WarehouseStages.floor_size_m(stage).y * 0.5
			var yard_start: float = yard.position.z - (yard.mesh as BoxMesh).size.z * 0.5
			var yard_end: float = yard.position.z + (yard.mesh as BoxMesh).size.z * 0.5
			_expect(_near(yard_start, floor_z), "stage %d: the slab starts under the dock wall, at the floor" % stage)
			_expect(_near(yard_end, floor_z + CompanyShed.WALL_THICKNESS + ShedExteriorPlan.yard_depth(stage)),
				"stage %d: the slab ends at the plan's depth from the wall" % stage)
			_check_sign_model(stage, board)
			_check_sign_stands_behind_name(stage, exterior, board)
			_check_yard_marks(stage, exterior, yard)
		_check_lamps(stage, exterior)
		exterior.free()
	_check_sign_text()
	for i: int in range(1, widths.size()):
		_expect(widths[i] > widths[i - 1] and depths[i] > depths[i - 1], "built exterior %d grows" % i)

	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Exterior Co")
	var shed := CompanyShed.new()
	root.add_child(shed)
	var stock := Inventory.new()
	shed.rebuild(state, stock)
	var first: Node = shed.get_node_or_null(^"Exterior")
	_expect(first != null, "the shed hangs an exterior")
	var first_width: float = _sign_width(first)
	state.warehouse_stage = 2
	shed.rebuild(state, stock)
	await process_frame
	var second: Node = shed.get_node_or_null(^"Exterior")
	var exteriors: Array = shed.get_children().filter(func(n: Node) -> bool: return n.name == &"Exterior")
	_expect(second != null and exteriors.size() == 1, "a redraw keeps exactly one exterior")
	_expect(_sign_width(second) > first_width, "the exterior follows the stage after a redraw")
	shed.free()
	quit(_failures)


func _sign_width(exterior: Node) -> float:
	if exterior == null:
		return 0.0
	var board := exterior.get_node(^"Sign") as MeshInstance3D
	return board.mesh.get_aabb().size.x * board.scale.x


## The sign's model measures what the plan says, its pivot is the centre of its base and the name's area is on it.
func _check_sign_model(stage: int, board: MeshInstance3D) -> void:
	var data: Dictionary = ShedExteriorPlan.variant(stage)
	var wanted: Vector2 = data["sign"]
	var box: AABB = board.mesh.get_aabb()
	_expect(_near(box.size.x, wanted.x) and _near(box.size.y, wanted.y),
		"stage %d: the sign model measures the plan" % stage)
	_expect(_near(box.size.z, ShedExterior.SIGN_DEPTH), "stage %d: the sign is %.2f deep" % [stage, box.size.z])
	_expect(_near(box.position.y, 0.0), "stage %d: the sign's pivot is on its base" % stage)
	_expect(_near(box.get_center().x, 0.0) and absf(box.get_center().z) < 0.002,
		"stage %d: the sign's pivot is centred" % stage)
	_expect(Rect2(-wanted * Vector2(0.5, 0.0), wanted).encloses(data["text"]),
		"stage %d: the name's area is on the sign" % stage)
	_expect(_tris(board.mesh) <= MAX_TRIS, "stage %d: sign within budget (%d)" % [stage, _tris(board.mesh)])
	var overlap: float = _fighting_area(board.mesh, Vector3.AXIS_Z)
	_expect(overlap < OVERLAP_ALLOWED, "stage %d: the sign's materials share a plane over %.4f m2" % [stage, overlap])


## The name's Label3D floats in front of everything on the sign, its mark included.
func _check_sign_stands_behind_name(stage: int, exterior: Node, board: MeshInstance3D) -> void:
	var label := exterior.get_node_or_null(^"SignText") as Label3D
	if label == null:
		return
	var gap: float = label.position.z - board.position.z - board.mesh.get_aabb().end.z
	_expect(gap >= 0.005, "stage %d: the name stands clear of the sign (%.3f m)" % [stage, gap])


## The paint lies between the slab and the road's top, inside the slab, and off the road.
func _check_yard_marks(stage: int, exterior: Node, yard: MeshInstance3D) -> void:
	var marks := exterior.get_node_or_null(^"YardMarks") as MeshInstance3D
	_expect(marks != null and marks.mesh != null, "stage %d: the yard has its marks" % stage)
	if marks == null or marks.mesh == null:
		return
	var slab: Vector3 = (yard.mesh as BoxMesh).size
	var depth: float = ShedExteriorPlan.yard_depth(stage)
	var box: AABB = marks.mesh.get_aabb()
	_expect(box.position.y > ShedExterior.SLAB_TOP and box.end.y < 0.0,
		"stage %d: the paint is on the slab, under the road" % stage)
	_expect(absf(box.position.x) <= slab.x * 0.5 + 0.06 and box.end.x <= slab.x * 0.5 + 0.06,
		"stage %d: the paint keeps to the slab's width" % stage)
	_expect(box.position.z >= -depth * 0.5 - 0.01 and box.end.z <= depth * 0.5 + 0.01,
		"stage %d: the paint keeps to the open yard's depth" % stage)
	var wall_face: float = WarehouseStages.floor_size_m(stage).y * 0.5 + CompanyShed.WALL_THICKNESS
	_expect(_near(marks.position.z, wall_face + depth * 0.5), "stage %d: the marks' pivot is the yard's centre" % stage)
	for point: Vector3 in marks.mesh.get_faces():
		var at: Vector3 = point + marks.position
		if absf(at.x) < ROAD_HALF_X and at.z > ROAD_START_Z:
			_expect(false, "stage %d: paint on the road at %s" % [stage, at])
			break
	_expect(_tris(marks.mesh) <= MAX_TRIS, "stage %d: marks within budget (%d)" % [stage, _tris(marks.mesh)])
	var overlap: float = _fighting_area(marks.mesh, Vector3.AXIS_Y)
	_expect(overlap < OVERLAP_ALLOWED, "stage %d: two colours of paint overlap over %.4f m2" % [stage, overlap])


func _check_lamps(stage: int, exterior: Node) -> void:
	var posts: Array = exterior.get_children().filter(
		func(n: Node) -> bool: return String(n.name).contains("LampPost"))
	var heads: Array = exterior.get_children().filter(
		func(n: Node) -> bool: return String(n.name).contains("LampHead"))
	var wanted: int = ShedExteriorPlan.lamp_xs(stage, WarehouseStages.floor_size_m(stage).x).size()
	_expect(posts.size() == wanted and heads.size() == wanted, "stage %d: a post and a head per lamp" % stage)
	for post: MeshInstance3D in posts:
		var box: AABB = post.mesh.get_aabb()
		_expect(is_equal_approx(post.position.y, ShedExterior.SLAB_TOP),
			"stage %d: the lamp stands on the slab" % stage)
		_expect(_near(box.position.y, 0.0) and _near(box.end.y, ShedExterior.LAMP_HEIGHT),
			"the lamp is 3.2 m on its base")
		_expect(_near(box.position.x + box.size.x * 0.5, 0.0) and _near(box.position.z, -0.2),
			"the lamp's pivot is under its pole")
		_expect(_tris(post.mesh) <= MAX_TRIS, "lamp within budget (%d)" % _tris(post.mesh))
	for head: MeshInstance3D in heads:
		var glow := head.material_override as StandardMaterial3D
		_expect(glow != null and glow.emission_enabled, "the lamp's head glows")


## The name fits its area in both languages, and on a floor narrower than the sign (which shrinks with it).
func _check_sign_text() -> void:
	var locale: String = TranslationServer.get_locale()
	for language: String in ["es", "en"]:
		TranslationServer.set_locale(language)
		for stage: int in ShedExteriorPlan.variant_count():
			var wide: Vector2 = ShedExteriorPlan.variant(stage)["sign"]
			for floor_x: float in [wide.x + 1.0, wide.x * 0.75]:
				var exterior: ShedExterior = ShedExterior.build(stage, Vector2(floor_x, 8.0), CompanyShed.WALL_HEIGHT)
				var label := exterior.get_node(^"SignText") as Label3D
				var board := exterior.get_node(^"Sign") as MeshInstance3D
				var width: float = label.pixel_size * label.font.get_string_size(
					label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
				var area: Rect2 = ShedExteriorPlan.variant(stage)["text"]
				_expect(label.text != String(ShedExteriorPlan.variant(stage)["key"]),
					"stage %d: translated in %s" % [stage, language])
				_expect(width <= area.size.x * board.scale.x + 0.01,
					"stage %d %s: \"%s\" fits its area" % [stage, language, label.text])
				_expect(board.mesh.get_aabb().size.x * board.scale.x <= floor_x + 0.01,
					"stage %d: the sign fits a %.1f m wall" % [stage, floor_x])
				exterior.free()
	TranslationServer.set_locale(locale)


## Area (m2) where faces of two surfaces (materials) overlap on one plane, among those looking toward +`axis`.
func _fighting_area(mesh: Mesh, axis: int) -> float:
	var faces: Array[Array] = []
	for surface: int in mesh.get_surface_count():
		faces.append(_faces_toward(mesh, surface, axis))
	var total: float = 0.0
	for a: int in faces.size():
		for b: int in range(a + 1, faces.size()):
			for one: Dictionary in faces[a]:
				for other: Dictionary in faces[b]:
					if absf(float(one["plane"]) - float(other["plane"])) < SAME_PLANE \
							and (one["box"] as Rect2).intersects(other["box"]):
						total += _shared_area(one["points"], other["points"])
	return total


## The triangles of a surface that look toward +`axis`, flattened on the other two axes: plane, points and bounds.
func _faces_toward(mesh: Mesh, surface: int, axis: int) -> Array[Dictionary]:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count: int = indices.size() if not indices.is_empty() else vertices.size()
	var across: int = Vector3.AXIS_Y if axis == Vector3.AXIS_Z else Vector3.AXIS_Z
	var found: Array[Dictionary] = []
	for i: int in range(0, count, 3):
		var corners: Array[int] = [i, i + 1, i + 2]
		if not indices.is_empty():
			corners = [indices[i], indices[i + 1], indices[i + 2]]
		if normals[corners[0]][axis] < 0.9:
			continue
		var points := PackedVector2Array()
		var bounds := Rect2()
		for corner: int in corners:
			var point := Vector2(vertices[corner].x, vertices[corner][across])
			bounds = Rect2(point, Vector2.ZERO) if points.is_empty() else bounds.expand(point)
			points.append(point)
		found.append({"plane": vertices[corners[0]][axis], "points": points, "box": bounds})
	return found


func _shared_area(one: PackedVector2Array, other: PackedVector2Array) -> float:
	var area: float = 0.0
	for shape: PackedVector2Array in Geometry2D.intersect_polygons(one, other):
		for i: int in shape.size():
			area += shape[i].cross(shape[(i + 1) % shape.size()]) * 0.5
	return absf(area)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.02


func _tris(mesh: Mesh) -> int:
	return mesh.get_faces().size() / 3


func _bodies_in(node: Node) -> int:
	var count: int = 1 if node is CollisionObject3D else 0
	for child: Node in node.get_children():
		count += _bodies_in(child)
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
		print("FAIL: ", message)
