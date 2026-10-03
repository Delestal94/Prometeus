extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/town_gen/tests/test_town_navigation.gd
## town_navigation.gd: partial street edges, connected detours, inaccessible
## districts and disconnected destinations. One hundred towns guide from depot
## to all three customers without crossing a closed district. Portable test.
## Connectors retain both endpoint districts through splits; opening the center
## permits 100 cross-district routes while other districts stay inaccessible.

const NAV := preload("res://modules/town_gen/town_navigation.gd")
const PLAN := preload("res://modules/town_gen/town_plan.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture: Dictionary = {
		"nodes":
		PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 20), Vector2(0, 20)]),
		"edges":
		[
			{"a": 0, "b": 1, "district": 0},
			{"a": 1, "b": 2, "district": 0},
			{"a": 2, "b": 3, "district": 0}
		]
	}
	var partial: Dictionary = NAV.route(fixture, Vector2(20, -3), Vector2(30, -4))
	_expect(
		is_equal_approx(partial.distance, 17),
		"Same-edge route uses 10 m of asphalt plus approach legs (got %s)" % partial
	)
	var detour: Dictionary = NAV.route(fixture, Vector2(10, 0), Vector2(10, 20))
	_expect(
		is_equal_approx(detour.distance, 200),
		"Nearby parallel streets require their connecting junction (got %s)" % detour
	)
	_expect(
		detour.points.has(Vector2(100, 0)) and detour.points.has(Vector2(100, 20)),
		"GPS path includes both detour turns (got %s)" % detour.points
	)
	_expect(
		is_zero_approx(float(NAV.route(fixture, Vector2(30, 0), Vector2(30, 0)).distance)),
		"Arriving at the same street point has zero distance"
	)
	fixture.edges.append({"a": 3, "b": 0, "district": 1})
	_expect(
		is_equal_approx(NAV.route(fixture, Vector2(10, 0), Vector2(10, 20)).distance, 40),
		"Opening the other district allows the shorter connector"
	)
	_expect(
		is_equal_approx(
			NAV.route(fixture, Vector2(10, 0), Vector2(10, 20), PackedInt32Array([0])).distance, 200
		),
		"A closed district cannot provide a shortcut"
	)
	fixture.edges = [{"a": 0, "b": 1, "district": 0}, {"a": 2, "b": 3, "district": 0}]
	_expect(
		NAV.route(fixture, Vector2(10, 0), Vector2(10, 20)).is_empty(),
		"Disconnected roads report no reachable route"
	)
	_expect(
		NAV.route(fixture, Vector2.ZERO, Vector2.ONE, PackedInt32Array([5])).is_empty(),
		"No accessible streets reports no route"
	)
	var crossing: Dictionary = {
		"nodes":
		PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(50, -20), Vector2(50, 20)]),
		"edges":
		[
			{"a": 0, "b": 1, "district": -1, "connector": true, "district_pair": Vector2i(0, 1)},
			{"a": 2, "b": 3, "district": 2, "connector": false},
		]
	}
	PLAN._split_crossings(crossing)
	_expect(
		NAV.accessible_edges(crossing, PackedInt32Array([0])).is_empty(),
		"A connector stays closed while either endpoint district is closed"
	)
	var opened: Array[Dictionary] = NAV.accessible_edges(crossing, PackedInt32Array([0, 1]))
	_expect(opened.size() == 2, "Only the two split connector pieces open (got %d)" % opened.size())
	for edge: Dictionary in opened:
		_expect(
			edge.get("district_pair") == Vector2i(0, 1), "Splitting preserves connector ownership"
		)
	_expect(
		is_equal_approx(
			NAV.route(crossing, Vector2(10, 0), Vector2(90, 0), PackedInt32Array([0, 1])).get(
				"distance", -1
			),
			80
		),
		"GPS traverses the split open connector"
	)
	for seed_value: int in range(1, 101):
		var plan: Dictionary = PLAN.generate(seed_value)
		var depot: Vector2
		for lot: Dictionary in plan.lots:
			if lot.district == 0 and lot.role == &"depot":
				depot = lot.frontage
		var center_stop: Vector2 = plan.nodes[plan.districts[1].node_ids[0]]
		var center_route: Dictionary = NAV.route(plan, depot, center_stop, PackedInt32Array([0, 1]))
		_expect(
			not center_route.is_empty(),
			"Center is reachable when both districts open (seed %d)" % seed_value
		)
		var available: Array[Dictionary] = NAV.accessible_edges(plan, PackedInt32Array([0, 1]))
		for edge: Dictionary in available:
			if edge.connector:
				_expect(
					edge.district_pair == Vector2i(0, 1),
					"No connector into a closed district opens"
				)
			else:
				_expect(edge.district in [0, 1], "No closed local street becomes accessible")
		var center_points: PackedVector2Array = center_route.get("points", PackedVector2Array())
		for i: int in range(1, center_points.size()):
			var at: Vector2 = (center_points[i - 1] + center_points[i]) * .5
			var clearance: float = INF
			for edge: Dictionary in available:
				clearance = minf(
					clearance,
					at.distance_to(
						Geometry2D.get_closest_point_to_segment(
							at, plan.nodes[edge.a], plan.nodes[edge.b]
						)
					)
				)
			_expect(
				clearance < .01,
				"Center guidance stays on built streets (seed %d, got %f)" % [seed_value, clearance]
			)
		for lot: Dictionary in plan.lots:
			if lot.district != 0 or lot.role != &"house":
				continue
			var route: Dictionary = NAV.route(plan, depot, lot.frontage, PackedInt32Array([0]))
			_expect(
				not route.is_empty(), "All starting customers are reachable (seed %d)" % seed_value
			)
			if route.is_empty():
				continue
			var points: PackedVector2Array = route.points
			_expect(
				points[0].is_equal_approx(depot) and points[-1].is_equal_approx(lot.frontage),
				(
					"Guidance starts at the truck and ends at the customer's street (seed %d)"
					% seed_value
				)
			)
			for i: int in range(1, points.size()):
				var midpoint: Vector2 = (points[i - 1] + points[i]) * .5
				var distance: float = INF
				for edge: Dictionary in plan.edges:
					if edge.district == 0:
						distance = minf(
							distance,
							midpoint.distance_to(
								Geometry2D.get_closest_point_to_segment(
									midpoint, plan.nodes[edge.a], plan.nodes[edge.b]
								)
							)
						)
				_expect(
					distance < .01,
					(
						"Guidance remains on built district streets (seed %d, got %f)"
						% [seed_value, distance]
					)
				)
	if _failures == 0:
		print(
			"PASS: partial roads, split connectors, closed districts, 300 customer and 100 center paths"
		)
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
