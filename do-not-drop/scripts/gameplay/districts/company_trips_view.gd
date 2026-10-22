class_name CompanyTripsView
extends Node
## The company vehicles out of the shed as every peer sees them (expansion D-0302.2.a).
##
## CompanyTrips (host only) decides when a trip starts and closes; this node is its face on every
## peer, the host too, kept by CompanyNet events and, for a late joiner, by the snapshot (part
## SNAPSHOT_KEY). Contract: docs/expansion-distritos/diseno/red-autoridad.md, row 19. Child of the
## company world on every peer (CompanyRoot, named "TripsView"); like DayCycle it is hooked to its
## peer's CompanyNet before the world is up (attach()). On the host it listens to CompanyTrips
## (follow()) and publishes each fact as a host event (CompanyNet.publish(): its own rule, no client
## asks for it), applied here first and then on every ready peer, in seq order with the rest:
##   trip_started  {trip, vehicle, orders, boxes, minute}  a vehicle with cargo crossed the gate out
##   trip_refused  {vehicle, minute}                       one crossed out with VEHICLES_FAR_MAX out:
##                                                         no trip starts, but it counts as out
##   trip_closed   {trip, vehicle, failed, minute}         it crossed back in. `trip` is "" (and
##                                                         `failed` empty) for one out refused
## Ids are text up to MAX_ID_LENGTH, `orders`, `boxes` and `failed` lists of them (up to MAX_ITEMS;
## a trip has at least one order), `minute` the host's game minute as an int (0..GameClock's
## MAX_MINUTE). Every peer applies them in apply_trip() with the same code (rule 6: no game rule is
## checked again, only that the data fits, rule 5, and that the vehicle is in or out as the event
## says); a peer whose view doesn't take one waits for a snapshot (CompanyNet._receive()).
##
## Only what is out lives here: a vehicle back is forgotten. Nothing here moves an order: the
## OrderBook stays the host's (CompanyTrips.book until D-0801) and orders are only ids. Reads, on any
## peer: vehicles_out() (in the order they left), trips_out() (what a client's DayCycle.trips_out
## reads; the host's reads CompanyTrips, the authority), is_out() and trip_of() (a vehicle's entry,
## in trip_started's shape). `changed` fires after every trip event applied here and after a
## snapshot (company_state_restored), once CompanyNet is done applying it, so a listener may request
## or publish; trip_closed only for a trip (not for a refused vehicle back), with what failed. A HUD
## listens to those two. Without a CompanyNet (attach() not called) the host's facts apply here at
## once. It names no autoload (lesson N-919).

## After every trip event applied here and after a snapshot: redraw from vehicles_out()/trip_of().
signal changed
## A trip came back (every peer, after the event): the orders of it that were not delivered.
signal trip_closed(trip_id: StringName, vehicle_id: StringName, failed: Array[StringName])

## The event kinds (CompanyNet takes them in its EVENT_KINDS and HOST_EVENT_KINDS).
const STARTED: StringName = &"trip_started"
const REFUSED: StringName = &"trip_refused"
const CLOSED: StringName = &"trip_closed"
const EVENT_KINDS: Array[StringName] = [STARTED, REFUSED, CLOSED]
## Key of the trips out in CompanyNet's snapshot (add_snapshot_part()): a list of entries in
## trip_started's shape, refused ones with trip "" and no orders or boxes.
const SNAPSHOT_KEY: String = "trips"
## Most vehicles a snapshot may carry out at once (rule 5): VEHICLES_FAR_MAX trips plus every
## refused vehicle, far over any fleet.
const MAX_OUT: int = 32
## Most orders, boxes or failed orders an event or an entry may carry.
const MAX_ITEMS: int = 64
const MAX_ID_LENGTH: int = RpcGuard.MAX_TEXT_LENGTH
const STARTED_KEYS: Array[String] = ["trip", "vehicle", "orders", "boxes", "minute"]
const REFUSED_KEYS: Array[String] = ["vehicle", "minute"]
const CLOSED_KEYS: Array[String] = ["trip", "vehicle", "failed", "minute"]

