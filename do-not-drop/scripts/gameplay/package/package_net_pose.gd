class_name PackageNetPose
extends RefCounted
## Where a box is drawn on a peer that doesn't simulate it, or that does but shouldn't draw it where it simulates it
## (N-217). One per DeliveryPackage (`_net_view`); split out of package.gd like package_handling.gd.
##
## - **Loose or shelved, on a client:** the host's poses (net_transform, in the truck's space while aboard) go into
##   a NetPoseSmoother on every synced packet (the synchronizer's `synchronized`) and the box is drawn a touch in
##   the past, interpolated, on this peer's truck if it rides: with several, the one the host names (net_vehicle,
##   D-0302.2.b.4.b, DeliveryPackage._find_vehicle()).
## - **In a remote carrier's hands, on every peer but the carrier's:** drawn in the hands of the carrier's body as
##   this peer draws it (`carrier_peer_id`: a Player on foot holds it), where that player's own code holds it
##   (PlayerCarry.hands_pose(): from the head's turn the player's pose carries and the lift since pick_up). The
##   carrier's body is drawn from its own buffer, 50-200 ms in the past, and the box rides it. The host keeps
##   simulating it at the newest carry pose (re-applied every tick, PackageHandling), held boxes don't collide, and
##   between ticks it's drawn on the body.
## - **In the carrier's own hands:** predicted (DeliveryPackage.predict_carry), on the carrier's own vehicle.
## - **Muted (D-2002.5):** held that way (muted()), the host sends the box's pose only every
##   NetRestThrottle.muted_interval (package.gd _publish_net_state()): every peer draws it on the hands anyway. What
##   arrives meanwhile (that trickle, a pose sent just before) is where the hands were, not where it'll be let go:
##   not buffered, and the buffer is stale (`_stale`) until the first pose after the hold starts it over.
## - **Let go** (dropped, handed over, sat down with it): until a fresh pose of the host's lands, it stays where it
##   was drawn, in the space of the vehicle the hands rode if it carries it there (the carrier's, not the box's
##   net_vehicle, stale while muted: a box let go of in the bay of a moving truck rides on with it instead of
##   hanging behind); then the gap from there to the host's copy (a round trip and a cushion behind the hands) is
##   carried over and eased out in DROP_BLEND_SECONDS instead of snapping. The carrier's own client did that since
##   N-217; the others, since D-2002.5 (before, the host's poses of the hold were in their buffer). The carrier's
##   own client between two predictions while still muted (a menu open skips update_carried_package()) draws it in
##   its player's hands.

## How long a box let go of takes to ease from where it was drawn in the hands to where the host has it.
const DROP_BLEND_SECONDS: float = 0.25

var smoother: NetPoseSmoother = null
var _carrier: Player = null
var _following: bool = false
## The last frame it was placed here, it was in someone's hands (followed or predicted).
var _was_in_hands: bool = false
## The buffer holds only poses of a muted hold, or from before it: the next fresh one starts it over.
var _stale: bool = false
## Stale and not in anyone's hands here: where it stays, in `_held_vehicle`'s space (null: the world's).
var _holding: bool = false
var _held_vehicle: Node3D = null
var _held_pose := Transform3D.IDENTITY
## The last frame the box was drawn in someone's hands: whether it was, the vehicle those hands rode (null: none)
## and that vehicle as drawn then.
var _hands_drawn: bool = false
var _hands_vehicle: Node3D = null
var _hands_truck := Transform3D.IDENTITY
var _error_origin := Vector3.ZERO
var _error_rotation := Quaternion.IDENTITY
var _error_left: float = 0.0


## Whether the host sends `p`'s pose only now and then: in the hands of a player on foot (carrier_peer_id), whom
## every other peer draws it on. The host mutes its synchronizer on this same test (package.gd
## _publish_net_state()); a client reads it from the same replicated pair (is_held, carrier_peer_id).
static func muted(p: DeliveryPackage) -> bool:
	return p.is_held and p.carrier_peer_id > 0


