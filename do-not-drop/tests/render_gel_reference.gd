extends SceneTree
## Run without --headless:
## Godot --path do-not-drop --rendering-method gl_compatibility
## --script res://tests/render_gel_reference.gd
##
## S-311.38 reference render. The constants are shared with the contract test
## and reproduce the measured framing of referencia_frente.jpg.

const OUTPUT_PATH: String = "res://../art/gel_character/review_bloque_e/s311_38_godot_reference.png"
const ITERATIONS_PATH: String = "res://../art/gel_character/reference_rounds.json"
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const WIDTH: int = 832
const HEIGHT: int = 1248
const CAMERA_DISTANCE_M: float = 4.0
const CAMERA_FOV_DEGREES: float = 30.9
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.813, 0.0)
const PRESET_ID: StringName = &"delgada"
const POSE_DEGREES: Dictionary = {
	&"upper_arm": 100.0,
	&"forearm": -25.0,
	&"hand": 20.0,
}

var _viewport: Viewport
var _gel_mesh: MeshInstance3D
var _output_path: String = OUTPUT_PATH
var _round: int = 1
var _round_values: Dictionary = {}
var _round_material: Dictionary = {}
var _camera_target_y: float = CAMERA_TARGET.y
var _camera_target_x: float = CAMERA_TARGET.x
var _camera_distance: float = CAMERA_DISTANCE_M
var _camera_fov: float = CAMERA_FOV_DEGREES
var _pose_degrees: Dictionary = POSE_DEGREES.duplicate()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel reference capture needs a rendering display; omit --headless")
		quit(2)
		return
	if not _load_round_options():
		quit(2)
		return
	var output_absolute: String = ProjectSettings.globalize_path(_output_path)
	DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
	_build_stage()
	for _frame: int in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	if image.get_size() != Vector2i(WIDTH, HEIGHT):
		push_error("Reference capture has the wrong size: %s" % image.get_size())
		quit(1)
		return
	var error: Error = image.save_png(output_absolute)
	if error != OK:
		push_error("Cannot save %s (got %d)" % [output_absolute, error])
		quit(1)
		return
	var mask_error: Error = await _save_silhouette_mask(output_absolute.get_basename() + "_mask.png")
	if mask_error != OK:
		push_error("Cannot save the silhouette mask (got %d)" % mask_error)
		quit(1)
		return
	print("PASS: S-311.38 Delgada reference render round %d at %s" % [_round, output_absolute])
	quit(0)


func _save_silhouette_mask(path: String) -> Error:
	var mask_material := StandardMaterial3D.new()
	mask_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask_material.albedo_color = Color.BLACK
	mask_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_gel_mesh.material_override = mask_material
	for _frame: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image().save_png(path)


func _load_round_options() -> bool:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for argument: String in arguments:
		if argument.begins_with("--round="):
			_round = maxi(1, int(argument.get_slice("=", 1)))
		elif argument.begins_with("--output="):
			_output_path = argument.get_slice("=", 1)
		else:
			push_error("Unknown reference-render option: %s" % argument)
			return false
	if _round <= 1:
		return true
	var file := FileAccess.open(ITERATIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot open %s" % ITERATIONS_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Reference-round configuration is not a dictionary")
		return false
	var round_key := str(_round)
	if not (parsed as Dictionary).has(round_key):
		push_error("Reference-round configuration has no round %d" % _round)
		return false
	var configuration: Dictionary = (parsed as Dictionary)[round_key]
	_round_values = configuration.get("proportions", {})
	_round_material = configuration.get("material", {})
	_camera_target_y = float(configuration.get("camera_target_y", CAMERA_TARGET.y))
	_camera_target_x = float(configuration.get("camera_target_x", CAMERA_TARGET.x))
	_camera_distance = float(configuration.get("camera_distance_m", CAMERA_DISTANCE_M))
	_camera_fov = float(configuration.get("camera_fov_degrees", CAMERA_FOV_DEGREES))
	for pose_name: String in configuration.get("pose_degrees", {}):
		_pose_degrees[StringName(pose_name)] = float(configuration["pose_degrees"][pose_name])
	if _output_path == OUTPUT_PATH:
		_output_path = "res://../art/gel_character/review_bloque_e/round_%02d/godot_render.png" % _round
	return true


