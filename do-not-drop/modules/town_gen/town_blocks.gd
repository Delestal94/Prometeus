extends RefCounted
## Version-three local streets divide oversized blocks without moving existing
## parcels or green areas. Links join two existing streets, never dead ends.

const DENSE_DISTRICTS: Array[int] = [0, 1, 2, 4]


static func populate(plan: Dictionary) -> void:
	plan.block_streets = []
	var parcels := PackedVector3Array()
	for lot: Dictionary in plan.lots:
		parcels.append(Vector3(lot.position.x, lot.position.y, lot.size.length() * .5 + 6))
	for id: int in DENSE_DISTRICTS:
		var anchors: Array[Vector2] = []
		for edge: Dictionary in plan.edges:
			if edge.district != id or edge.get("block_street", false):
				continue
			for fraction: float in [.2, .35, .5, .65, .8]:
				anchors.append((plan.nodes[edge.a] as Vector2).lerp(plan.nodes[edge.b], fraction))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([plan.seed, &"town_blocks", id, 3])
		for i: int in range(anchors.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var swap: Vector2 = anchors[i]
			anchors[i] = anchors[j]
			anchors[j] = swap
		var count: int = 0
		for i: int in range(anchors.size()):
			if count >= 2:
				break
			for j: int in range(i + 1, anchors.size()):
				var a: Vector2 = anchors[i]
				var b: Vector2 = anchors[j]
				if not _fits(plan, id, a, b, parcels):
					continue
				plan.edges.append(
					{
						"a": _node(plan, a),
						"b": _node(plan, b),
						"district": id,
						"width": 8.0,
						"connector": false,
						"block_street": true
					}
				)
				plan.block_streets.append({"district": id, "a": a, "b": b})
				count += 1
				break


static func _fits(
	plan: Dictionary, id: int, a: Vector2, b: Vector2, parcels: PackedVector3Array
) -> bool:
	var length: float = a.distance_to(b)
	if length < 45 or length > 180:
		return false
	for parcel: Vector3 in parcels:
		var center := Vector2(parcel.x, parcel.y)
		if (
			center.distance_to(Geometry2D.get_closest_point_to_segment(center, a, b))
			< parcel.z - .001
		):
			return false
	for green: Dictionary in plan.green_areas:
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(green.position, a, b)
		if near.distance_to(green.position) < green.radius + 7.6:
			return false
	var normal: Vector2 = (b - a).normalized().orthogonal() * 7.6
	for point: Vector2 in [a + normal, a - normal, b + normal, b - normal]:
		if not Geometry2D.is_point_in_polygon(point, plan.districts[id].outline):
			return false
	# At least two samples must open genuinely unused ground, rather than draw
	# a second asphalt band alongside an existing road.
	var fresh: int = 0
	for fraction: float in [.2, .35, .5, .65, .8]:
		var point: Vector2 = a.lerp(b, fraction)
		var distance: float = INF
		for edge: Dictionary in plan.edges:
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, plan.nodes[edge.a], plan.nodes[edge.b]
			)
			distance = minf(distance, point.distance_to(near))
		if distance > 12:
			fresh += 1
	return fresh >= 2


static func _node(plan: Dictionary, point: Vector2) -> int:
	for i: int in range(plan.nodes.size()):
		if plan.nodes[i].distance_squared_to(point) < .0001:
			return i
	plan.nodes.append(point)
	return plan.nodes.size() - 1
