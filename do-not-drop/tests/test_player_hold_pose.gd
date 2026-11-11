extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_hold_pose.gd
##
## S-205: the gel's hands grip the box while its player holds the primary action steadying it
## (scripts/gameplay/player/player_hold_pose.gd), for the whole crew and not only in the owner's mirror.
## Checks that:
## - the host puts who steadies the box in the care_state it publishes (package_rescue.gd
##   steadying_peers): `held_by` the tender, `helped_by` the helper, 0 when nobody, when the hold is
##   released, when a tool is worked instead and when the sample goes stale; a change forces the publish
##   on the next tick and holding on forces nothing more (no extra bandwidth while held);
## - the local player's pose follows `PlayerHoldFeedback.holding` -- no host round trip -- and the hands
##   engage in the very call that reads the input: both hands reach the box's sides when seated, and
##   come back when it is released;
## - a carrying player has no new IK: the carry pose's hands press in a few centimetres (squeeze) and
##   come back out;
## - a remote copy engages from the box's `care_state.held_by` / `helped_by` for its own peer only, never
##   from its local flag, and lets go when the host clears it;
## - the driver's seat, the phone in the hand, a ragdoll fall, a knockout and an emote own the arms and win;
## - a stopped run (or a box outside the run's cargo) clears held_by on the host's next tick, and an input
##   flapping every tick forces at most one publish per 0.05 s;
## - the real box (position, integrity) is never touched, and the protocol version moved with the payload.
##
## Nothing is drawn headless: how the grip reads is for revisor-visual.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const TRAP: String = "res://data/traps/noisy.tres"
const SEAT: NodePath = NodePath("Somewhere/Seat")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_check_host_publish()
	var manager: Node = root.get_node(^"/root/NetworkManager")
	_expect(int(manager.get(&"PROTOCOL_VERSION")) >= 63, "The protocol version moved with held_by (S-205)")
	var player: Player = await _spawn(1)
	var box: DeliveryPackage = _box(player.global_position + Vector3(0.0, 0.95, -0.4))
	await _check_seated_reach(player, box)
	await _check_carry_squeeze(player, box)
	await _check_remote(box)
	await _check_blockers(player, box)
	if _failures == 0:
		print("PASS: the hands grip the box the frame the hold goes down, for every peer")
	quit(_failures)


func _spawn(peer_id: int) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	root.add_child(player)
	await process_frame
	await process_frame
	# The test feeds the flag itself: the real physics frames would clear it (no card, no input).
	player._cargo_care.set_physics_process(false)
	return player


func _box(at: Vector3) -> DeliveryPackage:
	var box := PACKAGE_SCENE.instantiate() as DeliveryPackage
	box.trap_definition = load(TRAP) as TrapDefinition
	box.freeze = true
	box.position = at
	root.add_child(box)
	box.set_physics_process(false)
	box._cushion_signature = PackageRescue.care_signature(box.trap_behavior)
	return box


## The host side: who is holding, published and republished only on a change.
func _check_host_publish() -> void:
	var box := _box(Vector3(5.0, 1.0, 5.0))
	PackageRescue.publish_care(box)
	_expect(int(box.care_state.get("held_by", -1)) == 0 and int(box.care_state.get("helped_by", -1)) == 0,
		"A box nobody holds publishes held_by 0 and helped_by 0")
	box.set_tender(2)
	_expect(box.set_assistant(3), "A helper can join the tender")
	_expect(not _forced(box), "Nobody holding: nothing forces a publish")

	PackageTending.accept_input(box, 2, _sample(false))
	_expect(not _forced(box), "A sample without the hold changes nothing")
	PackageTending.accept_input(box, 2, _sample(true))
	_expect(_forced(box), "The tender's hand going down forces the publish on the next tick")
	PackageRescue.publish_care(box)
	_expect(int(box.care_state["held_by"]) == 2 and int(box.care_state["helped_by"]) == 0,
		"...and it names the tender (got %s)" % [box.care_state])
	_expect(not _forced(box), "Holding on forces nothing more: no extra publishes while held")

	PackageTending.accept_input(box, 3, _sample(true))
	_expect(_forced(box), "The helper joining in forces the publish")
	PackageRescue.publish_care(box)
	_expect(int(box.care_state["held_by"]) == 2 and int(box.care_state["helped_by"]) == 3,
		"...and names both (got %s)" % [box.care_state])

	PackageTending.accept_input(box, 2, _sample(false, true))
	_expect(_forced(box), "Letting go forces the publish")
	PackageRescue.publish_care(box)
	_expect(int(box.care_state["held_by"]) == 0 and int(box.care_state["helped_by"]) == 3,
		"...the tender is out, the helper still there (got %s)" % [box.care_state])

	(box._tender_inputs[3] as Dictionary)["age"] = 99.0
	_expect(_forced(box), "A sample that stops arriving expires the helper's hold")
	PackageRescue.publish_care(box)
	_expect(int(box.care_state["helped_by"]) == 0, "...and the helper's hands let go")
	_expect(not box.care_state.is_empty() and box.care_state.has("phase"), "The rest of the care state is untouched")
	box.queue_free()
	_check_host_edges()


