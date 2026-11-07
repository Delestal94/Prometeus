extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_tow.gd
##
## The tow home in the company's world (expansion D-0307.1; CompanyTow, company_tow_net.gd, TripTow's rule):
## - counts_as_stuck(): a driver, the pedal down and almost no speed count; no driver, no pedal, speed or mud do not.
## - Solo, company_root.tscn, the van out on a trip (cargo staged, driven across the gate): a van that still runs
##   (no stuck seconds) is refused with WORLD_TOW_NOT_STUCK, nothing charged, the trip open and the van where it is;
##   after CompanyTuning.TOW_STUCK_SECONDS fed as stuck it is STUCK and tow() puts it in its place in the playon
##   (inside the gate, park_transform()), charges CompanyTuning.TOW_COST as a wallet_moved with reason `tow`,
##   closes the trip (trip_closed, the order FAILED, trips_out 0, the view says it is back) and the day no longer
##   waits for it. One second short of the limit, or moving again, is not stuck.
## - A wallet short by one is refused (WORLD_TOW_NO_MONEY) and nothing changes; a broken van (set_broken()) is towed
##   without being stuck; a van with no trip is WORLD_TOW_NO_TRIP.
## - Once a van counted TOW_STUCK_SECONDS it stays STUCK with the pedal up or nobody driving, and is cleared only
##   by moving faster than TOW_STUCK_SPEED for TOW_UNSTUCK_SECONDS in a row (or by its trip closing).
## - Only the driver, somebody riding in the van or, with nobody at the wheel, anybody may ask (else
##   WORLD_TOW_NOT_YOURS); after the tow nobody has the wheel (no driver, controls off).
## - The request, trip_tow through CompanyNet: it ends in the same tow (the host's own request is a peer's), a refusal
##   comes back as request_rejected with the key, a vehicle that is not a short id is bad_data.
## - The tow and the recovery bring the bay along (D-0307.1.f): a box on the rack and one loose on the bay's floor
##   end up in the van in the playon, still, a box that fell off stays on the road and gives its mount back, and the
##   board offers the van with the mounts it really has. A van that falls through the world keeps its cargo the same
##   way.
## - The offer's text (WORLD_TOW_OFFER, the price in it) and the day summary's line for reason `tow`.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_tow"
const HEN: ProductDefinition = preload("res://data/products/hen.tres")
const VAN: StringName = &"van_classic"

var _failures: int = 0
var _rejected: Array = []
var _events: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	_check_rule()
	await _check_world(state)
	_check_texts()
	state.call(&"reset")
	if _failures == 0:
		print("PASS: a stuck or broken company van is towed to its place in the playon for TOW_COST, its trip"
			+ " closes and the money moves as an event; refusals change nothing; any peer may ask over CompanyNet")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


## counts_as_stuck() alone.
func _check_rule() -> void:
	_expect(CompanyTow.counts_as_stuck(0.0, 800.0, 1, false), "A driver with the pedal down and no speed is stuck")
	_expect(not CompanyTow.counts_as_stuck(0.0, 800.0, 0, false), "...not without a driver")
	_expect(not CompanyTow.counts_as_stuck(0.0, 0.0, 1, false), "...not without the pedal")
	_expect(not CompanyTow.counts_as_stuck(CompanyTuning.TOW_STUCK_SPEED, 800.0, 1, false), "...not at speed")
	_expect(not CompanyTow.counts_as_stuck(0.0, 800.0, 1, true), "...not in the mud (the crew pushes there)")
	_expect(CompanyTuning.TOW_STUCK_SECONDS > 0.0 and CompanyTuning.TOW_STUCK_SPEED > 0.0, "The limits are tuning")


