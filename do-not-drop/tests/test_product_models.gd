extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_product_models.gd
##
## The company's product models (expansion group 18, built by assets/tools/build_product_models.py in Blender's
## background mode), lot by lot: every model of LOTS
## - loads from assets/models/products/sm_product_<id>.glb as a scene;
## - has its simple collision: the "-colonly" box becomes one CollisionShape3D (a static body) wrapping the model
##   (within COLLISION_SLACK_M);
## - stands on the floor with its origin at the centre of its base (lowest point at 0, centred on X and Z);
## - is a plausible size (MIN_M to MAX_M on every side) and low-poly (at most MAX_TRIANGLES).
## Its look still needs a person (no capture in this test).

const DIR: String = "res://assets/models/products/"
const MIN_M: float = 0.01
const MAX_M: float = 2.0
const MAX_TRIANGLES: int = 800
const COLLISION_SLACK_M: float = 0.02
## lot -> product ids (1 D-1802, 2 D-1803, 3 D-1804, 4 D-1805, 5 D-1821, 6 D-1822).
const LOTS: Dictionary = {
	1: ["bottle", "book", "mug", "sneakers", "desk_lamp", "toaster", "backpack", "board_game", "headphones", "teapot"],
	2: [
		"wine_glasses", "plate_stack", "television", "mirror", "glass_jar", "tall_vase", "chandelier",
		"ceramic_teapot", "picture_frame", "snow_globe_glass"
	],
	3: [
		"ice_cream_tub", "fish", "flowers", "butter_block", "milk_bottle", "egg_carton", "frozen_peas",
		"strawberries", "yogurt_pack", "frozen_pizza"
	],
	4: [
		"bicycle", "rolled_mattress", "potted_plant", "fish_tank", "guitar", "floor_lamp", "rolled_rug",
		"armchair", "surfboard", "drum"
	],
}

var _failures: int = 0


func _initialize() -> void:
	for lot: int in LOTS:
		_expect((LOTS[lot] as Array).size() == 10, "lot %d has 10 products" % lot)
		for id: String in LOTS[lot]:
			_check(id)
	if _failures == 0:
		print("PASS: every product model loads, stands on its base, has its box collision and stays low-poly")
	quit(_failures)


func _check(id: String) -> void:
	var path: String = DIR + "sm_product_%s.glb" % id
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	_expect(scene != null, "%s loads" % path)
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	root.add_child(model)
	var box := AABB()
	var first: bool = true
	var triangles: int = 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var bounds: AABB = _to_model(model, mesh) * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices as PackedInt32Array).size() / 3 if indices != null else \
				(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_expect(not first, "%s has a mesh" % id)
	_expect(absf(box.position.y) < 0.01, "%s stands on the floor (lowest at %.3f)" % [id, box.position.y])
	var middle: Vector3 = box.get_center()
	_expect(absf(middle.x) < 0.01 and absf(middle.z) < 0.01, "%s is centred on its base (%s)" % [id, middle])
	for axis: int in 3:
		_expect(box.size[axis] >= MIN_M and box.size[axis] <= MAX_M, "%s is a plausible size (%s)" % [id, box.size])
	_expect(triangles <= MAX_TRIANGLES, "%s is low-poly (%d triangles)" % [id, triangles])
	var shapes: Array[Node] = model.find_children("*", "CollisionShape3D", true, false)
	_expect(shapes.size() == 1 and (shapes[0] as CollisionShape3D).shape != null, "%s has one simple collision" % id)
	if shapes.size() == 1 and (shapes[0] as CollisionShape3D).shape != null:
		var shape: CollisionShape3D = shapes[0]
		var hull: AABB = _to_model(model, shape) * shape.shape.get_debug_mesh().get_aabb()
		_expect((hull.size - box.size).abs().length() < COLLISION_SLACK_M * 3.0
			and (hull.position - box.position).abs().length() < COLLISION_SLACK_M * 3.0,
			"%s's collision box wraps it (%s vs %s)" % [id, hull, box])
	model.free()


## `node`'s transform in `model`'s space, from the local transforms (global ones are not ready in _initialize).
static func _to_model(model: Node, node: Node3D) -> Transform3D:
	var total := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != model:
		if at is Node3D:
			total = (at as Node3D).transform * total
		at = at.get_parent()
	return total


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
