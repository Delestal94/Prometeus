class_name CentroDecor
extends RefCounted
## What the gray Barrio Centro holds besides its roadway (expansion D-0314): sidewalks along both
## sides of every street of the zone, its 30 delivery houses (HouseMap.instance), four street corners
## with a switched-off traffic light, street lamps and benches. All of it is a gray placeholder made of
## primitives (no model): the real art is in docs/expansion-distritos/arte-pendiente/D-0314.md.
##
## Like EdgeCellContent, `index()` work is pure data (testable with no scene) and build_cell() makes
## the nodes of one cell, `Centro` under `Cell_<x>_<z>`: ONE mesh per colour and ONE collision body
## for all the sidewalks, lamps and benches of the cell, the four lights as a few boxes, and the houses.
## A sidewalk, lamp or house belongs to the cell its start point (or origin) lies in, like a piece of
## street. Sidewalks are cut where another roadway or a house crosses them, so they never cover a
## roadway or the walls of a house.

const ZONE: StringName = &"centro"
## Half the roadway RouteSegment really draws: StraightSegment's Road box is 12 m wide, whatever
## RoadEdge.width says (the surface per edge is D-0304.1b). test_company_centro keeps the two equal.
const ROADWAY_HALF_WIDTH: float = 6.0
const SIDEWALK_WIDTH: float = 2.0
## Over the roadway's top (y = 0); a curb a van can drive up if it has to.
const SIDEWALK_HEIGHT: float = 0.15
## The ground slab of the zone (CompanyRoot._add_zone_slab: centre -0.2, 0.2 thick): houses stand on it.
const GROUND_TOP: float = -0.1
## Length of one sidewalk piece along a street (evened out per street, RoadNetwork.sample_every).
const SIDEWALK_STEP: float = 32.0
## Roadways are looked up by buckets of this side (m): a cut only meets the few near the piece.
const BUCKET_SIZE: float = 64.0
## What is left of a cut sidewalk below this area (m2) is dropped.
const MIN_PIECE_AREA: float = 0.4
## Clear space kept around the walls of a house (its porch and the way to the door).
const HOUSE_MARGIN: float = 1.4

## Streets with at least this many ends at a junction can take a traffic light; the first LIGHT_COUNT
## by distance to the shed (then id) do.
const LIGHT_MIN_STREETS: int = 4
const LIGHT_COUNT: int = 4
const LIGHT_POLE_HEIGHT: float = 4.2
const LIGHT_POLE_SIZE: float = 0.22
const LIGHT_HEAD_SIZE: Vector3 = Vector3(0.45, 1.15, 0.45)
## How far the head hangs out of the pole toward the crossing, and below the pole's top.
const LIGHT_HEAD_REACH: float = 0.5
const LIGHT_HEAD_DROP: float = 0.7
const LIGHT_BOX_SIZE: Vector3 = Vector3(0.5, 1.1, 0.4)

const LAMP_FIRST: float = 24.0
const LAMP_SPACING: float = 48.0
## No lamp or bench closer than this to the end of a street (the crossing).
const PROP_END_CLEARANCE: float = 14.0
## How far in from the sidewalk's outer edge a lamp pole stands.
const LAMP_INSET: float = 0.4
const LAMP_HEIGHT: float = 4.6
const LAMP_POLE_SIZE: float = 0.16
const LAMP_HEAD_SIZE: Vector2 = Vector2(0.9, 0.35)
const LAMP_HEAD_THICKNESS: float = 0.18
const BENCH_FIRST: float = 48.0
const BENCH_SPACING: float = 96.0
## Seat length, depth, base and seat heights, back height.
const BENCH_LENGTH: float = 1.6
const BENCH_DEPTH: float = 0.5
const BENCH_BASE_HEIGHT: float = 0.4
const BENCH_SEAT_HEIGHT: float = 0.5
const BENCH_BACK_HEIGHT: float = 1.0
const BENCH_BACK_THICKNESS: float = 0.1

const SIDEWALK_COLOR := Color("9ea3a1")
const LAMP_COLOR := Color("5f676b")
const BENCH_COLOR := Color("7f8584")
const LIGHT_POLE_COLOR := Color("6a7276")
const LIGHT_HEAD_COLOR := Color("3c4246")

## A house enters the tree this many per frame after its cell: each one loads its model, makes its walls and
## its doorbell (10 to 15 ms in software rendering), so a cell with five would be a 60 ms frame.
const HOUSES_PER_FRAME: int = 1

