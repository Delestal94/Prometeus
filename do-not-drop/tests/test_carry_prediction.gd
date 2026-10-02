extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_carry_prediction.gd
##
## The box a client carries is drawn in that client's hands at once
## (DeliveryPackage.predict_carry), not a round trip later when the host's
## copy comes back: over Steam it trailed the carrier by the whole ping
## (playtest 2026-09-29). Once the carrier stops predicting, the box goes
## back to where the host says, eased over a quarter second rather than snapping back a round trip and a
## buffer behind the hands (N-217: walking at 3.6 m/s on 80 ms of ping, under 5 cm a frame at 144 fps); the
## host's own copy ignores predictions.
##
## Offline: the box is handed to another peer's authority, so this process
## runs it the way a client does.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	await physics_frame
	var van: Node3D = level.vehicle
	var box: Node3D = get_nodes_in_group(&"cargo")[0]
	box.set_multiplayer_authority(2)
	box.set(&"freeze", true)

	var host_pose := Transform3D(Basis(), Vector3(4.0, 1.0, -3.0))
	box.set(&"net_in_vehicle", false)
	box.set(&"net_transform", host_pose)
	box.call(&"_process", 0.0)
	_expect(box.global_position.is_equal_approx(host_pose.origin),
		"A client draws a box nobody here carries where the host says")

	var hands := Transform3D(Basis(), Vector3(4.6, 1.3, -2.2))
	box.call(&"predict_carry", hands, false)
	box.call(&"_process", 0.0)
	_expect(box.global_position.is_equal_approx(hands.origin),
		"The carrier's client draws the box in its hands, not where the host last had it")

	var in_bay := Transform3D(Basis(), Vector3(0.2, 1.2, 2.0))
	box.call(&"predict_carry", in_bay, true)
	box.call(&"_process", 0.0)
	_expect(box.global_position.distance_to(van.global_transform * in_bay.origin) < 0.01,
		"A pose predicted aboard goes on this peer's truck")

	for i in range(int(box.get(&"PREDICTION_FRAMES")) + 2):
		await physics_frame
	box.call(&"_process", 0.0)
	_expect(box.global_position.distance_to(host_pose.origin) > 0.1,
		"The frame it stops predicting, the box doesn't snap to the host's pose")
	box.call(&"_process", PackageNetPose.DROP_BLEND_SECONDS)
	_expect(box.global_position.is_equal_approx(host_pose.origin),
		"Once the carrier stops predicting (dropped, handed over), the host's pose wins again after the blend")

	_check_drop_while_walking(box)

	box.set_multiplayer_authority(1)
	box.global_position = host_pose.origin
	box.call(&"predict_carry", hands, false)
	box.call(&"_process", 0.0)
	_expect(box.global_position.is_equal_approx(host_pose.origin),
		"The host's own copy ignores predictions: it is the real one")

	if _failures == 0:
		print("PASS: a carried box follows its carrier's hands on their own client")
	quit(_failures)


## A carrier walking at 3.6 m/s drops the box on a link like `--net-sim=80,10,0` (40 ms each way, up to 10 ms of
## jitter on the poses): the host's copy is a round trip and a cushion behind the hands. Drawn at 144 fps, the box
## eases from the hands to the host's copy instead of snapping back (PackageNetPose.DROP_BLEND_SECONDS).
func _check_drop_while_walking(box: Node3D) -> void:
	box.set_multiplayer_authority(2)
	var view: PackageNetPose = box.get(&"_net_view")
	var rng := RandomNumberGenerator.new()
	rng.seed = 217
	var speed: float = 3.6
	var one_way: float = 0.04
	var drop_at: float = 2.0
	var hands := func(t: float) -> Transform3D: return Transform3D(Basis(), Vector3(10.0, 1.0, -speed * t))
	# What the host has at host time h, sent at 30 Hz.
	var packets: Array = []
	for k: int in range(int(3.0 * 30.0)):
		var h: float = k / 30.0
		var at: Transform3D = hands.call(minf(h - one_way, drop_at))
		packets.append([h + one_way + rng.randf_range(0.0, 0.01), h, at])
	packets.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var next: int = 0
	var frame: int = 0
	var previous := Vector3.INF
	var worst_jump: float = 0.0
	var gap: float = 0.0
	while true:
		var now: float = 1.0 + frame / 144.0
		var t: float = frame / 144.0
		if t > 3.0:
			break
		while next < packets.size() and float(packets[next][0]) <= t:
			box.set(&"net_in_vehicle", false)
			box.set(&"net_transform", packets[next][2])
			box.set(&"net_time", roundi(float(packets[next][1]) * 1000.0) + 500000)
			view.push(box, 1.0 + float(packets[next][0]))
			next += 1
		if t < drop_at:
			box.call(&"predict_carry", hands.call(t), false)
		else:
			box.set(&"_predicted_frame", -100)
		view.draw(box, 1.0 / 144.0, now)
		if t >= drop_at and gap == 0.0:
			gap = (box.get(&"_net_view").get(&"_error_origin") as Vector3).length()
		if t > drop_at - 0.2 and previous != Vector3.INF:
			worst_jump = maxf(worst_jump, box.global_position.distance_to(previous))
		previous = box.global_position
		frame += 1
	_expect(gap > 0.3, "Walking on that link, the host's copy is well behind the hands when they let go (%.2f m)" % gap)
	_expect(worst_jump < 0.05, "...and the box never moves more than 5 cm in a frame around the drop (%.1f cm)"
			% (worst_jump * 100.0))
	_expect(box.global_position.distance_to((hands.call(drop_at) as Transform3D).origin) < 0.01,
		"It ends where the host has it, where it was dropped")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