## Fresh boxes, a stopped run and a flapping input.
func _check_host_edges() -> void:
	var fresh := _box(Vector3(6.0, 1.0, 6.0))
	_expect(int(fresh.care_state.get("held_by", 0)) == 0 and int(fresh.care_state.get("helped_by", 0)) == 0,
		"A freshly initialized box reads held_by 0 and helped_by 0")
	var steady: Dictionary = PackageRescue.steadying_peers(fresh)
	_expect(int(steady["held_by"]) == 0 and int(steady["helped_by"]) == 0, "...and nobody is steadying it")
	var before: Dictionary = fresh.care_state
	PackageRescue.clear_steadying(fresh)
	_expect(is_same(fresh.care_state, before), "Clearing a box nobody holds leaves its care_state alone")

	# The run stops (time up, end of the route) while someone holds: one host tick clears it for everyone.
	var run: Node = PackageAutoloads.run_manager(fresh)
	_expect(run != null and not bool(run.get(&"is_running")), "No run is going in this test")
	fresh.set_tender(2)
	PackageTending.accept_input(fresh, 2, _sample(true))
	PackageRescue.publish_care(fresh)
	_expect(int(fresh.care_state["held_by"]) == 2, "The host published the hold (held_by 2)")
	fresh._physics_process(1.0 / 60.0)
	_expect(int(fresh.care_state["held_by"]) == 0 and int(fresh.care_state["helped_by"]) == 0,
		"The run stopped: one host tick clears held_by, so remote hands let go")
	_expect(not is_same(fresh.care_state, before), "...in a new dictionary, so ON_CHANGE replicates it")

	# An input that flaps every tick: at most one forced publish per HANDS_PUBLISH_MIN_SEC.
	var dt: float = 1.0 / 60.0
	var ticks: int = 120
	var publishes: int = 0
	var published: Dictionary = fresh.care_state
	for tick: int in ticks:
		PackageTending.accept_input(fresh, 2, _sample(tick % 2 == 0))
		PackageRescue._publish_hand_change(fresh)
		fresh._care_publish_time += dt
		if fresh._care_publish_time >= PackageRescue.care_publish_interval(fresh):
			fresh._care_publish_time = 0.0
			PackageRescue.publish_care(fresh)
			publishes += 1
	var limit: int = ceili(ticks * dt / PackageRescue.HANDS_PUBLISH_MIN_SEC) + 1
	_expect(publishes > 0 and publishes <= limit,
		"Flapping every tick for %d ticks publishes %d times, at most %d" % [ticks, publishes, limit])
	_expect(not is_same(fresh.care_state, published), "...and the state did get published")
	fresh.queue_free()


func _sample(steady: bool, work: bool = false) -> Dictionary:
	return {"steady": steady, "calm": steady, "balance": Vector2.ZERO, "work": work, "tool": &"tape"}


func _forced(box: DeliveryPackage) -> bool:
	box._care_publish_time = PackageRescue.HANDS_PUBLISH_MIN_SEC
	PackageRescue._publish_hand_change(box)
	return box._care_publish_time >= PackageRescue.care_publish_interval(box)


