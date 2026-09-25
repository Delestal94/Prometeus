extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_door_reactions.gd
##
## The neighbour at the door (N-604, door_reaction.gd, DeliveryHouse.REACTION_LINES):
## - five lines per outcome, and the one said is the same for the same seed,
##   house and outcome (every peer reads the same line);
## - it reacts to the relayed record (house_delivery_recorded), so clients see
##   it too, and only the house the record is about reacts;
## - happy hop for a good box, a look-over for a dented one, both hands to
##   the head for a ruined one -- with the line in a speech bubble;
## - a box that isn't theirs: out, head shake, "la mía es la A-2", back in;
## - nobody rang: a note on the door, and no neighbour.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for outcome: StringName in [&"delivered_ok", &"delivered_at_risk", &"delivered_ruined", &"wrong", &"missed"]:
		var lines: Array = DeliveryHouse.REACTION_LINES.get(outcome, [])
		_expect(lines.size() == 5, "Five lines for %s (got %d)" % [outcome, lines.size()])
	_expect(tr(DeliveryHouse.REACTION_LINES[&"delivered_ok"][0]) != DeliveryHouse.REACTION_LINES[&"delivered_ok"][0], "The lines are translation keys with a text behind them")
	var picked: String = DoorReaction.pick_line(DeliveryHouse.REACTION_LINES[&"delivered_ok"], 4242, 1, &"delivered_ok")
	_expect(picked == DoorReaction.pick_line(DeliveryHouse.REACTION_LINES[&"delivered_ok"], 4242, 1, &"delivered_ok"),
		"Same seed, house and outcome: same line")
	var variety: Dictionary = {}
	for seed_value: int in range(1, 40):
		variety[DoorReaction.pick_line(DeliveryHouse.REACTION_LINES[&"delivered_ok"], seed_value, 0, &"delivered_ok")] = true
	_expect(variety.size() >= 4, "Across seeds the lines vary (%d different)" % variety.size())

	var bus: Node = root.get_node(^"/root/EventBus")
	var houses: Array[DeliveryHouse] = []
	for index: int in range(5):
		var house := DeliveryHouse.new()
		house.house_index = index
		house.position = Vector3(index * 20.0, 0.0, 0.0)
		root.add_child(house)
		houses.append(house)
	await process_frame

	# Good box.
	bus.emit_signal(&"house_delivery_recorded", 0, &"delivered_ok", &"")
	var ok_reaction: DoorReaction = houses[0].reaction
	_expect(ok_reaction.resident.visible and ok_reaction.last_action == &"happy", "A good box: the neighbour comes out happy (%s)" % ok_reaction.last_action)
	_expect(ok_reaction.bubble.visible and ok_reaction.bubble.text in _said(&"delivered_ok"),
		"...and says one of the happy lines ('%s')" % ok_reaction.bubble.text)
	_expect(not houses[1].reaction.resident.visible and not houses[1].reaction.bubble.visible, "Only the house the record is about reacts")

	# Dented box.
	bus.emit_signal(&"house_delivery_recorded", 1, &"delivered_at_risk", &"")
	_expect(houses[1].reaction.last_action == &"inspect" and houses[1].reaction.bubble.text in _said(&"delivered_at_risk"),
		"A dented box gets looked over, with a suspicious line")

	# Ruined box: both hands up to the head.
	bus.emit_signal(&"house_delivery_recorded", 2, &"delivered_ruined", &"")
	var ruined: DoorReaction = houses[2].reaction
	_expect(ruined.last_action == &"grab_head" and ruined.bubble.text in _said(&"delivered_ruined"),
		"A ruined box: hands to the head, and an outraged line")
	for frame: int in range(20):
		await process_frame
	var skeleton := ruined.resident.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		# SkeletonIK3D is a SkeletonModifier3D: its pose only exists between
		# the modifier pass and the skin update, so it's read in there (as in
		# test_driver_ik.gd).
		var hands: Dictionary = {}
		var capture := func() -> void:
			var head: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin)
			for side: String in ["L", "R"]:
				var hand: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("Hand_" + side)).origin
				var upper: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("UpperArm_" + side)).origin
				hands[side] = [skeleton.to_global(hand).distance_to(head), signf(hand.x) == signf(upper.x)]
		skeleton.skeleton_updated.connect(capture)
		for frame: int in range(2):
			await process_frame
		skeleton.skeleton_updated.disconnect(capture)
		for side: String in ["L", "R"]:
			_expect(hands.has(side) and float(hands[side][0]) < 0.45, "The %s hand is up at the head (%.2f m away)" % [side, float(hands.get(side, [INF])[0])])
			_expect(hands.has(side) and bool(hands[side][1]), "The %s hand grabs its own side of the head (arms don't cross)" % side)
	else:
		_expect(false, "The neighbour has a skeleton to pose")

	# Somebody else's box.
	bus.emit_signal(&"house_refused_package", 3, "B-2")
	var refused: DoorReaction = houses[3].reaction
	_expect(refused.resident.visible and refused.last_action == &"shake_head", "Not their box: out they come, shaking their head")
	_expect(refused.bubble.text.contains("B-2"), "...naming the box they're waiting for ('%s')" % refused.bubble.text)
	await create_timer(DoorReaction.WRONG_SECONDS + 0.3).timeout
	_expect(not refused.resident.visible, "...and back inside: the house still waits")

	# Nobody rang.
	bus.emit_signal(&"house_delivery_recorded", 4, &"missed", &"")
	var missed: DoorReaction = houses[4].reaction
	_expect(missed.note != null and missed.note.text in _said(&"missed"), "Missed: a note on the door")
	_expect(not missed.resident.visible, "...and nobody comes out")

	for house: DeliveryHouse in houses:
		house.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the neighbour reacts to every outcome, on every peer, with the same line for the same seed")
	quit(_failures)


## The lines as shown: REACTION_LINES holds translation keys (N-605).
func _said(outcome: StringName) -> Array:
	return DeliveryHouse.REACTION_LINES[outcome].map(func(key: String) -> String: return tr(key))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
