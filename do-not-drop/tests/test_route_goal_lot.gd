extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_goal_lot.gd
## The base at the end of the route (tareas de Nacho N-116): route_goal_lot.gd
## replaced the concrete arch and its GoalArea. What this pins down:
##   - over several seeds and house counts the road ends in a level lot: the
##     ground under the slab and building is flat, no tree, prop or house
##     stands on it, and there is no arch or GoalArea left;
##   - the free bay is reachable from the road (the route's path carries on
##     into it, and a truck-sized volume sweeps from the road to the bay
##     without touching anything solid), the parked trucks are solid, and the
##     bay is clear;
##   - the lot is the same for every peer (same seed = same bay, number, town,
##     trucks and workers) and follows the seed (other seeds vary);
##   - the bay only counts when the truck is inside its lines; the tidy-parking
##     line is earned under 10 degrees off; a body outside or crossways is not
##     in the bay;
##   - at night the lamps get their glow, halos and lights, by day there are no
##     lights; workers are away from the free bay and asleep until a truck comes;
##   - in a level: driving through the bay without stopping does not end the run,
##     stopping in it does, and the results camera then frames the parked truck;
##     the section name and GPS ask for the bay by number;
##   - the coloured-box kit builds outward-facing geometry.

## How much of the road before the lot the way-in check sweeps, metres.
const APPROACH_LENGTH: float = 120.0
const SEEDS: Array[int] = [11, 424, 65021, 271828]
## Slab and building, plus a little, in lot space.
const LOT_X: float = 22.0
const LOT_Z_FRONT: float = 1.0
const LOT_Z_BACK: float = -38.0
const FLAT_TOLERANCE: float = 0.01
const MAX_PATH_GAP: float = 15.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_kit()
	for index: int in range(SEEDS.size()):
		await _test_seed(SEEDS[index], 1 + index % 4)
	await _test_same_for_every_peer()
	await _test_bay_rules()
	await _test_night_and_day()
	await _test_level()
	if _failures == 0:
		print("PASS: the route ends in a level base with a free bay: nothing on it, reachable, solid trucks, "
				+ "the same for everyone, stopping in the bay ends the run")
	quit(_failures)


func _test_kit() -> void:
	var unit: Array = GoalLotKit.unit_box()
	var vertices: PackedVector3Array = unit[0]
	var normals: PackedVector3Array = unit[1]
	var indices: PackedInt32Array = unit[2]
	var inward: int = 0
	for corner: int in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[corner]]
		var b: Vector3 = vertices[indices[corner + 1]]
		var c: Vector3 = vertices[indices[corner + 2]]
		# Godot's front faces are clockwise: the right-hand normal points inward.
		if (b - a).cross(c - a).dot(normals[indices[corner]]) < 0.0:
			inward += 1
	var triangles: int = indices.size() / 3
	_expect(inward == triangles, "The kit's box is wound the engine's way (%d of %d triangles)" % [inward, triangles])
	var boxes := GoalLotKit.Boxes.new()
	boxes.add(Vector3(2.0, 1.0, 3.0), Transform3D(Basis(Vector3.UP, 0.5), Vector3(4.0, 5.0, 6.0)), Color.RED)
	boxes.add_standing(Vector3(1.0, 1.0, 1.0), Vector3.ZERO, Color.BLUE)
	var instance: MeshInstance3D = boxes.build()
	var corners: int = instance.mesh.get_faces().size() if instance.mesh != null else 0
	_expect(corners == 72, "Two boxes make 24 triangles in one mesh (got %d vertices)" % corners)
	instance.free()


func _build_route(seed_value: int, houses: int, batch: bool = false) -> Node3D:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", seed_value)
	network.set(&"world_house_count", houses)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", batch)
	root.add_child(route)
	return route


func _clear_world(route: Node) -> void:
	route.free()
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)


