class_name CompanyTrips
extends Node
## The trips out of the shed, hooked to the world (expansion D-0302.1).
##
## Child of CompanyRoot on the host (a client has none: the host decides, a client only sees the
## vehicle). It owns the TripGate across the shed's exit and the active Trips, and every physics
## tick it feeds the gate with the position of each node in group VEHICLE_GROUP (named by its
## vehicle id). Cargo the dispatch zone hands a vehicle waits in stage_cargo(); when the vehicle
## crosses the gate outward the Trip starts with it (orders go OUT), and when it comes back in the
## Trip closes (what was not delivered fails). trips_out() is what DayCycle.trips_out reads, so the
## day waits for a vehicle still out (S3).
##
## No company vehicle exists yet (D-0207 and later put it in the world), so nothing joins the group
## and the gate stays idle; the OrderBook is this node's own until D-0813.1 points it at the book every
## peer shares (CompanyNet.orders.book, D-0813). Boxes are only ids here; where they ride is the
## vehicle's business.
##
## At most `far_max` vehicles are out at once (D-0316, CompanyTuning.VEHICLES_FAR_MAX): a vehicle
## out is one whose trip is out, or one that crossed outward while refused. departure_verdict() is
## what the dispatch board asks before loading a vehicle; a vehicle that crosses the gate outward
## with that many already out starts no trip (departure_refused, with the same reason) but counts
## as out until it crosses back in (trips_out(), so the day waits for it too), and keeps its cargo
## staged for its next departure. Stopping it at the gate and telling its driver why is D-0316.2.

signal trip_started(trip: Trip)
signal trip_closed(trip: Trip, failed: Array[StringName])
## A vehicle crossed outward with `far_max` vehicles out: no trip started, it counts as out until
## it is back. `reason` is departure_verdict()'s {ok, key, args}.
signal departure_refused(vehicle_id: StringName, reason: Dictionary)

## The group of the vehicles the gate watches.
const VEHICLE_GROUP: StringName = &"company_vehicle"
## Translation key (strings_world.csv) of the refusal: "%d vehicles are already out".
const FAR_LIMIT: String = "WORLD_DISPATCH_FAR_LIMIT"

var book: OrderBook = OrderBook.new()
var gate: TripGate
## Game minute for the trip's times, Callable() -> int. Unset: 0.
var minute_now: Callable = Callable()
## Most vehicles out at once.
var far_max: int = CompanyTuning.VEHICLES_FAR_MAX

var _staged: Dictionary = {}
var _active: Dictionary = {}
## vehicle id -> true: crossed outward while refused, out without a trip until it is back.
var _refused_out: Dictionary = {}
var _closed: Array[Trip] = []
var _next_id: int = 1


## The gate across the shed's exit (north wall, -Z, centered): `exit_origin` is the middle of the
## opening in world coordinates, `width` its width in metres.
func setup(exit_origin: Vector3, width: float) -> void:
	gate = TripGate.new(exit_origin, Vector3.FORWARD, width)
	gate.departed.connect(_on_departed)
	gate.returned.connect(_on_returned)


## What the dispatch zone loaded on `vehicle_id`: it leaves with this when it crosses the gate.
func stage_cargo(vehicle_id: StringName, orders: Array[StringName], boxes: Array[StringName]) -> void:
	_staged[vehicle_id] = {"orders": orders.duplicate(), "boxes": boxes.duplicate()}


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


## A vehicle left the world: it is not tracked any more and a trip it had stays out.
func forget(vehicle_id: StringName) -> void:
	if gate != null:
		gate.forget(vehicle_id)


func _physics_process(_delta: float) -> void:
	if gate == null or not is_inside_tree():
		return
	for vehicle: Node in get_tree().get_nodes_in_group(VEHICLE_GROUP):
		if vehicle is Node3D:
			gate.track(StringName(vehicle.name), (vehicle as Node3D).global_position)


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
	var trip: Trip = Trip.start(trip_id, vehicle_id, cargo["orders"], cargo["boxes"], book, _minute())
	if trip == null:
		return
	_next_id += 1
	_staged.erase(vehicle_id)
	_active[vehicle_id] = trip
	trip_started.emit(trip)


func _on_returned(vehicle_id: StringName) -> void:
	_refused_out.erase(vehicle_id)
	var trip: Trip = _active.get(vehicle_id)
	if trip == null:
		return
	_active.erase(vehicle_id)
	var failed: Array[StringName] = trip.close(book, _minute())
	_closed.append(trip)
	trip_closed.emit(trip, failed)


func _minute() -> int:
	return int(minute_now.call()) if minute_now.is_valid() else 0
