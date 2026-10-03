extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_city.gd
## town_city_delivery.tscn builds all six districts with the actual player/truck,
## twelve accessible green areas, every parcel and no closed connector gates.
## District architecture/scenery differ; native models fit their planned lots.
## All street edges have physical support and GPS reaches the existing orders
## from every district. Inspection and delivery scenes share the same layout.
## Port has physical dock/access above carved water; Sierra snow is local and
## natural relief never lifts streets, customer lots or green access paths.

const PLAN := preload("res://modules/town_gen/town_plan.gd")
const NAV := preload("res://modules/town_gen/town_navigation.gd")
const ART := preload("res://scripts/gameplay/town/town_art.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/gameplay/town/town_city_delivery.tscn")
	var level: Node3D = scene.instantiate()
	level.set(&"world_seed", 4242)
	root.add_child(level)
	current_scene = level
	var town: Node3D = level.get(&"town")
	while not bool(town.get(&"is_built")):
		await process_frame
	await physics_frame
	var plan: Dictionary = town.get(&"plan")
	_expect(
		plan == PLAN.generate(4242), "Building all districts preserves the complete seeded plan"
	)
	_expect(
		town.get_node(^"ClosedExits").get_child_count() == 0,
		"The full-city scene has no closed district exits"
	)
	_expect(level.get(&"houses").size() == 6, "The full city retains the six existing orders")
	var counts := [0, 0, 0, 0, 0, 0]
	var warehouses := [0, 0, 0, 0, 0, 0]
	var variants: Array[Dictionary] = [{}, {}, {}, {}, {}, {}]
	var kit := ART.KIT.new(town)
	for parcel: Node in town.get_children():
		if not parcel.has_meta(&"lot"):
			continue
		var lot: Dictionary = parcel.get_meta(&"lot")
		counts[lot.district] += 1
		var building: Node3D = parcel.get_node_or_null(^"Building")
		if building == null:
			var customers: Array = level.get(&"houses")
			_expect(
				customers.any(
					func(house: Node3D) -> bool: return house.get_meta(&"address") == lot.address
				),
				"A delivery customer replaces the corresponding frontage building"
			)
			continue
		_expect(building is StaticBody3D, "Every district building has physical collision")
		if building.get_meta(&"architecture", &"") == &"warehouse":
			warehouses[lot.district] += 1
		if building.has_meta(&"house_variant"):
			var variant: int = building.get_meta(&"house_variant")
			variants[lot.district][variant] = true
			var bounds: AABB = building.transform * kit.model_bounds(ART.HOUSE_MODELS[variant])
			var half: Vector2 = lot.size * .5
			_expect(
				(
					bounds.position.x >= -half.x
					and bounds.end.x <= half.x
					and bounds.position.z >= -half.y
					and bounds.end.z <= half.y
				),
				"All native-scale house models fit their yard (district %d)" % lot.district
			)
	for id: int in range(6):
		_expect(counts[id] > 0, "District %d has buildings (got %d)" % [id, counts[id]])
		var planned: int = (
			plan.lots.filter(func(lot: Dictionary) -> bool: return lot.district == id).size()
		)
		_expect(counts[id] == planned, "Every planned address is built in district %d" % id)
		var node: Vector2 = plan.nodes[plan.districts[id].node_ids[0]]
		var vehicle: Node3D = level.get(&"vehicle")
		vehicle.position = Vector3(node.x, 1.0, node.y)
		_expect(not level.call(&"guidance").is_empty(), "GPS works from district %d" % id)
	_expect(
		warehouses[2] > 0 and warehouses[4] > 0,
		"Industrial and port districts use warehouse fronts (got %s)" % [warehouses]
	)
	_expect(
		variants[3].has(4) and variants[5].has(1), "Country has farmhouses and Sierra has cabins"
	)
	var pedestrian: Dictionary = town.get(&"pedestrian_plan")
	_expect(pedestrian.green_paths.size() == 12, "All six districts have park and plaza entries")
	for path: Dictionary in pedestrian.green_paths:
		_expect(path.points.size() >= 2, "Green entry is reachable in district %d" % path.district)
	var edges: Array[Dictionary] = NAV.accessible_edges(plan, town.get(&"built_districts"))
	_expect(
		edges.size() == plan.edges.size(), "Every local road and interdistrict connector is open"
	)
	for edge: Dictionary in edges:
		var at: Vector2 = (plan.nodes[edge.a] + plan.nodes[edge.b]) * .5
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, 1, at.y), Vector3(at.x, -.1, at.y)
		)
		query.collision_mask = 1
		var hit: Dictionary = town.get_world_3d().direct_space_state.intersect_ray(query)
		_expect(
			not hit.is_empty() and hit.position.y >= .17, "Every city street supports the truck"
		)
	var forest: Array = town.get_meta(&"tree_art")
	_expect(
		forest.any(func(record: Dictionary) -> bool: return record.model == ART.PINE),
		"Sierra parks reuse the authored pine trees"
	)
	var landmarks: Node = town.get_node(^"DistrictLandmarks")
	var placed: Array = landmarks.get_children().filter(
		func(node: Node) -> bool: return node.has_meta(&"district")
	)
	_expect(
		placed.size() == 2,
		"Industry and country place their authored landmarks (got %d)" % placed.size()
	)
	for landmark: Node3D in placed:
		var at := Vector2(landmark.position.x, landmark.position.z)
		var radius: float = landmark.get_meta(&"clearance_radius")
		_expect(PLAN.road_clearance(plan, at) >= radius + 4, "Landmarks stand clear of streets")
	var terrain: TerrainField = town.get(&"terrain")
	var coast: Dictionary = terrain.get(&"coast")
	_expect(
		town.has_node(^"PortPier") and town.has_node(^"PortWater"),
		"The port builds its dock and carved water surface"
	)
	var dock_at: Vector2 = coast.shore + coast.direction * 30
	var dock_query := PhysicsRayQueryParameters3D.create(
		Vector3(dock_at.x, 2, dock_at.y), Vector3(dock_at.x, -3, dock_at.y), 1
	)
	var dock_hit: Dictionary = town.get_world_3d().direct_space_state.intersect_ray(dock_query)
	_expect(
		not dock_hit.is_empty() and absf(dock_hit.position.y - .2) < .01,
		"The dock supports walking above the water (got %s)" % [dock_hit]
	)
	_expect(
		terrain.height_at(Vector3(dock_at.x, 0, dock_at.y)) < -3,
		"The harbour has a carved submerged bed"
	)
	for lot: Dictionary in plan.lots:
		_expect(
			absf(terrain.height_at(Vector3(lot.position.x, 0, lot.position.y))) < .001,
			"Every parcel stays level after biome shaping (district %d)" % lot.district
		)
	for path: Dictionary in pedestrian.green_paths:
		for at: Vector2 in path.points:
			_expect(
				absf(terrain.height_at(Vector3(at.x, 0, at.y))) < .001,
				"Every green access stays level after biome shaping (district %d)" % path.district
			)
	var peak: float = 0
	var sierra: Dictionary = plan.districts[5]
	for x: int in range(-120, 121, 10):
		for z: int in range(-120, 121, 10):
			var at: Vector2 = sierra.center + Vector2(x, z)
			if Geometry2D.is_point_in_polygon(at, sierra.outline):
				peak = maxf(peak, terrain.height_at(Vector3(at.x, 0, at.y)))
	_expect(peak > 4, "Sierra retains visible hills between level platforms (peak %s)" % peak)
	var material: ShaderMaterial = terrain.get(&"_material")
	_expect(
		material.get_shader_parameter("snow_enabled") == true,
		"The city enables the local Sierra snow profile"
	)
	_expect(
		material.get_shader_parameter("snow_outline") == sierra.outline,
		"Snow follows Sierra's irregular outline"
	)
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: complete six-district city, authored profiles, open streets and six-order GPS")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
