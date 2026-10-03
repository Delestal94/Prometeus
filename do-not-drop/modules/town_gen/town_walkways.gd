extends RefCounted
## Pedestrian surfaces derived from the existing plan. Heights are metres.
## No RNG or plan mutations: opening districts preserves street and lot layout.

const NAV := preload("res://modules/town_gen/town_navigation.gd")
const SIDEWALK_WIDTH: float = 2.0
const RAMP_WIDTH: float = .8
const PATH_WIDTH: float = 2.0
const STREET_HEIGHT: float = .20


static func generate(plan: Dictionary, districts: PackedInt32Array) -> Dictionary:
	var result: Dictionary = {"surfaces": [], "lot_paths": [], "green_paths": []}
	if districts.is_empty():
		return result
	var edges: Array[Dictionary] = NAV.accessible_edges(plan, districts)
	var roads: Array[PackedVector2Array] = []
	var junctions: Dictionary = {}
	for edge: Dictionary in edges:
		roads.append(_strip(plan.nodes[edge.a], plan.nodes[edge.b], edge.width * .5))
		junctions[edge.a] = true
		junctions[edge.b] = true
	for id: int in junctions:
		roads.append(_circle(plan.nodes[id], 6.0 / cos(PI / 24.0) + .01, 24))
	for gate: Dictionary in plan.gates:
		var pair: Vector2i = gate.districts
		var first_open: bool = pair.x in districts
		if first_open == (pair.y in districts):
			continue
		var a: Vector2 = plan.nodes[gate.a if first_open else gate.b]
		var b: Vector2 = plan.nodes[gate.b if first_open else gate.a]
		roads.append(_strip(a, a.move_toward(b, minf(35, a.distance_to(b) * .5)), 6))
	for edge: Dictionary in edges:
		var a: Vector2 = plan.nodes[edge.a]
		var b: Vector2 = plan.nodes[edge.b]
		var normal: Vector2 = (b - a).normalized().orthogonal()
		for side: float in [-1, 1]:
			for radii: Vector2 in [Vector2(6, 8), Vector2(8, 8.8)]:
				var polygon := PackedVector2Array(
					[
						a + normal * radii.x * side,
						b + normal * radii.x * side,
						b + normal * radii.y * side,
						a + normal * radii.y * side
					]
				)
				_surface(
					result,
					polygon,
					roads,
					func(at: Vector2) -> float: return _street_height(plan.nodes, edges, at)
				)
	for id: int in junctions:
		var center: Vector2 = plan.nodes[id]
		for i: int in range(24):
			var a: Vector2 = Vector2.from_angle(TAU * i / 24.0)
			var b: Vector2 = Vector2.from_angle(TAU * (i + 1) / 24.0)
			for radii: Vector2 in [Vector2(6, 8), Vector2(8, 8.8)]:
				_surface(
					result,
					PackedVector2Array(
						[
							center + a * radii.x,
							center + b * radii.x,
							center + b * radii.y,
							center + a * radii.y
						]
					),
					roads,
					func(at: Vector2) -> float: return _street_height(plan.nodes, edges, at)
				)
	for lot: Dictionary in plan.lots:
		if lot.district not in districts:
			continue
		var direction: Vector2 = (lot.position - lot.frontage).normalized()
		var service: bool = lot.role in [&"depot", &"workshop"]
		var width: float = 5.0 if service else PATH_WIDTH
		var end: Vector2 = (
			lot.position - direction * (lot.size.y * .5 if service else (4.4 - lot.size.y * .12))
		)
		var points := PackedVector2Array(
			[lot.frontage + direction * 6, lot.frontage + direction * 8.8, end]
		)
		result.lot_paths.append({"address": lot.address, "points": points, "width": width})
		_path(result, points, width, roads, .08)
	for path: Dictionary in green_access(plan, districts):
		result.green_paths.append(path)
		_path(result, path.points, path.width, roads, STREET_HEIGHT)
	return result


## Access routes can be reserved before infill, independently of surface meshes.
static func green_access(plan: Dictionary, districts: PackedInt32Array) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	var edges: Array[Dictionary] = NAV.accessible_edges(plan, districts)
	for green: Dictionary in plan.green_areas:
		if green.district not in districts:
			continue
		var reserved: Dictionary = {}
		for path: Dictionary in plan.get("reserved_green_paths", []):
			if path.position == green.position:
				reserved = path
				break
		if not reserved.is_empty():
			paths.append(reserved.duplicate(true))
			continue
		var nearest: Vector2
		var distance: float = INF
		for edge: Dictionary in edges:
			if edge.district != green.district:
				continue
			var at: Vector2 = Geometry2D.get_closest_point_to_segment(
				green.position, plan.nodes[edge.a], plan.nodes[edge.b]
			)
			if at.distance_squared_to(green.position) < distance:
				distance = at.distance_squared_to(green.position)
				nearest = at
		var direction: Vector2 = (green.position - nearest).normalized()
		var radius: float = 10 if green.kind == &"plaza" else 5
		var start: Vector2 = nearest + direction * 7.5
		var end: Vector2 = green.position - direction * (radius - .5)
		var points: PackedVector2Array = _clear_path(plan, start, end)
		paths.append(
			{
				"district": green.district,
				"kind": green.kind,
				"position": green.position,
				"points": points,
				"width": PATH_WIDTH
			}
		)
	return paths


static func _strip(a: Vector2, b: Vector2, half_width: float) -> PackedVector2Array:
	var normal: Vector2 = (b - a).normalized().orthogonal() * half_width
	return PackedVector2Array([a + normal, b + normal, b - normal, a - normal])


