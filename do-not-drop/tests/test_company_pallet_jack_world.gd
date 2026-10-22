extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_pallet_jack_world.gd
##
## The pallet jack and the supplier pallets in the shed's world (expansion D-0605.b: company_pallets.gd,
## pallet_jack_view.gd, pallet_yard_view.gd, pallet_box.gd, pallet_jack_point.gd, pallet_jack_use.gd,
## SupplierTruckView's open bed, CompanyShed.station_for(&"jack"), CompanyNet jack_pick / jack_put / jack_push):
## - the bed of the truck has slots for its pallets, all inside its walls, under its roof and apart from each other;
## - the jack waits at its home by the dock, in reach of the truck's rear; load_due() says when the day's truck
##   brings its pallets (from its drive-in to its departure, never without a delivery);
## - jack_loaded puts the day's pallets on the bed and draws them there, on the host and on a second peer; the
##   shed's first pallets (already in the stock) are not loaded again, and a pallet loaded is not loaded twice;
##   loaded_event() lists only what apply() takes (a 60-character id stays out), the same on every peer;
## - a player takes a pallet off the bed with the jack (the truck parked, the bed in the jack's reach) and puts it down
##   on the floor: the units of the pallet enter the stock once, at the put-down, and not before; the pallet is
##   drawn on the forks while it is carried and on the floor afterwards (and no longer by the Inventory's own draw);
## - a pallet put down on another one is refused (no_room); pushing the jack one step (away from the player) frees
##   the spot; a pallet picked up from the floor and put down again does not count twice, not even emptied first;
## - the host refuses: the truck away (truck_away), the jack full, an unknown pallet, a player 40 m away
##   (out_of_reach), a push into the wall (blocked); bad data is refused or dropped, and none changes anything;
## - a second peer (its own CompanyNet fed the host's events in order) holds and draws the same: stock, book,
##   jack, floor pallets, bed; a peer that joins late gets them from the snapshot part, and a part that does not fit
##   (bad id, NaN, two pallets on the jack, a floor pallet without a spot, a `received` that is not a bool, too many)
##   is refused changing nothing;
## - the next day's truck takes what stayed on the old bed with it (the floor keeps its pallets);
## - the real company world (company_root.tscn, solo): on day 2 the host puts the truck's pallets on the bed
##   once, in the minute it drives in, and a player works the jack through its points, all the way to the stock.
## Not covered: the ENet pair (a client's request over the wire): the jack uses the same CompanyNet requests the
## pair tests already carry (test_company_online, net_pair_company); the save of the book is D-0605.c.

const HEN: StringName = &"hen"
const LAMP: StringName = &"antique_lamp"
const DAY: int = 2
const EPS: float = 0.0001
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
## The real root saves here on leaving, never in the game's slot.
const DIR: String = "user://test_company_pallet_jack_world"

## What SupplierTruckView and CompanyShed read of the company.
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
var _events: Array = []
var _refusals: Array = []
## Where the test's player stands (its reach origin), as CompanyNet.player_origin answers.
var _player_at: Vector3 = Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_geometry()
	_test_load_due()
	_test_loaded_event()
	await _test_world()
	await _test_root()
	if _failures == 0:
		print("PASS: the pallet jack moves a pallet from the truck to the floor, the stock rises once, on all peers")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


# --- Geometry ---


