extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_async_build.gd
##
## N-408: the loading screen must never freeze, so the route builds itself over
## several frames (a slice of work per frame, the terrain's numbers on worker
## threads) instead of holding the main thread for seconds. With no loading cover up
## (a test, a tool, a restart) it builds in one go unless Route.always_slice is set,
## which is what this test does.
##
## - the route is not built when add_child() returns; it holds the loading cover
##   up (group SceneLoader.BUSY_GROUP) until it is, then leaves it and emits
##   `built` once; loading_progress() only ever goes up, from near 0 to 1;
## - it takes several frames, and no slice of work between two frames is long;
## - nothing falls while it builds: the cones the segments drop are bodies, held
##   out of the physics until the ground is there, and still stand on it after;
## - the result is the same road, the same ground and the same dressing as the
##   blocking build's (the golden test signs every node of them; this is a quick
##   digest for the same seed);
## - with a loading cover up (a SceneLoader under the root) it slices on its own, and
##   not when it is told not to (async_build off);
## - reveal_steps() cuts its first draw into several steps (N-408c, like the depot's):
##   the route stays hidden until the first one, the terrain tiles and the batched
##   dressing's cells are pieces of their own, no step shows a big share of it, and
##   after the last one it looks exactly as before (what was hidden stays hidden);
## - the delivery level waits for it: players are not spawned and the session is
##   not told "ready" until the road stands, and the houses get their orders then.

const ROUTE_SCENE: String = "res://scenes/gameplay/route/route.tscn"
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const ROUTE_SCRIPT: String = "res://scripts/gameplay/route/route.gd"
## A slice this long on this machine would be a hitch, even on a slow CI runner.
const MAX_SLICE_MSEC: float = 600.0

var _failures: int = 0


## A cover that stays up and loads nothing: all the route looks for is that it is there.
class IdleCover extends SceneLoader:
	func _run() -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var original_seed: Variant = network.get(&"world_seed")
	var original_houses: Variant = network.get(&"world_house_count")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 0)
	var route_script: GDScript = load(ROUTE_SCRIPT) as GDScript
	route_script.set(&"always_slice", true)
	await _test_sliced_build()
	await _test_same_world()
	await _test_reveal_steps()
	await _test_bodies_hold()
	await _test_level_waits()
	route_script.set(&"always_slice", false)
	await _test_cover_decides()
	network.set(&"world_seed", original_seed)
	network.set(&"world_house_count", original_houses)
	if _failures == 0:
		print("PASS: the route builds over frames, holds the cover while it does and ends up the same world")
	quit(_failures)


func _new_route(houses: int) -> Node3D:
	var route: Node3D = (load(ROUTE_SCENE) as PackedScene).instantiate() as Node3D
	route.set(&"house_count", houses)
	route.set(&"start_yard", Rect2(-15.0, 4.0, 30.0, 26.0))
	return route


func _test_sliced_build() -> void:
	var route: Node3D = _new_route(2)
	var built_count: Array[int] = [0]
	route.connect(&"built", func() -> void: built_count[0] += 1)
	root.add_child(route)
	_expect(not route.get(&"is_built"), "The route is not built when add_child() returns")
	_expect(route.is_in_group(SceneLoader.BUSY_GROUP), "It holds the loading cover up while it builds")
	var progress: float = float(route.call(&"loading_progress"))
	_expect(progress >= 0.0 and progress < 0.5, "The bar starts low (%.2f)" % progress)
	var last: float = progress
	var monotonic: bool = true
	var frames: int = 0
	while not route.get(&"is_built") and frames < 5000:
		await process_frame
		frames += 1
		var now: float = float(route.call(&"loading_progress"))
		if now < last:
			monotonic = false
		last = now
		if not route.get(&"is_built"):
			_expect(now < 1.0, "The bar is not full before the route is built")
	_expect(route.get(&"is_built"), "The route finishes building")
	_expect(frames >= 8, "It took several frames, not one (%d)" % frames)
	_expect(monotonic, "The bar never goes back")
	_expect(is_equal_approx(float(route.call(&"loading_progress")), 1.0), "It ends at 1")
	_expect(not route.is_in_group(SceneLoader.BUSY_GROUP), "It lets the cover go once built")
	_expect(built_count[0] == 1, "`built` fired once (%d)" % built_count[0])
	var stats: Dictionary = route.get(&"build_stats")
	_expect(float(stats.get("longest_slice_msec", INF)) < MAX_SLICE_MSEC,
		"No slice of work held the main thread for long (%.0f ms)" % float(stats.get("longest_slice_msec", INF)))
	_expect(int(stats.get("frames", 0)) >= 8, "The build recorded its frames (%s)" % [stats.get("frames")])
	var complete: bool = (route.get(&"houses") as Array).size() == 2 and route.get(&"dresser") != null
	_expect(complete and route.get(&"goal_lot") != null, "Houses, dressing and goal lot are all there")
	route.free()
	await process_frame


