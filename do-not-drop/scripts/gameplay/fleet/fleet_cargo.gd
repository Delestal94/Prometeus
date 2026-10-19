extends RefCounted
## What a fleet vehicle does for its cargo, apart from how it moves (expansion D-0208).
##
## One per vehicle, made by the vehicle's own script with itself as `body`: the van
## (vehicle.gd) holds it by composition, and a boat, a plane or a bike would do the same
## without inheriting from VehicleBody3D. `body` is any Node3D; the motion it reads
## (linear_velocity, angular_velocity, center_of_mass, freeze) comes from a RigidBody3D, a
## CharacterBody3D (velocity only) or, for anything else, properties of those names.
## Preloaded, not by class_name: a new global class isn't in the class cache until the
## editor imports again, and headless runs load the van first.
##
## What it answers (vehicle.gd keeps thin wrappers with the same names, so no caller changed):
## - carries(), point_velocity(), needs_sweep(): who rides along, and at what speed;
## - the cargo shell: a kinematic copy of the body's collision shapes on SHELL_LAYER that
##   carries boxes and riders without them pushing the vehicle back;
## - on_package_placed(): sets a shelved box on its deck, whatever its shape;
## - get_cargo_spawn_transform(): where a new box appears.
## Not here: doors, the loading ramp and the rack's art (the van's), and anything that
## drives (engine, steering, prediction, net pose, wheels, parking).
##
## Inventory of vehicle.gd before D-0208 (line numbers of that file) -- what was cargo:
## - 245-263 consts MOUNT_REFERENCE_HALF_HEIGHT, CARGO_BAY, CARGO_WALL_INNER_X,
##   CARGO_WALL_CLEARANCE, SHELL_LAYER, and 264 `_shell`;
## - 266 `_package_spawn` (the first seat's mount) and 701-702 get_cargo_spawn_transform();
## - 316-347 carries(), point_velocity(), needs_sweep();
## - 390-464 _build_cargo_shell(), SHELL_TELEPORT_DISTANCE, _notification(),
##   _teleport_shell(), _follow_with_shell(); called from _ready() (305) and
##   _physics_process() (793);
## - 467-494 _on_package_placed(), connected in _ready() (313) on the host;
## - 379-387 _apply_door() disables the rear blocker on the body and on the shell (stays).
## In vehicle.tscn: node CargoBay (303) holds the seats' eye points and the PackageMount
## markers (540-610); the shell copies the CollisionShape3D children (170-237, never
## RearRamp, 244). Seats: see fleet_seats.gd.

## A 0.65 m box's half height: rack markers sit that far above their deck.
const MOUNT_REFERENCE_HALF_HEIGHT: float = 0.325
## The default bay (the van's): its inside in the body's own space, side wall to side
## wall, floor to roof, cab wall to rear doors (vehicle.tscn's collision shapes).
## Whatever is in here rides with the vehicle -- see carries(). Another vehicle sets `bay`.
const CARGO_BAY: AABB = AABB(Vector3(-1.05, 0.0, -0.35), Vector3(2.1, 2.6, 4.95))
## Inner face of each side wall (WallCollision at x = ±1.05, 0.1 thick).
const CARGO_WALL_INNER_X: float = 1.0
## Room a shelved box keeps from the wall: its tape and straps stick out a
## few centimetres past the collider (package_feedback.gd).
const CARGO_WALL_CLEARANCE: float = 0.045
## The cargo shell's physics layer (7, "vehicle_shell"). What rides in the
## vehicle or bumps into it -- boxes, players, loose clutter, a ragdoll -- collides
## with the shell, never with the vehicle's own body, whose mask is the
## environment alone. The shell is kinematic: it carries and stops a box like
## a wall of infinite mass, and nothing that hits it pushes back on the
## vehicle. Before it, an 8-20 kg box sliding about the bay (or a player, who
## the solver treats as immovable) shoved a 950 kg truck around: it drove in
## jerks (playtest 2026-09-25).
const SHELL_LAYER: int = 64
## Farther than the vehicle can travel in a tick: moved by hand (a test, a
## reset), not driven. The shell jumps there with it before the next step
## (transform notifications are flushed once a frame) instead of
## sweeping the whole way in it, which would fling whatever it carries at
## hundreds of metres a second.
const SHELL_TELEPORT_DISTANCE: float = 2.0

