extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_prediction.gd
##
## The client at the wheel predicts its truck (N-218, vehicle_prediction.gd): two real trucks in two physics
## worlds of one process -- the host's (authority, played by a remote driver) and the client's copy (another
## peer's authority, this peer at the wheel) -- joined by a fake link that holds every input and every pose
## 150 ms (9 ticks) plus up to 2 ticks of jitter, as `--fake-lag=150` does, and later also loses 5 % of each:
## - the client unfreezes its copy once the host's truck is simulated and a pose is in, and the wheel answers
##   the same tick the input is read (the host's hasn't moved yet);
## - the inputs go out numbered, and the host plays them one per tick and says which one its pose stands for;
## - driving 4 s round a slalom, the client's prediction stays within a few centimetres of the host's truck
##   after the same input, and no correction ever moves it more than 10 cm in a tick, with loss too;
## - a box the host has in the bay is drawn in the client truck's space, riding the prediction;
## - a drag only the host's truck feels (mud, an animal hit) pulls the copy back to it without swinging;
## - the host moving its truck (a reset) snaps the client's copy there instead of easing across 20 m;
## - someone else taking the wheel stops the prediction: frozen again, drawn from the pose buffer, the gap
##   eased out instead of jumping back; the host forgets the old driver's inputs, and its pose stands for no input
##   (0) until the new driver's first one plays, not for the old driver's last number;
## - back at the wheel, the host's poses for no input are not compared with the new prediction; the wheel going
##   elsewhere and back between two ticks leaves the client's prediction and its history alone;
## - the wheel changing hands at speed (N-922.7): the truck drawn eases into the pose buffer over a time that keeps
##   it going forward, never backing up; back at the wheel at speed, the copy starts where it is drawn and is eased to
##   the host's newest pose instead of jumping there with the camera;
## - the old van's gearbox: the host's gear arriving puts the predicted copy's clutch in for the shift (N-922.7);
## - the driver's inputs cut off for more than NetInputBuffer.STALE_TICKS (no disconnect): the host lets go of the
##   pedal and keeps the wheel, and drives on once inputs arrive again; a brake is kept until the truck stops,
##   and doesn't turn into backing up;
## - a wall only the client's world has, the truck one of its exceptions (TruckPassThrough), doesn't stop the copy
##   the host's truck never met: no 3 m snap (N-922.3); the depot's staff and forklift let the truck through on every
##   peer, a level crossing's arms and train cars only where it isn't the host's (get_collision_exceptions());
## - with no ground under the host's truck in the client's world yet, the copy waits frozen instead of falling, and
##   predicts once the road is built (N-922.4);
## - `--net-sim` on a LAN (configure_net_sim) holds the driver's inputs and the host's states back (N-922.5);
## - the host going mid-drive (the level's _stop_orphaned_run) freezes the copy where it is, no longer predicted.

const LAG_TICKS: int = 9
const JITTER_TICKS: int = 2
const MAX_CORRECTION: float = 0.1
const CLIENT_ID: int = 1
const HOST_ID: int = 2

var _failures: int = 0
var _host: VehicleBody3D
var _client: VehicleBody3D
var _rng := RandomNumberGenerator.new()
var _tick: int = 0
## [deliver_at_tick, data] in send order.
var _uplink: Array = []
var _downlink: Array = []
var _loss: float = 0.0
## The driver's inputs stop reaching the host, the poses still come back (a hitch, a Wi-Fi drop one way).
var _uplink_cut: bool = false
## A braking force only the host's truck feels (N of it per kg per m/s).
var _drag: float = 0.0
var _worst_shift: float = 0.0
var _errors: Array[float] = []


func _initialize() -> void:
	_rng.seed = 218
	_run.call_deferred()


