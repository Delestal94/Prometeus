extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_forklift_world.gd
##
## The forklift a player drives in the shed (expansion D-0606.b: company_forklift.gd, forklift_view.gd,
## company_pallets.gd's fork_act / fork_state, pallet_yard_view.gd's rack pallets, CompanyShed.rack_slots() and
## station_for(&"forklift"), pallet_jack_point.gd's seat, CompanyNet fork_act):
## - the shed has pallet slots on its shelves (one per deck, ids "<shelf>-<level>") and the forklift waits at its
##   home, on the floor, clear of the jack and facing the truck's gate;
## - a player gets on it (the seat point, only with nobody driving and no box in hand), and it follows their player:
##   the host judges every request by where the driver stands, the other peers draw it there;
## - with the forks down and the truck parked it takes a pallet off the bed (one event, `by` forklift): the pallet is
##   drawn on its forks and not on the jack, the jack's forks refuse while it holds it, the stock does not move yet;
## - the mast: a request moves the forks for at most FORKLIFT_MAST_BURST_S, the host's height rides every event and
##   a second peer integrates the same; held up to the high deck, a pallet is left on a rack slot: the stock rises
##   once, the pallet is drawn on the rack where the slot is, on both peers;
## - refused, changing nothing: a pallet to a taken slot or at the wrong level or out of reach (no_rack), a pallet
##   taken at a level where there is none (no_pallet), on the floor with the forks up, a driver who is not the driver
##   (not_driver), a second driver (taken), bad data (a dir of 2, an unknown act, NaN, a negative peer);
## - the pallet comes down from the rack and is left on the floor; the stock never counts it twice; leaving parks the
##   forklift where it stood with its forks as they were;
## - a peer that joins late gets the forklift (driver, forks, pallet on them) and the rack pallets from the snapshot
##   part, and a part that does not fit is refused changing nothing;
## - the host lets the forklift go when its driver's player is gone;
## - the real company world (company_root.tscn, solo): the seat point gets the host's player on the forklift.
## - a real Player with the interact override (PlayerInteraction): the interact key and the prompt are the forklift's.
## Not covered: the real keyboard and the ENet pair (a client's fork_act over the wire; the same CompanyNet requests
## the pair tests already carry).

const HEN: StringName = &"hen"
const LAMP: StringName = &"antique_lamp"
const DAY: int = 2
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
## The real root saves here on leaving, never in the game's slot.
const DIR: String = "user://test_company_forklift_world"
const TOP: StringName = &"shelf_1-1"

## A player: a body in the group, with its own peer, hands and reach.
class FakePlayer extends Node3D:
	var carried_package: Variant = null

	func reach_origin() -> Vector3:
		return global_position + Vector3.UP * 0.6

class FakeCompany extends RefCounted:
	var day: int = 2
	var warehouse_stage: int = 0

var _failures: int = 0
var _state: DefaultShed.ScratchState
var _company := FakeCompany.new()
var _schedule := SupplierSchedule.new()
var _minute: Array[float] = [0.0]
var _net: CompanyNet
var _shed: CompanyShed
var _truck: SupplierTruckView
var _mirror: CompanyNet
var _mirror_shed: CompanyShed
var _mirror_truck: SupplierTruckView
var _driver: FakePlayer
var _refusals: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_world()
	await _test_player_override()
	await _test_root()
	if _failures == 0:
		print("PASS: a player drives the forklift, takes a pallet off the truck and leaves it on a high rack")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


# --- The world ---


