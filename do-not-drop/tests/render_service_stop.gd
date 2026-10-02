extends SceneTree
## Run without --headless (revisor-visual), one PNG per view and mode under
## user:// (render_service_<mode>_<view>.png), or under the folder in the
## RENDER_OUT environment variable:
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_service_stop.gd
## A ServiceStopSegment (N-110, models from N-110.1) lit like the level
## (level_base.tscn's Sun and WorldEnvironment), twice: on the delivery
## route's terrain (the station's parts conformed to it, a few pines around
## for scale) and as Endless lays it (the segment's own ground box). Views:
## the approach as the driver sees it, pulled into the lay-by, at the
## counter on foot, the back of the kiosk and a wide one from above.

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const PINE: String = "res://assets/models/environment/sm_env_tree_pine.tscn"

var _world: Node3D
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
	for mode: String in ["delivery", "endless"]:
		await _build(mode == "delivery")
		await _view(mode, "approach", Vector3(-2.5, 2.4, 6.0), Vector3(9.0, 3.0, -60.0))
		await _view(mode, "lay_by", Vector3(8.6, 2.4, -46.0), Vector3(16.0, 1.6, -70.0))
		await _view(mode, "counter", Vector3(15.2, 1.7, -66.5), Vector3(19.6, 1.3, -71.2))
		await _view(mode, "back", Vector3(31.0, 3.0, -58.0), Vector3(21.0, 1.0, -66.0))
		await _view(mode, "wide", Vector3(-10.0, 16.0, -30.0), Vector3(16.0, 1.0, -70.0))
		_world.queue_free()
		await process_frame
	quit(0)


func _build(on_terrain: bool) -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_take_game_light()
	var segment := ServiceStopSegment.new()
	segment.continuous_terrain = on_terrain
	if on_terrain:
		var terrain: Node3D = RouteTerrain.new()
		_world.add_child(terrain)
		terrain.add_span(Vector3(0, 0, 60), Vector3(0, 0, -170), true, 6.0)
		_world.add_child(segment)
		terrain.build()
		terrain.conform_geometry(segment)
		var pine := load(PINE) as PackedScene
		for spot: Vector3 in [Vector3(30.0, 0.0, -50.0), Vector3(34.0, 0.0, -78.0), Vector3(28.0, 0.0, -95.0),
				Vector3(-14.0, 0.0, -60.0), Vector3(22.0, 0.0, -30.0)]:
			var tree := pine.instantiate() as Node3D
			_world.add_child(tree)
			spot.y = float(terrain.call(&"height_at", spot))
			tree.position = spot
	else:
		_world.add_child(segment)
	var sky := RouteSky.new()
	sky.name = "RouteSky"
	_world.add_child(sky)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_world.add_child(_camera)
	_camera.current = true
	await process_frame


func _view(mode: String, view_name: String, from: Vector3, to: Vector3) -> void:
	_camera.position = from
	_camera.look_at(to)
	for _i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "%srender_service_%s_%s.png" % [_out, mode, view_name]
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))


func _take_game_light() -> void:
	var level_scene: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	var sun := level_scene.get_node(^"Sun") as DirectionalLight3D
	var environment := level_scene.get_node(^"WorldEnvironment") as WorldEnvironment
	level_scene.remove_child(sun)
	level_scene.remove_child(environment)
	level_scene.free()
	_world.add_child(environment)
	_world.add_child(sun)
	WorldMood.forced_label = "soleado_dia_verano"
