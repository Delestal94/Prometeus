extends SceneTree
## Run without --headless (revisor-visual), PNGs under user:// (render_company_shed_<view>.png), or
## under the folder in the RENDER_OUT environment variable:
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_company_shed.gd
## The Modo Empresa root (company_root.tscn: the default CompanyShed, the game's sun and sky) seen
## from a player's eye (1.7 m) from the dock and from the exit, a low view of the floor joints and
## a high diagonal one, to judge the concrete floor and plaster walls (D-0911). The last view opens
## the stock list (StockBoard, D-0612.b) over the shed with a few products seeded on shelves, at the
## dock and in a hand, and one order short of hens, so the "missing" mark shows.
## It takes the Modo Empresa dev flags from its own command line (D-0238, CompanyDevFlags), e.g.
##   ... --script res://tests/render_company_shed.gd -- --company-day=5 --money=9000 --district=suburbio

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
	var player: Node = level.get_node_or_null(^"World/Player")
	if player == null:
		player = level.get(&"player")
	if player is Node3D:
		(player as Node3D).visible = false
	_camera = Camera3D.new()
	_camera.fov = 75.0
	level.add_child(_camera)
	_camera.current = true
	await _view("eye_from_dock", Vector3(0.0, 1.7, 3.6), Vector3(0.0, 1.2, -4.0))
	await _view("eye_from_exit", Vector3(0.0, 1.7, -3.6), Vector3(0.0, 1.0, 4.0))
	await _view("eye_corner", Vector3(-5.5, 1.7, 3.5), Vector3(3.0, 0.8, -2.0))
	await _view("floor_low", Vector3(-3.0, 0.9, 2.0), Vector3(3.0, 0.0, -2.0))
	await _view("high_diagonal", Vector3(-8.0, 9.0, 9.0), Vector3(0.0, 0.0, 0.0))
	await _view("top_down", Vector3(0.0, 14.0, 0.01), Vector3(0.0, 0.0, 0.0))
	await _stock_list(level)
	quit(0)


func _stock_list(level: Node) -> void:
	var board: StockBoard = level.get(&"stock_board") as StockBoard
	if board == null or board.net == null or board.net.inventory == null:
		push_error("render_company_shed: no stock board in the company root")
		return
	var inv: Inventory = board.net.inventory
	inv.receive(&"hen", 2, &"shelf:a")
	inv.receive(&"sourdough", 6, &"shelf:b")
	inv.receive(&"milk_canister", 4, &"dock")
	inv.receive(&"antique_lamp", 1, &"hands:1")
	var book: OrderBook = board.book_of.call() as OrderBook if board.book_of.is_valid() else null
	if book != null:
		var items: Array = [{"product": &"hen", "qty": 11}]
		book.add(Order.make(&"render_o1", "Ana", &"centro", &"h1", items, 0, {}))
	board.open()
	await process_frame
	var sc: ScrollContainer = board.panel.get(&"_scroll")
	var fo: Control = root.gui_get_focus_owner()
	print("DBG scroll=", sc.scroll_vertical, " focus=", fo.name if fo else &"none", " order=", board.panel.products())
	await _view("stock_list", Vector3(0.0, 1.7, 3.6), Vector3(0.0, 1.2, -4.0))
	print("DBG after scroll=", sc.scroll_vertical, " focus=", root.gui_get_focus_owner().name if root.gui_get_focus_owner() else &"none")
	board.close()


func _view(view_name: String, from: Vector3, to: Vector3) -> void:
	_camera.position = from
	_camera.look_at(to)
	for _i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "%srender_company_shed_%s.png" % [_out, view_name]
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