func _test_world() -> void:
	_state = DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(_state)
	var stock: Inventory = _state.stock()
	_schedule.place(DAY - 1, [{"product": HEN, "qty": 30}, {"product": LAMP, "qty": 10}])
	_minute[0] = float(SupplierSchedule.arrival_minute()) + 30.0
	_net = CompanyNet.new()
	_net.name = "ForkNet"
	_net.company = _state
	_net.inventory = stock
	root.add_child(_net)
	_shed = CompanyShed.new()
	_shed.name = "HostShed"
	root.add_child(_shed)
	_shed.follow(_net)
	_shed.rebuild(_state, stock)
	_truck = _make_truck(_net, _shed, "HostTruck")
	_net.stations = _shed.station_for
	_net.request_rejected.connect(func(_rid: int, reason: StringName) -> void: _refusals.append(reason))
	_net.event_applied.connect(func(event_seq: int, kind: StringName, data: Dictionary) -> void:
		_mirror._receive(event_seq, kind, data))
	_mirror = CompanyNet.new()
	_mirror.name = "MirrorNet"
	_mirror.company = _state
	_mirror.inventory.from_dict(stock.to_dict())
	root.add_child(_mirror)
	_mirror_shed = CompanyShed.new()
	_mirror_shed.name = "MirrorShed"
	root.add_child(_mirror_shed)
	_mirror_shed.follow(_mirror)
	_mirror_shed.rebuild(_state, _mirror.inventory)
	_mirror_truck = _make_truck(_mirror, _mirror_shed, "MirrorTruck")
	# Both nets are "the host" here (no peer): only the first one's forklift may ask or let go.
	_mirror_shed.yard.forklift.net = null
	_driver = FakePlayer.new()
	_driver.name = "Driver"
	root.add_child(_driver)
	_driver.add_to_group(&"player")
	await process_frame

	var yard: PalletYardView = _shed.yard
	var fork: ForkliftView = yard.forklift
	var state: CompanyForklift = _net.pallets.forklift
	_test_geometry()
	var units_before: int = _net.inventory.total_units()
	var loaded: Dictionary = _net.pallets.loaded_event(DAY, _schedule.pallets_for(DAY), _net.inventory)
	_expect(_net.publish(CompanyPallets.LOADED, loaded), "The truck brings the day's three pallets")
	var bed: Array[StringName] = _net.pallets.book.ids_at(PalletJack.AT_BED)
	_expect(bed == [&"d2_antique_lamp_1", &"d2_hen_1", &"d2_hen_2"], "... on its bed (%s)" % [bed])

	# Getting on: the seat, only for a free forklift and empty hands.
	_stand(PalletYardView.fork_home(0), PI)
	_expect(fork.seat_point.get_prompt() != "" and not fork.is_local_driving() and state.driver == 0,
		"Nobody drives at the start: the seat has its prompt")
	_driver.carried_package = Node3D.new()
	var boarded: Array[int] = [0]
	fork.used.connect(func(_how: StringName, _peer: int, _from: Vector3) -> void: boarded[0] += 1)
	fork.seat_point.interact(_driver)
	_expect(boarded[0] == 0, "A player with a box in hand does not get on")
	(_driver.carried_package as Node).free()
	_driver.carried_package = null
	var seq_before: int = _net.seq
	_expect(PalletJackUse.use(_net, yard, PalletJackPoint.ACTION_BOARD, 1, _driver.global_position)
		== PalletJackUse.RESULT_BOARDED and _net.seq == seq_before + 1, "Using the seat is one event")
	_expect(state.driver == 1 and _mirror.pallets.forklift.driver == 1 and not fork.seat_point.can_interact(_driver)
		and fork.seat_point.get_prompt() == "" and _mirror_shed.yard.forklift.seat_point.taken,
		"Peer 1 drives it, on both peers, and the seat is taken")
	_expect(fork.is_local_driving() and _driver.has_meta(&"interact_override"),
		"The driver's own peer takes the interact key (PlayerInteraction's override)")
	var seq_taken: int = _net.seq
	_refusals.clear()
	_expect(PalletJackUse.use(_net, yard, PalletJackPoint.ACTION_BOARD, 1, _driver.global_position)
		== PalletJackUse.REASON_REFUSED and _refusals == [CompanyForklift.REASON_TAKEN] and _net.seq == seq_taken,
		"Getting on a second time is refused: taken (%s)" % [_refusals])

	# It follows the player, on every peer.
	_stand(Vector2(-3.0, 4.0), 0.5)
	await process_frame
	_expect(_pose_of(fork) == [Vector3(-3.0, 0.0, 4.0), 0.5] and _pose_of(_mirror_shed.yard.forklift) == _pose_of(fork),
		"The forklift is under its driver and faces where they face, on both peers (%s)" % [_pose_of(fork)])
	_expect((fork.pose()["body"] as Vector2).is_equal_approx(Vector2(-3.0, 4.0))
		and absf(float(fork.pose()["yaw"]) - 0.5) < 0.001,
		"... and the host judges by that pose")

	# The mast keys, as the view reads them each frame: a request when pressed, one more every 0.35 s while held and
	# one to stop; never one per frame.
	fork.keys_need_capture = false
	var asked: int = _net.seq
	Input.action_press(&"forklift_mast_up")
	await create_timer(1.0).timeout
	var while_held: int = _net.seq - asked
	_expect(while_held >= 2 and while_held <= 4 and state.mast_dir == 1,
		"Holding the mast key asks now and then, not every frame (%d events in 1 s)" % while_held)
	Input.action_release(&"forklift_mast_up")
	await process_frame
	await process_frame
	_expect(state.mast_dir == 0 and state.height_at(Time.get_ticks_msec()) > 0.3,
		"Letting go stops the forks where the host left them (%.2f m)" % state.height_at(Time.get_ticks_msec()))
	await _publish_height(0.0)

	# Taking a pallet off the bed: forks down, the rear in reach of the forks.
	var rear: Vector2 = SupplierTruckView.rear_of(0)
	_stand(rear + Vector2(0.0, -CompanyTuning.FORKLIFT_TIP_M - 0.3), PI)
	var tip: Vector2 = CompanyForklift.tip_of(fork.pose()["body"], fork.pose()["yaw"])
	_expect(tip.distance_to(rear) < 0.4 and fork.fork_height() == 0.0, "The forks point at the truck's rear, down")
	var lamp: StringName = &"d2_antique_lamp_1"
	var seq_pick: int = _net.seq
	_work()
	_expect(_net.seq == seq_pick + 1 and _net.pallets.book.carrying == lamp and state.holds
		and _mirror.pallets.forklift.holds, "Work takes the first pallet of the bed: one event, on the forks")
	_expect(fork.carried_id() == lamp and yard.jack.carried_id() == &""
		and _truck.bed_ids() == [&"d2_hen_1", &"d2_hen_2"]
		and _mirror_shed.yard.forklift.carried_id() == lamp and _mirror_shed.yard.jack.carried_id() == &"",
		"It is drawn on the forklift's forks, not on the jack, and gone from the bed (both peers)")
	_expect(_net.inventory.total_units() == units_before, "Carried, its units are not in the stock yet")
	_refusals.clear()
	var seq_jack: int = _net.seq
	_net.request_for(1, CompanyPallets.PUT, {})
	_net.request_for(1, CompanyPallets.PICK, {"pallet": &"d2_hen_1"})
	_expect(_refusals == [CompanyPallets.REASON_JACK_EMPTY, CompanyPallets.REASON_JACK_FULL] and _net.seq == seq_jack,
		"The jack cannot put down or pick up while the forklift holds the pallet (%s)" % [_refusals])
	_same_as_mirror("with the pallet on the forks")

	# The mast: up to the high deck, by requests, as the keys do.
	var top: float = CompanyShed.SHELF_DECKS[1]
	var racks: Dictionary = _shed.rack_slots()
	var slot_pos: Vector2 = racks[TOP]["pos"]
	var fork_at_rack := Vector2(slot_pos.x + 0.9, slot_pos.y)
	_stand(fork_at_rack, PI * 0.5)
	await _raise_to(top)
	var host_height: float = state.height_at(Time.get_ticks_msec())
	var mirror_height: float = _mirror.pallets.forklift.height_at(Time.get_ticks_msec())
	_expect(absf(host_height - top) <= 0.1 and absf(mirror_height - host_height) < 0.02,
		"The forks stopped at the high deck, the second peer's agree (%.3f / %.3f)" % [host_height, top])
	await process_frame
	_expect(absf(fork.fork_height() - host_height) < 0.02
		and absf(_mirror_shed.yard.forklift.fork_height() - host_height) < 0.02,
		"... and both forklifts draw them there")

	# Wrong level, too far, a pallet where there is none: refused, nothing changes.
	await _publish_height(0.5)
	_expect(_work_refused(CompanyForklift.REASON_NO_RACK), "Between decks the pallet is not left on the rack (no_rack)")
	await _publish_height(top)
	_stand(fork_at_rack + Vector2(4.0, 0.0), PI * 0.5)
	_expect(_work_refused(CompanyForklift.REASON_NO_RACK), "Out of the slot's reach: no_rack")
	_stand(fork_at_rack, PI * 0.5)
	_expect(_net.inventory.total_units() == units_before, "None of those moved a unit")

	# Left on the rack: the stock rises once.
	var seq_rack: int = _net.seq
	_work()
	var book: PalletJack = _net.pallets.book
	_expect(_net.seq == seq_rack + 1 and book.carrying == &"" and not state.holds
		and book.places[lamp]["at"] == PalletJack.AT_RACK and book.places[lamp]["slot"] == TOP,
		"Work leaves the pallet on the high rack slot (%s)" % [book.places[lamp]])
	_expect(_net.inventory.count(LAMP, &"pallet:d2_antique_lamp_1") == 10
		and _net.inventory.total_units() == units_before + 10,
		"The stock rose by the pallet's 10 units, once")
	_expect(yard.rack_nodes.has(lamp) and fork.carried_id() == &"" and _mirror_shed.yard.rack_nodes.has(lamp),
		"It is drawn on the rack, no longer on the forks (both peers)")
	var drawn: Node3D = yard.rack_nodes[lamp]
	_expect(is_equal_approx(drawn.position.y, top)
		and Vector2(drawn.position.x, drawn.position.z).is_equal_approx(slot_pos)
		and not _shed.pallet_nodes.has("d2_antique_lamp_1"), "... on the deck, at the slot, and not in reception")
	_same_as_mirror("with the pallet on the rack")

	# A pallet where there is none; the slot taken.
	await _publish_height(0.0)
	_stand(fork_at_rack, PI * 0.5)
	_expect(_work_refused(CompanyForklift.REASON_NO_PALLET), "Down, facing the shelf, no pallet to take (no_pallet)")
	_stand(rear + Vector2(0.0, -CompanyTuning.FORKLIFT_TIP_M - 0.3), PI)
	_work()
	_expect(state.holds and _net.pallets.book.carrying == &"d2_hen_1", "A second pallet comes off the bed")
	_stand(fork_at_rack, PI * 0.5)
	await _publish_height(top)
	_expect(_work_refused(CompanyForklift.REASON_NO_RACK) and state.holds and book.rack_pallet(TOP) == lamp,
		"The slot is taken: no_rack, the pallet stays on the forks")
	_expect(_net.inventory.total_units() == units_before + 10, "Still +10")
	# With the forks up the pallet does not go on the floor either.
	_stand(Vector2(-1.0, 1.0), 0.0)
	_expect(_work_refused(CompanyForklift.REASON_NO_RACK), "Up in the air it does not go on the floor")

	# The late peer takes the snapshot with the forklift driven, loaded, high.
	await _check_late(_net.snapshot()["pallets"])

	# Bring the first pallet down and leave the second on the floor.
	_stand(fork_at_rack, PI * 0.5)
	await _publish_height(0.0)
	_stand(Vector2(-1.0, 1.0), 0.0)
	var floor_tip: Vector2 = CompanyForklift.tip_of(Vector2(-1.0, 1.0), 0.0)
	_work()
	_expect(book.places[&"d2_hen_1"]["at"] == PalletJack.AT_FLOOR
		and (book.places[&"d2_hen_1"]["pos"] as Vector2).is_equal_approx(floor_tip) and not state.holds,
		"With the forks down it leaves the pallet on the floor, in front of them (%s)" % [book.places[&"d2_hen_1"]])
	_expect(_net.inventory.count(HEN, &"pallet:d2_hen_1") == 24 and _net.inventory.total_units() == units_before + 34,
		"The stock rose by 24 once more (+34)")
	_expect(yard.floor_nodes.has(&"d2_hen_1") and _mirror_shed.yard.floor_nodes.has(&"d2_hen_1"), "Drawn on the floor")
	_stand(fork_at_rack, PI * 0.5)
	await _publish_height(top)
	_work()
	_expect(state.holds and book.carrying == lamp and book.rack_pallet(TOP) == &"",
		"The pallet comes down from the rack")
	_expect(_net.inventory.total_units() == units_before + 34, "... and the stock does not move")
	_expect(not yard.rack_nodes.has(lamp) and fork.carried_id() == lamp, "It leaves the rack and rides on the forks")
	_same_as_mirror("with the first pallet back on the forks")
	await _publish_height(top)
	_work()
	_expect(book.places[lamp]["at"] == PalletJack.AT_RACK and _net.inventory.total_units() == units_before + 34,
		"Left on the rack again, it is not received a second time (+34)")

	# Bad data and who may.
	_test_bad_data()

	# Getting off.
	var leave_at: Dictionary = fork.pose()
	_expect(_ask({"act": CompanyForklift.ACT_LEAVE}) and state.driver == 0 and _mirror.pallets.forklift.driver == 0,
		"Leaving frees the forklift on both peers")
	_expect(state.at is Vector2 and (state.at as Vector2).is_equal_approx(leave_at["body"])
		and is_equal_approx(state.yaw, float(leave_at["yaw"])) and fork.seat_point.can_interact(_driver)
		and not _driver.has_meta(&"interact_override") and not fork.is_local_driving(),
		"It stays where it stood, the seat is free and the driver's keys are theirs again")
	_stand(Vector2(5.0, 5.0), 1.0)
	await process_frame
	var left_at := Vector3(leave_at["body"].x, 0.0, leave_at["body"].y)
	var parked_pose: Array = [_snap(left_at), snappedf(float(leave_at["yaw"]), 0.001)]
	_expect(_pose_of(fork) == parked_pose and _pose_of(_mirror_shed.yard.forklift) == parked_pose,
		"Parked: the driver's player moves on, it does not (%s vs %s)" % [_pose_of(fork), parked_pose])
	_same_as_mirror("after getting off")

	# The host lets go of a forklift whose driver's player is gone.
	_stand(state.at, state.yaw)
	_expect(PalletJackUse.use(_net, yard, PalletJackPoint.ACTION_BOARD, 1, _driver.global_position)
		== PalletJackUse.RESULT_BOARDED and state.driver == 1, "Getting on again, where it was left")
	_driver.remove_from_group(&"player")
	_driver.free()
	_driver = null
	var waited: int = 0
	while state.driver != 0 and waited < 40:
		await create_timer(0.1).timeout
		waited += 1
	_expect(state.driver == 0 and _mirror.pallets.forklift.driver == 0,
		"Its driver's player gone, the host lets it go after about %.1f s (waited %.1f)"
		% [ForkliftView.GONE_SECONDS, waited * 0.1])
	_expect(_events_consistent(), "Both peers applied every event in order (%d / %d)" % [_mirror.seq, _net.seq])

	for node: Node in [_mirror_truck, _mirror_shed, _mirror, _truck, _shed, _net]:
		node.free()