func _test_geometry() -> void:
	var truck: Vector3 = CompanyTuning.SUPPLIER_TRUCK_SIZE_M
	var half_width: float = truck.x * 0.5 - SupplierTruckView.BED_WALL
	var rear_z: float = truck.z * 0.5
	var cargo_len: float = truck.z - SupplierTruckView.CAB_LENGTH
	var turned := Vector2(CompanyTuning.PALLET_FOOTPRINT_M.y, CompanyTuning.PALLET_FOOTPRINT_M.x)
	var ceiling: float = truck.y - SupplierTruckView.BED_WALL
	for rank: int in SupplierTruckView.BED_SLOTS:
		var at: Vector3 = SupplierTruckView.bed_slot(rank)
		_expect(absf(at.x) + turned.x * 0.5 <= half_width + EPS and at.z + turned.y * 0.5 <= rear_z + EPS
			and at.z - turned.y * 0.5 >= rear_z - cargo_len + SupplierTruckView.BED_WALL - EPS,
			"Slot %d is inside the bed's walls (%s)" % [rank, at])
		_expect(at.y >= SupplierTruckView.CARGO_FLOOR + SupplierTruckView.BED_WALL - EPS
			and at.y + PalletBox.height() <= ceiling + EPS, "Slot %d is above the floor and under the roof" % rank)
		for other: int in range(rank + 1, SupplierTruckView.BED_SLOTS):
			var apart: Vector3 = SupplierTruckView.bed_slot(other) - at
			_expect(absf(apart.y) >= PalletBox.height() - EPS or absf(apart.x) >= turned.x - EPS
				or absf(apart.z) >= turned.y - EPS, "Slots %d and %d do not overlap" % [rank, other])
	_expect(SupplierTruckView.bed_slot(0).z > SupplierTruckView.bed_slot(2).z, "Slot 0 is the nearest to the rear")
	var home: Vector2 = PalletYardView.home(0)
	var rear: Vector2 = SupplierTruckView.rear_of(0)
	_expect(home.distance_to(rear) <= CompanyTuning.PALLET_JACK_REACH_M,
		"The jack's home is in reach of the truck's rear (%.2f m)" % home.distance_to(rear))
	var floor_rect: Rect2 = PalletYardView.floor_rect(0)
	_expect(floor_rect.has_point(home) and rear.y > floor_rect.end.y, "Home is on the floor, the rear outside it")
	_expect(PalletJackView.LENGTH == 1.6 and PalletJackView.WIDTH == 0.55 and PalletJackView.HEIGHT == 1.2,
		"The jack is 1.6 x 0.55 x 1.2 m (arte-pendiente/D-0605.md)")


func _test_load_due() -> void:
	var schedule := SupplierSchedule.new()
	schedule.place(DAY - 1, [{"product": HEN, "qty": 5}])
	var arrival: int = SupplierSchedule.arrival_minute()
	var drive_in: int = int(CompanyTuning.SUPPLIER_DRIVE_IN_MIN)
	_expect(not CompanyPallets.load_due(schedule, DAY, arrival - drive_in - 1)
		and CompanyPallets.load_due(schedule, DAY, arrival - drive_in)
		and CompanyPallets.load_due(schedule, DAY, arrival + 30)
		and not CompanyPallets.load_due(schedule, DAY, SupplierSchedule.departure_minute()),
		"The pallets come with the drive-in and wait until the truck leaves")
	_expect(not CompanyPallets.load_due(schedule, DAY + 1, arrival + 30), "A day without a delivery brings nothing")


## loaded_event() publishes only what apply() takes: a pallet whose id is too long for the network stays out.
func _test_loaded_event() -> void:
	var host := CompanyPallets.new()
	var long_id := StringName("d4_hen_" + "x".repeat(53))
	var planned: Array[Dictionary] = [Pallet.make(long_id, HEN, 5), Pallet.make(&"d4_hen_1", HEN, 5)]
	var event: Dictionary = host.loaded_event(DAY + 2, planned, Inventory.new())
	var listed: Array = event.get("pallets", [])
	_expect(String(long_id).length() == 60 and listed.size() == 1 and listed[0]["id"] == "d4_hen_1",
		"A pallet with a 60-character id stays out of jack_loaded (%s)" % [event])
	var peer := CompanyPallets.new()
	_expect(host.apply(Inventory.new(), CompanyPallets.LOADED, event)
		and peer.apply(Inventory.new(), CompanyPallets.LOADED, event) and peer.to_dict() == host.to_dict()
		and host.book.ids_at(PalletJack.AT_BED) == [&"d4_hen_1"], "... and what the host publishes, every peer applies")


# --- The world ---


