extends RefCounted
class_name NetPredictionReconciler
## The client's side of a body it predicts but the host owns: what it
## predicted after each of its numbered inputs, compared with what the host
## says it had after the same input, and the difference eased into the body.
##
## The client runs the body ahead with its own inputs, so it answers them in
## the same tick instead of a round trip later. Each tick it records the
## state its last step left (record(), keyed by the input that step used). The
## host's state comes back a round trip later stamped with the input it
## stands for (NetInputBuffer.tick_seq()); reconcile() looks up the client's
## own state after that input and keeps the difference as an error still to
## correct. step() hands back, every tick, the share of that error to add to
## the body now: about POSITION_TIME of easing for position, a quicker
## ROTATION_TIME for the heading, never more than MAX_STEP or MAX_TURN_STEP a
## tick, nothing under the dead zones (a few centimetres is the noise of two
## physics engines, not a mistake worth chasing). Velocity only gets a slow
## pull (VELOCITY_TIME) once it is clearly off (DEAD_VELOCITY: something only
## the host felt, a drag or a hit): a vehicle's velocity shakes with its
## suspension every tick, and chasing that with a round trip of delay rocks
## the body instead of steadying it (measured: positions 30x further apart).
##
## No re-simulation: physics engines like Jolt can't step one body back and
## forth on its own. What is corrected is shifted into every state still in
## the history too, so the next comparison measures only what is left, never
## the same error twice.
##
## - **Snap:** an error past SNAP_DISTANCE or SNAP_ANGLE (a reset, a rescue,
##   something only the host knows moved it) is corrected whole, in one tick,
##   and counted in `snaps`; a nudge() that far, in `start_snaps`.
## - **Lost track:** host states for inputs older than anything kept, the
##   history full, UNMATCHED_LIMIT times in a row (a link stalled for seconds):
##   it snaps to the host's state as it is, against the newest one kept.
## - Host states for inputs not yet recorded, or from before the history
##   started (a new prediction session), are ignored.

## States kept: 3 s of 60 Hz ticks, longer than any round trip worth predicting through.
const HISTORY_SIZE: int = 180
## Time constants of the easing (s): the error left after t is exp(-t / this),
## so position is ~92 % corrected in 150 ms, rotation sooner, velocity slowly.
const POSITION_TIME: float = 0.06
const ROTATION_TIME: float = 0.04
const VELOCITY_TIME: float = 0.5
## Largest correction per tick (60 Hz): 10 cm, 3 degrees, 1 m/s, 0.3 rad/s.
const MAX_STEP: float = 0.1
const MAX_TURN_STEP: float = 0.0524
const MAX_VELOCITY_STEP: float = 1.0
const MAX_SPIN_STEP: float = 0.3
## Errors smaller than these are left alone.
const DEAD_POSITION: float = 0.02
const DEAD_ANGLE: float = 0.0087
const DEAD_VELOCITY: float = 0.5
const DEAD_SPIN: float = 0.2
## Errors bigger than these are corrected at once.
const SNAP_DISTANCE: float = 3.0
const SNAP_ANGLE: float = 0.785
const UNMATCHED_LIMIT: int = 30

## [seq, Transform3D, linear_velocity, angular_velocity], oldest first.
var _history: Array = []
var _position_error := Vector3.ZERO
var _rotation_error := Quaternion.IDENTITY
var _velocity_error := Vector3.ZERO
var _spin_error := Vector3.ZERO
var _snap: bool = false
## The snap pending is a nudge()'s, not a measured error's.
var _snap_nudged: bool = false
var _unmatched: int = 0
var _matched_seq: int = -1
## The size of the last error measured (m), for tests and the network overlay.
var last_error: float = 0.0
## How many measured errors were snapped instead of eased: the prediction went
## wrong by that much (or the host moved the body).
var snaps: int = 0
## How many nudge()s were snapped instead of eased (a start far from where the
## body should be: the controls taken back at speed while it is still drawn
## ahead of the host's poses, a jittery link). No prediction went wrong there,
## so they don't count as `snaps` (N-922.9).
var start_snaps: int = 0


## The state the last step left, after the input numbered `seq`.
func record(seq: int, pose: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3) -> void:
	if not _history.is_empty():
		var newest: int = int(_history[-1][0])
		if seq == newest:
			_history[-1] = [seq, pose, linear_velocity, angular_velocity]
			return
		if seq < newest:
			clear()
	_history.append([seq, pose, linear_velocity, angular_velocity])
	while _history.size() > HISTORY_SIZE:
		_history.pop_front()