## The shelves' pallet slots and the forklift's home.
func _test_geometry() -> void:
	var racks: Dictionary = _shed.rack_slots()
	var shelves: int = 0
	for piece: Dictionary in _shed.pieces:
		if piece["id"] == &"shelf":
			shelves += 1
	_expect(racks.size() == shelves * CompanyShed.SHELF_LEVELS and racks.has(TOP) and racks.has(&"shelf_1-0"),
		"Every shelf has a pallet slot per deck (%d slots for %d shelves)" % [racks.size(), shelves])
	_expect(is_equal_approx(racks[TOP]["level"], CompanyShed.SHELF_DECKS[1])
		and is_equal_approx(racks[&"shelf_1-0"]["level"], CompanyShed.SHELF_DECKS[0]), "... at the decks' heights")
	var floor_rect: Rect2 = PalletYardView.floor_rect(0)
	var inside: bool = true
	for slot: Variant in racks:
		inside = inside and floor_rect.has_point(racks[slot]["pos"])
	_expect(inside, "... on the floor")
	var home: Vector2 = PalletYardView.fork_home(0)
	_expect(floor_rect.has_point(home) and home.distance_to(PalletYardView.home(0)) > 1.2
		and _shed.cart_can_stand(Vector3(home.x, 0.0, home.y)),
		"The forklift waits on the floor, clear of the jack and the furniture")
	var forks: Vector2 = CompanyForklift.tip_of(home, PI)
	_expect(forks.is_equal_approx(home + Vector2(0.0, CompanyTuning.FORKLIFT_TIP_M)),
		"At home it faces the gate (south)")
	_expect(is_equal_approx(CompanyForklift.tip_of(Vector2.ZERO, PI * 0.5).x, -CompanyTuning.FORKLIFT_TIP_M),
		"A heading of a quarter turn faces west")
	var station: Dictionary = _shed.station_for(CompanyPallets.FORK_STATION)
	_expect(station.get("body") is Vector2 and station.get("yaw") is float and station.get("spot") is Vector3
		and (station.get("racks") as Array).size() == racks.size() and station.get("bed_at") is Vector2,
		"The shed resolves the forklift as a station")


