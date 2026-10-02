class_name PackageNetPose
extends RefCounted
## Where a box is drawn on a peer that doesn't simulate it, or that does but shouldn't draw it where it simulates it
## (N-217). One per DeliveryPackage (`_net_view`); split out of package.gd like package_handling.gd.
##
## - **Loose or shelved, on a client:** the host's poses (net_transform, in the truck's space while aboard) go into
##   a NetPoseSmoother on every synced packet (the synchronizer's `synchronized`) and the box is drawn a touch in
##   the past, interpolated, on this peer's truck if it rides.
## - **In a remote carrier's hands, on every peer but the carrier's:** drawn on the carrier's body as this peer
##   draws it (`carrier_peer_id`, `hold_offset` in the body's space, sent by the carrier with each carry pose). The
##   carrier's body is drawn from its own buffer, 50-200 ms in the past; the box drawn from its newest carry pose,
##   or from its own buffer, floated up to 0.7 m off the hands at a walk. The host keeps simulating it at the newest
##   carry pose (re-applied every tick, PackageHandling), held boxes don't collide, and between ticks it's drawn on
##   the body.
## - **In the carrier's own hands:** predicted (DeliveryPackage.predict_carry). When the prediction ends (dropped,
##   handed over) the buffer is a round trip and a cushion behind the hands: the gap is carried over and eased
##   out in DROP_BLEND_SECONDS instead of snapping the box back.

## How long the carrier's own client takes to ease a dropped box from its hands to where the host has it.
const DROP_BLEND_SECONDS: float = 0.25
## Furthest from a carrier's body a box may be held and still be drawn on it (m): a bad offset is ignored.
const MAX_HOLD_REACH: float = 2.5

var smoother: NetPoseSmoother = null
var _carrier: Node3D = null
var _following: bool = false
var _was_predicted: bool = false
var _error_origin := Vector3.ZERO
var _error_rotation := Quaternion.IDENTITY
var _error_left: float = 0.0


## Client: the host's newest pose into the buffer (a whole synced packet has landed).
func push(p: DeliveryPackage, now: float = NetPoseSmoother.local_now()) -> void:
	if smoother == null:
		smoother = NetPoseSmoother.new()
		var network: Node = p.get_node_or_null(^"/root/NetworkManager")
		if network != null and network.has_method(&"pose_net_sim"):
			smoother.configure_sim(network.call(&"pose_net_sim"))
	smoother.push(p.net_time / 1000.0, p.net_transform, now, p.net_in_vehicle)


## The player holding the box on foot whom this peer doesn't control, or null.
func remote_carrier(p: DeliveryPackage) -> Node3D:
	# IDENTITY: the first pose with the hands' offset hasn't come in yet (carrier_peer_id goes by a reliable delta,
	# hold_offset with the poses).
	if p.carrier_peer_id <= 0 or not p.is_held or p.hold_offset == Transform3D.IDENTITY \
			or p.hold_offset.origin.length() > MAX_HOLD_REACH:
		return null
	if not is_instance_valid(_carrier) or _carrier.get_multiplayer_authority() != p.carrier_peer_id:
		_carrier = null
		for player: Node in p.get_tree().get_nodes_in_group(&"player"):
			if player.get_multiplayer_authority() == p.carrier_peer_id and player is Node3D:
				_carrier = player
				break
	if _carrier == null or (_carrier.has_method(&"is_local") and bool(_carrier.call(&"is_local"))):
		return null
	return _carrier


## On a remote carrier's body as this peer draws it, when one holds the box on foot; false when nobody does. The
## carrier's own _process calls it too, right after placing the body (Player.Ride.apply_net_state), so the box and
## the hands' IK come from this frame's body whichever of the two is processed first.
func follow(p: DeliveryPackage) -> bool:
	var carrier: Node3D = remote_carrier(p)
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
	p.global_transform = _drawn(carrier) * p.hold_offset
	_was_predicted = false
	_error_left = 0.0
	return true


## Every frame, on every peer (package.gd _process).
func draw(p: DeliveryPackage, delta: float, now: float = NetPoseSmoother.local_now()) -> void:
	if follow(p) or p.is_multiplayer_authority():
		return
	var predicted: bool = Engine.get_physics_frames() - p._predicted_frame <= DeliveryPackage.PREDICTION_FRAMES
	if not predicted and not p._has_net_state:
		return
	var vehicle: Node3D = p._find_vehicle()
	var vehicle_pose: Transform3D = _drawn(vehicle) if vehicle != null else Transform3D.IDENTITY
	if predicted:
		var hands: Transform3D = p._predicted_pose
		p.global_transform = vehicle_pose * hands if p._predicted_in_vehicle and vehicle != null else hands
		_was_predicted = true
		_error_left = 0.0
		return
	var pose: Transform3D = Transform3D.IDENTITY
	if smoother != null and not smoother.is_empty():
		pose = smoother.sample(now, vehicle_pose)
	if pose == Transform3D.IDENTITY:
		pose = vehicle_pose * p.net_transform if p.net_in_vehicle and vehicle != null else p.net_transform
	if _was_predicted:
		# Just stopped predicting: where it was drawn (in the hands) minus where the host's copy is drawn.
		_was_predicted = false
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
