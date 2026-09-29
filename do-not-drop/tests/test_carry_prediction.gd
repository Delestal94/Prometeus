extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_carry_prediction.gd
##
## The box a client carries is drawn in that client's hands at once
## (DeliveryPackage.predict_carry), not a round trip later when the host's
## copy comes back: over Steam it trailed the carrier by the whole ping
## (playtest 2026-09-29). Once the carrier stops predicting, the box goes
## back to where the host says; the host's own copy ignores predictions.
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
	_expect(box.global_position.is_equal_approx(host_pose.origin),
		"Once the carrier stops predicting (dropped, handed over), the host's pose wins again")

	box.set_multiplayer_authority(1)
	box.global_position = host_pose.origin
	box.call(&"predict_carry", hands, false)
	box.call(&"_process", 0.0)
	_expect(box.global_position.is_equal_approx(host_pose.origin),
		"The host's own copy ignores predictions: it is the real one")

	if _failures == 0:
		print("PASS: a carried box follows its carrier's hands on their own client")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
