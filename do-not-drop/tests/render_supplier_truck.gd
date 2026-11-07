extends SceneTree
## Run without --headless (revisor-visual), PNGs under user:// (render_supplier_truck_<view>.png), or
## under the folder in the RENDER_OUT environment variable:
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_supplier_truck.gd
## The supplier's truck model (D-0601, sm_vehicle_supplier_truck.glb in SupplierTruckView) at the Modo Empresa
## shed, on its own calendar and clock: reversing to the dock, parked with the shutter down, half way up and
## rolled up over the twelve pallets of the bed, seen from the shed's dock and from the yard.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
## Pallets of the bed: full, so the top layer shows how much room the rolled shutter leaves.
const PALLETS: int = 12
const PALLET_UNITS: int = 24

var _camera: Camera3D
var _out: String = "user://"
var _minute: Array[float] = [0.0]


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
	var truck: SupplierTruckView = level.get(&"supplier_truck") as SupplierTruckView
	if truck == null:
		push_error("render_supplier_truck: no supplier truck in the company root")
		quit(1)
		return
	_stage_truck(truck)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	level.add_child(_camera)
	_camera.current = true
	var parked: Vector3 = truck.origin + _on_floor(SupplierTruck.parked_rect(0).get_center())
	var rear: Vector3 = truck.origin + _on_floor(SupplierTruckView.rear_of(0))
	var from_dock: Vector3 = rear + Vector3(0.0, 1.7, -6.0)
	var yard: Vector3 = parked + Vector3(9.0, 2.2, 6.0)
	var arrival: float = float(SupplierSchedule.arrival_minute())
	var door: Vector3 = rear + Vector3(0.0, 1.6, 0.0)
	await _view("reversing", arrival - 0.8, parked + Vector3(-11.0, 3.0, 13.0), parked + Vector3(0.0, 1.0, 4.0))
	await _view("rear_shut", arrival, from_dock, door)
	await _view("rear_half", arrival + SupplierTruckView.REAR_DOOR_ROLL_MIN * 0.5, from_dock, door)
	await _view("rear_open", arrival + 30.0, from_dock, door)
	await _view("yard_front", arrival + 30.0, yard, parked + Vector3(0.0, 1.4, 0.0))
	await _view("yard_rear", arrival + 30.0, parked + Vector3(8.0, 2.0, -4.5), parked + Vector3(0.0, 1.6, 1.0))
	await _view("side", arrival + 30.0, parked + Vector3(-10.0, 1.6, 0.0), parked + Vector3(0.0, 1.5, 0.0))
	quit(0)


func _on_floor(at: Vector2) -> Vector3:
	return Vector3(at.x, 0.0, at.y)


## The view follows this script's clock and calendar, with a full bed of its own.
func _stage_truck(truck: SupplierTruckView) -> void:
	var schedule := SupplierSchedule.new()
	schedule.place(CompanyTuning.STARTING_DAY - 1, [{"product": &"hen", "qty": PALLET_UNITS}])
	truck.schedule = schedule
	truck.minute_now = func() -> float: return _minute[0]
	truck.company = null
	var book := PalletJack.new()
	var fresh: Array[Dictionary] = []
	for i: int in PALLETS:
		fresh.append(Pallet.make(StringName("render_%d" % i), &"hen" if i % 2 == 0 else &"sourdough", PALLET_UNITS))
	book.load_bed(fresh)
	truck.pallets = book
	truck.refresh_bed()


func _view(view_name: String, minute: float, from: Vector3, to: Vector3) -> void:
	_minute[0] = minute
	_camera.position = from
	_camera.look_at(to)
	for _i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "%srender_supplier_truck_%s.png" % [_out, view_name]
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
