extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_seat_tending.gd
##
## N-228.4: several seats look at the same package mount (RightSeat3 owns its
## mount, LeftSeat3 and CenterSeat also tend it; RackSeat1 tends the bays that
## LeftSeat1 and LeftSeat2 own). A box has one tender, and the last one to sit
## down used to take it from the one already minding it, leaving them seated
## with a HUD the host ignored. seat_tending.gd (called by seat_point.gd and
## PackageRescue.peer_left) makes it:
##   - a neighbour sitting down does not take the box from its tender;
##   - the mount's own seat does take it from a neighbour, who is told;
##   - when the tender gets up or drops out, the other sitter takes over, and
##     if the neighbour leaves instead the tender is unchanged.
## Peers other than the host are simulated (authority only), so the log shows
## "unknown peer" for RPCs sent to them; the host's player checks what is told.

const VEHICLE: String = "World/Vehicle/CargoBay/"

var _failures: int = 0
var _level: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(_level)
	current_scene = _level
	await process_frame
	await physics_frame
	# The host's own player (peer 1) is the one whose RPCs land here; the other
	# crewmates are only players with another peer id as authority, so the
	# engine logs "unknown peer" for the RPCs addressed to them. What they
	# would be told is checked on the host's player.
	var host: Node = _player(1)
	var packages: Array[Node] = []
	packages.assign(root.get_tree().get_nodes_in_group(&"cargo"))

	# RightSeat3 owns its mount; CenterSeat and LeftSeat3 look at it as well.
	var box: Node = packages[0]
	var mount: Node = _level.get_node(VEHICLE + "RightSeat3PackageMount/InteractionArea")
	mount.call(&"store", box)
	var owner_seat: Node = _seat("RightSeat3EyePoint")
	var neighbour: Node = _seat("CenterSeatEyePoint")
	var neighbour_two: Node = _seat("LeftSeat3EyePoint")
	var owner: Node = _player(2)
	var third: Node = _player(3)
	await process_frame

	owner_seat.call(&"interact", owner)
	_expect(_tender(box) == 2, "The owner seat's sitter tends the box on its mount (got %d)" % _tender(box))
	neighbour.call(&"interact", host)
	_expect(host.get(&"seat_node_path") == neighbour.get_parent().get_path(), "The neighbour sits down")
	_expect(_tender(box) == 2, "A neighbour sitting down does not take the box (got %d)" % _tender(box))
	_expect(host.get(&"tended_package") == null, "...and the neighbour is not told they tend it")
	neighbour_two.call(&"interact", third)
	_expect(_tender(box) == 2, "A second neighbour does not take it either (got %d)" % _tender(box))

	host.call(&"leave_seat")
	_expect(_tender(box) == 2, "A neighbour getting up leaves the tender alone (got %d)" % _tender(box))
	neighbour.call(&"interact", host)
	_expect(_tender(box) == 2, "...also when they sit again (got %d)" % _tender(box))

	# The tender gets up: the box passes to a sitter facing the mount (the other
	# neighbour first leaves, so the one we can look at is the heir).
	neighbour_two.call(&"release_occupant", 3)
	owner_seat.call(&"release_occupant", 2)
	_expect(_tender(box) == 1, "The tender getting up hands the box to a neighbour (got %d)" % _tender(box))
	_expect(host.get(&"tended_package") == box, "The heir is told which box they tend")
	var tenders: int = 0
	for peer_id: int in [1, 2, 3]:
		if _tends_any(peer_id):
			tenders += 1
	_expect(tenders == 1, "Only one sitter tends it afterwards (got %d)" % tenders)

	# The owner comes back: the box returns to the owner seat, the heir is told.
	owner_seat.call(&"interact", owner)
	_expect(_tender(box) == 2, "The owner sitting down takes it back from a neighbour (got %d)" % _tender(box))
	_expect(host.get(&"tended_package") == null, "The neighbour who was minding it is told it is no longer theirs")

	# The tender drops out while a neighbour sits (PackageRescue.peer_left, run
	# by every package on peer_disconnected): the neighbour takes over.
	box.call(&"peer_left", 2)
	owner.free()
	_expect(_tender(box) == 1, "A disconnected tender's box goes to the sitter beside it (got %d)" % _tender(box))
	_expect(host.get(&"tended_package") == box, "...and they are told")

	# Nobody else facing the mount: it is left without a tender, as before.
	host.call(&"leave_seat")
	_expect(_tender(box) == 0, "With nobody left facing the mount nobody tends it (got %d)" % _tender(box))

	# A stale hand-over: the host's "you tend this" crossing the player's own
	# leave must not leave a standing player holding a box.
	host.call(&"tend_package", box.get_path())
	_expect(host.get(&"tended_package") == null, "A standing player ignores a box handed to them")
	host.set(&"tended_package", box)
	_seat("RackSeat3EyePoint").call(&"interact", host)
	_expect(host.get(&"tended_package") == null, "Sitting down starts without the box tended before")
	host.call(&"leave_seat")

	# A box in someone's hands is theirs when they sit with it, whoever minded
	# it before: CenterSeat's sitter tends the box in RightSeat3's bay, the host
	# takes it out and sits at LeftSeat3 holding it.
	var minder: Node = _player(2)
	var courier: Node = _player(3)
	await process_frame
	neighbour.call(&"interact", minder)
	_expect(_tender(box) == 2, "A neighbour tends the box when alone with it (got %d)" % _tender(box))
	box.call(&"take_by", host)
	neighbour_two.call(&"interact", host)
	_expect(host.get(&"seat_node_path") == neighbour_two.get_parent().get_path(), "The host sits with the box in hand")
	_expect(_tender(box) == 1 and host.get(&"tended_package") == box,
		"Sitting with a box in hand takes it from its old tender (got %d)" % _tender(box))
	_expect(bool(box.call(&"is_aboard")), "The box on the lap counts as aboard")

	# That lap reserves the column's only bay: nobody else sits down with a box.
	var spare: Node = _spare_box(4)
	spare.call(&"take_by", courier)
	neighbour.call(&"release_occupant", 2)
	_expect(not bool(neighbour.call(&"can_interact", courier)),
		"A second neighbour cannot sit with a box while the bay is promised to a lap")
	_expect(bool(neighbour.call(&"can_interact", minder)), "...but one with empty hands can")
	host.call(&"leave_seat")
	mount.call(&"store", box)
	_expect(host.get(&"carried_package") == null, "The host's hands are empty again")
	box.call(&"set_tender", 0)

	# The wheel's seat never inherits a box (it used to name LeftSeat1's bay).
	var driver_seat: Node = _level.get_node("World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea")
	driver_seat.get_parent().get_parent().get_parent().call(&"set_door_open", &"cab_left", true)
	var driver: Node = _player(6)
	await process_frame
	driver_seat.call(&"interact", driver)
	_expect(int(driver_seat.call(&"seated_peer")) == 0 and not bool(driver_seat.call(&"looks_at_mount", mount)),
		"The driver's seat looks after no mount")
	var column_bay: Node = _level.get_node(VEHICLE + "LeftSeat1PackageMount/InteractionArea")
	var driven_box: Node = _spare_box(3)
	column_bay.call(&"store", driven_box)
	var column_seat: Node = _seat("LeftSeat1EyePoint")
	var column_sitter: Node = _player(4)
	await process_frame
	column_seat.call(&"interact", column_sitter)
	_expect(_tender(driven_box) == 4, "The bay's own sitter tends its box (got %d)" % _tender(driven_box))
	column_seat.call(&"release_occupant", 4)
	_expect(_tender(driven_box) == 0, "Getting up does not pass the box to the driver (got %d)" % _tender(driven_box))
	driver_seat.call(&"release_occupant", 6)
	driven_box.call(&"release_mount")

	# The same on a rack column: LeftSeat1 owns the bay RackSeat1 also tends.
	var bay: Node = _level.get_node(VEHICLE + "LeftSeat1PackageMount/InteractionArea")
	var rack_box: Node = packages[1]
	bay.call(&"store", rack_box)
	var column_owner: Node = _seat("LeftSeat1EyePoint")
	var rack: Node = _seat("RackSeat1EyePoint")
	var fourth: Node = _player(4)
	await process_frame
	rack.call(&"interact", host)
	_expect(_tender(rack_box) == 1 and host.get(&"tended_package") == rack_box,
		"Alone, the rack seat tends the bay's box (got %d)" % _tender(rack_box))
	column_owner.call(&"interact", fourth)
	_expect(_tender(rack_box) == 4, "The bay's own seat takes it from the rack seat (got %d)" % _tender(rack_box))
	_expect(host.get(&"tended_package") == null, "The rack sitter is told")
	column_owner.call(&"release_occupant", 4)
	_expect(_tender(rack_box) == 1 and host.get(&"tended_package") == rack_box,
		"The rack sitter gets it back when the owner stands (got %d)" % _tender(rack_box))
	column_owner.call(&"interact", fourth)
	_expect(_tender(rack_box) == 4, "The owner sitting down again takes it back (got %d)" % _tender(rack_box))
	host.call(&"leave_seat")
	_expect(_tender(rack_box) == 4, "The rack sitter getting up leaves the owner tending (got %d)" % _tender(rack_box))
	rack.call(&"interact", host)
	_expect(_tender(rack_box) == 4, "A rack sitter arriving later does not take it (got %d)" % _tender(rack_box))
	column_owner.call(&"release_occupant", 4)
	_expect(_tender(rack_box) == 1 and host.get(&"tended_package") == rack_box,
		"The owner leaving hands it to the rack sitter (got %d)" % _tender(rack_box))

	# A rack seat facing two bays keeps the one nobody minds.
	host.call(&"leave_seat")
	var column_owner_two: Node = _player(7)
	await process_frame
	column_owner.call(&"interact", column_owner_two)
	_expect(_tender(rack_box) == 7, "The bay's owner tends its box again (got %d)" % _tender(rack_box))
	var second_bay: Node = _level.get_node(VEHICLE + "LeftSeat2PackageMount/InteractionArea")
	var other_box: Node = _spare_box(2)
	second_bay.call(&"store", other_box)
	rack.call(&"interact", host)
	_expect(_tender(rack_box) == 7,
		"The rack seat leaves the first bay's box to its tender (got %d)" % _tender(rack_box))
	_expect(_tender(other_box) == 1 and host.get(&"tended_package") == other_box,
		"...and tends the other bay's box instead (got %d)" % _tender(other_box))

	courier.free()  # still holding a box that goes with the level
	_level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: seats sharing a mount keep one tender and hand the box over when they leave")
	quit(_failures)


func _seat(seat_name: String) -> Node:
	return _level.get_node(VEHICLE + seat_name + "/InteractionArea")


## A player whose multiplayer authority is `peer_id` (host-side simulation of a crewmate).
func _player(peer_id: int) -> Node:
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.set_multiplayer_authority(peer_id)
	root.add_child(player)
	return player


## A loose extra box (the level only declares a few).
func _spare_box(index: int) -> Node:
	var box: Node = load("res://scenes/gameplay/package/package.tscn").instantiate()
	box.set(&"package_id", StringName("seat_tending_spare_%d" % index))
	box.name = "SeatTendingSpare%d" % index
	box.set(&"freeze", true)
	_level.add_child(box)
	return box


func _tender(package: Node) -> int:
	return int(package.get(&"tender_peer_id"))


func _tends_any(peer_id: int) -> bool:
	for package: Node in root.get_tree().get_nodes_in_group(&"cargo"):
		if _tender(package) == peer_id:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
