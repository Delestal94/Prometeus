extends RefCounted
## A complete town is planned once, independently of district unlocks or peers.
## Coordinates are metres in the horizontal plane. Version changes are explicit
## so a future campaign save can keep the generator that made its world.

const GENERATOR_VERSION: int = 3
const BASE_LAYOUT_VERSION: int = 1
const INFILL := preload("res://modules/town_gen/town_infill.gd")
const BLOCKS := preload("res://modules/town_gen/town_blocks.gd")
const WALK := preload("res://modules/town_gen/town_walkways.gd")
const ROAD_WIDTH: float = 12.0
const DISTRICT_LINKS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(0, 3),
	Vector2i(1, 2),
	Vector2i(2, 4),
	Vector2i(4, 3),
	Vector2i(3, 5),
	Vector2i(5, 2),
]
const CENTRES: Array[Vector2] = [
	Vector2(-230, -60),
	Vector2(40, -340),
	Vector2(410, -220),
	Vector2(-80, 340),
	Vector2(480, 290),
	Vector2(150, 80),
]


static func generate(seed_value: int, generator_version: int = GENERATOR_VERSION) -> Dictionary:
	if generator_version not in [1, 2, 3]:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"town_shape", BASE_LAYOUT_VERSION])
	var plan: Dictionary = {
		"seed": seed_value,
		"generator_version": generator_version,
		"nodes": PackedVector2Array(),
		"edges": [],
		"districts": [],
		"lots": [],
		"green_areas": [],
		"gates": [],
	}
	var rotation: float = rng.randf_range(-PI, PI)
	var stretch := Vector2(rng.randf_range(.85, 1.2), rng.randf_range(.85, 1.2))
	for district_id: int in range(6):
		var center: Vector2 = (
			(
				CENTRES[district_id] * stretch
				+ Vector2(rng.randf_range(-25, 25), rng.randf_range(-25, 25))
			)
			. rotated(rotation)
		)
		_make_district(plan, district_id, center, rotation, rng)
	_connect_districts(plan)
	_split_crossings(plan)
	for district: Dictionary in plan.districts:
		_place_green_areas(plan, district, seed_value)
		_place_lots(plan, district, seed_value)
	if generator_version == 2:
		INFILL.populate(plan, PackedInt32Array([0, 1]))
	elif generator_version == 3:
		plan.reserved_green_paths = WALK.green_access(plan, PackedInt32Array([0, 1, 2, 3, 4, 5]))
		BLOCKS.populate(plan)
		_split_crossings(plan)
		INFILL.populate(plan, PackedInt32Array(BLOCKS.DENSE_DISTRICTS))
	return plan


static func _make_district(
	plan: Dictionary, district_id: int, center: Vector2, rotation: float, rng: RandomNumberGenerator
) -> void:
	var node_ids: Array[int] = []
	var outline := PackedVector2Array()
	var phase: float = rotation + rng.randf_range(-.35, .35)
	for i: int in range(7):
		var angle: float = phase + TAU * i / 7.0 + rng.randf_range(-.09, .09)
		var radius: float = rng.randf_range(90.0, 115.0)
		var offset := Vector2.from_angle(angle) * radius
		node_ids.append(plan.nodes.size())
		plan.nodes.append(center + offset)
		outline.append(center + offset.normalized() * (radius + rng.randf_range(35, 50)))
	for i: int in range(7):
		_add_edge(plan, node_ids[i], node_ids[(i + 1) % 7], district_id)
	# Chords create unequal blocks without cutting through the central plaza.
	_add_edge(plan, node_ids[0], node_ids[2], district_id)
	_add_edge(plan, node_ids[3], node_ids[5], district_id)
	plan.districts.append(
		{"id": district_id, "center": center, "outline": outline, "node_ids": node_ids}
	)


static func _add_edge(
	plan: Dictionary,
	a: int,
	b: int,
	district: int,
	connector: bool = false,
	pair: Vector2i = Vector2i(-1, -1)
) -> void:
	var edge: Dictionary = {
		"a": a, "b": b, "district": district, "width": ROAD_WIDTH, "connector": connector
	}
	if connector:
		edge["district_pair"] = pair
	plan.edges.append(edge)


static func _connect_districts(plan: Dictionary) -> void:
	for pair: Vector2i in DISTRICT_LINKS:
		var closest := Vector2i(-1, -1)
		var distance: float = INF
		for a: int in plan.districts[pair.x].node_ids:
			for b: int in plan.districts[pair.y].node_ids:
				var candidate: float = plan.nodes[a].distance_squared_to(plan.nodes[b])
				if candidate < distance:
					distance = candidate
					closest = Vector2i(a, b)
		_add_edge(plan, closest.x, closest.y, -1, true, pair)
		plan.gates.append(
			{
				"districts": pair,
				"a": closest.x,
				"b": closest.y,
				"position": (plan.nodes[closest.x] + plan.nodes[closest.y]) * .5
			}
		)