func _test_seed(seed_value: int, houses: int) -> void:
	var route: Node3D = _build_route(seed_value, houses)
	var label: String = "Seed %d, %d houses" % [seed_value, houses]
	var lot: RouteGoalLot = route.get("goal_lot")
	_expect(lot != null, "%s: the road ends in a goal lot" % label)
	if lot == null:
		_clear_world(route)
		return
	_expect(route.get_node_or_null(^"GoalArea") == null and route.get_node_or_null(^"GoalArchTop") == null,
			"%s: the old arch and goal area are gone" % label)
	# Level ground under the slab and the building.
	var terrain: Node = route.get("terrain")
	var worst: float = 0.0
	var samples: int = 0
	var z: float = 0.0
	while z >= RouteGoalLot.BACK_Z - RouteGoalLot.BUILDING_DEPTH:
		var x: float = -RouteGoalLot.HALF_WIDTH
		while x <= RouteGoalLot.HALF_WIDTH:
			var at: Vector3 = lot.transform * Vector3(x, 0.0, z)
			worst = maxf(worst, absf(float(terrain.call(&"height_at", at)) - lot.position.y))
			samples += 1
			x += 2.0
		z -= 2.0
	_expect(worst <= FLAT_TOLERANCE,
			"%s: the ground under the base is level (worst %.3f m over %d points)" % [label, worst, samples])
	# Nothing planted or built on it.
	var intruders: PackedStringArray = []
	for node: Node in route.find_children("*", "Node3D", true, false):
		if node == lot or lot.is_ancestor_of(node) or not node.has_meta(&"rule"):
			continue
		var local: Vector3 = lot.to_local((node as Node3D).global_position)
		if absf(local.x) <= LOT_X and local.z <= LOT_Z_FRONT and local.z >= LOT_Z_BACK:
			intruders.append("%s (%s) at %.1f, %.1f" % [node.name, node.get_meta(&"rule"), local.x, local.z])
	_expect(intruders.is_empty(), "%s: nothing dressed stands on the base: %s" % [label, intruders])
	for house: DeliveryHouse in route.get("houses"):
		_expect(lot.to_local(house.global_position).distance_to(Vector3(0.0, 0.0, -18.0)) > 32.0,
				"%s: house %d is clear of the base" % [label, house.house_index + 1])
	# Reachable: the path goes on into the bay, in short steps.
	var path: Array = route.get("_path_points")
	var widest: float = 0.0
	for index: int in range(1, path.size()):
		widest = maxf(widest, (path[index - 1] as Vector3).distance_to(path[index]))
	_expect(widest <= MAX_PATH_GAP,
			"%s: the road's path has no gap over %.0f m (widest %.1f)" % [label, MAX_PATH_GAP, widest])
	var end: Vector3 = path[-1]
	var bay: Vector3 = route.to_local(lot.bay_centre())
	_expect(Vector2(end.x - bay.x, end.z - bay.z).length() < 1.0, "%s: the path ends in the free bay" % label)
	_expect(route.call(&"distance_from_path", lot.bay_centre()) < 2.0,
			"%s: the bay is on the path (off-road check)" % label)
	_expect(lot.bay_number >= 1 and lot.bay_number <= 9, "%s: the free bay has a number (%d)" % [label, lot.bay_number])
	var target: Vector3 = route.call(&"goal_target")
	_expect(int(route.call(&"goal_bay_number")) == lot.bay_number and target.is_equal_approx(lot.bay_centre()),
			"%s: the route points at the bay" % label)
	_expect(lot.terrain_platform().height == lot.position.y and (terrain.get("platforms") as Array).size() == 1,
			"%s: the terrain levels a platform at the lot's height" % label)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	# The truck fits the free bay: nothing solid in its place.
	var pose: Transform3D = lot.parking_pose()
	_expect(_hits(space, Vector3(2.4, 2.6, 7.4), pose * Vector3(0.0, 0.6, 0.8), pose.basis) == 0,
			"%s: the free bay is clear" % label)
	# The way in from the road to the bay is clear for a truck.
	var blocked: int = 0
	for index: int in range(1, path.size()):
		var from: Vector3 = path[index - 1]
		var to: Vector3 = path[index]
		# Only the approach: a route that bends can leave much earlier road (a bridge
		# 600 m back) at the lot's negative z, and that is not the way in.
		var to_lot: Vector3 = lot.to_local(route.to_global(to))
		if to_lot.z > 0.0 or Vector2(to_lot.x, to_lot.z).length() > APPROACH_LENGTH:
			continue
		for step: int in range(5):
			var at: Vector3 = route.to_global(from.lerp(to, float(step) / 5.0))
			blocked += _hits(space, Vector3(2.4, 2.4, 2.4), at + Vector3.UP * 1.9, Basis.IDENTITY)
	_expect(blocked == 0, "%s: a truck-sized volume passes from the gate to the bay (%d hits)" % [label, blocked])
	# The parked trucks are solid.
	var solid: int = 0
	for index: int in range(RouteGoalLot.BAY_COUNT):
		if index == lot.free_index:
			continue
		var spot: Vector3 = lot.to_global(Vector3(RouteGoalLot.bay_x(index), 2.0, -26.0))
		solid += 1 if _hits(space, Vector3(1.0, 1.0, 1.0), spot, lot.global_basis) > 0 else 0
	_expect(solid == RouteGoalLot.BAY_COUNT - 1,
			"%s: the %d parked trucks are solid (%d)" % [label, RouteGoalLot.BAY_COUNT - 1, solid])
	# The parked trucks are drawn nose-in, inside their bays' lines and the wall.
	var trucks: MultiMeshInstance3D = lot.get_node_or_null(^"ParkedTrucks")
	_expect(trucks != null and trucks.multimesh.instance_count == RouteGoalLot.BAY_COUNT - 1,
			"%s: five trucks are drawn" % label)
	if trucks != null:
		var bounds: AABB = trucks.multimesh.mesh.get_aabb()
		_expect(lot.truck_transforms.size() == trucks.multimesh.instance_count,
				"%s: the lot knows where each truck is drawn" % label)
		for index: int in range(lot.truck_transforms.size()):
			var drawn: AABB = lot.truck_transforms[index] * bounds
			var centre_x: float = drawn.get_center().x
			var bay_index: int = roundi(centre_x / RouteGoalLot.BAY_WIDTH + float(RouteGoalLot.BAY_COUNT - 1) * 0.5)
			var off_centre: float = absf(centre_x - RouteGoalLot.bay_x(bay_index))
			var in_lines: bool = off_centre < 0.5 and drawn.size.x < RouteGoalLot.BAY_WIDTH - 1.0
			var in_depth: bool = drawn.position.z >= RouteGoalLot.BAY_BACK_Z and drawn.end.z <= RouteGoalLot.BAY_FRONT_Z
			_expect(in_lines and in_depth, "%s: truck %d stands inside its bay (%s)" % [label, index, drawn])
	var unloading: MeshInstance3D = lot.get_node_or_null(^"UnloadingTruck")
	if unloading != null:
		var seen: AABB = unloading.transform * unloading.mesh.get_aabb()
		var to_side: float = absf(seen.get_center().x)
		_expect(to_side > 12.0 and to_side < 18.0 and seen.end.z < -6.0 and seen.position.z > -20.0,
				"%s: the unloading truck is to one side (%s)" % [label, seen])
	# The people keep off the free bay, and are asleep until a truck comes.
	_expect(lot.workers.size() >= 2, "%s: there are workers unloading (%d)" % [label, lot.workers.size()])
	for worker: Node3D in lot.workers:
		_expect(worker.global_position.distance_to(lot.bay_centre()) > 10.0,
				"%s: %s stays away from the free bay" % [label, worker.name])
		_expect(worker.process_mode == Node.PROCESS_MODE_DISABLED,
				"%s: %s sleeps until a truck comes near" % [label, worker.name])
	_expect(lot.cones.size() >= 2, "%s: cones mark the bay (%d)" % [label, lot.cones.size()])
	_clear_world(route)
	await process_frame