func _world() -> Node3D:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(4, 4)
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(800.0, 1.0, 800.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	return world


func _truck(world: Node3D, authority: int) -> VehicleBody3D:
	var truck := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	truck.set_multiplayer_authority(authority)
	truck.position = Vector3(0.0, 0.8, 0.0)
	world.add_child(truck)
	truck.set(&"controls_enabled", false)  # Driven by this test, not by the keyboard.
	return truck


func _run() -> void:
	var host_world: Node3D = _world()
	var client_world: Node3D = _world()
	# Offline this process is peer 1: the client's copy belongs to "the host" (HOST_ID), and peer 1 drives it.
	_host = _truck(host_world, 1)
	_client = _truck(client_world, HOST_ID)
	_host.remove_from_group(&"vehicle")
	root.get_node(^"/root/RunManager").set(&"is_running", true)
	_host.set(&"driver_peer_id", HOST_ID + 1)  # Someone not the host: played from the input buffer.
	_client.set(&"driver_peer_id", CLIENT_ID)
	_client.set(&"presentation_engine_running", true)
	await process_frame

	_expect(_client.freeze and not bool(_client.call(&"is_predicted")),
		"Before any pose from the host the copy waits frozen")
	for _i: int in range(LAG_TICKS + JITTER_TICKS + 30):
		await _step(0.0, 0.0)
	_expect(bool(_host.get(&"net_simulating")), "The host says its truck is simulated")
	_expect(bool(_client.call(&"is_predicted")) and not _client.freeze,
		"The client at the wheel unfreezes its copy and predicts it once the host's truck runs")
	var sent: Array = _client.get(&"_prediction").last_sent
	_expect(not sent.is_empty() and int(_host.get(&"net_input_seq")) > 0,
		"Inputs go out numbered and the host's pose says which one it played (%s, host at %d)" % [
			sent, int(_host.get(&"net_input_seq"))])

	# The wheel answers this tick, not a round trip later.
	_client.call(&"set_controls", 0.0, 1.0, false)
	await _step_raw()
	_expect(absf(_client.steering) > 0.01 and absf(_host.steering) < 0.001,
		"The wheel turns on the client the tick it's read (client %.3f, host still %.3f)" % [
			_client.steering, _host.steering])

	# Drive a slalom for 4 s, then 3 s more over a lossy link.
	_errors.clear()
	for tick: int in range(240):
		await _step(1.0, sin(float(tick) / 25.0))
	var clean_errors: Array[float] = _errors.duplicate()
	var speed: float = _client.linear_velocity.length() * 3.6
	_expect(speed > 30.0, "The predicted truck drives (%.0f km/h)" % speed)
	_loss = 0.05
	_errors.clear()
	for tick: int in range(180):
		await _step(0.8, sin(float(tick) / 20.0))
	_loss = 0.0
	_expect(_worst_shift <= MAX_CORRECTION + 0.0001,
		"No correction moves the truck more than 10 cm in a tick (worst %.3f m)" % _worst_shift)
	_expect(_median(clean_errors) < 0.1 and _max(clean_errors) < 0.6,
		"The prediction stays with the host after the same input (median %.3f m, worst %.3f m)" % [
			_median(clean_errors), _max(clean_errors)])
	_expect(_median(_errors) < 0.2 and _max(_errors) < 1.0,
		"...also losing 5 %% of inputs and poses (median %.3f m, worst %.3f m)" % [_median(_errors), _max(_errors)])
	print("prediction error: clean median %.3f worst %.3f; lossy median %.3f worst %.3f; worst shift %.3f" % [
		_median(clean_errors), _max(clean_errors), _median(_errors), _max(_errors), _worst_shift])

	# Something only the host feels (mud, an animal hit: forces the host applies to its own truck): the client's
	# copy is pulled back to it, never more than 10 cm a tick, and doesn't swing round it.
	_errors.clear()
	_drag = 0.3
	for tick: int in range(180):
		await _step(1.0, 0.3 * sin(float(tick) / 30.0))
	_drag = 0.0
	var dragged: Array[float] = _errors.slice(_errors.size() / 2)
	_expect(_worst_shift <= MAX_CORRECTION + 0.0001 and _max(dragged) < 0.6,
		"A drag only the host feels: the copy is held within %.2f m of it (worst shift %.3f m)" % [
			_max(dragged), _worst_shift])
	print("host-only drag: settled worst %.3f m, median %.3f m" % [_max(dragged), _median(dragged)])

	_check_box_rides()

	# A reset on the host: the client's copy snaps there instead of easing across.
	var reconciler: NetPredictionReconciler = _client.get(&"_prediction").reconciler
	var snaps_before: int = reconciler.snaps
	_host.global_position += Vector3(20.0, 0.0, 0.0)
	var target_offset: Vector3 = _host.global_position - _client.global_position
	for _i: int in range(LAG_TICKS + JITTER_TICKS + 6):
		await _step(0.0, 0.0)
	_expect(reconciler.snaps > snaps_before, "A truck the host moved 20 m is snapped to, not eased across")
	for _i: int in range(LAG_TICKS + JITTER_TICKS + 2):
		await _step(0.0, 0.0)
	_expect(reconciler.last_error < 0.5,
		"...and is where the host has it after the same input (%.2f m off; it was moved %.1f m)" % [
			reconciler.last_error, target_offset.length()])

	# Someone else takes the wheel.
	var predicted_at: Vector3 = _client.global_position
	var old_driver_seq: int = int(_host.get(&"net_input_seq"))
	_client.set(&"driver_peer_id", 7)
	_host.set(&"driver_peer_id", 7)
	_expect((_host.get(&"_prediction").inputs as NetInputBuffer).newest() == -1,
		"The host forgets the old driver's inputs when the wheel changes hands")
	_expect(old_driver_seq > 0 and int(_host.get(&"net_input_seq")) == 0,
		"...and its pose stands for no input (0), not the old driver's last one (%d) (got %d)" % [
			old_driver_seq, int(_host.get(&"net_input_seq"))])
	await _step_raw()
	_expect(_client.freeze and not bool(_client.call(&"is_predicted")),
		"Not driving any more: the copy is frozen again, drawn from the host's poses")
	_client.call(&"_process", 0.0)
	_expect(_client.global_position.distance_to(predicted_at) < 1.0,
		"The frame prediction stops the truck doesn't jump back to the pose buffer (%.2f m)" % [
			_client.global_position.distance_to(predicted_at)])
	var smoother: NetPoseSmoother = _client.get(&"_net_smoother")
	_client.call(&"_process", float(_client.get(&"_prediction").get(&"exit_seconds")))
	_expect(_client.global_position.distance_to(smoother.sample(NetPoseSmoother.local_now()).origin) < 0.01,
		"...and is drawn where the pose buffer has it once the blend is over")
	for _i: int in range(LAG_TICKS + JITTER_TICKS + 4):
		await _step_raw()
	_expect(int(_host.get(&"net_input_seq")) == 0, "Still no input while the new driver has sent none")

	await _check_wheel_back()
	await _check_exit_while_moving()
	await _check_stale_inputs()
	await _check_wall_only_here()
	await _check_let_through()
	await _check_no_ground()
	await _check_remote_clutch()
	await _check_net_sim()
	await _check_host_gone()

	root.get_node(^"/root/RunManager").set(&"is_running", false)
	if _failures == 0:
		print("PASS: the client at the wheel predicts its truck and is eased to the host's")
	quit(_failures)


## The client takes the wheel back and drives off (N-922.2).
func _check_wheel_back() -> void:
	_host.set(&"driver_peer_id", HOST_ID + 1)
	_client.set(&"driver_peer_id", CLIENT_ID)
	var reconciler: NetPredictionReconciler = _client.get(&"_prediction").reconciler
	var snaps_before: int = reconciler.snaps
	for _i: int in range(LAG_TICKS):
		await _step(0.0, 0.0)
	_expect(bool(_client.call(&"is_predicted")) and reconciler.history_size() > 0 and reconciler.last_error == 0.0
			and reconciler.snaps == snaps_before,
		"Back at the wheel, the host's poses for no input yet are not compared with the new prediction")
	for _i: int in range(90):
		await _step(1.0, 0.2)
	_expect(int(_host.get(&"net_input_seq")) > 0, "...and once the host plays its inputs, its pose stands for them")
	# The wheel goes elsewhere and back between two ticks; driver_peer_id's setter runs on the client too.
	_host.set(&"driver_peer_id", 7)
	_host.set(&"driver_peer_id", HOST_ID + 1)
	_client.set(&"driver_peer_id", 7)
	_client.set(&"driver_peer_id", CLIENT_ID)
	await _step(1.0, 0.2)
	_expect(bool(_client.call(&"is_predicted")) and reconciler.history_size() > 1,
		"The wheel away and back between two ticks: the prediction goes on with its history (%d states)" % [
			reconciler.history_size()])


## Someone else takes the wheel at speed (N-922.7): the gap between the predicted truck and the pose buffer (a round
## trip and a cushion behind, metres at this speed) closes over a time that keeps the truck drawn going forward,
## never backing up as it did closed in 0.3 s; then it is drawn where the buffer has it. The client drives again.
func _check_exit_while_moving() -> void:
	for _i: int in range(150):
		await _step(1.0, 0.0)
	var speed: float = _client.linear_velocity.length()
	_client.set(&"driver_peer_id", 7)
	_host.set(&"driver_peer_id", 7)
	var prediction: Object = _client.get(&"_prediction")
	var drawn: Array[Transform3D] = []
	var started_at: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < 2500:
		await _step_raw()
		drawn.append(_client.global_transform)
	var backward: float = 0.0
	for index: int in range(1, drawn.size()):
		var step: Vector3 = drawn[index].origin - drawn[index - 1].origin
		backward = maxf(backward, -step.dot(-drawn[index].basis.z))
	var smoother: NetPoseSmoother = _client.get(&"_net_smoother")
	var left: float = drawn[-1].origin.distance_to(smoother.sample(NetPoseSmoother.local_now()).origin)
	var blend: float = float(prediction.get(&"exit_seconds"))
	print("exit at %.0f km/h: blend %.2f s, worst step back %.3f m, %.2f m from the buffer after" % [
		speed * 3.6, blend, backward, left])
	_expect(speed > 10.0 and blend > 0.3 and backward < 0.02,
		"Let go of at %.0f km/h, the truck drawn eases into the pose buffer over %.2f s, never backing up (%.3f m)" % [
			speed * 3.6, blend, backward])
	_expect(left < 0.5, "...and is drawn where the buffer has it once that is over (%.2f m off)" % left)
	# Back at the wheel at speed: the copy starts where it is drawn and is eased to the host's newest pose, a cushion
	# ahead, instead of jumping there with the driver's camera. As _check_wheel_back left it afterwards: the host
	# playing the client's flat-out inputs, the wheel a little turned.
	_host.set(&"driver_peer_id", HOST_ID + 1)
	_client.set(&"driver_peer_id", CLIENT_ID)
	var was: Vector3 = _client.global_position
	var jump: float = INF
	var ahead: float = 0.0
	for _i: int in range(2 * (LAG_TICKS + JITTER_TICKS) + NetInputBuffer.CUSHION + 4):
		await _step(1.0, 0.2)
		if jump == INF and bool(_client.call(&"is_predicted")):
			jump = _client.global_position.distance_to(was) - _client.linear_velocity.length() / 60.0
			ahead = smoother.latest_pose().origin.distance_to(was)
		was = _client.global_position
	print("restart at speed: %.2f m more than a tick's travel (the host's newest pose %.2f m ahead)" % [jump, ahead])
	_expect(jump < 0.25, "Back at the wheel at speed: no jump to the host's newest pose (%.2f m)" % jump)


## The driver's inputs stop reaching the host, without it leaving (N-922.2).
func _check_stale_inputs() -> void:
	# Flat out: past STALE_TICKS the host lets go of the pedal instead of driving on for good; the wheel stays.
	var throttle_before: float = float(_host.call(&"throttle_input"))
	await _cut_uplink_until_stale(1.0, 0.2)
	_expect(throttle_before == 1.0 and float(_host.call(&"throttle_input")) == 0.0
			and is_equal_approx(float(_host.call(&"steer_input")), 0.2),
		"A driver silent for more than STALE_TICKS: the host lets go of the pedal, keeps the wheel (%.1f -> %.1f)" % [
			throttle_before, float(_host.call(&"throttle_input"))])
	await _restore_uplink(1.0)
	_expect(float(_host.call(&"throttle_input")) == 1.0, "...and drives on with the inputs once they arrive again")
	# Braking: the brake goes on while the truck rolls (freewheeling downhill would be worse), and doesn't turn into
	# backing up once it has stopped.
	var brake: float = -0.5
	for _i: int in range(LAG_TICKS + JITTER_TICKS + 4):
		await _step(brake, 0.0)
	await _cut_uplink_until_stale(brake, 0.0)
	var rolling: float = _forward_speed(_host)
	for _i: int in range(30):
		await _step(brake, 0.0)
	var slowed: float = _forward_speed(_host)
	_expect(rolling > 5.0 and is_equal_approx(float(_host.call(&"throttle_input")), brake) and slowed < rolling - 2.5,
		"A driver silent while braking: the host keeps braking (throttle %.1f, %.1f -> %.1f m/s in 0.5 s)" % [
			float(_host.call(&"throttle_input")), rolling, slowed])
	var ticks: int = 0
	while _forward_speed(_host) > 0.7 and ticks < 300:
		await _step(brake, 0.0)
		ticks += 1
	for _i: int in range(60):
		await _step(brake, 0.0)
	_expect(float(_host.call(&"throttle_input")) == 0.0 and _forward_speed(_host) > -0.5,
		"...until it stops, and then doesn't back up (throttle %.1f, %.2f m/s)" % [
			float(_host.call(&"throttle_input")), _forward_speed(_host)])
	await _restore_uplink(1.0)


## A body only the client's world has, across the road (N-922.3): with the truck as its exception, the copy drives
## through it, as the host's truck does where there is none, and isn't snapped back.
func _check_wall_only_here() -> void:
	var reconciler: NetPredictionReconciler = _client.get(&"_prediction").reconciler
	for _i: int in range(60):
		await _step(1.0, 0.0)
	var forward: Vector3 = -_client.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 4.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	_client.get_parent().add_child(wall)
	var at: Vector3 = _client.global_position + forward * 6.0
	wall.global_transform = Transform3D(Basis.looking_at(forward), Vector3(at.x, 2.0, at.z))
	var let_through: bool = _pass_through_script().call(&"let_through", [wall], self)
	var snaps_before: int = reconciler.snaps
	_errors.clear()
	var speed: float = _forward_speed(_client)
	for _i: int in range(75):
		await _step(1.0, 0.0)
	var past: float = (_client.global_position - wall.global_position).dot(forward)
	_expect(let_through and wall.get_collision_exceptions().has(_client) and speed > 5.0 and past > 3.0
			and reconciler.snaps == snaps_before and _max(_errors) < 1.0,
		("A wall only the client has, the truck its exception: the copy drives through (%.1f m past at %.0f km/h),"
				+ " no snap (%d), worst %.2f m") % [past, speed * 3.6, reconciler.snaps - snaps_before, _max(_errors)])
	wall.queue_free()


## Who lets the truck through (N-922.3): the depot's staff and forklift, which every peer runs on its own clock, on
## every peer; a crossing's arms and cars, which the host moves, only where this peer isn't the host.
func _check_let_through() -> void:
	var world: Node = _client.get_parent()
	var worker: PhysicsBody3D = (load("res://scripts/gameplay/depot/depot_worker.gd") as GDScript).new()
	worker.position = _client.global_position + Vector3(40.0, 0.0, 0.0)
	world.add_child(worker)
	var forklift: PhysicsBody3D = (load("res://scripts/gameplay/depot/depot_forklift.gd") as GDScript).new()
	forklift.call(&"place", worker.position + Vector3(4.0, 0.0, 0.0), worker.position + Vector3(4.0, 0.0, 10.0))
	world.add_child(forklift)
	var crossing: Node3D = (load("res://scripts/gameplay/route/segments/rail_crossing_segment.gd") as GDScript).new()
	crossing.position = _client.global_position + Vector3(-80.0, -0.8, 0.0)
	world.add_child(crossing)
	await _step(0.0, 0.0)
	await _step(0.0, 0.0)
	var crossing_bodies: Array = []
	crossing_bodies.append_array(crossing.get(&"_arms"))
	crossing_bodies.append_array(crossing.get(&"_train"))
	_expect(worker.get_collision_exceptions().has(_client) and forklift.get_collision_exceptions().has(_client),
		"The depot's staff and forklift let the truck through")
	var solid := func(body: PhysicsBody3D) -> bool: return body.get_collision_exceptions().is_empty()
	_expect(crossing_bodies.size() == 6 and not bool(crossing.get(&"lets_truck_through"))
			and crossing_bodies.all(solid),
		"On the host a crossing's arms and train cars stay solid for the truck")
	crossing.set(&"lets_truck_through", true)
	await _step(0.0, 0.0)
	var through := func(body: PhysicsBody3D) -> bool: return body.get_collision_exceptions().has(_client)
	_expect(crossing_bodies.all(through),
		"...and on a client its truck drives through them, which reach it half a round trip late")
	for node: Node in [worker, forklift, crossing]:
		node.queue_free()
	await _step(0.0, 0.0)


## A client at the wheel whose world has no road yet under the host's truck (N-922.4: back from a drop, or late into
## an endless run, before the streamer builds there): its copy waits frozen instead of falling, and starts once the
## ground is in.
func _check_no_ground() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(4, 4)
	root.add_child(viewport)
	var bare := Node3D.new()
	viewport.add_child(bare)
	var copy: VehicleBody3D = _truck(bare, HOST_ID)
	copy.remove_from_group(&"vehicle")
	copy.set(&"driver_peer_id", CLIENT_ID)
	copy.set(&"presentation_engine_running", true)
	await physics_frame
	var host_pose := Transform3D(Basis(Vector3.UP, 0.4), Vector3(30.0, 0.666, -12.0))
	for tick: int in range(20):
		_send_pose(copy, tick, host_pose)
		await physics_frame
	_expect(copy.freeze and not bool(copy.call(&"is_predicted")) and copy.global_position.y > 0.5,
		"No ground under the host's truck here yet: the copy waits frozen, drawn from the poses (y %.2f)" % [
			copy.global_position.y])
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	bare.add_child(ground)
	for tick: int in range(20, 80):
		_send_pose(copy, tick, host_pose)
		await physics_frame
	_expect(bool(copy.call(&"is_predicted")) and not copy.freeze and copy.global_position.y > 0.3,
		"...and once the road is built under it, it predicts, standing on it (y %.2f)" % copy.global_position.y)
	viewport.queue_free()
	await physics_frame


## `--net-sim` on a LAN (N-922.5, Vehicle.configure_net_sim): the client at the wheel holds back the inputs it sends
## and the host's states it compares with, instead of only the pose buffer it doesn't draw from. A 2 s lag: nothing
## gets through in these few ticks. Turned off again, both ways go straight through.
func _check_net_sim() -> void:
	var prediction: Object = _client.get(&"_prediction")
	var seen_seq: int = int(prediction.get(&"host_seq"))
	_client.call(&"configure_net_sim", {"lag_ms": 2000, "jitter_ms": 0, "loss_pct": 0.0})
	for _i: int in range(LAG_TICKS + JITTER_TICKS + 4):
		await _step(1.0, 0.0)
	var uplink: NetDelayQueue = prediction.get(&"uplink")
	var downlink: NetDelayQueue = prediction.get(&"downlink")
	_expect(bool(_client.call(&"is_predicted")) and uplink.pending() > LAG_TICKS and downlink.pending() > 0
			and int(prediction.get(&"host_seq")) == seen_seq,
		"--net-sim holds the driver's inputs (%d) and the host's states (%d) back; none compared yet" % [
			uplink.pending(), downlink.pending()])
	_client.call(&"configure_net_sim", {"lag_ms": 0, "jitter_ms": 0, "loss_pct": 0.0})
	uplink.clear()
	downlink.clear()
	for _i: int in range(LAG_TICKS + JITTER_TICKS + 4):
		await _step(1.0, 0.0)
	_expect(uplink.pending() == 0 and downlink.pending() == 0 and int(prediction.get(&"host_seq")) > seen_seq,
		"...and with it off, both go straight through again")


## The old van's manual gearbox on the copy the client predicts (N-922.7): the host's gear arriving puts the copy's
## clutch in for SHIFT_SECONDS, no pull, as the host's had, then lets it out. A copy not predicting keeps none.
func _check_remote_clutch() -> void:
	var world: Node3D = _world()
	var copy: VehicleBody3D = _truck(world, HOST_ID)
	copy.remove_from_group(&"vehicle")
	copy.set(&"variant_id", &"vintage")
	copy.set(&"presentation_engine_running", true)
	var gearbox: Node = copy.get(&"gearbox")
	var shift_seconds: float = float((gearbox.get_script() as GDScript).get_script_constant_map()["SHIFT_SECONDS"])
	await physics_frame
	gearbox.set(&"gear", 2)
	var idle_clutch: float = float(gearbox.get(&"shift_left"))
	copy.set(&"driver_peer_id", CLIENT_ID)
	var host_pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.666, 0.0))
	for tick: int in range(10):
		_send_pose(copy, tick, host_pose)
		await physics_frame
	gearbox.set(&"gear", 3)
	var clutch_in: float = float(gearbox.get(&"shift_left"))
	var pull: float = float(gearbox.call(&"drive_multiplier", 10.0, float(copy.get(&"maximum_speed_kmh"))))
	for tick: int in range(10, 10 + ceili(shift_seconds * 60.0) + 3):
		_send_pose(copy, tick, host_pose)
		await physics_frame
	var clutch_after: float = float(gearbox.get(&"shift_left"))
	_expect(bool(copy.call(&"is_predicted")) and is_zero_approx(idle_clutch)
			and is_equal_approx(clutch_in, shift_seconds) and pull == 0.0 and is_zero_approx(clutch_after),
		"The host's shift reaching the predicted copy: clutch in for %.1f s, no pull, then out (%.2f, %.2f, %.2f)" % [
			shift_seconds, clutch_in, pull, clutch_after])
	world.get_parent().queue_free()
	await physics_frame


