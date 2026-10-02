class_name VehiclePrediction
extends RefCounted
## The truck driven by a client, without the round trip (N-218, Fase 3 of docs/investigacion-red.md). One per truck
## (vehicle.gd `_prediction`), on every peer; split out of vehicle.gd like PackageNetPose out of package.gd.
##
## Before: the client at the wheel sent its input to the host and saw the truck answer a ping plus the pose
## buffer later (100 ms and more). Now:
## - **The driver's client** unfreezes its copy of the truck and simulates it with its own input the same tick,
##   numbering every tick's input and sending it to the host (submit_driver_input). Its state after each input
##   goes into a NetPredictionReconciler; the host's state comes back stamped with the input it stands for
##   (net_input_seq), is compared with the client's own state after that input, and the difference is eased
##   into the truck (position in ~150 ms, heading sooner, at most 10 cm a tick, snapped past 3 m), without
##   re-simulating: Jolt can't step one body on its own.
## - **The host** plays the driver's inputs back one per physics tick from a NetInputBuffer (a cushion of two
##   against jitter, the last one held through a loss), so its pose says exactly which input it stands for.
##   The host stays the authority: its truck carries the boxes, the shell and every rule; nothing the client
##   predicts is believed.
## - **Everyone else** draws the host's truck from the pose buffer as before (NetPoseSmoother).
##
## The boxes stay on the host; on the driver's client they are drawn in the space of its truck
## (PackageNetPose, `net_in_vehicle`), so they ride along with the prediction. Riders and boxes judge the truck
## by whether it is interpolated (Player.Ride.drawn_transform): a predicting copy is simulated, unfrozen and
## interpolated, so they take the host's path on it.
##
## Only while the host's truck is simulated too (`net_simulating`: not frozen for loading, parking or the end of
## a run). When the client stops driving (left the seat, someone else took the wheel, the host froze the truck)
## its copy is frozen again and drawn from the pose buffer, the gap eased out in EXIT_BLEND_SECONDS.
##
## `--no-drive-prediction` turns it off on that client (to compare, or if it misbehaves).

const EXIT_BLEND_SECONDS: float = 0.3
const EXIT_BLEND_MAX_DISTANCE: float = 30.0

var enabled: bool = not OS.get_cmdline_user_args().has("--no-drive-prediction")
## Whether this peer's copy is the one predicting right now.
var active: bool = false
var reconciler := NetPredictionReconciler.new()
## Host: the remote driver's inputs.
var inputs := NetInputBuffer.new()
## The input number the last physics step used (host: the buffer's tick; client: its own count). Replicated
## as net_input_seq.
var applied_seq: int = 0
## Client: the last input sent to the host, [seq, throttle, steering, handbrake] (for tests).
var last_sent: Array = []
## Client: how far the last tick's correction moved the truck (m), for tests and the network overlay.
var last_shift: float = 0.0
var _next_seq: int = 0
var _was_local_driver: bool = false
## Something on this peer froze the predicting copy (the level, at the end of a run): no starting again until
## prediction stops being wanted at least once.
var _held_off: bool = false
var _exit_origin := Vector3.ZERO
var _exit_rotation := Quaternion.IDENTITY
var _exit_left: float = 0.0


## Whether this peer is a client holding the wheel of `vehicle` (the host never predicts its own truck).
static func is_remote_driver_here(vehicle: VehicleBody3D) -> bool:
	if vehicle.is_multiplayer_authority():
		return false
	var driver: int = int(vehicle.get(&"driver_peer_id"))
	return driver != 0 and driver == vehicle.multiplayer.get_unique_id()


## Host: whether the wheel is held by a peer other than the host.
static func driven_remotely(vehicle: VehicleBody3D) -> bool:
	var driver: int = int(vehicle.get(&"driver_peer_id"))
	return driver != 0 and driver != vehicle.multiplayer.get_unique_id()


## Host, each physics tick before the truck's forces: the remote driver's input for this tick.
func host_tick(vehicle: VehicleBody3D) -> void:
	if not driven_remotely(vehicle):
		return
	var entry: Array = inputs.consume()
	if entry.is_empty():
		return
	var data: Array = entry[1]
	vehicle.call(&"set_controls", float(data[0]), float(data[1]), bool(data[2]))
	applied_seq = int(entry[0])


## Host: an input from the driver (already checked: sender, finite numbers).
func receive(seq: int, throttle: float, steering_input: float, handbrake: bool) -> void:
	inputs.push(seq, [throttle, steering_input, handbrake])


## Host: the wheel changed hands.
func driver_changed() -> void:
	inputs.clear()