## The solo world: a van out on a trip, stuck, towed.
func _check_world(state: Node) -> void:
	_clean()
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	for _tick: int in range(30):
		await physics_frame
	var tow: CompanyTow = level.get_node_or_null(^"Tow") as CompanyTow
	_expect(tow != null and level.net.tow.handler.is_valid(), "The host's world has its Tow, hooked to CompanyNet")
	var van: Node3D = level.fleet.vehicle(String(VAN))
	if tow == null or van == null:
		_free(level)
		return
	level.net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		_events.append([kind, data]))
	level.net.request_rejected.connect(func(rid: int, reason: StringName) -> void: _rejected.append([rid, reason]))
	var trips: CompanyTrips = level.trips
	var home: Transform3D = CompanyFleet.park_transform(level.shed, level.net.company, 0)

	_expect(tow.tow(VAN)["reason"] == StringName(TripTow.NO_TRIP), "A van with no trip is WORLD_TOW_NO_TRIP")
	await _go_out(level, van, &"o_a", &"box_a")
	_expect(trips.trip_of(VAN) != null and trips.trips_out() == 1, "Setup: the van is out on a trip")
	for _tick: int in range(5):
		await physics_frame
	_expect(tow.stuck_seconds(VAN) == 0.0 and tow.vehicle_state(VAN) == TripTow.VEHICLE_OK,
		"Nobody drives it: no stuck seconds, the van is OK")
	var money: int = state.money
	var refused: Dictionary = tow.tow(VAN)
	_expect(refused["reason"] == StringName(TripTow.NOT_STUCK) and state.money == money
		and trips.trips_out() == 1 and van.global_position.distance_to(home.origin) > 5.0,
		"A van that still runs is refused (NOT_STUCK): nothing charged, trip open, van where it is")

	# Stuck: one second short is not enough, the limit is.
	for _second: int in range(int(CompanyTuning.TOW_STUCK_SECONDS) - 1):
		tow.feed(VAN, 0.0, 800.0, 1, false, 1.0)
	_expect(tow.vehicle_state(VAN) == TripTow.VEHICLE_OK, "One second short of the limit is not stuck")
	tow.feed(VAN, 2.0, 800.0, 1, false, 1.0)
	_expect(tow.stuck_seconds(VAN) == 0.0, "Moving again starts the count from 0")
	for _second: int in range(int(CompanyTuning.TOW_STUCK_SECONDS)):
		tow.feed(VAN, 0.0, 800.0, 1, false, 1.0)
	_expect(tow.vehicle_state(VAN) == TripTow.VEHICLE_STUCK, "At the limit the van is STUCK")
	_events.clear()
	var answer: Dictionary = tow.tow(VAN)
	_expect(bool(answer["ok"]) and answer["reason"] == &"" and answer["cost"] == CompanyTuning.TOW_COST
		and answer["black_screen_s"] == CompanyTuning.TOW_BLACK_SCREEN_SECONDS, "A stuck van is towed (%s)" % [answer])
	_expect(state.money == money - CompanyTuning.TOW_COST and state.ledger_total(TripTow.LEDGER_REASON)
		== -CompanyTuning.TOW_COST, "The wallet paid TOW_COST with reason tow (%d from %d)" % [state.money, money])
	var wallet_events: Array = _events.filter(func(e: Array) -> bool: return e[0] == CompanyNet.WALLET)
	var closed_events: Array = _events.filter(func(e: Array) -> bool: return e[0] == CompanyTripsView.CLOSED)
	_expect(wallet_events.size() == 1 and wallet_events[0][1]["reason"] == TripTow.LEDGER_REASON
		and wallet_events[0][1]["amount"] == -CompanyTuning.TOW_COST, "The money went out as one wallet_moved")
	_expect(closed_events.size() == 1 and closed_events[0][1]["vehicle"] == String(VAN)
		and closed_events[0][1]["failed"] == [&"o_a"], "...and the trip as one trip_closed with what failed")
	_expect(trips.trips_out() == 0 and trips.trip_of(VAN) == null and not level.trips_view.is_out(VAN)
		and trips.book.state_of(&"o_a") == Order.STATE_FAILED, "The trip is closed, the order FAILED, nothing out")
	_expect(van.global_position.distance_to(home.origin) < 0.2 and trips.gate.side_of(van.global_position)
		== TripGate.INSIDE, "The van is in its place in the playon, inside the gate")
	_expect(tow.stuck_seconds(VAN) == 0.0 and tow.vehicle_state(VAN) == TripTow.VEHICLE_OK,
		"...and its count and its latch start again")
	for _tick: int in range(10):
		await physics_frame
	_expect(trips.closed_trips().size() == 1 and trips.trips_out() == 0,
		"The gate seeing it come in closes nothing twice (trips closed %d)" % trips.closed_trips().size())
	_expect(tow.tow(VAN)["reason"] == StringName(TripTow.NO_TRIP), "A second tow is NO_TRIP and charges nothing")

	# A wallet short by one is refused.
	await _go_out(level, van, &"o_b", &"box_b")
	tow.feed(VAN, 0.0, 800.0, 1, false, CompanyTuning.TOW_STUCK_SECONDS)
	state.charge(state.money - (CompanyTuning.TOW_COST - 1), &"rent")
	var short: Dictionary = tow.tow(VAN)
	_expect(short["reason"] == StringName(TripTow.NO_MONEY) and short["args"] == [CompanyTuning.TOW_COST]
		and state.money == CompanyTuning.TOW_COST - 1 and trips.trip_of(VAN) != null,
		"A wallet short by one is refused (NO_MONEY): nothing charged, the trip open")
	_expect(van.global_position.distance_to(home.origin) > 5.0, "...and the van stays out")

	# Once stuck it stays stuck: the pedal up or the driver gone does not clear it, only really moving.
	for _tick: int in range(5):
		tow.feed(VAN, 0.0, 0.0, 0, false, 1.0)
	_expect(tow.vehicle_state(VAN) == TripTow.VEHICLE_STUCK,
		"A latched van stays STUCK with the pedal up and nobody driving")
	tow.feed(VAN, 5.0, 0.0, 0, false, CompanyTuning.TOW_UNSTUCK_SECONDS * 0.5)
	tow.feed(VAN, 0.0, 0.0, 0, false, 0.1)
	tow.feed(VAN, 5.0, 0.0, 0, false, CompanyTuning.TOW_UNSTUCK_SECONDS * 0.5)
	_expect(tow.vehicle_state(VAN) == TripTow.VEHICLE_STUCK,
		"...and a short jerk (under TOW_UNSTUCK_SECONDS in a row) does not clear it")
	tow.feed(VAN, 5.0, 0.0, 0, false, CompanyTuning.TOW_UNSTUCK_SECONDS)
	_expect(tow.vehicle_state(VAN) == TripTow.VEHICLE_OK and tow.stuck_seconds(VAN) == 0.0,
		"...moving for TOW_UNSTUCK_SECONDS in a row clears it")

	# Asked over CompanyNet: a van that runs is refused; somebody else's is not yours; a broken one is towed.
	state.earn(1, &"order_paid")
	var rid: int = level.net.request(CompanyTowNet.ASK, {"vehicle": String(VAN)})
	_expect(_rejected.size() == 1 and _rejected[0] == [rid, StringName(TripTow.NOT_STUCK)],
		"trip_tow of a van that runs comes back as request_rejected with the key (%s)" % [_rejected])
	tow.set_broken(VAN, true)
	van.set(&"driver_peer_id", 99)
	rid = level.net.request(CompanyTowNet.ASK, {"vehicle": String(VAN)})
	_expect(_rejected.size() == 2 and _rejected[1] == [rid, StringName(CompanyTow.NOT_YOURS)]
		and trips.trips_out() == 1 and state.money == CompanyTuning.TOW_COST,
		"Another peer drives it: WORLD_TOW_NOT_YOURS, nothing charged, the trip open (%s)" % [_rejected])
	van.set(&"driver_peer_id", level.net.multiplayer.get_unique_id())
	van.set(&"controls_enabled", true)
	rid = level.net.request(CompanyTowNet.ASK, {"vehicle": String(VAN)})
	_expect(_rejected.size() == 2 and trips.trips_out() == 0 and state.money == 0
		and van.global_position.distance_to(home.origin) < 0.2,
		"Its own driver asking for a broken van gets the tow (no refusal, trips out %d, money %d)"
		% [trips.trips_out(), state.money])
	_expect(int(van.get(&"driver_peer_id")) == 0 and not bool(van.get(&"controls_enabled")),
		"...and the wheel is let go (no driver, controls off) so the van does not lurch")
	_expect(tow.vehicle_state(VAN) == TripTow.VEHICLE_OK, "...and its fault is cleared with the tow")
	level.net.request(CompanyTowNet.ASK, {"vehicle": 5})
	level.net.request(CompanyTowNet.ASK, {"vehicle": ""})
	level.net.request(CompanyTowNet.ASK, {})
	_expect(_rejected.size() == 5 and _rejected.slice(2).all(func(r: Array) -> bool:
		return r[1] == CompanyTowNet.REASON_BAD_DATA),
		"A vehicle that is not a short id is bad_data (%s)" % [_rejected])
	await _check_cargo(level, tow, van, state)
	_free(level)


