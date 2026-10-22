class_name CompanyTrips
extends Node
## The trips out of the shed, hooked to the world (expansion D-0302.1).
##
## Child of CompanyRoot on the host only: the host decides. A client has none and sees the trips out
## through its CompanyTripsView (D-0302.2.a), which the host's view keeps by publishing every
## trip_started, departure_refused, trip_closed and refused_returned of this node as a CompanyNet
## event. It owns the TripGate across the playon's far edge (CompanyFleet.gate_of(), the yard outside the shed's
## exit) and the active Trips, and every physics tick it feeds the gate with the position of each node in group
## VEHICLE_GROUP (named by its vehicle id). Cargo the dispatch zone hands a vehicle waits in stage_cargo(); when
## the vehicle crosses the gate outward the Trip starts with it (orders go OUT), and when it comes back in the
## Trip closes (what was not delivered fails). trips_out() is what the host's DayCycle.trips_out
## reads, so the day waits for a vehicle still out (S3); this node stays the authority there, the
## views only follow it. Nothing here sends anything: the host's view publishes (its follow()).
##
## The company's vehicles join the group in CompanyFleet (World/Vehicles, D-0302.2.b), parked inside the
## gate's line (the playon); only those of this node's own multiplayer count (a test holds several sessions in
## one tree). The OrderBook is this node's own, not the one every peer shares
## (CompanyNet.orders.book, D-0813), until what it does to it (mark_out, close) goes out as events
## (rows 17, 19 and 20 of red-autoridad.md). Boxes are only ids here; where they ride is the
## vehicle's business.
##
## At most `far_max` vehicles are out at once (D-0316, CompanyTuning.VEHICLES_FAR_MAX): a vehicle
## out is one whose trip is out, or one that crossed outward while refused. departure_verdict() is
## what the dispatch board asks before loading a vehicle. A vehicle with cargo staged that tries to
## cross the gate outward with that many already out is held at the gate (D-0316.2, `hold_at_gate`):
## every tick it would cross, it is put back where it last stood inside, its horizontal motion stopped,
## so it never leaves, nor counts as out (its heading is its own: it can steer along the line); departure_held
## says so, with the reason and its driver, at most once every `held_notice_msec` per vehicle and driver
## (CompanyTripsView tells that driver). Its cargo
## stays staged. Only one fed through track(), with no node to hold (or with hold_at_gate off), still
## crosses: it starts no trip (departure_refused) but counts as out until it crosses back in
## (trips_out(), so the day waits for it too; refused_returned when it does).

signal trip_started(trip: Trip)
signal trip_closed(trip: Trip, failed: Array[StringName])
## A vehicle crossed outward with `far_max` vehicles out: no trip started, it counts as out until
## it is back. `reason` is departure_verdict()'s {ok, key, args}.
signal departure_refused(vehicle_id: StringName, reason: Dictionary)
## A vehicle that left while refused crossed back in: it no longer counts as out (no trip closes).
signal refused_returned(vehicle_id: StringName)
## A vehicle with cargo tried to cross outward with `far_max` out and was held inside the gate (D-0316.2):
## `reason` is departure_verdict()'s, `driver` its driver_peer_id (0: nobody at the wheel). At most once
## every held_notice_msec per vehicle and driver, however many ticks it pushes against the gate (a new driver
## is told at once).
signal departure_held(vehicle_id: StringName, reason: Dictionary, driver: int)

## The group of the vehicles the gate watches.
const VEHICLE_GROUP: StringName = &"company_vehicle"
## Translation key (strings_world.csv) of the refusal: "%d vehicles are already out".
const FAR_LIMIT: String = "WORLD_DISPATCH_FAR_LIMIT"
## Most orders, and most boxes, one vehicle's cargo keeps (stage_cargo()), far over any vehicle's
## load: what one trip event may carry (CompanyTripsView.MAX_ITEMS). DispatchZone hands no more.
const MAX_CARGO: int = 64
## Longest vehicle, order or box id kept (RpcGuard's text limit): what a trip event may carry.
const MAX_ID_LENGTH: int = RpcGuard.MAX_TEXT_LENGTH

var book: OrderBook = OrderBook.new()
var gate: TripGate
## Game minute for the trip's times, Callable() -> int. Unset: 0.
var minute_now: Callable = Callable()
## Most vehicles out at once.
var far_max: int = CompanyTuning.VEHICLES_FAR_MAX
## Hold at the gate a vehicle that may not leave (D-0316.2); off, it crosses refused and counts as out.
var hold_at_gate: bool = true
## Real milliseconds between two departure_held of the same vehicle.
var held_notice_msec: int = 3000