## The CompanyNet the trips travel through (attach()), or null: this peer's view alone.
var net: CompanyNet = null

## Host: the CompanyTrips followed (follow()), for the minute of a refusal.
var _source: CompanyTrips = null
## vehicle id -> {trip, vehicle, orders, boxes, minute}, in the order they left.
var _out: Dictionary = {}
## Applied here and not told yet: [trip, vehicle, failed] per trip closed, and whether anything
## changed. Flushed on event_applied (_on_event_applied()).
var _pending_closed: Array = []
var _dirty: bool = false


## Leaving the world, the view unhooks from its CompanyNet: no trip event lands here any more and
## snapshots go without its part (a client keeps what it had). attach() hooks it back.
func _exit_tree() -> void:
	if _has_net() and net.trips_view == self:
		net.trips_view = null
		net.remove_snapshot_part(SNAPSHOT_KEY)
		if net.event_applied.is_connected(_on_event_applied):
			net.event_applied.disconnect(_on_event_applied)
		if net.company_state_restored.is_connected(_on_restored):
			net.company_state_restored.disconnect(_on_restored)
	net = null


## Hooks this view to `company_net` on every peer before its world is up (like any snapshot part):
## the trip events land in apply_trip() and the snapshot carries the trips out. False, changing
## nothing, without a CompanyNet or when it already has a trips part.
func attach(company_net: CompanyNet) -> bool:
	if company_net == null:
		return false
	if not company_net.add_snapshot_part(SNAPSHOT_KEY, _take_snapshot_part, _put_snapshot_part):
		return false
	net = company_net
	company_net.trips_view = self
	company_net.event_applied.connect(_on_event_applied)
	company_net.company_state_restored.connect(_on_restored)
	return true


## Host: publishes what `trips` decides from now on, one event per fact (trips out before this
## call are not sent: follow it before any vehicle moves, as CompanyRoot does).
func follow(trips: CompanyTrips) -> void:
	if trips == null:
		return
	_source = trips
	var hooks: Dictionary = {
		&"trip_started": _on_trip_started, &"trip_closed": _on_trip_closed,
		&"departure_refused": _on_departure_refused, &"refused_returned": _on_refused_returned,
	}
	for hook: StringName in hooks:
		if not trips.is_connected(hook, hooks[hook]):
			trips.connect(hook, hooks[hook])


## True where the trips are decided: the host (solo too), or this peer when it has no CompanyNet.
func is_host() -> bool:
	return net.is_host() if _has_net() else true


## Vehicles out (with a trip or refused), in the order they left.
func vehicles_out() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_out.keys())
	return ids


## How many vehicles are out: those with a trip and those that left refused (CompanyTrips' count).
func trips_out() -> int:
	return _out.size()


func is_out(vehicle_id: StringName) -> bool:
	return _out.has(vehicle_id)


## `vehicle_id`'s entry while it is out, a copy: {trip, vehicle, orders, boxes, minute} (trip "" and
## no orders or boxes when it left refused). {} when it is in.
func trip_of(vehicle_id: StringName) -> Dictionary:
	var entry: Dictionary = _out.get(vehicle_id, {})
	return entry.duplicate(true)


