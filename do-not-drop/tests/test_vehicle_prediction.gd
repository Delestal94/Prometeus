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
##   eased out instead of jumping back; the host forgets the old driver's inputs.

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
	_client.set(&"driver_peer_id", 7)
	_host.set(&"driver_peer_id", 7)
	_expect((_host.get(&"_prediction").inputs as NetInputBuffer).newest() == -1,
		"The host forgets the old driver's inputs when the wheel changes hands")
	await _step_raw()
	_expect(_client.freeze and not bool(_client.call(&"is_predicted")),
		"Not driving any more: the copy is frozen again, drawn from the host's poses")
	_client.call(&"_process", 0.0)
	_expect(_client.global_position.distance_to(predicted_at) < 1.0,
		"The frame prediction stops the truck doesn't jump back to the pose buffer (%.2f m)" % [
			_client.global_position.distance_to(predicted_at)])
	var smoother: NetPoseSmoother = _client.get(&"_net_smoother")
	_client.call(&"_process", VehiclePrediction.EXIT_BLEND_SECONDS)
	_expect(_client.global_position.distance_to(smoother.sample(NetPoseSmoother.local_now()).origin) < 0.01,
		"...and is drawn where the pose buffer has it once the blend is over")

	root.get_node(^"/root/RunManager").set(&"is_running", false)
	if _failures == 0:
		print("PASS: the client at the wheel predicts its truck and is eased to the host's")
	quit(_failures)


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
	if not sent.is_empty() and (_uplink.is_empty() or int(_uplink[-1][1][0]) < int(sent[0])):
		_send(_uplink, sent.duplicate())
	_host.set(&"net_simulating", not _host.freeze)
	_send(_downlink, [
		float(_host.get(&"net_time")), _host.get(&"net_position"), _host.get(&"net_rotation"),
		int(_host.get(&"net_input_seq")), _host.get(&"net_linear_velocity"), _host.get(&"net_angular_velocity"),
		bool(_host.get(&"net_simulating"))])
	while not _uplink.is_empty() and int(_uplink[0][0]) <= _tick:
		var input: Array = _uplink.pop_front()[1]
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