## Client, each physics tick, before the truck's forces. Sends this tick's input while this peer drives,
## starts or stops predicting, records the state the last step left and adds this tick's correction.
## True while predicting: the caller runs the truck's forces.
func client_tick(vehicle: VehicleBody3D, delta: float, smoother: NetPoseSmoother, host_velocity: Vector3,
		host_spin: Vector3, host_simulating: bool) -> bool:
	var driving: bool = is_remote_driver_here(vehicle)
	if driving != _was_local_driver:
		_was_local_driver = driving
		# Whatever the last session at the wheel left in the controls doesn't carry over.
		vehicle.call(&"set_controls", 0.0, 0.0, false)
	var wanted: bool = enabled and driving and host_simulating and smoother != null and not smoother.is_empty()
	if not wanted:
		_held_off = false
	var started: bool = false
	if active and (not wanted or vehicle.freeze):
		_held_off = wanted
		_stop(vehicle, smoother)
	elif not active and wanted and not _held_off:
		_start(vehicle, smoother, host_velocity, host_spin)
		started = true
	if not driving:
		return false
	if active and not started:
		reconciler.record(applied_seq, vehicle.global_transform, vehicle.linear_velocity, vehicle.angular_velocity)
		_correct(vehicle, delta)
	_next_seq += 1
	applied_seq = _next_seq
	var throttle: float = float(vehicle.get(&"_throttle"))
	var steering_input: float = float(vehicle.get(&"_steering_input"))
	var handbrake: bool = bool(vehicle.get(&"_handbrake"))
	last_sent = [applied_seq, throttle, steering_input, handbrake]
	var peer: MultiplayerPeer = vehicle.multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		vehicle.rpc_id(1, &"submit_driver_input", applied_seq, throttle, steering_input, handbrake)
	return active


## Client: the host's state after input `seq` (a whole synced packet).
func host_state(seq: int, pose: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3) -> void:
	if active:
		reconciler.reconcile(seq, pose, linear_velocity, angular_velocity)


func _correct(vehicle: VehicleBody3D, delta: float) -> void:
	var correction: Array = reconciler.step(delta)
	var shift: Vector3 = correction[0]
	var turn: Quaternion = correction[1]
	last_shift = shift.length()
	if shift != Vector3.ZERO or turn != Quaternion.IDENTITY:
		var pose: Transform3D = vehicle.global_transform
		vehicle.global_transform = Transform3D(Basis(turn) * pose.basis, pose.origin + shift)
	var push: Vector3 = correction[2]
	var spin: Vector3 = correction[3]
	if push != Vector3.ZERO or spin != Vector3.ZERO:
		# On the body's live state, not through `linear_velocity`: that is the copy RigidBody3D took before
		# VehicleBody3D added this step's suspension and tyre impulses, and writing it back would undo them
		# (the truck sank onto its chassis).
		var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(vehicle.get_rid())
		if state != null:
			state.linear_velocity += push
			state.angular_velocity += spin


func _start(vehicle: VehicleBody3D, smoother: NetPoseSmoother, host_velocity: Vector3, host_spin: Vector3) -> void:
	active = true
	_exit_left = 0.0
	reconciler.clear()
	# From the newest pose the host sent, not the one drawn a cushion behind it.
	var latest: Transform3D = smoother.latest_pose()
	if latest != Transform3D.IDENTITY:
		vehicle.global_transform = latest
	vehicle.freeze = false
	vehicle.linear_velocity = host_velocity
	vehicle.angular_velocity = host_spin
	vehicle.sleeping = false


func _stop(vehicle: VehicleBody3D, smoother: NetPoseSmoother) -> void:
	active = false
	reconciler.clear()
	vehicle.freeze = true
	if smoother == null or smoother.is_empty():
		return
	# Where it's drawn now minus where the pose buffer has it: eased out instead of jumping back a round trip.
	var buffered: Transform3D = smoother.sample(NetPoseSmoother.local_now())
	if buffered == Transform3D.IDENTITY:
		return
	_exit_origin = vehicle.global_transform.origin - buffered.origin
	_exit_rotation = (vehicle.global_basis.get_rotation_quaternion()
			* buffered.basis.get_rotation_quaternion().inverse()).normalized()
	# Moving, the buffer is a round trip and a cushion behind (7 m at 50 km/h on 150 ms): eased all the same.
	# Only something much further (the host moved the truck) jumps.
	_exit_left = EXIT_BLEND_SECONDS if _exit_origin.length() < EXIT_BLEND_MAX_DISTANCE else 0.0


## Client, not predicting: the buffered pose with what is left of the gap from when prediction stopped.
func blend_exit(pose: Transform3D, delta: float) -> Transform3D:
	if _exit_left <= 0.0:
		return pose
	_exit_left = maxf(_exit_left - delta, 0.0)
	var share: float = _exit_left / EXIT_BLEND_SECONDS
	return Transform3D(Basis(Quaternion.IDENTITY.slerp(_exit_rotation, share)) * pose.basis,
			pose.origin + _exit_origin * share)