## The cargo bay in the body's space (carries()).
var bay: AABB = CARGO_BAY
## The marker where a new box appears (get_cargo_spawn_transform()); set by the owner.
var spawn_point: Node3D
## The shell, once build_shell() has run.
var shell: StaticBody3D

var _body: Node3D
var _rigid: RigidBody3D
var _character: CharacterBody3D


func _init(body: Node3D) -> void:
	_body = body
	_rigid = body as RigidBody3D
	_character = body as CharacterBody3D


## Whether a world point is inside the cargo bay, i.e. riding along: players
## standing in the back, boxes, loose clutter. Uses this peer's copy of the
## vehicle, so on a client it answers for the vehicle that client actually sees.
##
## `margin` grows the bay on every side: whoever's already aboard passes it,
## so something right at the rear doors doesn't flicker in and out.
func carries(world_point: Vector3, margin: float = 0.0) -> bool:
	return bay.grow(margin).has_point(_body.to_local(world_point))


## How fast a point riding in the vehicle is moving in the world: what a box
## let go of in the moving bay has to start with, or it slams into the rear
## wall as if dropped from a standstill. The velocities are replicated, so
## this holds on a client's copy too.
func point_velocity(world_point: Vector3) -> Vector3:
	var centre: Vector3 = _body.global_transform * _center_of_mass()
	return _linear_velocity() + _angular_velocity().cross(world_point - centre)


## Whether a rigid body in or around the vehicle (a box, loose clutter) should
## use continuous collision this tick. Jolt sweeps it from last tick's spot
## to this one against the cargo shell where the shell ends up, so riding
## along -- a third of a metre a tick at 72 km/h -- the sweep started from
## behind the rack's rear stop and the shut rear doors, and a box resting
## against them was stopped on the far side and fell out (playtest
## 2026-09-27, tests/test_cargo_shell.gd). So: sweep while loose in the
## world, or while it moves inside the bay faster than the vehicle carries it
## (a crash throwing it at the bulkhead); not while it just rides along.
func needs_sweep(box: RigidBody3D, margin: float = 0.0) -> bool:
	if not carries(box.global_position, margin):
		return true
	var carried: Vector3 = point_velocity(box.global_position)
	return (box.linear_velocity - carried).length_squared() > carried.length_squared()


func get_cargo_spawn_transform() -> Transform3D:
	return spawn_point.global_transform


## The shell: a copy of every collision shape of the body (sharing
## the Shape resources), in the same place, on SHELL_LAYER. On the host it's
## a kinematic body moved each tick to where the vehicle will be at the end of
## the step (follow), so it carries its riders at the vehicle's own
## speed. On a client the vehicle is a frozen copy the network teleports; there
## the shell is a plain static child that jumps along with it, the way the
## vehicle's own shapes used to.
func build_shell() -> void:
	var simulated: bool = _body.is_multiplayer_authority()
	shell = AnimatableBody3D.new() if simulated else StaticBody3D.new()
	shell.name = "CargoShell"
	shell.collision_layer = SHELL_LAYER
	shell.collision_mask = 0
	if _rigid != null:
		shell.physics_material_override = _rigid.physics_material_override
	if simulated:
		(shell as AnimatableBody3D).sync_to_physics = false
		shell.top_level = true
		shell.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# Top level: this is its world pose, from the moment it exists.
		shell.transform = _body.global_transform
	for child: Node in _body.get_children():
		var source := child as CollisionShape3D
		if source == null:
			continue
		var copy := CollisionShape3D.new()
		copy.name = source.name
		copy.shape = source.shape
		copy.transform = source.transform
		copy.disabled = source.disabled
		shell.add_child(copy)
	_body.add_child(shell)
	if simulated:
		_body.set_notify_transform(true)


## The body's NOTIFICATION_TRANSFORM_CHANGED: moved by hand, the shell goes along.
func on_body_transform_changed() -> void:
	if shell != null and shell.top_level:
		if shell.global_position.distance_to(_body.global_position) > SHELL_TELEPORT_DISTANCE:
			_teleport_shell(_body.global_transform)