func _test_world() -> void:
	_state = DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(_state)
	var stock: Inventory = _state.stock()
	_schedule.place(DAY - 1, [{"product": HEN, "qty": 30}, {"product": LAMP, "qty": 10}])
	_minute[0] = float(SupplierSchedule.arrival_minute()) - 10.0
	_net = CompanyNet.new()
	_net.name = "JackNet"
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
	_net.player_origin = func(_peer: int) -> Variant: return _player_at
	_net.request_rejected.connect(func(_rid: int, reason: StringName) -> void: _refusals.append(reason))
	_net.event_applied.connect(func(event_seq: int, kind: StringName, data: Dictionary) -> void:
		_events.append(event_seq)
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
	await process_frame

	var yard: PalletYardView = _shed.yard
	var home: Vector2 = PalletYardView.home(0)
	_expect(yard != null and yard.jack != null and yard.jack.position.is_equal_approx(Vector3(home.x, 0.0, home.y)),
		"The jack stands at its home on the shed floor")
	_expect(yard.jack.work_point.get_prompt() != "" and yard.jack.push_point.get_prompt() != ""
		and yard.jack.work_point.get_prompt() != yard.jack.push_point.get_prompt(), "Both points have their own prompt")
	var starters: int = CompanyShed.pallets_in(_net.inventory).size()
	_expect(starters > 0 and _shed.pallet_nodes.size() == starters, "The shed's first pallets are drawn from the stock")
	var units_before: int = _net.inventory.total_units()

	# The truck's pallets: not the shed's first ones, once.
	var first_pallets: Array[Dictionary] = DefaultShed.load_default().first_pallets()
	var first_trip: Dictionary = _net.pallets.loaded_event(1, first_pallets, _net.inventory)
	_expect(first_trip.is_empty(), "The first truck's pallets are already in the shed: nothing to load")
	var event: Dictionary = _net.pallets.loaded_event(DAY, _schedule.pallets_for(DAY), _net.inventory)
	_expect((event.get("pallets", []) as Array).size() == 3, "The day's truck brings three pallets (%s)" % [event])
	_expect(_net.publish(CompanyPallets.LOADED, event) and _net.pallets.loaded_day == DAY,
		"The host publishes jack_loaded")
	var ids: Array[StringName] = [&"d2_antique_lamp_1", &"d2_hen_1", &"d2_hen_2"]
	_expect(_net.pallets.book.ids_at(PalletJack.AT_BED) == ids, "The three are on the bed, in id order (%s)"
		% [_net.pallets.book.ids_at(PalletJack.AT_BED)])
	_expect(_truck.bed_ids() == ids and _truck.get_node(^"Bed").get_child_count() == 3,
		"The truck draws its three pallets in slots")
	_expect(_net.inventory.total_units() == units_before, "Loading the bed moves no unit into the stock")
	_expect(_net.pallets.loaded_event(DAY, _schedule.pallets_for(DAY), _net.inventory).is_empty(),
		"The same day's pallets are not loaded twice")
	_expect(_shed.pallet_nodes.size() == starters, "The shed's own pallets draw as before")
	_same_as_mirror("after loading the bed")

	# The truck has not parked yet: it drives in, the bed is not open.
	_player_at = _jack_world() + Vector3(-1.2, 1.5, 0.0)
	var station: Dictionary = _shed.station_for(CompanyPallets.STATION)
	_expect(station.get("location") == &"jack:yard" and station.get("spot") is Vector3 and station.get("at") is Vector2
		and station.get("floor") is Rect2 and station.get("stand_ok") is Callable and station.get("free_ok") is Callable
		and station.get("bed_at") is Vector2 and station.get("bed_open") == false,
		"The shed resolves the jack as a station, the bed closed (%s)" % [station])
	var seq_closed: int = _net.seq
	_expect(PalletJackUse.plan_pick(_net.pallets, station) == &"", "With the truck away there is nothing to pick")
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.REASON_NOTHING_THERE, "The forks do nothing then")
	_net.request_for(1, CompanyPallets.PICK, {"pallet": &"d2_hen_1"})
	_expect(_refusals == [CompanyPallets.REASON_TRUCK_AWAY] and _net.seq == seq_closed,
		"Asked anyway the host refuses with truck_away (%s)" % [_refusals])

	# Parked: the jack takes the first pallet off the bed.
	_minute[0] = float(SupplierSchedule.arrival_minute()) + 30.0
	station = _shed.station_for(CompanyPallets.STATION)
	_expect(station.get("bed_open") == true and PalletJackUse.plan_pick(_net.pallets, station) == &"d2_antique_lamp_1",
		"The truck parked, the first pallet of the bed is the one to pick")
	_refusals.clear()
	var seq_pick: int = _net.seq
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.RESULT_PICKED and _net.seq == seq_pick + 1,
		"The forks pick a pallet up: one event")
	_expect(_net.pallets.book.carrying == &"d2_antique_lamp_1" and _truck.bed_ids() == [&"d2_hen_1", &"d2_hen_2"]
		and yard.jack.carried_id() == &"d2_antique_lamp_1", "It leaves the bed and rides on the forks")
	_expect(_net.inventory.total_units() == units_before
		and _net.inventory.count(LAMP, &"pallet:d2_antique_lamp_1") == 0,
		"Carried, its units are not in the stock yet")
	_same_as_mirror("with the pallet on the forks")

	# The jack is full.
	var seq_full: int = _net.seq
	_net.request_for(1, CompanyPallets.PICK, {"pallet": &"d2_hen_1"})
	_expect(_refusals == [CompanyPallets.REASON_JACK_FULL] and _net.seq == seq_full,
		"A second pallet is refused: jack_full")

	# Put down: the stock goes up once, by the pallet's units.
	_refusals.clear()
	var home_spot: Vector2 = PalletYardView.home(0)
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.RESULT_PUT, "The forks put the pallet down")
	var book: PalletJack = _net.pallets.book
	_expect(book.carrying == &"" and book.places[&"d2_antique_lamp_1"]["at"] == PalletJack.AT_FLOOR
		and (book.places[&"d2_antique_lamp_1"]["pos"] as Vector2).is_equal_approx(home_spot),
		"The pallet stands on the floor where the jack is")
	_expect(_net.inventory.count(LAMP, &"pallet:d2_antique_lamp_1") == 10
		and _net.inventory.total_units() == units_before + 10,
		"The stock went up by the pallet's 10 units, once (%d)" % _net.inventory.total_units())
	_expect(yard.floor_nodes.has(&"d2_antique_lamp_1") and yard.jack.carried_id() == &""
		and not _shed.pallet_nodes.has("d2_antique_lamp_1"),
		"It is drawn on the floor by the yard, no longer by the Inventory's draw")
	var lamp_node: Node3D = yard.floor_nodes[&"d2_antique_lamp_1"]
	_expect(lamp_node.position.is_equal_approx(Vector3(home_spot.x, 0.0, home_spot.y)), "... at the spot the book says")
	_same_as_mirror("after the first pallet is down")

	# On top of another: refused. Then a push frees the spot.
	_refusals.clear()
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.RESULT_PICKED and book.carrying == &"d2_hen_1",
		"With the jack empty the forks take the next pallet of the bed")
	var seq_over: int = _net.seq
	var stock_over: int = _net.inventory.total_units()
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.REASON_REFUSED
		and _refusals == [CompanyPallets.REASON_NO_ROOM],
		"Put down on the first one it is refused: no_room (%s)" % [_refusals])
	_expect(_net.seq == seq_over and book.carrying == &"d2_hen_1" and _net.inventory.total_units() == stock_over,
		"Nothing changed: still on the forks, the stock the same")
	var step: float = CompanyTuning.JACK_PUSH_STEP_M
	var pushed_to: Vector2 = home_spot + Vector2(step, 0.0)
	_expect(_use(PalletJackPoint.ACTION_PUSH, _player_at) == PalletJackUse.RESULT_PUSHED
		and _net.seq == seq_over + 1, "A push is one event")
	_expect(_net.pallets.jack_at is Vector2 and (_net.pallets.jack_at as Vector2).is_equal_approx(pushed_to)
		and yard.jack.position.is_equal_approx(Vector3(pushed_to.x, 0.0, pushed_to.y)),
		"The jack rolled one step away from the player (%s)" % [_net.pallets.jack_at])
	var moved_spot: Vector3 = _shed.station_for(CompanyPallets.STATION)["spot"]
	_expect(moved_spot.is_equal_approx(yard.jack.global_position + Vector3.UP * 0.5), "Its reach spot follows the jack")
	_player_at = _jack_world() + Vector3(-1.2, 1.5, 0.0)
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.RESULT_PUT, "Put down one step on, it fits")
	_expect(_net.inventory.count(HEN, &"pallet:d2_hen_1") == 24 and _net.inventory.total_units() == units_before + 34,
		"The stock went up by 24 more (%d)" % _net.inventory.total_units())
	await create_timer(PalletJackView.SLIDE_SECONDS + 0.15).timeout
	_same_as_mirror("after the second pallet")

	# A pallet picked up from the floor and put down again does not count twice.
	var plan: StringName = PalletJackUse.plan_pick(_net.pallets, _shed.station_for(CompanyPallets.STATION))
	_expect(plan == &"d2_hen_1", "Away from the dock the nearest pallet on the floor is the one to pick (%s)" % plan)
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.RESULT_PICKED and book.carrying == &"d2_hen_1"
		and _net.inventory.count(HEN, &"pallet:d2_hen_1") == 24,
		"It goes back on the forks, its units stay in the stock")
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.RESULT_PUT
		and _net.inventory.total_units() == units_before + 34, "... and down again: the stock is still +34")
	_same_as_mirror("after picking from the floor")

	# Emptied (its units moved off it on every peer) and set down again, it is not received a second time.
	for peer_stock: Inventory in [_net.inventory, _mirror.inventory]:
		peer_stock.move(HEN, 24, &"pallet:d2_hen_1", &"shelf:emptied")
	_expect(_net.inventory.contents_at(&"pallet:d2_hen_1").is_empty() and book.places[&"d2_hen_1"]["received"] == true,
		"The pallet is emptied; the book remembers it was received")
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.RESULT_PICKED and book.carrying == &"d2_hen_1"
		and _use(PalletJackPoint.ACTION_WORK) == PalletJackUse.RESULT_PUT, "The empty pallet goes up and down again")
	_expect(_net.inventory.total_units() == units_before + 34 and _net.inventory.count(HEN, &"pallet:d2_hen_1") == 0,
		"... and the stock is still +34: an emptied pallet is not received twice (%d)" % _net.inventory.total_units())
	_same_as_mirror("after setting an emptied pallet down")

	# Reach, the wall and bad data are the host's.
	var seq_far: int = _net.seq
	_refusals.clear()
	_player_at = _jack_world() + Vector3(40.0, 1.5, 0.0)
	_expect(_use(PalletJackPoint.ACTION_WORK) == PalletJackUse.REASON_REFUSED
		and _refusals == [CompanyNet.REASON_OUT_OF_REACH], "40 m away the host refuses the forks (%s)" % [_refusals])
	_expect(_use(PalletJackPoint.ACTION_PUSH) == PalletJackUse.REASON_REFUSED
		and _refusals.back() == CompanyNet.REASON_OUT_OF_REACH, "... and the push")
	_expect(_net.seq == seq_far, "Out of reach nothing moved")
	_player_at = _jack_world() + Vector3(-1.2, 1.5, 0.0)
	var blocked: bool = false
	for _try: int in 12:
		var before_seq: int = _net.seq
		_refusals.clear()
		if _use(PalletJackPoint.ACTION_PUSH, _player_at) == PalletJackUse.REASON_REFUSED:
			blocked = _refusals == [CompanyPallets.REASON_BLOCKED] and _net.seq == before_seq
			break
		_player_at = _jack_world() + Vector3(-1.2, 1.5, 0.0)
	_expect(blocked, "Pushed on and on east the host ends with blocked (%s)" % [_refusals])
	var legacy: Node3D = _shed.pallet_nodes.values()[0]
	_expect(not _shed.cart_can_stand(Vector3(500.0, 0.0, 0.0)) and _shed.pallet_spot_free(Vector2(0.0, 0.0))
		and not _shed.pallet_spot_free(Vector2(legacy.position.x, legacy.position.z)),
		"The floor checks know walls and the shed's own pallets")
	var seq_bad: int = _net.seq
	_refusals.clear()
	_net.request_for(1, CompanyPallets.PICK, {"pallet": "not an id!"})
	_net.request_for(1, CompanyPallets.PICK, {"pallet": &"d9_nothing_1"})
	_net.request_for(1, CompanyPallets.PUSH, {"dir": Vector2.ZERO})
	_net.request_for(1, CompanyPallets.PUSH, {"dir": Vector2(NAN, 0.0)})
	_net.request_for(1, CompanyPallets.PUT, {})
	_expect(_net.seq == seq_bad and _refusals == [CompanyPallets.REASON_BAD_DATA, CompanyPallets.REASON_NO_PALLET,
		CompanyPallets.REASON_BAD_DATA, CompanyPallets.REASON_JACK_EMPTY],
		"A bad id, an unknown pallet, a zero push and an empty put are refused, a NaN push dropped (%s)" % [_refusals])
	await create_timer(PalletJackView.SLIDE_SECONDS + 0.15).timeout
	_same_as_mirror("after the refusals")
	_expect(_events.size() == _net.seq and _mirror.seq == _net.seq,
		"Both peers applied every event in order (%d / %d)" % [_mirror.seq, _net.seq])

	# A late peer: the snapshot parts bring the book, the jack, the floor and the bed.
	var snapshot: Dictionary = _net.snapshot()
	_expect(snapshot.get("pallets") is Dictionary and snapshot.has("inventory"),
		"The host's snapshot carries the pallets part")
	var late := CompanyNet.new()
	late.name = "LateNet"
	late.company = _state
	root.add_child(late)
	_expect(late.pallets.put_snapshot(snapshot["pallets"]), "The late peer takes the pallets part")
	late.inventory.from_dict(snapshot["inventory"])
	var late_shed := CompanyShed.new()
	late_shed.name = "LateShed"
	root.add_child(late_shed)
	late_shed.follow(late)
	late_shed.rebuild(_state, late.inventory)
	var late_truck: SupplierTruckView = _make_truck(late, late_shed, "LateTruck")
	await process_frame
	_expect(_yard_look(late_shed) == _yard_look(_shed) and late_truck.bed_ids() == _truck.bed_ids()
		and late.pallets.to_dict() == _net.pallets.to_dict(), "The late peer draws the same yard and bed")
	_bad_snapshots(late, snapshot["pallets"])

	# The next day's truck takes what stayed on the bed with it; the floor keeps its pallets.
	_schedule.place(DAY, [{"product": HEN, "qty": 5}])
	_company.day = DAY + 1
	_expect(_net.pallets.book.ids_at(PalletJack.AT_BED) == [&"d2_hen_2"], "One pallet of day 2 stayed on the bed")
	var next_event: Dictionary = _net.pallets.loaded_event(DAY + 1, _schedule.pallets_for(DAY + 1), _net.inventory)
	_expect(_net.publish(CompanyPallets.LOADED, next_event) and _net.pallets.loaded_day == DAY + 1,
		"Day 3's truck loads its pallet")
	_expect(_net.pallets.book.ids_at(PalletJack.AT_BED) == [&"d3_hen_1"]
		and not _net.pallets.book.places.has(&"d2_hen_2")
		and _net.pallets.book.ids_at(PalletJack.AT_FLOOR).size() == 2 and _truck.bed_ids() == [&"d3_hen_1"],
		"The old truck left with its pallet, the new one's is on the bed, the floor kept its two")
	_expect(_net.inventory.total_units() == units_before + 34, "What stayed on the bed was never counted")
	_same_as_mirror("after the next day's truck")

	for node: Node in [late_truck, late_shed, late, _mirror_truck, _mirror_shed, _mirror, _truck, _shed, _net]:
		node.free()


