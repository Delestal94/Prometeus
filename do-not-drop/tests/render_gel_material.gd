extends SceneTree
## Run without --headless, with the GL Compatibility renderer:
## Godot --path do-not-drop --rendering-method gl_compatibility
## --script res://tests/render_gel_material.gd
##
## Visual proof for block D. It renders the real LOD0 gel body with the shared
## runtime material through a full turn. S-311.33 verifies stable self-overlap,
## a soft translucent shadow on the floor and received directional shadows.
## Pass `-- --opaque` for the S-311.35 no-screen-read milky fallback.

const OUTPUT: String = "res://../art/gel_character/review_bloque_d"
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const GEL_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")
const GEL_OPAQUE_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body_opaque.tres")

var _camera: Camera3D
var _gel: Node3D
var _use_opaque: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel material review needs a rendering display; omit --headless")
		quit(2)
		return
	root.size = Vector2i(960, 960)
	_use_opaque = "--opaque" in OS.get_cmdline_user_args()
	var output_path: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path)
	_build_stage()
	var file_name := "s311_35_opaque_milky_turntable.png" if _use_opaque \
		else "s311_33_transparency_shadow_turntable.png"
	await _save_turntable(output_path.path_join(file_name))
	print("PASS: gel %s turntable at %s" % ["opaque milky" if _use_opaque else "transparency and shadow", output_path])
	quit(0)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("0b111a")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("71869d")
	environment.environment.ambient_light_energy = 0.2
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(environment)
	var light_setups: Array[Array] = [
		[Vector3(-48.0, 150.0, 0.0), Color("fff0d6"), 0.7],
		[Vector3(-18.0, 145.0, 0.0), Color("b8d9ff"), 0.25],
		[Vector3(10.0, 0.0, 0.0), Color("9fddff"), 1.4],
	]
	for index: int in light_setups.size():
		var setup: Array = light_setups[index]
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setup[0]
		light.light_color = setup[1]
		light.light_energy = setup[2]
		light.shadow_enabled = index == 0
		if light.shadow_enabled:
			light.shadow_opacity = 0.72
			light.directional_shadow_max_distance = 8.0
		root.add_child(light)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(4.0, 4.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("222c38")
	floor_material.roughness = 0.82
	floor.material_override = floor_material
	root.add_child(floor)
	_build_dark_studio_backdrop()
	_gel = GEL_SCENE.instantiate() as Node3D
	root.add_child(_gel)
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(_gel)
	if mesh == null:
		push_error("Gel LOD0 has no mesh for material review")
		quit(1)
		return
	mesh.material_override = GEL_OPAQUE_MATERIAL if _use_opaque else GEL_MATERIAL
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(_gel)
	if animation != null and animation.has_animation(&"Idle"):
		animation.play(&"Idle")
		animation.advance(0.0)
		animation.pause()
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.position = Vector3(0.0, 1.18, -3.65)
	_camera.look_at(Vector3(0.0, 0.74, 0.0))
	_camera.fov = 31.0
	_camera.make_current()


func _build_dark_studio_backdrop() -> void:
	_add_backdrop_box(Vector3(4.0, 3.0, 0.06), Vector3(0.0, 1.15, 0.86), Color("111a25"))
	_add_backdrop_box(Vector3(0.09, 2.55, 0.04), Vector3(-0.28, 1.18, 0.81), Color("aacbe6"))
	_add_backdrop_box(Vector3(0.09, 2.55, 0.04), Vector3(0.28, 1.18, 0.81), Color("d7b9a3"))
	_add_backdrop_box(Vector3(2.4, 0.07, 0.04), Vector3(0.0, 1.02, 0.80), Color("79b99d"))


func _add_backdrop_box(size: Vector3, position: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	instance.material_override = material
	root.add_child(instance)


func _save_turntable(path: String) -> void:
	var sheet := Image.create_empty(1920, 960, false, Image.FORMAT_RGBA8)
	for index: int in 8:
		_gel.rotation.y = deg_to_rad(float(index) * -45.0)
		var frame: Image = await _capture()
		frame.resize(480, 480, Image.INTERPOLATE_LANCZOS)
		var destination := Vector2i((index % 4) * 480, (index / 4) * 480)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), destination)
	var error: Error = sheet.save_png(path)
	if error != OK:
		push_error("Cannot save %s (got %d)" % [path, error])
		quit(1)


func _capture() -> Image:
	for _frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
