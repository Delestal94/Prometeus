extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_centro.gd
##
## The gray Barrio Centro (expansion D-0314, scripts/gameplay/districts/centro_decor.gd, handed to the
## cells by EdgeCellContent / CompanyCells.use_graph on data/world/road_graph.tres and houses.tres):
## - the 30 houses of Centro are built once each, in the cell their origin lies in, standing on the
##   ground (not floating), with no wall on any roadway, on a sidewalk or on another house; they enter
##   the tree one per frame after their cell (HouseDrip), none costing more than the budget;
## - every street of Centro has a sidewalk on both sides, as wide as CentroDecor says, cut where a
##   crossing roadway or a house is in the way and never on a roadway; the roadway half-width it assumes
##   is the one a StraightSegment really draws;
## - four traffic lights (switched off) stand at four junctions of 4 or more streets, one pole and head
##   per corner, none on a roadway;
## - the decor of a cell is cheap: at most one mesh per colour and one body for the sidewalks, lamps
##   and benches (faces turned outward, the way Godot draws them), and building every cell of Centro
##   stays under a budget in milliseconds;
## - a cell with nothing of Centro (far away, the Campo) has no `Centro` node.

const ZONES_DIR: String = "res://data/zones/"
## Real milliseconds: a cell with its streets and decor entering the tree, one house entering it, all
## of Centro's cells together and the plan of the decor (headless, software rendering, a slow CI runner:
## a wide margin over what it measures: 5, 15, 40 and 20).
const CELL_BUDGET_MSEC: float = 50.0
const HOUSE_BUDGET_MSEC: float = 100.0
const TOTAL_BUDGET_MSEC: float = 500.0
const INDEX_BUDGET_MSEC: float = 250.0
## Overlap (m2) between two outlines that still counts as "they only touch".
const TOUCH_AREA: float = 0.05
const MIN_SIDEWALK_SHARE: float = 0.75

var _failures: int = 0
var _graph: RoadGraph
var _map: HouseMap
var _cells: CompanyCells
var _content: EdgeCellContent
var _decor: CentroDecor
var _holder: Node3D
## { Vector2i cell: Node3D Centro node }
var _built: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_graph = RoadGraph.load_default()
	_map = HouseMap.load_default()
	_expect(_graph != null and _map != null, "The road graph and the houses load")
	if _graph == null or _map == null:
		quit(1)
		return
	_cells = CompanyCells.new()
	root.add_child(_cells)
	var started: int = Time.get_ticks_usec()
	_content = _cells.use_graph(_graph)
	var index_msec: float = float(Time.get_ticks_usec() - started) / 1000.0
	print("  index: %.1f ms" % index_msec)
	_expect(index_msec < INDEX_BUDGET_MSEC,
			"Planning Centro's decor stays under %d ms (%.0f)" % [INDEX_BUDGET_MSEC, index_msec])
	_decor = _content.decor
	_expect(_decor != null, "use_graph() gives the cells the Centro decor")
	if _decor == null:
		quit(1)
		return
	_holder = Node3D.new()
	root.add_child(_holder)
	_build_all()
	await _settle_houses()
	_test_houses()
	_test_sidewalks()
	await _test_roadway_width()
	_test_lights()
	_test_cost_and_meshes()
	_test_empty_cells()
	_holder.queue_free()
	_cells.free()
	quit(_failures)