const COLLISION_LAYER: int = 1
const COLLISION_MASK: int = 6

## { Vector2i cell: { "strips": Array[Dictionary], "lamps": Array[Dictionary], "benches": Array[Dictionary],
## "lights": Array[StringName], "houses": Array[HouseSpot] } }
var _by_cell: Dictionary = {}
var graph: RoadGraph
var houses: HouseMap
var cell_size: float
var _roadways: Array[Dictionary] = []
## { Vector2i bucket: Array[int] } indexes into _roadways.
var _road_buckets: Dictionary = {}
## { Vector2i cell: Array[{ edge, polygon }] } the cut sidewalks, kept once made.
var _cut_cache: Dictionary = {}
var _blocks: Array[Dictionary] = []
var _light_nodes: Array[StringName] = []


func _init(road_graph: RoadGraph, house_map: HouseMap, size: float) -> void:
	graph = road_graph
	houses = house_map
	cell_size = size
	_index_roadways()
	_index_houses()
	_index_lights()
	for edge: RoadEdge in graph.edges:
		if edge.area == ZONE:
			_index_edge(edge)


# --- Pure data -------------------------------------------------------------------------------------


## Cells that hold something of the decor.
func cells() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for cell: Vector2i in _by_cell:
		found.append(cell)
	return found


func cell_of(ground: Vector2) -> Vector2i:
	return Vector2i(floori(ground.x / cell_size), floori(ground.y / cell_size))


func houses_in(cell: Vector2i) -> Array[HouseSpot]:
	var found: Array[HouseSpot] = []
	for house: HouseSpot in _slot(cell, "houses"):
		found.append(house)
	return found


## The junctions that carry a traffic light (RoadNode ids), in order.
func light_nodes() -> Array[StringName]:
	return _light_nodes.duplicate()


func lights_in(cell: Vector2i) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: StringName in _slot(cell, "lights"):
		found.append(id)
	return found


func strip_count(cell: Vector2i) -> int:
	return _slot(cell, "strips").size()


func lamp_count(cell: Vector2i) -> int:
	return _slot(cell, "lamps").size()


func bench_count(cell: Vector2i) -> int:
	return _slot(cell, "benches").size()


## The ground outline (x, z) of every sidewalk piece of the cell, already cut where a roadway or a house
## is in the way; with `street` set, only the pieces along that street.
func sidewalk_polygons(cell: Vector2i, street: StringName = &"") -> Array[PackedVector2Array]:
	var found: Array[PackedVector2Array] = []
	for piece: Dictionary in _cut_cell(cell):
		if street == &"" or piece.edge == street:
			found.append(piece.polygon)
	return found


## The sidewalk piece outlines of one street, nominal (not cut), for tests: `[{ side, polygon }]`.
func nominal_strips(edge_id: StringName) -> Array[PackedVector2Array]:
	var found: Array[PackedVector2Array] = []
	for cell: Vector2i in _by_cell:
		for strip: Dictionary in _slot(cell, "strips"):
			if strip.edge == edge_id:
				found.append(_strip_polygon(strip))
	return found


## The roadway outlines of every street of the graph, as RouteSegment draws them.
func roadway_polygons() -> Array[PackedVector2Array]:
	var found: Array[PackedVector2Array] = []
	for road: Dictionary in _roadways:
		found.append(road.polygon)
	return found


## The wall outlines of a house on the ground (one rectangle per solid volume of its model).
static func house_footprints(house: HouseSpot) -> Array[PackedVector2Array]:
	var found: Array[PackedVector2Array] = []
	var models: Array = DeliveryHouse.HOUSE_COLLIDERS
	var colliders: Array = models[clampi(house.variant, 0, models.size() - 1)]
	var cos_yaw: float = cos(house.yaw)
	var sin_yaw: float = sin(house.yaw)
	for volume: Array in colliders:
		var size: Vector3 = volume[0]
		var centre: Vector3 = volume[1]
		var outline := PackedVector2Array()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var lx: float = centre.x + corner.x * size.x * 0.5
			var lz: float = centre.z + corner.y * size.z * 0.5
			# Basis(UP, yaw) turned a local (x, z) into the world.
			outline.append(house.position + Vector2(lx * cos_yaw + lz * sin_yaw, -lx * sin_yaw + lz * cos_yaw))
		found.append(outline)
	return found