var _staged: Dictionary = {}
var _active: Dictionary = {}
## vehicle id -> true: crossed outward while refused, out without a trip until it is back.
var _refused_out: Dictionary = {}
var _closed: Array[Trip] = []
var _next_id: int = 1
## vehicle id -> its global_position the last tick it stood inside the gate (where a hold puts it back).
var _inside_pose: Dictionary = {}
## vehicle id -> [driver, Time.get_ticks_msec()] of its last departure_held: a new driver is told at once.
var _held_told: Dictionary = {}


## The gate across the playon's far edge: `exit_origin` is the middle of the opening in world coordinates
## (CompanyFleet.gate_of()), `width` its width in metres, `outward` the way out (the shed's north, -Z of its basis;
## default the world's -Z). The yard (set_yard()) makes the whole compound the inside.
func setup(exit_origin: Vector3, width: float, outward: Vector3 = Vector3.FORWARD) -> void:
	gate = TripGate.new(exit_origin, outward, width)
	gate.departed.connect(_on_departed)
	gate.returned.connect(_on_returned)


## The inside is the rectangle of the shed and the playon, `back` metres behind the gate's line and `half_width` to
## each side of the axis (CompanyFleet.yard_back_m() / yard_half_width_m()): leaving it anywhere is a departure,
## coming in anywhere a return (TripGate.set_yard()). Call after setup().
func set_yard(back: float, half_width: float) -> void:
	if gate != null:
		gate.set_yard(back, half_width)


## What the dispatch zone loaded on `vehicle_id`: it leaves with this when it crosses the gate.
## Only what a trip event can carry is kept (one warning when something is left out): the first
## MAX_CARGO orders and boxes whose ids fit (id_fits()); a vehicle whose own id doesn't fit gets
## nothing staged, so it never starts a trip the other peers could not be told about.
func stage_cargo(vehicle_id: StringName, orders: Array[StringName], boxes: Array[StringName]) -> void:
	if not id_fits(vehicle_id):
		push_warning("CompanyTrips: vehicle id '%s' is empty or over %d characters; nothing staged"
			% [vehicle_id, MAX_ID_LENGTH])
		return
	var kept_orders: Array[StringName] = fitting(orders)
	var kept_boxes: Array[StringName] = fitting(boxes)
	if kept_orders.size() < orders.size() or kept_boxes.size() < boxes.size():
		push_warning("CompanyTrips: %s keeps %d of %d orders and %d of %d boxes (at most %d ids of %d characters)"
			% [vehicle_id, kept_orders.size(), orders.size(), kept_boxes.size(), boxes.size(), MAX_CARGO,
				MAX_ID_LENGTH])
	_staged[vehicle_id] = {"orders": kept_orders, "boxes": kept_boxes}


## An id a trip event may carry: not empty, at most MAX_ID_LENGTH characters.
static func id_fits(id: StringName) -> bool:
	return id != &"" and String(id).length() <= MAX_ID_LENGTH


## The first MAX_CARGO ids of `ids` that fit (id_fits()), in order.
static func fitting(ids: Array[StringName]) -> Array[StringName]:
	var kept: Array[StringName] = []
	for id: StringName in ids:
		if kept.size() < MAX_CARGO and id_fits(id):
			kept.append(id)
	return kept


## Where a vehicle is now. Returns what the gate saw (&"departed", &"returned" or &"").
func track(vehicle_id: StringName, pos: Vector3) -> StringName:
	return gate.track(vehicle_id, pos) if gate != null else &""


func trip_of(vehicle_id: StringName) -> Trip:
	return _active.get(vehicle_id)


## Vehicles out: those with a trip out and those that left while refused (what DayCycle waits for).
func trips_out() -> int:
	return _active.size() + _refused_out.size()


## Whether `vehicle_id` is out (with its trip, or without one because it was refused).
func is_out(vehicle_id: StringName) -> bool:
	return _active.has(vehicle_id) or _refused_out.has(vehicle_id)


## May `vehicle_id` leave now? {ok, key, args} as DispatchRules answers: not ok, with FAR_LIMIT and
## [far_max], while `far_max` other vehicles are out. A vehicle already out is never refused.
func departure_verdict(vehicle_id: StringName) -> Dictionary:
	if is_out(vehicle_id) or trips_out() < far_max:
		return {"ok": true, "key": "", "args": []}
	return {"ok": false, "key": FAR_LIMIT, "args": [far_max]}


func closed_trips() -> Array[Trip]:
	return _closed.duplicate()