## Every peer, the host too: a trip event (CompanyNet._apply_state()). Checked like any data from
## the network (rule 5: exactly the kind's keys, ids, bounded lists, the minute in range) and
## against what is out here (a vehicle starts or is refused only while in, closes only while out
## with that trip). False, changing nothing, when it doesn't fit. The signals wait for
## event_applied (_on_event_applied()).
func apply_trip(kind: StringName, data: Dictionary) -> bool:
	var vehicle: StringName = &""
	match kind:
		STARTED, REFUSED:
			var entry: Dictionary = (
				_entry_from(data, false) if kind == STARTED else _refused_from(data)
			)
			if entry.is_empty() or _out.has(entry["vehicle"]) or _out.size() >= MAX_OUT:
				return false
			vehicle = entry["vehicle"]
			_out[vehicle] = entry
		CLOSED:
			if not _keys_ok(data, CLOSED_KEYS) or not _id_ok(data["vehicle"]):
				return false
			vehicle = StringName(data["vehicle"])
			var trip: Variant = data["trip"]
			var entry: Dictionary = _out.get(vehicle, {})
			if not _text_ok(trip) or entry.is_empty() or entry["trip"] != StringName(trip):
				return false
			var failed: Variant = data["failed"]
			var most_failed: int = MAX_ITEMS if entry["trip"] != &"" else 0
			if not _ids_ok(failed, 0, most_failed) or not _minute_ok(data["minute"]):
				return false
			_out.erase(vehicle)
			if entry["trip"] != &"":
				_pending_closed.append([entry["trip"], vehicle, _ids(failed)])
		_:
			return false
	_dirty = true
	if not _has_net():
		_flush()
	return true


## Host: `trip` started (CompanyTrips.trip_started).
func _on_trip_started(trip: Trip) -> void:
	_publish(STARTED, {
		"trip": trip.id, "vehicle": trip.vehicle_id, "orders": trip.order_ids.duplicate(),
		"boxes": trip.box_ids.duplicate(), "minute": _wire_minute(trip.depart_min),
	})


## Host: `trip` came back with `failed` (CompanyTrips.trip_closed).
func _on_trip_closed(trip: Trip, failed: Array[StringName]) -> void:
	_publish(CLOSED, {
		"trip": trip.id, "vehicle": trip.vehicle_id, "failed": failed.duplicate(),
		"minute": _wire_minute(trip.return_min),
	})


## Host: `vehicle_id` left while VEHICLES_FAR_MAX were out (CompanyTrips.departure_refused). The
## reason is always the cap (CompanyTrips.FAR_LIMIT): a peer that shows it reads it from there.
func _on_departure_refused(vehicle_id: StringName, _reason: Dictionary) -> void:
	_publish(REFUSED, {"vehicle": vehicle_id, "minute": _source_minute()})


## Host: a vehicle out refused is back (CompanyTrips.refused_returned): trip_closed with no trip.
func _on_refused_returned(vehicle_id: StringName) -> void:
	var none: Array[StringName] = []
	_publish(CLOSED, {
		"trip": &"", "vehicle": vehicle_id, "failed": none, "minute": _source_minute(),
	})


## Host: the event goes through CompanyNet, which applies it here too (apply_trip()), or without one
## applies here at once. CompanyNet logs an event it could not publish; the host's view then lags
## CompanyTrips (which still decides the day) until the next fact that fits.
func _publish(kind: StringName, data: Dictionary) -> bool:
	if not is_host():
		return false
	return net.publish(kind, data) if _has_net() else apply_trip(kind, data)


## Every peer: the trips the last events changed are told now that CompanyNet is not applying.
func _on_event_applied(_seq: int, kind: StringName, _data: Dictionary) -> void:
	if EVENT_KINDS.has(kind):
		_flush()


## Every peer but the host: a snapshot replaced the trips out (no trip_closed for what it skipped).
func _on_restored(_snapshot_seq: int) -> void:
	_pending_closed.clear()
	_dirty = false
	changed.emit()


func _flush() -> void:
	var closed: Array = _pending_closed
	_pending_closed = []
	var was_dirty: bool = _dirty
	_dirty = false
	for fact: Array in closed:
		trip_closed.emit(fact[0], fact[1], fact[2])
	if was_dirty:
		changed.emit()


## Host: the trips out a snapshot carries, in the order they left.
func _take_snapshot_part() -> Variant:
	var entries: Array = []
	for vehicle: StringName in _out:
		entries.append((_out[vehicle] as Dictionary).duplicate(true))
	return entries