## A truck view over `net`'s book, drawn the way CompanyRoot does it: redrawn on the pallets' events.
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


## Snapshot parts that do not fit leave the late peer's book as it was.
func _bad_snapshots(late: CompanyNet, good: Dictionary) -> void:
	var keep: Dictionary = late.pallets.to_dict()
	var broken: Array[Dictionary] = []
	var place: Dictionary = (good["book"]["places"] as Dictionary)["d2_hen_1"].duplicate(true)
	var with_place := func(key: String, value: Variant) -> Dictionary:
		var copy: Dictionary = good.duplicate(true)
		(copy["book"]["places"] as Dictionary)[key] = value
		return copy
	var bad_id: Dictionary = with_place.call("not an id!", place)
	var no_pos: Dictionary = with_place.call("d2_hen_1", {"pallet": place["pallet"], "at": "floor"})
	var nan_pos: Dictionary = with_place.call("d2_hen_1", {"pallet": place["pallet"], "at": "floor", "pos": [NAN, 0.0]})
	var on_jack: Dictionary = with_place.call("d2_hen_1", {"pallet": place["pallet"], "at": "jack"})
	var odd_place: Dictionary = with_place.call("d2_hen_1", {"pallet": place["pallet"], "at": "moon"})
	var other_id: Dictionary = with_place.call("d2_hen_1", {"pallet": {"id": "x", "product": "hen", "qty": 1,
		"state": "sealed"}, "at": "bed"})
	var no_qty: Dictionary = with_place.call("d2_hen_1", {"pallet": {"id": "d2_hen_1", "product": "hen", "qty": 0,
		"state": "sealed"}, "at": "bed"})
	var odd_received: Dictionary = with_place.call("d2_hen_1", place.merged({"received": "yes"}, true))
	var jack_at_nan: Dictionary = good.duplicate(true)
	jack_at_nan["jack_at"] = Vector2(NAN, 0.0)
	var carrying_nothing: Dictionary = good.duplicate(true)
	carrying_nothing["book"]["carrying"] = "d2_hen_1"
	var many: Dictionary = good.duplicate(true)
	for index: int in CompanyPallets.MAX_PALLETS + 1:
		(many["book"]["places"] as Dictionary)["p%d" % index] = place
	broken.append_array([bad_id, no_pos, nan_pos, on_jack, odd_place, other_id, no_qty, odd_received, jack_at_nan,
		carrying_nothing, many])
	var refused: int = 0
	for part: Dictionary in broken:
		if not late.pallets.put_snapshot(part) and late.pallets.to_dict() == keep:
			refused += 1
	_expect(refused == broken.size(), "A snapshot part that does not fit is refused, changing nothing (%d of %d)"
		% [refused, broken.size()])
	_expect(not late.pallets.put_snapshot("nope") and not late.pallets.put_snapshot({"book": 3}),
		"... whatever its type")


