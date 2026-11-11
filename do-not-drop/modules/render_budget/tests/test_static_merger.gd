extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/render_budget/tests/test_static_merger.gd
##
## StaticMerger (modules/render_budget, expansion D-2012.2): the static meshes of many small code-built pieces
## folded into a few nodes of one holder, and the nodes that only carried them freed.
## - Plain boxes under plain holders become one `MergedStatic` mesh, a surface per material, the same triangles
##   in the same place (the merged AABB is the boxes' own in the holder's space); the holders that are left
##   empty are freed, the roots never.
## - Bodies and their collision shapes stay, and so do their visible boxes' holders when they are bodies (the box
##   is folded, the body is not); with drop_hidden a hidden box straight under a body (a collision-only box) goes.
## - Left alone, with everything under them: a mesh with a script, one under a node with an AnimationPlayer, one with
##   a ShaderMaterial, a mirrored one, a hidden branch. A mesh with metadata (somebody's marker) is drawn merged but
##   its node stays, with no mesh of its own.
## - `claim` is asked about what merge() would leave of a bare mesh: true frees it, false keeps it.
## - Two copies of an instanced model become one `MergedModels` MultiMesh with two instances, and the copies go.
## - begin() / fold() / fold_branch() / finish() are the same pass in steps: the same meshes, vertices and frees
##   as merge(), and nothing is added to the holder before finish().

const MODEL: String = "res://modules/render_budget/tests/fern_piece.tscn"
## Vertices of a box as loose triangles.
const BOX_VERTICES: int = 36

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_merge()
	_test_left_alone()
	_test_claim()
	_test_models()
	_test_steps()
	if _failures == 0:
		print("PASS: StaticMerger folds static boxes and model copies into a few meshes and frees their holders")
	quit(_failures)


func _material(color: Color) -> StandardMaterial3D:
	var made := StandardMaterial3D.new()
	made.albedo_color = color
	return made


