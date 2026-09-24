extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_world_determinism.gd
## Every player builds the same world from the session seed (tareas de Nacho
## N-802). test_world_seed checks the goal and the houses; this checks
## everything: the whole level is built twice with the same seed -- road,
## terrain, every roadside prop and tree (batched or not), yards, depot, the
## boxes on its shelves -- and every position must match, as must the orders
## on the board, the shelf codes and the weather. A randf() that skips the
## session seed anywhere in the world breaks it (the bug of the old #122).
##
## Left out on purpose: what each peer simulates or animates on its own
## (players, the truck, the loose clutter in the cargo bay, particles,
## cameras), which never needed to match.

const SEED: int = 424242
const SNAP: float = 0.001

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", SEED)
	network.set(&"world_house_count", 3)
	var first: Dictionary = await _build()
	var second: Dictionary = await _build()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)

	_expect(first.positions.size() > 2000, "The fingerprint covers the whole world (%d positions)" % first.positions.size())
	_expect(first.positions.size() == second.positions.size(), "Both builds place as many things (%d vs %d)" % [first.positions.size(), second.positions.size()])
	if first.positions != second.positions:
		var only_first: Array = first.positions.filter(func(entry: String) -> bool: return not second.positions.has(entry))
		var only_second: Array = second.positions.filter(func(entry: String) -> bool: return not first.positions.has(entry))
		_expect(false, "Every position matches between builds; first differences: %s / %s" % [only_first.slice(0, 5), only_second.slice(0, 5)])
	_expect(first.orders == second.orders, "The depot posts the same orders (%s)" % [first.orders])
	_expect(first.codes == second.codes, "The boxes get the same shelf codes")
	_expect(first.mood == second.mood, "The weather and time of day match (%s)" % first.mood)

	if _failures == 0:
		print("PASS: the same seed builds the same world, down to every prop, box and order (%d positions)" % first.positions.size())
	quit(_failures)


func _build() -> Dictionary:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	# Right after it's built, before any physics tick: how many ticks the
	# first frame runs depends on how long loading took, and bodies settle.
	var world: Node3D = level.get_node(^"World")
	var positions: Array[String] = []
	_collect(world, world, positions)
	positions.sort()
	await process_frame
	var depot: Node = world.get_node(^"Depot")
	var orders: Array = []
	for order: Dictionary in depot.get(&"orders"):
		orders.append([String(order.package_id), order.code, int(order.house)])
	var codes: Array = []
	for package: Node in level.get(&"packages"):
		codes.append("%s=%s" % [package.get(&"package_id"), package.get_meta(&"dispatch_code", "")])
	codes.sort()
	var mood: String = str(WorldMood.active)
	level.free()
	root.get_node(^"/root/RunManager").call(&"reset_run")
	await process_frame
	return {"positions": positions, "orders": orders, "codes": codes, "mood": mood}


## Every placed thing's position in world space, by kind, plus every
## instance of every MultiMesh (the batched dressing).
func _collect(node: Node, world: Node3D, out: Array[String]) -> void:
	if _skipped(node):
		return
	if node is Node3D and not node is Camera3D:
		out.append("%s %s" % [node.get_class(), _snap((node as Node3D).global_position)])
	if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var batch: MultiMeshInstance3D = node
		for index: int in range(batch.multimesh.instance_count):
			out.append("instance %s" % _snap(batch.global_transform * batch.multimesh.get_instance_transform(index).origin))
	for child: Node in node.get_children():
		_collect(child, world, out)


## What each peer runs on its own, and what moves before the first frame.
func _skipped(node: Node) -> bool:
	if node is VehicleBody3D or node.is_in_group(&"player") or node is GPUParticles3D or node is CPUParticles3D:
		return true
	if String(node.name).begins_with("CargoClutter"):
		return true
	# Depot workers, the forklift and the roadside animals move from their
	# first frame, each peer on its own.
	var script := node.get_script() as Script
	if script == null:
		return false
	var path: String = script.resource_path.get_file()
	return path in ["depot_worker.gd", "depot_forklift.gd", "wildlife_animal.gd"]


func _snap(point: Vector3) -> String:
	return str(point.snapped(Vector3.ONE * SNAP))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
