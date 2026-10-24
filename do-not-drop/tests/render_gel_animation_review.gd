extends SceneTree
## S-311.83 studio proof. Run without --headless:
## Godot --path do-not-drop --rendering-method gl_compatibility \
##   --script res://tests/render_gel_animation_review.gd

const OUTPUT: String = "res://../art/gel_character/review/"
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const CELL_SIZE := Vector2i(320, 240)
const MOTION_FRACTIONS: Array[float] = [0.18, 0.50, 0.82]
const TURN_ANGLES: Array[float] = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
const CLIPS: Array[StringName] = [
	&"Idle", &"Walk", &"Stroll", &"Run", &"Jump", &"PickUpPackage", &"PickUpHigh",
	&"Sit", &"TurnInPlace", &"CarryWalk", &"ThrowPackage", &"DropPackage", &"Drive",
	&"EnterTruck", &"ExitTruck", &"RingDoorbell", &"Stumble", &"Slip", &"Pushed",
	&"BoxHit", &"Scared", &"Dizzy", &"ShakeOffWater",
]
const PRESETS: Array[Dictionary] = [
	{&"id": &"delgada", &"label": "Delgada"},
	{&"id": &"flaca", &"label": "Flaca"},
	{&"id": &"extremo_seguro", &"label": "Extremo seguro"},
]
const EXTREME_VALUES: Dictionary = {
	&"total_height": 0.90,
	&"leg_length": 0.85,
	&"arm_length": 1.15,
	&"torso_length": 0.85,
	&"neck_length": 1.10,
	&"head_size": 1.15,
	&"general_thickness": -0.55,
	&"belly": 0.60,
	&"chest": 0.60,
	&"shoulders": 0.55,
	&"hips": 0.60,
	&"arm_thickness": 0.55,
	&"leg_thickness": 0.55,
	&"hand_size": 0.70,
	&"foot_size": 0.70,
	&"head_shape": -0.50,
	&"neck_thickness": 0.55,
}

var _gel: Node3D
var _animation: AnimationPlayer
var _shaper := GelBodyShaper.new()
var _output_absolute: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel animation review needs a rendering display; omit --headless")
		quit(2)
		return
	_output_absolute = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(_output_absolute)
	if not _build_stage():
		quit(1)
		return
	var files: Array[String] = []
	files.append(await _render_turntable())
	for clip: StringName in CLIPS:
		files.append(await _render_motion_sheet(clip))
	if not _write_manifest(files):
		quit(1)
		return
	print("PASS: S-311.83 studio review rendered %d files in %s" % [files.size(), _output_absolute])
	quit(0)


func _build_stage() -> bool:
	root.size = CELL_SIZE
	root.msaa_3d = Viewport.MSAA_4X
	var stage := Node3D.new()
	root.add_child(stage)

	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("edeff3")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("dfe8ff")
	world.environment.ambient_light_energy = 0.42
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(world)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8.0, 8.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("d7dbe2")
	floor_material.roughness = 0.9
	floor.material_override = floor_material
	stage.add_child(floor)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -32.0, -8.0)
	key.light_color = Color("fff3df")
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.shadow_opacity = 0.55
	key.set("light_angular_distance", 7.0)
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18.0, 145.0, 12.0)
	rim.light_color = Color("9ebcff")
	rim.light_energy = 0.65
	stage.add_child(rim)

	_gel = GEL_SCENE.instantiate() as Node3D
	stage.add_child(_gel)
	_animation = PlayerAppearance.find_animation_player(_gel)
	if _animation == null or not _shaper.setup(_gel):
		push_error("Cannot prepare the gel body for the animation review")
		return false
	PlayerAppearance.set_gel_material(_gel, true)
	PlayerAppearance.set_gel_look(_gel, Color("65bde4"), 1.0, 0.88)
	PlayerAppearance.enable_shadows(_gel)

	var camera := Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 12.0
	camera.position = Vector3(2.65, 1.42, -4.1)
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.92, 0.0))
	camera.make_current()
	return true


func _render_turntable() -> String:
	var sheet := Image.create_empty(
		CELL_SIZE.x * TURN_ANGLES.size(),
		CELL_SIZE.y * PRESETS.size(),
		false,
		Image.FORMAT_RGBA8
	)
	sheet.fill(Color("252a34"))
	_animation.play(&"Idle")
	_animation.speed_scale = 0.0
	_animation.seek(0.0, true)
	_animation.advance(0.0)
	for row: int in PRESETS.size():
		_apply_preset(PRESETS[row][&"id"])
		for column: int in TURN_ANGLES.size():
			_gel.rotation.y = deg_to_rad(-TURN_ANGLES[column])
			var image: Image = await _capture()
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i(column * CELL_SIZE.x, row * CELL_SIZE.y))
	_gel.rotation.y = 0.0
	var filename := "s311_83_turntable.png"
	if sheet.save_png(_output_absolute.path_join(filename)) != OK:
		push_error("Cannot save the S-311.83 turntable")
	return filename


func _render_motion_sheet(clip: StringName) -> String:
	if not _animation.has_animation(clip):
		push_error("Review clip is missing: %s" % clip)
		return ""
	var sheet := Image.create_empty(
		CELL_SIZE.x * MOTION_FRACTIONS.size(),
		CELL_SIZE.y * PRESETS.size(),
		false,
		Image.FORMAT_RGBA8
	)
	sheet.fill(Color("252a34"))
	var duration: float = _animation.get_animation(clip).length
	for row: int in PRESETS.size():
		_apply_preset(PRESETS[row][&"id"])
		for column: int in MOTION_FRACTIONS.size():
			_animation.play(clip)
			_animation.speed_scale = 0.0
			_animation.seek(duration * MOTION_FRACTIONS[column], true)
			_animation.advance(0.0)
			var image: Image = await _capture()
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i(column * CELL_SIZE.x, row * CELL_SIZE.y))
	var filename := "s311_83_motion_%s.png" % String(clip).to_snake_case()
	if sheet.save_png(_output_absolute.path_join(filename)) != OK:
		push_error("Cannot save the S-311.83 motion sheet for %s" % clip)
	return filename


func _apply_preset(preset_id: StringName) -> void:
	var proportions: GelBodyProportions
	if preset_id == &"extremo_seguro":
		proportions = GelBodyProportions.new()
		proportions.apply_dictionary(EXTREME_VALUES)
	else:
		proportions = GelProportionPresets.load_preset(preset_id)
	if proportions == null:
		push_error("Cannot load review preset %s" % preset_id)
		return
	_shaper.apply(proportions)


func _capture() -> Image:
	for _frame: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _write_manifest(files: Array[String]) -> bool:
	if files.any(func(path: String) -> bool: return path.is_empty()):
		return false
	var animation_rows: Array[Dictionary] = []
	for clip: StringName in CLIPS:
		animation_rows.append({
			&"clip": String(clip),
			&"duration_seconds": snappedf(_animation.get_animation(clip).length, 0.000001),
			&"sample_fractions": MOTION_FRACTIONS,
			&"file": "s311_83_motion_%s.png" % String(clip).to_snake_case(),
		})
	var manifest := {
		&"task": "S-311.83",
		&"cell_size": [CELL_SIZE.x, CELL_SIZE.y],
		&"row_order": PRESETS.map(func(entry: Dictionary) -> String: return entry[&"label"]),
		&"extreme_values": EXTREME_VALUES,
		&"turntable_angles_degrees": TURN_ANGLES,
		&"animations": animation_rows,
		&"files": files,
	}
	var file := FileAccess.open(_output_absolute.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write the S-311.83 review manifest")
		return false
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	return true
