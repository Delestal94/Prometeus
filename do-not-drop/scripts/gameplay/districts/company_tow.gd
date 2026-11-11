class_name CompanyTow
extends Node
## "Volver con grua" in the company's world (expansion D-0307.1): the host's side of TripTow.tow_home().
##
## Child "Tow" of CompanyRoot on the host only (a client has none: it asks over CompanyNet, trip_tow, and sees the
## result as the events it already follows). It does three things:
## - It knows when a vehicle on a trip is STUCK: every physics tick, a vehicle of the fleet with an open trip, a
##   driver, the pedal down and almost no speed (CompanyTuning.TOW_STUCK_SPEED) counts seconds, and past
##   CompanyTuning.TOW_STUCK_SECONDS it is TripTow.VEHICLE_STUCK and stays so (a latch: lifting the pedal or leaving the
##   wheel does not clear it) until it moves faster than TOW_STUCK_SPEED for TOW_UNSTUCK_SECONDS in a row, or its trip
##   closes. The same rule as the delivery run's wedge counter
##   (level_common.gd), but its own: that one lives in a level this world is not. In the mud it never counts (the
##   crew pushes there); moving, or letting go of the wheel, starts the count again. Only vehicles with a trip are
##   looked at (two at most, CompanyTuning.VEHICLES_FAR_MAX): a handful of property reads a tick.
## - It knows when one is BROKEN: nothing breaks a company vehicle yet (VehicleFaults' door and mirror live in the
##   delivery run and never stop a van), so set_broken() is the hook the day a fault or a crash does (D-0307.2).
## - tow() asks TripTow, through CompanyTrips.tow(), with a wallet that moves the company's money as an event
##   (CompanyNet.publish_wallet(): wallet_moved on every peer, ledger reason `tow`), closes the trip (trip_closed
##   goes out through the TripsView) and puts the vehicle back in its place in the playon (CompanyFleet.send_home()).
##   Refused, nothing changes. Only the vehicle's driver, somebody riding in it or, with nobody at the wheel, anybody
##   may ask (WORLD_TOW_NOT_YOURS otherwise); after it nobody has the wheel (CompanyFleet.release_wheel()).
##   The black screen of the answer (`black_screen_s`) is the HUD's (D-0307.1, open).
##
## It sets CompanyNet.tow.handler: any peer's trip_tow request ends in ask(). Nothing here names an autoload.

## Translation key (strings_world.csv) of the offer the board shows next to the button: "Tow home (-$%d)".
const OFFER_KEY: String = "WORLD_TOW_OFFER"
## Refusal key: another peer drives (or rides in) that vehicle.
const NOT_YOURS: String = "WORLD_TOW_NOT_YOURS"

var trips: CompanyTrips
var fleet: CompanyFleet
var net: CompanyNet

## vehicle id -> seconds it has counted as stuck.
var _stuck: Dictionary = {}
## vehicle id -> true: it counted TOW_STUCK_SECONDS and stays STUCK until it really moves (feed()).
var _latched: Dictionary = {}
## vehicle id -> seconds in a row it has moved faster than TOW_STUCK_SPEED while latched.
var _moving: Dictionary = {}
## vehicle id -> true: a fault or a crash left it unable to drive (set_broken()).
var _broken: Dictionary = {}


## The host's "Tow" under `parent`, hooked to `company_trips`, `company_fleet` and `company_net`'s tow requests.
static func add_to(parent: Node, company_trips: CompanyTrips, company_fleet: CompanyFleet, company_net: CompanyNet) \
		-> CompanyTow:
	var made := CompanyTow.new()
	made.name = "Tow"
	made.trips = company_trips
	made.fleet = company_fleet
	made.net = company_net
	parent.add_child(made)
	company_net.tow.handler = made.ask
	return made


func _exit_tree() -> void:
	if net != null and is_instance_valid(net) and net.tow.handler == ask:
		net.tow.handler = Callable()


## The text of the offer for the board's button: the translation of OFFER_KEY with the price.
static func offer_text() -> String:
	var text: String = TranslationServer.translate(OFFER_KEY)
	return text % CompanyTuning.TOW_COST if text.count("%") == 1 else text


## Whether a vehicle counts as stuck this tick: a driver, the pedal down, almost no speed, not in the mud. Pure.
static func counts_as_stuck(speed: float, engine_force: float, driver_peer: int, in_mud: bool) -> bool:
	return not in_mud and driver_peer != 0 and absf(engine_force) > 0.0 and speed < CompanyTuning.TOW_STUCK_SPEED


## TripTow's state of `vehicle_id`: BROKEN when set_broken() says so, STUCK once it counted TOW_STUCK_SECONDS (and
## until it really moves or its trip closes), else OK.
func vehicle_state(vehicle_id: StringName) -> StringName:
	if _broken.has(vehicle_id):
		return TripTow.VEHICLE_BROKEN
	if _latched.has(vehicle_id):
		return TripTow.VEHICLE_STUCK
	return TripTow.VEHICLE_OK


