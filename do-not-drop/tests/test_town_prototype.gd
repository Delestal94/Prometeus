extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_prototype.gd
## town_prototype.gd: scene builds the planned starting district with collidable
## buildings, accessible streets, two closed exits, plaza monument, park furniture
## and existing house/depot/furniture models with batched authored trees away
## from asphalt. Art varies independently of the planned street geometry.
## Opening the center preserves the plan, adds its native models and parks,
## removes only the open gate, and gives the connecting road continuous collision.
## Pedestrian surfaces are batched/collidable, match the road at entries,
## reach parks without blocked centers, and clear trees/benches from their paths.
## Reuses route_terrain.gd, StraightSegment and RouteDresser: physical/textured
## terrain with exterior relief, original road paint and batched city scenery.

const SCENE := preload("res://scenes/gameplay/town/town_prototype.tscn")
const PLAN := preload("res://modules/town_gen/town_plan.gd")
const NAV := preload("res://modules/town_gen/town_navigation.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var town: Node3D = SCENE.instantiate()
	town.set(&"world_seed", 4242)
	town.set(&"enable_camera", false)
	root.add_child(town)
	current_scene = town
	await process_frame
	await physics_frame
	var plan: Dictionary = town.get(&"plan")
	_expect(plan == PLAN.generate(4242), "Scene geometry uses its exact seed plan")
	_expect(
		town.get_node(^"Roads").get_child_count() > 10, "Loop streets and diagonal links are built"
	)
	_expect(
		town.get_node(^"ClosedExits").get_child_count() == 2,
		"Both starting district exits are gated"
	)
	var houses: int = 0
	var depot: int = 0
	var workshop: int = 0
	for node: Node in town.get_children():
		if not node.has_meta(&"lot"):
			continue
		var lot: Dictionary = node.get_meta(&"lot")
		_expect(lot.district == 0, "Only the starting district is built in this prototype")
		_expect(node.get_node(^"Building") is StaticBody3D, "Buildings have physical collision")
		if lot.role == &"house":
			houses += 1
		elif lot.role == &"depot":
			depot += 1
		elif lot.role == &"workshop":
			workshop += 1
	_expect(
		houses == 3 and depot == 1 and workshop == 1,
		(
			"The starting scene has its depot, three customers and workshop (got %d/%d/%d)"
			% [depot, houses, workshop]
		)
	)
	_expect(
		town.has_node(^"Green_plaza/Monument") and town.has_node(^"Green_plaza/PackageSculpture"),
		"The plaza has a physical monument and parcel sculpture"
	)
	_expect(
		town.has_node(^"Green_park") and town.has_node(^"Green_park/Bench"),
		"The park has green space and furniture"
	)
	var plaza: Node3D = town.get_node(^"Green_plaza")
	var lawn: MeshInstance3D = plaza.get_node(^"Lawn")
	var walkway: MeshInstance3D = plaza.get_node(^"Walkway")
	_expect(
		walkway.position.y - lawn.position.y >= .1,
		"Plaza paving is separated from grass to avoid flickering"
	)
	var bench: Node3D = plaza.get_node(^"Bench")
	_expect(
		(
			bench.get_meta(&"model_source")
			== "res://assets/models/environment/props/sm_env_prop_bench.glb"
		),
		"Park benches reuse the authored game model"
	)
	var bounds: AABB = bench.get_meta(&"grounded_bounds")
	_expect(
		is_zero_approx(bounds.position.y) and bench.get_node(^"Colliders").get_child_count() > 0,
		"Park bench rests on the lawn and has physical collision (got %s)" % bounds
	)
	var trees: PackedVector2Array = town.get(&"tree_positions")
	_expect(
		trees.size() >= 16 and trees.size() <= 24,
		"Plaza and park retain trees around their clear entries (got %d)" % trees.size()
	)
	for at: Vector2 in trees:
		_expect(PLAN.road_clearance(plan, at) > 3, "Tree crowns leave streets clear")
	var batches: Array[Node] = town.get_node(^"BatchedDressing").find_children(
		"*", "MultiMeshInstance3D", true, false
	)
	var tree_count: int = 0
	for batch: MultiMeshInstance3D in batches:
		tree_count += batch.multimesh.instance_count
	_expect(
		tree_count == trees.size(),
		"Authored trees are batched rather than separate draw calls (got %d)" % tree_count
	)
	var art_records: Array = town.get_meta(&"tree_art")
	var species: Dictionary = {}
	for record: Dictionary in art_records:
		species[record.model] = true
	_expect(species.size() == 3, "The parks reuse three existing tree species (got %s)" % species)
	var variants: Dictionary = {}
	for parcel: Node in town.get_children():
		if not parcel.has_meta(&"lot"):
			continue
		var building: Node3D = parcel.get_node(^"Building")
		if building.has_meta(&"house_variant"):
			variants[building.get_meta(&"house_variant")] = true
			_expect(
				building.has_node(^"HouseVisual"),
				"Residential lots use the existing architecture models"
			)
			var visual: Node3D = building.get_node(^"HouseVisual")
			var half_size: Vector2 = parcel.get_meta(&"lot").size * .5
			for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
				var in_lot: Transform3D = (
					(parcel as Node3D).global_transform.affine_inverse() * mesh.global_transform
				)
				var footprint: AABB = in_lot * mesh.get_aabb()
				_expect(
					(
						footprint.position.x >= -half_size.x
						and footprint.end.x <= half_size.x
						and footprint.position.z >= -half_size.y
						and footprint.end.z <= half_size.y
					),
					"Authored house meshes fit their lot at native scale (got %s)" % footprint
				)
		else:
			_expect(
				building.get_meta(&"model_sources").size() >= 4,
				"Service buildings reuse original depot door and furnishing pieces"
			)
	_expect(variants.size() >= 3, "The district has varied housing (got %s)" % variants)
	for edge: Dictionary in plan.edges:
		if edge.district != 0:
			continue
		var at: Vector2 = (plan.nodes[edge.a] + plan.nodes[edge.b]) * .5
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, 20, at.y), Vector3(at.x, -2, at.y)
		)
		var hit: Dictionary = town.get_world_3d().direct_space_state.intersect_ray(query)
		var road_support: Node = hit.get("collider")
		_expect(
			road_support != null and bool(road_support.get_meta(&"road_surface", false)),
			(
				"Street center has asphalt collision without obstructing props (edge %s, at %s, hit %s)"
				% [edge, at, road_support.get_path() if road_support != null else "none"]
			)
		)
	town.queue_free()
	await process_frame
	var expanded: Node3D = SCENE.instantiate()
	expanded.set(&"world_seed", 4242)
	expanded.set(&"enable_camera", false)
	expanded.set(&"built_districts", PackedInt32Array([0, 1]))
	root.add_child(expanded)
	current_scene = expanded
	await process_frame
	await physics_frame
	_expect(expanded.get(&"plan") == plan, "Opening a district never moves the existing town")
	var center_lots: int = 0
	var planned_lots: int = 0
	var tall_shops: int = 0
	for lot: Dictionary in plan.lots:
		if lot.district == 1:
			planned_lots += 1
	for node: Node in expanded.get_children():
		if not node.has_meta(&"lot"):
			continue
		var parcel := node as Node3D
		var lot: Dictionary = parcel.get_meta(&"lot")
		_expect(lot.district in [0, 1], "Only the two requested districts are constructed")
		if lot.district != 1:
			continue
		center_lots += 1
		var building: Node3D = parcel.get_node(^"Building")
		if lot.role == &"shop" and building.get_meta(&"house_variant") == 3:
			tall_shops += 1
		var half: Vector2 = lot.size * .5
		for mesh: MeshInstance3D in building.get_node(^"HouseVisual").find_children(
			"*", "MeshInstance3D", true, false
		):
			var bounds_in_lot: AABB = (
				(parcel.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			)
			_expect(
				(
					bounds_in_lot.position.x >= -half.x
					and bounds_in_lot.end.x <= half.x
					and bounds_in_lot.position.z >= -half.y
					and bounds_in_lot.end.z <= half.y
				),
				"Center buildings fit the original lot at native scale (got %s)" % bounds_in_lot
			)
	_expect(
		center_lots == planned_lots and center_lots > 0,
		"All planned center lots are built (got %d/%d)" % [center_lots, planned_lots]
	)
	_expect(tall_shops > 0, "The center uses taller existing architecture for its shops")
	_expect(
		(
			expanded.has_node(^"District_1_Green_plaza/Monument")
			and expanded.has_node(^"District_1_Green_park/Bench")
		),
		"The center includes its plaza, monument and furnished park"
	)
	var exits: Node = expanded.get_node(^"ClosedExits")
	_expect(
		exits.get_child_count() == 2 and exits.has_node(^"Gate_2") and exits.has_node(^"Gate_3"),
		"Center access opens while Industrial and Country stay gated"
	)
	for edge: Dictionary in NAV.accessible_edges(plan, PackedInt32Array([0, 1])):
		for fraction: float in [.05, .25, .5, .75, .95]:
			var at: Vector2 = (plan.nodes[edge.a] as Vector2).lerp(plan.nodes[edge.b], fraction)
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(at.x, 20, at.y), Vector3(at.x, -2, at.y)
			)
			var hit: Dictionary = expanded.get_world_3d().direct_space_state.intersect_ray(query)
			var body: Node = hit.get("collider")
			_expect(
				body != null and bool(body.get_meta(&"road_surface", false)),
				(
					"Open streets and the entire corridor have unobstructed asphalt support (edge %s, at %s)"
					% [edge, at]
				)
			)
	var pedestrian: Dictionary = expanded.get(&"pedestrian_plan")
	_check_route_reuse(expanded)
	_expect(
		expanded.has_node(^"PedestrianSurfaces/CollisionShape3D"),
		"Walkways share one batched mesh and physical surface"
	)
	for path: Dictionary in pedestrian.green_paths:
		for i: int in range(1, path.points.size()):
			for fraction: float in [.25, .5, .75]:
				var at: Vector2 = (path.points[i - 1] as Vector2).lerp(path.points[i], fraction)
				var query := PhysicsRayQueryParameters3D.create(
					Vector3(at.x, 20, at.y), Vector3(at.x, -2, at.y)
				)
				var hit: Dictionary = expanded.get_world_3d().direct_space_state.intersect_ray(
					query
				)
				var body: Node = hit.get("collider")
				_expect(
					(
						body != null
						and (
							bool(body.get_meta(&"pedestrian_surface", false))
							or bool(body.get_meta(&"road_surface", false))
						)
					),
					(
						"Park entry has continuous unblocked walking support (got %s)"
						% (body.get_path() if body != null else "none")
					)
				)
	for at: Vector2 in expanded.get(&"tree_positions"):
		_expect(
			float(expanded.call(&"_path_clearance", at)) > 4,
			"Tree crowns stay clear of green-area entries"
		)
	expanded.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: starting district geometry, green areas, gates and unobstructed streets")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1


