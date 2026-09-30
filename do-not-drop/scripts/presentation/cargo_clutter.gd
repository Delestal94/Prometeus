extends Node
## Loose odds and ends riding in the cargo bay (tareas de Nacho #18): a
## toolbox on the floor and a thermos left on the seat bench, real rigid
## bodies that slide, tip over and clatter on every bump -- and roll out the
## back if someone drives off with the doors open (#17).
##
## Their look is a low-poly GLB each (N-139, assets/tools/build_cargo_clutter.py),
## origin at the centre of the base: the collision shapes stay the plain box and
## cylinder they always were. The models keep their flat palette on purpose:
## none of their materials is in LowpolyMaterials.DETAIL, so apply() would
## change nothing and only cost a pass over the meshes.
##
## Pure scenery, simulated separately on every client and never replicated:
## they only collide with the truck's cargo shell and the ground, never with
## packages (a thermos must not be what ruins a Fragile box) or players.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const TOOLBOX_MODEL: PackedScene = preload("res://assets/models/props/cargo/sm_prop_cargo_toolbox.glb")
const THERMOS_MODEL: PackedScene = preload("res://assets/models/props/cargo/sm_prop_cargo_thermos.glb")
## Collision sizes (m): the body of the toolbox, and the thermos' height.
const TOOLBOX_SIZE: Vector3 = Vector3(0.36, 0.2, 0.2)
const THERMOS_HEIGHT: float = 0.26
const ENVIRONMENT_AND_SHELL: int = 1 | Vehicle.SHELL_LAYER
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
	_items.append(_make_toolbox(world, Vector3(0.74, 0.37, 2.2)))
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


## Continuous collision only while loose or thrown about the bay: riding
## along with it on, they were swept out through the shut rear doors, like
## the boxes (Vehicle.needs_sweep()).
func _physics_process(_delta: float) -> void:
	if vehicle == null:
		return
	for item: RigidBody3D in _items:
		if is_instance_valid(item):
			item.continuous_cd = bool(vehicle.call(&"needs_sweep", item, 0.4))


## A rigid body with `shape` for collision and `model` (a GLB whose origin is
## the centre of its base) as the look, dropped by `drop` so that base rests
## on the floor of the collision shape (half its height).
func _make_item(world: Node, item_name: String, shape: Shape3D, model: PackedScene, drop: float, mass_kg: float, at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "CargoClutter" + item_name
	body.mass = mass_kg
	body.collision_layer = 0
	body.collision_mask = ENVIRONMENT_AND_SHELL
	# Light and quick next to the walls they rattle against: without
	# continuous collision a hard stop could tunnel them straight through
	# (switched per tick, see _physics_process).
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 2
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var visual: Node3D = model.instantiate()
	visual.position = Vector3(0.0, -drop, 0.0)
	body.add_child(visual)
	_add_rattle(body, 1.6 if item_name == "Toolbox" else 2.3)
	world.add_child(body)
	body.global_transform = vehicle.global_transform * Transform3D(Basis(Vector3.UP, randf_range(-0.3, 0.3)), at)
	if not vehicle.is_multiplayer_authority():
		body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body.reset_physics_interpolation()
	return body


func _make_toolbox(world: Node, at: Vector3) -> RigidBody3D:
	var box := BoxShape3D.new()
	box.size = TOOLBOX_SIZE
	return _make_item(world, "Toolbox", box, TOOLBOX_MODEL, TOOLBOX_SIZE.y * 0.5, 3.5, at)


func _make_thermos(world: Node, at: Vector3) -> RigidBody3D:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.045
	cylinder.height = THERMOS_HEIGHT
	return _make_item(world, "Thermos", cylinder, THERMOS_MODEL, THERMOS_HEIGHT * 0.5, 0.8, at)


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
