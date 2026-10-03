extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_prototype.gd
## town_prototype.gd: scene builds the planned starting district with collidable
## buildings, accessible streets, two closed exits, plaza monument, park furniture
## and existing house/depot/furniture models with batched authored trees away
## from asphalt. Art varies independently of the planned street geometry.

const SCENE := preload("res://scenes/gameplay/town/town_prototype.tscn")
const PLAN := preload("res://modules/town_gen/town_plan.gd")
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
	_expect(trees.size() == 24, "Plaza and park get their tree rings (got %d)" % trees.size())
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
	if _failures == 0:
		print("PASS: starting district geometry, green areas, gates and unobstructed streets")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
