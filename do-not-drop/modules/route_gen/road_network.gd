class_name RoadNetwork
extends Resource
## A street map as a graph: RoadNodes joined by RoadEdges that are cubic Beziers.
## Pure data and geometry, no scene nodes (portable module, docs/modulos.md): the
## owner builds meshes, terrain spans and pieces from what it answers.
##
## - Geometry: every edge is flattened once into a polyline (FLATTEN_STEP apart)
##   with its running length, so length, point_at, tangent_at, sample_every and
##   nearest_point agree with each other.
## - Travel: distances_from() and shortest_path() walk the graph by length. A gate
##   node whose lock is not in `open_locks` can be reached but not crossed.
## - Checks: validate() lists what is wrong with the data, crossing_pairs() the
##   streets that cross without a node.
##
## A network that is edited after it was queried needs invalidate().

## Flattening: one polyline point every this many meters of control polygon.
const FLATTEN_STEP: float = 4.0
const FLATTEN_MIN_STEPS: int = 8
const FLATTEN_MAX_STEPS: int = 400
## Crossings this close to a node both streets share are the node itself.
const NODE_TOUCH_RADIUS: float = 1.0
## A street shorter than this is a mistake.
const MIN_EDGE_LENGTH: float = 1.0

@export var nodes: Array[RoadNode] = []
@export var edges: Array[RoadEdge] = []

var _indexed: bool = false
var _node_index: Dictionary = {}
var _edge_index: Dictionary = {}
## node id -> Array[RoadEdge]
var _adjacent: Dictionary = {}
## edge id -> { "points": PackedVector2Array, "along": PackedFloat64Array }
var _lines: Dictionary = {}


## Point of a cubic Bezier at t (0..1).
static func bezier_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


## Forget what was worked out. Call after changing nodes, edges or their fields.
func invalidate() -> void:
	_indexed = false
	_node_index.clear()
	_edge_index.clear()
	_adjacent.clear()
	_lines.clear()


func node_by_id(node_id: StringName) -> RoadNode:
	_ensure_index()
	return _node_index.get(node_id) as RoadNode


func edge_by_id(edge_id: StringName) -> RoadEdge:
	_ensure_index()
	return _edge_index.get(edge_id) as RoadEdge


## The streets that start or end at the node.
func edges_at(node_id: StringName) -> Array[RoadEdge]:
	_ensure_index()
	var found: Array[RoadEdge] = []
	found.assign(_adjacent.get(node_id, []))
	return found


## The node at the other end of `edge` from `node_id`.
func other_end(edge: RoadEdge, node_id: StringName) -> StringName:
	return edge.to_id if edge.from_id == node_id else edge.from_id


## The street flattened, from its from node to its to node. Empty when an end
## node does not exist.
func centerline(edge_id: StringName) -> PackedVector2Array:
	return _line(edge_id).get("points", PackedVector2Array())


func edge_length(edge_id: StringName) -> float:
	var along: PackedFloat64Array = _line(edge_id).get("along", PackedFloat64Array())
	return 0.0 if along.is_empty() else along[along.size() - 1]


func total_length() -> float:
	var total: float = 0.0
	for edge: RoadEdge in edges:
		total += edge_length(edge.id)
	return total


## The point `distance` meters along the street (clamped to its ends).
func point_at(edge_id: StringName, distance: float) -> Vector2:
	var line: Dictionary = _line(edge_id)
	if line.is_empty():
		return Vector2.ZERO
	var points: PackedVector2Array = line.points
	var i: int = _segment_index(line.along, distance)
	var seg_start: float = line.along[i]
	var seg_len: float = line.along[i + 1] - seg_start
	var t: float = 0.0 if seg_len <= 0.0 else clampf((distance - seg_start) / seg_len, 0.0, 1.0)
	return points[i].lerp(points[i + 1], t)


## The unit direction of travel (from node to to node) `distance` meters along.
func tangent_at(edge_id: StringName, distance: float) -> Vector2:
	var line: Dictionary = _line(edge_id)
	if line.is_empty():
		return Vector2.ZERO
	var points: PackedVector2Array = line.points
	var i: int = _segment_index(line.along, distance)
	return (points[i + 1] - points[i]).normalized()


## Points roughly `spacing` meters apart along the street, both ends included
## (the spacing is evened out so the last gap is not a stub).
func sample_every(edge_id: StringName, spacing: float) -> PackedVector2Array:
	var samples := PackedVector2Array()
	var length: float = edge_length(edge_id)
	if length <= 0.0:
		return samples
	var count: int = maxi(1, roundi(length / maxf(spacing, 0.01)))
	for i in count + 1:
		samples.append(point_at(edge_id, length * float(i) / float(count)))
	return samples