## The corners of a junction where the sidewalks meet: a ground point per pair of neighbouring streets,
## with the unit direction from the corner back to the junction's centre. Pairs more than ~170 degrees
## apart (the two halves of a street that just goes on) have no corner.
func corners(node_id: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var centre: Vector2 = graph.node_by_id(node_id).position
	var heading: Array[Vector2] = []
	for edge: RoadEdge in graph.edges_at(node_id):
		var away: Vector2 = graph.tangent_at(edge.id, 0.0)
		if edge.to_id == node_id:
			away = -graph.tangent_at(edge.id, graph.edge_length(edge.id))
		heading.append(away)
	heading.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.angle() < b.angle())
	var reach: float = ROADWAY_HALF_WIDTH + SIDEWALK_WIDTH * 0.5
	for i in heading.size():
		var first: Vector2 = heading[i]
		var second: Vector2 = heading[(i + 1) % heading.size()]
		var turn: float = 1.0 + first.dot(second)
		if heading.size() < 2 or turn < 0.02:
			continue
		var spot: Vector2 = centre + (first + second) * reach / turn
		found.append({"position": spot, "to_centre": (centre - spot).normalized()})
	return found


# --- The nodes -------------------------------------------------------------------------------------


## The `Centro` node of the cell (sidewalks, props, lights, houses), or null when the cell holds none.
func build_cell(cell: Vector2i) -> Node3D:
	if not _by_cell.has(cell):
		return null
	var node := Node3D.new()
	node.name = "Centro"
	_build_solids(node, cell)
	for id: StringName in _slot(cell, "lights"):
		_build_light(node, id)
	var homes: Array = _slot(cell, "houses")
	if not homes.is_empty():
		var drip := HouseDrip.new()
		drip.name = "Houses"
		drip.per_frame = HOUSES_PER_FRAME
		for house: HouseSpot in homes:
			drip.pending.append(houses.instance(house, GROUND_TOP))
		node.add_child(drip)
	return node


func _build_solids(node: Node3D, cell: Vector2i) -> void:
	var by_color: Dictionary = {}
	var faces := PackedVector3Array()
	for polygon: PackedVector2Array in sidewalk_polygons(cell):
		_prism(_mesh_for(by_color, SIDEWALK_COLOR), polygon, GROUND_TOP, SIDEWALK_HEIGHT)
	for lamp: Dictionary in _slot(cell, "lamps"):
		_build_lamp(by_color, lamp)
	for bench: Dictionary in _slot(cell, "benches"):
		_build_bench(by_color, bench)
	var names: Dictionary = {SIDEWALK_COLOR: "Sidewalks", LAMP_COLOR: "Lamps", BENCH_COLOR: "Benches"}
	for color: Color in by_color:
		var batch: _Batch = by_color[color]
		var instance := MeshInstance3D.new()
		instance.name = names[color]
		instance.mesh = batch.to_mesh()
		instance.material_override = RouteProps.material(color)
		node.add_child(instance)
		faces.append_array(batch.vertices)
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = COLLISION_MASK
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	node.add_child(body)


func _build_lamp(by_color: Dictionary, lamp: Dictionary) -> void:
	var batch: _Batch = _mesh_for(by_color, LAMP_COLOR)
	var at: Vector2 = lamp.position
	var along: Vector2 = lamp.along
	_prism(batch, _rect(at, along, LAMP_POLE_SIZE * 0.5, LAMP_POLE_SIZE * 0.5), GROUND_TOP, LAMP_HEIGHT)
	# The head reaches over the sidewalk, toward the street.
	var toward_road: Vector2 = lamp.to_road
	var head_centre: Vector2 = at + toward_road * (LAMP_HEAD_SIZE.x * 0.5 - LAMP_POLE_SIZE * 0.5)
	_prism(batch, _rect(head_centre, toward_road, LAMP_HEAD_SIZE.x * 0.5, LAMP_HEAD_SIZE.y * 0.5),
			LAMP_HEIGHT, LAMP_HEIGHT + LAMP_HEAD_THICKNESS)