## Client: the snapshot's trips out in place of the ones here, without a signal (`changed` comes
## with company_state_restored). False when it is not a list of up to MAX_OUT entries, each one
## fitting, every vehicle once.
func _put_snapshot_part(value: Variant) -> bool:
	if not value is Array or (value as Array).size() > MAX_OUT:
		return false
	var got: Dictionary = {}
	for raw: Variant in value:
		var entry: Dictionary = _entry_from(raw, true)
		if entry.is_empty() or got.has(entry["vehicle"]):
			return false
		got[entry["vehicle"]] = entry
	_out = got
	_pending_closed.clear()
	_dirty = false
	return true


## A trip_started (or, with `allow_refused`, a snapshot entry, which may be refused: trip "" with
## no orders or boxes) as a typed entry, or {} when it isn't exactly what the host writes.
static func _entry_from(raw: Variant, allow_refused: bool) -> Dictionary:
	if not raw is Dictionary or not _keys_ok(raw, STARTED_KEYS):
		return {}
	var data: Dictionary = raw
	if not _id_ok(data["vehicle"]) or not _text_ok(data["trip"]) or not _minute_ok(data["minute"]):
		return {}
	var refused: bool = String(data["trip"]).is_empty()
	if refused and not allow_refused:
		return {}
	var most: int = 0 if refused else MAX_ITEMS
	if not _ids_ok(data["orders"], 0 if refused else 1, most) or not _ids_ok(data["boxes"], 0, most):
		return {}
	return {
		"trip": StringName(data["trip"]), "vehicle": StringName(data["vehicle"]),
		"orders": _ids(data["orders"]), "boxes": _ids(data["boxes"]), "minute": int(data["minute"]),
	}


## A trip_refused as an entry with no trip, or {}.
static func _refused_from(raw: Dictionary) -> Dictionary:
	if not _keys_ok(raw, REFUSED_KEYS) or not _id_ok(raw["vehicle"]) or not _minute_ok(raw["minute"]):
		return {}
	var none: Array[StringName] = []
	return {
		"trip": &"", "vehicle": StringName(raw["vehicle"]), "orders": none, "boxes": none.duplicate(),
		"minute": int(raw["minute"]),
	}


## `data` has exactly `keys`.
static func _keys_ok(data: Dictionary, keys: Array[String]) -> bool:
	if data.size() != keys.size():
		return false
	for key: String in keys:
		if not data.has(key):
			return false
	return true


## A list of `at_least`..`most` ids.
static func _ids_ok(value: Variant, at_least: int, most: int) -> bool:
	if not value is Array:
		return false
	var list: Array = value
	if list.size() < at_least or list.size() > most:
		return false
	for id: Variant in list:
		if not _id_ok(id):
			return false
	return true


## A list _ids_ok() let through, typed and copied.
static func _ids(list: Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: Variant in list:
		ids.append(StringName(id))
	return ids


## Text up to MAX_ID_LENGTH, possibly empty.
static func _text_ok(value: Variant) -> bool:
	return CompanyAsk.is_id(value) and String(value).length() <= MAX_ID_LENGTH


## Text up to MAX_ID_LENGTH, not empty.
static func _id_ok(value: Variant) -> bool:
	return _text_ok(value) and not String(value).is_empty()


## A game minute as the host writes it: an int from 0 to GameClock.MAX_MINUTE.
static func _minute_ok(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= int(GameClock.MAX_MINUTE)


## Host: a minute as it travels (a trip's times are -1 until set; a clock left running is held).
static func _wire_minute(minute: int) -> int:
	return clampi(minute, 0, int(GameClock.MAX_MINUTE))


func _source_minute() -> int:
	return _wire_minute(_source.minute() if _source != null and is_instance_valid(_source) else 0)


func _has_net() -> bool:
	return net != null and is_instance_valid(net)
