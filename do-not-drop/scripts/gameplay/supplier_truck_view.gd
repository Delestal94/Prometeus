class_name SupplierTruckView
extends Node3D
## Draws the supplier's truck of the Modo Empresa (expansion D-0601): a grey-box truck that
## SupplierTruck puts at the pose of the game clock's minute.
##
## It only draws. Nothing is sent and nothing is decided here: every peer reads the same clock
## (GameClock, the host's anchor) and the same calendar, so the truck is at the same place on all of
## them with no RPC and no random roll. Hidden whenever there is no truck (another day, before it
## drives in, once it is out), and then it costs a dictionary lookup per frame.
##
## Sits in the world next to the shed (a sibling, because CompanyShed.rebuild() frees its children),
## at `origin`, the shed's centre. Grey-box stand-in made of primitives with the depot's palette; the
## final model is a pending art task (docs/expansion-distritos/arte-pendiente/D-0601.md).
##
## Its bed is open at the rear and draws the pallets the book says are on it (PalletJack.AT_BED, D-0605.b),
## pallet by pallet in slots the rear fills first, so what the jack takes leaves a gap and what stays is
## still there when the truck leaves: the pallets are part of the truck's node and move with it.

const CAB_COLOR: Color = Color(0.78, 0.45, 0.16)
const CARGO_COLOR: Color = Color(0.74, 0.74, 0.76)
const CHASSIS_COLOR: Color = Color(0.22, 0.22, 0.24)
const GLASS_COLOR: Color = Color(0.30, 0.42, 0.52)
const WHEEL_RADIUS: float = 0.5
const WHEEL_WIDTH: float = 0.3
const CAB_LENGTH: float = 1.7
const CARGO_FLOOR: float = 0.7
## The bed's walls and floor are this thick; the rear is open.
const BED_WALL: float = 0.08
## Pallets lie across the bed two by two with their long side along it, in rows of this pitch (m) from the
## rear, and are stacked in two layers: BED_SLOTS of them are drawn, the rest wait on the book.
const BED_ROW_PITCH: float = 1.3
const BED_COLUMNS: int = 2
const BED_ROWS: int = 3
const BED_SLOTS: int = 12

## Today's calendar; null draws nothing.
var schedule: SupplierSchedule
## Where the shed's centre is in the world (the shed's position).
var origin: Vector3 = Vector3.ZERO
## The company (CompanyState-shaped: `day` and `warehouse_stage`); null reads day 1, stage 0.
var company: Object
## Callable() -> float, the game minute (GameClock.minute_now()).
var minute_now: Callable = Callable()
## The book of pallets (CompanyNet.pallets.book): the ones on the bed are drawn there (refresh_bed()). Null draws none.
var pallets: PalletJack

var _body: Node3D
var _bed: Node3D
## What the bed was drawn from: the ids on it, in order.
var _bed_ids: Array[StringName] = []


func _init() -> void:
	name = "SupplierTruck"
	visible = false
	_body = _build_body()
	add_child(_body)
	_bed = Node3D.new()
	_bed.name = "Bed"
	add_child(_bed)


func _process(_delta: float) -> void:
	refresh()


## Puts the truck where the clock says. Public so a test or a screenshot can step it by hand.
func refresh() -> void:
	if schedule == null or not minute_now.is_valid():
		visible = false
		return
	var day: int = int(company.get("day")) if company != null else CompanyTuning.STARTING_DAY
	var stage: int = int(company.get("warehouse_stage")) if company != null else 0
	var pose: Dictionary = SupplierTruck.pose(schedule, day, float(minute_now.call()), stage)
	visible = bool(pose["present"])
	if not visible:
		return
	var at: Vector2 = pose["position"]
	position = origin + Vector3(at.x, 0.0, at.y)
	rotation.y = float(pose["yaw"])


## Whether the truck is parked and waiting now: the jack may take pallets off its bed (the day's calendar, as
## the pose reads it).
func bed_open() -> bool:
	if schedule == null or not minute_now.is_valid():
		return false
	var day: int = int(company.get("day")) if company != null else CompanyTuning.STARTING_DAY
	return schedule.truck_state(day, floori(float(minute_now.call()))) == SupplierSchedule.STATE_AT_DOCK


## The middle of the bed's open rear when the truck is parked, in the shed's frame (x, z in metres).
static func rear_of(stage: int) -> Vector2:
	var parked: Rect2 = SupplierTruck.parked_rect(stage)
	return Vector2(parked.get_center().x, parked.position.y)