## One whole pose packet from the host (the truck standing at `pose`), as the synchronizer applies it.
func _send_pose(copy: VehicleBody3D, tick: int, pose: Transform3D) -> void:
	copy.set(&"net_simulating", true)
	copy.set(&"net_time", float(tick) / 60.0)
	copy.set(&"net_position", pose.origin)
	copy.set(&"net_rotation", pose.basis.get_euler())
	copy.set(&"net_input_seq", 0)
	copy.set(&"net_linear_velocity", Vector3.ZERO)
	copy.set(&"net_angular_velocity", Vector3.ZERO)


## Loaded at run time: vehicle/ scripts sit next to ones that name autoloads.
static func _pass_through_script() -> GDScript:
	return load("res://scripts/gameplay/vehicle/truck_pass_through.gd")


## The host goes mid-drive (N-922.2): the session closes, this peer is an offline host and the copy is its own
## (authority 1). The level stops the run; loaded at run time like vehicle_prediction.gd (it names autoloads).
func _check_host_gone() -> void:
	for _i: int in range(60):
		await _step(1.0, 0.0)
	var speed: float = _client.linear_velocity.length() * 3.6
	_client.set_multiplayer_authority(1)
	var level: Node = (load("res://scripts/gameplay/level_common.gd") as GDScript).new()
	level.set(&"vehicle", _client)
	level.call(&"_stop_orphaned_run", "host_lost")
	level.free()
	var left_at: Vector3 = _client.global_position
	for _i: int in range(60):
		await physics_frame
	var moved := Vector2(_client.global_position.x - left_at.x, _client.global_position.z - left_at.z)
	_expect(speed > 5.0 and _client.freeze and moved.length() < 0.05 and not bool(_client.call(&"is_predicted")),
		"The host gone mid-drive: the truck stays put, not predicted (was at %.0f km/h, moved %.2f m)" % [
			speed, moved.length()])


