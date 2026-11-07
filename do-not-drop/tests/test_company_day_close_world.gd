extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_day_close_world.gd
##
## The day's close wired into the real solo company_root.tscn (D-0851: CompanyRoot._add_trips(), its business tick's
## "orders" step and CompanyDispatch.add_to(); test_company_day_close_orders plays the rules on a world of its own, so
## losing these lines of the root only shows here):
## - the root's CompanyTrips asks the day whether it may leave and times a delivery with the shed's clock;
## - through the real business tick a customer gives up on a late order but not on one loaded on the van (the "orders"
##   step knows CompanyTrips.carries());
## - a trip that comes back with its order undelivered fails it in the shared book, not only in the trips' own;
## - in CLOSING the van gets DAY_CLOSED; with SUMMARY what was loaded on it and never left comes off (rule 7): no cargo,
##   the board offers the van again and no longer hides the box, and on the next day crossing the gate starts no trip.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_day_close_world"
const HEN: ProductDefinition = preload("res://data/products/hen.tres")
## One business tick and a bit, so every call runs exactly one (the rest is dropped: no catch-up).
const TICK_SECONDS: float = 1.5 / CompanyTuning.BUSINESS_TICK_HZ
const GHOST: StringName = &"van_ghost"
const BOX: StringName = &"box_loaded"
const GHOST_BOX: StringName = &"box_trip"

var _failures: int = 0
var _zone: StringName = &""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	for zone: ZoneDefinition in CompanyCatalog.load_all().zones():
		if zone.is_open_at_start() and _zone == &"":
			_zone = zone.id
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var dispatch := level.get_node_or_null(^"Dispatch") as CompanyDispatch
	_expect(level.trips != null and level.business_tick != null and dispatch != null,
		"The solo root has its trips, its business tick and its board")
	if level.trips != null and level.business_tick != null and dispatch != null:
		_play_day(level, dispatch)
	level.queue_free()
	current_scene = null
	await process_frame
	state.call(&"reset")
	_clean()
	if _failures == 0:
		print("PASS: the real company root denies leaving after 20:00, keeps a loaded order, fails what came back"
			+ " undelivered and lets go of what never left when the day ends")
	quit(_failures)


func _play_day(level: CompanyRoot, dispatch: CompanyDispatch) -> void:
	var net: CompanyNet = level.net
	var book: OrderBook = net.orders.book
	var trips: CompanyTrips = level.trips
	var cycle: DayCycle = level.day_cycle
	var vans: Array[Node3D] = level.fleet.vehicles()
	var van := StringName(vans[0].name)
	cycle.call(&"_transition", DayCycle.Phase.OPERATING)
	_expect(trips.departure_verdict(van)["ok"], "In OPERATING the van may leave")
	_check_shed_minute(level)

	net.orders.plan([_order(&"w_free", 480, 500), _order(&"w_loaded", 480, 500), _order(&"w_trip", 480, 1300),
		_order(&"w_window", 1100, 1300)])
	_tick(level, 501)
	_expect(book.state_of(&"w_free") == Order.STATE_LATE and book.state_of(&"w_loaded") == Order.STATE_LATE
		and book.state_of(&"w_trip") == Order.STATE_OPEN, "The business tick brings the orders in, two of them late")
	dispatch._order_of[BOX] = &"w_loaded"
	trips.stage_cargo(van, [&"w_loaded"], [BOX])
	dispatch._on_loaded(van, [BOX])
	_expect(trips.book.state_of(&"w_loaded") == Order.STATE_PACKED and dispatch.available_vehicle() != vans[0],
		"The van is loaded with one of them: the trips' book has it packed and the board doesn't offer the van")

	_tick(level, 500 + CompanyTuning.ORDER_ABANDON_MIN + 1)
	_expect(book.state_of(&"w_free") == Order.STATE_FAILED and book.state_of(&"w_loaded") == Order.STATE_LATE,
		"A window late the customer gives up on the free order, not on the loaded one (got %s, %s)"
		% [book.state_of(&"w_free"), book.state_of(&"w_loaded")])
	_check_trip_comes_back(level)

	_tick(level, 1150)
	_expect(book.state_of(&"w_window") == Order.STATE_OPEN, "W comes in at 19:10")
	_tick(level, CompanyTuning.DAY_END_MIN)
	_expect(cycle.phase() == DayCycle.Phase.CLOSING and trips.departure_verdict(van)["key"] == CompanyTrips.DAY_CLOSED,
		"At 20:00 the day is CLOSING and the van gets DAY_CLOSED (got %s, %s)"
		% [cycle.phase_name(), trips.departure_verdict(van)])
	_expect(trips.has_cargo(van), "...still loaded: it may not leave, nothing has unloaded it yet")
	_tick(level, CompanyTuning.DAY_END_MIN + 1)
	_expect(book.open_orders().is_empty() and book.state_of(&"w_window") == Order.STATE_CANCELLED
		and book.state_of(&"w_loaded") == Order.STATE_FAILED,
		"The tick after, with nothing out, the day's orders close, the loaded one too (got %s, %s)"
		% [book.state_of(&"w_window"), book.state_of(&"w_loaded")])
	_tick(level, CompanyTuning.DAY_END_MIN + 2)
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY, "SUMMARY follows (got %s)" % cycle.phase_name())
	_check_let_go(level, dispatch, vans[0])