## Seconds `vehicle_id` has counted as stuck now (0 when it moves, nobody drives it or it has no trip).
func stuck_seconds(vehicle_id: StringName) -> float:
	return float(_stuck.get(vehicle_id, 0.0))


## A fault or a crash left `vehicle_id` unable to drive (or it was repaired): the tow is offered for it.
func set_broken(vehicle_id: StringName, broken: bool) -> void:
	if broken:
		_broken[vehicle_id] = true
	else:
		_broken.erase(vehicle_id)


## Host: tows `vehicle_id` home. TripTow's answer plus `reason`: &"" when it was done (the vehicle is back in the
## playon, the wallet charged, the trip closed, nobody at its wheel), else the key of the refusal (bad_data when a
## wallet that could pay did not take the event). A vehicle that is not here is WORLD_TOW_NO_TRIP, as one with no
## open trip.
func tow(vehicle_id: StringName) -> Dictionary:
	var answer: Dictionary = trips.tow(vehicle_id, vehicle_state(vehicle_id), _Wallet.new(net))
	answer["reason"] = &"" if bool(answer["ok"]) else StringName(answer["key"])
	if bool(answer["ok"]):
		_forget(vehicle_id)
		_broken.erase(vehicle_id)
		if fleet.send_home(vehicle_id):
			fleet.release_wheel(fleet.vehicle(String(vehicle_id)))
	elif answer["key"] == TripTow.NO_MONEY and net.company != null and net.company.can_afford(CompanyTuning.TOW_COST):
		answer["reason"] = CompanyTowNet.REASON_BAD_DATA
	return answer


## What CompanyNet.tow.handler calls for a request of `peer`: the refusal (NOT_YOURS when somebody else drives or
## rides in the vehicle, else tow()'s), or &"" when it was done.
func ask(peer: int, vehicle_id: StringName) -> StringName:
	var body: Node3D = fleet.vehicle(String(vehicle_id))
	if body != null and not may_ask(body, peer):
		return StringName(NOT_YOURS)
	return StringName(tow(vehicle_id)["reason"])


## Whether `peer` may ask to tow `body`: its driver, somebody riding in it, or anybody while nobody is at the wheel.
func may_ask(body: Node3D, peer: int) -> bool:
	var driver: int = int(body.get(&"driver_peer_id"))
	if driver == 0 or driver == peer:
		return true
	for seat: Node in body.find_children("*", "SeatPoint", true, false):
		var occupant: Variant = seat.get(&"occupant")
		if typeof(occupant) == TYPE_OBJECT and is_instance_valid(occupant) \
				and (occupant as Node).get_multiplayer_authority() == peer:
			return true
	return false


func _physics_process(delta: float) -> void:
	for body: Node3D in fleet.vehicles():
		var rigid := body as RigidBody3D
		if rigid != null:
			feed(StringName(body.name), rigid.linear_velocity.length(), float(body.get(&"engine_force")),
				int(body.get(&"driver_peer_id")), bool(body.get_meta(&"in_mud", false)), delta)


## One tick of `vehicle_id`'s count with what the physics reads (the tick feeds it; a test may too): a vehicle with
## no open trip counts nothing; one that counts_as_stuck() adds `delta` seconds and, at TOW_STUCK_SECONDS, latches
## STUCK; before that any other tick starts again from 0. A latched one stays STUCK, whatever the pedal or the
## driver do, until it moves faster than TOW_STUCK_SPEED for TOW_UNSTUCK_SECONDS in a row (or its trip closes).
func feed(vehicle_id: StringName, speed: float, engine_force: float, driver_peer: int, in_mud: bool,
		delta: float) -> void:
	if trips.trip_of(vehicle_id) == null:
		_forget(vehicle_id)
	elif _latched.has(vehicle_id):
		_moving[vehicle_id] = float(_moving.get(vehicle_id, 0.0)) + delta if speed > CompanyTuning.TOW_STUCK_SPEED \
			else 0.0
		if float(_moving[vehicle_id]) >= CompanyTuning.TOW_UNSTUCK_SECONDS:
			_forget(vehicle_id)
	elif counts_as_stuck(speed, engine_force, driver_peer, in_mud):
		_stuck[vehicle_id] = stuck_seconds(vehicle_id) + delta
		if stuck_seconds(vehicle_id) >= CompanyTuning.TOW_STUCK_SECONDS:
			_latched[vehicle_id] = true
	else:
		_stuck.erase(vehicle_id)


func _forget(vehicle_id: StringName) -> void:
	_stuck.erase(vehicle_id)
	_latched.erase(vehicle_id)
	_moving.erase(vehicle_id)


## The company's wallet as TripTow.tow_home() wants it (can_afford() and spend()), but the money moves as an event
## every peer applies (wallet_moved), never on the host's wallet alone.
class _Wallet extends RefCounted:
	var _net: CompanyNet

	func _init(company_net: CompanyNet) -> void:
		_net = company_net

	func can_afford(amount: int) -> bool:
		return _net.company != null and _net.company.can_afford(amount)

	func spend(amount: int, reason: StringName) -> bool:
		return amount > 0 and _net.publish_wallet(-amount, reason)