## Cuts the driver's inputs off the host, the driver holding these controls, until the host's input is stale.
func _cut_uplink_until_stale(throttle: float, steer: float) -> void:
	var buffer: NetInputBuffer = _host.get(&"_prediction").inputs
	_uplink_cut = true
	var ticks: int = 0
	while not buffer.is_stale() and ticks < 120:
		await _step(throttle, steer)
		ticks += 1


## The driver's inputs reach the host again, until it plays them.
func _restore_uplink(throttle: float) -> void:
	_uplink_cut = false
	for _i: int in range(LAG_TICKS + JITTER_TICKS + NetInputBuffer.CUSHION + 2):
		await _step(throttle, 0.0)


## Speed along the truck's front (local -Z); negative backing up.
static func _forward_speed(truck: VehicleBody3D) -> float:
	return truck.linear_velocity.dot(-truck.global_basis.z)


## A box the host has riding in the bay (net_in_vehicle), drawn on the client: on the predicted truck.
func _check_box_rides() -> void:
	var box: Node3D = (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate()
	box.set_multiplayer_authority(HOST_ID)
	_client.get_parent().add_child(box)
	box.set(&"freeze", true)
	box.set(&"_vehicle", _client)
	var in_bay := Transform3D(Basis(), Vector3(0.3, 0.9, 2.0))
	box.set(&"net_in_vehicle", true)
	box.set(&"net_transform", in_bay)
	box.set(&"_has_net_state", true)
	box.call(&"_process", 0.0)
	_expect(box.global_position.distance_to(_client.get_global_transform_interpolated() * in_bay.origin) < 0.01,
		"A box in the bay is drawn in the space of the client's predicted truck")
	box.queue_free()


## One physics tick of both trucks with the link in between, the client's driver holding these controls.
func _step(throttle: float, steer: float) -> void:
	_client.call(&"set_controls", throttle, steer, false)
	await _step_raw()


func _step_raw() -> void:
	if _drag > 0.0:
		_host.apply_central_force(-_host.linear_velocity * _host.mass * _drag)
	await physics_frame
	_tick += 1
	# What the last tick sent each way, onto the link.
	var sent: Array = _client.get(&"_prediction").last_sent
	if not sent.is_empty() and not _uplink_cut and (_uplink.is_empty() or int(_uplink[-1][1][0]) < int(sent[0])):
		_send(_uplink, sent.duplicate())
	_host.set(&"net_simulating", not _host.freeze)
	_send(_downlink, [
		float(_host.get(&"net_time")), _host.get(&"net_position"), _host.get(&"net_rotation"),
		int(_host.get(&"net_input_seq")), _host.get(&"net_linear_velocity"), _host.get(&"net_angular_velocity"),
		bool(_host.get(&"net_simulating"))])
	while not _uplink.is_empty() and int(_uplink[0][0]) <= _tick:
		var input: Array = _uplink.pop_front()[1]
		# As submit_driver_input: only while this client is the host's driver (inputs still on the way when the
		# wheel changed hands are dropped).
		if int(_host.get(&"driver_peer_id")) == HOST_ID + 1:
			_host.call(&"receive_driver_input", int(input[0]), float(input[1]), float(input[2]), bool(input[3]))
	while not _downlink.is_empty() and int(_downlink[0][0]) <= _tick:
		var state: Array = _downlink.pop_front()[1]
		_client.set(&"net_simulating", state[6])
		_client.set(&"net_time", state[0])
		_client.set(&"net_position", state[1])
		_client.set(&"net_rotation", state[2])
		_client.set(&"net_input_seq", state[3])
		_client.set(&"net_linear_velocity", state[4])
		_client.set(&"net_angular_velocity", state[5])
		var reconciler: NetPredictionReconciler = _client.get(&"_prediction").reconciler
		if bool(_client.call(&"is_predicted")) and reconciler.history_size() > 0:
			_errors.append(reconciler.last_error)
	_worst_shift = maxf(_worst_shift, float(_client.get(&"_prediction").last_shift))


## Onto a link: LAG_TICKS plus jitter later, in order (unreliable_ordered drops what would overtake), some lost.
func _send(link: Array, data: Array) -> void:
	if _loss > 0.0 and _rng.randf() < _loss:
		return
	var at: int = _tick + LAG_TICKS + _rng.randi_range(0, JITTER_TICKS)
	if not link.is_empty():
		at = maxi(at, int(link[-1][0]))
	link.append([at, data])


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return INF
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


static func _max(values: Array[float]) -> float:
	var most: float = 0.0 if not values.is_empty() else INF
	for value: float in values:
		most = maxf(most, value)
	return most


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