func _teleport_shell(to: Transform3D) -> void:
	var shell_rid: RID = shell.get_rid()
	PhysicsServer3D.body_set_mode(shell_rid, PhysicsServer3D.BODY_MODE_STATIC)
	shell.global_transform = to
	PhysicsServer3D.body_set_mode(shell_rid, PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_set_state(shell_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, to)


## Host, each tick before the step: where the vehicle will be once the step
## is done -- its pose now, carried on by its velocity and spin -- so the
## step moves the shell along with the vehicle at the vehicle's own speed.
## Following the vehicle's pose as of now instead, it would trail a tick
## behind (a third of a metre at 72 km/h), and the boxes with it.
func follow(delta: float) -> void:
	var ahead: Transform3D = _body.global_transform
	if not _is_frozen():
		var mass_centre: Vector3 = _center_of_mass()
		var centre: Vector3 = _body.global_transform * mass_centre
		var turned: Basis = _body.global_basis
		var spin: Vector3 = _angular_velocity()
		if spin.length_squared() > 0.000001:
			turned = Basis(spin.normalized(), spin.length() * delta) * _body.global_basis
		ahead = Transform3D(turned, centre + _linear_velocity() * delta - turned * mass_centre)
	if shell.global_position.distance_to(ahead.origin) > SHELL_TELEPORT_DISTANCE:
		_teleport_shell(ahead)
		return
	# Kinematic: this is only the target the step moves it to.
	shell.global_transform = ahead


## A box set on the rack rests on its deck whatever its shape: the markers
## are placed for the standard 0.65 m box, so a tall or flat one is raised or
## lowered by the difference instead of sinking into the deck or hovering.
func on_package_placed(package_id: StringName) -> void:
	for package: Node in _body.get_tree().get_nodes_in_group(&"cargo"):
		if package.get(&"package_id") != package_id or not package.has_method(&"get_half_extents"):
			continue
		var mount_point: Node = package.get(&"current_mount") as Node
		# A mount's interaction area hangs off its marker; place_at() may also
		# have been handed the marker itself.
		var marker: Node3D = mount_point as Node3D
		if mount_point is Area3D:
			marker = mount_point.get_parent() as Node3D
		if marker == null or not _body.is_ancestor_of(marker):
			continue
		var half: Vector3 = package.call(&"get_half_extents")
		var offset: float = half.y - MOUNT_REFERENCE_HALF_HEIGHT
		var local_center: Vector3 = _body.to_local(marker.global_transform * Vector3(0.0, offset, 0.0))
		# A wide box (the flat one is 0.95 m) centred on a marker laid out for
		# the 0.65 m one reached into the side wall, and its tape and straps
		# showed through on the outside: slide it in until it clears.
		var box_basis: Basis = _body.global_basis.inverse() * marker.global_basis
		var reach_x: float = (absf(box_basis.x.x) * half.x + absf(box_basis.y.x) * half.y
			+ absf(box_basis.z.x) * half.z + CARGO_WALL_CLEARANCE)
		var limit_x: float = maxf(CARGO_WALL_INNER_X - reach_x, 0.0)
		local_center.x = clampf(local_center.x, -limit_x, limit_x)
		(package as Node3D).global_position = _body.to_global(local_center)
		(package as Node3D).reset_physics_interpolation()


func _linear_velocity() -> Vector3:
	if _rigid != null:
		return _rigid.linear_velocity
	if _character != null:
		return _character.velocity
	return _read_vector(&"linear_velocity")


func _angular_velocity() -> Vector3:
	if _rigid != null:
		return _rigid.angular_velocity
	return _read_vector(&"angular_velocity")


func _center_of_mass() -> Vector3:
	if _rigid != null:
		return _rigid.center_of_mass
	return _read_vector(&"center_of_mass")


func _is_frozen() -> bool:
	if _rigid != null:
		return _rigid.freeze
	return false


## A property of the body that is no RigidBody3D / CharacterBody3D, zero when it has none.
func _read_vector(property: StringName) -> Vector3:
	var value: Variant = _body.get(property)
	return value if value is Vector3 else Vector3.ZERO