## The shed's clock runs behind the world's by its lag: a delivery reads the shed's, the root wired it.
func _check_shed_minute(level: CompanyRoot) -> void:
	var cycle: DayCycle = level.day_cycle
	level.clock.start(700.0)
	cycle._lag = 60.0
	_expect(level.trips.minute() == 700 and level.trips.delivery_minute() == 640,
		"The root's trips time a delivery with the shed's clock (world %d, delivery %d)"
		% [level.trips.minute(), level.trips.delivery_minute()])
	cycle._lag = 0.0


## A trip with one order leaves and comes back: the order fails in the shared book.
func _check_trip_comes_back(level: CompanyRoot) -> void:
	var trips: CompanyTrips = level.trips
	var book: OrderBook = level.net.orders.book
	trips.book.add(book.get_order(&"w_trip"))
	trips.book.mark_packed(&"w_trip", GHOST_BOX)
	trips.stage_cargo(GHOST, [&"w_trip"], [GHOST_BOX])
	trips.gate.departed.emit(GHOST)
	_expect(trips.trip_of(GHOST) != null, "A vehicle leaves with W")
	trips.gate.returned.emit(GHOST)
	_expect(trips.trip_of(GHOST) == null and book.state_of(&"w_trip") == Order.STATE_FAILED,
		"...and comes back without delivering: W fails in the shared book (got %s)" % book.state_of(&"w_trip"))


## SUMMARY: the van is free again, and the next day it starts nothing with what it carried.
func _check_let_go(level: CompanyRoot, dispatch: CompanyDispatch, van_body: Node3D) -> void:
	var trips: CompanyTrips = level.trips
	var van := StringName(van_body.name)
	_expect(not trips.has_cargo(van) and not trips.carries(&"w_loaded")
		and trips.book.state_of(&"w_loaded") == Order.STATE_CANCELLED,
		"With SUMMARY the van lets its cargo go (cargo %s, book %s)" % [trips.has_cargo(van),
		trips.book.state_of(&"w_loaded")])
	_expect(not dispatch._loaded.has(BOX), "...the board stops hiding the box")
	_expect(dispatch.available_vehicle() == van_body, "...and offers the van again")
	var closed: int = trips.closed_trips().size()
	_expect(level.day_cycle.next_day() and level.net.orders.book.size() == 0, "Day 2 opens with an empty book")
	trips.gate.departed.emit(van)
	_expect(trips.trip_of(van) == null and trips.trips_out() == 0,
		"The van crosses the gate with no trip: it carries nothing")
	trips.gate.returned.emit(van)
	_expect(trips.closed_trips().size() == closed, "...and comes back with none to close")


## The clock reads `minute` and one real business tick runs (the day cycle, then the orders step).
func _tick(level: CompanyRoot, minute: int) -> void:
	level.clock.start(float(minute))
	level.business_tick.tick.advance(TICK_SECONDS)


func _order(id: StringName, created: int, due: int) -> Dictionary:
	var house := StringName("%s_house_1" % _zone)
	var items: Array = [{"product": &"hen", "qty": 1}]
	return Order.normalize(Order.make(id, "Ana", _zone, house, items, created, {&"hen": HEN}, [], due))


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