static func _circle(center: Vector2, radius: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(count):
		points.append(center + Vector2.from_angle(TAU * i / float(count)) * radius)
	return points


static func _street_height(
	nodes: PackedVector2Array, edges: Array[Dictionary], at: Vector2
) -> float:
	var clearance: float = INF
	for edge: Dictionary in edges:
		clearance = minf(
			clearance,
			(
				at.distance_to(
					Geometry2D.get_closest_point_to_segment(at, nodes[edge.a], nodes[edge.b])
				)
				- edge.width * .5
			)
		)
	return STREET_HEIGHT * clampf((SIDEWALK_WIDTH + RAMP_WIDTH - clearance) / RAMP_WIDTH, 0, 1)


static func _surface(
	result: Dictionary,
	polygon: PackedVector2Array,
	roads: Array[PackedVector2Array],
	height_at: Callable
) -> void:
	var pieces: Array[PackedVector2Array] = [polygon]
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	for road: PackedVector2Array in roads:
		var road_bounds := Rect2(road[0], Vector2.ZERO)
		for point: Vector2 in road:
			road_bounds = road_bounds.expand(point)
		if not bounds.intersects(road_bounds):
			continue
		var cut: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in pieces:
			cut.append_array(Geometry2D.clip_polygons(piece, road))
		pieces = cut
	for piece: PackedVector2Array in pieces:
		if piece.size() < 3 or Geometry2D.triangulate_polygon(piece).is_empty():
			continue
		var points := PackedVector3Array()
		for at: Vector2 in piece:
			points.append(Vector3(at.x, height_at.call(at), at.y))
		result.surfaces.append(points)


static func _path(
	result: Dictionary,
	points: PackedVector2Array,
	width: float,
	roads: Array[PackedVector2Array],
	end_height: float
) -> void:
	for i: int in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var first_height: float = STREET_HEIGHT
		var last_height: float = end_height if i == points.size() - 1 else STREET_HEIGHT
		var height_at := func(at: Vector2) -> float:
			var fraction: float = clampf((at - a).dot(b - a) / a.distance_squared_to(b), 0, 1)
			return lerpf(first_height, last_height, fraction)
		_surface(result, _strip(a, b, width * .5), roads, height_at)
		var normal: Vector2 = (b - a).normalized().orthogonal()
		for side: float in [-1, 1]:
			var polygon := PackedVector2Array(
				[
					a + normal * width * .5 * side,
					b + normal * width * .5 * side,
					b + normal * (width * .5 + .5) * side,
					a + normal * (width * .5 + .5) * side
				]
			)
			_surface(
				result,
				polygon,
				roads,
				func(at: Vector2) -> float:
					var across: float = absf((at - a).dot(normal)) - width * .5
					return maxf(
						_street_height_from_roads(roads, at),
						height_at.call(at) * clampf(1 - across / .5, 0, 1)
					)
			)


static func _street_height_from_roads(roads: Array[PackedVector2Array], at: Vector2) -> float:
	var distance: float = INF
	for road: PackedVector2Array in roads:
		for i: int in range(road.size()):
			distance = minf(
				distance,
				at.distance_to(
					Geometry2D.get_closest_point_to_segment(
						at, road[i], road[(i + 1) % road.size()]
					)
				)
			)
	return STREET_HEIGHT * clampf((2.8 - distance) / .8, 0, 1)


## Visibility graph around inflated parcel rectangles; no path cuts a building.
static func _clear_path(plan: Dictionary, start: Vector2, end: Vector2) -> PackedVector2Array:
	var obstacles: Array[PackedVector2Array] = []
	var nodes := PackedVector2Array([start, end])
	for lot: Dictionary in plan.lots:
		var polygon := PackedVector2Array()
		var half: Vector2 = lot.size * .5 + Vector2.ONE * 1.6
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			polygon.append(lot.position + (corner * half).rotated(lot.angle))
		obstacles.append(polygon)
		if (
			lot.position.distance_to(
				Geometry2D.get_closest_point_to_segment(lot.position, start, end)
			)
			< half.length() + 10
		):
			nodes.append_array(polygon)
	var edges: Array[Dictionary] = []
	for a: int in range(nodes.size()):
		for b: int in range(a + 1, nodes.size()):
			if _visible(nodes[a], nodes[b], obstacles):
				edges.append({"a": a, "b": b, "district": 0})
	var start_linked: bool = false
	var end_linked: bool = false
	for edge: Dictionary in edges:
		start_linked = start_linked or edge.a == 0 or edge.b == 0
		end_linked = end_linked or edge.a == 1 or edge.b == 1
	if not start_linked or not end_linked:
		return PackedVector2Array()
	var route: Dictionary = NAV.route({"nodes": nodes, "edges": edges}, start, end)
	return route.get("points", PackedVector2Array())


static func _visible(a: Vector2, b: Vector2, obstacles: Array[PackedVector2Array]) -> bool:
	for polygon: PackedVector2Array in obstacles:
		var mid: Vector2 = (a + b) * .5
		if Geometry2D.is_point_in_polygon(mid, polygon):
			var boundary: float = INF
			for i: int in range(polygon.size()):
				boundary = minf(
					boundary,
					mid.distance_to(
						Geometry2D.get_closest_point_to_segment(
							mid, polygon[i], polygon[(i + 1) % polygon.size()]
						)
					)
				)
			if boundary > .001:
				return false
		for i: int in range(polygon.size()):
			var hit: Variant = Geometry2D.segment_intersects_segment(
				a, b, polygon[i], polygon[(i + 1) % polygon.size()]
			)
			if hit != null and hit.distance_to(a) > .001 and hit.distance_to(b) > .001:
				return false
	return true