func _check_seated_reach(player: Player, box: DeliveryPackage) -> void:
	var pose: Node3D = player.get_node(^"PlayerHoldPose")
	var care: Node = player._cargo_care
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(player._body_visual)
	var left := BoneAttachment3D.new()
	left.bone_name = &"hand.L"
	skeleton.add_child(left)
	var right := BoneAttachment3D.new()
	right.bone_name = &"hand.R"
	skeleton.add_child(right)
	player.seat_node_path = SEAT
	# The sit clip blends in over a moment: measure the hands once it has.
	await create_timer(1.0).timeout
	var rest_left: Vector3 = left.global_position
	var rest_right: Vector3 = right.global_position
	var box_origin: Transform3D = box.global_transform
	var integrity: float = box.integrity
	var left_goal: Vector3 = box.to_global(Vector3(-0.33, 0.16, 0.0))
	var right_goal: Vector3 = box.to_global(Vector3(0.33, 0.16, 0.0))
	_expect(pose.weight() == 0.0 and pose.hand_targets().is_empty(), "Nothing is built while nobody holds")

	# The press, read this frame: the pose answers in the same call, with nothing from the host.
	care.hold_feedback.set_input(box, true)
	_expect(care.hold_feedback.holding, "The local flag is up")
	pose.update_pose(0.016)
	_expect(pose.weight() > 0.1, "The pose starts the very frame of the press (weight %.2f)" % pose.weight())
	_expect(pose.hand_targets().size() == 2, "Both hands get a target")
	_expect(box.care_state.get("held_by", 0) == 0, "...while the host has said nothing")
	await _settle(player, pose)
	_expect(is_equal_approx(pose.weight(), 1.0), "Within 0.1 s the grip is full (%.2f)" % pose.weight())
	var held_left: Vector3 = left.global_position
	var held_right: Vector3 = right.global_position
	_expect(held_left.distance_to(left_goal) < rest_left.distance_to(left_goal) - 0.03,
		"The left hand moves toward the box (%.2f m -> %.2f m)" % [rest_left.distance_to(left_goal),
		held_left.distance_to(left_goal)])
	_expect(held_right.distance_to(right_goal) < rest_right.distance_to(right_goal) - 0.03,
		"The right hand moves toward the box (%.2f m -> %.2f m)" % [rest_right.distance_to(right_goal),
		held_right.distance_to(right_goal)])
	var targets: Array[Marker3D] = pose.hand_targets()
	_expect(left.global_position.distance_to(targets[0].global_position) < 0.08
			and right.global_position.distance_to(targets[1].global_position) < 0.08,
		"The IK puts each hand on its target (%.3f, %.3f m off)" % [
			left.global_position.distance_to(targets[0].global_position),
			right.global_position.distance_to(targets[1].global_position)])
	var across: Vector3 = player.global_basis.x
	_expect(targets[0].global_position.dot(across) < targets[1].global_position.dot(across),
		"The left hand takes the box's left side")
	_expect(box.global_transform.is_equal_approx(box_origin) and is_equal_approx(box.integrity, integrity),
		"The real box is untouched")

	# The release, read this frame: it lets go at once too.
	care.hold_feedback.release()
	pose.update_pose(0.016)
	_expect(pose.weight() < 1.0, "Letting go starts the same frame")
	await _settle(player, pose)
	_expect(pose.weight() == 0.0 and pose.hand_targets().is_empty(), "...and removes the IK")
	await process_frame
	_expect(left.global_position.distance_to(rest_left) < 0.05 and right.global_position.distance_to(rest_right) < 0.05,
		"Both hands are back where they were (%.3f, %.3f m off)" % [left.global_position.distance_to(rest_left),
		right.global_position.distance_to(rest_right)])
	player.seat_node_path = NodePath()
	left.queue_free()
	right.queue_free()


func _check_carry_squeeze(player: Player, box: DeliveryPackage) -> void:
	var pose: Node3D = player.get_node(^"PlayerHoldPose")
	var carry: Node3D = player._carry_pose
	var care: Node = player._cargo_care
	player.carried_package = box
	for _i: int in 8:
		carry.update_pose(box, 1.0, 0.1)
		await process_frame
	var open_gap: float = _hand_gap(carry)
	care.hold_feedback.set_input(box, true)
	pose.update_pose(0.016)
	_expect(pose.hand_targets().is_empty(), "A carrying player gets no new IK: the carry pose holds the box")
	await _settle(player, pose)
	for _i: int in 3:
		carry.update_pose(box, 1.0, 0.1)
	var squeezed_gap: float = _hand_gap(carry)
	_expect(is_equal_approx(float(carry.squeeze), 1.0),
		"The carry hands are fully pressed in (%.2f)" % float(carry.squeeze))
	_expect(squeezed_gap < open_gap - 0.04 and squeezed_gap > open_gap - 0.06,
		"The hands pull in a few centimetres each (gap %.3f -> %.3f m)" % [open_gap, squeezed_gap])
	care.hold_feedback.release()
	await _settle(player, pose)
	for _i: int in 3:
		carry.update_pose(box, 1.0, 0.1)
	_expect(float(carry.squeeze) == 0.0 and absf(_hand_gap(carry) - open_gap) < 0.001, "Releasing opens them again")

	# Seated with the box on the lap: the carry pose is off, so the reach is what grips it.
	player.seat_node_path = SEAT
	care.hold_feedback.set_input(box, true)
	pose.update_pose(0.016)
	_expect(pose.hand_targets().size() == 2, "A seated passenger with the box on their lap reaches for it")
	care.hold_feedback.release()
	await _settle(player, pose)
	player.seat_node_path = NodePath()
	player.carried_package = null


