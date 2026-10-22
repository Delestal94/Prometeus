class_name CompanyGateBrake
extends Node
## A client at the wheel of a company vehicle the host holds at the gate brakes its own copy there too
## (expansion D-0316.4).
##
## The host holds a vehicle with cargo that may not leave (CompanyTrips.hold_at_gate, D-0316.2): every tick it would
## cross the gate outward it is put back where it last stood inside, its horizontal motion stopped. The client at
## the wheel predicts its copy (VehiclePrediction, N-218) and knew nothing of that: its copy ran on past the line for
## a round trip and the host's stop came back as one correction past NetPredictionReconciler.SNAP_DISTANCE (3.05 to
## 3.17 m at 12 m/s over 150 ms + 20 ms of jitter, the copy up to 5 m from the host's van).
##
## Child "GateBrake" of CompanyRoot on a client (add_to(); the host's hold is CompanyTrips'), after World, so like
## CompanyTrips it runs once the vehicles' tick recorded what their last step left and set this tick's forces. It
## watches the company vehicles this peer predicts (CompanyTrips.VEHICLE_GROUP, is_predicted()) and keeps where each
## last stood inside the gate. When the view says one was held (CompanyTripsView.held_at_gate, from the host's
## _held_here) it builds the gate the host watches anew (`gate_source`: CompanyFleet.trip_gate(), all of it the shed
## and the company the snapshot brought) and, for CompanyTuning.GATE_BRAKE_REAL_SECONDS after each notice, does to
## that copy what the host does: every tick it would cross, back where it last stood inside, horizontal motion
## stopped, heading its own (CompanyTrips.put_back()). The host tells the driver again every held_notice_msec while
## it pushes, which keeps the brake on. It lets go sooner when the view says the host lets the vehicle go too: fewer
## than the cap out (a vehicle came back), or this one out.
##
## Nothing is sent and nothing here decides: the host's hold stays the truth and whatever still differs is eased by
## the prediction's reconciler like any other difference. The first notice comes late: by then the copy is past the
## line by its speed times the input's way up, the host's input cushion and the notice's way back. That copy is only
## stopped where it is (CompanyTrips.stop()) and the reconciler slides it back to where the host holds it: put back
## too, the stretch it ran on would be taken off twice (by the brake, then by the reconciler, which compares the
## host's stop with the states it recorded out there) and the first time in one jump. Measured in test_company_fleet
## at 12 m/s over 150 ms + 20 ms: no snap, at most 0.23 m a tick, the copy 1.8-2.1 m from the host's van (2.7-3.1 m
## with the notice 85 ms late, as a real link brings it). Not covered: the host letting go for a reason this peer
## can't see (the cargo unloaded while it pushes) keeps the copy braked until the time is up, and the reconciler
## then catches it up.

## The view whose held_at_gate this follows (attach()). Null: only the time lets a brake go.
var view: CompanyTripsView = null
## Callable() -> TripGate, the gate the host watches (CompanyFleet.trip_gate()): built on each notice, and the first
## time a copy is predicted. Unset or returning null: nothing is braked.
var gate_source: Callable = Callable()
## Real milliseconds one notice keeps the brake on.
var brake_msec: int = roundi(CompanyTuning.GATE_BRAKE_REAL_SECONDS * 1000.0)

var _gate: TripGate = null
## vehicle id -> [Time.get_ticks_msec() it is braked until, the cap it was held with].
var _braking: Dictionary = {}
## vehicle id -> where its predicted copy last stood inside the gate (global position).
var _inside_pose: Dictionary = {}
## vehicle id -> whether its predicted copy stood inside the gate last tick (after the brake: put back, it did).
var _was_inside: Dictionary = {}


## Client (CompanyRoot): a GateBrake child of `parent`, added after its World so it runs after the vehicles' tick,
## following `trips_view` and braking at the gate the host's CompanyTrips watches: CompanyFleet.trip_gate() of `shed`
## and of `company_net`'s company, the one its snapshot brought.
static func add_to(
	parent: Node, trips_view: CompanyTripsView, shed: Node3D, company_net: CompanyNet
) -> CompanyGateBrake:
	var brake := CompanyGateBrake.new()
	brake.name = "GateBrake"
	brake.gate_source = func() -> TripGate:
		var placed: bool = is_instance_valid(shed) and is_instance_valid(company_net)
		return CompanyFleet.trip_gate(shed, company_net.company) if placed else null
	parent.add_child(brake)
	brake.attach(trips_view)
	return brake


## Follows `trips_view`'s held_at_gate from now on.
func attach(trips_view: CompanyTripsView) -> void:
	if trips_view == null:
		return
	view = trips_view
	if not view.held_at_gate.is_connected(hold):
		view.held_at_gate.connect(hold)


## The host held `vehicle_id`, which this peer drives, with `cap` vehicles out: the copy it predicts is braked at the
## gate for brake_msec from now (again from now if it already was), on the gate as it stands now.
func hold(vehicle_id: StringName, cap: int) -> void:
	_braking[vehicle_id] = [Time.get_ticks_msec() + brake_msec, cap]
	_gate = _built_gate()


## Whether this peer brakes its copy of `vehicle_id` at the gate now.
func is_braking(vehicle_id: StringName) -> bool:
	return _braking.has(vehicle_id)


## The gate the copies are braked at (null before any is predicted, or without a gate_source).
func gate() -> TripGate:
	return _gate


func _physics_process(_delta: float) -> void:
	if not is_inside_tree():
		return
	_let_go(Time.get_ticks_msec())
	for vehicle: Node in get_tree().get_nodes_in_group(CompanyTrips.VEHICLE_GROUP):
		if vehicle is Node3D and vehicle.multiplayer == multiplayer:
			_watch(vehicle as Node3D)


## One vehicle's tick: only a copy this peer predicts. Inside the gate its pose is kept. Braked, one crossing now (it
## stood inside last tick) is put back there, as the host does; one already past the line when the notice came is
## stopped where it is instead, and the reconciler brings it back to where the host holds it (put back here too, the
## round trip it ran on past the line would be taken off twice, and in one jump).
func _watch(body: Node3D) -> void:
	var id := StringName(body.name)
	if not body.has_method(&"is_predicted") or not bool(body.call(&"is_predicted")):
		_inside_pose.erase(id)
		_was_inside.erase(id)
		return
	if _gate == null:
		_gate = _built_gate()
		if _gate == null:
			return
	var at: Vector3 = body.global_position
	var inside: bool = _gate.side_of(at) == TripGate.INSIDE
	var was_inside: bool = _was_inside.get(id, false)
	_was_inside[id] = inside
	if inside:
		_inside_pose[id] = at
	elif not _braking.has(id):
		return
	elif was_inside and _inside_pose.has(id):
		CompanyTrips.put_back(body, _inside_pose[id])
		_was_inside[id] = true
	else:
		CompanyTrips.stop(body)


## Lets a brake go when the host lets the vehicle go too, as far as this peer knows: its time is up, fewer than its
## cap are out, or the vehicle is out itself (the host started its trip).
func _let_go(now: int) -> void:
	var watching: bool = view != null and is_instance_valid(view)
	for id: StringName in _braking.keys():
		var brake: Array = _braking[id]
		if now >= int(brake[0]) or (watching and (view.is_out(id) or view.trips_out() < int(brake[1]))):
			_braking.erase(id)


func _built_gate() -> TripGate:
	if not gate_source.is_valid():
		return null
	var built: Variant = gate_source.call()
	return built as TripGate if built is TripGate else null