## The van carries `order`/`box` out across the gate: a trip starts with it.
func _go_out(level: CompanyRoot, van: Node3D, order: StringName, box: StringName) -> void:
	var trips: CompanyTrips = level.trips
	trips.book.add(Order.make(order, "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0,
		{&"hen": HEN}))
	trips.book.mark_packed(order, box)
	trips.stage_cargo(VAN, [order], [box])
	var exit: Vector3 = CompanyFleet.gate_of(level.shed, level.net.company)
	var outward: Vector3 = -level.shed.global_basis.z
	for at: Vector3 in [exit - outward, exit + outward * 3.0]:
		van.global_position = Vector3(at.x, van.global_position.y, at.z)
		await physics_frame
		await physics_frame


## A sealed box, in the packages of `level`, with the id `box_<order>`.
func _box(level: CompanyRoot, order: StringName) -> DeliveryPackage:
	var box := PackedBox.new(&"M")
	box.place(HEN, Vector3i.ZERO)
	box.taped = true
	box.label_order_id = order
	var package: DeliveryPackage = BoxToPackage.build(box, {&"hen": HEN})
	level.packages.add_child(package)
	return package


## Moves `van` flat to `to`, as driving there would, with the boxes that ride on it. `height`: its new height, when
## given.
func _carry(van: Node3D, riding: Array[DeliveryPackage], to: Vector3, height: float = INF) -> void:
	var local: Array[Vector3] = []
	for package: DeliveryPackage in riding:
		local.append(van.to_local(package.global_position))
	van.global_position = Vector3(to.x, van.global_position.y if height == INF else height, to.z)
	for index: int in riding.size():
		riding[index].global_position = van.to_global(local[index])
		riding[index].linear_velocity = Vector3.ZERO
		riding[index].reset_physics_interpolation()


