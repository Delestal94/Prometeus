extends SceneTree
## Run (needs a GPU, not --headless):
##   Godot --path do-not-drop --script res://tests/render_depot.gd
## Saves review shots of the starting depot (depot.gd) to user://depot_*.png:
## the view a player spawns with, the order board, the dispatch shelves, the
## workshop, lockers and supplies counter, the stock aisle with the forklift,
## the facade from the road, and the door closed behind the truck.

## [name, camera position, look-at] in depot space.
const SHOTS := [
	["spawn_view", Vector3(0.0, 1.65, 17.4), Vector3(0.0, 1.5, 5.0)],
	["spawn_floor_arrows", Vector3(0.6, 6.0, 22.5), Vector3(0.6, 0.0, 15.0)],
	["spawn_turned_left", Vector3(0.0, 1.65, 17.4), Vector3(-8.0, 1.8, 18.5)],
	["spawn_turned_right", Vector3(0.0, 1.65, 17.4), Vector3(8.0, 1.8, 18.5)],
	["order_board", Vector3(-2.6, 1.7, 15.2), Vector3(-4.5, 1.8, 13.0)],
	["dispatch_shelves", Vector3(-4.2, 1.8, 14.0), Vector3(-8.5, 1.0, 21.0)],
	["aisle_between_shelves", Vector3(-8.5, 1.65, 13.2), Vector3(-8.5, 1.2, 24.0)],
	["workshop", Vector3(6.5, 1.8, 13.0), Vector3(13.0, 1.2, 6.0)],
	["lockers_and_break", Vector3(9.0, 1.7, 16.0), Vector3(14.5, 1.6, 20.0)],
	["supplies_counter", Vector3(10.8, 1.7, 20.2), Vector3(10.8, 1.3, 25.0)],
	["stock_aisle_forklift", Vector3(-11.2, 2.2, 24.0), Vector3(-12.2, 1.2, 4.0)],
	["back_of_depot", Vector3(2.0, 2.4, 20.0), Vector3(-2.0, 1.2, 30.5)],
	["overview", Vector3(12.0, 6.2, 2.0), Vector3(-4.0, 0.5, 20.0)],
	["facade", Vector3(6.0, 2.0, -13.0), Vector3(-1.0, 3.6, 0.0)],
]

var _camera: Camera3D
var _depot: Node3D
var _level: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = (load("res://scenes/gameplay/level_base.tscn") as PackedScene).instantiate()
	root.add_child(_level)
	current_scene = _level
	_depot = _level.get_node(^"World/Depot")
	for tick in range(90):
		await physics_frame
	# Hide the start card and the HUD: these shots are of the place.
	var hud: CanvasLayer = _level.get_node(^"HUD")
	hud.visible = false
	for node: Node in get_nodes_in_group(&"player"):
		(node as Node3D).visible = false
	_camera = Camera3D.new()
	_camera.fov = 72.0
	_camera.near = 0.05
	_level.add_child(_camera)
	for shot: Array in SHOTS:
		_camera.global_position = _depot.to_global(shot[1])
		_camera.look_at(_depot.to_global(shot[2]))
		await _save(shot[0])
	# The truck gone, the door rolled down behind it.
	var vehicle := _level.get(&"vehicle") as Node3D
	vehicle.global_position = _depot.to_global(Vector3(0.0, 0.9, -14.0))
	_depot.get(&"door").call(&"set_open", false, false)
	_camera.global_position = _depot.to_global(Vector3(4.0, 2.0, -16.0))
	_camera.look_at(_depot.to_global(Vector3(0.0, 2.8, 0.0)))
	await _save("door_closed")
	quit(0)


func _save(shot_name: String) -> void:
	_camera.make_current()
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := "user://depot_%s.png" % shot_name
	image.save_png(path)
	print("RENDER: ", ProjectSettings.globalize_path(path))
