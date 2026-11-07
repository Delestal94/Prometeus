extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ground_plant_tri_cap.gd
## N-331.6: everything the "ground_plant" rule of RouteDresser scatters (bushes,
## ferns, rocks, logs...) is repeated by the dozen in view, so each model has a
## triangle cap of 250. Reads the rule's own path list, so a model added to the
## rule is checked without touching this test.
## Three models were already over when the cap landed (fern, bramble thicket and
## tall grass clump, 360-448 tris); since N-331.10 the three fit: fern 154
## (220 since N-331.11), bramble 243, tall_grass 210. LEGACY_OVER_CAP stays
## empty: a model that goes over the cap again is redone, not given a ceiling here.
## N-331.11: the small fern's fronds are joined blades, not loose leaflets: every
## edge-connected piece of its mesh (welded by position) is a whole frond of at
## least JOINED_MIN_TRIS (the N-331.10 leaflets came apart in pairs of 2).

const MAX_TRIS: int = 250

const LEGACY_OVER_CAP: Dictionary = {}

const JOINED_FERN: String = "sm_env_forest_fern.glb"
const JOINED_MIN_TRIS: int = 10

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
		if path.get_file() == JOINED_FERN:
			var smallest: int = _smallest_piece(instance)
			_expect(smallest >= JOINED_MIN_TRIS, "%s: smallest connected piece has %d tris, want >= %d (joined fronds)"
				% [JOINED_FERN, smallest, JOINED_MIN_TRIS])
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


## Triangles in the smallest edge-connected piece of the model's meshes, with
## vertices welded by position (the importer splits them by normal).
func _smallest_piece(root_node: Node) -> int:
	var corners: Array[String] = []
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var order: PackedInt32Array = indices if indices != null else PackedInt32Array(range(vertices.size()))
			for i: int in order:
				var v: Vector3 = vertices[i]
				corners.append("%d,%d,%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0)])
	var count: int = corners.size() / 3
	if count == 0:
		return 0
	var parent: PackedInt32Array = PackedInt32Array(range(count))
	var owner: Dictionary = {}
	for t: int in range(count):
		for k: int in range(3):
			var a: String = corners[t * 3 + k]
			var b: String = corners[t * 3 + (k + 1) % 3]
			var edge: String = a + "|" + b if a < b else b + "|" + a
			if owner.has(edge):
				_union(parent, t, int(owner[edge]))
			else:
				owner[edge] = t
	var sizes: Dictionary = {}
	for t: int in range(count):
		var r: int = _find(parent, t)
		sizes[r] = int(sizes.get(r, 0)) + 1
	var smallest: int = count
	for r: int in sizes:
		smallest = mini(smallest, int(sizes[r]))
	return smallest


func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	parent[_find(parent, a)] = _find(parent, b)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