func _hits(space: PhysicsDirectSpaceState3D, size: Vector3, centre: Vector3, basis: Basis) -> int:
	var shape := BoxShape3D.new()
	shape.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(basis, centre)
	query.collision_mask = 1
	return space.intersect_shape(query, 8).size()


func _lot_signature(lot: RouteGoalLot) -> Array:
	var workers: Array = lot.workers.map(func(worker: Node3D) -> Vector3: return worker.position)
	return [lot.free_index, lot.bay_number, lot.town_name, lot.unload_side, lot.truck_transforms, workers, lot.position]


func _test_same_for_every_peer() -> void:
	var signatures: Array = []
	for pass_index: int in range(2):
		var route: Node3D = _build_route(SEEDS[0], 2)
		signatures.append(_lot_signature(route.get("goal_lot")))
		await process_frame
		_clear_world(route)
		await process_frame
	_expect(signatures[0] == signatures[1],
			"The same seed builds the same base twice: bay, number, town, trucks, workers, place")
	# Lots on their own, over many seeds: the bay, its number and the trucks follow the seed.
	var seen_bays: Dictionary = {}
	var seen_numbers: Dictionary = {}
	var seen_sides: Dictionary = {}
	for seed_value: int in range(1, 41):
		var a: RouteGoalLot = _standalone_lot(seed_value, 0.0)
		var b: RouteGoalLot = _standalone_lot(seed_value, 0.0)
		_expect(_lot_signature(a) == _lot_signature(b), "Seed %d: two lots from one seed match" % seed_value)
		seen_bays[a.free_index] = true
		seen_numbers[a.bay_number] = true
		seen_sides[a.unload_side] = true
		var placed: bool = a.free_index >= 0 and a.free_index < RouteGoalLot.BAY_COUNT
		_expect(placed and a.bay_number == a.first_number + a.free_index,
				"Seed %d: the bay's number follows its place (%d, place %d)" % [seed_value, a.bay_number, a.free_index])
		a.get_parent().free()
		b.get_parent().free()
	_expect(seen_bays.size() == RouteGoalLot.BAY_COUNT,
			"Over 40 seeds every place in the row is the free one at some point (%d)" % seen_bays.size())
	_expect(seen_numbers.size() >= 5, "and the numbers vary (%d different)" % seen_numbers.size())
	_expect(seen_sides.size() == 2, "and the unloading truck stands on either side")
	await process_frame


