extends RefCounted
## Shortest street path, including partial edges at both ends. Accessibility
## filters the already generated graph; it never moves a street or a lot.


## Shared by navigation and geometry: a connector opens only when both ends do.
static func accessible_edges(
	plan: Dictionary, districts: PackedInt32Array = PackedInt32Array()
) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for edge: Dictionary in plan.get("edges", []):
		var pair: Vector2i = edge.get("district_pair", Vector2i(-1, -1))
		if (
			districts.is_empty()
			or int(edge.district) in districts
			or (pair.x >= 0 and pair.y >= 0 and pair.x in districts and pair.y in districts)
		):
			edges.append(edge)
	return edges


static func route(
	plan: Dictionary,
	start: Vector2,
	destination: Vector2,
	districts: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	var edges: Array[Dictionary] = accessible_edges(plan, districts)
	if edges.is_empty():
		return {}
	var nodes: PackedVector2Array = plan.nodes.duplicate()
	var from: Dictionary = _project(nodes, edges, start)
	var to: Dictionary = _project(nodes, edges, destination)
	var start_id: int = nodes.size()
	nodes.append(from.point)
	var end_id: int = nodes.size()
	nodes.append(to.point)
	var adjacency: Array = []
	for i: int in range(nodes.size()):
		adjacency.append([])
	for edge: Dictionary in edges:
		_link(adjacency, nodes, edge.a, edge.b)
	_link(adjacency, nodes, start_id, from.edge.a)
	_link(adjacency, nodes, start_id, from.edge.b)
	_link(adjacency, nodes, end_id, to.edge.a)
	_link(adjacency, nodes, end_id, to.edge.b)
	if from.edge_index == to.edge_index:
		_link(adjacency, nodes, start_id, end_id)
	var distances := PackedFloat64Array()
	distances.resize(nodes.size())
	distances.fill(INF)
	distances[start_id] = 0
	var previous := PackedInt32Array()
	previous.resize(nodes.size())
	previous.fill(-1)
	var visited: Dictionary = {}
	for iteration: int in range(nodes.size()):
		var nearest: int = -1
		var best: float = INF
		for i: int in range(nodes.size()):
			if not visited.has(i) and distances[i] < best:
				best = distances[i]
				nearest = i
		if nearest < 0 or nearest == end_id:
			break
		visited[nearest] = true
		for link: Dictionary in adjacency[nearest]:
			var candidate: float = best + float(link.cost)
			if candidate < distances[link.node]:
				distances[link.node] = candidate
				previous[link.node] = nearest
	if is_inf(distances[end_id]):
		return {}
	var ids: Array[int] = [end_id]
	while ids.back() != start_id:
		ids.append(previous[ids.back()])
	ids.reverse()
	var points := PackedVector2Array([start])
	for id: int in ids:
		if points[-1].distance_squared_to(nodes[id]) > .0001:
			points.append(nodes[id])
	if points[-1].distance_squared_to(destination) > .0001:
		points.append(destination)
	var distance: float = (
		start.distance_to(from.point) + distances[end_id] + destination.distance_to(to.point)
	)
	return {"points": points, "distance": distance}


static func _project(nodes: PackedVector2Array, edges: Array[Dictionary], at: Vector2) -> Dictionary:
	var projection: Dictionary = {}
	var closest: float = INF
	for i: int in range(edges.size()):
		var edge: Dictionary = edges[i]
		var point: Vector2 = Geometry2D.get_closest_point_to_segment(at, nodes[edge.a], nodes[edge.b])
		var distance: float = at.distance_squared_to(point)
		if distance < closest:
			closest = distance
			projection = {"point": point, "edge": edge, "edge_index": i}
	return projection


static func _link(adjacency: Array, nodes: PackedVector2Array, a: int, b: int) -> void:
	var cost: float = nodes[a].distance_to(nodes[b])
	adjacency[a].append({"node": b, "cost": cost})
	adjacency[b].append({"node": a, "cost": cost})
