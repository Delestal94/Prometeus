extends SceneTree
## Run without --headless (revisor-visual), PNGs under user:// (render_shed_exterior_<view>.png), or
## under the folder in the RENDER_OUT environment variable:
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_shed_exterior.gd
## The outside of the shed (D-0936, ShedExterior) at each of the four stages in the Modo Empresa root
## (company_root.tscn: its sun, sky and ground): from the yard at a player's eye, the sign up close and
## a high diagonal over the yard, to judge the sign models, the yard's marks and the lamps.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"

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
	var level: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	for _i: int in 20:
		await process_frame
	var player: Node = level.get(&"player")
	if player is Node3D:
		# Off, not only hidden: its interaction holds on to a piece the redraws below free.
		(player as Node3D).visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
	_camera = Camera3D.new()
	_camera.fov = 75.0
	level.add_child(_camera)
	_camera.current = true
	var shed: CompanyShed = level.get(&"shed") as CompanyShed
	var state: Node = root.get_node(^"CompanyState")
	var stock := Inventory.new()
	for stage: int in ShedExteriorPlan.variant_count():
		state.warehouse_stage = stage
		shed.rebuild(state, stock)
		for _i: int in 4:
			await process_frame
		var floor_m: Vector2 = WarehouseStages.floor_size_m(stage)
		var front: float = floor_m.y * 0.5 + CompanyShed.WALL_THICKNESS
		var yard: float = ShedExteriorPlan.yard_depth(stage)
		var sign_m: Vector2 = ShedExteriorPlan.sign_size(stage, floor_m.x)
		var top: float = CompanyShed.WALL_HEIGHT + sign_m.y * 0.5
		var eye: Vector3 = Vector3(0.0, 1.7, front + yard + 3.0)
		await _view("stage%d_yard_eye" % stage, eye, Vector3(0.0, top * 0.7, front))
		var close: Vector3 = Vector3(sign_m.x * 0.3, top + 0.4, front + sign_m.x * 0.6)
		await _view("stage%d_sign" % stage, close, Vector3(0.0, top, front))
		var high: Vector3 = Vector3(-floor_m.x * 0.5, 8.0, front + yard + 6.0)
		await _view("stage%d_high" % stage, high, Vector3(0.0, 0.0, front + yard * 0.5))
	quit(0)


func _view(view_name: String, from: Vector3, to: Vector3) -> void:
	_camera.position = from
	_camera.look_at(to)
	for _i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "%srender_shed_exterior_%s.png" % [_out, view_name]
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
