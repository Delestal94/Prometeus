extends SceneTree
## Reproducible S-311.69 review: all eight crew colours on the real gel body,
## placed on a 20 m arc in daylight and at night. The filtered captures use
## the same full-severity Machado matrices as test_player_colors.gd.
##
## Run with a rendering display:
## Godot --path do-not-drop --resolution 1280x720 \
##   --script res://tests/render_gel_legibility.gd
## Pass `-- --output=<directory>` to write CI artifacts outside the checkout.

const DEFAULT_OUTPUT: String = "res://../art/gel_character/review_bloque_h/s311_69_legibility"
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const DISTANCE_METERS: float = 20.0
const CAPTURE_SIZE := Vector2i(1280, 720)
const TEAM_COLORS: Array[Color] = [
	Color("83e2ba"), Color("f4c562"), Color("f47e6d"), Color("6db3d6"),
	Color("c9a0e0"), Color("e8eaf0"), Color("5f7fd0"), Color("4f9a8f"),
]
const VIEWS: PackedStringArray = ["normal", "deuteranopia", "protanopia"]
const MACHADO: Dictionary = {
	"deuteranopia": [
		Vector3(0.367322, 0.860646, -0.227968),
		Vector3(0.280085, 0.672501, 0.047413),
		Vector3(-0.011820, 0.042940, 0.968881),
	],
	"protanopia": [
		Vector3(0.152286, 1.052583, -0.204868),
		Vector3(0.114503, 0.786281, 0.099216),
		Vector3(-0.003882, -0.048116, 1.051998),
	],
}

var _stage: Node3D
var _environment: Environment
var _sun: DirectionalLight3D
var _night_lights: Array[OmniLight3D] = []
var _caption: Label
var _output: String = DEFAULT_OUTPUT
var _captures: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel legibility capture needs a rendering display; omit --headless")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	root.size = CAPTURE_SIZE
	var output_path := _global_output_path()
	DirAccess.make_dir_recursive_absolute(output_path)
	_build_stage()
	for lighting: String in ["day", "night"]:
		_set_lighting(lighting)
		for _frame: int in range(16):
			await process_frame
		var original := await _capture()
		for view: String in VIEWS:
			var image := original.duplicate()
			if view != "normal":
				_apply_filter(image, view)
			var key := "%s_%s" % [lighting, view]
			var path := output_path.path_join("s311_69_%s.png" % key)
			if image.save_png(path) != OK:
				push_error("Cannot save %s" % path)
				quit(1)
				return
			_captures[key] = image
			print("Saved ", path)
	_save_contact_sheet(output_path)
	print("PASS: S-311.69 eight gel players captured at %.1f m in six views" % DISTANCE_METERS)
	quit(0)


func _build_stage() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	current_scene = _stage

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	_stage.add_child(world_environment)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(42.0, 48.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, -0.02, -19.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("52605e")
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	_stage.add_child(ground)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	_sun.shadow_enabled = true
	_stage.add_child(_sun)
	_add_night_light(Vector3(-8.0, 5.0, -15.0), Color("a9d5ff"))
	_add_night_light(Vector3(8.0, 4.0, -18.0), Color("ffd09c"))

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.08, 0.0)
	camera.fov = 43.0
	camera.far = 80.0
	_stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.82, -DISTANCE_METERS), Vector3.UP)
	camera.make_current()

	var x_positions: Array[float] = [-6.3, -4.5, -2.7, -0.9, 0.9, 2.7, 4.5, 6.3]
	for index: int in TEAM_COLORS.size():
		var x := x_positions[index]
		var z := -sqrt(DISTANCE_METERS * DISTANCE_METERS - x * x)
		_spawn_gel(index, Vector3(x, 0.0, z), camera.global_position)
	_add_overlay()


func _spawn_gel(index: int, at: Vector3, facing: Vector3) -> void:
	var gel := GEL_SCENE.instantiate() as Node3D
	gel.name = "Crew_%02d" % (index + 1)
	_stage.add_child(gel)
	gel.global_position = at
	gel.look_at(facing, Vector3.UP, true)
	PlayerAppearance.set_gel_material(gel, false)
	PlayerAppearance.set_gel_look(gel, Color("79d7e9"), 0.9, 1.08)
	PlayerAppearance.set_gel_team_accent(gel, TEAM_COLORS[index])
	PlayerAppearance.enable_shadows(gel)
	var animation := PlayerAppearance.find_animation_player(gel)
	if animation != null and animation.has_animation(&"Idle"):
		animation.play(&"Idle")
		animation.advance(float(index) * 0.09)
		animation.pause()


func _add_night_light(at: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = 28.0
	light.shadow_enabled = true
	_stage.add_child(light)
	_night_lights.append(light)


func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	_stage.add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(36.0, 28.0)
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", Color.WHITE)
	_caption.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_caption)


func _set_lighting(lighting: String) -> void:
	var night := lighting == "night"
	_environment.background_color = Color("07101f") if night else Color("8fb9c3")
	_environment.ambient_light_color = Color("7188aa") if night else Color("d9edf0")
	_environment.ambient_light_energy = 0.22 if night else 0.38
	_sun.light_color = Color("8eabdd") if night else Color("fff1d4")
	_sun.light_energy = 0.12 if night else 0.78
	for light: OmniLight3D in _night_lights:
		light.light_energy = 2.4 if night else 0.0
	_caption.text = "S-311.69  |  8 teammates  |  %.1f m  |  %s" % [
		DISTANCE_METERS,
		"NIGHT" if night else "DAYLIGHT",
	]
	for gel: Node in _stage.find_children("Crew_*", "Node3D", false, false):
		var mesh := PlayerAppearance.find_mesh_instance(gel)
		if mesh != null:
			mesh.set_instance_shader_parameter(&"gel_weather", Vector4(0.0, 0.37, 2.0 if night else 0.0, 0.0))


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _apply_filter(image: Image, view: String) -> void:
	var matrix: Array = MACHADO[view]
	for y: int in image.get_height():
		for x: int in image.get_width():
			var source := image.get_pixel(x, y)
			var linear := source.srgb_to_linear()
			var filtered := Color(
				clampf((matrix[0] as Vector3).dot(Vector3(linear.r, linear.g, linear.b)), 0.0, 1.0),
				clampf((matrix[1] as Vector3).dot(Vector3(linear.r, linear.g, linear.b)), 0.0, 1.0),
				clampf((matrix[2] as Vector3).dot(Vector3(linear.r, linear.g, linear.b)), 0.0, 1.0),
				source.a
			).linear_to_srgb()
			filtered.a = source.a
			image.set_pixel(x, y, filtered)


func _save_contact_sheet(output_path: String) -> void:
	var sheet := Image.create_empty(1920, 720, false, Image.FORMAT_RGBA8)
	var index := 0
	for lighting: String in ["day", "night"]:
		for view: String in VIEWS:
			var frame := (_captures["%s_%s" % [lighting, view]] as Image).duplicate()
			frame.resize(640, 360, Image.INTERPOLATE_LANCZOS)
			var destination := Vector2i((index % 3) * 640, (index / 3) * 360)
			sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), destination)
			index += 1
	var path := output_path.path_join("s311_69_contact_sheet.png")
	if sheet.save_png(path) != OK:
		push_error("Cannot save %s" % path)


func _global_output_path() -> String:
	if _output.begins_with("res://") or _output.begins_with("user://"):
		return ProjectSettings.globalize_path(_output)
	return _output if _output.is_absolute_path() else ProjectSettings.globalize_path(_output)
