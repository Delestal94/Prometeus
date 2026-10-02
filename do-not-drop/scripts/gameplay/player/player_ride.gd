extends RefCounted
## Riding in the truck and where the other peers see a player (N-225.5), split out of player.gd: finding the
## truck, being carried along by it, publishing the owner's pose (in the truck's space while aboard) and putting
## everyone else's copy of the player where the owner says. The state (`_riding`, `_ride_last_transform`,
## `_vehicle`, `net_position`, `net_in_vehicle`) and the masks stay on the Player, which keeps thin wrappers for
## what tests and the other player components call.
##
## The truck is by name on purpose (vehicle.gd has no class name and tests put plain-Node fakes with `carries`
## in the "vehicle" group).


static func find_vehicle(p: Player) -> Node3D:
	if not is_instance_valid(p._vehicle) and p.is_inside_tree():
		var found: Node = p.get_tree().get_first_node_in_group(&"vehicle")
		p._vehicle = found as Node3D if found != null and found.has_method(&"carries") else null
	return p._vehicle


## What an on-foot player collides with: see Player.ON_FOOT_MASK.
static func on_foot_mask(p: Player, riding: bool) -> int:
	if not riding:
		return Player.ON_FOOT_MASK
	var vehicle: Node3D = find_vehicle(p)
	var moving: bool = (vehicle is RigidBody3D
			and (vehicle as RigidBody3D).linear_velocity.length() > Player.RIDING_SPEED)
	return Player.RIDING_MASK if moving else Player.ON_FOOT_MASK


