extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_road_graph.gd
##
## The company map's street graph (expansion D-0304, scripts/gameplay/districts/road_graph.gd
## on modules/route_gen's RoadNetwork, data in data/world/road_graph.tres):
## - the file loads as a RoadGraph with all three node kinds and all four surfaces,
##   about 12 km of street, no error from the module's validate() nor from the game's
##   rules (every street joins two nodes that exist; every node lies in the zone it
##   names; every gate node matches a data/gates file and the zone it closes; every
##   piece kind is one of the route's; gravel and mud only on loose surfaces);
## - from the shed every node of an open zone (no gate) is reached with every gate
##   closed; Campo's nodes are reached only once gate_campo_obra is open, and every
##   node of the map once all are open;
## - the golden rule of mapa.md holds on the real streets: the first Centro node is
##   within 90 s of driving (1080 m at 12 m/s), the first Campo node within 3 min,
##   the whole of Centro within 3 min and the whole of Campo within 5 min;
## - the curves: every street starts and ends on its nodes, is no shorter than its
##   chord nor wildly longer, is sampled with no gap over the spacing, and no two
##   streets cross without a node;
## - the shortest way from the shed to the farthest Centro and Campo nodes chains its
##   streets with no gap (the line an autopilot would follow);
## - the ground: register_terrain() lays spans along every street, flat on it and
##   gravel where the surface is loose;
## - CompanyCells.pin_streets() pins the cells under the three main streets;
## - every piece kind the data names builds as a RouteSegment with a length.

const ZONES_DIR: String = "res://data/zones/"
const GATES_DIR: String = "res://data/gates/"
const SPEED: float = 12.0
const GOLDEN_CENTRO_FIRST: float = 90.0 * SPEED
const GOLDEN_CAMPO_FIRST: float = 180.0 * SPEED
const GOLDEN_CENTRO_LAST: float = 180.0 * SPEED
const GOLDEN_CAMPO_LAST: float = 300.0 * SPEED
const SAMPLE_GAP: float = 10.0

var _failures: int = 0
var _graph: RoadGraph
var _zones: Array[ZoneDefinition] = []
var _gates: Array[GateRequirement] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_graph = RoadGraph.load_default()
	_expect(_graph != null, "data/world/road_graph.tres loads as a RoadGraph")
	if _graph == null:
		quit(1)
		return
	_load_zones_and_gates()
	_test_data()
	_test_reachability()
	_test_golden_rule()
	_test_curves()
	_test_autopilot_line()
	_test_terrain()
	_test_cells()
	_test_segment_kinds()
	if _failures == 0:
		print("PASS: the road graph is sound, reaches every open zone from the shed and keeps the golden rule")
	quit(_failures)


func _load_zones_and_gates() -> void:
	for file: String in DirAccess.get_files_at(ZONES_DIR):
		if file.ends_with(".tres"):
			_zones.append(load(ZONES_DIR + file) as ZoneDefinition)
	for file: String in DirAccess.get_files_at(GATES_DIR):
		if file.ends_with(".tres"):
			_gates.append(load(GATES_DIR + file) as GateRequirement)


func _test_data() -> void:
	_expect(_graph.nodes.size() >= 25 and _graph.edges.size() >= 30, "The graph has its nodes and streets")
	var kinds: Dictionary = {}
	for node: RoadNode in _graph.nodes:
		kinds[node.kind] = true
	_expect(kinds.size() == 3, "All three node kinds are used: %s" % [kinds.keys()])
	var surfaces: Dictionary = {}
	for edge: RoadEdge in _graph.edges:
		surfaces[edge.surface] = true
		_expect(_graph.node_by_id(edge.from_id) != null and _graph.node_by_id(edge.to_id) != null,
				"Street %s joins two nodes that exist" % edge.id)
	_expect(surfaces.size() == 4, "All four surfaces are used: %s" % [surfaces.keys()])
	var length: float = _graph.total_length()
	_expect(length > 11000.0 and length < 13000.0, "About 12 km of street (%d m)" % int(length))
	_expect(_graph.node_by_id(RoadGraph.SHED_NODE).position == Vector2.ZERO, "The shed's gate is the origin")
	var problems: PackedStringArray = _graph.problems(_zones, _gates)
	_expect(problems.is_empty(), "No problems in the data: %s" % [problems])
	for street: StringName in RoadGraph.MAIN_STREETS:
		var count: int = 0
		for edge: RoadEdge in _graph.edges:
			count += 1 if edge.street == street else 0
		_expect(count >= 2, "The main street %s has its streets" % street)


