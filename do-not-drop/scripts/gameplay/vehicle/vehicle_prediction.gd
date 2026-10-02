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
##   against jitter, the last one held through a loss, its pedal let go once stale), so its pose says exactly which
##   input it stands for.
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
## a run), and starting only once this peer has ground under it (has_ground, N-922.4). When the client stops
## driving (left the seat, someone else took the wheel, the host froze the truck) its copy is frozen again and
## drawn from the pose buffer, the gap eased out in EXIT_BLEND_SECONDS.
##
## `--no-drive-prediction` turns it off on that client (to compare, or if it misbehaves).

## vehicle.gd has no class_name; this preloads it for the type (N-224.4). It names autoloads, so a `--script`
## test that names VehiclePrediction at compile time fails to build: load it at run time instead.
const Vehicle = preload("res://scripts/gameplay/vehicle/vehicle.gd")
const EXIT_BLEND_SECONDS: float = 0.3
const EXIT_BLEND_MAX_DISTANCE: float = 30.0
## Forward speed (m/s) above which a throttle against the motion brakes; below it, it backs up (vehicle.gd _drive).
const BRAKING_SPEED: float = 0.7
## Prediction starts only over ground (has_ground): a ray from this far above the host's newest pose to this far
## below it (m), against the environment layer.
const GROUND_PROBE_ABOVE: float = 0.5
const GROUND_PROBE: float = 4.0
const GROUND_MASK: int = 1

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
## Client: the input number of the newest host state compared with its own (0 before any), for tests.
var host_seq: int = 0
## Client, `--net-sim` on LAN (N-922.5): the inputs it sends and the host's states it compares with, each held back
## half the profile's lag plus its jitter and lost at its rate, as the sockets would do it over Steam. Without them a
## LAN test with `--net-sim` only delayed the pose buffer, which the driver doesn't use: the prediction looked perfect.
var uplink := NetDelayQueue.new()
var downlink := NetDelayQueue.new()
var _next_seq: int = 0
var _was_local_driver: bool = false
## Something on this peer froze the predicting copy (the level, at the end of a run): no starting again until
## prediction stops being wanted at least once.
var _held_off: bool = false
var _exit_origin := Vector3.ZERO
var _exit_rotation := Quaternion.IDENTITY
var _exit_left: float = 0.0


## Whether this peer is a client holding the wheel of `vehicle` (the host never predicts its own truck).
static func is_remote_driver_here(vehicle: Vehicle) -> bool:
	if vehicle.is_multiplayer_authority():
		return false
	var driver: int = vehicle.driver_peer_id
	return driver != 0 and driver == vehicle.multiplayer.get_unique_id()


## Host: whether the wheel is held by a peer other than the host.
static func driven_remotely(vehicle: Vehicle) -> bool:
	var driver: int = vehicle.driver_peer_id
	return driver != 0 and driver != vehicle.multiplayer.get_unique_id()


## Host, each physics tick before the truck's forces: the remote driver's input for this tick.
func host_tick(vehicle: Vehicle) -> void:
	if not driven_remotely(vehicle):
		return
	var entry: Array = inputs.consume()
	if entry.is_empty():
		return
	var data: Array = entry[1]
	var throttle: float = float(data[0])
	if inputs.is_stale() and not _brakes(vehicle, throttle):
		# The driver went quiet without leaving (a hitch, a Wi-Fi drop): its last input held for good would keep
		# the truck flat out with the wheel turned. The pedal is let go -- unless it was braking, which goes on
		# until the truck stops (freewheeling downhill would be worse) and never turns into backing up. The wheel
		# and the handbrake stay as held.
		throttle = 0.0
	vehicle.set_controls(throttle, float(data[1]), bool(data[2]))
	applied_seq = int(entry[0])


## Whether `throttle` brakes the truck as it moves now: against the motion, while still rolling (vehicle.gd
## _drive; slower than that it would back up).
static func _brakes(vehicle: Vehicle, throttle: float) -> bool:
	var forward_speed: float = vehicle.linear_velocity.dot(-vehicle.global_basis.z)
	return throttle * forward_speed < 0.0 and absf(forward_speed) > BRAKING_SPEED


## Host: an input from the driver (already checked: sender, finite numbers).
func receive(seq: int, throttle: float, steering_input: float, handbrake: bool) -> void:
	inputs.push(seq, [throttle, steering_input, handbrake])


## The wheel changed hands (called on every peer: driver_peer_id is replicated). Host: the old driver's inputs are
## dropped, and until the new driver's first one plays the pose stands for no input (0; a client counts from 1),
## not for the old driver's last number, which the new driver's own count may reach and be corrected against.
## A client's applied_seq is its own count and goes on: reset there, a wheel that went elsewhere and back between
## two ticks would have its next state recorded under 0, which wipes the reconciler's history.
func driver_changed(vehicle: Vehicle) -> void:
	if not vehicle.is_inside_tree() or not vehicle.is_multiplayer_authority():
		return
	inputs.clear()
	applied_seq = 0