func _build_bench(by_color: Dictionary, bench: Dictionary) -> void:
	var batch: _Batch = _mesh_for(by_color, BENCH_COLOR)
	var at: Vector2 = bench.position
	var along: Vector2 = bench.along
	var to_road: Vector2 = bench.to_road
	_prism(batch, _rect(at, along, BENCH_LENGTH * 0.5 - 0.15, BENCH_DEPTH * 0.5 - 0.1), SIDEWALK_HEIGHT,
			SIDEWALK_HEIGHT + BENCH_BASE_HEIGHT)
	_prism(batch, _rect(at, along, BENCH_LENGTH * 0.5, BENCH_DEPTH * 0.5), SIDEWALK_HEIGHT + BENCH_BASE_HEIGHT,
			SIDEWALK_HEIGHT + BENCH_SEAT_HEIGHT)
	var back_at: Vector2 = at - to_road * (BENCH_DEPTH * 0.5 - BENCH_BACK_THICKNESS * 0.5)
	_prism(batch, _rect(back_at, along, BENCH_LENGTH * 0.5, BENCH_BACK_THICKNESS * 0.5),
			SIDEWALK_HEIGHT + BENCH_SEAT_HEIGHT, SIDEWALK_HEIGHT + BENCH_BACK_HEIGHT)


## A switched-off traffic light: at every corner of the junction a gray pole with a dark head turned to the
## crossing, and a control box at the foot of the first one.
func _build_light(parent: Node3D, node_id: StringName) -> void:
	var light := Node3D.new()
	light.name = "TrafficLight_%s" % node_id
	parent.add_child(light)
	var index: int = 0
	for corner: Dictionary in corners(node_id):
		var spot: Vector2 = corner.position
		var to_centre: Vector2 = corner.to_centre
		var yaw: float = atan2(-to_centre.x, -to_centre.y)
		var basis := Basis(Vector3.UP, yaw)
		RouteProps.box_at(light, "Pole_%d" % index, Vector3(LIGHT_POLE_SIZE, LIGHT_POLE_HEIGHT, LIGHT_POLE_SIZE),
				Transform3D(basis, Vector3(spot.x, SIDEWALK_HEIGHT + LIGHT_POLE_HEIGHT * 0.5, spot.y)),
				LIGHT_POLE_COLOR, true)
		var head: Vector2 = spot + to_centre * LIGHT_HEAD_REACH
		RouteProps.box_at(light, "Head_%d" % index, LIGHT_HEAD_SIZE,
				Transform3D(basis, Vector3(head.x, SIDEWALK_HEIGHT + LIGHT_POLE_HEIGHT - LIGHT_HEAD_DROP, head.y)),
				LIGHT_HEAD_COLOR)
		if index == 0:
			var box: Vector2 = spot - to_centre * LIGHT_POLE_SIZE
			RouteProps.box_at(light, "ControlBox", LIGHT_BOX_SIZE,
					Transform3D(basis, Vector3(box.x, SIDEWALK_HEIGHT + LIGHT_BOX_SIZE.y * 0.5, box.y)),
					LIGHT_POLE_COLOR, true)
		index += 1


# --- Index -----------------------------------------------------------------------------------------


func _entry(cell: Vector2i) -> Dictionary:
	if not _by_cell.has(cell):
		_by_cell[cell] = {"strips": [], "lamps": [], "benches": [], "lights": [], "houses": []}
	return _by_cell[cell]


func _slot(cell: Vector2i, key: String) -> Array:
	if not _by_cell.has(cell):
		return []
	return (_by_cell[cell] as Dictionary)[key]


func _index_roadways() -> void:
	for edge: RoadEdge in graph.edges:
		var line: PackedVector2Array = graph.sample_every(edge.id, SIDEWALK_STEP)
		for i in line.size() - 1:
			var polygon: PackedVector2Array = _band(line[i], line[i + 1], -ROADWAY_HALF_WIDTH, ROADWAY_HALF_WIDTH)
			var box: Rect2 = _bounds(polygon)
			for bucket: Vector2i in _buckets_of(box):
				if not _road_buckets.has(bucket):
					_road_buckets[bucket] = []
				(_road_buckets[bucket] as Array).append(_roadways.size())
			_roadways.append({"edge": edge.id, "polygon": polygon, "bounds": box})


func _buckets_of(box: Rect2) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var low := Vector2i(floori(box.position.x / BUCKET_SIZE), floori(box.position.y / BUCKET_SIZE))
	var high := Vector2i(floori(box.end.x / BUCKET_SIZE), floori(box.end.y / BUCKET_SIZE))
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			found.append(Vector2i(x, y))
	return found


func _index_houses() -> void:
	if houses == null:
		return
	for house: HouseSpot in houses.houses:
		if house.zone != ZONE:
			continue
		(_entry(cell_of(house.position))["houses"] as Array).append(house)
		for footprint: PackedVector2Array in house_footprints(house):
			for grown: PackedVector2Array in Geometry2D.offset_polygon(footprint, HOUSE_MARGIN):
				_blocks.append({"polygon": grown, "bounds": _bounds(grown)})