## A lot by itself under a plain parent, at the origin, for the tests that do not need a road.
func _standalone_lot(seed_value: int, darkness: float) -> RouteGoalLot:
	var holder := Node3D.new()
	root.add_child(holder)
	var lot := RouteGoalLot.new()
	lot.configure(seed_value, "Villa Test", darkness)
	holder.add_child(lot)
	return lot


## A layer-2 body (what the truck is to the areas) at the given pose.
func _dummy_truck(parent: Node, pose: Transform3D) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.0, 4.0)
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_transform = pose
	return body


func _test_bay_rules() -> void:
	var lot: RouteGoalLot = _standalone_lot(SEEDS[0], 0.0)
	lot.bay_occupied_changed.connect(func(occupied: bool, _body: Node3D) -> void: _arrivals += 1 if occupied else 0)
	await physics_frame
	var pose: Transform3D = lot.parking_pose()
	var truck: CharacterBody3D = _dummy_truck(root, pose)
	for tick: int in range(4):
		await physics_frame
	_expect(lot.is_bay_occupied() and _arrivals == 1, "A truck in the free bay counts as arrived (%d)" % _arrivals)
	_expect(lot.gate_open, "The barrier lifts when a truck comes near the gate")
	for worker: Node3D in lot.workers:
		_expect(worker.process_mode != Node.PROCESS_MODE_DISABLED, "%s wakes up when a truck comes near" % worker.name)
	var stories: Array[String] = lot.result_stories()
	_expect(stories.size() == 1 and stories[0] == tr("WORLD_LOT_TIDY_PARKING"),
			"Straight in the bay: the tidy-parking line (%s, %.1f degrees)" % [stories, lot.parked_deviation])
	# Crooked, but still inside the lines.
	truck.global_transform = Transform3D(pose.basis.rotated(Vector3.UP, deg_to_rad(9.0)), pose.origin)
	await physics_frame
	await physics_frame
	_expect(lot.is_bay_occupied() and not lot.result_stories().is_empty(),
			"9 degrees off is still tidy (%.1f)" % lot.parked_deviation)
	truck.global_transform = Transform3D(pose.basis.rotated(Vector3.UP, deg_to_rad(16.0)), pose.origin)
	await physics_frame
	await physics_frame
	_expect(lot.is_bay_occupied() and lot.result_stories().is_empty(),
			"16 degrees off is parked, but not tidy (%.1f)" % lot.parked_deviation)
	# Backed in: the other way round is as tidy.
	truck.global_transform = Transform3D(pose.basis.rotated(Vector3.UP, PI), lot.bay_centre() + Vector3.UP * 0.9)
	await physics_frame
	await physics_frame
	_expect(lot.is_bay_occupied() and lot.parked_deviation < 1.0,
			"Backed in counts the same (%.1f degrees)" % lot.parked_deviation)
	# Across the bay, or out on the aisle: not in it.
	truck.global_transform = Transform3D(pose.basis.rotated(Vector3.UP, PI * 0.5), pose.origin)
	await physics_frame
	await physics_frame
	_expect(not lot.is_bay_occupied(), "Crossways it does not fit the bay")
	truck.global_transform = Transform3D(pose.basis, pose.origin + lot.global_basis * Vector3(0.0, 0.0, 8.0))
	await physics_frame
	await physics_frame
	_expect(not lot.is_bay_occupied(), "Out on the aisle in front of the bay is not parked")
	var next_door: Vector3 = lot.global_basis * Vector3(BAY_WIDTH_SHIFT, 0.0, 0.0)
	truck.global_transform = Transform3D(pose.basis, pose.origin + next_door)
	await physics_frame
	await physics_frame
	_expect(not lot.is_bay_occupied(), "In the neighbouring bay's line is not parked")
	truck.free()
	await physics_frame
	await physics_frame
	_expect(not lot.is_bay_occupied(), "Leaving clears the arrival")
	lot.get_parent().free()
	await process_frame


