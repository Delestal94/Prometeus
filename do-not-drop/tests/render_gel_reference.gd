extends SceneTree
## Run without --headless:
## Godot --path do-not-drop --rendering-method gl_compatibility
## --script res://tests/render_gel_reference.gd
##
## S-311.38 reference render. The constants are shared with the contract test
## and reproduce the measured framing of referencia_frente.jpg.

const OUTPUT_PATH: String = "res://../art/gel_character/review_bloque_e/s311_38_godot_reference.png"
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


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel reference capture needs a rendering display; omit --headless")
		quit(2)
		return
	var output_absolute: String = ProjectSettings.globalize_path(OUTPUT_PATH)
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
	print("PASS: S-311.38 Delgada reference render at %s" % output_absolute)
	quit(0)


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
	if preset == null or not shaper.setup(gel) or not shaper.apply(preset):
		push_error("Cannot apply the Delgada preset to the reference body")
		quit(1)
		return
	PlayerAppearance.set_gel_material(gel, false)
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(gel)
	var studio_material := mesh.material_override.duplicate(true) as ShaderMaterial
	studio_material.set_shader_parameter(&"refraction_mix", 0.45)
	studio_material.set_shader_parameter(&"center_opacity", 0.42)
	studio_material.set_shader_parameter(&"edge_opacity", 0.86)
	studio_material.set_shader_parameter(&"absorption_coefficient", 3.0)
	studio_material.set_shader_parameter(&"absorption_opacity", 0.50)
	mesh.material_override = studio_material
	PlayerAppearance.set_gel_look(gel, Color("8f8bc9"), 1.0, 0.80)
	PlayerAppearance.enable_shadows(gel)
	_apply_reference_pose(PlayerAppearance.find_skeleton(gel))

	var camera := Camera3D.new()
	camera.name = "ReferenceFrontCamera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = CAMERA_FOV_DEGREES
	camera.near = 0.1
	camera.far = 12.0
	stage.add_child(camera)
	camera.position = Vector3(0.0, CAMERA_TARGET.y, -CAMERA_DISTANCE_M)
	camera.look_at(CAMERA_TARGET)
	camera.make_current()


func _apply_reference_pose(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		push_error("Gel reference body has no skeleton")
		return
	skeleton.reset_bone_poses()
	for bone_name: StringName in POSE_DEGREES:
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
				deg_to_rad(float(POSE_DEGREES[bone_name])) * side_sign
			)
			skeleton.set_bone_pose_rotation(
				bone,
				(local_rest * global_rest.inverse() * rotation * global_rest).get_rotation_quaternion()
			)
		skeleton.force_update_all_bone_transforms()
