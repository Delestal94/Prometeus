extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_golden_art.gd
##
## N-971: the route golden (test_route_golden.gd) must not move when a segment's art changes. Builds a
## NarrowBridgeSegment, merges its geometry the way route.gd does with batch_dressing
## (DressingBatcher.merge_segment_geometry: the boxes and the meshes of every instanced .glb end up in one
## MergedGeometry) and signs it like the golden does (instanced .glb = scene name, x / z, yaw; MergedGeometry =
## only the surfaces with a RouteSegment._material()):
## - swapping the model of the bridge post (RouteSegment._scenes[POST_MODEL], as #396 / N-333 did with a new .glb)
##   leaves the signature alone: the bug was the post's mesh going into the MergedGeometry hash;
## - moving a post model, or the BridgePost collider, in z does change it (the signature is not blind).
## A change to the signing in test_route_golden.gd (_node_line / _merged_mesh) has to be mirrored here.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var base: String = await _signature(false, false)
	_expect(not base.is_empty() and base.contains("BridgePostModel"),
		"The bridge signature lists the post models (got %d chars)" % base.length())
	_expect(base.contains("MergedGeometry"), "The bridge segment gets a MergedGeometry (as with batch_dressing)")

	var swapped: String = await _signature(true, false)
	_expect(swapped == base, "Replacing the post's .glb leaves the signature unchanged (art is not hashed)")

	var moved_model: String = await _signature(false, true)
	_expect(moved_model != base, "Moving a post model in z changes the signature")

	var moved_box: String = await _signature(false, false, true)
	_expect(moved_box != base, "Moving the BridgePost collider in z changes the signature")

	RouteSegment._scenes.erase(NarrowBridgeSegment.POST_MODEL)
	if _failures == 0:
		print("PASS: swapping a segment's .glb leaves its golden signature alone; moving a transform changes it")
	quit(_failures)


## Builds a bridge, merges it and returns its signature. `swap_post`: another model under the post's path;
## `move_model` / `move_box`: shift the first BridgePostModel / BridgePost 1 m in z after building.
func _signature(swap_post: bool, move_model: bool, move_box: bool = false) -> String:
	RouteSegment._scenes.erase(NarrowBridgeSegment.POST_MODEL)
	if swap_post:
		# A different mesh under the same file name, as when the .glb is re-exported.
		var model := Node3D.new()
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = SphereMesh.new()
		model.add_child(mesh_node)
		mesh_node.owner = model
		var replacement := PackedScene.new()
		replacement.pack(model)
		model.free()
		replacement.take_over_path(NarrowBridgeSegment.POST_MODEL)
		RouteSegment._scenes[NarrowBridgeSegment.POST_MODEL] = replacement
	var segment := NarrowBridgeSegment.new()
	segment.name = "Segment6"
	root.add_child(segment)
	await process_frame
	if move_model:
		segment.get_node(^"BridgePostModel").position.z += 1.0
	if move_box:
		segment.get_node(^"BridgePost").position.z += 1.0
	await DressingBatcher.merge_segment_geometry([segment])
	var lines := PackedStringArray()
	_sign_tree(segment, segment, lines)
	segment.free()
	await process_frame
	return "\n".join(lines)


func _sign_tree(segment: Node, node: Node, lines: PackedStringArray) -> void:
	var auto_names := RegEx.create_from_string("@(\\w+)@\\d+")  # instance counters change from build to build
	var parts: Array[String] = [auto_names.sub(str(segment.get_path_to(node)), "@$1@", true), node.get_class()]
	var file: String = node.scene_file_path
	if file.ends_with(".glb") or file.ends_with(".gltf"):
		var basis_x: Vector3 = (node as Node3D).transform.basis.x
		parts.append("scene=%s at(%.4f %.4f) yaw=%.4f" % [file.get_file(), (node as Node3D).position.x,
			(node as Node3D).position.z, atan2(-basis_x.z, basis_x.x)])
		lines.append(" | ".join(parts))
		return  # what is inside a .glb is art
	if node is Node3D:
		parts.append(str((node as Node3D).transform))
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if String(node.name).begins_with("MergedGeometry"):
			parts.append(_merged_mesh(mesh_node.mesh))
		elif mesh_node.mesh != null:
			parts.append("%s %s" % [mesh_node.mesh.get_class(), mesh_node.mesh.get_aabb()])
	lines.append(" | ".join(parts))
	for child: Node in node.get_children():
		_sign_tree(segment, child, lines)


## Same rule as test_route_golden.gd's _merged_mesh(): only the surfaces with a code-built material.
func _merged_mesh(mesh: Mesh) -> String:
	var code_materials: Array = RouteSegment._materials.values()
	var text: String = "merged"
	for surface: int in range(mesh.get_surface_count()):
		if code_materials.has(mesh.surface_get_material(surface)):
			var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var total := Vector3.ZERO
			for vertex: Vector3 in vertices:
				total += vertex
			text += " [verts=%d sum=%s]" % [vertices.size(), total]
	return text


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