func _build_stage() -> void:
	root.size = Vector2i(WIDTH, HEIGHT)
	root.msaa_3d = Viewport.MSAA_4X
	_viewport = root
	var stage := Node3D.new()
	root.add_child(stage)

	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.WHITE
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("f5f2ff")
	world.environment.ambient_light_energy = 0.18
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(world)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8.0, 8.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("f7f7f7")
	floor_material.roughness = 0.92
	floor.material_override = floor_material
	stage.add_child(floor)

	var key := DirectionalLight3D.new()
	key.name = "SoftKeyUpperLeft"
	key.rotation_degrees = Vector3(-38.0, -28.0, -10.0)
	key.light_color = Color("fff8ee")
	key.light_energy = 0.68
	key.shadow_enabled = true
	key.shadow_opacity = 0.45
	key.directional_shadow_max_distance = 8.0
	key.set("light_angular_distance", 8.0)
	stage.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "SoftFillRight"
	fill.rotation_degrees = Vector3(-18.0, 150.0, 8.0)
	fill.light_color = Color("e8edff")
	fill.light_energy = 0.12
	stage.add_child(fill)

	var gel: Node3D = GEL_SCENE.instantiate() as Node3D
	stage.add_child(gel)
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(gel)
	if animation != null:
		animation.stop()
	var shaper := GelBodyShaper.new()
	var preset: GelBodyProportions = GelProportionPresets.load_preset(PRESET_ID)
	if not _round_values.is_empty():
		preset.apply_dictionary(_round_values)
	if preset == null or not shaper.setup(gel) or not shaper.apply(preset):
		push_error("Cannot apply the Delgada preset to the reference body")
		quit(1)
		return
	PlayerAppearance.set_gel_material(gel, false)
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(gel)
	_gel_mesh = mesh
	var studio_material := mesh.material_override.duplicate(true) as ShaderMaterial
	studio_material.set_shader_parameter(&"refraction_mix", 0.45)
	studio_material.set_shader_parameter(&"center_opacity", 0.42)
	studio_material.set_shader_parameter(&"edge_opacity", 0.86)
	studio_material.set_shader_parameter(&"absorption_coefficient", 3.0)
	studio_material.set_shader_parameter(&"absorption_opacity", 0.50)
	for parameter_name: String in _round_material:
		if parameter_name.begins_with("gel_"):
			continue
		studio_material.set_shader_parameter(StringName(parameter_name), _round_material[parameter_name])
	mesh.material_override = studio_material
	var color := Color.from_string(String(_round_material.get("gel_color", "8f8bc9")), Color("8f8bc9"))
	var opacity: float = float(_round_material.get("gel_opacity", 1.0))
	var brightness: float = float(_round_material.get("gel_brightness", 0.80))
	print("REFERENCE_LOOK color=%s opacity=%.3f brightness=%.3f" % [color, opacity, brightness])
	PlayerAppearance.set_gel_look(gel, color, opacity, brightness)
	PlayerAppearance.enable_shadows(gel)
	_apply_reference_pose(PlayerAppearance.find_skeleton(gel))

	var camera := Camera3D.new()
	camera.name = "ReferenceFrontCamera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = _camera_fov
	camera.near = 0.1
	camera.far = 12.0
	stage.add_child(camera)
	var camera_target := Vector3(_camera_target_x, _camera_target_y, 0.0)
	camera.position = Vector3(_camera_target_x, _camera_target_y, -_camera_distance)
	camera.look_at(camera_target)
	camera.make_current()


func _apply_reference_pose(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		push_error("Gel reference body has no skeleton")
		return
	skeleton.reset_bone_poses()
	for bone_name: StringName in _pose_degrees:
		for side: String in ["L", "R"]:
			var bone: int = skeleton.find_bone(String(bone_name) + "." + side)
			if bone < 0:
				continue
			var global_rest: Basis = skeleton.get_bone_global_rest(bone).basis
			var local_rest: Basis = skeleton.get_bone_rest(bone).basis
			var axis: Vector3 = skeleton.global_basis.inverse() * Vector3.BACK
			var side_sign: float = 1.0 if side == "L" else -1.0
			var rotation := Basis(
				axis.normalized(),
				deg_to_rad(float(_pose_degrees[bone_name])) * side_sign
			)
			skeleton.set_bone_pose_rotation(
				bone,
				(local_rest * global_rest.inverse() * rotation * global_rest).get_rotation_quaternion()
			)
		skeleton.force_update_all_bone_transforms()