## Every cell of the decor through the real path (EdgeCellContent.build_cell), timed one by one.
func _build_all() -> void:
	var total: float = 0.0
	var worst: float = 0.0
	var worst_cell := Vector2i.ZERO
	for cell: Vector2i in _decor.cells():
		var t0: int = Time.get_ticks_usec()
		var node: Node3D = _content.build_cell(cell)
		# Entering the tree builds the pieces' boxes and each house's walls and model: the same frame.
		_holder.add_child(node)
		var msec: float = float(Time.get_ticks_usec() - t0) / 1000.0
		total += msec
		if msec > worst:
			worst = msec
			worst_cell = cell
		var centro: Node3D = node.get_node_or_null(^"Centro") as Node3D
		if centro != null:
			_built[cell] = centro
	print("  %d cells built in %.1f ms (worst %.1f ms at %s)" % [_decor.cells().size(), total, worst, worst_cell])
	_expect(worst < CELL_BUDGET_MSEC,
			"No cell of Centro takes %d ms to build (worst %.0f at %s)" % [CELL_BUDGET_MSEC, worst, worst_cell])
	_expect(total < TOTAL_BUDGET_MSEC,
			"All the cells of Centro build in under %d ms (%.0f)" % [TOTAL_BUDGET_MSEC, total])


## The houses come in one per frame (HouseDrip._process); the first cell is left to do it by itself, the
## rest are released by hand with the time of each one taken.
func _settle_houses() -> void:
	var worst: float = 0.0
	var first: bool = true
	for cell: Vector2i in _built:
		var drip: Node = (_built[cell] as Node).get_node_or_null(^"Houses")
		if drip == null:
			continue
		var homes: int = _decor.houses_in(cell).size()
		if first:
			first = false
			_expect((drip.get(&"pending") as Array).size() == homes,
					"A cell's houses wait to come in, after the cell itself")
			var frames: int = 0
			while not (drip.get(&"pending") as Array).is_empty() and frames < homes + 2:
				await process_frame
				frames += 1
			_expect((drip.get(&"pending") as Array).is_empty() and drip.get_child_count() == homes,
					"The %d houses of the first cell come in by themselves, in %d frames" % [homes, frames])
			_expect(frames >= homes, "...one per frame, not all at once (%d frames for %d)" % [frames, homes])
		while not (drip.get(&"pending") as Array).is_empty():
			var t0: int = Time.get_ticks_usec()
			drip.call(&"release", 1)
			worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
	print("  worst house entering the tree: %.1f ms" % worst)
	_expect(worst < HOUSE_BUDGET_MSEC,
			"A house enters the tree in under %d ms (worst %.0f)" % [HOUSE_BUDGET_MSEC, worst])


func _test_houses() -> void:
	var spots: Array[HouseSpot] = _map.in_zone(&"centro")
	_expect(spots.size() == 30, "Centro has its 30 houses")
	var seen: Dictionary = {}
	for cell: Vector2i in _built:
		var holder: Node = (_built[cell] as Node).get_node_or_null(^"Houses")
		if holder == null:
			continue
		for house: Node in holder.get_children():
			_expect(not seen.has(house.name), "%s is built once" % house.name)
			seen[house.name] = {"cell": cell, "node": house}
	var roadways: Array[PackedVector2Array] = _decor.roadway_polygons()
	var sidewalks: Array[PackedVector2Array] = _all_sidewalks()
	var footprints: Array[Dictionary] = []
	for spot: HouseSpot in spots:
		_expect(seen.has(StringName(spot.id)) or seen.has(String(spot.id)), "%s is in the world" % spot.id)
		var entry: Dictionary = seen.get(StringName(spot.id), seen.get(String(spot.id), {}))
		if entry.is_empty():
			continue
		var node: DeliveryHouse = entry.node
		var cell: Vector2i = entry.cell
		var size: float = CompanyTuning.CELL_SIZE
		var expected := Vector2i(floori(spot.position.x / size), floori(spot.position.y / size))
		_expect(cell == expected, "%s is in cell %s, where it falls (in %s)" % [spot.id, expected, cell])
		_expect(node.get_parent().get_parent().get_parent().name == "Cell_%d_%d" % [expected.x, expected.y],
				"%s hangs from its Cell node" % spot.id)
		_expect(Vector2(node.position.x, node.position.z).is_equal_approx(spot.position),
				"%s stands on its spot" % spot.id)
		_expect(is_equal_approx(node.position.y, CentroDecor.GROUND_TOP),
				"%s stands on the ground, not in the air" % spot.id)
		_expect(node.visual_variant == spot.variant, "%s keeps its model" % spot.id)
		for footprint: PackedVector2Array in CentroDecor.house_footprints(spot):
			footprints.append({"id": spot.id, "polygon": footprint})
			_expect(_overlap_area(footprint, roadways) < TOUCH_AREA, "%s has no wall on a roadway" % spot.id)
			_expect(_overlap_area(footprint, sidewalks) < TOUCH_AREA, "%s has no wall on a sidewalk" % spot.id)
			for corner: Vector2 in footprint:
				var near: Dictionary = _graph.nearest_point(corner)
				_expect(float(near.distance) > CentroDecor.ROADWAY_HALF_WIDTH,
						"%s: a wall corner is %.1f m from a street axis, over the roadway's half"
						% [spot.id, near.distance])
	for i in footprints.size():
		for k in i:
			if footprints[k].id != footprints[i].id:
				var other: Array[PackedVector2Array] = [footprints[k].polygon]
				_expect(_overlap_area(footprints[i].polygon, other) < TOUCH_AREA,
						"%s and %s do not overlap" % [footprints[k].id, footprints[i].id])
	# The houses of the other zones are not in Centro's cells' decor.
	for spot: HouseSpot in _map.in_zone(&"campo"):
		_expect(not seen.has(StringName(spot.id)) and not seen.has(String(spot.id)),
				"%s (Campo) is not built by Centro" % spot.id)