## A digest of the road, the ground and the dressing: enough to tell two builds apart.
func _digest(route: Node3D) -> Array:
	var terrain: TerrainField = route.get(&"terrain")
	var heights: Array[float] = []
	for index: int in range(0, 60):
		var at := Vector3(float(index) * 13.0 - 80.0, 0.0, -float(index) * 29.0 + 30.0)
		heights.append(snappedf(terrain.height_at(at), 0.0001))
	var meshes: int = 0
	var vertices: int = 0
	for node: Node in route.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			meshes += 1
			vertices += (mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var houses: Array = []
	for house: Node3D in route.get(&"houses"):
		houses.append([snappedf(house.position.x, 0.0001), snappedf(house.position.y, 0.0001),
			snappedf(house.position.z, 0.0001)])
	var points: Array[Vector3] = route.get(&"_path_points")
	return [snappedf(float(route.get(&"route_length")), 0.0001), (route.get(&"_segments") as Array).size(),
		houses, heights,
		meshes, vertices, route.find_children("*", "", true, false).size(), points.size(),
		snappedf(points[points.size() / 2].y, 0.0001), (route.get(&"dresser").placed_counts as Dictionary)]


func _test_same_world() -> void:
	var route_script: GDScript = load(ROUTE_SCRIPT) as GDScript
	var sliced: Node3D = _new_route(2)
	root.add_child(sliced)
	await Signal(sliced, &"built")
	await process_frame  # Not freed from inside the signal that woke us.
	var from_sliced: Array = _digest(sliced)
	sliced.free()
	route_script.set(&"always_slice", false)
	var blocking: Node3D = _new_route(2)
	root.add_child(blocking)
	_expect(blocking.get(&"is_built"), "With no loading cover, the route builds in one go unless told to slice")
	var from_blocking: Array = _digest(blocking)
	blocking.free()
	route_script.set(&"always_slice", true)
	await process_frame
	_expect(from_sliced == from_blocking, "The sliced build is the very same world as the blocking one")
	_expect(from_sliced[3].size() == 60 and from_sliced[6] > 1000,
		"The digest saw a real route (%d nodes)" % from_sliced[6])


## A seed whose road has a construction zone: its cones are loose bodies.
func _seed_with_cones() -> int:
	for candidate: int in range(1, 200):
		for planned: Dictionary in RoutePlanner.plan_spine(candidate, 2, true).segments:
			if planned.script == ConstructionZoneSegment:
				return candidate
	return 0


func _test_bodies_hold() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var seed_value: int = _seed_with_cones()
	_expect(seed_value != 0, "Some seed has a construction zone")
	network.set(&"world_seed", seed_value)
	var route: Node3D = _new_route(2)
	root.add_child(route)
	var cones: Array[Node] = []
	var frames: int = 0
	while not route.get(&"is_built") and frames < 5000:
		await process_frame
		frames += 1
		for body: Node in route.find_children("ConstructionCone*", "RigidBody3D", true, false):
			if not cones.has(body):
				cones.append(body)
		# Falling is at 4.9 m in the first second: not a metre of it while the ground is missing.
		for cone: Node in cones:
			if (cone as Node3D).global_position.y < -6.0:
				_expect(false, "A cone fell while the route was building (y %.1f)" % (cone as Node3D).global_position.y)
				return
	_expect(cones.size() > 0, "The road built cones (%d)" % cones.size())
	# Let the physics run a while with the cones thawed: they stay on the ground.
	for _frame: int in range(40):
		await physics_frame
	var terrain: TerrainField = route.get(&"terrain")
	var fell: int = 0
	for cone: Node in cones:
		var at: Vector3 = (cone as Node3D).global_position
		if at.y < terrain.height_at(at) - 1.0:
			fell += 1
	_expect(fell == 0, "No cone fell through the world while the route built (%d of %d)" % [fell, cones.size()])
	for body: Node in route.find_children("*", "RigidBody3D", true, false):
		_expect((body as Node3D).process_mode != Node.PROCESS_MODE_DISABLED,
			"%s lives again once the route stands" % body.name)
		break
	route.free()
	network.set(&"world_seed", 4242)
	await process_frame


func _test_cover_decides() -> void:
	var cover := IdleCover.new()
	cover.name = "SceneLoader"
	root.add_child(cover)
	var sliced: Node3D = _new_route(1)
	root.add_child(sliced)
	_expect(not sliced.get(&"is_built"), "With a loading cover up the route slices its build on its own")
	var unsliced: Node3D = _new_route(1)
	unsliced.set(&"async_build", false)
	root.add_child(unsliced)
	_expect(unsliced.get(&"is_built"), "...unless it is told not to")
	await Signal(sliced, &"built")
	await process_frame
	sliced.free()
	unsliced.free()
	cover.free()
	var plain: Node3D = _new_route(1)
	root.add_child(plain)
	_expect(plain.get(&"is_built"), "Without the cover it builds in one go")
	plain.free()
	await process_frame


func _test_level_waits() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	var level: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var route: Node3D = level.get_node(^"World/Route")
	_expect(not route.get(&"is_built"), "The level's route is still building after _ready()")
	_expect(level.local_player == null, "Nobody is spawned into a world that is still building")
	_expect(route.get(&"house_count") >= 1 and level.depot.assignments().size() == int(route.get(&"house_count")),
		"The orders are posted on the board from the start (%d)" % level.depot.assignments().size())
	await process_frame
	await process_frame
	_expect(level.local_player == null and not route.get(&"is_built"), "...nor on the frames after")
	var frames: int = 0
	while not route.get(&"is_built") and frames < 5000:
		await process_frame
		frames += 1
	_expect(route.get(&"is_built"), "The level's route builds")
	await process_frame
	await process_frame
	_expect(level.local_player != null, "The player is spawned once the road stands")
	var houses: Array = route.get(&"houses")
	var labelled: int = 0
	for house: DeliveryHouse in houses:
		if not house.assigned_package_id.is_empty():
			labelled += 1
	_expect(labelled == houses.size() and houses.size() > 0,
		"Every house got its order when the route built (%d of %d)" % [labelled, houses.size()])
	level.free()
	current_scene = null
	await process_frame


func _test_reveal_steps() -> void:
	var route: Node3D = _new_route(2)
	root.add_child(route)
	var early: Array[Callable] = route.call(&"reveal_steps")
	_expect(early.size() == 1, "Before it is built the route has one step: just showing itself (%d)" % early.size())
	route.visible = false
	await Signal(route, &"built")
	await process_frame
	route.visible = true
	var before: Array[bool] = _visible_state(route)
	route.visible = false
	var steps: Array[Callable] = route.call(&"reveal_steps")
	_expect(steps.size() >= 8, "Its first draw is cut into several steps (%d)" % steps.size())
	_expect(not route.visible, "The route itself stays hidden until the first step")
	var terrain: Node3D = route.get(&"terrain")
	var tiles: int = 0
	for tile: Node in terrain.get_children():
		if tile is Node3D and not (tile as Node3D).visible:
			tiles += 1
	_expect(tiles > 1 and terrain.visible, "The terrain is cut by tile, not shown in one go (%d tiles waiting)" % tiles)
	var cells: Node = route.get_node_or_null(^"BatchedDressing")
	_expect(cells != null and cells.get_child_count() > 1, "The route has batched dressing cells to split")
	if cells != null:
		var waiting: int = 0
		for cell: Node in cells.get_children():
			if not (cell as Node3D).visible:
				waiting += 1
		_expect(waiting == cells.get_child_count(), "Every dressing cell waits for its own step (%d)" % waiting)
	var growing: bool = true
	var largest: int = 0
	var shown_so_far: int = _count_shown(route)
	var start: int = shown_so_far
	for index: int in range(steps.size()):
		steps[index].call()
		if index == 0:
			_expect(route.visible, "The first step shows the route")
		var count: int = _count_shown(route)
		if count < shown_so_far:
			growing = false
		largest = maxi(largest, count - shown_so_far)
		shown_so_far = count
	var total: int = shown_so_far - start
	_expect(growing, "Each step only adds to what is shown")
	_expect(largest * 4 <= total, "No step shows a big share of the route (%d of %d pieces)" % [largest, total])
	_expect(_visible_state(route) == before, "After the last step the route looks exactly as before")
	route.free()
	await process_frame


## Every node's own `visible` under (and including) `node`, in tree order.
func _visible_state(node: Node) -> Array[bool]:
	var state: Array[bool] = []
	if node is Node3D:
		state.append((node as Node3D).visible)
	for child: Node in node.get_children():
		state.append_array(_visible_state(child))
	return state


## The pieces showing: the route's children plus the terrain tiles and dressing cells.
func _count_shown(route: Node3D) -> int:
	var count: int = 0
	var terrain: Node = route.get(&"terrain")
	for child: Node in route.get_children():
		var holders: Array[Node] = [child]
		if child == terrain or child.name == &"BatchedDressing":
			holders = child.get_children()
		for piece: Node in holders:
			if piece is Node3D and (piece as Node3D).visible:
				count += 1
	return count


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