## A vehicle left the world mid-day (sold, towed, freed): the gate forgets it, its staged cargo is dropped and
## it no longer counts as out: a trip it had closes as if it came back (what wasn't delivered fails,
## trip_closed) and one out refused is back (refused_returned), so the day never waits for a vehicle that
## isn't there. Nothing calls it yet (CompanyFleet frees none mid-day); the world closing is no vehicle leaving.
func forget(vehicle_id: StringName) -> void:
	if gate != null:
		gate.forget(vehicle_id)
	_staged.erase(vehicle_id)
	_inside_pose.erase(vehicle_id)
	_held_told.erase(vehicle_id)
	_on_returned(vehicle_id)


func _physics_process(_delta: float) -> void:
	if gate == null or not is_inside_tree():
		return
	for vehicle: Node in get_tree().get_nodes_in_group(VEHICLE_GROUP):
		if vehicle is Node3D and vehicle.multiplayer == multiplayer:
			_watch(vehicle as Node3D)


## One vehicle's tick at the gate: held inside when it would leave refused (hold_at_gate), else fed to
## the gate, its pose kept while it stands inside.
func _watch(body: Node3D) -> void:
	var id := StringName(body.name)
	var at: Vector3 = body.global_position
	if hold_at_gate and _inside_pose.has(id) and gate.departs(id, at) and _would_refuse(id):
		_hold(body, id)
		return
	gate.track(id, at)
	if gate.side_of(at) == TripGate.INSIDE:
		_inside_pose[id] = at
	else:
		_inside_pose.erase(id)


## What _on_departed() would refuse: a vehicle in, with cargo staged, that departure_verdict() doesn't let go.
func _would_refuse(vehicle_id: StringName) -> bool:
	return _staged.has(vehicle_id) and not is_out(vehicle_id) and not departure_verdict(vehicle_id)["ok"]


## Puts `body` back where it last stood inside the gate (at its own height: its suspension holds that), its
## horizontal motion stopped, and says so (departure_held) unless it told this driver about this vehicle in
## the last held_notice_msec. Its heading is left as it is, turning too: the gate is a wall it can steer along,
## not a lock. The gate never sees it outside.
func _hold(body: Node3D, vehicle_id: StringName) -> void:
	var inside: Vector3 = _inside_pose[vehicle_id]
	body.global_transform = Transform3D(body.global_basis, Vector3(inside.x, body.global_position.y, inside.z))
	var rigid := body as RigidBody3D
	if rigid != null and not rigid.freeze:
		# On the body's live state: RigidBody3D.linear_velocity is the copy from before a VehicleBody3D's
		# suspension impulses of this step, and writing it undid them (the van sank onto its chassis, as
		# vehicle_prediction.gd notes).
		var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(rigid.get_rid())
		if state != null:
			state.linear_velocity = Vector3(0.0, state.linear_velocity.y, 0.0)
	body.reset_physics_interpolation()
	var wheel: Variant = body.get(&"driver_peer_id")
	var driver: int = int(wheel) if wheel is int else 0
	var now: int = Time.get_ticks_msec()
	var told: Array = _held_told.get(vehicle_id, [])
	if not told.is_empty() and int(told[0]) == driver and now - int(told[1]) < held_notice_msec:
		return
	_held_told[vehicle_id] = [driver, now]
	departure_held.emit(vehicle_id, departure_verdict(vehicle_id), driver)


func _on_departed(vehicle_id: StringName) -> void:
	if is_out(vehicle_id) or not _staged.has(vehicle_id):
		return
	var verdict: Dictionary = departure_verdict(vehicle_id)
	if not verdict["ok"]:
		_refused_out[vehicle_id] = true
		departure_refused.emit(vehicle_id, verdict)
		return
	var cargo: Dictionary = _staged[vehicle_id]
	var trip_id := StringName("trip_%d" % _next_id)
	var trip: Trip = Trip.start(trip_id, vehicle_id, cargo["orders"], cargo["boxes"], book, minute())
	if trip == null:
		return
	_next_id += 1
	_staged.erase(vehicle_id)
	_active[vehicle_id] = trip
	trip_started.emit(trip)


func _on_returned(vehicle_id: StringName) -> void:
	if _refused_out.erase(vehicle_id):
		refused_returned.emit(vehicle_id)
	var trip: Trip = _active.get(vehicle_id)
	if trip == null:
		return
	_active.erase(vehicle_id)
	var failed: Array[StringName] = trip.close(book, minute())
	_closed.append(trip)
	trip_closed.emit(trip, failed)


## The game minute now (minute_now's, 0 while it is unset): the trips' times, and the minute a
## refusal or a refused vehicle's return is published with (CompanyTripsView).
func minute() -> int:
	return int(minute_now.call()) if minute_now.is_valid() else 0