# --- The real company world ---


## Solo on the real root: on day 2 the truck's pallets come once and the jack works through its points.
func _test_root() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var net: CompanyNet = level.net
	_expect(net != null and level.shed.yard != null and level.shed.truck == level.supplier_truck
		and level.supplier_truck.pallets == net.pallets.book, "The root wires the yard, the truck and the book")
	if net == null:
		return
	# Day 1: the truck's pallets are the shed's own, already in the stock: nothing to load.
	level.clock.start(float(SupplierSchedule.arrival_minute()) - 3.0)
	await process_frame
	_expect(net.pallets.loaded_day == 0 and net.pallets.book.places.is_empty(),
		"Day 1 loads nothing (its pallets start in the shed)")
	state.set(&"day", DAY)
	level.clock.start(float(SupplierSchedule.arrival_minute()) - 8.0)
	await process_frame
	_expect(net.pallets.book.places.is_empty(), "Before the truck drives in the bed is empty")
	var loads: Array[int] = [0]
	net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		if kind == CompanyPallets.LOADED:
			loads[0] += 1)
	level.clock.start(float(SupplierSchedule.arrival_minute()) - 3.0)
	await process_frame
	var on_bed: Array[StringName] = net.pallets.book.ids_at(PalletJack.AT_BED)
	_expect(on_bed == [&"d2_milk_canister_1", &"d2_wedding_cake_1"] and net.pallets.loaded_day == DAY,
		"On day 2 the host loads the truck's two pallets as it drives in (%s)" % [on_bed])
	_expect(level.supplier_truck.bed_ids() == on_bed, "... and the truck draws them")
	level.clock.start(float(SupplierSchedule.arrival_minute()) - 2.0)
	for _frame: int in 3:
		await process_frame
	_expect(loads[0] == 1 and net.pallets.book.ids_at(PalletJack.AT_BED) == on_bed,
		"Once: the minutes that follow load nothing more (%d loads)" % loads[0])
	# Parked: take a pallet off the bed and put it down with the points.
	level.clock.start(float(SupplierSchedule.arrival_minute()) + 20.0)
	await process_frame
	var yard: PalletYardView = level.shed.yard
	var jack_at: Vector3 = yard.jack.global_position
	net.player_origin = func(_peer: int) -> Variant: return jack_at + Vector3(-1.2, 1.5, 0.0)
	var units_before: int = net.inventory.total_units()
	yard.jack.work_point.used.emit(PalletJackPoint.ACTION_WORK, 1, jack_at + Vector3(-1.2, 0.0, 0.0))
	_expect(net.pallets.book.carrying == &"d2_milk_canister_1"
		and level.supplier_truck.bed_ids() == [&"d2_wedding_cake_1"],
		"The forks of the real jack take the first pallet off the bed (%s)" % net.pallets.book.carrying)
	yard.jack.work_point.used.emit(PalletJackPoint.ACTION_WORK, 1, jack_at + Vector3(-1.2, 0.0, 0.0))
	_expect(net.pallets.book.places[&"d2_milk_canister_1"]["at"] == PalletJack.AT_FLOOR
		and net.inventory.count(&"milk_canister", &"pallet:d2_milk_canister_1") == 12
		and net.inventory.total_units() == units_before + 12,
		"... and put it down: the stock rose by its 12 units, once")
	_expect(yard.floor_nodes.has(&"d2_milk_canister_1") and not level.shed.pallet_nodes.has("d2_milk_canister_1"),
		"It is drawn on the floor by the yard")
	level.queue_free()
	await process_frame
	state.call(&"reset")
	_clean()