## Whether `package` is in `van`'s bay and at rest, or close to it.
func _at_rest_in(van: Node3D, package: DeliveryPackage) -> bool:
	return bool(van.call(&"carries", package.global_position)) and package.linear_velocity.length() < 1.0


## A van out with a box on the rack, one on the floor of the bay and one that fell on the road, towed; then it falls.
func _check_cargo(level: CompanyRoot, tow: CompanyTow, van: Node3D, state: Node) -> void:
	await _go_out(level, van, &"o_c", &"box_c")
	state.earn(CompanyTuning.TOW_COST, &"order_paid")
	var on_rack: DeliveryPackage = _box(level, &"rack")
	var on_floor: DeliveryPackage = _box(level, &"floor")
	var fell: DeliveryPackage = _box(level, &"fell")
	var boxes: Array[StringName] = [on_rack.package_id, on_floor.package_id, fell.package_id]
	_expect(DispatchRack.store(van, level.packages, boxes) == boxes, "Setup: the three boxes are on the rack")
	on_floor.release_mount()
	on_floor.global_position = van.to_global(Vector3(0.0, 0.4, 2.0))
	await physics_frame
	var riding: Array[DeliveryPackage] = [on_rack, on_floor]
	fell.freeze = true
	var road: Vector3 = fell.global_position
	_carry(van, riding, van.global_position - level.shed.global_basis.z * 120.0)
	for _tick: int in range(30):
		await physics_frame
	_expect(fell.is_loaded, "Setup: the box that stayed on the road still says it is loaded")
	tow.set_broken(VAN, true)
	_expect(bool(tow.tow(VAN)["ok"]), "The van with its cargo is towed")
	for _tick: int in range(120):
		await physics_frame
	var home: Transform3D = CompanyFleet.park_transform(level.shed, level.net.company, 0)
	_expect(van.global_position.distance_to(home.origin) < 0.2, "The van is in its place in the playon")
	_expect(_at_rest_in(van, on_rack) and on_rack.is_loaded and on_rack.current_mount != null
		and on_rack.current_mount.get(&"occupied_by") == on_rack,
		"The box on the rack came with it (box %s, van %s)" % [on_rack.global_position, van.global_position])
	_expect(_at_rest_in(van, on_floor), "...and the one on the floor (box %s)" % on_floor.global_position)
	_expect(not fell.is_loaded and fell.global_position.distance_to(road) < 0.5,
		"The box that fell stays on the road, off its mount (%s)" % fell.global_position)
	_expect(DispatchRack.free_mounts(van).size() == 6, "One mount taken: the others are back (%d free)"
		% DispatchRack.free_mounts(van).size())
	var offered: VehicleDefinition = (level.get_node(^"Dispatch") as CompanyDispatch).context()["vehicle"]
	_expect(offered != null and offered.cargo_slots == 6, "The board offers the van with those six")

	# Through a hole in the ground, the boxes falling with it: back in the playon together.
	_carry(van, riding, van.global_position, CompanyFleet.FALL_Y_M - 5.0)
	for _tick: int in range(60):
		await physics_frame
	_expect(van.global_position.distance_to(home.origin) < 0.2, "The fallen van is back in the playon")
	_expect(_at_rest_in(van, on_rack) and on_rack.is_loaded,
		"...with the box on the rack (%s)" % on_rack.global_position)
	_expect(_at_rest_in(van, on_floor), "...and the one on the floor (%s)" % on_floor.global_position)


## The offer's text carries the price; the day summary names reason `tow`.
func _check_texts() -> void:
	_expect(CompanyTow.offer_text().contains(str(CompanyTuning.TOW_COST)),
		"The offer's text has the price (%s)" % CompanyTow.offer_text())
	_expect(DaySummaryPanel.REASON_KEYS.get("tow") == "UI_FINANCE_REASON_TOW"
		and DaySummaryPanel.reason_name("tow") != "tow", "The day summary has its own line for reason tow (%s)"
		% DaySummaryPanel.reason_name("tow"))


func _free(level: Node) -> void:
	level.queue_free()
	current_scene = null
	_clean()


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
