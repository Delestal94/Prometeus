extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_depot_async_build.gd
##
## N-408: the loading screen must never freeze, so the depot builds itself over
## several frames (a slice of work per frame) instead of holding the main thread
## for ~300 ms inside _ready(). With no loading cover up (a test, a tool) it builds
## in one go unless Depot.always_slice is set, which is what this test does.
##
## - the depot is not built when add_child() returns; it holds the loading cover up
##   (group SceneLoader.BUSY_GROUP) until it is, then leaves it and emits `built`
##   once; loading_progress() only ever goes up, from near 0 to 1; it takes several
##   frames and no slice of work between two frames is long;
## - the result is the very same depot as the blocking build's: the same nodes in
##   the same order, the same meshes, the same shelf slots, the same stock;
## - with a loading cover up (a SceneLoader under the root) it slices on its own, and
##   not when it is told not to (async_build off);
## - reveal_steps() cuts its first draw into several steps: the depot stays hidden
##   until the first one, every step shows some of it, and after the last one it
##   looks exactly as it did before (what was hidden on purpose stays hidden);
## - the level waits for it (delivery and Endless alike): the boxes it brought wait
##   frozen, nobody is spawned and the session is not told "ready" until the depot
##   stands; then the boxes are on its shelves, the orders are on its board and the
##   houses have them.

## By path, not by class name: a test that names Depot compiles the packages before the autoloads exist.
const DEPOT_SCRIPT: String = "res://scripts/gameplay/depot/depot.gd"
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const ENDLESS_SCENE: String = "res://scenes/gameplay/level_endless.tscn"
## A slice this long on this machine would be a hitch, even on a slow CI runner.
const MAX_SLICE_MSEC: float = 250.0

var _failures: int = 0


## A cover that stays up and loads nothing: all the depot looks for is that it is there.
class IdleCover extends SceneLoader:
	func _run() -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var original_seed: Variant = network.get(&"world_seed")
	network.set(&"world_seed", 4242)
	# Every trap unlocked: locked ones are sent to the back (depot.gd withhold_locked)
	# and the test profile's unlocks depend on whichever tests ran before this one.
	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	for unlock_id: StringName in (unlocks.get(&"TRAP_UNLOCKS") as Dictionary).values():
		unlocks.unlocked[unlock_id] = true
	(load(DEPOT_SCRIPT) as GDScript).set(&"always_slice", true)
	await _test_sliced_build()
	await _test_same_depot()
	await _test_reveal_steps()
	await _test_level_waits(LEVEL_SCENE, true)
	await _test_level_waits(ENDLESS_SCENE, false)
	(load(DEPOT_SCRIPT) as GDScript).set(&"always_slice", false)
	await _test_cover_decides()
	network.set(&"world_seed", original_seed)
	if _failures == 0:
		print("PASS: the depot builds over frames, holds the cover, ends up the same and shows itself in pieces")
	quit(_failures)


func _new_depot() -> Node3D:
	return (load(DEPOT_SCRIPT) as GDScript).new() as Node3D


func _test_sliced_build() -> void:
	var depot: Variant = _new_depot()
	var built_count: Array[int] = [0]
	depot.built.connect(func() -> void: built_count[0] += 1)
	root.add_child(depot)
	_expect(not depot.is_built, "The depot is not built when add_child() returns")
	_expect(depot.is_in_group(SceneLoader.BUSY_GROUP), "It holds the loading cover up while it builds")
	var progress: float = depot.loading_progress()
	_expect(progress >= 0.0 and progress < 0.5, "The bar starts low (%.2f)" % progress)
	var last: float = progress
	var monotonic: bool = true
	var frames: int = 0
	while not depot.is_built and frames < 3000:
		await process_frame
		frames += 1
		var now: float = depot.loading_progress()
		if now < last:
			monotonic = false
		last = now
		if not depot.is_built:
			_expect(now < 1.0, "The bar is not full before the depot is built")
	_expect(depot.is_built, "The depot finishes building")
	_expect(frames >= 3, "It took several frames, not one (%d)" % frames)
	_expect(monotonic, "The bar never goes back")
	_expect(is_equal_approx(depot.loading_progress(), 1.0), "It ends at 1")
	_expect(not depot.is_in_group(SceneLoader.BUSY_GROUP), "It lets the cover go once built")
	_expect(built_count[0] == 1, "`built` fired once (%d)" % built_count[0])
	var stats: Dictionary = depot.build_stats
	var longest: float = float(stats.get("longest_slice_msec", INF))
	_expect(longest < MAX_SLICE_MSEC, "No slice of work held the main thread for long (%.0f ms)" % longest)
	_expect(int(stats.get("frames", 0)) >= 3, "The build recorded its frames (%s)" % [stats.get("frames")])
	_expect(depot.door != null and depot.slots.size() > 0 and depot.get_node_or_null(^"OrderBoard") != null
			and depot.get_node_or_null(^"Stock") != null, "Door, shelf slots, board and stock are all there")
	depot.free()
	await process_frame