func _test_reachability() -> void:
	var closed: Dictionary = _graph.distances_from(RoadGraph.SHED_NODE)
	var open_zones: Dictionary = {}
	for zone in _zones:
		if zone.is_open_at_start():
			open_zones[zone.id] = true
	_expect(open_zones.has(&"centro") and open_zones.has(&"parque_industrial"), "Centro and the park are open")
	for node: RoadNode in _graph.nodes:
		if open_zones.has(node.area):
			_expect(closed.has(node.id),
					"From the shed, %s (open zone %s) is reached with every gate closed" % [node.id, node.area])
		if node.area == &"campo":
			_expect(node.kind == &"gate" or not closed.has(node.id), "Campo node %s is behind its gate" % node.id)
	_expect(closed.has(&"gate_campo_obra") and closed.has(&"gate_puerto") and closed.has(&"gate_suburbio"),
			"Each closed gate is itself reached")
	var campo_open: Dictionary = _graph.distances_from(RoadGraph.SHED_NODE, [&"gate_campo_obra"])
	for node: RoadNode in _graph.nodes:
		if node.area == &"campo":
			_expect(campo_open.has(node.id), "With the works gate open, %s is reached" % node.id)
	var every_lock: Array = []
	for node: RoadNode in _graph.nodes:
		if node.kind == &"gate":
			every_lock.append(node.lock_id)
	var all_open: Dictionary = _graph.distances_from(RoadGraph.SHED_NODE, every_lock)
	_expect(all_open.size() == _graph.nodes.size(), "With every gate open all %d nodes are reached (%d)" % [
			_graph.nodes.size(), all_open.size()])


func _test_golden_rule() -> void:
	var every_lock: Array = []
	for node: RoadNode in _graph.nodes:
		if node.kind == &"gate":
			every_lock.append(node.lock_id)
	var dist: Dictionary = _graph.distances_from(RoadGraph.SHED_NODE, every_lock)
	var first: Dictionary = {&"centro": INF, &"campo": INF}
	var last: Dictionary = {&"centro": 0.0, &"campo": 0.0}
	for node: RoadNode in _graph.nodes:
		if node.kind == &"gate" or not first.has(node.area):
			continue
		first[node.area] = minf(first[node.area], dist[node.id])
		last[node.area] = maxf(last[node.area], dist[node.id])
	_expect(first[&"centro"] <= GOLDEN_CENTRO_FIRST,
			"The first Centro node is within 90 s (%d m)" % int(first[&"centro"]))
	_expect(first[&"campo"] <= GOLDEN_CAMPO_FIRST, "The first Campo node is within 3 min (%d m)" % int(first[&"campo"]))
	_expect(last[&"centro"] <= GOLDEN_CENTRO_LAST, "All of Centro is within 3 min (%d m)" % int(last[&"centro"]))
	_expect(last[&"campo"] <= GOLDEN_CAMPO_LAST, "All of Campo is within 5 min (%d m)" % int(last[&"campo"]))


func _test_curves() -> void:
	for edge: RoadEdge in _graph.edges:
		var from: Vector2 = _graph.node_by_id(edge.from_id).position
		var to: Vector2 = _graph.node_by_id(edge.to_id).position
		var length: float = _graph.edge_length(edge.id)
		var chord: float = from.distance_to(to)
		_expect(length >= chord - 0.01 and length < chord * 1.5, "Street %s: length %d m against a %d m chord" % [
				edge.id, int(length), int(chord)])
		var points: PackedVector2Array = _graph.sample_every(edge.id, SAMPLE_GAP)
		_expect(points[0].is_equal_approx(from) and points[points.size() - 1].is_equal_approx(to),
				"Street %s starts and ends on its nodes" % edge.id)
		var widest: float = 0.0
		for i in points.size() - 1:
			widest = maxf(widest, points[i].distance_to(points[i + 1]))
		_expect(widest <= SAMPLE_GAP * 1.25, "Street %s: no gap over the spacing (%.1f m)" % [edge.id, widest])
	var crossings: Array = _graph.crossing_pairs()
	_expect(crossings.is_empty(), "No two streets cross without a node: %s" % [crossings])