var _arrivals: int = 0
const BAY_WIDTH_SHIFT: float = 2.4


func _test_night_and_day() -> void:
	LowpolyMaterials.set_night_level(1.0)
	var lot: RouteGoalLot = _standalone_lot(SEEDS[1], 1.0)
	var lights: Array[Node] = lot.find_children("*", "OmniLight3D", true, false)
	_expect(lot.lamp_spots.size() == 4 and lights.size() == 5,
			"At night the four lamps and the free bay have a light (%d lights)" % lights.size())
	var lot_halos: int = 0
	for spot: Array in NightFlares.halo_spots(lot.get_parent()):
		for local: Vector3 in lot.lamp_spots:
			if (lot.transform * local).distance_to(spot[0] as Vector3) < 0.01:
				lot_halos += 1
				break
	_expect(lot_halos == 4, "The four lamps get their halos (%d found)" % lot_halos)
	_expect(lot.has_meta(&"halo_points") and (lot.get_meta(&"halo_points") as PackedVector3Array).size() == 4,
			"The lot lists its lamp glass for the halos")
	lot.get_parent().free()
	LowpolyMaterials.set_night_level(0.0)
	lot = _standalone_lot(SEEDS[1], 0.0)
	_expect(lot.find_children("*", "OmniLight3D", true, false).is_empty(), "By day there are no lights")
	lot.get_parent().free()
	await process_frame