## The cells (Vector2i, floor(position / cell_size)) the street passes through.
func cells_crossed(edge_id: StringName, cell_size: float) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var seen: Dictionary = {}
	for p: Vector2 in sample_every(edge_id, cell_size * 0.25):
		var cell := Vector2i(floori(p.x / cell_size), floori(p.y / cell_size))
		if not seen.has(cell):
			seen[cell] = true
			found.append(cell)
	return found


## The closest point of any street to `p`: { edge, along, point, distance }, or an
## empty dictionary when the farthest allowed is `max_distance` and nothing is that near.
func nearest_point(p: Vector2, max_distance: float = INF) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = max_distance
	for edge: RoadEdge in edges:
		var line: Dictionary = _line(edge.id)
		if line.is_empty():
			continue
		var points: PackedVector2Array = line.points
		for i in points.size() - 1:
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])
			var d: float = p.distance_to(closest)
			if d < best_distance:
				best_distance = d
				best = {
					"edge": edge.id,
					"along": line.along[i] + points[i].distance_to(closest),
					"point": closest,
					"distance": d,
				}
	return best


## Length of the shortest way from `start_id` to every node it can reach:
## node id -> meters. Locks listed in `open_locks` let a gate node be crossed.
func distances_from(start_id: StringName, open_locks: Array = []) -> Dictionary:
	return _walk(start_id, open_locks).dist


## The node ids from `from_id` to `to_id` by the shortest way, both included.
## Empty when there is none.
func shortest_path(from_id: StringName, to_id: StringName, open_locks: Array = []) -> Array[StringName]:
	var walk: Dictionary = _walk(from_id, open_locks)
	var path: Array[StringName] = []
	if not walk.dist.has(to_id):
		return path
	var at: StringName = to_id
	while at != &"":
		path.push_front(at)
		at = walk.prev.get(at, &"")
	return path


## Pairs [edge_id, edge_id] of streets that cross somewhere other than at a node
## they share (a crossing needs a junction).
func crossing_pairs() -> Array:
	var pairs: Array = []
	var boxes: Array[Rect2] = []
	for edge: RoadEdge in edges:
		boxes.append(_bounds(centerline(edge.id)))
	for i in edges.size():
		for j in range(i + 1, edges.size()):
			if boxes[i].intersects(boxes[j], true) and _lines_cross(edges[i], edges[j]):
				pairs.append([edges[i].id, edges[j].id])
	return pairs


## What is wrong with the data, one line each. Empty when the network is sound:
## unique ids, known kinds and surfaces, every street between two nodes that
## exist, a gate with a lock, a dead end with one street, no loose node.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen: Dictionary = {}
	for node: RoadNode in nodes:
		if node == null or node.id == &"" or seen.has(node.id):
			problems.append("node id empty or repeated: %s" % (node.id if node != null else "null"))
			continue
		seen[node.id] = true
		if not RoadNode.KINDS.has(node.kind):
			problems.append("node %s: unknown kind %s" % [node.id, node.kind])
		if node.kind == &"gate" and node.lock_id == &"":
			problems.append("node %s: a gate needs a lock_id" % node.id)
		if node.kind != &"gate" and node.lock_id != &"":
			problems.append("node %s: only a gate has a lock_id" % node.id)
	var seen_edges: Dictionary = {}
	for edge: RoadEdge in edges:
		if edge == null or edge.id == &"" or seen_edges.has(edge.id):
			problems.append("edge id empty or repeated: %s" % (edge.id if edge != null else "null"))
			continue
		seen_edges[edge.id] = true
		problems.append_array(_edge_problems(edge, seen))
	_ensure_index()
	for node: RoadNode in nodes:
		if node == null or not _node_index.has(node.id):
			continue
		var degree: int = edges_at(node.id).size()
		if degree == 0:
			problems.append("node %s: no street reaches it" % node.id)
		elif node.kind == &"dead_end" and degree != 1:
			problems.append("node %s: a dead end has one street, not %d" % [node.id, degree])
	return problems


