extends SceneTree
## S-311.100 final studio turntables. Run with a rendering display:
## Godot --path do-not-drop --rendering-method gl_compatibility \
##   --script res://tests/render_gel_final_turntables.gd

const OUTPUT: String = "res://../art/gel_character/review"
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")
const CELL_SIZE := Vector2i(220, 180)
const ANGLES: Array[float] = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
const PRESET_ROWS: Array[Dictionary] = [
	{&"id": &"delgada", &"label": "Delgada"},
	{&"id": &"flaca", &"label": "Flaca"},
	{&"id": &"rellena", &"label": "Rellena"},
	{&"id": &"petisa", &"label": "Petisa"},
	{&"id": &"cabezona", &"label": "Cabezona"},
	{&"id": &"larguirucha", &"label": "Larguirucha"},
]
const COLOR_SHEETS: Array[Dictionary] = [
	{&"id": &"mint", &"label": "Menta", &"color": Color("83e2ba")},
	{&"id": &"amber", &"label": "Ámbar", &"color": Color("f4c562")},
	{&"id": &"coral", &"label": "Coral", &"color": Color("f47e6d")},
	{&"id": &"sky", &"label": "Cielo", &"color": Color("6db3d6")},
	{&"id": &"lilac", &"label": "Lila", &"color": Color("c9a0e0")},
	{&"id": &"cobalt", &"label": "Cobalto", &"color": Color("5f7fd0")},
]

var _gel: Node3D
var _animation: AnimationPlayer
var _shaper := GelBodyShaper.new()
var _output_path: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Final gel turntables need a rendering display; omit --headless")
		quit(2)
		return
	root.size = CELL_SIZE
	root.msaa_3d = Viewport.MSAA_4X
	_output_path = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(_output_path)
	if not _build_stage():
		quit(1)
		return
	var files: Array[String] = []
	for color_entry: Dictionary in COLOR_SHEETS:
		var file_name := "s311_100_turntable_%s.png" % String(color_entry.id)
		if not await _render_color_sheet(color_entry, _output_path.path_join(file_name)):
			quit(1)
			return
		files.append(file_name)
	if not _write_manifest(files):
		quit(1)
		return
	print("PASS: S-311.100 six-preset turntables in six colors at %s" % _output_path)
	quit(0)


func _build_stage() -> bool:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("111827")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("dce8ff")
	world.environment.ambient_light_energy = 0.38
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(world)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(5.0, 5.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("2a3546")
	floor_material.roughness = 0.86
	floor.material_override = floor_material
	stage.add_child(floor)
	_add_light(stage, Vector3(-42.0, -32.0, -8.0), Color("fff1d6"), 1.12, true)
	_add_light(stage, Vector3(-18.0, 145.0, 12.0), Color("80b7ff"), 0.68, false)
	_gel = GEL_SCENE.instantiate() as Node3D
	stage.add_child(_gel)
	PlayerAppearance.set_gel_material(_gel, false)
	PlayerAppearance.enable_shadows(_gel)
	_animation = PlayerAppearance.find_animation_player(_gel)
	if _animation == null or not _shaper.setup(_gel):
		push_error("Cannot prepare the gel body for final turntables")
		return false
	_animation.play(&"Idle")
	_animation.speed_scale = 0.0
	_animation.seek(0.75, true)
	_animation.advance(0.0)
	var camera := Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 37.0
	camera.position = Vector3(2.45, 1.34, -4.0)
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.91, 0.0))
	camera.make_current()
	return true


func _add_light(
	stage: Node3D,
	rotation: Vector3,
	color: Color,
	energy: float,
	shadow: bool
) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rotation
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadow
	stage.add_child(light)


func _render_color_sheet(color_entry: Dictionary, path: String) -> bool:
	var sheet := Image.create_empty(
		CELL_SIZE.x * ANGLES.size(), CELL_SIZE.y * PRESET_ROWS.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("111827"))
	PlayerAppearance.set_gel_look(_gel, color_entry.color, 0.90, 1.02)
	for row: int in PRESET_ROWS.size():
		var proportions: GelBodyProportions = Presets.load_preset(PRESET_ROWS[row].id)
		if proportions == null:
			push_error("Cannot load final preset %s" % PRESET_ROWS[row].id)
			return false
		_shaper.apply(proportions)
		for column: int in ANGLES.size():
			_gel.rotation.y = deg_to_rad(-ANGLES[column])
			var frame: Image = await _capture()
			sheet.blit_rect(
				frame,
				Rect2i(Vector2i.ZERO, CELL_SIZE),
				Vector2i(column * CELL_SIZE.x, row * CELL_SIZE.y)
			)
	_gel.rotation.y = 0.0
	var error: Error = sheet.save_png(path)
	if error != OK:
		push_error("Cannot save %s (got %d)" % [path, error])
		return false
	print("Saved ", path)
	return true


func _capture() -> Image:
	for _frame: int in range(2):
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _write_manifest(files: Array[String]) -> bool:
	var manifest := {
		&"task": "S-311.100",
		&"source": "Godot LOD0 runtime character",
		&"default_character_changed": false,
		&"cell_size": [CELL_SIZE.x, CELL_SIZE.y],
		&"sheet_size": [CELL_SIZE.x * ANGLES.size(), CELL_SIZE.y * PRESET_ROWS.size()],
		&"preset_row_order": PRESET_ROWS.map(
			func(entry: Dictionary) -> String: return String(entry.label)),
		&"turntable_angles_degrees": ANGLES,
		&"colors": COLOR_SHEETS.map(func(entry: Dictionary) -> Dictionary:
			return {&"id": String(entry.id), &"label": String(entry.label),
				&"html": (entry.color as Color).to_html(false)}),
		&"turntable_files": files,
		&"editor_video": "s311_100_editor_sliders.avi",
		&"editor_preview": "s311_100_editor_preview.png",
		&"animation_reel": "s311_100_animation_reel.avi",
		&"animation_reel_preview": "s311_100_animation_reel_preview.png",
		&"video_resolution": [1280, 720],
		&"video_fps": 24,
		&"reel_categories": {
			&"base": ["Idle", "Walk", "Run", "Jump"],
			&"funny": ["Point", "ShakeLikeDog", "BlowBubble", "BallBounce"],
			&"dances": [
				"SimpleStep", "Robot", "Disco", "FloorWorm", "VictoryDance", "Conga",
			],
			&"deaths": ["Pancake", "MeltAndReturn", "Defeat", "SplitAndJoin"],
		},
	}
	var file := FileAccess.open(_output_path.path_join("s311_100_manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write the final studio manifest")
		return false
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	return true