func _check_route_reuse(town: Node3D) -> void:
	var terrain: TerrainField = town.get(&"terrain")
	_expect(
		(
			terrain.get_script().get_base_script().resource_path
			== "res://scripts/gameplay/route/route_terrain.gd"
		),
		"Town uses the existing game terrain shader and physical height field"
	)
	_expect(
		not town.has_node(^"Ground") and terrain.build_progress == 1.0,
		"Continuous terrain replaces the oversized flat ground box"
	)
	_expect(terrain.get_child_count() > 0, "The terrain has physical mesh tiles")
	var segments: Array = town.get(&"street_segments")
	_expect(not segments.is_empty(), "Open streets reuse the original road segment builder")
	var painted: int = 0
	for segment: RouteSegment in segments:
		if segment.has_node(^"MergedGeometry"):
			painted += 1
		_expect(
			segment is StraightSegment and segment.continuous_terrain,
			"The original straight segment supplies road paint without duplicate ground"
		)
		_expect(
			not segment.has_node(^"Road") and not segment.has_node(^"Ground"),
			"Route segments do not overlay a second physical road/ground"
		)
	_expect(painted > 0, "The original paint is retained in merged segment geometry")
	var plan: Dictionary = town.get(&"plan")
	for lot: Dictionary in plan.lots:
		if lot.district in [0, 1]:
			_expect(
				absf(terrain.height_at(Vector3(lot.position.x, 0, lot.position.y))) < .001,
				"Urban lots stay level instead of sitting between countryside ridges"
			)
	var highest: float = 0
	for edge: Dictionary in NAV.accessible_edges(plan, PackedInt32Array([0, 1])):
		var a: Vector2 = plan.nodes[edge.a]
		var b: Vector2 = plan.nodes[edge.b]
		var middle: Vector2 = (a + b) * .5
		_expect(
			absf(terrain.height_at(Vector3(middle.x, 0, middle.y))) < .001,
			"The reused terrain keeps existing city roads and delivery levels stable"
		)
		for side: float in [-1, 1]:
			var at: Vector2 = middle + (b - a).normalized().orthogonal() * side * 60
			highest = maxf(highest, terrain.height_at(Vector3(at.x, 0, at.y)))
	_expect(highest > 2, "Ground outside the city has real height variation (got %f)" % highest)
	var dresser: RefCounted = town.get(&"dresser")
	_expect(
		(
			dresser.get_script().get_base_script().resource_path
			== "res://scripts/gameplay/route/route_dresser.gd"
		),
		"Town adapts the original placement engine"
	)
	var counts: Dictionary = dresser.get(&"placed_counts")
	_expect(
		int(counts.get(&"tree", 0)) > 0 and int(counts.get(&"ground_plant", 0)) > 0,
		"Original scenery rules populate the city surroundings (got %s)" % counts
	)
	var holder: Node = town.get_node(^"RouteStreets/BatchedDressing")
	_expect(
		not holder.find_children("*", "MultiMeshInstance3D", true, false).is_empty(),
		"Reused route scenery is batched for rendering"
	)