## The host's state after the input numbered `seq`. False when there's nothing
## of ours to compare it with.
func reconcile(seq: int, pose: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3) -> bool:
	if _history.is_empty() or seq < _matched_seq:
		return false
	if seq < int(_history[0][0]):
		if _history.size() >= HISTORY_SIZE:
			_unmatched += 1
			if _unmatched >= UNMATCHED_LIMIT:
				_unmatched = 0
				_measure(_history[-1], pose, linear_velocity, angular_velocity)
				_snap = true
				_snap_nudged = false
		return false
	if seq > int(_history[-1][0]):
		return false
	_unmatched = 0
	var at: int = 0
	while at + 1 < _history.size() and int(_history[at + 1][0]) <= seq:
		at += 1
	# Older states are done with; the matched one stays (the host may stand
	# for it again).
	for _drop: int in range(at):
		_history.pop_front()
	_matched_seq = seq
	if _snap_nudged:
		# The error a nudge() put in is replaced by this one, and so is its snap.
		_snap = false
		_snap_nudged = false
	_measure(_history[0], pose, linear_velocity, angular_velocity)
	if _position_error.length() > SNAP_DISTANCE or _rotation_error.get_angle() > SNAP_ANGLE:
		_snap = true
	return true


## An error known before any host state measures it: the body was put
## somewhere else than where it should be (started where it is drawn, a
## cushion behind the host's newest pose), and is eased there like a measured
## error, snapped past SNAP_DISTANCE or SNAP_ANGLE (counted in start_snaps, not
## snaps). A host state measured later replaces it: what is left of it is part
## of what that one measures.
func nudge(position: Vector3, rotation: Quaternion = Quaternion.IDENTITY) -> void:
	_position_error += position
	_rotation_error = (rotation * _rotation_error).normalized()
	if not _snap and (_position_error.length() > SNAP_DISTANCE or _rotation_error.get_angle() > SNAP_ANGLE):
		_snap = true
		_snap_nudged = true


func _measure(ours: Array, pose: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3) -> void:
	var predicted: Transform3D = ours[1]
	_position_error = pose.origin - predicted.origin
	_rotation_error = (pose.basis.get_rotation_quaternion()
			* predicted.basis.get_rotation_quaternion().inverse()).normalized()
	_velocity_error = linear_velocity - (ours[2] as Vector3)
	_spin_error = angular_velocity - (ours[3] as Vector3)
	last_error = _position_error.length()


## This tick's correction, to add to the body before it steps:
## [position shift, rotation (world, about the body's origin), linear velocity
## shift, angular velocity shift]. Already shifted into the history.
func step(delta: float) -> Array:
	var shift := Vector3.ZERO
	var turn := Quaternion.IDENTITY
	var push := Vector3.ZERO
	var spin := Vector3.ZERO
	if _snap:
		_snap = false
		if _snap_nudged:
			start_snaps += 1
		else:
			snaps += 1
		_snap_nudged = false
		shift = _position_error
		turn = _rotation_error
		push = _velocity_error
		spin = _spin_error
	else:
		shift = _eased(_position_error, DEAD_POSITION, POSITION_TIME, MAX_STEP, delta)
		push = _eased(_velocity_error, DEAD_VELOCITY, VELOCITY_TIME, MAX_VELOCITY_STEP, delta)
		spin = _eased(_spin_error, DEAD_SPIN, VELOCITY_TIME, MAX_SPIN_STEP, delta)
		var angle: float = _rotation_error.get_angle()
		if angle > DEAD_ANGLE:
			var share: float = minf(angle * (1.0 - exp(-delta / ROTATION_TIME)), MAX_TURN_STEP) / angle
			turn = Quaternion.IDENTITY.slerp(_rotation_error, share).normalized()
	_position_error -= shift
	_rotation_error = (_rotation_error * turn.inverse()).normalized()
	_velocity_error -= push
	_spin_error -= spin
	if shift != Vector3.ZERO or turn != Quaternion.IDENTITY or push != Vector3.ZERO or spin != Vector3.ZERO:
		var turned := Basis(turn)
		for entry: Array in _history:
			var pose: Transform3D = entry[1]
			entry[1] = Transform3D(turned * pose.basis, pose.origin + shift)
			entry[2] = (entry[2] as Vector3) + push
			entry[3] = (entry[3] as Vector3) + spin
	return [shift, turn, push, spin]


static func _eased(error: Vector3, dead: float, time: float, most: float, delta: float) -> Vector3:
	if error.length() <= dead:
		return Vector3.ZERO
	return (error * (1.0 - exp(-delta / time))).limit_length(most)


## The position error still to correct (m).
func pending_distance() -> float:
	return _position_error.length()


func history_size() -> int:
	return _history.size()


func clear() -> void:
	_history.clear()
	_position_error = Vector3.ZERO
	_rotation_error = Quaternion.IDENTITY
	_velocity_error = Vector3.ZERO
	_spin_error = Vector3.ZERO
	_snap = false
	_snap_nudged = false
	_unmatched = 0
	_matched_seq = -1
	last_error = 0.0
