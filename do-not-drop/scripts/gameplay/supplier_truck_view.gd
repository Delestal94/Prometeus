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

const CAB_COLOR: Color = Color(0.78, 0.45, 0.16)
const CARGO_COLOR: Color = Color(0.74, 0.74, 0.76)
const CHASSIS_COLOR: Color = Color(0.22, 0.22, 0.24)
const GLASS_COLOR: Color = Color(0.30, 0.42, 0.52)
const WHEEL_RADIUS: float = 0.5
const WHEEL_WIDTH: float = 0.3
const CAB_LENGTH: float = 1.7
const CARGO_FLOOR: float = 0.7

## Today's calendar; null draws nothing.
var schedule: SupplierSchedule
## Where the shed's centre is in the world (the shed's position).
var origin: Vector3 = Vector3.ZERO
## The company (CompanyState-shaped: `day` and `warehouse_stage`); null reads day 1, stage 0.
var company: Object
## Callable() -> float, the game minute (GameClock.minute_now()).
var minute_now: Callable = Callable()

var _body: Node3D


func _init() -> void:
	name = "SupplierTruck"
	visible = false
	_body = _build_body()
	add_child(_body)


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


## The truck facing -Z (Godot's forward), centred on its footprint, wheels on the floor.
func _build_body() -> Node3D:
	var size: Vector3 = CompanyTuning.SUPPLIER_TRUCK_SIZE_M
	var root := Node3D.new()
	root.name = "Body"
	var cargo_len: float = size.z - CAB_LENGTH
	var front: float = -size.z * 0.5
	_add_box(root, "Chassis", Vector3(size.x * 0.92, 0.3, size.z), Vector3(0.0, 0.55, 0.0), CHASSIS_COLOR)
	_add_box(root, "Cargo", Vector3(size.x, size.y - CARGO_FLOOR, cargo_len),
		Vector3(0.0, CARGO_FLOOR + (size.y - CARGO_FLOOR) * 0.5, front + CAB_LENGTH + cargo_len * 0.5),
		CARGO_COLOR)
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