func _index_lights() -> void:
	var candidates: Array[RoadNode] = []
	for node: RoadNode in graph.nodes:
		if node.area == ZONE and graph.edges_at(node.id).size() >= LIGHT_MIN_STREETS:
			candidates.append(node)
	candidates.sort_custom(func(a: RoadNode, b: RoadNode) -> bool:
		var da: float = a.position.length()
		var db: float = b.position.length()
		return da < db if not is_equal_approx(da, db) else String(a.id) < String(b.id))
	for node: RoadNode in candidates.slice(0, LIGHT_COUNT):
		_light_nodes.append(node.id)
		(_entry(cell_of(node.position))["lights"] as Array).append(node.id)


func _index_edge(edge: RoadEdge) -> void:
	var points: PackedVector2Array = graph.sample_every(edge.id, SIDEWALK_STEP)
	for i in points.size() - 1:
		for side: int in [-1, 1]:
			var strip := {"edge": edge.id, "a": points[i], "b": points[i + 1], "side": side}
			(_entry(cell_of(points[i]))["strips"] as Array).append(strip)
	var length: float = graph.edge_length(edge.id)
	var lamp_index: int = 0
	var at: float = LAMP_FIRST
	while at <= length - PROP_END_CLEARANCE:
		if at >= PROP_END_CLEARANCE:
			var side: int = 1 if lamp_index % 2 == 0 else -1
			var lamp := _prop(edge, at, side, ROADWAY_HALF_WIDTH + SIDEWALK_WIDTH - LAMP_INSET)
			if not _blocked(lamp.position):
				(_entry(cell_of(lamp.position))["lamps"] as Array).append(lamp)
		lamp_index += 1
		at += LAMP_SPACING
	at = BENCH_FIRST
	while at <= length - PROP_END_CLEARANCE:
		var bench := _prop(edge, at, 1, ROADWAY_HALF_WIDTH + SIDEWALK_WIDTH * 0.5)
		if not _blocked(bench.position):
			(_entry(cell_of(bench.position))["benches"] as Array).append(bench)
		at += BENCH_SPACING


## A lamp or bench: `position` is `offset` meters off the street's axis, to `side`; `along` is the street's
## direction there and `to_road` the unit vector from the prop back to the roadway.
func _prop(edge: RoadEdge, distance: float, side: int, offset: float) -> Dictionary:
	var tangent: Vector2 = graph.tangent_at(edge.id, distance)
	var normal: Vector2 = tangent.orthogonal() * float(side)
	return {
		"position": graph.point_at(edge.id, distance) + normal * offset,
		"along": tangent,
		"to_road": -normal,
	}


func _blocked(ground: Vector2) -> bool:
	for block: Dictionary in _blocks:
		if (block.bounds as Rect2).has_point(ground) and Geometry2D.is_point_in_polygon(ground, block.polygon):
			return true
	return false


## One sidewalk piece without the cuts.
func _strip_polygon(strip: Dictionary) -> PackedVector2Array:
	var side: float = float(strip.side)
	var inner: float = ROADWAY_HALF_WIDTH * side
	var outer: float = (ROADWAY_HALF_WIDTH + SIDEWALK_WIDTH) * side
	return _band(strip.a, strip.b, minf(inner, outer), maxf(inner, outer))


## The cut sidewalks of a cell, made once: [{ edge, polygon }].
func _cut_cell(cell: Vector2i) -> Array:
	if not _cut_cache.has(cell):
		var made: Array = []
		for strip: Dictionary in _slot(cell, "strips"):
			for polygon: PackedVector2Array in _cut_strip(strip):
				made.append({"edge": strip.edge, "polygon": polygon})
		_cut_cache[cell] = made
	return _cut_cache[cell]


## The strip with every other roadway and every house cut out of it.
func _cut_strip(strip: Dictionary) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [_strip_polygon(strip)]
	var area: Rect2 = _bounds(pieces[0]).grow(0.05)
	var cutters: Array[Dictionary] = []
	var seen: Dictionary = {}
	for bucket: Vector2i in _buckets_of(area):
		for index: int in _road_buckets.get(bucket, []):
			var road: Dictionary = _roadways[index]
			if not seen.has(index) and road.edge != strip.edge and area.intersects(road.bounds):
				seen[index] = true
				cutters.append(road)
	for block: Dictionary in _blocks:
		if area.intersects(block.bounds):
			cutters.append(block)
	for cutter: Dictionary in cutters:
		var next: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in pieces:
			if not _bounds(piece).intersects(cutter.bounds):
				next.append(piece)
				continue
			next.append_array(Geometry2D.clip_polygons(piece, cutter.polygon))
		pieces = next
	var kept: Array[PackedVector2Array] = []
	for piece: PackedVector2Array in pieces:
		if absf(_signed_area(piece)) >= MIN_PIECE_AREA:
			kept.append(piece)
	return kept