func _test_bad_data() -> void:
	var seq: int = _net.seq
	var state: CompanyForklift = _net.pallets.forklift
	var keep: Dictionary = _net.pallets.to_dict()
	_refusals.clear()
	_net.request(CompanyPallets.FORK_ACT, {"act": "fly"})
	_net.request(CompanyPallets.FORK_ACT, {"act": CompanyForklift.ACT_MAST, "dir": 2})
	_net.request(CompanyPallets.FORK_ACT, {"act": CompanyForklift.ACT_MAST, "dir": "up"})
	_net.request(CompanyPallets.FORK_ACT, {})
	_expect(_refusals == [CompanyForklift.REASON_BAD_DATA, CompanyForklift.REASON_BAD_DATA,
		CompanyForklift.REASON_BAD_DATA, CompanyForklift.REASON_BAD_DATA] and _net.seq == seq,
		"An unknown act, a dir of 2, a text dir and no act are refused: bad_data (%s)" % [_refusals])
	# Somebody who is not the driver: judged at the station with their peer.
	var station: Dictionary = _shed.station_for(CompanyPallets.FORK_STATION)
	var other: Dictionary = station.merged({"peer": 2})
	var verdicts: Array = []
	for data: Dictionary in [{"act": &"leave"}, {"act": &"work"}, {"act": &"mast", "dir": 1}, {"act": &"board"}]:
		verdicts.append(_net.pallets.check(CompanyPallets.FORK_ACT, data, other)["reason"])
	_expect(verdicts == [CompanyForklift.REASON_NOT_DRIVER, CompanyForklift.REASON_NOT_DRIVER,
		CompanyForklift.REASON_NOT_DRIVER, CompanyForklift.REASON_TAKEN], "Another peer is refused: %s" % [verdicts])
	var no_station: Dictionary = _net.pallets.check(CompanyPallets.FORK_ACT, {"act": &"work"}, {})
	_expect(no_station["reason"] == CompanyForklift.REASON_NO_STATION,
		"... and a request at no station")
	# fork_state events that do not fit change nothing.
	var good: Dictionary = CompanyForklift.state_event(1, Vector2(1.0, 1.0), 0.0, 0, 0.5)
	var refused: int = 0
	var broken: Array[Dictionary] = [good.merged({"driver": -1}, true), good.merged({"driver": 1.5}, true),
		good.merged({"at": Vector2(NAN, 0.0)}, true), good.merged({"at": [1, 2]}, true),
		good.merged({"yaw": INF}, true),
		good.merged({"dir": 5}, true), good.merged({"dir": 0.5}, true), good.merged({"height": NAN}, true),
		good.merged({"height": "high"}, true), {"driver": 1}]
	for event: Dictionary in broken:
		if not _net.pallets.apply(_net.inventory, CompanyPallets.FORK, event):
			refused += 1
	_expect(refused == broken.size() and _net.pallets.to_dict()["book"] == keep["book"] and state.driver == 1,
		"fork_state events that do not fit are refused, changing nothing (%d of %d)" % [refused, broken.size()])
	# jack_placed with a slot that is not an id, a pallet that is not the carried one.
	var other_book := CompanyPallets.new()
	var held := Inventory.new()
	other_book.book.load_bed([Pallet.make(&"x1", HEN, 5)])
	_expect(other_book.apply(held, CompanyPallets.PICKED, {"pallet": &"x1", "by": CompanyForklift.BY})
		and other_book.forklift.holds, "A jack_picked `by` the forklift puts the pallet on its forks")
	_expect(not other_book.apply(held, CompanyPallets.PLACED, {"pallet": &"x1", "pos": Vector2.ZERO, "slot": 3})
		and not other_book.apply(held, CompanyPallets.PLACED, {"pallet": &"x2", "pos": Vector2.ZERO, "slot": &"s-1"})
		and other_book.forklift.holds and other_book.book.carrying == &"x1", "A bad slot or another pallet is refused")
	_expect(other_book.apply(held, CompanyPallets.PLACED, {"pallet": &"x1", "pos": Vector2(1.0, 1.0), "slot": &"s-1"})
		and not other_book.forklift.holds and other_book.book.rack_pallet(&"s-1") == &"x1",
		"... and a good slot takes it onto the rack")


