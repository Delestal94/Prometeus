extends RefCounted
## Add compact frontage parcels without relocating version-one streets/addresses.
const WALK := preload("res://modules/town_gen/town_walkways.gd")


static func populate(plan: Dictionary, districts: PackedInt32Array) -> void:
	plan.reserved_green_paths = WALK.green_access(plan, districts)
	var occupied: Array[Dictionary] = []
	for lot: Dictionary in plan.lots:
		occupied.append(_obstacle(_parcel(lot, 1.0)))
	var accesses: Array[Dictionary] = []
	for lot: Dictionary in plan.lots:
		if lot.district in districts:
			_reserve_lot(accesses, lot)
	for path: Dictionary in plan.reserved_green_paths:
		for i: int in range(1, path.points.size()):
			accesses.append(_obstacle(_strip(path.points[i - 1], path.points[i], 2.6)))
	for district_id: int in districts:
		_fill_district(plan, district_id, occupied, accesses)


static func _fill_district(
	plan: Dictionary, id: int, occupied: Array[Dictionary], accesses: Array[Dictionary]
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, &"town_infill", id, 2])
	var address: int = 1
	for lot: Dictionary in plan.lots:
		if lot.district == id:
			address = maxi(address, lot.address.y + 1)
	for edge: Dictionary in plan.edges:
		if edge.district != id:
			continue
		var a: Vector2 = plan.nodes[edge.a]
		var direction: Vector2 = (plan.nodes[edge.b] - a).normalized()
		var length: float = a.distance_to(plan.nodes[edge.b])
		for along: int in range(16, int(length) - 15, 4):
			for side: float in [-1.0, 1.0]:
				var size := Vector2(rng.randf_range(14, 18), rng.randf_range(16, 18))
				var frontage: Vector2 = a + direction * along
				var lot: Dictionary = {
					"district": id,
					"size": size,
					"frontage": frontage,
					"position": frontage + direction.orthogonal() * side * (10.6 + size.y * .5),
					"angle": direction.angle(),
					"address": Vector2i(id + 1, address),
					"role": &"shop" if id == 1 and address % 3 == 0 else &"residential",
					"urban_infill": true,
				}
				var footprint: PackedVector2Array = _parcel(lot, 0)
				var obstacle: Dictionary = _obstacle(_parcel(lot, 1))
				if not _fits(plan, id, footprint) or _overlaps(obstacle, occupied):
					continue
				if _overlaps(obstacle, accesses):
					continue
				var entry: Dictionary = _obstacle(_strip(frontage, lot.position, 2.0))
				if _overlaps(entry, occupied):
					continue
				plan.lots.append(lot)
				occupied.append(obstacle)
				_reserve_lot(accesses, lot)
				address += 1


static func _fits(plan: Dictionary, id: int, polygon: PackedVector2Array) -> bool:
	var candidate: Dictionary = _obstacle(polygon)
	for edge: Dictionary in plan.edges:
		var road: Dictionary = _obstacle(
			_strip(plan.nodes[edge.a], plan.nodes[edge.b], edge.width * .5 + 3.6)
		)
		if _overlaps(candidate, [road]):
			return false
	for point: Vector2 in polygon:
		if not Geometry2D.is_point_in_polygon(point, plan.districts[id].outline):
			return false
		for edge: Dictionary in plan.edges:
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, plan.nodes[edge.a], plan.nodes[edge.b]
			)
			if point.distance_to(nearest) < edge.width * .5 + 3.6:
				return false
	for green: Dictionary in plan.green_areas:
		if Geometry2D.is_point_in_polygon(green.position, polygon):
			return false
		for i: int in range(polygon.size()):
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(
				green.position, polygon[i], polygon[(i + 1) % polygon.size()]
			)
			if nearest.distance_to(green.position) < green.radius + 2:
				return false
	return true


static func _parcel(lot: Dictionary, margin: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		points.append(
			lot.position + (corner * (lot.size * .5 + Vector2.ONE * margin)).rotated(lot.angle)
		)
	return points


static func _strip(a: Vector2, b: Vector2, half_width: float) -> PackedVector2Array:
	var normal: Vector2 = (b - a).normalized().orthogonal() * half_width
	return PackedVector2Array([a + normal, b + normal, b - normal, a - normal])


static func _reserve_lot(accesses: Array[Dictionary], lot: Dictionary) -> void:
	var half_width: float = 3.5 if lot.role in [&"depot", &"workshop"] else 2.0
	accesses.append(_obstacle(_strip(lot.frontage, lot.position, half_width)))


static func _obstacle(polygon: PackedVector2Array) -> Dictionary:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	return {"polygon": polygon, "bounds": bounds}


static func _overlaps(candidate: Dictionary, obstacles: Array[Dictionary]) -> bool:
	for obstacle: Dictionary in obstacles:
		if (
			candidate.bounds.intersects(obstacle.bounds)
			and not Geometry2D.intersect_polygons(candidate.polygon, obstacle.polygon).is_empty()
		):
			return true
	return false