# --- Geometry --------------------------------------------------------------------------------------


## The band between two offsets (`low` < `high`, meters to the left of a -> b) of a segment, as a quad.
static func _band(a: Vector2, b: Vector2, low: float, high: float) -> PackedVector2Array:
	var normal: Vector2 = (b - a).normalized().orthogonal()
	return PackedVector2Array([a + normal * low, b + normal * low, b + normal * high, a + normal * high])


## A rectangle `half_length` each way along `forward` and `half_width` across it.
static func _rect(centre: Vector2, forward: Vector2, half_length: float, half_width: float) -> PackedVector2Array:
	var side: Vector2 = forward.orthogonal()
	return PackedVector2Array([
		centre - forward * half_length - side * half_width, centre + forward * half_length - side * half_width,
		centre + forward * half_length + side * half_width, centre - forward * half_length + side * half_width,
	])


static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var low: Vector2 = polygon[0]
	var high: Vector2 = polygon[0]
	for p: Vector2 in polygon:
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	return Rect2(low, high - low)


static func _signed_area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in polygon.size():
		var p: Vector2 = polygon[i]
		var q: Vector2 = polygon[(i + 1) % polygon.size()]
		total += p.x * q.y - q.x * p.y
	return total * 0.5


func _mesh_for(by_color: Dictionary, color: Color) -> _Batch:
	if not by_color.has(color):
		by_color[color] = _Batch.new()
	return by_color[color]


## A prism over a ground outline from `bottom` to `top` (no underside): top face and a wall per edge.
func _prism(batch: _Batch, outline: PackedVector2Array, bottom: float, top: float) -> void:
	var ring: PackedVector2Array = outline
	# Walls point outward when the outline runs the way (x, z) shoelace calls negative.
	if _signed_area(ring) > 0.0:
		ring = PackedVector2Array()
		for i in range(outline.size() - 1, -1, -1):
			ring.append(outline[i])
	var corners_: PackedInt32Array = Geometry2D.triangulate_polygon(ring)
	for i in range(0, corners_.size(), 3):
		batch.triangle(_up(ring[corners_[i]], top), _up(ring[corners_[i + 1]], top), _up(ring[corners_[i + 2]], top),
				Vector3.UP)
	for i in ring.size():
		var p: Vector2 = ring[i]
		var q: Vector2 = ring[(i + 1) % ring.size()]
		var facing: Vector3 = Vector3(-(q.y - p.y), 0.0, q.x - p.x).normalized()
		batch.triangle(_up(p, bottom), _up(q, bottom), _up(q, top), facing)
		batch.triangle(_up(p, bottom), _up(q, top), _up(p, top), facing)


static func _up(ground: Vector2, height: float) -> Vector3:
	return Vector3(ground.x, height, ground.y)


## The houses of a cell, put in the tree a few per frame (HOUSES_PER_FRAME) instead of all with the cell.
## The ones not in yet are freed with the node if the cell goes first.
class HouseDrip extends Node3D:
	var pending: Array[Node3D] = []
	var per_frame: int = 1

	func _process(_delta: float) -> void:
		release(per_frame)

	## Puts the next `count` pending houses in the tree.
	func release(count: int) -> void:
		for i in count:
			if pending.is_empty():
				break
			add_child(pending.pop_front())
		set_process(not pending.is_empty())

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			for house: Node3D in pending:
				if is_instance_valid(house):
					house.free()
			pending.clear()


## Triangles with their face normal, one surface.
class _Batch extends RefCounted:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()

	## Godot draws the clockwise side of a triangle: the corners are put in the order that faces `normal`.
	func triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
		if (b - a).cross(c - a).dot(normal) > 0.0:
			var swap: Vector3 = b
			b = c
			c = swap
		vertices.append_array(PackedVector3Array([a, b, c]))
		normals.append_array(PackedVector3Array([normal, normal, normal]))

	func to_mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
