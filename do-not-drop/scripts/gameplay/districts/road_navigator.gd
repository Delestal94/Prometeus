class_name RoadNavigator
extends RefCounted
## The GPS's path finder over the company map (expansion D-0308).
##
## Pure functions over a RoadNetwork (RoadGraph in the game): no node, no autoload. route() finds the
## quickest way between two points of the map, weighing each street by length / typical speed of its
## surface (CompanyTuning.SURFACE_SPEED), never crossing a gate node whose lock is not in open_locks.
## guidance() then reads that route for a vehicle at a position: meters and seconds left and the
## waypoint the arrow points at. Points are Vector2 (x, z) on the map.
##
## Not wired to the dashboard yet (D-0308.1 in detalle/F1-03-distritos.md).

const DEFAULT_SPEED: float = 10.0
## Spacing of the points of a route's polyline, in meters.
const POLYLINE_STEP: float = 8.0
const REASON_OFF_MAP: StringName = &"off_map"
const REASON_GATE_CLOSED: StringName = &"gate_closed"
const REASON_NO_WAY: StringName = &"no_way"


## The quickest way from `from` to `to`, both snapped to the nearest street:
## { ok, seconds, length, polyline: PackedVector2Array, edges: Array[StringName], nodes: Array[StringName],
## locks: Array[StringName] (gates it passes) }. Not ok: { ok: false, reason, locks } where reason is
## off_map, gate_closed (locks lists the gates that would open the way) or no_way.
static func route(net: RoadNetwork, from: Vector2, to: Vector2, open_locks: Array = []) -> Dictionary:
	var found: Dictionary = _solve(net, from, to, open_locks)
	if found.ok or found.reason != REASON_NO_WAY:
		return found
	var every_lock: Array = []
	for node: RoadNode in net.nodes:
		if node.kind == &"gate" and node.lock_id != &"":
			every_lock.append(node.lock_id)
	var unlocked: Dictionary = _solve(net, from, to, every_lock)
	if unlocked.ok:
		var needed: Array[StringName] = []
		for lock: StringName in unlocked.locks:
			if not open_locks.has(lock):
				needed.append(lock)
		return {"ok": false, "reason": REASON_GATE_CLOSED, "locks": needed}
	return {"ok": false, "reason": REASON_NO_WAY, "locks": [] as Array[StringName]}


## What the dashboard shows for a vehicle at `position` on a route() result:
## { distance (m left), seconds (left), waypoint: Vector3 (the point `ahead` meters on), done }.
## Empty when the route is not ok.
static func guidance(planned: Dictionary, position: Vector2, ahead: float = 30.0) -> Dictionary:
	if not planned.get("ok", false):
		return {}
	var line: PackedVector2Array = planned.polyline
	var total: float = 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	# The closest point of the polyline, as meters travelled along it.
	var best_along: float = 0.0
	var best_d: float = INF
	var walked: float = 0.0
	for i in line.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(position, line[i], line[i + 1])
		var d: float = position.distance_to(closest)
		if d < best_d:
			best_d = d
			best_along = walked + line[i].distance_to(closest)
		walked += line[i].distance_to(line[i + 1])
	var left: float = maxf(0.0, total - best_along)
	var target: Vector2 = _along(line, minf(total, best_along + ahead))
	return {
		"distance": left,
		"seconds": float(planned.seconds) * (left / total) if total > 0.0 else 0.0,
		"waypoint": Vector3(target.x, 0.0, target.y),
		"done": left <= 1.0,
	}


## Seconds to drive `meters` of a street with this surface.
static func seconds_for(edge: RoadEdge, meters: float) -> float:
	return meters / float(CompanyTuning.SURFACE_SPEED.get(edge.surface, DEFAULT_SPEED))


