extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_prototype.gd
## town_prototype.gd: scene builds the planned starting district with collidable
## buildings, accessible streets, two closed exits, plaza monument, park furniture
## and batched trees away from asphalt. Seeded scenes reproduce the same geometry.

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
	_expect(town.get_node(^"Roads").get_child_count() > 10, "Loop streets and diagonal links are built")
	_expect(town.get_node(^"ClosedExits").get_child_count() == 2, "Both starting district exits are gated")
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
	_expect(houses == 3 and depot == 1 and workshop == 1,
		"The starting scene has its depot, three customers and workshop (got %d/%d/%d)"
		% [depot, houses, workshop])
	_expect(town.has_node(^"Green_plaza/Monument") and town.has_node(^"Green_plaza/PackageSculpture"),
		"The plaza has a physical monument and parcel sculpture")
	_expect(town.has_node(^"Green_park") and town.has_node(^"Green_park/Bench"),
		"The park has green space and furniture")
	var plaza: Node3D = town.get_node(^"Green_plaza")
	var lawn: MeshInstance3D = plaza.get_node(^"Lawn")
	var walkway: MeshInstance3D = plaza.get_node(^"Walkway")
	_expect(walkway.position.y - lawn.position.y >= .1,
		"Plaza paving is separated from grass to avoid flickering")
	var bench: Node3D = plaza.get_node(^"Bench")
	var support: Node3D = bench.get_node(^"Support")
	_expect(support.global_position.y < bench.global_position.y and support.global_position.y < .3,
		"Park bench has physical supports reaching the ground")
	var trees: PackedVector2Array = town.get(&"tree_positions")
	_expect(trees.size() == 24, "Plaza and park get their tree rings (got %d)" % trees.size())
	for at: Vector2 in trees:
		_expect(PLAN.road_clearance(plan, at) > 3, "Tree crowns leave streets clear")
	_expect((town.get_node(^"TreeCrowns") as MultiMeshInstance3D).multimesh.instance_count == trees.size(),
		"Trees are batched rather than separate draw calls")
	for edge: Dictionary in plan.edges:
		if edge.district != 0:
			continue
		var at: Vector2 = (plan.nodes[edge.a] + plan.nodes[edge.b]) * .5
		var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, 20, at.y), Vector3(at.x, -2, at.y))
		var hit: Dictionary = town.get_world_3d().direct_space_state.intersect_ray(query)
		_expect(not hit.is_empty() and hit.get("collider") == town.get_node(^"Ground"),
			"Street center is supported by ground with no building or prop blocking it")
	town.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: starting district geometry, green areas, gates and unobstructed streets")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