func _test_sidewalks() -> void:
	var nominal_area: float = 0.0
	var cut_area: float = 0.0
	var roadways: Array[PackedVector2Array] = _decor.roadway_polygons()
	var streets: int = 0
	for edge: RoadEdge in _graph.edges:
		if edge.area != CentroDecor.ZONE:
			continue
		streets += 1
		var left: int = 0
		var right: int = 0
		for polygon: PackedVector2Array in _all_sidewalks(edge.id):
			var centre: Vector2 = _centroid(polygon)
			if _side_of(edge, centre) > 0.0:
				left += 1
			else:
				right += 1
			cut_area += absf(_area(polygon))
			# Never on a roadway (the street's own, or one that crosses it).
			_expect(_overlap_area(polygon, roadways) < TOUCH_AREA, "A sidewalk of %s is not on a roadway" % edge.id)
		for nominal: PackedVector2Array in _decor.nominal_strips(edge.id):
			nominal_area += absf(_area(nominal))
		_expect(left > 0 and right > 0, "%s has a sidewalk on both sides (%d / %d pieces)" % [edge.id, left, right])
	_expect(streets > 0, "Centro has streets (%d)" % streets)
	_expect(cut_area >= nominal_area * MIN_SIDEWALK_SHARE,
			"Little is cut off the sidewalks (%.0f of %.0f m2)" % [cut_area, nominal_area])
	_expect(cut_area < nominal_area,
			"Something is cut where streets cross (%.0f of %.0f m2)" % [cut_area, nominal_area])
	# One straight piece far from any crossing is as wide as the constant says.
	var sample: Array[PackedVector2Array] = _all_sidewalks(&"avenida_este_3")
	var widest: float = 0.0
	for polygon: PackedVector2Array in sample:
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for p: Vector2 in polygon:
			bounds = bounds.expand(p)
		widest = maxf(widest, minf(bounds.size.x, bounds.size.y))
	_expect(is_equal_approx(widest, CentroDecor.SIDEWALK_WIDTH),
			"The Avenida Este's sidewalk is %.1f m wide (%.2f)" % [CentroDecor.SIDEWALK_WIDTH, widest])