## The level stopped the run under this peer's copy (the host is gone, N-922): frozen where it is, the prediction
## over and not started again until it stops being wanted.
func halt(vehicle: Vehicle) -> void:
	active = false
	_held_off = true
	_exit_left = 0.0
	reconciler.clear()
	downlink.clear()
	uplink.clear()
	vehicle.freeze = true


## A `--net-sim` profile ({lag_ms, jitter_ms, loss_pct}) for the inputs this client sends and the host's states it
## compares with, half the lag each way; an empty one simulates nothing.
func configure_sim(sim: Dictionary) -> void:
	uplink.configure_sim(sim, 0.5)
	downlink.configure_sim(sim, 0.5)


## Client, each physics tick, before the truck's forces. Sends this tick's input while this peer drives,
## starts or stops predicting, records the state the last step left and adds this tick's correction.
## True while predicting: the caller runs the truck's forces.
func client_tick(vehicle: Vehicle, delta: float, smoother: NetPoseSmoother, host_velocity: Vector3,
		host_spin: Vector3, host_simulating: bool) -> bool:
	var now: float = NetPoseSmoother.local_now()
	# Inputs held back by --net-sim go out once their time has come, driving or not (they were on their way).
	for held: Variant in uplink.take(now):
		_send(vehicle, held)
	var driving: bool = is_remote_driver_here(vehicle)
	if driving != _was_local_driver:
		_was_local_driver = driving
		# Whatever the last session at the wheel left in the controls doesn't carry over.
		vehicle.set_controls(0.0, 0.0, false)
	var wanted: bool = enabled and driving and host_simulating and smoother != null and not smoother.is_empty()
	if not wanted:
		_held_off = false
	var started: bool = false
	if active and (not wanted or vehicle.freeze):
		_held_off = wanted
		_stop(vehicle, smoother)
	elif not active and wanted and not _held_off and has_ground(vehicle, smoother.latest_pose()):
		_start(vehicle, smoother, host_velocity, host_spin)
		started = true
	if not driving:
		return false
	if active and not started:
		reconciler.record(applied_seq, vehicle.global_transform, vehicle.linear_velocity, vehicle.angular_velocity)
		for state: Variant in downlink.take(now):
			_reconcile(state)
		_correct(vehicle, delta)
	_next_seq += 1
	applied_seq = _next_seq
	last_sent = [applied_seq, vehicle.throttle_input(), vehicle.steer_input(), vehicle.handbrake_input()]
	if uplink.is_active():
		uplink.push(last_sent, now)
	else:
		_send(vehicle, last_sent)
	return active


## Client: one input, [seq, throttle, steering, handbrake], to the host (nobody to send it to offline).
static func _send(vehicle: Vehicle, input: Array) -> void:
	var peer: MultiplayerPeer = vehicle.multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer and vehicle.is_inside_tree():
		vehicle.rpc_id(1, &"submit_driver_input", int(input[0]), float(input[1]), float(input[2]), bool(input[3]))


## Whether this peer's world has ground under `pose` (the newest one the host sent), within GROUND_PROBE metres
## (N-922.4). A client that takes the wheel as it comes back (N-221) or joins late into an endless run gets the
## host's pose before its streamer has built the road there (60 m a tick): its copy, unfrozen on nothing, fell
## through the world. Until there is ground it stays frozen and drawn from the pose buffer.
static func has_ground(vehicle: Vehicle, pose: Transform3D) -> bool:
	if not vehicle.is_inside_tree():
		return false
	var from: Vector3 = pose.origin + Vector3.UP * GROUND_PROBE_ABOVE
	var query := PhysicsRayQueryParameters3D.create(from, pose.origin + Vector3.DOWN * GROUND_PROBE, GROUND_MASK)
	query.exclude = [vehicle.get_rid()]
	return not vehicle.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Client: the host's state after input `seq` (a whole synced packet). Held back with --net-sim (downlink).
func host_state(seq: int, pose: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3) -> void:
	if not active:
		return
	var state: Array = [seq, pose, linear_velocity, angular_velocity]
	if downlink.is_active():
		downlink.push(state, NetPoseSmoother.local_now())
	else:
		_reconcile(state)


func _reconcile(state: Array) -> void:
	host_seq = int(state[0])
	reconciler.reconcile(int(state[0]), state[1], state[2], state[3])


func _correct(vehicle: Vehicle, delta: float) -> void:
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


func _start(vehicle: Vehicle, smoother: NetPoseSmoother, host_velocity: Vector3, host_spin: Vector3) -> void:
	active = true
	_exit_left = 0.0
	reconciler.clear()
	downlink.clear()
	# From the newest pose the host sent, not the one drawn a cushion behind it.
	var latest: Transform3D = smoother.latest_pose()
	if latest != Transform3D.IDENTITY:
		vehicle.global_transform = latest
	vehicle.freeze = false
	vehicle.linear_velocity = host_velocity
	vehicle.angular_velocity = host_spin
	vehicle.sleeping = false


func _stop(vehicle: Vehicle, smoother: NetPoseSmoother) -> void:
	active = false
	reconciler.clear()
	downlink.clear()
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
