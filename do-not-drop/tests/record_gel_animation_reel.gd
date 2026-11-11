extends SceneTree
## S-311.100 animation reel. Run with MovieWriter and a rendering display:
## Godot --path do-not-drop --rendering-method gl_compatibility --fixed-fps 24 \
##   --write-movie ../art/gel_character/review/s311_100_animation_reel.avi \
##   --script res://tests/record_gel_animation_reel.gd

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")
const PREVIEW_PATH: String = "res://../art/gel_character/review/s311_100_animation_reel_preview.png"
const FPS: int = 24
const CLIP_FRAMES: int = 34
const CATEGORIES: Array[Dictionary] = [
	{
		&"label": "BASE", &"preset": &"delgada", &"color": Color("83e2ba"),
		&"clips": [&"Idle", &"Walk", &"Run", &"Jump"],
	},
	{
		&"label": "GRACIOSAS", &"preset": &"rellena", &"color": Color("f4c562"),
		&"clips": [&"Point", &"ShakeLikeDog", &"BlowBubble", &"BallBounce"],
	},
	{
		&"label": "BAILES", &"preset": &"larguirucha", &"color": Color("6db3d6"),
		&"clips": [&"SimpleStep", &"Robot", &"Disco", &"FloorWorm", &"VictoryDance", &"Conga"],
	},
	{
		&"label": "MUERTES", &"preset": &"petisa", &"color": Color("f47e6d"),
		&"clips": [&"Pancake", &"MeltAndReturn", &"Defeat", &"SplitAndJoin"],
	},
]

var _gel: Node3D
var _animation: AnimationPlayer
var _shaper := GelBodyShaper.new()
var _category_label: Label
var _clip_label: Label
var _preview_saved: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel animation reel needs a rendering display; omit --headless")
		quit(2)
		return
	root.size = Vector2i(960, 540)
	root.msaa_3d = Viewport.MSAA_4X
	if not _build_stage():
		quit(1)
		return
	_build_labels()
	await _hold(18)
	for category: Dictionary in CATEGORIES:
		if not await _play_category(category):
			quit(1)
			return
	if not _preview_saved:
		push_error("Cannot save the animation reel preview")
		quit(1)
		return
	_category_label.text = "S-311 · PERSONAJE GELATINOSO"
	_clip_label.text = "Reel final"
	_animation.play(&"Idle")
	_animation.speed_scale = 1.0
	await _hold(FPS)
	print("PASS: S-311.100 animation reel completed")
	quit(0)


func _build_stage() -> bool:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("101723")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d8e7ff")
	world.environment.ambient_light_energy = 0.34
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(world)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(7.0, 7.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("293649")
	floor_material.roughness = 0.86
	floor.material_override = floor_material
	stage.add_child(floor)
	_add_light(stage, Vector3(-38.0, -30.0, -8.0), Color("fff0d8"), 1.18, true)
	_add_light(stage, Vector3(-16.0, 150.0, 9.0), Color("7db5ff"), 0.75, false)
	_gel = GEL_SCENE.instantiate() as Node3D
	stage.add_child(_gel)
	PlayerAppearance.set_gel_material(_gel, false)
	PlayerAppearance.enable_shadows(_gel)
	_animation = PlayerAppearance.find_animation_player(_gel)
	if _animation == null or not _shaper.setup(_gel):
		push_error("Cannot prepare the gel body for the final animation reel")
		return false
	var camera := Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 35.0
	camera.position = Vector3(2.55, 1.42, -4.25)
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.87, 0.0))
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


func _build_labels() -> void:
	var band := ColorRect.new()
	band.color = Color(0.035, 0.055, 0.085, 0.86)
	band.position = Vector2(0.0, 0.0)
	band.size = Vector2(960.0, 82.0)
	root.add_child(band)
	_category_label = Label.new()
	_category_label.position = Vector2(28.0, 12.0)
	_category_label.add_theme_font_size_override(&"font_size", 26)
	_category_label.add_theme_color_override(&"font_color", Color("8fd8ff"))
	root.add_child(_category_label)
	_clip_label = Label.new()
	_clip_label.position = Vector2(28.0, 44.0)
	_clip_label.add_theme_font_size_override(&"font_size", 18)
	_clip_label.add_theme_color_override(&"font_color", Color.WHITE)
	root.add_child(_clip_label)


func _play_category(category: Dictionary) -> bool:
	_category_label.text = String(category.label)
	_clip_label.text = ""
	var proportions: GelBodyProportions = Presets.load_preset(category.preset)
	if proportions == null:
		push_error("Cannot load reel preset %s" % category.preset)
		return false
	_shaper.apply(proportions)
	PlayerAppearance.set_gel_look(_gel, category.color, 0.91, 1.03)
	await _hold(12)
	for clip: StringName in category.clips:
		if not _animation.has_animation(clip):
			push_error("Animation reel is missing %s" % clip)
			return false
		_clip_label.text = String(clip)
		var duration: float = _animation.get_animation(clip).length
		var screen_seconds: float = float(CLIP_FRAMES) / float(FPS)
		_animation.play(clip)
		_animation.speed_scale = duration / screen_seconds
		_animation.seek(0.0, true)
		for frame: int in range(CLIP_FRAMES):
			await process_frame
			if (
				not _preview_saved
				and String(category.label) == "BAILES"
				and clip == &"VictoryDance"
				and frame == CLIP_FRAMES / 2
			):
				_preview_saved = root.get_texture().get_image().save_png(PREVIEW_PATH) == OK
	return true


func _hold(frames: int) -> void:
	for _frame: int in range(frames):
		await process_frame