func _test_level() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 1)
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var manager: Node = root.get_node(^"/root/RunManager")
	level.call(&"start_debug_delivery")
	await physics_frame
	var route: Node3D = level.get_node(^"World/Route")
	var lot: RouteGoalLot = route.get("goal_lot")
	var van: VehicleBody3D = level.get(&"vehicle")
	_expect(bool(manager.get(&"is_running")), "The run starts")
	var section: String = route.call(&"get_section_name", lot.bay_centre())
	_expect(section == tr("WORLD_ROUTE_SECTION_GOAL") % lot.bay_number,
			"Near the end the guide asks for the bay by number (%s)" % section)
	_expect("%d" % lot.bay_number in String(route.call(&"get_section_name", lot.bay_centre())),
			"...and the number is in the text")
	for index: int in range(int(manager.get(&"expected_houses"))):
		manager.call(&"register_delivery", index, &"delivered_ok", &"")
	# The boxes aboard come along, where they sit in the bay.
	var aboard: Dictionary = {}
	for package: RigidBody3D in level.get(&"packages"):
		if is_instance_valid(package) and bool(package.get(&"is_loaded")):
			aboard[package] = van.global_transform.affine_inverse() * package.global_transform

	# Through the bay without stopping: the tail at the mouth, creeping at 1.8 m/s.
	var pose: Transform3D = lot.parking_pose()
	var start: Transform3D = Transform3D(pose.basis, pose.origin + lot.global_basis * Vector3(0.0, 0.0, 1.5))
	_place(van, start, aboard)
	var heading: Vector3 = -lot.global_basis.z
	var was_in_bay: bool = false
	for tick: int in range(60):
		van.linear_velocity = heading * 1.8
		van.call(&"set_controls", 0.0, 0.0, false)
		await physics_frame
		was_in_bay = was_in_bay or lot.is_bay_occupied()
	_expect(was_in_bay, "The moving truck did pass through the bay")
	_expect(bool(manager.get(&"is_running")), "Rolling through the bay at speed does not end the run")

	# Stopped in it: ends, delivered.
	_place(van, pose, aboard)
	var ended: bool = false
	for tick: int in range(60 * 4):
		van.call(&"set_controls", -1.0, 0.0, true)
		await physics_frame
		if not bool(manager.get(&"is_running")):
			ended = true
			break
	_expect(ended, "Stopped in the free bay, the run ends")
	_expect(bool((manager.get(&"results") as Dictionary).get("delivered", false)), "...delivered")
	var stories: Array = (manager.get(&"results") as Dictionary).get("stories", [])
	_expect(tr("WORLD_LOT_TIDY_PARKING") in stories, "The results carry the tidy-parking line (%s)" % [stories])
	# The last shot is the parked truck in the base.
	await process_frame
	var camera: Node = van.get_node_or_null(^"ResultsCamera")
	_expect(camera != null and float(camera.get(&"arc_half")) > 0.0,
			"The results camera frames the parked truck instead of circling it")
	if camera != null:
		await process_frame
		var offset: Vector3 = (camera as Node3D).global_position - van.global_position
		var out: float = offset.dot(lot.results_direction())
		_expect(out > 6.0, "...from out in the lot, not from behind the back wall (%.1f m out)" % out)

	level.queue_free()
	await process_frame
	manager.call(&"reset_run")
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)


func _place(van: VehicleBody3D, pose: Transform3D, aboard: Dictionary) -> void:
	van.global_transform = pose
	van.linear_velocity = Vector3.ZERO
	van.angular_velocity = Vector3.ZERO
	for package: RigidBody3D in aboard:
		package.global_transform = van.global_transform * (aboard[package] as Transform3D)
		package.linear_velocity = Vector3.ZERO
		package.angular_velocity = Vector3.ZERO


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
