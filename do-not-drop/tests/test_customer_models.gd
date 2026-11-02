extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_customer_models.gd
##
## The customers at the door (expansion D-1819, assets/tools/build_customer_models.py in Blender's background mode):
## six variants, each loads, stands on its feet (lowest point at 0, about the origin), is a person's height
## (MIN_HEIGHT_M to MAX_HEIGHT_M: the kid is the short one), low-poly, with one simple collision, and no two files
## alike. They have no rig: the door's reaction moves the whole figure. Their look still needs a person.

const DIR: String = "res://assets/models/characters/customers/"
const CUSTOMERS: Array[String] = ["grandma", "cap_neighbour", "braids_girl", "moustache_man", "kid", "cook"]
const MIN_HEIGHT_M: float = 1.1
const MAX_HEIGHT_M: float = 2.1
const MAX_TRIANGLES: int = 800

var _failures: int = 0


func _initialize() -> void:
	var files: Dictionary = {}
	var heights: Array[float] = []
	for id: String in CUSTOMERS:
		var path: String = DIR + "sm_customer_%s.glb" % id
		var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
		_expect(scene != null, "%s loads" % id)
		if scene == null:
			continue
		files[hash(FileAccess.get_file_as_bytes(path))] = id
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
				var indices: Variant = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
				triangles += (indices as PackedInt32Array).size() / 3 if indices != null else 0
		_expect(absf(box.position.y) < 0.01, "%s stands on its feet (%.3f)" % [id, box.position.y])
		_expect(absf(box.get_center().x) < 0.05 and absf(box.get_center().z) < 0.15, "%s stands about its origin" % id)
		_expect(box.size.y >= MIN_HEIGHT_M and box.size.y <= MAX_HEIGHT_M, "%s is %.2f m tall" % [id, box.size.y])
		_expect(triangles <= MAX_TRIANGLES, "%s is low-poly (%d)" % [id, triangles])
		_expect(model.find_children("*", "CollisionShape3D", true, false).size() == 1, "%s has one collision" % id)
		heights.append(box.size.y)
		model.free()
	_expect(files.size() == CUSTOMERS.size(), "six different customers")
	_expect(heights.min() < 1.4, "one of them is a kid (%.2f m)" % heights.min())
	if _failures == 0:
		print("PASS: six customers stand at the door at a person's height, low-poly and all different")
	quit(_failures)


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
