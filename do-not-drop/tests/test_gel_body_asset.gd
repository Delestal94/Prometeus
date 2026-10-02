extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_body_asset.gd
## Guards the isolated S-311 body exports, not the active rounded player:
## three triangle budgets, identical eleven working morphs, twenty named bones,
## nine animation durations, finite vertex/UV data, zone colours and foot pivot.
## Closure, UV overlap and intersections are checked independently by validate_glb.py.

const BASE: String = "res://assets/models/characters/gel/gel_body_lod%d.glb"
const MORPHS: Array[String] = [
	"general_thickness", "belly", "chest", "shoulders", "hips", "arm_thickness",
	"leg_thickness", "hand_size", "foot_size", "head_shape", "neck_thickness",
]
const BUDGETS: Array[int] = [6000, 2500, 800]
const DURATIONS: Dictionary = {
	"Idle": 6.0, "Walk": 1.0 / 3.0, "Stroll": 0.6, "Run": 1.0 / 3.0, "Jump": 1.6,
	"PickUpPackage": 1.6, "PickUpHigh": 1.6, "Sit": 4.0, "TurnInPlace": 0.8,
}
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for lod: int in range(3):
		var path: String = BASE % lod
		var scene: PackedScene = load(path) as PackedScene
		_expect(scene != null, "LOD%d is importable (got %s)" % [lod, scene])
		if scene == null:
			continue
		var model: Node3D = scene.instantiate() as Node3D
		root.add_child(model)
		await process_frame
		var skeleton: Skeleton3D = _find(model, "Skeleton3D") as Skeleton3D
		_expect(skeleton != null, "LOD%d has a skeleton (got %s)" % [lod, skeleton])
		if skeleton != null:
			_expect(skeleton.get_bone_count() == 20,
				"LOD%d has twenty bones (got %d)" % [lod, skeleton.get_bone_count()])
			for name: String in ["pelvis", "chest", "neck", "head"]:
				_expect(skeleton.find_bone(name) >= 0, "LOD%d retains %s" % [lod, name])
			for side: String in ["L", "R"]:
				for name: String in ["upper_arm", "forearm", "hand", "thumb", "grip", "thigh", "shin", "foot"]:
					_expect(skeleton.find_bone(name + "." + side) >= 0, "LOD%d retains %s.%s" % [lod, name, side])
		var player: AnimationPlayer = _find(model, "AnimationPlayer") as AnimationPlayer
		_expect(player != null, "LOD%d has animation clips (got %s)" % [lod, player])
		if player != null:
			for clip: String in DURATIONS:
				_expect(player.has_animation(clip), "LOD%d retains clip %s" % [lod, clip])
				if player.has_animation(clip):
					var duration: float = player.get_animation(clip).length
					_expect(absf(duration - float(DURATIONS[clip])) < 0.02,
						"LOD%d %s duration matches source (got %.3f)" % [lod, clip, duration])
		var body: MeshInstance3D = _find(model, "MeshInstance3D") as MeshInstance3D
		_expect(body != null and body.mesh != null, "LOD%d has body geometry (got %s)" % [lod, body])
		if body != null and body.mesh != null:
			_check_mesh(body, lod)
		model.free()
	if _failures == 0:
		print("PASS: isolated gel body LODs, morphs, rig, clips and geometry")
	quit(_failures)


func _check_mesh(body: MeshInstance3D, lod: int) -> void:
	var mesh: Mesh = body.mesh
	_expect(mesh.get_surface_count() == 1, "LOD%d body uses one surface (got %d)" % [lod, mesh.get_surface_count()])
	_expect(mesh.get_blend_shape_count() == MORPHS.size(),
		"LOD%d has eleven morphs (got %d)" % [lod, mesh.get_blend_shape_count()])
	for index: int in mini(mesh.get_blend_shape_count(), MORPHS.size()):
		_expect(String(mesh.get_blend_shape_name(index)) == MORPHS[index],
			"LOD%d morph%d matches contract (got %s)" % [lod, index, mesh.get_blend_shape_name(index)])
		body.set_blend_shape_value(index, -1.0)
		_expect(is_equal_approx(body.get_blend_shape_value(index), -1.0),
			"LOD%d morph%d accepts negative weight" % [lod, index])
		body.set_blend_shape_value(index, 1.0)
		_expect(is_equal_approx(body.get_blend_shape_value(index), 1.0),
			"LOD%d morph%d accepts positive weight" % [lod, index])
		body.set_blend_shape_value(index, 0.0)
	var triangles: int = 0
	var bottom: float = INF
	var top: float = -INF
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var zones: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		_expect(uv.size() == vertices.size(),
			"LOD%d has UV0 for every vertex (got %d/%d)" % [lod, uv.size(), vertices.size()])
		_expect(zones.size() == vertices.size(),
			"LOD%d has zone colours (got %d/%d)" % [lod, zones.size(), vertices.size()])
		# One report per LOD, not one per vertex: a broken export would print thousands.
		var bad_vertices: int = 0
		for vertex: Vector3 in vertices:
			if not vertex.is_finite():
				bad_vertices += 1
				continue
			var world: Vector3 = body.to_global(vertex)
			bottom = minf(bottom, world.y)
			top = maxf(top, world.y)
		_expect(bad_vertices == 0, "LOD%d positions are finite (got %d bad)" % [lod, bad_vertices])
		var bad_uvs: int = 0
		for point: Vector2 in uv:
			if not point.is_finite():
				bad_uvs += 1
		_expect(bad_uvs == 0, "LOD%d UVs are finite (got %d bad)" % [lod, bad_uvs])
	_expect(triangles <= BUDGETS[lod], "LOD%d stays within budget (got %d/%d)" % [lod, triangles, BUDGETS[lod]])
	_expect(absf(bottom) < 0.005, "LOD%d soles sit at world zero (got %.4f)" % [lod, bottom])
	_expect(absf(top - 1.74) < 0.03, "LOD%d keeps the target height (got %.4f)" % [lod, top])


func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child: Node in node.get_children():
		var result: Node = _find(child, type)
		if result != null:
			return result
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