## Client: the host's newest pose into the buffer (a whole synced packet has landed). One of a muted hold isn't.
func push(p: DeliveryPackage, now: float = NetPoseSmoother.local_now()) -> void:
	if muted(p):
		_stale = true
		return
	if smoother == null:
		smoother = NetPoseSmoother.new()
		var network: Node = p.get_node_or_null(^"/root/NetworkManager")
		if network != null and network.has_method(&"pose_net_sim"):
			smoother.configure_sim(network.call(&"pose_net_sim"))
	if _stale:
		_stale = false
		smoother.clear()
	smoother.push(p.net_time / 1000.0, p.net_transform, now, p.net_in_vehicle)


## The Player holding the box on foot whom this peer doesn't control, or null. Null too while the copy is hidden
## (a far company box, CompanyInterest): a stale copy stays at its last pose instead of following a carrier.
func remote_carrier(p: DeliveryPackage) -> Player:
	if not p.visible:
		return null
	var carrier: Player = _carrier_of(p)
	return carrier if carrier != null and not carrier.is_local() else null


## The Player on foot holding the box (carrier_peer_id), this peer's or another's, or null. Only a player of the
## box's own session counts (a test runs several in one tree). Seated here already (its seat came before the
## host's carrier_peer_id 0): null, the box goes on the lap with the host's poses.
func _carrier_of(p: DeliveryPackage) -> Player:
	if not muted(p):
		return null
	if not is_instance_valid(_carrier) or _carrier.get_multiplayer_authority() != p.carrier_peer_id:
		_carrier = null
		for node: Node in p.get_tree().get_nodes_in_group(&"player"):
			if node is Player and node.get_multiplayer_authority() == p.carrier_peer_id \
					and node.multiplayer == p.multiplayer:
				_carrier = node as Player
				break
	if _carrier == null or not _carrier.seat_node_path.is_empty():
		return null
	return _carrier


## In the hands of a remote carrier's body as this peer draws it, when one holds the box on foot; false when nobody
## does. The carrier's own _process calls it too, right after placing the body (Player.Ride.apply_net_state), so the
## box and the hands' IK come from this frame's body whichever of the two is processed first.
func follow(p: DeliveryPackage) -> bool:
	var carrier: Player = remote_carrier(p)
	if carrier == null:
		if _following:
			_following = false
			if p.is_multiplayer_authority():
				p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
				p.reset_physics_interpolation()
		return false
	if not _following:
		_following = true
		p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# In the body's space, then on the body as drawn: a rider of the host's (interpolated) truck is drawn between
	# its ticks.
	var hands: Transform3D = carrier._carry_component.hands_pose(p)
	p.global_transform = _drawn(carrier) * (carrier.global_transform.affine_inverse() * hands)
	_stale = true
	_in_hands(carrier._find_vehicle())
	return true


## Every frame, on every peer (package.gd _process).
func draw(p: DeliveryPackage, delta: float, now: float = NetPoseSmoother.local_now()) -> void:
	if follow(p) or p.is_multiplayer_authority():
		return
	if muted(p):
		_stale = true
	var predicted: bool = Engine.get_physics_frames() - p._predicted_frame <= DeliveryPackage.PREDICTION_FRAMES
	var vehicle: Node3D = p._find_vehicle()
	if predicted:
		# In the space of the carrier's own vehicle (D-0302.2.b.4.b): the host may not have the box in it yet.
		var hands_on: Node3D = p._predicted_vehicle if is_instance_valid(p._predicted_vehicle) else vehicle
		var hands: Transform3D = p._predicted_pose
		p.global_transform = _drawn(hands_on) * hands if p._predicted_in_vehicle and hands_on != null else hands
		_in_hands(hands_on)
		return
	if _stale:
		_hold(p, vehicle)
		return
	if not p._has_net_state:
		return
	var was: Transform3D = _last_drawn(p)
	_holding = false
	_hands_drawn = false
	var vehicle_pose: Transform3D = _drawn(vehicle) if vehicle != null else Transform3D.IDENTITY
	var pose: Transform3D = Transform3D.IDENTITY
	if smoother != null and not smoother.is_empty():
		pose = smoother.sample(now, vehicle_pose)
	if pose == Transform3D.IDENTITY:
		pose = vehicle_pose * p.net_transform if p.net_in_vehicle and vehicle != null else p.net_transform
	if _was_in_hands:
		# Just let go of: where it was drawn (in the hands, or held since) minus where the host's copy is drawn.
		_was_in_hands = false
		_error_origin = was.origin - pose.origin
		var drawn_rotation: Quaternion = was.basis.get_rotation_quaternion()
		_error_rotation = drawn_rotation * pose.basis.get_rotation_quaternion().inverse()
		_error_left = DROP_BLEND_SECONDS
	if _error_left > 0.0:
		_error_left = maxf(_error_left - delta, 0.0)
		var share: float = _error_left / DROP_BLEND_SECONDS
		pose.origin += _error_origin * share
		pose.basis = Basis(Quaternion.IDENTITY.slerp(_error_rotation, share)) * pose.basis
	p.global_transform = pose


