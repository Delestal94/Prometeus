extends SceneTree
## S-311.99 final integration review. Run with a rendering display:
## Godot --path do-not-drop --rendering-method gl_compatibility \
##   --script res://tests/render_gel_character.gd
##
## Saves front and three-quarter views of two real player instances under
## art/gel_character/review/. The full six-preset presentation is S-311.100.

const OUTPUT: String = "res://../art/gel_character/review"
const PLAYER_SCENE := preload("res://scenes/gameplay/player/player.tscn")
const Proportions := preload(
	"res://scripts/gameplay/player/gel/gel_body_proportions.gd"
)
const LOOKS: Array[Dictionary] = [
	{
		&"face": &"happy", &"skin": &"night_neon", &"hair": &"quiff",
		&"eyebrows": &"thick", &"moustache": &"handlebar",
		&"costume": &"astronaut", &"accessory": &"glasses",
		&"proportions": {
			&"total_height": 1.10, &"head_size": 0.91, &"general_thickness": -0.25,
		},
	},
	{
		&"face": &"angry", &"skin": &"layered_gummy", &"hair": &"braid",
		&"eyebrows": &"arched", &"moustache": &"pencil",
		&"costume": &"pirate", &"accessory": &"scarf",
		&"proportions": {
			&"total_height": 0.94, &"head_size": 1.10, &"general_thickness": 0.32,
		},
	},
]

var _players: Array[Player] = []
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel character review needs a rendering display; omit --headless")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_4X
	_build_stage()
	for index: int in LOOKS.size():
		_players.append(await _build_player(index, LOOKS[index]))
	var output_path: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path)
	await _save_view(output_path.path_join("s311_99_complete_looks_front.png"), 0.0)
	await _save_view(output_path.path_join("s311_99_complete_looks_three_quarter.png"), -28.0)
	print("PASS: S-311.99 complete-look captures at %s" % output_path)
	quit(0)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("111827")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d9e7ff")
	environment.environment.ambient_light_energy = 0.38
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(environment)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(7.0, 5.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("263244")
	floor_material.roughness = 0.84
	floor.material_override = floor_material
	root.add_child(floor)
	_add_light(Vector3(-42.0, -32.0, -8.0), Color("fff1d6"), 1.12, true)
	_add_light(Vector3(-18.0, 145.0, 12.0), Color("80b7ff"), 0.72, false)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.34, -4.8)
	_camera.fov = 38.0
	root.add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.92, 0.0))
	_camera.make_current()


func _add_light(rotation: Vector3, color: Color, energy: float, shadow: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rotation
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadow
	root.add_child(light)


func _build_player(index: int, look: Dictionary) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.set_multiplayer_authority(20 + index)
	player.position = Vector3(-0.78 if index == 0 else 0.78, 0.0, 0.0)
	root.add_child(player)
	await process_frame
	var state: Node = player.get_node(^"GelProportions")
	state.set(&"packet", Proportions.packet_from_dictionary(look.proportions))
	state.set(&"skin_id", look.skin)
	state.set(&"hair_id", look.hair)
	state.set(&"eyebrows_id", look.eyebrows)
	state.set(&"moustache_id", look.moustache)
	state.set(&"costume_id", look.costume)
	state.set(&"accessory_id", look.accessory)
	player.get_node(^"GelFaceReactions").set(&"base_face_id", look.face)
	for _frame: int in range(8):
		await process_frame
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player


func _save_view(path: String, yaw_degrees: float) -> void:
	for index: int in _players.size():
		_players[index].rotation_degrees.y = yaw_degrees if index == 0 else -yaw_degrees
	for _frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Cannot save %s (got %d)" % [path, error])
		quit(1)
