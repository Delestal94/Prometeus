class_name PackageNetPose
extends RefCounted
## Where a box is drawn on a peer that doesn't simulate it, or that does but shouldn't draw it where it simulates it
## (N-217). One per DeliveryPackage (`_net_view`); split out of package.gd like package_handling.gd.
##
## - **Loose or shelved, on a client:** the host's poses (net_transform, in the truck's space while aboard) go into
##   a NetPoseSmoother on every synced packet (the synchronizer's `synchronized`) and the box is drawn a touch in
##   the past, interpolated, on this peer's truck if it rides.
## - **In a remote carrier's hands, on every peer but the carrier's:** drawn in the hands of the carrier's body as
##   this peer draws it (`carrier_peer_id`: a Player on foot holds it), where that player's own code holds it
##   (PlayerCarry.hands_pose(): from the head's turn the player's pose carries and the lift since pick_up). The
##   carrier's body is drawn from its own buffer, 50-200 ms in the past, and the box rides it. The host keeps
##   simulating it at the newest carry pose (re-applied every tick, PackageHandling), held boxes don't collide, and
##   between ticks it's drawn on the body.
## - **In the carrier's own hands:** predicted (DeliveryPackage.predict_carry).
## - **Muted (D-2002.5):** held that way (muted()), the host sends the box's pose only every
##   NetRestThrottle.muted_interval (package.gd _publish_net_state()): every peer draws it on the hands anyway. What
##   arrives meanwhile (that trickle, a pose sent just before) is where the hands were, not where it'll be let go:
##   not buffered, and the buffer is stale (`_stale`) until the first pose after the hold starts it over.
## - **Let go** (dropped, handed over, sat down with it): until a fresh pose of the host's lands, it stays where it
##   was drawn; then the gap from there to the host's copy (a round trip and a cushion behind the hands) is carried
##   over and eased out in DROP_BLEND_SECONDS instead of snapping. The carrier's own client did that since N-217;
##   the others, since D-2002.5 (before, the host's poses of the hold were in their buffer).

## How long a box let go of takes to ease from where it was drawn in the hands to where the host has it.
const DROP_BLEND_SECONDS: float = 0.25

var smoother: NetPoseSmoother = null
var _carrier: Player = null
var _following: bool = false
## The last frame it was placed here, it was in someone's hands (followed or predicted).
var _was_in_hands: bool = false
## The buffer holds only poses of a muted hold, or from before it: the next fresh one starts it over.
var _stale: bool = false
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
## (a far company box, CompanyInterest): a stale copy stays at its last pose instead of following a carrier. Only
## a player of the box's own session counts (a test runs several in one tree).
func remote_carrier(p: DeliveryPackage) -> Player:
	if not p.visible or not muted(p):
		return null
	if not is_instance_valid(_carrier) or _carrier.get_multiplayer_authority() != p.carrier_peer_id:
		_carrier = null
		for node: Node in p.get_tree().get_nodes_in_group(&"player"):
			if node is Player and node.get_multiplayer_authority() == p.carrier_peer_id \
					and node.multiplayer == p.multiplayer:
				_carrier = node
				break
	# Seated here already (its seat came before the host's carrier_peer_id 0): the box goes on the lap with the
	# host's poses.
	if _carrier == null or _carrier.is_local() or not _carrier.seat_node_path.is_empty():
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
	_was_in_hands = true
	_stale = true
	_error_left = 0.0
	return true


## Every frame, on every peer (package.gd _process).
func draw(p: DeliveryPackage, delta: float, now: float = NetPoseSmoother.local_now()) -> void:
	if follow(p) or p.is_multiplayer_authority():
		return
	if muted(p):
		_stale = true
	var predicted: bool = Engine.get_physics_frames() - p._predicted_frame <= DeliveryPackage.PREDICTION_FRAMES
	if not predicted and not p._has_net_state:
		return
	var vehicle: Node3D = p._find_vehicle()
	var vehicle_pose: Transform3D = _drawn(vehicle) if vehicle != null else Transform3D.IDENTITY
	if predicted:
		var hands: Transform3D = p._predicted_pose
		p.global_transform = vehicle_pose * hands if p._predicted_in_vehicle and vehicle != null else hands
		_was_in_hands = true
		_error_left = 0.0
		return
	if _stale:
		# Let go of after a muted hold (or held where the hands can't be drawn): where it was, until the host's
		# first fresh pose.
		return
	var pose: Transform3D = Transform3D.IDENTITY
	if smoother != null and not smoother.is_empty():
		pose = smoother.sample(now, vehicle_pose)
	if pose == Transform3D.IDENTITY:
		pose = vehicle_pose * p.net_transform if p.net_in_vehicle and vehicle != null else p.net_transform
	if _was_in_hands:
		# Just let go of: where it was drawn (in the hands) minus where the host's copy is drawn.
		_was_in_hands = false
		_error_origin = p.global_transform.origin - pose.origin
		var drawn_rotation: Quaternion = p.global_transform.basis.get_rotation_quaternion()
		_error_rotation = drawn_rotation * pose.basis.get_rotation_quaternion().inverse()
		_error_left = DROP_BLEND_SECONDS
	if _error_left > 0.0:
		_error_left = maxf(_error_left - delta, 0.0)
		var share: float = _error_left / DROP_BLEND_SECONDS
		pose.origin += _error_origin * share
		pose.basis = Basis(Quaternion.IDENTITY.slerp(_error_rotation, share)) * pose.basis
	p.global_transform = pose


## Where a node is drawn this frame (a frozen client truck isn't interpolated: see Player.Ride.drawn_transform).
static func _drawn(node: Node3D) -> Transform3D:
	if node.is_physics_interpolated_and_enabled():
		return node.get_global_transform_interpolated()
	return node.global_transform
