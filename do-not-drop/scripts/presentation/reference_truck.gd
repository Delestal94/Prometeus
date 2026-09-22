class_name ReferenceTruck
extends Node3D
## Presentation adapter for the authored low-poly step van.  Gameplay nodes
## remain in vehicle.tscn so seats, packages, physics and networking retain
## their stable paths.

const TRUCK_PATH := "res://assets/models/truck_reference_lowpoly.glb"
const MODEL_SCALE := 0.8

var vehicle: VehicleBody3D
var model: Node3D
var _rear_doors: Array[Node3D] = []
var _rear_blockers: Array[CollisionShape3D] = []


func _ready() -> void:
	vehicle = get_parent() as VehicleBody3D
	call_deferred("_install")


func _install() -> void:
	if vehicle == null or vehicle.get_node_or_null("ReferenceTruckModel") != null:
		return
	_hide_legacy_meshes()
	model = _load_model()
	if model == null:
		push_error("No se pudo cargar el modelo de camión: " + TRUCK_PATH)
		return
	model.name = "ReferenceTruckModel"
	# Blender uses +X as front.  Godot gameplay uses -Z as front.
	model.position = Vector3(0.0, -0.674, 0.604)
	model.rotation.y = PI * 0.5
	model.scale = Vector3.ONE * MODEL_SCALE
	vehicle.get_node("BodyVisuals").add_child(model)
	_make_glass_transparent()
	_attach_wheel_visuals()
	_reposition_gameplay_anchors()
	_add_rear_door_control()
	set_rear_doors_open(bool(vehicle.get(&"rear_cargo_open")))


func _load_model() -> Node3D:
	# GLTFDocument works both in-editor and in command-line runs before an
	# editor import cache exists.
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	if document.append_from_file(TRUCK_PATH, state) != OK:
		return null
	return document.generate_scene(state) as Node3D


func _hide_legacy_meshes() -> void:
	for container_name in [&"BodyVisuals", &"CabinInterior", &"CargoBay"]:
		var container := vehicle.get_node_or_null(NodePath(container_name))
		if container == null:
			continue
		for mesh: MeshInstance3D in container.find_children("*", "MeshInstance3D", true, false):
			mesh.visible = false
	# The stock wheels are deliberately hidden, but their VehicleWheel3D nodes
	# remain the authoritative suspension and rotation points.
	for wheel_name in [&"FrontLeftWheel", &"FrontRightWheel", &"RearLeftWheel", &"RearRightWheel"]:
		var wheel := vehicle.get_node_or_null(NodePath(wheel_name))
		if wheel != null:
			for mesh: MeshInstance3D in wheel.find_children("*", "MeshInstance3D", true, false):
				mesh.visible = false


func _make_glass_transparent() -> void:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.47, 0.78, 0.92, 0.26)
	glass.metallic = 0.08
	glass.roughness = 0.18
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if "window" in mesh.name.to_lower() or "glass" in mesh.name.to_lower():
			mesh.material_override = glass


func _attach_wheel_visuals() -> void:
	# Keep Godot's VehicleWheel3D suspension/rotation, replacing only its
	# primitive tire art with the authored tire, rim, hub and bolts.
	var mapping := {
		"Wheel_Front_Left_AXLE_Y": "FrontLeftWheel",
		"Wheel_Front_Right_AXLE_Y": "FrontRightWheel",
		"Wheel_Rear_Left_AXLE_Y": "RearLeftWheel",
		"Wheel_Rear_Right_AXLE_Y": "RearRightWheel",
	}
	for art_name: String in mapping:
		var art := model.find_child(art_name, true, false) as Node3D
		var wheel := vehicle.get_node_or_null(NodePath(mapping[art_name])) as Node3D
		if art != null and wheel != null:
			art.reparent(wheel, true)


func _reposition_gameplay_anchors() -> void:
	# Driver and the seven passenger interactions line up with the authored
	# interior; stable names keep all existing gameplay and tests working.
	_set_anchor("CabinInterior/DriverEyePoint", Vector3(-0.50, 1.48, -1.35))
	var seats := {
		"LeftSeat1EyePoint": Vector3(-0.56, 1.18, 0.05),
		"LeftSeat2EyePoint": Vector3(-0.56, 1.18, 0.95),
		"LeftSeat3EyePoint": Vector3(-0.56, 1.18, 1.85),
		"RightSeat1EyePoint": Vector3(0.56, 1.18, 0.05),
		"RightSeat2EyePoint": Vector3(0.56, 1.18, 0.95),
		"RightSeat3EyePoint": Vector3(0.56, 1.18, 1.85),
		"CenterSeatEyePoint": Vector3(0.0, 1.18, 2.65),
	}
	for anchor_name: String in seats:
		_set_anchor("CargoBay/" + anchor_name, seats[anchor_name])
	# Usable shelf mounts at waist height, aligned to both long shelving runs.
	_set_anchor("CargoBay/LeftShelfPackageMount", Vector3(-0.72, 0.72, 3.20))
	_set_anchor("CargoBay/RightShelfPackageMount", Vector3(0.72, 0.72, 3.20))
	_set_anchor("CargoBay/LeftSeat1PackageMount", Vector3(-0.55, 0.85, 0.05))
	_set_anchor("CargoBay/LeftSeat2PackageMount", Vector3(-0.55, 0.85, 0.95))
	_set_anchor("CargoBay/RightSeat1PackageMount", Vector3(0.55, 0.85, 0.05))
	_set_anchor("CargoBay/RightSeat2PackageMount", Vector3(0.55, 0.85, 0.95))


func _set_anchor(path: String, local_position: Vector3) -> void:
	var anchor := vehicle.get_node_or_null(path) as Node3D
	if anchor != null:
		anchor.position = local_position


func _add_rear_door_control() -> void:
	for name in [&"RearDoor_Left_HINGE_Z", &"RearDoor_Right_HINGE_Z"]:
		var door := model.find_child(name, true, false) as Node3D
		if door != null:
			_rear_doors.append(door)
	var area := Area3D.new()
	area.name = "RearDoorControl"
	area.set_script(preload("res://scripts/gameplay/interaction/rear_cargo_door.gd"))
	area.position = Vector3(0.0, 1.0, 4.55)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.15
	shape.shape = sphere
	area.add_child(shape)
	vehicle.add_child(area)
	var blockers := StaticBody3D.new()
	blockers.name = "RearClosedDoorCollision"
	for side in [-1.0, 1.0]:
		var blocker := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.05, 2.05, 0.12)
		blocker.shape = box
		blocker.position = Vector3(side * 0.53, 1.15, 4.52)
		blockers.add_child(blocker)
		_rear_blockers.append(blocker)
	vehicle.add_child(blockers)


func set_rear_doors_open(open: bool) -> void:
	if model == null:
		return
	for door: Node3D in _rear_doors:
		var side := -1.0 if "Left" in door.name else 1.0
		# Blender's vertical Z axis becomes Godot's Y axis on import.
		door.rotation.y = side * (1.92 if open else 0.0)
	for blocker: CollisionShape3D in _rear_blockers:
		blocker.disabled = open