## Stale (let go of after a muted hold, or held where no hands can be drawn): until the host's first fresh pose,
## where it was drawn, riding the vehicle the hands last rode if it carries it there (in its space as drawn that
## frame: a frame at 20 m/s is a third of a metre), with none drawn the box's own (`vehicle`); in the hands of this
## peer's own player while that player still holds it and isn't predicting it this tick (a menu open skips
## update_carried_package()).
func _hold(p: DeliveryPackage, vehicle: Node3D) -> void:
	var own: Player = _carrier_of(p)
	if own != null and own.is_local() and own.carried_package == p:
		p.global_transform = own._carry_component.hands_pose(p)
		_in_hands(own._find_vehicle())
		return
	if not _holding:
		var was: Transform3D = _last_drawn(p)
		var under: Node3D = _hands_vehicle if _hands_drawn else vehicle
		_holding = true
		_held_vehicle = under if _carries(under, was.origin) else null
		_held_pose = _drawn(_held_vehicle).affine_inverse() * was if _held_vehicle != null else was
	p.global_transform = _drawn(_held_vehicle) * _held_pose if is_instance_valid(_held_vehicle) else _held_pose


## Where it was drawn last frame, as of this frame: carried on by its vehicle's motion since if it rode in the bay
## (held there, or in hands there); else where it is. A frame at 20 m/s is a third of a metre.
func _last_drawn(p: DeliveryPackage) -> Transform3D:
	if _holding:
		return _drawn(_held_vehicle) * _held_pose if is_instance_valid(_held_vehicle) else _held_pose
	if _hands_drawn and is_instance_valid(_hands_vehicle):
		var now_pose: Transform3D = _drawn(_hands_vehicle)
		var local: Transform3D = _hands_truck.affine_inverse() * p.global_transform
		if _carries(_hands_vehicle, (now_pose * local).origin):
			return now_pose * local
	return p.global_transform


## Drawn in someone's hands this frame, those hands riding `vehicle` (null: none), as it is drawn now.
func _in_hands(vehicle: Node3D) -> void:
	_was_in_hands = true
	_holding = false
	_hands_drawn = true
	_hands_vehicle = vehicle
	_hands_truck = _drawn(vehicle) if vehicle != null else Transform3D.IDENTITY
	_error_left = 0.0


## Whether `vehicle` (a truck, by name: vehicle.gd has no class name) carries `point` in its bay.
static func _carries(vehicle: Node3D, point: Vector3) -> bool:
	return is_instance_valid(vehicle) and vehicle.has_method(&"carries") \
			and bool(vehicle.call(&"carries", point, DeliveryPackage.RIDE_MARGIN))


## Where a node is drawn this frame (a frozen client truck isn't interpolated: see Player.Ride.drawn_transform).
static func _drawn(node: Node3D) -> Transform3D:
	if node.is_physics_interpolated_and_enabled():
		return node.get_global_transform_interpolated()
	return node.global_transform