func _box(parent: Node, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


## A holder in the tree, away from the origin and turned, so the merged space is not the world's by chance.
func _holder() -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.position = Vector3(100.0, 2.0, -50.0)
	holder.rotation.y = 0.7
	return holder


## A piece: a root with two plain holders of boxes (two materials), a body with a visible and a hidden box.
func _piece(holder: Node3D, at: Vector3, red: Material, grey: Material) -> Dictionary:
	var piece := Node3D.new()
	piece.name = "Piece"
	piece.position = at
	holder.add_child(piece)
	var left := Node3D.new()
	left.name = "Left"
	piece.add_child(left)
	_box(left, Vector3(-2.0, 0.0, 0.0), Vector3(1.0, 2.0, 3.0), red)
	_box(left, Vector3(-4.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0), grey)
	var right := Node3D.new()
	right.name = "Right"
	piece.add_child(right)
	_box(right, Vector3(3.0, 1.0, 0.0), Vector3(2.0, 2.0, 2.0), red)
	var body := StaticBody3D.new()
	body.name = "Body"
	piece.add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	_box(body, Vector3.ZERO, Vector3(4.0, 0.4, 4.0), grey)
	var hidden := _box(body, Vector3.ZERO, Vector3(1.0, 1.0, 1.0), null)
	hidden.visible = false
	return {"piece": piece, "body": body, "shape": shape}


## The AABB, in `holder`'s space, of every visible box under `node` (by the boxes' own size and placement).
func _boxes_aabb(holder: Node3D, node: Node) -> AABB:
	var to_holder: Transform3D = holder.global_transform.affine_inverse()
	var found: bool = false
	var bounds := AABB()
	for part: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := part as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var box: AABB = (to_holder * mesh.global_transform) * mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	return bounds


func _merged(holder: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child: Node in holder.get_children():
		if String(child.name).begins_with(StaticMerger.MERGED_NAME):
			out.append(child as MeshInstance3D)
	return out


func _vertex_count(mesh: Mesh) -> int:
	var count: int = 0
	for surface: int in mesh.get_surface_count():
		count += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return count


func _test_merge() -> void:
	var holder := _holder()
	var red := _material(Color.RED)
	var grey := _material(Color.GRAY)
	var made: Dictionary = _piece(holder, Vector3(0.0, 0.0, 10.0), red, grey)
	var expected: AABB = _boxes_aabb(holder, made.piece)
	var result: Dictionary = StaticMerger.merge(holder, [made.piece], true)
	var merged: Array[MeshInstance3D] = _merged(holder)
	_expect(merged.size() == 1, "The boxes become one MergedStatic (got %d)" % merged.size())
	_expect(int(result.parts) == 4, "Four visible boxes are merged (got %s)" % result.parts)
	if merged.size() == 1:
		var mesh: Mesh = merged[0].mesh
		_expect(mesh.get_surface_count() == 2, "A surface per material (got %d)" % mesh.get_surface_count())
		_expect(_vertex_count(mesh) == 4 * BOX_VERTICES, "The same triangles (%d vertices)" % _vertex_count(mesh))
		var aabb: AABB = mesh.get_aabb()
		_expect(aabb.position.is_equal_approx(expected.position) and aabb.size.is_equal_approx(expected.size),
			"...in the same place (merged %s, boxes %s)" % [aabb, expected])
		var materials: Array = [mesh.surface_get_material(0), mesh.surface_get_material(1)]
		_expect(materials.has(red) and materials.has(grey), "...with the same materials")
	var piece: Node3D = made.piece
	_expect(is_instance_valid(piece) and piece.get_parent() == holder, "The root is never freed")
	_expect(piece.get_node_or_null(^"Left") == null and piece.get_node_or_null(^"Right") == null,
		"The holders left empty are freed")
	_expect(is_instance_valid(made.body) and is_instance_valid(made.shape), "The body and its shape stay")
	_expect((made.body as Node).get_child_count() == 1, "...with only the shape: its box was folded, the hidden one"
		+ " dropped (children %d)" % (made.body as Node).get_child_count())
	holder.free()


func _test_left_alone() -> void:
	var holder := _holder()
	var red := _material(Color.RED)
	var piece := Node3D.new()
	holder.add_child(piece)
	var scripted := _box(piece, Vector3.ZERO, Vector3.ONE, red)
	var script := GDScript.new()
	script.source_code = "extends MeshInstance3D\n"
	script.reload()
	scripted.set_script(script)
	var marked := _box(piece, Vector3(2.0, 0.0, 0.0), Vector3.ONE, red)
	marked.set_meta(&"marker", true)
	var animated := Node3D.new()
	piece.add_child(animated)
	animated.add_child(AnimationPlayer.new())
	var moving := _box(animated, Vector3.ZERO, Vector3.ONE, red)
	var shader := ShaderMaterial.new()
	var shaded := _box(piece, Vector3(4.0, 0.0, 0.0), Vector3.ONE, shader)
	var mirrored := _box(piece, Vector3(6.0, 0.0, 0.0), Vector3.ONE, red)
	mirrored.scale = Vector3(-1.0, 1.0, 1.0)
	var hidden_branch := Node3D.new()
	hidden_branch.visible = false
	piece.add_child(hidden_branch)
	var under_hidden := _box(hidden_branch, Vector3.ZERO, Vector3.ONE, red)
	var plain := _box(piece, Vector3(8.0, 0.0, 0.0), Vector3.ONE, red)
	var result: Dictionary = StaticMerger.merge(holder, [piece])
	_expect(int(result.parts) == 2, "Only the plain box and the marked one are merged (got %s)" % result.parts)
	_expect(not is_instance_valid(plain), "...the plain one goes")
	_expect(is_instance_valid(marked) and marked.mesh == null,
		"...the marked one stays, for whoever marked it, drawn by the merged mesh (its own mesh emptied)")
	for kept: Node in [scripted, moving, shaded, mirrored, under_hidden]:
		_expect(is_instance_valid(kept) and (kept as MeshInstance3D).mesh != null,
			"%s is left as it was" % (kept.name if is_instance_valid(kept) else "a freed mesh"))
	holder.free()


func _test_claim() -> void:
	var holder := _holder()
	var piece := Node3D.new()
	holder.add_child(piece)
	var taken := _box(piece, Vector3.ZERO, Vector3.ONE, ShaderMaterial.new())
	taken.name = "Taken"
	var left := _box(piece, Vector3(2.0, 0.0, 0.0), Vector3.ONE, ShaderMaterial.new())
	left.name = "Left"
	var asked: Array[String] = []
	var claim := func(mesh: MeshInstance3D) -> bool:
		asked.append(String(mesh.name))
		return mesh.name == &"Taken"
	StaticMerger.merge(holder, [piece], false, claim)
	asked.sort()
	_expect(asked == ["Left", "Taken"], "claim is asked about each mesh merge() would leave (%s)" % [asked])
	_expect(not is_instance_valid(taken), "A claimed mesh goes")
	_expect(is_instance_valid(left) and left.mesh != null, "One not claimed stays")
	holder.free()


func _test_models() -> void:
	var holder := _holder()
	var piece := Node3D.new()
	holder.add_child(piece)
	var scene := load(MODEL) as PackedScene
	var copies: Array[Node3D] = []
	for index: int in 2:
		var copy := scene.instantiate() as Node3D
		copy.position = Vector3(index * 3.0, 0.0, 0.0)
		piece.add_child(copy)
		copies.append(copy)
	DressingBatcher.record_instances = true
	StaticMerger.merge(holder, [piece])
	DressingBatcher.record_instances = false
	var batch := holder.get_node_or_null(NodePath(StaticMerger.MODELS_NAME)) as MultiMeshInstance3D
	_expect(batch != null and batch.multimesh.instance_count == 2,
		"Two copies of a model become one MergedModels of two instances")
	if batch != null:
		var placed: Array = batch.get_meta(StaticMerger.INSTANCES_META, [])
		_expect(placed.size() == 2 and (placed[1] as Transform3D).origin.distance_to((placed[0] as Transform3D).origin) > 2.9,
			"...each where its copy stood (%s)" % [placed])
	_expect(not is_instance_valid(copies[0]) and not is_instance_valid(copies[1]), "...and the copies go")
	holder.free()


func _test_steps() -> void:
	var red := _material(Color.RED)
	var grey := _material(Color.GRAY)
	var whole := _holder()
	var whole_pieces: Array = []
	for index: int in 3:
		whole_pieces.append(_piece(whole, Vector3(index * 12.0, 0.0, 0.0), red, grey).piece)
	var at_once: Dictionary = StaticMerger.merge(whole, whole_pieces, true)
	var stepped := _holder()
	var pieces: Array[Node3D] = []
	for index: int in 3:
		pieces.append(_piece(stepped, Vector3(index * 12.0, 0.0, 0.0), red, grey).piece)
	var job: RefCounted = StaticMerger.begin(stepped, true)
	StaticMerger.fold(job, pieces[0])
	for branch: Node in pieces[1].get_children():
		StaticMerger.fold_branch(job, branch)
	_expect(_merged(stepped).is_empty(), "Nothing is added to the holder before finish()")
	StaticMerger.fold(job, pieces[2])
	var in_steps: Dictionary = StaticMerger.finish(job, stepped)
	_expect(int(in_steps.parts) == int(at_once.parts) and int(in_steps.freed) == int(at_once.freed),
		"In steps, the same parts and frees as merge() (%s / %s)" % [in_steps, at_once])
	var one: Array[MeshInstance3D] = _merged(whole)
	var other: Array[MeshInstance3D] = _merged(stepped)
	_expect(one.size() == 1 and other.size() == 1 and _vertex_count(one[0].mesh) == _vertex_count(other[0].mesh)
			and one[0].mesh.get_aabb().is_equal_approx(other[0].mesh.get_aabb()),
		"...and the same merged mesh")
	whole.free()
	stepped.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