func _edge_problems(edge: RoadEdge, known_nodes: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	for end_id: StringName in [edge.from_id, edge.to_id]:
		if not known_nodes.has(end_id):
			problems.append("edge %s: node %s does not exist" % [edge.id, end_id])
	if edge.from_id == edge.to_id:
		problems.append("edge %s: starts and ends at %s" % [edge.id, edge.from_id])
	if not RoadEdge.SURFACES.has(edge.surface):
		problems.append("edge %s: unknown surface %s" % [edge.id, edge.surface])
	if edge.width <= 0.0:
		problems.append("edge %s: width must be above 0" % edge.id)
	if known_nodes.has(edge.from_id) and known_nodes.has(edge.to_id) and edge_length(edge.id) < MIN_EDGE_LENGTH:
		problems.append("edge %s: shorter than %d m" % [edge.id, int(MIN_EDGE_LENGTH)])
	return problems


func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	for node: RoadNode in nodes:
		if node != null:
			_node_index[node.id] = node
			_adjacent[node.id] = []
	for edge: RoadEdge in edges:
		if edge == null:
			continue
		_edge_index[edge.id] = edge
		for end_id: StringName in [edge.from_id, edge.to_id]:
			if _adjacent.has(end_id):
				_adjacent[end_id].append(edge)


## The flattened street: { points, along } (along[i] = meters from the start).
func _line(edge_id: StringName) -> Dictionary:
	if _lines.has(edge_id):
		return _lines[edge_id]
	var edge: RoadEdge = edge_by_id(edge_id)
	if edge == null:
		return {}
	var from: RoadNode = _node_index.get(edge.from_id)
	var to: RoadNode = _node_index.get(edge.to_id)
	if from == null or to == null:
		return {}
	var p0: Vector2 = from.position
	var p3: Vector2 = to.position
	var p1: Vector2 = p0 + edge.out_handle
	var p2: Vector2 = p3 + edge.in_handle
	var reach: float = p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p3)
	var steps: int = clampi(ceili(reach / FLATTEN_STEP), FLATTEN_MIN_STEPS, FLATTEN_MAX_STEPS)
	var points := PackedVector2Array()
	var along := PackedFloat64Array()
	var run: float = 0.0
	for i in steps + 1:
		var point: Vector2 = bezier_point(p0, p1, p2, p3, float(i) / float(steps))
		if i > 0:
			run += points[i - 1].distance_to(point)
		points.append(point)
		along.append(run)
	var line: Dictionary = {"points": points, "along": along}
	_lines[edge_id] = line
	return line


## Index i of the polyline segment that holds `distance`, so i + 1 exists.
func _segment_index(along: PackedFloat64Array, distance: float) -> int:
	var low: int = 0
	var high: int = along.size() - 2
	while low < high:
		var mid: int = (low + high + 1) >> 1
		if along[mid] <= distance:
			low = mid
		else:
			high = mid - 1
	return low


## Dijkstra by street length: { dist: node id -> meters, prev: node id -> node id }.
func _walk(start_id: StringName, open_locks: Array) -> Dictionary:
	_ensure_index()
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	if not _node_index.has(start_id):
		return {"dist": dist, "prev": prev}
	dist[start_id] = 0.0
	var pending: Array[StringName] = [start_id]
	var done: Dictionary = {}
	while not pending.is_empty():
		var at: StringName = pending[0]
		for candidate: StringName in pending:
			if dist[candidate] < dist[at]:
				at = candidate
		pending.erase(at)
		done[at] = true
		if at != start_id and _is_closed(_node_index[at], open_locks):
			continue
		for edge: RoadEdge in _adjacent[at]:
			var next: StringName = other_end(edge, at)
			var reach: float = dist[at] + edge_length(edge.id)
			if not done.has(next) and reach < dist.get(next, INF):
				if not dist.has(next):
					pending.append(next)
				dist[next] = reach
				prev[next] = at
	return {"dist": dist, "prev": prev}


func _is_closed(node: RoadNode, open_locks: Array) -> bool:
	return node.kind == &"gate" and node.lock_id != &"" and not open_locks.has(node.lock_id)


func _bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var box := Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		box = box.expand(p)
	return box


func _lines_cross(a: RoadEdge, b: RoadEdge) -> bool:
	var shared: Array[Vector2] = []
	for end_id: StringName in [a.from_id, a.to_id]:
		if end_id == b.from_id or end_id == b.to_id:
			shared.append((_node_index[end_id] as RoadNode).position)
	var pa: PackedVector2Array = centerline(a.id)
	var pb: PackedVector2Array = centerline(b.id)
	for i in pa.size() - 1:
		for j in pb.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(pa[i], pa[i + 1], pb[j], pb[j + 1])
			if hit == null:
				continue
			var touches_node: bool = false
			for node_position: Vector2 in shared:
				touches_node = touches_node or (hit as Vector2).distance_to(node_position) <= NODE_TOUCH_RADIUS
			if not touches_node:
				return true
	return false