# --- The late peer ---


## A peer that joins takes the snapshot part: the forklift (driven, loaded, forks high) and the rack pallets.
func _check_late(part: Dictionary) -> void:
	var fork_part: Dictionary = part["forklift"]
	var level: float = CompanyShed.SHELF_DECKS[1]
	_expect(fork_part["driver"] == 1 and fork_part["holds"] == true and absf(float(fork_part["height"]) - level) < 0.15,
		"The snapshot carries the driver, the pallet on the forks and the height (%s)" % [fork_part])
	var late := CompanyNet.new()
	late.name = "LateNet"
	late.company = _state
	root.add_child(late)
	_expect(late.pallets.put_snapshot(part), "The late peer takes the pallets part")
	late.inventory.from_dict(_net.snapshot()["inventory"])
	var late_shed := CompanyShed.new()
	late_shed.name = "LateShed"
	root.add_child(late_shed)
	late_shed.follow(late)
	late_shed.rebuild(_state, late.inventory)
	await process_frame
	_expect(_look(late_shed) == _look(_shed) and late.pallets.forklift.driver == 1 and late.pallets.forklift.holds,
		"It draws the same: forklift, forks, its pallet, rack pallets (%s vs %s)" % [_look(late_shed), _look(_shed)])
	_expect(late_shed.yard.forklift.is_local_driving() == _shed.yard.forklift.is_local_driving(),
		"... and knows whose it is")
	# Parts that do not fit leave it as it was.
	var keep: Dictionary = late.pallets.to_dict()
	var broken: Array[Dictionary] = []
	var changes: Array[Dictionary] = [{"driver": -3}, {"yaw": NAN}, {"dir": 7}, {"height": INF}, {"holds": "yes"},
		{"at": Vector2(INF, 0.0)}]
	for change: Dictionary in changes:
		var copy: Dictionary = part.duplicate(true)
		(copy["forklift"] as Dictionary).merge(change, true)
		broken.append(copy)
	var holds_nothing: Dictionary = part.duplicate(true)
	holds_nothing["book"]["carrying"] = ""
	broken.append(holds_nothing)
	broken.append(part.merged({"forklift": 5}, true))
	var refused: int = 0
	for bad: Dictionary in broken:
		if not late.pallets.put_snapshot(bad) and _same_book(late.pallets.to_dict(), keep):
			refused += 1
	_expect(refused == broken.size(), "Forklift parts that do not fit are refused, changing nothing (%d of %d)"
		% [refused, broken.size()])
	late_shed.free()
	late.free()


