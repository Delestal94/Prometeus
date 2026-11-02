extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_prop_models.gd
##
## The shed's prop models (expansion group 18, assets/tools/build_shed_props.py in Blender's background mode):
## - the boxes (D-1806): S, M, L and XL, open and closed, each exactly its packing-grid size
##   (CompanyTuning.BOX_CELLS times GRID_CELL_M) when closed; open ones are as wide and as deep (the flaps fold out
##   over the top), and both carry a box collision of the closed size;
## - the supplies (D-1807), the cold and wet containers (D-1809) and the clipboard in the hand (D-1816, no
##   collision: it is held);
## every model loads, stands centred on its base, is a plausible size and stays low-poly (MAX_TRIANGLES).
## Their look still needs a person.

const DIR: String = "res://assets/models/props/"
const MAX_TRIANGLES: int = 800
const SLACK_M: float = 0.02
## group -> [model paths under DIR, with collision].
const GROUPS: Dictionary = {
	"boxes": [[
		"boxes/sm_box_s_open", "boxes/sm_box_s_closed", "boxes/sm_box_m_open", "boxes/sm_box_m_closed",
		"boxes/sm_box_l_open", "boxes/sm_box_l_closed", "boxes/sm_box_xl_open", "boxes/sm_box_xl_closed",
	], true],
}

var _failures: int = 0


func _initialize() -> void:
	for group: String in GROUPS:
		for path: String in GROUPS[group][0]:
			_check(path, bool(GROUPS[group][1]))
	if GROUPS.has("boxes"):
		_check_box_sizes()
	if _failures == 0:
		print("PASS: the shed's props load, stand on their base at their size and stay low-poly")
	quit(_failures)


func _check(path: String, collides: bool) -> Dictionary:
	var file: String = DIR + path + ".glb"
	var scene := load(file) as PackedScene if ResourceLoader.exists(file) else null
	_expect(scene != null, "%s loads" % file)
	if scene == null:
		return {}
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
	_expect(absf(box.position.y) < 0.01 and absf(box.get_center().x) < 0.01 and absf(box.get_center().z) < 0.01,
		"%s stands centred on its base (%s)" % [path, box])
	_expect(box.size.x > 0.005 and box.size.y > 0.001 and box.size.z > 0.005 and box.size.x < 2.0
		and box.size.z < 2.0, "%s is a plausible size (%s)" % [path, box.size])
	_expect(triangles <= MAX_TRIANGLES, "%s is low-poly (%d)" % [path, triangles])
	var shapes: Array[Node] = model.find_children("*", "CollisionShape3D", true, false)
	var hull := AABB()
	if collides:
		_expect(shapes.size() == 1, "%s has one simple collision" % path)
		if shapes.size() == 1:
			var shape: CollisionShape3D = shapes[0]
			hull = _to_model(model, shape) * shape.shape.get_debug_mesh().get_aabb()
	else:
		_expect(shapes.is_empty(), "%s has no collision (it is held)" % path)
	model.free()
	return {"box": box, "hull": hull}


func _check_box_sizes() -> void:
	for size_id: StringName in CompanyTuning.BOX_CELLS:
		var cells: Vector3i = CompanyTuning.BOX_CELLS[size_id]
		var expected := Vector3(cells) * CompanyTuning.GRID_CELL_M
		var name: String = String(size_id).to_lower()
		var closed: Dictionary = _check("boxes/sm_box_%s_closed" % name, true)
		var opened: Dictionary = _check("boxes/sm_box_%s_open" % name, true)
		if closed.is_empty() or opened.is_empty():
			continue
		var shut: AABB = closed["box"]
		_expect((shut.size - expected).abs().length() < SLACK_M, "%s closed is %s (got %s)" % [size_id, expected,
			shut.size])
		for hull: AABB in [closed["hull"], opened["hull"]]:
			_expect((hull.size - expected).abs().length() < SLACK_M, "%s collides as its closed size" % size_id)
		var open_box: AABB = opened["box"]
		_expect(open_box.size.x >= expected.x - SLACK_M and open_box.size.z >= expected.z - SLACK_M,
			"%s open is at least as wide and deep" % size_id)


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