## Where slot `rank` of the bed is, in the truck's own frame (the truck faces -Z, its rear is +Z): the
## middle of the pallet's footprint on the bed's floor or, in the second layer, on the pallets under it.
static func bed_slot(rank: int) -> Vector3:
	var per_layer: int = BED_COLUMNS * BED_ROWS
	var layer: int = floori(float(rank) / float(per_layer))
	var row: int = floori(float(rank % per_layer) / float(BED_COLUMNS))
	var column: int = rank % BED_COLUMNS
	var rear_z: float = CompanyTuning.SUPPLIER_TRUCK_SIZE_M.z * 0.5
	return Vector3((float(column) - (BED_COLUMNS - 1) * 0.5) * (CompanyTuning.PALLET_FOOTPRINT_M.y + 0.2),
		CARGO_FLOOR + BED_WALL + float(layer) * (PalletBox.height() + 0.05),
		rear_z - CompanyTuning.PALLET_FOOTPRINT_M.x * 0.5 - 0.1 - float(row) * BED_ROW_PITCH)


## Redraws the pallets of the bed from the book: nothing changes when the same ones are still there.
func refresh_bed() -> void:
	var on_bed: Array[StringName] = []
	if pallets != null:
		on_bed = pallets.ids_at(PalletJack.AT_BED)
	if on_bed == _bed_ids:
		return
	_bed_ids = on_bed
	for child: Node in _bed.get_children():
		_bed.remove_child(child)
		child.queue_free()
	for rank: int in mini(on_bed.size(), BED_SLOTS):
		var node: Node3D = PalletBox.build(pallets.places[on_bed[rank]]["pallet"], true)
		node.position = bed_slot(rank)
		_bed.add_child(node)


## The ids drawn on the bed, in slot order (the rear first).
func bed_ids() -> Array[StringName]:
	return _bed_ids.duplicate()


## The truck facing -Z (Godot's forward), centred on its footprint, wheels on the floor.
func _build_body() -> Node3D:
	var size: Vector3 = CompanyTuning.SUPPLIER_TRUCK_SIZE_M
	var root := Node3D.new()
	root.name = "Body"
	var cargo_len: float = size.z - CAB_LENGTH
	var front: float = -size.z * 0.5
	_add_box(root, "Chassis", Vector3(size.x * 0.92, 0.3, size.z), Vector3(0.0, 0.55, 0.0), CHASSIS_COLOR)
	# The bed: floor, side walls, front wall and roof; the rear (+Z) is open so the pallets show.
	var bed_top: float = size.y - CARGO_FLOOR
	var bed_mid_z: float = front + CAB_LENGTH + cargo_len * 0.5
	_add_box(root, "CargoFloor", Vector3(size.x, BED_WALL, cargo_len),
		Vector3(0.0, CARGO_FLOOR + BED_WALL * 0.5, bed_mid_z), CARGO_COLOR)
	_add_box(root, "CargoRoof", Vector3(size.x, BED_WALL, cargo_len),
		Vector3(0.0, size.y - BED_WALL * 0.5, bed_mid_z), CARGO_COLOR)
	_add_box(root, "CargoFront", Vector3(size.x, bed_top, BED_WALL),
		Vector3(0.0, CARGO_FLOOR + bed_top * 0.5, front + CAB_LENGTH + BED_WALL * 0.5), CARGO_COLOR)
	for side: float in [-1.0, 1.0]:
		_add_box(root, "CargoWall", Vector3(BED_WALL, bed_top, cargo_len),
			Vector3(side * (size.x * 0.5 - BED_WALL * 0.5), CARGO_FLOOR + bed_top * 0.5, bed_mid_z), CARGO_COLOR)
	_add_box(root, "Cab", Vector3(size.x * 0.96, size.y * 0.62, CAB_LENGTH - 0.1),
		Vector3(0.0, CARGO_FLOOR + size.y * 0.31 - 0.1, front + (CAB_LENGTH - 0.1) * 0.5), CAB_COLOR)
	_add_box(root, "Windshield", Vector3(size.x * 0.8, size.y * 0.22, 0.06),
		Vector3(0.0, size.y * 0.62, front - 0.02), GLASS_COLOR)
	for wheel_z: float in [front + 1.0, size.z * 0.5 - 1.0, size.z * 0.5 - 2.4]:
		for side: float in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = WHEEL_RADIUS
			cylinder.bottom_radius = WHEEL_RADIUS
			cylinder.height = WHEEL_WIDTH
			cylinder.material = DepotKit.flat(Color(0.08, 0.08, 0.09))
			wheel.mesh = cylinder
			wheel.name = "Wheel"
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(side * (size.x * 0.5 - 0.1), WHEEL_RADIUS, wheel_z)
			root.add_child(wheel)
	return root


func _add_box(parent: Node3D, box_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = DepotKit.flat(color)
	instance.mesh = mesh
	instance.name = box_name
	instance.position = at
	parent.add_child(instance)
