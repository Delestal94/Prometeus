class_name GripArea
extends Area3D
## A stretch of road that lowers the grip of the vehicles on it, for a piece that is not a GravelSegment
## or a mud pit but is loose all the same (a street whose whole surface is gravel or dirt). The grip goes
## through GripZones like theirs: the lowest active zone wins, nothing compounds and the last zone left
## puts the wheels back. Add it to the piece and give it its footprint with add_box().

## Physics layer the vehicles are on (vehicle.tscn), the same GravelSegment's trigger watches.
const VEHICLE_LAYER: int = 2
## Height of the trigger, centred on the road's surface (m): as GravelSegment's.
const HEIGHT: float = 2.0

## What the wheels' wheel_friction_slip drops to inside.
@export var slip: float = 1.1

## The vehicles this area is holding down, so freeing it (a culled cell) lets go of them.
var _vehicles: Array[Node] = []


func _init() -> void:
	collision_layer = 0
	collision_mask = VEHICLE_LAYER
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Adds a stretch of footprint, `size` (x, z in metres) centred on the surface at `surface_transform`.
func add_box(surface_transform: Transform3D, size: Vector2) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, HEIGHT, size.y)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = surface_transform
	add_child(collider)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"vehicle"):
		return
	GripZones.enter(body, self, slip)
	if not _vehicles.has(body):
		_vehicles.append(body)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group(&"vehicle"):
		return
	GripZones.leave(body, self)
	_vehicles.erase(body)


func _exit_tree() -> void:
	for vehicle: Node in _vehicles:
		GripZones.leave(vehicle, self)
	_vehicles.clear()