## The assumed half-width is what a StraightSegment draws, and its top is the ground line of the curb.
func _test_roadway_width() -> void:
	var segment := StraightSegment.new()
	_holder.add_child(segment)
	await process_frame
	var road: Node3D = segment.get_node_or_null(^"Road") as Node3D
	_expect(road != null, "A StraightSegment draws a Road")
	if road == null:
		return
	var size: Vector3 = ((road.get_child(0) as MeshInstance3D).mesh as BoxMesh).size
	_expect(is_equal_approx(size.x * 0.5, CentroDecor.ROADWAY_HALF_WIDTH),
			"ROADWAY_HALF_WIDTH (%.1f) is the road RouteSegment draws (%.1f)"
			% [CentroDecor.ROADWAY_HALF_WIDTH, size.x * 0.5])
	_expect(is_equal_approx(road.position.y + size.y * 0.5, 0.0), "The roadway's top is y = 0, under the curb's top")
	_expect(CentroDecor.SIDEWALK_HEIGHT > 0.0 and CentroDecor.GROUND_TOP < 0.0,
			"The curb stands over the roadway, the houses under it")
	segment.queue_free()


func _test_lights() -> void:
	var nodes: Array[StringName] = _decor.light_nodes()
	_expect(nodes.size() == CentroDecor.LIGHT_COUNT and nodes.size() == 4,
			"Four junctions carry a traffic light (%d)" % nodes.size())
	var found: Dictionary = {}
	var roadways: Array[PackedVector2Array] = _decor.roadway_polygons()
	for cell: Vector2i in _built:
		for child: Node in (_built[cell] as Node).get_children():
			if String(child.name).begins_with("TrafficLight_"):
				_expect(not found.has(child.name), "%s is built once" % child.name)
				found[child.name] = {"cell": cell, "node": child}
	_expect(found.size() == 4, "Four traffic lights are in the world (%d)" % found.size())
	for id: StringName in nodes:
		var name: String = "TrafficLight_%s" % id
		_expect(found.has(StringName(name)) or found.has(name), "%s is there" % name)
		var junction: RoadNode = _graph.node_by_id(id)
		_expect(junction.area == CentroDecor.ZONE and _graph.edges_at(id).size() >= 4,
				"%s is a Centro junction of 4+ streets" % id)
		var entry: Dictionary = found.get(StringName(name), found.get(name, {}))
		if entry.is_empty():
			continue
		var cell: Vector2i = entry.cell
		var size: float = CompanyTuning.CELL_SIZE
		_expect(cell == Vector2i(floori(junction.position.x / size), floori(junction.position.y / size)),
				"%s is in the cell of its junction" % name)
		var poles: int = 0
		var heads: int = 0
		for part: Node in (entry.node as Node).get_children():
			var body := part as Node3D
			if String(part.name).begins_with("Pole_"):
				poles += 1
				var at := Vector2(body.position.x, body.position.z)
				_expect(at.distance_to(junction.position) > CentroDecor.ROADWAY_HALF_WIDTH,
						"A pole of %s is off the junction's middle" % name)
				_expect(not _inside_any(at, roadways), "A pole of %s is not on a roadway" % name)
				_expect(part is StaticBody3D, "A pole of %s is solid" % name)
			elif String(part.name).begins_with("Head_"):
				heads += 1
		_expect(poles == 4 and heads == 4, "%s has a pole and a head per corner (%d, %d)" % [name, poles, heads])
		_expect((entry.node as Node).get_node_or_null(^"ControlBox") != null, "%s has its control box" % name)


