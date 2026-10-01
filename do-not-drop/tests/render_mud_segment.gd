extends SceneTree
## Run without --headless (revisor-visual), one PNG per view under user://
## (render_mud_<view>.png):
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_mud_segment.gd
## A MudSegment (mud_segment.gd, N-108) on the game's terrain, lit like the
## level (level_base.tscn's Sun and WorldEnvironment): the approach as the
## driver sees it (the warning board on the right), the pit, from above, the
## bogged truck (a grey box stands in for the van) with the pushing and strap
## spots and their progress board, and the comic crane arriving.

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"

var _world: Node3D
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	_world = Node3D.new()
	root.add_child(_world)
	_take_game_light()
	var terrain: Node3D = RouteTerrain.new()
	_world.add_child(terrain)
	terrain.add_span(Vector3(0, 0, 100), Vector3(0, 0, -160), true, 6.0)
	var mud := MudSegment.new()
	mud.continuous_terrain = true
	_world.add_child(mud)
	terrain.build()
	terrain.conform_geometry(mud)
	var sky := RouteSky.new()
	sky.name = "RouteSky"
	_world.add_child(sky)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_world.add_child(_camera)
	_camera.current = true
	mud.set_physics_process(false)
	await _view("approach", Vector3(-1.5, 2.4, 22.0), Vector3(4.0, 1.5, -8.0))
	await _view("pit", Vector3(0.0, 2.2, -8.0), Vector3(0.0, 0.0, -30.0))
	await _view("above", Vector3(14.0, 42.0, -14.0), Vector3(0.0, 0.0, -30.0))
	# A stand-in truck stuck in the pit, bogged.
	var truck := Node3D.new()
	truck.add_to_group(&"vehicle")
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 2.4, 7.0)
	body.mesh = box
	body.position.y = 1.2
	truck.add_child(body)
	_world.add_child(truck)
	truck.global_position = Vector3(0.0, 0.67, -24.0)
	truck.set_meta(&"tow_straps", 1)
	mud.set(&"strap_ready", true)
	mud.set(&"progress", 0.4)
	mud.set(&"crane_left", 31.0)
	mud.set(&"state", MudSegment.State.BOGGED)
	mud.call(&"_follow_spots")
	mud.call(&"_show_status")
	await _view("bogged", Vector3(6.0, 3.2, -10.0), Vector3(0.0, 1.2, -24.0))
	await _view("bogged_rear", Vector3(3.0, 2.2, -36.0), Vector3(0.0, 1.0, -28.0))
	# The crane on its way in, then parked ahead with its cable on.
	mud.set(&"state", MudSegment.State.CRANE_COMING)
	mud.call(&"_on_state_changed", MudSegment.State.BOGGED)
	mud.set(&"_crane_time", MudSegment.CRANE_ARRIVE_SECONDS)
	for _i: int in 6:
		await process_frame
	await _view("crane", Vector3(10.0, 3.5, -8.0), Vector3(0.0, 1.5, -36.0))
	mud.set(&"haul_method", &"crane")
	mud.set(&"state", MudSegment.State.HAULING)
	mud.call(&"_on_state_changed", MudSegment.State.CRANE_COMING)
	await _view("crane_cable", Vector3(8.0, 3.5, -14.0), Vector3(0.0, 1.5, -34.0))
	_world.queue_free()
	await process_frame
	quit(0)


func _view(view_name: String, from: Vector3, to: Vector3) -> void:
	_camera.position = from
	_camera.look_at(to)
	for _i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://render_mud_%s.png" % view_name
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