## The jack's position in the world.
func _jack_world() -> Vector3:
	return _shed.yard.jack.global_position


## One use of the jack's point by peer 1 at `_player_at`.
func _use(action: StringName, from: Vector3 = Vector3.ZERO) -> StringName:
	var standing: Vector3 = from if from != Vector3.ZERO else _player_at
	return PalletJackUse.use(_net, _shed.yard, action, 1, standing)


## What a peer draws of the yard: the jack's spot and load, the floor pallets with their spots.
func _yard_look(shed: CompanyShed) -> Array:
	var floor_spots: Dictionary = {}
	for id: StringName in shed.yard.floor_nodes:
		floor_spots[id] = (shed.yard.floor_nodes[id] as Node3D).position
	return [shed.yard.jack.position, shed.yard.jack.carried_id(), floor_spots]


func _same_as_mirror(when: String) -> void:
	_expect(_yard_look(_shed) == _yard_look(_mirror_shed) and _truck.bed_ids() == _mirror_truck.bed_ids(),
		"The second peer draws the same yard and bed %s: %s vs %s"
		% [when, _yard_look(_mirror_shed), _yard_look(_shed)])
	_expect(_mirror.inventory.to_dict() == _net.inventory.to_dict()
		and _mirror.pallets.to_dict() == _net.pallets.to_dict(),
		"... and holds the same stock and book %s" % when)


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
