extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_merit.gd
##
## S-102 merit contract: every package milestone uses the declared value,
## one fact cannot score twice, package input chooses the responsible peer,
## and rescue, hand-over and complaint-saving photos reach CrewProgression.

class MilestoneTrap:
	extends ITrapBehavior

	func queue_twice(milestone: StringName) -> void:
		_add_milestone(milestone)
		_add_milestone(milestone)


const EXPECTED_POINTS := {
	&"defused": 25,
	&"rescued": 20,
	&"calmed": 10,
	&"dried": 10,
	&"leveled": 8,
	&"sequence": 8,
	&"handover": 5,
	&"photo_saved": 15,
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crew: Node = root.get_node(^"CrewProgression")
	crew.call(&"reset_campaign")
	_test_points_table(crew)
	crew.call(&"reset_campaign")
	await _test_package_attribution_and_actions(crew)
	crew.call(&"reset_campaign")
	_test_photo_saved(crew)
	crew.call(&"reset_campaign")
	root.get_node(^"RunManager").call(&"reset_run")
	if _failures == 0:
		print("PASS: merit milestones score once for the responsible player and relay package, carry and photo actions")
	quit(_failures)


func _test_points_table(crew: Node) -> void:
	var peer_id: int = 9
	var expected_total: int = 0
	var points: Dictionary = (crew.get_script() as Script).get_script_constant_map()[&"MERIT_POINTS"]
	_expect(points == EXPECTED_POINTS, "The merit table keeps the designed values (got %s)" % points)
	for milestone: StringName in EXPECTED_POINTS:
		expected_total += int(EXPECTED_POINTS[milestone])
		var package_id := StringName("table_%s" % milestone)
		_expect(bool(crew.call(&"award_milestone", peer_id, package_id, milestone, 1)),
			"%s grants its table value" % milestone)
		_expect(not bool(crew.call(&"award_milestone", peer_id, package_id, milestone, 1)),
			"%s cannot score the same occurrence twice" % milestone)
	_expect(int(crew.merit.get(peer_id, 0)) == expected_total,
		"All milestone values stay personal (got %d, expected %d)" % [int(crew.merit.get(peer_id, 0)), expected_total])
	_expect(not crew.merit.has(1), "The host does not receive another peer's merit")


func _test_package_attribution_and_actions(crew: Node) -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var run: Node = root.get_node(^"RunManager")
	run.call(&"start_run")
	var package: DeliveryPackage = level.get_node(^"World/Package") as DeliveryPackage
	var player: Node = level.get(&"local_player")

	# The trap queue deduplicates repeated reports in one frame, and the
	# package gives the fact to the last passenger with useful input.
	var trap := MilestoneTrap.new()
	trap.on_setup(package, {})
	trap.queue_twice(&"defused")
	package.set(&"trap_behavior", trap)
	package.set(&"_last_tender_peer", 7)
	package.call(&"_award_pending_trap_milestones")
	package.call(&"_award_pending_trap_milestones")
	_expect(int(crew.merit.get(7, 0)) == 25,
		"A repeated trap milestone scores once for the last tender (got %d)" % int(crew.merit.get(7, 0)))
	_expect(not crew.merit.has(1), "Trap merit is not reassigned to the host")
	_expect(not DeliveryPackage._has_useful_input({"calm": false}), "Released input is not recorded as useful")
	_expect(DeliveryPackage._has_useful_input({"steady": true}), "An active hold is useful input")

	# A loose box picked up outside the truck only becomes a rescue once it
	# reaches a mount again.
	package.set(&"trap_behavior", package.trap_definition.call(&"create_behavior"))
	package.trap_behavior.call(&"on_setup", package, package.trap_definition.get(&"params"))
	package.global_position = Vector3(80.0, 2.0, 80.0)
	package.call(&"take_by", player)
	_expect(int(crew.merit.get(1, 0)) == 0, "Picking up a fallen box alone is not yet a rescue")
	var mount: Node = level.get_node(^"World/Vehicle/CargoBay/LeftShelfPackageMount/InteractionArea")
	mount.call(&"store", package)
	_expect(int(crew.merit.get(1, 0)) == 20, "Remounting the recovered box grants rescued merit")

	# The transfer path awards the giver, not the recipient. Both local test
	# players use peer 1, so the delta proves the hand-over hook itself.
	var recipient: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	recipient.name = "MeritRecipient"
	level.get_node(^"World").add_child(recipient)
	await process_frame
	recipient.global_position = player.global_position
	package.call(&"take_by", player)
	package.call(&"request_transfer", recipient.get_path())
	_expect(int(crew.merit.get(1, 0)) == 25, "A valid hand-to-hand transfer grants 5 merit to the giver")

	run.call(&"reset_run")
	level.free()
	await process_frame


func _test_photo_saved(crew: Node) -> void:
	var run: Node = root.get_node(^"RunManager")
	run.call(&"reset_run")
	run.call(&"start_run")
	run.call(&"register_delivery", 0, &"delivered_ruined", &"photo_box")
	_expect(bool(run.call(&"attach_delivery_photo", 0)), "A first delivery photo is accepted")
	_expect(int(crew.merit.get(1, 0)) == 15, "A photo that dismisses a damaged-delivery complaint grants 15 merit")
	_expect(not bool(run.call(&"attach_delivery_photo", 0)), "The same house cannot file the photo twice")
	_expect(int(crew.merit.get(1, 0)) == 15, "A repeated photo does not duplicate merit")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
