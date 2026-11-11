extends SceneTree
## Run without --headless (revisor-visual), PNGs under user:// (render_company_far_<view>.png), or under the
## folder in the RENDER_OUT environment variable:
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_company_far.gd
## What the company map looks like from afar, on the medium preset of the D-2012 budget (D-2012.1): from the
## player's spawn in the shed, three views out of the door and one toward the back; then, with the player moved
## out to the Avenida Este so the cells follow, a look ahead toward Centro and a look back at the shed. Each
## view also prints `RENDER_COMPANY_FAR view=<name> draw_calls=<n> objects=<n> cells=<loaded> impostors=<n>`,
## the table of the far cells in docs/rendimiento-pc.md.
## The company saves into a temp folder (user://render_company_far), never the game's slot.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const SAVE_DIR: String = "user://render_company_far"
const EYE: Vector3 = Vector3(0.0, 1.7, 2.6)
## Where the player goes for the last views: on the Avenida Este, three cells from the shed.
const AVENUE: Vector3 = Vector3(640.0, 1.0, 6.0)
## Frames to wait for the anchors and the streamer's quarter-second look at them.
const SETTLE_FRAMES: int = 40
const MAX_SETTLE_FRAMES: int = 1200

var _camera: Camera3D
var _out: String = "user://"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	var out: String = OS.get_environment("RENDER_OUT")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		_out = out.trim_suffix("/") + "/"
	root.size = Vector2i(1280, 720)
	WorldQuality.apply(self, WorldQuality.Level.MEDIUM)
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = SAVE_DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	_camera = Camera3D.new()
	_camera.far = 4000.0
	var player_camera: Camera3D = level.player.get_node_or_null(^"Head/Camera3D") as Camera3D
	if player_camera != null:
		_camera.cull_mask = player_camera.cull_mask
	level.add_child(_camera)
	_camera.make_current()
	await _settle(level)
	await _view(level, "door_front", EYE, Vector3(0.0, 0.0, 500.0))
	await _view(level, "door_left", EYE, Vector3(-400.0, 0.0, 500.0))
	await _view(level, "door_right", EYE, Vector3(400.0, 0.0, 500.0))
	await _view(level, "inside_back", EYE, Vector3(0.0, 1.0, -4.0))
	level.player.global_position = AVENUE
	await _settle(level)
	await _view(level, "avenue_ahead", AVENUE + Vector3.UP * 2.0, AVENUE + Vector3(400.0, 0.0, 0.0))
	await _view(level, "avenue_back", AVENUE + Vector3.UP * 2.0, Vector3.ZERO)
	root.remove_child(level)
	level.free()
	_clean_save_dir()
	root.get_node(^"/root/CompanyState").call(&"reset")
	quit(0)


## Lets the anchors reach the streamer and everything the cells owe arrive.
func _settle(level: CompanyRoot) -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame
	var left: int = MAX_SETTLE_FRAMES
	while level.cells.is_busy() and left > 0:
		left -= 1
		await process_frame


func _view(level: CompanyRoot, view_name: String, from: Vector3, to: Vector3) -> void:
	_camera.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)
	for _i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "%srender_company_far_%s.png" % [_out, view_name]
	root.get_texture().get_image().save_png(path)
	print("RENDER_COMPANY_FAR view=%s draw_calls=%d objects=%d cells=%d impostors=%d" % [
		view_name,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		level.cells.loaded_cells().size(),
		level.cells.impostor_count()])


func _clean_save_dir() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR))
