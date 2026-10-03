extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/town_gen/tests/test_town_walkways.gd
## town_walkways.gd: deterministic sidewalks/ramp heights outside asphalt,
## parcel access and green-area paths that detour around buildings. Empty
## Reserved version-two green routes match the original accesses;
## district selection builds nothing; planning never mutates the town. Portable.
## Mixed-width streets have raised sidewalks 16 cm above asphalt; parcel
## ordinary entries retain a vertical curb; only vehicle/corner accesses slope.

const WALK := preload("res://modules/town_gen/town_walkways.gd")
const PLAN := preload("res://modules/town_gen/town_plan.gd")
const NAV := preload("res://modules/town_gen/town_navigation.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture: Dictionary = {
		"lots": [{"position": Vector2.ZERO, "size": Vector2(4, 4), "angle": .2}]
	}
	var detour: PackedVector2Array = WALK._clear_path(fixture, Vector2(-10, 0), Vector2(10, 0))
	_expect(
		detour.size() >= 4, "A green path detours around the intervening parcel (got %s)" % detour
	)
	_check_path(fixture, detour)
	var mixed: Dictionary = {
		"nodes":
		PackedVector2Array([Vector2(-80, 0), Vector2(0, 0), Vector2(80, 0), Vector2(0, 80)]),
		"edges":
		[
			{"a": 0, "b": 1, "district": 0, "width": 12.0},
			{"a": 1, "b": 2, "district": 0, "width": 12.0},
			{"a": 1, "b": 3, "district": 0, "width": 8.0}
		],
		"lots":
		[
			{
				"district": 0,
				"address": Vector2i(1, 1),
				"role": &"residential",
				"frontage": Vector2(0, 40),
				"position": Vector2(20, 40),
				"size": Vector2(16, 16)
			}
		],
		"green_areas": [],
		"gates": []
	}
	var paving: Dictionary = WALK.generate(mixed, PackedInt32Array([0]))
	var entry: Dictionary = paving.lot_paths[0]
	_expect(entry.points[0] == Vector2(4, 40), "Narrow-street access begins at its asphalt edge")
	_expect(
		entry.heights[0] > .35 and entry.heights[1] > .35,
		"An ordinary pedestrian frontage retains its raised curb"
	)
	_expect(not paving.corner_paths.is_empty(), "Intersections have localized accessible curb cuts")
	for path: Dictionary in paving.corner_paths:
		_expect(
			absf(path.heights[0] - WALK.STREET_HEIGHT) < .000001 and path.heights[1] > .35,
			"Corner curb cuts join asphalt and raised pavement"
		)
	mixed.lots[0].role = &"workshop"
	var garage: Dictionary = WALK.generate(mixed, PackedInt32Array([0])).lot_paths[0]
	_expect(
		absf(garage.heights[0] - WALK.STREET_HEIGHT) < .000001 and garage.heights[1] > .35,
		"Vehicle entrances lower the curb to asphalt height"
	)
	var raised: bool = false
	for surface: PackedVector3Array in paving.surfaces:
		var polygon := PackedVector2Array()
		var lowest: float = INF
		for vertex: Vector3 in surface:
			polygon.append(Vector2(vertex.x, vertex.z))
			lowest = minf(lowest, vertex.y)
		if Geometry2D.is_point_in_polygon(Vector2(5, 20), polygon):
			raised = raised or lowest > WALK.STREET_HEIGHT + .15
	_expect(raised, "Physical sidewalk planning is higher than its narrow street")
	for seed_value: int in [1, 17, 77, 4242, 90210]:
		var plan: Dictionary = PLAN.generate(seed_value)
		var old: Dictionary = PLAN.generate(seed_value, 1)
		_expect(
			(
				plan.reserved_green_paths
				== WALK.green_access(old, PackedInt32Array([0, 1, 2, 3, 4, 5]))
			),
			"Version-three reservations retain all twelve original green entrances"
		)
		var original: Dictionary = plan.duplicate(true)
		var districts := PackedInt32Array([0, 1])
		var result: Dictionary = WALK.generate(plan, districts)
		_expect(
			result == WALK.generate(plan, districts), "Walkways repeat exactly for the same plan"
		)
		_expect(plan == original, "Adding pedestrian access leaves the seeded layout unchanged")
		_expect(not result.surfaces.is_empty(), "Open districts have pedestrian surfaces")
		_expect(result.green_paths.size() == 4, "Both districts connect their plaza and park")
		var lots: int = 0
		for lot: Dictionary in plan.lots:
			if lot.district in districts:
				lots += 1
		_expect(result.lot_paths.size() == lots, "Every built parcel has its own frontage access")
		var edges: Array[Dictionary] = NAV.accessible_edges(plan, districts)
		for surface: PackedVector3Array in result.surfaces:
			var polygon := PackedVector2Array()
			for vertex: Vector3 in surface:
				_expect(
					vertex.y >= -.001 and vertex.y <= WALK.SIDEWALK_HEIGHT + .001,
					"Ramp and walkway heights stay in the ground-to-street range"
				)
				polygon.append(Vector2(vertex.x, vertex.z))
			var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
			_expect(not indices.is_empty(), "Each clipped walkway surface triangulates")
			for i: int in range(0, indices.size(), 3):
				var at: Vector2 = (
					(polygon[indices[i]] + polygon[indices[i + 1]] + polygon[indices[i + 2]]) / 3.0
				)
				var distance: float = INF
				for edge: Dictionary in edges:
					distance = minf(
						distance,
						(
							at.distance_to(
								Geometry2D.get_closest_point_to_segment(
									at, plan.nodes[edge.a], plan.nodes[edge.b]
								)
							)
							- edge.width * .5
						)
					)
				_expect(
					distance >= -.01,
					(
						"Pedestrian paving leaves the asphalt lane uncovered (seed %d, at %s, got %f)"
						% [seed_value, at, distance]
					)
				)
		for path: Dictionary in result.green_paths:
			_expect(
				path.points.size() >= 2,
				"Every green area has a reachable entry (seed %d)" % seed_value
			)
			_check_path(plan, path.points)
			var radius: float = 10 if path.kind == &"plaza" else 5
			if not path.points.is_empty():
				_expect(
					path.points[-1].distance_to(path.position) < radius,
					"Entry reaches the green area's paved center"
				)
		var empty: Dictionary = WALK.generate(plan, PackedInt32Array())
		_expect(
			(
				empty.surfaces.is_empty()
				and empty.lot_paths.is_empty()
				and empty.green_paths.is_empty()
			),
			"No district selection creates no pedestrian geometry"
		)
	if _failures == 0:
		print("PASS: seeded sidewalks, ramps, parcel entrances, green paths and building detours")
	quit(_failures)


func _check_path(plan: Dictionary, points: PackedVector2Array) -> void:
	for i: int in range(1, points.size()):
		for fraction: float in [0.0, .25, .5, .75, 1.0]:
			var at: Vector2 = points[i - 1].lerp(points[i], fraction)
			for lot: Dictionary in plan.lots:
				var local: Vector2 = (at - lot.position).rotated(-float(lot.angle))
				var half: Vector2 = lot.size * .5 + Vector2.ONE
				_expect(
					absf(local.x) >= half.x or absf(local.y) >= half.y,
					"Green access keeps its full walking width clear of parcels"
				)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