## Crossings are real graph junctions, not two asphalt strips that navigation
## treats as disconnected. Adjacent endpoints are already connected.
static func _split_crossings(plan: Dictionary) -> void:
	var original: Array = plan.edges.duplicate()
	var cuts: Array = []
	for edge: Dictionary in original:
		cuts.append([edge.a, edge.b])
	for i: int in range(original.size()):
		var first: Dictionary = original[i]
		for j: int in range(i + 1, original.size()):
			var second: Dictionary = original[j]
			if first.a in [second.a, second.b] or first.b in [second.a, second.b]:
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(
				plan.nodes[first.a], plan.nodes[first.b], plan.nodes[second.a], plan.nodes[second.b]
			)
			if hit == null:
				continue
			var node_id: int = _junction(plan, hit)
			if node_id not in cuts[i]:
				cuts[i].append(node_id)
			if node_id not in cuts[j]:
				cuts[j].append(node_id)
	plan.edges.clear()
	for i: int in range(original.size()):
		var edge: Dictionary = original[i]
		var start: Vector2 = plan.nodes[edge.a]
		cuts[i].sort_custom(
			func(a: int, b: int) -> bool:
				return (
					start.distance_squared_to(plan.nodes[a])
					< start.distance_squared_to(plan.nodes[b])
				)
		)
		for j: int in range(cuts[i].size() - 1):
			_add_edge(
				plan,
				cuts[i][j],
				cuts[i][j + 1],
				edge.district,
				edge.connector,
				edge.get("district_pair", Vector2i(-1, -1))
			)
			if edge.get("block_street", false):
				plan.edges[-1]["block_street"] = true
				plan.edges[-1]["width"] = edge.width


static func _junction(plan: Dictionary, position: Vector2) -> int:
	for i: int in range(plan.nodes.size()):
		if plan.nodes[i].distance_squared_to(position) < .0001:
			return i
	plan.nodes.append(position)
	return plan.nodes.size() - 1


static func road_clearance(plan: Dictionary, position: Vector2) -> float:
	var nearest: float = INF
	for edge: Dictionary in plan.edges:
		var point: Vector2 = Geometry2D.get_closest_point_to_segment(
			position, plan.nodes[edge.a], plan.nodes[edge.b]
		)
		nearest = minf(nearest, position.distance_to(point) - float(edge.width) * .5)
	return nearest


static func _place_green_areas(plan: Dictionary, district: Dictionary, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"town_green", district.id, BASE_LAYOUT_VERSION])
	for kind: StringName in [&"plaza", &"park"]:
		var radius: float = 22.0 if kind == &"plaza" else 16.0
		for attempt: int in range(300):
			var at: Vector2 = (
				district.center
				if attempt == 0
				else (
					district.center
					+ Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(25, 85)
				)
			)
			if not Geometry2D.is_point_in_polygon(at, district.outline):
				continue
			if (
				road_clearance(plan, at) < radius + 3.0
				or not _space_available(plan, at, radius + 6)
			):
				continue
			plan.green_areas.append(
				{"district": district.id, "position": at, "radius": radius, "kind": kind}
			)
			break


static func _space_available(plan: Dictionary, at: Vector2, radius: float) -> bool:
	for green: Dictionary in plan.green_areas:
		if at.distance_to(green.position) < radius + float(green.radius):
			return false
	for lot: Dictionary in plan.lots:
		if at.distance_to(lot.position) < radius + (lot.size as Vector2).length() * .5 + 2:
			return false
	return true


static func _place_lots(plan: Dictionary, district: Dictionary, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"town_lots", district.id, BASE_LAYOUT_VERSION])
	var candidates: Array[Dictionary] = []
	for edge: Dictionary in plan.edges:
		if edge.district == district.id:
			candidates.append(edge)
	# Fisher-Yates with a private RNG; no process-global shuffle()/randf().
	for i: int in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Dictionary = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var placed: int = 0
	for edge: Dictionary in candidates:
		var a: Vector2 = plan.nodes[edge.a]
		var b: Vector2 = plan.nodes[edge.b]
		var direction: Vector2 = (b - a).normalized()
		for fraction: float in [.28, .5, .72]:
			for side: float in [-1.0, 1.0]:
				var size := Vector2(rng.randf_range(12, 18), rng.randf_range(14, 22))
				var radius: float = size.length() * .5
				var frontage: Vector2 = a.lerp(b, fraction)
				var at: Vector2 = frontage + direction.orthogonal() * side * (radius + 10)
				if not _lot_fits(plan, district.outline, at, size, direction.angle()):
					continue
				if road_clearance(plan, at) < radius + 2 or not _space_available(plan, at, radius):
					continue
				var roles: Array[StringName] = [&"depot", &"house", &"house", &"house", &"workshop"]
				var role: StringName = &"shop" if placed % 4 == 0 else &"residential"
				if district.id == 0 and placed < roles.size():
					role = roles[placed]
				plan.lots.append(
					{
						"district": district.id,
						"position": at,
						"size": size,
						"angle": direction.angle(),
						"frontage": frontage,
						"role": role,
						"address": Vector2i(district.id + 1, placed + 1)
					}
				)
				placed += 1


static func _lot_fits(
	plan: Dictionary, outline: PackedVector2Array, at: Vector2, size: Vector2, angle: float
) -> bool:
	for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]:
		var point: Vector2 = at + (corner * size * .5).rotated(angle)
		if not Geometry2D.is_point_in_polygon(point, outline) or road_clearance(plan, point) < 1:
			return false
	return true