static func _solve(net: RoadNetwork, from: Vector2, to: Vector2, open_locks: Array) -> Dictionary:
	var a: Dictionary = net.nearest_point(from)
	var b: Dictionary = net.nearest_point(to)
	if a.is_empty() or b.is_empty():
		return {"ok": false, "reason": REASON_OFF_MAP, "locks": [] as Array[StringName]}
	var edge_a: RoadEdge = net.edge_by_id(a.edge)
	var edge_b: RoadEdge = net.edge_by_id(b.edge)
	var along_a: float = a.along
	var along_b: float = b.along
	var best_seconds: float = INF
	var best: Dictionary = {}
	# Both on the same street: straight along it, no node to cross.
	if edge_a.id == edge_b.id:
		best_seconds = seconds_for(edge_a, absf(along_a - along_b))
		best = {"same": true}
	# Dijkstra from the two ends of the street the vehicle is on.
	var dist: Dictionary = {}
	var prev_node: Dictionary = {}
	var prev_edge: Dictionary = {}
	var length_a: float = net.edge_length(edge_a.id)
	var starts: Dictionary = {edge_a.from_id: along_a, edge_a.to_id: length_a - along_a}
	for node_id: StringName in starts:
		dist[node_id] = seconds_for(edge_a, starts[node_id])
	var pending: Array[StringName] = []
	pending.assign(starts.keys())
	var done: Dictionary = {}
	while not pending.is_empty():
		var at: StringName = pending[0]
		for candidate: StringName in pending:
			if dist[candidate] < dist[at]:
				at = candidate
		pending.erase(at)
		done[at] = true
		if _closed(net, at, open_locks):
			continue
		for edge: RoadEdge in net.edges_at(at):
			var next: StringName = net.other_end(edge, at)
			var reach: float = dist[at] + seconds_for(edge, net.edge_length(edge.id))
			if not done.has(next) and reach < dist.get(next, INF):
				if not dist.has(next):
					pending.append(next)
				dist[next] = reach
				prev_node[next] = at
				prev_edge[next] = edge.id
	var length_b: float = net.edge_length(edge_b.id)
	var ends: Dictionary = {edge_b.from_id: along_b, edge_b.to_id: length_b - along_b}
	var end_node: StringName = &""
	for node_id: StringName in ends:
		if not dist.has(node_id) or _closed(net, node_id, open_locks):
			continue
		var total: float = dist[node_id] + seconds_for(edge_b, ends[node_id])
		if total < best_seconds:
			best_seconds = total
			end_node = node_id
			best = {"same": false}
	if best.is_empty():
		return {"ok": false, "reason": REASON_NO_WAY, "locks": [] as Array[StringName]}
	return _build(net, a, b, best.same, end_node, prev_node, prev_edge, best_seconds)


static func _build(
	net: RoadNetwork, a: Dictionary, b: Dictionary, same: bool, end_node: StringName,
	prev_node: Dictionary, prev_edge: Dictionary, seconds: float
) -> Dictionary:
	var line := PackedVector2Array()
	var edges: Array[StringName] = [a.edge]
	var nodes: Array[StringName] = []
	if same:
		_append(line, _slice(net, a.edge, a.along, b.along))
	else:
		# Walk back from the street's end node to the node the trip left the first street by.
		var chain_nodes: Array[StringName] = [end_node]
		var chain_edges: Array[StringName] = []
		var at: StringName = end_node
		while prev_node.has(at):
			chain_edges.push_front(prev_edge[at])
			at = prev_node[at]
			chain_nodes.push_front(at)
		var first: RoadEdge = net.edge_by_id(a.edge)
		var first_node: StringName = chain_nodes[0]
		var first_along: float = 0.0 if first_node == first.from_id else net.edge_length(first.id)
		_append(line, _slice(net, a.edge, a.along, first_along))
		nodes = chain_nodes
		for i in chain_edges.size():
			var edge: RoadEdge = net.edge_by_id(chain_edges[i])
			var forward: bool = edge.from_id == chain_nodes[i]
			var length: float = net.edge_length(edge.id)
			_append(line, _slice(net, edge.id, 0.0 if forward else length, length if forward else 0.0))
			edges.append(edge.id)
		var last: RoadEdge = net.edge_by_id(b.edge)
		var last_start: float = 0.0 if end_node == last.from_id else net.edge_length(last.id)
		_append(line, _slice(net, b.edge, last_start, b.along))
	if edges[edges.size() - 1] != b.edge:
		edges.append(b.edge)
	var locks: Array[StringName] = []
	for node_id: StringName in nodes:
		var node: RoadNode = net.node_by_id(node_id)
		if node.kind == &"gate" and node.lock_id != &"" and not locks.has(node.lock_id):
			locks.append(node.lock_id)
	var length_total: float = 0.0
	for i in line.size() - 1:
		length_total += line[i].distance_to(line[i + 1])
	return {
		"ok": true, "seconds": seconds, "length": length_total, "polyline": line,
		"edges": edges, "nodes": nodes, "locks": locks,
	}


## The points of a street from `from_along` to `to_along` (either order), POLYLINE_STEP apart.
static func _slice(net: RoadNetwork, edge_id: StringName, from_along: float, to_along: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var span: float = absf(to_along - from_along)
	var count: int = maxi(1, ceili(span / POLYLINE_STEP))
	for i in count + 1:
		points.append(net.point_at(edge_id, lerpf(from_along, to_along, float(i) / float(count))))
	return points


## Joins points to a polyline without repeating the joint.
static func _append(line: PackedVector2Array, points: PackedVector2Array) -> void:
	for p: Vector2 in points:
		if line.is_empty() or line[line.size() - 1].distance_to(p) > 0.001:
			line.append(p)


## The point `distance` meters along a polyline.
static func _along(line: PackedVector2Array, distance: float) -> Vector2:
	var walked: float = 0.0
	for i in line.size() - 1:
		var seg: float = line[i].distance_to(line[i + 1])
		if walked + seg >= distance and seg > 0.0:
			return line[i].lerp(line[i + 1], (distance - walked) / seg)
		walked += seg
	return line[line.size() - 1] if not line.is_empty() else Vector2.ZERO


static func _closed(net: RoadNetwork, node_id: StringName, open_locks: Array) -> bool:
	var node: RoadNode = net.node_by_id(node_id)
	return node != null and node.kind == &"gate" and node.lock_id != &"" and not open_locks.has(node.lock_id)
