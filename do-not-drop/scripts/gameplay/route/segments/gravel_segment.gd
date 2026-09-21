extends RouteSegment
class_name GravelSegment
## A dirt/gravel patch that actually reduces grip, not just a different
## albedo. Verified empirically that VehicleWheel3D.get_skidinfo() ignores
## StaticBody3D.physics_material_override entirely in this Godot/Jolt build
## -- the only thing that moves real wheel grip is
## VehicleWheel3D.wheel_friction_slip, so this segment drives that property
## directly on entry and restores it on exit via an Area3D trigger sized to
## match the road footprint.

const GRAVEL := Color("a08a5c")

## Matches vehicle.tscn's per-wheel default so a restore is exact even if
## that default ever changes there without this file noticing.
@export var default_friction_slip: float = 3.5
@export var reduced_friction_slip: float = 1.1

## wheel -> its friction_slip from just before this segment touched it, so
## overlapping gravel segments (or re-entry) never compounds a reduction.
var _original_friction: Dictionary = {}


func _init() -> void:
	length = 30.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), GRAVEL, true)

	var trigger := Area3D.new()
	trigger.name = "GripZone"
	trigger.position = Vector3(0.0, 0.0, -length * 0.5)
	trigger.collision_layer = 0
	trigger.collision_mask = 2  # vehicle's own layer, set in vehicle.tscn
	trigger.monitoring = true
	add_child(trigger)
	var collider := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(12.0, 2.0, length)
	collider.shape = box_shape
	trigger.add_child(collider)
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"vehicle"):
		return
	for wheel: Node in body.get_children():
		if wheel is VehicleWheel3D and not _original_friction.has(wheel):
			_original_friction[wheel] = wheel.wheel_friction_slip
			wheel.wheel_friction_slip = reduced_friction_slip


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group(&"vehicle"):
		return
	for wheel: Node in body.get_children():
		if wheel is VehicleWheel3D and _original_friction.has(wheel):
			wheel.wheel_friction_slip = _original_friction[wheel]
			_original_friction.erase(wheel)


func _exit_tree() -> void:
	# Safety net for RouteStreamer culling this segment while a wheel is
	# still tracked (e.g. the vehicle reverses back out past the cull
	# threshold instead of driving forward through body_exited normally) --
	# without this, a culled segment could leave grip reduced forever.
	for wheel: Variant in _original_friction.keys():
		if is_instance_valid(wheel):
			(wheel as VehicleWheel3D).wheel_friction_slip = _original_friction[wheel]
	_original_friction.clear()
