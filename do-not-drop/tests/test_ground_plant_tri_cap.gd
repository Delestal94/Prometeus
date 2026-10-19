extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ground_plant_tri_cap.gd
## N-331.6: everything the "ground_plant" rule of RouteDresser scatters (bushes,
## ferns, rocks, logs...) is repeated by the dozen in view, so each model has a
## triangle cap of 250. Reads the rule's own path list, so a model added to the
## rule is checked without touching this test.
## Three models were already over when the cap landed (fern, bramble thicket and
## tall grass clump, 360-448 tris); since N-331.10 the three fit: fern 154,
## bramble 243, tall_grass 210. LEGACY_OVER_CAP stays empty: a model that goes
## over the cap again is redone, not given a ceiling here.

const MAX_TRIS: int = 250

const LEGACY_OVER_CAP: Dictionary = {}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dresser := RouteDresser.new(Node3D.new(), null, 1)
	var paths: Array = []
	for rule: Dictionary in dresser.get(&"_rules"):
		if rule.id == &"ground_plant":
			paths = rule.paths
	_expect(paths.size() > 0, "ground_plant rule has models")
	for path: String in paths:
		var scene: PackedScene = load(path) as PackedScene
		_expect(scene != null, "%s loads" % path.get_file())
		if scene == null:
			continue
		var instance: Node = scene.instantiate()
		var tris: int = _triangles(instance)
		instance.free()
		_expect(tris > 0, "%s has geometry" % path.get_file())
		var cap: int = int(LEGACY_OVER_CAP.get(path.get_file(), MAX_TRIS))
		_expect(tris <= cap, "%s has %d tris, cap is %d" % [path.get_file(), tris, cap])
	quit(_failures)


func _triangles(root_node: Node) -> int:
	var total: int = 0
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices != null and (indices as PackedInt32Array).size() > 0:
				total += (indices as PackedInt32Array).size() / 3
			else:
				total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
