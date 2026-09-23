extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_render_batching.gd
##
## DressingBatcher (scripts/gameplay/route/dressing_batcher.gd) is a pure
## render optimisation: it may change how the route is drawn, never what the
## route is. The same seed is built twice, once as individual pieces and once
## batched, and compared:
##   - every static piece became exactly one MultiMesh instance, at exactly
##     the transform the dresser gave it (nothing lost, moved or doubled);
##   - what has behaviour of its own (animals, the windmill) stays a node;
##   - collision is untouched: the same shapes, in the same places;
##   - the route ends up drawn from a small fraction of the mesh instances;
##   - houses are one mesh each, animals stop being drawn when far away;
## plus the synthesized sounds being built once and shared.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node("NetworkManager")
	var original_seed: int = int(network.world_seed)
	network.world_seed = 9090

	DressingBatcher.record_instances = true
	var plain: Node3D = await _build(false)
	var expected: Dictionary = _piece_transforms(plain)
	var plain_meshes: int = plain.find_children("*", "MeshInstance3D", true, false).size()
	var plain_shapes: Array = _shape_signature(plain)
	plain.free()
	await process_frame

	var batched: Node3D = await _build(true)
	var holder: Node = batched.get_node_or_null(^"BatchedDressing")
	_expect(holder != null, "The batched route has its BatchedDressing")

	# 1. Every remaining piece plus every batch instance adds up to what the
	# dresser placed, each instance on a placed piece's exact transform.
	var remaining: Dictionary = _piece_transforms(batched)
	var instances: int = 0
	var unmatched: int = 0
	for multimesh_instance: Node in batched.find_children("*", "MultiMeshInstance3D", true, false):
		var multimesh: MultiMesh = (multimesh_instance as MultiMeshInstance3D).multimesh
		# Headless, the dummy renderer can't give instance transforms back:
		# read the copy the batcher kept for this (see record_instances).
		var recorded: Array = multimesh_instance.get_meta(&"instance_transforms", [])
		var headless: bool = DisplayServer.get_name() == "headless"
		_expect(recorded.size() == multimesh.instance_count, "Each batch keeps one transform per instance")
		for index: int in range(multimesh.instance_count):
			instances += 1
			var key: String = _key(recorded[index] if headless else multimesh.get_instance_transform(index))
			if int(expected.get(key, 0)) > 0:
				expected[key] = int(expected[key]) - 1
			else:
				unmatched += 1

	for key: String in remaining:
		expected[key] = int(expected.get(key, 0)) - int(remaining[key])
	var left_over: int = 0
	for key: String in expected:
		left_over += absi(int(expected[key]))
	_expect(instances > 1500, "Most of the dressing got batched (%d instances)" % instances)
	_expect(unmatched == 0, "Every batch instance sits exactly where a piece was placed (%d strays)" % unmatched)
	_expect(left_over == 0, "Nothing was lost or doubled: pieces = instances + kept nodes (%d off)" % left_over)

	# 2. Behaviour stays a node.
	var animals: Array[Node] = batched.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.get_script() == preload("res://scripts/presentation/wildlife_animal.gd"))
	_expect(not animals.is_empty(), "Animals are still nodes (%d)" % animals.size())
	for animal: Node in animals.slice(0, 5):
		for geometry: Node in animal.find_children("*", "GeometryInstance3D", true, false):
			_expect((geometry as GeometryInstance3D).visibility_range_end > 0.0, "Far animals aren't drawn (%s)" % animal.name)
			break

	# 3. Collision untouched.
	_expect(_shape_signature(batched) == plain_shapes, "Batching leaves every collision shape as it was (%d shapes)" % plain_shapes.size())

	# 4. Far fewer things to draw.
	var batched_meshes: int = batched.find_children("*", "MeshInstance3D", true, false).size() + batched.find_children("*", "MultiMeshInstance3D", true, false).size()
	_expect(batched_meshes * 5 < plain_meshes, "Drawn from a fraction of the instances (%d -> %d)" % [plain_meshes, batched_meshes])

	# 5. Houses are one mesh each; segments keep their named colliders.
	for house: Node in batched.get(&"houses"):
		var visual: Node = house.get_node_or_null(^"HouseVisual")
		_expect(visual != null and visual.find_children("*", "MeshInstance3D", true, false).size() == 1, "%s is drawn as one merged mesh" % house.name)
	batched.free()
	DressingBatcher.record_instances = false

	# 6. Sounds are synthesized once.
	_expect(SynthAudio.tape_rip() == SynthAudio.tape_rip(), "A synthesized sound is built once and shared")
	_expect(SynthAudio.ambient_wind().data.size() > 0, "The shared stream still holds samples")

	network.world_seed = original_seed
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: batching draws the same route from far fewer instances, without moving, losing or de-colliding anything")
	quit(_failures)


func _build(batch: bool) -> Node3D:
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate() as Node3D
	route.set(&"house_count", 3)
	route.set(&"batch_dressing", batch)
	root.add_child(route)
	await process_frame
	return route


## Route-space transforms of every placed piece still standing as a node
## (dressing groups and yards), counted by rounded transform.
func _piece_transforms(route: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var inverse: Transform3D = route.global_transform.affine_inverse()
	for node: Node in route.find_children("*", "Node3D", true, false):
		var parent_name: String = String(node.get_parent().name)
		if not (parent_name.ends_with("Dressing") or parent_name == "Yard"):
			continue
		if parent_name == "BatchedDressing" or node.find_children("*", "MeshInstance3D", true, false).is_empty():
			continue
		var key: String = _key(inverse * (node as Node3D).global_transform)
		result[key] = int(result.get(key, 0)) + 1
	return result


func _key(xform: Transform3D) -> String:
	var o: Vector3 = xform.origin.snapped(Vector3.ONE * 0.01)
	var z: Vector3 = xform.basis.z.snapped(Vector3.ONE * 0.01)
	return "%s|%s" % [o, z]


func _shape_signature(route: Node3D) -> Array:
	var signature: Array = []
	for shape: Node in route.find_children("*", "CollisionShape3D", true, false):
		signature.append("%s|%s" % [(shape as Node3D).global_position.snapped(Vector3.ONE * 0.01), (shape as CollisionShape3D).shape.get_class() if (shape as CollisionShape3D).shape != null else "none"])
	signature.sort()
	return signature


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
