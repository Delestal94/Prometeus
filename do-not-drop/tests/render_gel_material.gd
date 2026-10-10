extends SceneTree
## Run without --headless, with the GL Compatibility renderer:
## Godot --path do-not-drop --rendering-method gl_compatibility
## --script res://tests/render_gel_material.gd
##
## Visual proof for block D. It renders the real LOD0 gel body with the shared
## runtime material from the front and at three quarters. A high-contrast grid
## behind the body makes S-311.28 screen-space refraction directly visible.

const OUTPUT: String = "res://../art/gel_character/review_bloque_d"
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const GEL_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")

var _camera: Camera3D
var _gel: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel material review needs a rendering display; omit --headless")
		quit(2)
		return
	root.size = Vector2i(960, 960)
	var output_path: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path)
	_build_stage()
	await _save(output_path.path_join("s311_28_refraction_front.png"))
	_gel.rotation.y = deg_to_rad(-32.0)
	await _save(output_path.path_join("s311_28_refraction_three_quarter.png"))
	print("PASS: gel refraction captures at ", output_path)
	quit(0)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("26333f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c7def1")
	environment.environment.ambient_light_energy = 0.42
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(environment)
	for setup: Array in [
		[Vector3(-34.0, -28.0, 0.0), Color("fff0d6"), 1.3],
		[Vector3(-18.0, 145.0, 0.0), Color("b8d9ff"), 0.65],
	]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setup[0]
		light.light_color = setup[1]
		light.light_energy = setup[2]
		root.add_child(light)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(4.0, 4.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("768493")
	floor_material.roughness = 0.82
	floor.material_override = floor_material
	root.add_child(floor)
	_build_refraction_backdrop()
	_gel = GEL_SCENE.instantiate() as Node3D
	root.add_child(_gel)
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(_gel)
	if mesh == null:
		push_error("Gel LOD0 has no mesh for material review")
		quit(1)
		return
	mesh.material_override = GEL_MATERIAL
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(_gel)
	if animation != null and animation.has_animation(&"Idle"):
		animation.play(&"Idle")
		animation.advance(0.0)
		animation.pause()
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.position = Vector3(0.0, 0.92, -3.15)
	_camera.look_at(Vector3(0.0, 0.86, 0.0))
	_camera.fov = 31.0
	_camera.make_current()


func _build_refraction_backdrop() -> void:
	_add_backdrop_box(Vector3(4.0, 3.0, 0.06), Vector3(0.0, 1.15, 0.86), Color("31516a"))
	for x: float in [-0.9, -0.45, 0.0, 0.45, 0.9]:
		_add_backdrop_box(Vector3(0.045, 2.65, 0.08), Vector3(x, 1.15, 0.79), Color("f2d6ad"))
	for y: float in [0.45, 0.9, 1.35, 1.8]:
		_add_backdrop_box(Vector3(3.5, 0.045, 0.08), Vector3(0.0, y, 0.78), Color("9dcbe0"))


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


func _save(path: String) -> void:
	for _frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Cannot save %s (got %d)" % [path, error])
		quit(1)
