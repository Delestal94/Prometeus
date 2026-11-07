class_name SupplierTruckView
extends Node3D
## Draws the supplier's truck of the Modo Empresa (expansion D-0601): the box truck model that
## SupplierTruck puts at the pose of the game clock's minute.
##
## It only draws. Nothing is sent and nothing is decided here: every peer reads the same clock
## (GameClock, the host's anchor) and the same calendar, so the truck is at the same place on all of
## them with no RPC and no random roll. Hidden whenever there is no truck (another day, before it
## drives in, once it is out), and then it costs a dictionary lookup per frame.
##
## Sits in the world next to the shed (a sibling, because CompanyShed.rebuild() frees its children),
## at `origin`, the shed's centre. The model is sm_vehicle_supplier_truck.glb (assets/tools/
## build_street_props.py, group "supplier"); it has no collider, like the primitives it replaced.
##
## Its bed draws the pallets the book says are on it (PalletJack.AT_BED, D-0605.b), pallet by pallet in slots
## the rear fills first, so what the jack takes leaves a gap and what stays is still there when the truck
## leaves: the pallets are part of the truck's node and move with it. The rear is a roll-up shutter, shut on
## the road and rolled up while the truck waits at the dock (door_opening(), the same clock on every peer).

const MODEL: PackedScene = preload("res://assets/models/vehicles/sm_vehicle_supplier_truck.glb")
## The model's headlamps glow after dark, like the other vehicles' (N-304).
const NIGHT_LIGHTS: Array = ["lamp"]
## The roll-up shutter of the model: its origin is the top edge, so scaling its local Y rolls it up.
const REAR_DOOR_NODE: String = "RearDoor"
## How much of the shutter still hangs under the header when it is rolled up (a lip with its bottom bar).
const REAR_DOOR_ROLLED: float = 0.04
## Game minutes (1.5 s real each) the shutter takes to roll up when the truck has parked, and to roll down
## before it leaves.
const REAR_DOOR_ROLL_MIN: float = 1.0
## Where the model's box starts behind the nose and how high its floor stands (build_street_props.py keeps
## the same numbers): the bed's slots are measured from them.
const CAB_LENGTH: float = 1.7
const CARGO_FLOOR: float = 0.7
## The bed's walls and floor are this thick.
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
var _rear_door: Node3D
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
	_rear_door.scale.y = lerpf(1.0, REAR_DOOR_ROLLED, door_opening(float(minute_now.call())))


## Whether the truck is parked and waiting now: the jack may take pallets off its bed (the day's calendar, as
## the pose reads it).
func bed_open() -> bool:
	if schedule == null or not minute_now.is_valid():
		return false
	var day: int = int(company.get("day")) if company != null else CompanyTuning.STARTING_DAY
	return schedule.truck_state(day, floori(float(minute_now.call()))) == SupplierSchedule.STATE_AT_DOCK


## How far the rear shutter is rolled up at `minute`, 0 (shut) to 1 (open): it follows the parked hours of
## the day's calendar, so it depends on the clock alone, like the pose. It opens in the first minute of the
## wait and shuts in the last one, while the truck stands still.
static func door_opening(minute: float) -> float:
	var waited: float = minute - float(SupplierSchedule.arrival_minute())
	var left: float = float(SupplierSchedule.departure_minute()) - minute
	return clampf(minf(waited, left) / REAR_DOOR_ROLL_MIN, 0.0, 1.0)


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


## The truck's model, facing -Z (Godot's forward), centred on its footprint, wheels on the floor.
func _build_body() -> Node3D:
	var root := Node3D.new()
	root.name = "Body"
	var model := MODEL.instantiate() as Node3D
	model.name = "Model"
	root.add_child(model)
	LowpolyMaterials.apply(model)
	LowpolyMaterials.light_up(model, NIGHT_LIGHTS)
	_rear_door = model.find_child(REAR_DOOR_NODE, true, false) as Node3D
	return root
