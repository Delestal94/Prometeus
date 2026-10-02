extends SceneTree
## Run: Godot --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy
## --script res://tests/render_gel_body_lods.gd -- --out=<absolute-directory>
## Opaque diagnostic silhouettes for S-311 B: three LODs, three views, base,
## a limb-thinning proxy for future Flaca, and 22 single morph extremes.
## Fixed 60-degree vertical FOV, 1920x1080, camera 15m from body centre.
## This is not material approval E or the final bone-length Flaca preset C.

const BASE: String = "res://assets/models/characters/gel/gel_body_lod%d.glb"
var _output: String = "user://gel_body_lods"
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _manifest: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel silhouette capture needs a display")
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_output)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	root.add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color.BLACK
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	_stage.add_child(environment)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.1
	_camera.far = 30.0
	_stage.add_child(_camera)
	_camera.make_current()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	var failed: bool = false
	for lod: int in range(3):
		var scene: PackedScene = load(BASE % lod) as PackedScene
		if scene == null:
			push_error("Cannot load gel LOD%d" % lod)
			failed = true
			continue
		var model: Node3D = scene.instantiate() as Node3D
		_stage.add_child(model)
		var animation: AnimationPlayer = _find(model, "AnimationPlayer") as AnimationPlayer
		if animation != null and animation.has_animation("Idle"):
			animation.play("Idle")
			animation.advance(0.0)
			animation.pause()
		var body: MeshInstance3D = _find(model, "MeshInstance3D") as MeshInstance3D
		if body == null:
			push_error("Gel LOD%d has no mesh" % lod)
			model.free()
			failed = true
			continue
		body.material_override = material
		var states: Array[Dictionary] = [
			{"name": "delgada", "weights": {}},
			{"name": "flaca_shape_proxy", "weights": {"general_thickness": -1.0}},
		]
		for index: int in body.mesh.get_blend_shape_count():
			var name: String = String(body.mesh.get_blend_shape_name(index))
			states.append({"name": name + "_minus", "weights": {name: -1.0}})
			states.append({"name": name + "_plus", "weights": {name: 1.0}})
		for state: Dictionary in states:
			for index: int in body.mesh.get_blend_shape_count():
				var name: String = String(body.mesh.get_blend_shape_name(index))
				body.set_blend_shape_value(index, float(state.weights.get(name, 0.0)))
			for view: String in ["front", "profile", "three_quarter"]:
				var direction: Vector3 = Vector3(0, 0, -1)
				if view == "profile":
					direction = Vector3(-1, 0, 0)
				elif view == "three_quarter":
					direction = Vector3(-1, 0, -1).normalized()
				var centre := Vector3(0, 0.87, 0)
				_camera.position = centre + direction * 15.0
				_camera.look_at(centre)
				for _frame: int in range(3):
					await process_frame
					await RenderingServer.frame_post_draw
				var filename: String = "lod%d_%s_%s.png" % [lod, state.name, view]
				var error: Error = _viewport.get_texture().get_image().save_png(_output.path_join(filename))
				if error != OK:
					push_error("Cannot save %s (got %d)" % [filename, error])
					failed = true
				_manifest.append({"file": filename, "lod": lod, "state": state.name,
					"weights": state.weights, "view": view})
				if lod == 0 and state.name == "delgada":
					_camera.position = centre + direction * 2.0
					_camera.look_at(centre)
					for _frame: int in range(3):
						await process_frame
						await RenderingServer.frame_post_draw
					var close_name: String = "close_delgada_%s.png" % view
					var close_error: Error = _viewport.get_texture().get_image().save_png(
						_output.path_join(close_name))
					if close_error != OK:
						push_error("Cannot save %s (got %d)" % [close_name, close_error])
						failed = true
		if lod == 0:
			for index: int in body.mesh.get_blend_shape_count():
				body.set_blend_shape_value(index, 0.0)
			var skeleton: Skeleton3D = _find(model, "Skeleton3D") as Skeleton3D
			if skeleton != null:
				if animation != null:
					animation.stop()
				skeleton.reset_bone_poses()
				# Diagnostic reference pose only, not a new clip or runtime shaper.
				for side: String in ["L", "R"]:
					var bone: int = skeleton.find_bone("upper_arm." + side)
					if bone >= 0:
						var rest: Basis = skeleton.get_bone_global_rest(bone).basis
						var axis: Vector3 = skeleton.global_basis.inverse() * Vector3.BACK
						var sign_angle: float = 1.0 if side == "L" else -1.0
						var rotation := Basis(axis.normalized(), deg_to_rad(75.0) * sign_angle)
						var local_rest: Basis = skeleton.get_bone_rest(bone).basis
						skeleton.set_bone_pose_rotation(bone,
							(local_rest * rest.inverse() * rotation * rest).get_rotation_quaternion())
				_camera.position = Vector3(0, 0.87, -2.0)
				_camera.look_at(Vector3(0, 0.87, 0))
				for _frame: int in range(3):
					await process_frame
					await RenderingServer.frame_post_draw
				var reference_error: Error = _viewport.get_texture().get_image().save_png(
					_output.path_join("reference_pose_front.png"))
				if reference_error != OK:
					push_error("Cannot save reference diagnostic (got %d)" % reference_error)
					failed = true
		model.free()
	var report: Dictionary = {
		"distance_m": 15.0, "fov_vertical_deg": 60.0, "resolution": [1920, 1080],
		"renderer": "gl_compatibility", "material": "opaque_unshaded_diagnostic",
		"flaca_note": "shape proxy only; bone-length preset awaits C", "captures": _manifest,
	}
	var file: FileAccess = FileAccess.open(_output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write silhouette capture manifest")
		failed = true
	else:
		file.store_string(JSON.stringify(report, "\t"))
	if not failed:
		print("PASS: %d diagnostic silhouettes at %s" % [_manifest.size(), _output])
	quit(1 if failed else 0)


func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child: Node in node.get_children():
		var result: Node = _find(child, type)
		if result != null:
			return result
	return null