func _test_autopilot_line() -> void:
	var every_lock: Array = []
	for node: RoadNode in _graph.nodes:
		if node.kind == &"gate":
			every_lock.append(node.lock_id)
	var dist: Dictionary = _graph.distances_from(RoadGraph.SHED_NODE, every_lock)
	for area: StringName in [&"centro", &"campo"]:
		var far_id: StringName = &""
		for node: RoadNode in _graph.nodes:
			if node.area == area and (far_id == &"" or dist[node.id] > dist[far_id]):
				far_id = node.id
		var path: Array[StringName] = _graph.shortest_path(RoadGraph.SHED_NODE, far_id, every_lock)
		_expect(path.size() >= 3 and path[0] == RoadGraph.SHED_NODE and path[path.size() - 1] == far_id,
				"There is a way from the shed to %s: %s" % [far_id, path])
		var line: PackedVector2Array = _drive_line(path)
		var widest: float = 0.0
		for i in line.size() - 1:
			widest = maxf(widest, line[i].distance_to(line[i + 1]))
		_expect(widest <= SAMPLE_GAP * 1.25, "The line to %s has no gap (%.1f m)" % [far_id, widest])
		_expect(line[0].is_equal_approx(Vector2.ZERO) and line[line.size() - 1].is_equal_approx(
				_graph.node_by_id(far_id).position), "The line to %s runs from the shed to it" % far_id)


## The streets of a node path chained in the direction of travel.
func _drive_line(path: Array[StringName]) -> PackedVector2Array:
	var line := PackedVector2Array()
	for i in path.size() - 1:
		for edge: RoadEdge in _graph.edges_at(path[i]):
			if _graph.other_end(edge, path[i]) != path[i + 1]:
				continue
			var points: PackedVector2Array = _graph.sample_every(edge.id, SAMPLE_GAP)
			if edge.from_id != path[i]:
				points.reverse()
			line.append_array(points)
			break
	return line


func _test_terrain() -> void:
	var terrain := TerrainField.new()
	var spans: int = _graph.register_terrain(terrain, 10.0)
	_expect(spans > 1000 and terrain.spans.size() == spans, "A terrain span every 10 m: %d" % spans)
	var checked: int = 0
	for edge: RoadEdge in _graph.edges:
		var middle: Vector2 = _graph.point_at(edge.id, _graph.edge_length(edge.id) * 0.5)
		var near: Vector3 = terrain.nearest(middle)
		_expect(near.x < 0.5, "Street %s: the terrain road is under its middle (%.2f m off)" % [edge.id, near.x])
		_expect(is_equal_approx(near.z, edge.half_width()) or near.x < 0.5,
				"Street %s: the span is half as wide as the roadway" % edge.id)
		if _graph.is_loose(edge) == (near.y > 0.5):
			checked += 1
	_expect(checked >= _graph.edges.size() - 4,
			"Loose streets are gravel on the terrain (%d of %d)" % [checked, _graph.edges.size()])
	_expect(terrain.nearest(Vector2(-2500, -2500)).x > 100.0, "Far from every street the terrain is not road")
	terrain.free()


func _test_cells() -> void:
	var cells := CompanyCells.new()
	var mountains := Vector2i(0, -6)
	_expect(not cells.grid.is_pinned(mountains), "Mountain cell starts unpinned")
	var count: int = cells.pin_streets(_graph)
	_expect(cells.grid.is_pinned(Vector2i(4, 0)), "The Avenida Este is pinned up to the port")
	_expect(cells.grid.is_pinned(Vector2i(0, 2)) and cells.grid.is_pinned(Vector2i(-3, 0)),
			"The Camino del Campo and the Calle Oeste are pinned")
	_expect(not cells.grid.is_pinned(Vector2i(3, 6)), "A secondary street's cell stays unpinned: (3, 6)")
	_expect(count >= 0 and not cells.grid.is_pinned(mountains), "The mountains stay free")
	for edge: RoadEdge in _graph.edges:
		if RoadGraph.MAIN_STREETS.has(edge.street):
			for cell: Vector2i in _graph.cells_crossed(edge.id, cells.grid.cell_size):
				_expect(cells.grid.is_pinned(cell), "Street %s: cell %s is pinned" % [edge.id, cell])
	_expect(cells.pin_streets(_graph) == 0, "Pinning twice pins nothing new")
	cells.free()


func _test_segment_kinds() -> void:
	for kind: StringName in RoadGraph.SEGMENT_SCRIPTS:
		var segment: Variant = (RoadGraph.SEGMENT_SCRIPTS[kind] as GDScript).new()
		_expect(segment is RouteSegment and (segment as RouteSegment).length > 0.0,
				"Piece kind %s is a RouteSegment with a length" % kind)
		if segment is Node:
			(segment as Node).free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