func _test_cost_and_meshes() -> void:
	var meshes_total: int = 0
	var lamps: int = 0
	var benches: int = 0
	var wrong_way: int = 0
	var off_height: int = 0
	var up_faces: int = 0
	for cell: Vector2i in _built:
		var centro: Node3D = _built[cell]
		var meshes: int = 0
		var bodies: int = 0
		for child: Node in centro.get_children():
			if child is MeshInstance3D:
				meshes += 1
				var arrays: Array = ((child as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in range(0, vertices.size(), 3):
					# Godot draws the clockwise side: the cross product points against the face's normal.
					var cross: Vector3 = (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
					if cross.dot(normals[i]) > 0.0:
						wrong_way += 1
					if normals[i].dot(Vector3.UP) > 0.99:
						up_faces += 1
						if child.name == &"Sidewalks":
							if not is_equal_approx(vertices[i].y, CentroDecor.SIDEWALK_HEIGHT):
								off_height += 1
			elif child is StaticBody3D and child.name == &"Solid":
				bodies += 1
		meshes_total += meshes
		_expect(meshes <= 3, "Cell %s: at most one mesh per colour (%d)" % [cell, meshes])
		_expect(bodies <= 1, "Cell %s: one body for the sidewalks and props" % cell)
		lamps += _decor.lamp_count(cell)
		benches += _decor.bench_count(cell)
	_expect(wrong_way == 0, "Every face of the decor meshes is drawn on its outward side (%d are not)" % wrong_way)
	_expect(off_height == 0 and up_faces > 0,
			"Sidewalk tops are at the curb height (%d are not, of %d tops)" % [off_height, up_faces])
	_expect(lamps > 10 and benches > 3, "Centro has lamps (%d) and benches (%d)" % [lamps, benches])
	_expect(meshes_total <= 3 * _built.size(), "Meshes stay few (%d in %d cells)" % [meshes_total, _built.size()])


func _test_empty_cells() -> void:
	_expect(_decor.build_cell(Vector2i(-5, -5)) == null, "A cell far from Centro has no Centro node")
	_expect(_decor.build_cell(Vector2i(0, 6)) == null, "A Campo cell has no Centro node")
	var far: Node3D = _content.build_cell(Vector2i(400, 400))
	_expect(far.get_child_count() == 0, "...and a cell with no street at all is as empty as before")
	far.free()
	var plain := EdgeCellContent.new(_graph, CompanyTuning.CELL_SIZE)
	var street: Node3D = plain.build_cell(Vector2i(1, 0))
	_expect(street.get_node_or_null(^"Centro") == null, "Without a decor, a cell holds the streets only")
	street.free()


# --- Helpers ---------------------------------------------------------------------------------------


func _all_sidewalks(street: StringName = &"") -> Array[PackedVector2Array]:
	var found: Array[PackedVector2Array] = []
	for cell: Vector2i in _decor.cells():
		found.append_array(_decor.sidewalk_polygons(cell, street))
	return found


## Total area where `polygon` lies over any of `others`.
func _overlap_area(polygon: PackedVector2Array, others: Array[PackedVector2Array]) -> float:
	var total: float = 0.0
	var box := _bounds(polygon)
	for other: PackedVector2Array in others:
		if not box.intersects(_bounds(other)):
			continue
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(polygon, other):
			total += absf(_area(piece))
	return total


func _inside_any(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon: PackedVector2Array in polygons:
		if _bounds(polygon).has_point(point) and Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


func _bounds(polygon: PackedVector2Array) -> Rect2:
	var box := Rect2(polygon[0], Vector2.ZERO)
	for p: Vector2 in polygon:
		box = box.expand(p)
	return box


func _area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in polygon.size():
		var p: Vector2 = polygon[i]
		var q: Vector2 = polygon[(i + 1) % polygon.size()]
		total += p.x * q.y - q.x * p.y
	return total * 0.5


func _centroid(polygon: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p: Vector2 in polygon:
		sum += p
	return sum / float(polygon.size())


## Which side of the street's axis a ground point is: > 0 left of the way from node to node.
func _side_of(edge: RoadEdge, point: Vector2) -> float:
	var line: PackedVector2Array = _graph.centerline(edge.id)
	var best: float = INF
	var side: float = 0.0
	for i in line.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, line[i], line[i + 1])
		var d: float = point.distance_to(closest)
		if d < best:
			best = d
			side = (line[i + 1] - line[i]).cross(point - line[i])
	return side


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: ", message)
	else:
		_failures += 1
		printerr("  FAIL: ", message)