## A client's truck is teleported by the network whenever an update lands,
## not on physics ticks, and isn't interpolated. A rider moved with it only
## on ticks, and drawn interpolated between them, was drawn up to a metre
## behind it at speed: the view jumped against the truck's own walls. While
## riding such a truck the owner follows it every frame, uninterpolated.
static func ride_frame_by_frame(p: Player) -> void:
	var vehicle: Node3D = find_vehicle(p)
	var per_frame: bool = p._riding and vehicle != null and not vehicle.is_physics_interpolated_and_enabled()
	var wanted: Node.PhysicsInterpolationMode = (Node.PHYSICS_INTERPOLATION_MODE_OFF if per_frame
			else Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
	if p.physics_interpolation_mode != wanted:
		p.physics_interpolation_mode = wanted
		p.reset_physics_interpolation()
	if per_frame:
		ride_with_vehicle(p)


## Everyone else's copy of this player: where the owner says, inside this
## peer's truck if they're riding in it. Each frame against the truck as
## drawn -- except riding a simulated (interpolated) truck, the host's: there
## this body is solid in the moving bay, and a frame's drawn pose is up to a
## tick behind the simulated one. So there it follows the truck on the ticks
## (`on_tick`, from _physics_process) and is drawn interpolated along with it;
## placed per frame it rammed the loose boxes at every step.
## The owner's poses come through a NetPoseSmoother (N-217): drawn a touch in
## the past, interpolated, so the jitter of the link (and the host's relay)
## doesn't make them jump. Until the first one lands, the raw pair. The head's
## turn, the gait speed and the jump clip ride in the same buffer (drawn_extra),
## so the animation doesn't run ahead of the body.
static func apply_net_state(p: Player, on_tick: bool = false) -> void:
	if not p._has_net_state:
		return
	var vehicle: Node3D = find_vehicle(p)
	var riding: bool = p.net_in_vehicle and vehicle != null
	var tick_placed: bool = riding and vehicle.is_physics_interpolated_and_enabled()
	var wanted: Node.PhysicsInterpolationMode = (Node.PHYSICS_INTERPOLATION_MODE_INHERIT if tick_placed
			else Node.PHYSICS_INTERPOLATION_MODE_OFF)
	if p.physics_interpolation_mode != wanted:
		p.physics_interpolation_mode = wanted
		p.reset_physics_interpolation()
	if on_tick != tick_placed:
		return
	var truck: Transform3D = Transform3D.IDENTITY
	if vehicle != null:
		truck = vehicle.global_transform if on_tick else drawn_transform(vehicle)
	if p._net_smoother != null and not p._net_smoother.is_empty():
		var pose: Transform3D = p._net_smoother.sample(NetPoseSmoother.local_now(), truck)
		if pose != Transform3D.IDENTITY:
			p.global_position = pose.origin
			p.rotation.y = yaw_on(truck.basis, truck.basis.inverse() * pose.basis) if p._net_smoother.latest_local() \
					else yaw_of(pose.basis)
			_apply_drawn_extra(p, p._net_smoother.drawn_extra(), p._net_smoother.drawn_extra_before())
	elif riding:
		p.global_position = truck * p.net_position
		p.rotation.y = yaw_of(truck.basis) + p.net_yaw
	else:
		p.global_position = p.net_position
		p.rotation.y = p.net_yaw
	# A box in this body's hands is drawn on it: now, not before or after the body moves (PackageNetPose).
	if not on_tick and is_instance_valid(p.carried_package):
		p.carried_package._net_view.follow(p.carried_package)


## Everyone else's copy, when a synced packet has landed whole (the
## synchronizer's `synchronized`): the owner's pose into the buffer, in the
## truck's space while they ride, with what the animation needs in step.
static func push_net_pose(p: Player) -> void:
	if not p.is_inside_tree() or p.is_local():
		return
	if p._net_smoother == null:
		p._net_smoother = NetPoseSmoother.new()
		var network: Node = p.get_node_or_null(^"/root/NetworkManager")
		if network != null and network.has_method(&"pose_net_sim"):
			p._net_smoother.configure_sim(network.call(&"pose_net_sim"))
	var head: Vector3 = p._head.rotation
	p._net_smoother.push(p.net_time / 1000.0, Transform3D(Basis(Vector3.UP, p.net_yaw), p.net_position),
			NetPoseSmoother.local_now(), p.net_in_vehicle,
			PackedFloat32Array([head.x, head.y, head.z, p.locomotion_speed, p.jump_anim_time]))


## The synced animation numbers as of the moment drawn (push_net_pose()). The
## jump clip restarts at 0: from a higher value it keeps the earlier one
## instead of sliding back through the whole clip.
static func _apply_drawn_extra(p: Player, extra: PackedFloat32Array, before: PackedFloat32Array) -> void:
	if extra.size() != 5:
		return
	p._head.rotation = Vector3(extra[0], extra[1], extra[2])
	p.locomotion_speed = extra[3]
	p.jump_anim_time = maxf(extra[4], before[4]) if before.size() == 5 else extra[4]


## A heading on a truck that may be tilted: the truck's own heading plus the
## turn `relative` (in the truck's space) adds to it. yaw_of() of the tilted
## product would be off by the tilt.
static func yaw_on(truck: Basis, relative: Basis) -> float:
	return yaw_of(truck) + yaw_of(relative)


## Where a remote player is by their newest pose, not where it's drawn: the
## host judges a request against where the owner was when they made it
## (reach_origin()). Anyone without poses yet, or this peer's own, is where
## it stands.
static func latest_position(p: Player) -> Vector3:
	if p.is_local() or p._net_smoother == null or p._net_smoother.is_empty():
		return p.global_position
	var at: Vector3 = p._net_smoother.latest_pose().origin
	if p._net_smoother.latest_local():
		var vehicle: Node3D = find_vehicle(p)
		return vehicle.global_transform * at if vehicle != null else p.global_position
	return at


## The heading of a basis about +Y (Basis(Vector3.UP, yaw_of(b)) faces where b does, level).
static func yaw_of(basis: Basis) -> float:
	var forward: Vector3 = -basis.z
	return atan2(-forward.x, -forward.z)


## Where a node is drawn this frame. A client's truck is frozen and not
## interpolated, and then get_global_transform_interpolated() hands back last
## frame's cached pose instead of where the network just put it.
static func drawn_transform(node: Node3D) -> Transform3D:
	if node.is_physics_interpolated_and_enabled():
		return node.get_global_transform_interpolated()
	return node.global_transform


static func publish_net_state(p: Player) -> void:
	var vehicle: Node3D = find_vehicle(p)
	# A little give once aboard, so standing right at the rear doors doesn't
	# flip between the truck's space and the world's every other frame.
	var riding: bool = vehicle != null and bool(vehicle.call(&"carries", p.global_position,
			Player.RIDE_MARGIN if p.net_in_vehicle else 0.0))
	p.net_in_vehicle = riding
	p.net_position = vehicle.to_local(p.global_position) if riding else p.global_position
	p.net_yaw = angle_difference(yaw_of(vehicle.global_basis), yaw_of(p.global_basis)) if riding \
			else yaw_of(p.global_basis)
	p.net_time = NetPoseSmoother.clock_ms()


## Standing (or jumping) in the cargo bay, the owner is moved along with the
## truck by however much it moved since the last tick, turning with it. On a
## client the truck is a copy the network teleports, which carries nobody by
## itself: its walls just slid over the player (through the closed doors,
## and out the back).
static func ride_with_vehicle(p: Player) -> void:
	var vehicle: Node3D = find_vehicle(p)
	if vehicle == null:
		p._riding = false
		return
	var now: Transform3D = vehicle.global_transform
	if p._riding:
		var motion: Transform3D = now * p._ride_last_transform.affine_inverse()
		p.global_position = motion * p.global_position
		var heading: Vector3 = motion.basis * -p.global_basis.z
		heading.y = 0.0
		if heading.length_squared() > 0.0001:
			p.rotate_y((-p.global_basis.z).signed_angle_to(heading.normalized(), Vector3.UP))
	p._riding = bool(vehicle.call(&"carries", p.global_position, Player.RIDE_MARGIN if p._riding else 0.0))
	p._ride_last_transform = now
