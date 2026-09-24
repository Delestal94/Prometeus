extends SceneTree
## Run with a temporary empty Godot project and the GLB path after --.

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1, "Provide absolute GLB path")
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file(args[0], state)
	assert(result == OK, "GLB failed to load")
	var model := document.generate_scene(state)
	assert(model != null, "GLB produced no scene")
	root.add_child(model)
	await process_frame
	var nodes: Array[Node] = [model]
	var skeleton: Skeleton3D
	var animation_player: AnimationPlayer
	var skinned_meshes := 0
	var morphs: Array[String] = []
	var shirt: MeshInstance3D
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		for child in node.get_children():
			nodes.append(child)
		if node is Skeleton3D:
			skeleton = node
		if node is AnimationPlayer:
			animation_player = node
		if node is MeshInstance3D:
			if node.skin != null:
				skinned_meshes += 1
			for i in node.get_blend_shape_count():
				morphs.append(str(node.mesh.get_blend_shape_name(i)))
				shirt = node
	assert(skeleton != null, "No skeleton imported")
	assert(skinned_meshes == 16, "Skin lost during import")
	assert(skeleton.find_bone("pelvis") >= 0)
	assert(skeleton.find_bone("grip.L") >= 0)
	assert(skeleton.find_bone("grip.R") >= 0)
	assert(morphs.has("Respirar") and morphs.has("Barriga_blanda"))
	assert(animation_player != null and not animation_player.get_animation_list().is_empty())
	var animations := animation_player.get_animation_list()
	var clip := ""
	for candidate in animations:
		if candidate != "RESET":
			clip = candidate
			break
	assert(not clip.is_empty(), "No playable animation")
	animation_player.play(clip)
	animation_player.seek(0.73, true)
	animation_player.advance(0)
	var breathing := shirt.get_blend_shape_value(0)
	assert(breathing > 0.4, "Breathing animation did not survive export")
	var report := {"godot": Engine.get_version_info()["string"],
		"bones": skeleton.get_bone_count(), "skinned_meshes": skinned_meshes,
		"morphs": morphs, "animations": Array(animations), "breathing_at_0_73s": breathing}
	print("GODOT_IMPORT_PASS ", JSON.stringify(report))
	var file := FileAccess.open(args[0].get_base_dir().path_join("godot_validation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	quit(0)