func _hand_gap(carry: Node3D) -> float:
	var targets: Array = carry.get(&"_targets")
	return (targets[0] as Node3D).global_position.distance_to((targets[1] as Node3D).global_position)


func _check_remote(box: DeliveryPackage) -> void:
	var remote: Player = await _spawn(2)
	var pose: Node3D = remote.get_node(^"PlayerHoldPose")
	remote.seat_node_path = SEAT
	_expect(not remote.is_local(), "Player_2 is another peer's copy here")
	pose.update_pose(0.1)
	_expect(pose.weight() == 0.0, "A remote copy holds nothing while care_state says nobody does")
	# Its own machine's flag is not the source for a remote copy.
	remote._cargo_care.hold_feedback.set_input(box, true)
	pose.update_pose(0.1)
	_expect(pose.weight() == 0.0, "...and ignores the local flag")
	remote._cargo_care.hold_feedback.release()

	var state: Dictionary = box.care_state.duplicate()
	state["held_by"] = 3
	box.care_state = state
	await _settle(remote, pose)
	_expect(pose.weight() == 0.0, "Someone else's hold does not move this player's hands")

	state["held_by"] = 2
	box.care_state = state
	pose.set(&"_scan_left", 0.0)
	pose.update_pose(0.016)
	_expect(pose.weight() > 0.0 and pose.gripped_package() == box, "held_by this peer: the hands engage")
	await _settle(remote, pose)
	_expect(is_equal_approx(pose.weight(), 1.0) and pose.hand_targets().size() == 2,
		"...and reach the box with both hands on every peer")

	state["held_by"] = 0
	box.care_state = state
	await _settle(remote, pose)
	_expect(pose.weight() == 0.0 and pose.hand_targets().is_empty(), "The host clearing held_by lets go")

	state["helped_by"] = 2
	box.care_state = state
	await _settle(remote, pose)
	_expect(is_equal_approx(pose.weight(), 1.0), "A helper's hold (helped_by) grips the box too")
	state["helped_by"] = 0
	box.care_state = state
	await _settle(remote, pose)
	_expect(pose.weight() == 0.0, "...and lets go the same way")
	remote.seat_node_path = NodePath()
	remote.queue_free()


func _check_blockers(player: Player, box: DeliveryPackage) -> void:
	var pose: Node3D = player.get_node(^"PlayerHoldPose")
	var care: Node = player._cargo_care
	player.seat_node_path = SEAT
	care.hold_feedback.set_input(box, true)
	await _settle(player, pose)
	_expect(pose.weight() == 1.0, "Holding again: the hands are on the box")

	player.seat_node_path = NodePath("Somewhere/DriverEyePoint")
	pose.update_pose(0.016)
	_expect(pose.weight() == 0.0 and pose.hand_targets().is_empty(), "The driver's hands stay on the wheel")
	player.seat_node_path = SEAT
	await _settle(player, pose)
	_expect(pose.weight() == 1.0, "...and the grip is back off the driver's seat")

	player._ragdolled = true
	pose.update_pose(0.016)
	_expect(pose.weight() == 0.0, "A ragdoll fall lets go of the grip")
	player._ragdolled = false
	await _settle(player, pose)

	player._gel_effects_component.knockout_cause = 1
	pose.update_pose(0.016)
	_expect(pose.weight() == 0.0, "A knocked-out gel lets go")
	player._gel_effects_component.knockout_cause = 0
	await _settle(player, pose)

	player.anim_state = PlayerAnimator.EMOTE_CLIPS[0]
	pose.update_pose(0.016)
	_expect(pose.weight() == 0.0, "An emote owns the arms while it plays")
	player.anim_state = Player.ANIM_IDLE
	await _settle(player, pose)
	_expect(pose.weight() == 1.0, "...and the grip comes back after it")

	# On foot, helping a box that is not in the arms: the right hand is the phone's if it is up.
	player.seat_node_path = NodePath()
	await _settle(player, pose)
	_expect(pose.weight() == 1.0 and pose.hand_targets().size() == 2, "Helping on foot reaches for the box too")
	var phone: Node3D = player.get_node(^"PlayerPhoneProp")
	phone.set(&"phone_raised", true)
	pose.update_pose(0.016)
	_expect(pose.weight() == 0.0, "The phone in the right hand wins over the grip")
	phone.set(&"phone_raised", false)
	await _settle(player, pose)
	_expect(pose.weight() == 1.0, "...and the grip is back when the phone goes down")
	care.hold_feedback.release()
	await _settle(player, pose)


func _settle(_player: Player, pose: Node3D) -> void:
	for _i: int in 6:
		pose.update_pose(0.1)
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + message)