# --- The player's side ---


## A Player whose meta `interact_override` is set: interacting calls it, and the prompt it publishes is its own.
func _test_player_override() -> void:
	var player: Node = (load("res://scenes/gameplay/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	var component: Node = player.get(&"_interaction_component")
	var used: Array[int] = [0]
	player.set_meta(&"interact_override", {"use": func() -> void: used[0] += 1,
		"prompt": func() -> String: return "driving"})
	component.call(&"try_interact")
	component.call(&"publish_prompt", "walking")
	_expect(used[0] == 1 and player.get(&"_last_prompt") == "driving",
		"A driver's interact key and prompt are the override's (%d, %s)" % [used[0], player.get(&"_last_prompt")])
	player.remove_meta(&"interact_override")
	component.call(&"publish_prompt", "walking")
	_expect(player.get(&"_last_prompt") == "walking", "Without the override the prompt is the aimed one again")
	player.free()


# --- The real company world ---


## Solo on the real root: the seat point puts the host's player on the forklift and leaving frees it.
func _test_root() -> void:
	_clean()
	var company: Node = root.get_node(^"/root/CompanyState")
	company.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var net: CompanyNet = level.net
	var fork: ForkliftView = level.shed.yard.forklift if level.shed != null and level.shed.yard != null else null
	_expect(net != null and fork != null and fork.net == net, "The root's yard has the forklift, wired to the net")
	if net == null or fork == null:
		return
	var home: Vector2 = PalletYardView.fork_home(0)
	_expect(fork.position.is_equal_approx(Vector3(home.x, 0.0, home.y)), "It waits at its home")
	var seat: Vector3 = fork.global_position
	net.player_origin = func(_peer: int) -> Variant: return fork.global_position + Vector3(0.0, 1.0, 0.0)
	fork.seat_point.used.emit(PalletJackPoint.ACTION_BOARD, 1, seat)
	_expect(net.pallets.forklift.driver == 1 and fork.seat_point.taken, "The seat point gets the host's player on it")
	_expect(net.request(CompanyPallets.FORK_ACT, {"act": CompanyForklift.ACT_LEAVE}) != 0
		and net.pallets.forklift.driver == 0
		and not fork.seat_point.taken, "... and getting off frees it")
	level.queue_free()
	await process_frame
	company.call(&"reset")
	_clean()


# --- Helpers ---


## Stands the driver's player at `body` (shed frame) facing `heading`.
func _stand(body: Vector2, heading: float) -> void:
	_driver.global_position = Vector3(body.x, 0.0, body.y)
	_driver.rotation = Vector3(0.0, heading, 0.0)


## A fork_act request from peer 1 (the host's own); true when the host took it (an event came out of it).
func _ask(data: Dictionary) -> bool:
	var before: int = _net.seq
	_net.request(CompanyPallets.FORK_ACT, data)
	return _net.seq > before


func _work() -> void:
	_ask({"act": CompanyForklift.ACT_WORK})


## Work that the host refuses with `reason`: no event, no change in the book.
func _work_refused(reason: StringName) -> bool:
	var seq: int = _net.seq
	var keep: Dictionary = _net.pallets.book.to_dict()
	_refusals.clear()
	_work()
	return _refusals == [reason] and _net.seq == seq and _net.pallets.book.to_dict() == keep


## Holds the mast up, asking again every 0.35 s as the keys do, until the host's forks are at `target`.
func _raise_to(target: float) -> void:
	var sent: int = -1000
	var deadline: int = Time.get_ticks_msec() + 8000
	var fork: CompanyForklift = _net.pallets.forklift
	while fork.height_at(Time.get_ticks_msec()) < target - 0.03 and Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() - sent >= 350:
			sent = Time.get_ticks_msec()
			_net.request(CompanyPallets.FORK_ACT, {"act": CompanyForklift.ACT_MAST, "dir": 1})
		await process_frame
	_net.request(CompanyPallets.FORK_ACT, {"act": CompanyForklift.ACT_MAST, "dir": 0})


## The host sets the forks straight at `height` (a fork_state event, as it does for a driver that is gone).
func _publish_height(height: float) -> void:
	var pose: Dictionary = _shed.yard.forklift.pose()
	_net.publish(CompanyPallets.FORK, CompanyForklift.state_event(_net.pallets.forklift.driver, pose["body"],
		pose["yaw"], 0, height))
	await process_frame


func _make_truck(net: CompanyNet, shed: CompanyShed, truck_name: String) -> SupplierTruckView:
	var truck := SupplierTruckView.new()
	truck.name = truck_name
	truck.schedule = _schedule
	truck.company = _company
	truck.minute_now = func() -> float: return _minute[0]
	truck.pallets = net.pallets.book
	root.add_child(truck)
	shed.truck = truck
	net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		if CompanyPallets.EVENT_KINDS.has(kind):
			truck.refresh_bed())
	truck.refresh_bed()
	return truck


## Where a forklift is drawn and which way it faces.
func _pose_of(view: ForkliftView) -> Array:
	return [_snap(view.position), snappedf(view.rotation.y, 0.001)]


func _snap(point: Vector3) -> Vector3:
	return Vector3(snappedf(point.x, 0.001), snappedf(point.y, 0.001), snappedf(point.z, 0.001))


## What a peer draws of the yard: the jack's load, the floor and rack pallets, the forklift, its forks and its load.
func _look(shed: CompanyShed) -> Array:
	var yard: PalletYardView = shed.yard
	var floor_spots: Dictionary = {}
	for id: StringName in yard.floor_nodes:
		floor_spots[id] = (yard.floor_nodes[id] as Node3D).position
	var rack_spots: Dictionary = {}
	for id: StringName in yard.rack_nodes:
		rack_spots[id] = [(yard.rack_nodes[id] as Node3D).position, (yard.rack_nodes[id] as Node3D).rotation.y]
	return [yard.jack.position, yard.jack.carried_id(), floor_spots, rack_spots, _pose_of(yard.forklift),
		yard.forklift.carried_id(), snappedf(yard.forklift.fork_height(), 0.05), yard.forklift.seat_point.taken]


func _same_book(a: Dictionary, b: Dictionary) -> bool:
	return a["book"] == b["book"] and a["jack_at"] == b["jack_at"] \
		and a["forklift"]["driver"] == b["forklift"]["driver"]


func _same_as_mirror(when: String) -> void:
	_expect(_look(_shed) == _look(_mirror_shed), "The second peer draws the same yard %s: %s vs %s"
		% [when, _look(_mirror_shed), _look(_shed)])
	_expect(_mirror.inventory.to_dict() == _net.inventory.to_dict()
		and _mirror.pallets.book.to_dict() == _net.pallets.book.to_dict()
		and _mirror.pallets.forklift.driver == _net.pallets.forklift.driver
		and _mirror.pallets.forklift.holds == _net.pallets.forklift.holds,
		"... and holds the same stock and book %s" % when)


func _events_consistent() -> bool:
	return _mirror.seq == _net.seq


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
