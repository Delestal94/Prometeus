extends Node
## Loose odds and ends riding in the cargo bay (tareas de Nacho #18): a
## toolbox on the floor and a thermos left on the seat bench, real rigid
## bodies that slide, tip over and clatter on every bump -- and roll out the
## back if someone drives off with the doors open (#17).
##
## Pure scenery, simulated separately on every client and never replicated:
## they only collide with the truck and the ground, never with packages
## (a thermos must not be what ruins a Fragile box) or players.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const ENVIRONMENT_AND_VEHICLE: int = 1 | 2
## Relative speed (m/s) for a knock to be heard.
const RATTLE_MIN_SPEED: float = 0.9

var vehicle: VehicleBody3D
var _items: Array[RigidBody3D] = []
var _vehicle_last: Transform3D = Transform3D.IDENTITY
var _tracking: bool = false
const Vehicle = preload("res://scripts/gameplay/vehicle/vehicle.gd")


func _ready() -> void:
	vehicle = get_parent().get(&"vehicle")
	# After the level has placed the truck, so the items start inside it.
	_spawn.call_deferred()


func _spawn() -> void:
	var world: Node = vehicle.get_parent()
	if world == null:
		return
	# Vehicle space: +X right, -Z toward the cab, cargo floor top at y 0.26.
	_items.append(_make_item(world, "Toolbox", Vector3(0.36, 0.2, 0.2), Color("d2412f"), 3.5, Vector3(0.74, 0.37, 2.2)))
	_items.append(_make_thermos(world, Vector3(0.82, 0.74, 1.05)))


## On a client the truck is a frozen copy the network teleports every frame:
## it drags nothing along, so its walls just swept through whatever sat in
## the bay and the clutter bounced about and fell out. There, whatever's in
## the bay is moved with the truck by hand and only jostles in its own space.
## On the host the real, moving truck carries it physically. Every frame, not
## every tick, and uninterpolated: the network moves the truck whenever an
## update lands, and anything following it only on ticks trailed behind.
func _process(_delta: float) -> void:
	if vehicle == null or vehicle.is_multiplayer_authority():
		return
	var previous: Transform3D = _vehicle_last
	_vehicle_last = vehicle.global_transform
	if not _tracking:
		_tracking = true
		return
	var motion: Transform3D = _vehicle_last * previous.affine_inverse()
	for item: RigidBody3D in _items:
		# Judged against where the truck was, which is where the item still is.
		if is_instance_valid(item) and Vehicle.CARGO_BAY.has_point(previous.affine_inverse() * item.global_position):
			item.global_transform = motion * item.global_transform


func _make_item(world: Node, item_name: String, size: Vector3, color: Color, mass_kg: float, at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "CargoClutter" + item_name
	body.mass = mass_kg
	body.collision_layer = 0
	body.collision_mask = ENVIRONMENT_AND_VEHICLE
	# Light and quick next to the walls they rattle against: without
	# continuous collision a hard stop could tunnel them straight through.
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	if item_name == "Toolbox":
		# A handle, so it reads as a toolbox rather than a red brick.
		var handle := MeshInstance3D.new()
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(0.2, 0.03, 0.03)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color("3b3f42")
		handle_mesh.material = steel
		handle.mesh = handle_mesh
		handle.position = Vector3(0.0, size.y * 0.5 + 0.04, 0.0)
		body.add_child(handle)
	_add_rattle(body, 1.6 if item_name == "Toolbox" else 2.3)
	world.add_child(body)
	body.global_transform = vehicle.global_transform * Transform3D(Basis(Vector3.UP, randf_range(-0.3, 0.3)), at)
	if not vehicle.is_multiplayer_authority():
		body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body.reset_physics_interpolation()
	return body


func _make_thermos(world: Node, at: Vector3) -> RigidBody3D:
	var body := _make_item(world, "Thermos", Vector3(0.08, 0.26, 0.08), Color("2c7fb8"), 0.8, at)
	# Swap the box look for a proper cylinder with a dark cap.
	for child: Node in body.get_children():
		if child is MeshInstance3D:
			child.free()
	var shape := body.get_child(0) as CollisionShape3D
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = 0.045
	cylinder_shape.height = 0.26
	shape.shape = cylinder_shape
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.045
	cylinder.bottom_radius = 0.045
	cylinder.height = 0.26
	cylinder.radial_segments = 10
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("2c7fb8")
	paint.metallic = 0.4
	paint.roughness = 0.35
	cylinder.material = paint
	mesh.mesh = cylinder
	body.add_child(mesh)
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.04
	cap_mesh.bottom_radius = 0.047
	cap_mesh.height = 0.05
	cap_mesh.radial_segments = 10
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("1f2326")
	cap_mesh.material = dark
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, 0.155, 0.0)
	body.add_child(cap)
	return body


func _add_rattle(body: RigidBody3D, pitch: float) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = SynthAudio.impact_thud()
	sound.bus = &"SFX"
	sound.volume_db = WorldMix.CLUTTER_DB
	sound.unit_size = 3.0
	sound.max_distance = 18.0
	sound.pitch_scale = pitch
	body.add_child(sound)
	body.body_entered.connect(func(_other: Node) -> void:
		var relative: Vector3 = body.linear_velocity - vehicle.linear_velocity
		if relative.length() >= RATTLE_MIN_SPEED and not sound.playing:
			sound.pitch_scale = pitch * randf_range(0.9, 1.1)
			sound.play())


func _exit_tree() -> void:
	for item: RigidBody3D in _items:
		if is_instance_valid(item):
			item.queue_free()
