extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/town_gen/tests/test_town_plan.gd
## town_plan.gd: 100 seeds keep six connected, non-grid districts, three starting
## customers, depot/workshop, parks and plazas clear of streets and frontage lots.
## Planning is repeatable, independent of global RNG and future unlock state;
## Version-two infill preserves version-one addresses and reserved green accesses;
## compact parcels have two metres between yards and clear sidewalks.
## Street crossings become graph junctions. Runs without game autoloads/assets.

const PLAN := preload("res://modules/town_gen/town_plan.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var signatures: Dictionary = {}
	for seed_value: int in range(1, 101):
		var plan: Dictionary = PLAN.generate(seed_value)
		signatures[hash(plan.nodes)] = true
		_expect(
			plan.generator_version == PLAN.GENERATOR_VERSION,
			"A plan names its generator version (seed %d)" % seed_value
		)
		_expect(
			plan.seed == seed_value and plan.districts.size() == 6,
			"A seed plans exactly six districts (seed %d)" % seed_value
		)
		_expect(
			_reachable(plan) == plan.nodes.size(),
			"All street junctions are connected (seed %d)" % seed_value
		)
		_expect(plan.gates.size() == 7, "Seven district links are preserved (seed %d)" % seed_value)
		_check_green(plan, seed_value)
		_check_lots(plan, seed_value)
		_check_infill(plan, seed_value)
		_check_streets(plan, seed_value)
		if seed_value <= 4:
			_check_crossings(plan)
	_expect(PLAN.generate(4242, 99).is_empty(), "Unknown generator versions are rejected")
	var first: Dictionary = PLAN.generate(4242)
	seed(721)
	for i: int in range(50):
		randf()
	_expect(first == PLAN.generate(4242), "Global RNG use cannot change the same town seed")
	_expect(
		signatures.size() == 100, "Different seeds vary town geometry (got %d)" % signatures.size()
	)
	if _failures == 0:
		print("PASS: 100 connected asymmetric towns, clear greenery/lots and deterministic seeds")
	quit(_failures)


func _reachable(plan: Dictionary) -> int:
	var seen: Dictionary = {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var node_id: int = queue.pop_back()
		for edge: Dictionary in plan.edges:
			var next: int = -1
			if edge.a == node_id:
				next = edge.b
			elif edge.b == node_id:
				next = edge.a
			if next >= 0 and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size()


func _check_green(plan: Dictionary, seed_value: int) -> void:
	for district_id: int in range(6):
		var kinds: Array[StringName] = []
		for green: Dictionary in plan.green_areas:
			if green.district != district_id:
				continue
			kinds.append(green.kind)
			_expect(
				PLAN.road_clearance(plan, green.position) >= float(green.radius) + 3,
				"Green space stays outside street surfaces (seed %d)" % seed_value
			)
			for i: int in range(24):
				var rim: Vector2 = (
					green.position + Vector2.from_angle(TAU * i / 24) * float(green.radius)
				)
				_expect(
					Geometry2D.is_point_in_polygon(rim, plan.districts[district_id].outline),
					"The whole park fits its district (seed %d)" % seed_value
				)
		_expect(
			&"plaza" in kinds and &"park" in kinds,
			(
				"Every district reserves a plaza and park (seed %d district %d got %s)"
				% [seed_value, district_id, kinds]
			)
		)


func _check_lots(plan: Dictionary, seed_value: int) -> void:
	var roles: Dictionary = {}
	for i: int in range(plan.lots.size()):
		var lot: Dictionary = plan.lots[i]
		var radius: float = (lot.size as Vector2).length() * .5
		if lot.district == 0:
			roles[lot.role] = int(roles.get(lot.role, 0)) + 1
		_expect(
			lot.get("urban_infill", false) or PLAN.road_clearance(plan, lot.position) >= radius + 2,
			"Buildings/yard leave the road clear (seed %d)" % seed_value
		)
		_expect(
			absf(PLAN.road_clearance(plan, lot.frontage) + PLAN.ROAD_WIDTH * .5) < .01,
			"Each address has real street frontage (seed %d)" % seed_value
		)
		for green: Dictionary in plan.green_areas:
			_expect(
				(
					lot.get("urban_infill", false)
					or lot.position.distance_to(green.position) >= radius + float(green.radius)
				),
				"Lots do not consume reserved green areas (seed %d)" % seed_value
			)
		for j: int in range(i + 1, plan.lots.size()):
			var other: Dictionary = plan.lots[j]
			var separation: float = radius + (other.size as Vector2).length() * .5 + 2
			var compact: bool = lot.get("urban_infill", false) or other.get("urban_infill", false)
			_expect(
				(
					(
						compact
						and (
							Geometry2D
							. intersect_polygons(_footprint(lot, .99), _footprint(other, .99))
							. is_empty()
						)
					)
					or (
						not compact
						and lot.position.distance_to(other.position) >= separation - .001
					)
				),
				"Frontage lots do not overlap (seed %d)" % seed_value
			)
	_expect(
		(
			roles.get(&"depot", 0) == 1
			and roles.get(&"house", 0) == 3
			and roles.get(&"workshop", 0) == 1
		),
		(
			"Starting district has depot, three clients and workshop (seed %d got %s)"
			% [seed_value, roles]
		)
	)


func _footprint(lot: Dictionary, margin: float = 0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		points.append(
			lot.position + (corner * (lot.size * .5 + Vector2.ONE * margin)).rotated(lot.angle)
		)
	return points


func _check_infill(plan: Dictionary, seed_value: int) -> void:
	var old: Dictionary = PLAN.generate(seed_value, 1)
	for key: String in ["nodes", "edges", "districts", "gates", "green_areas"]:
		_expect(
			plan[key] == old[key], "Infill preserves version-one %s (seed %d)" % [key, seed_value]
		)
	_expect(
		plan.lots.slice(0, old.lots.size()) == old.lots,
		"Infill preserves every existing lot/address (seed %d)" % seed_value
	)
	var addresses: Dictionary = {}
	var counts := [0, 0]
	for lot: Dictionary in plan.lots:
		_expect(not addresses.has(lot.address), "Addresses remain unique (seed %d)" % seed_value)
		addresses[lot.address] = true
		if not lot.get("urban_infill", false):
			continue
		counts[lot.district] += 1
		var polygon: PackedVector2Array = _footprint(lot)
		for point: Vector2 in polygon:
			_expect(
				(
					Geometry2D.is_point_in_polygon(point, plan.districts[lot.district].outline)
					and PLAN.road_clearance(plan, point) >= 3.59
				),
				"Compact lots preserve sidewalks and fit the outline (seed %d)" % seed_value
			)
		for green: Dictionary in plan.green_areas:
			for i: int in range(polygon.size()):
				var near: Vector2 = Geometry2D.get_closest_point_to_segment(
					green.position, polygon[i], polygon[(i + 1) % polygon.size()]
				)
				_expect(
					near.distance_to(green.position) >= green.radius + 1.99,
					"Infill preserves the entire green space (seed %d)" % seed_value
				)
		for path: Dictionary in plan.reserved_green_paths:
			for point: Vector2 in path.points:
				_expect(
					not Geometry2D.is_point_in_polygon(point, _footprint(lot, 2.5)),
					"Reserved green entrances remain clear (seed %d)" % seed_value
				)
	_expect(
		counts[0] >= 4 and counts[1] >= 4,
		"Both initial districts gain compact frontages (seed %d got %s)" % [seed_value, counts]
	)


func _check_streets(plan: Dictionary, seed_value: int) -> void:
	var diagonal: int = 0
	for edge: Dictionary in plan.edges:
		var vector: Vector2 = plan.nodes[edge.b] - plan.nodes[edge.a]
		_expect(
			vector.length() > .01 and edge.width >= 12,
			"Streets have positive length and truck-width space (seed %d)" % seed_value
		)
		if absf(vector.x) > 1 and absf(vector.y) > 1:
			diagonal += 1
	_expect(
		diagonal > plan.edges.size() / 2,
		"The town is not an axis-aligned rectangular grid (seed %d)" % seed_value
	)


func _check_crossings(plan: Dictionary) -> void:
	for i: int in range(plan.edges.size()):
		var a: Dictionary = plan.edges[i]
		for j: int in range(i + 1, plan.edges.size()):
			var b: Dictionary = plan.edges[j]
			if a.a in [b.a, b.b] or a.b in [b.a, b.b]:
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(
				plan.nodes[a.a], plan.nodes[a.b], plan.nodes[b.a], plan.nodes[b.b]
			)
			_expect(hit == null, "Crossing streets share a graph node (edges %s/%s)" % [a, b])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
