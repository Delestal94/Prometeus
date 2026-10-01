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
## peer's truck if they're riding in it, a little in the past and
## interpolated (PlayerNetPose, N-217). Each frame against the truck as
## drawn -- except riding a simulated (interpolated) truck, the host's: there
## this body is solid in the moving bay, and a frame's drawn pose is up to a
## tick behind the simulated one. So there it follows the truck on the ticks
## (`on_tick`, from _physics_process) and is drawn interpolated along with it;
## placed per frame it rammed the loose boxes at every step.
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
	var pose_node: Node = net_pose(p)
	if pose_node == null:
		p.global_position = truck * p.net_position if riding else p.net_position
		return
	var pose: Transform3D = pose_node.drawn(p.net_position, riding, truck)
	p.global_position = pose.origin
	p.global_rotation = Vector3(0.0, pose_node.yaw_of(pose), 0.0)


## The player's PlayerNetPose (player.tscn), or null on a bare test player.
static func net_pose(p: Player) -> Node:
	return p.get_node_or_null(^"PlayerNetPose")


## Host: extra reach for this player's requests (PlayerNetPose.reach_slack()).
static func reach_slack(p: Player) -> float:
	var pose_node: Node = net_pose(p)
	return float(pose_node.reach_slack(p.get_multiplayer_authority())) if pose_node != null else 0.0


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
	var pose_node: Node = net_pose(p)
	if pose_node != null:
		pose_node.publish(p, vehicle, riding)


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