## A digest of what the depot built: enough to tell two builds apart.
func _digest(depot: Variant) -> Array:
	var names: Array[String] = []
	for child: Node in depot.get_children():
		# Nodes made without a name get a counter in theirs (@Label3D@366): the same piece, another number.
		var child_name: String = String(child.name)
		if child_name.begins_with("@"):
			child_name = child_name.get_slice("@", 1)
		names.append("%s:%s" % [child_name, child.get_class()])
	var meshes: int = 0
	var vertices: int = 0
	for node: Node in depot.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			meshes += 1
			vertices += (mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var slots: Array = []
	for slot: Dictionary in depot.slots:
		slots.append([slot.code, snappedf(slot.transform.origin.x, 0.0001), snappedf(slot.transform.origin.z, 0.0001)])
	var stock: Array[String] = []
	for package: Node in depot.get_node(^"Stock").get_children():
		stock.append(String(package.name))
	return [names, depot.find_children("*", "", true, false).size(), meshes, vertices, slots, depot.guides.size(),
		stock, depot.supplies, depot.team_money]


func _test_same_depot() -> void:
	var sliced: Variant = _new_depot()
	root.add_child(sliced)
	await Signal(sliced, &"built")
	await process_frame  # Not freed from inside the signal that woke us.
	await process_frame
	var from_sliced: Array = _digest(sliced)
	sliced.free()
	(load(DEPOT_SCRIPT) as GDScript).set(&"always_slice", false)
	var blocking: Variant = _new_depot()
	root.add_child(blocking)
	_expect(blocking.is_built, "With no loading cover, the depot builds in one go unless told to slice")
	# The pieces that finish themselves a frame later (workers, the mirror) have by now, like the sliced one's.
	await process_frame
	await process_frame
	var from_blocking: Array = _digest(blocking)
	blocking.free()
	(load(DEPOT_SCRIPT) as GDScript).set(&"always_slice", true)
	await process_frame
	_expect(from_sliced == from_blocking, "The sliced build is the very same depot as the blocking one")
	_expect(from_sliced[1] > 1000 and (from_sliced[4] as Array).size() > 10,
		"The digest saw a real depot (%d nodes)" % from_sliced[1])


func _visible_state(depot: Variant) -> Array[bool]:
	var state: Array[bool] = [depot.visible]
	for child: Node in depot.get_children():
		state.append(child is Node3D and (child as Node3D).visible)
	return state


func _test_reveal_steps() -> void:
	var depot: Variant = _new_depot()
	root.add_child(depot)
	var early: Array[Callable] = depot.reveal_steps()
	_expect(early.size() == 1, "Before it is built a depot has one step: just showing itself (%d)" % early.size())
	depot.visible = false
	await Signal(depot, &"built")
	await process_frame
	depot.visible = true
	var before: Array[bool] = _visible_state(depot)
	depot.visible = false
	var steps: Array[Callable] = depot.reveal_steps()
	_expect(steps.size() >= 6, "Its first draw is cut into several steps (%d)" % steps.size())
	var hidden_children: int = 0
	for child: Node in depot.get_children():
		if child is Node3D and not (child as Node3D).visible and before[depot.get_children().find(child) + 1]:
			hidden_children += 1
	_expect(hidden_children > 20, "The pieces wait hidden until their step (%d)" % hidden_children)
	_expect(not depot.visible, "The depot itself stays hidden until the first step")
	var shown_so_far: int = 0
	var growing: bool = true
	for index: int in range(steps.size()):
		steps[index].call()
		var count: int = 0
		for child: Node in depot.get_children():
			if child is Node3D and (child as Node3D).visible:
				count += 1
		if index == 0:
			_expect(depot.visible, "The first step shows the depot")
		if count < shown_so_far:
			growing = false
		shown_so_far = count
	_expect(growing, "Each step only adds to what is shown")
	_expect(_visible_state(depot) == before, "After the last step the depot looks exactly as before")
	depot.free()
	await process_frame


func _test_cover_decides() -> void:
	var cover := IdleCover.new()
	cover.name = "SceneLoader"
	root.add_child(cover)
	var sliced: Variant = _new_depot()
	root.add_child(sliced)
	_expect(not sliced.is_built, "With a loading cover up the depot slices its build on its own")
	var unsliced: Variant = _new_depot()
	unsliced.set(&"async_build", false)
	root.add_child(unsliced)
	_expect(unsliced.is_built, "...unless it is told not to")
	await Signal(sliced, &"built")
	await process_frame
	sliced.free()
	unsliced.free()
	cover.free()
	var plain: Variant = _new_depot()
	root.add_child(plain)
	_expect(plain.is_built, "Without the cover it builds in one go")
	plain.free()
	await process_frame


func _test_level_waits(scene: String, has_route: bool) -> void:
	var tag: String = "delivery" if has_route else "endless"
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	var level: Node = (load(scene) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var depot: Variant = level.get_node(^"World/Depot")
	_expect(not depot.is_built, "%s: the level's depot is still building after _ready()" % tag)
	_expect(level.local_player == null, "%s: nobody is spawned into a world that is still building" % tag)
	_expect(level.packages.is_empty(), "%s: nothing is shelved before the depot stands" % tag)
	var waiting: Array[Node] = get_nodes_in_group(&"cargo")
	_expect(waiting.size() >= 7, "%s: the boxes the level brought are there (%d)" % [tag, waiting.size()])
	for package: Node in waiting:
		_expect(bool(package.get(&"freeze")), "%s: %s waits frozen until the floor exists" % [tag, package.name])
	await process_frame
	await process_frame
	_expect(level.local_player == null and not depot.is_built, "%s: ...nor on the frames after" % tag)
	var frames: int = 0
	while not depot.is_built and frames < 3000:
		await process_frame
		frames += 1
	_expect(depot.is_built, "%s: the level's depot builds" % tag)
	if has_route:
		var route: Node3D = level.get_node(^"World/Route")
		frames = 0
		while not route.get(&"is_built") and frames < 5000:
			await process_frame
			frames += 1
	await process_frame
	await process_frame
	_expect(level.local_player != null, "%s: the player is spawned once the world stands" % tag)
	_expect(not level.packages.is_empty() and level.packages.size() >= 14,
		"%s: the level's boxes and the depot's own are shelved (%d)" % [tag, level.packages.size()])
	var shelved: int = 0
	for package: Node in level.packages:
		if package.has_meta(&"dispatch_code"):
			shelved += 1
	_expect(shelved == level.packages.size(),
		"%s: every box has its bin (%d of %d)" % [tag, shelved, level.packages.size()])
	_expect(depot.orders.size() == (int(level.get_node(^"World/Route").get(&"house_count")) if has_route else 0),
		"%s: the orders are on the board (%d)" % [tag, depot.orders.size()])
	if has_route:
		var houses: Array = level.get_node(^"World/Route").get(&"houses")
		var labelled: int = 0
		for house: Node in houses:
			if not (house.get(&"assigned_package_id") as StringName).is_empty():
				labelled += 1
		_expect(labelled == houses.size() and houses.size() > 0,
			"%s: every house got its order (%d of %d)" % [tag, labelled, houses.size()])
	level.free()
	current_scene = null
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
