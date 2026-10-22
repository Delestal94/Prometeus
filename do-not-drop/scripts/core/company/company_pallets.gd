class_name CompanyPallets
extends RefCounted
## The supplier pallets and the pallet jack as the host decides them and every peer keeps them (expansion
## D-0605.b).
##
## The company has one pallet jack and one book of pallets (PalletJack: on the truck's bed, on the jack, on the
## floor). The units of a pallet go into the Inventory once, when it first stands on the floor (PalletJack
## does it); here is what the Inventory cannot say: where each pallet is and where the jack stands. A player
## works the jack with three requests, checked by the host at the station `jack` (CompanyNet: reach to the
## jack, like any units request) and answered with one event each, applied the same on every peer (rule 6:
## nothing is checked again, only that the data fits):
##   jack_pick {pallet}  -> jack_picked {pallet}     a pallet of the bed or the floor goes on the jack
##   jack_put {}         -> jack_placed {pallet, pos} the carried pallet stands on the floor, at the jack
##   jack_push {dir}     -> jack_moved {pos}          the jack rolls CompanyTuning.JACK_PUSH_STEP_M along `dir`
## and two events nobody asks for, published by the host when the day's truck comes and when it leaves
## (CompanyNet.publish):
##   jack_loaded {day, pallets}  the pallets on the truck's bed (what stayed on the bed of an older truck left
##   with it: PalletJack.left_on_bed). `pos` is in the shed's own frame (X east, Z south), in metres.
##   jack_departed {day, lines}  the truck drove off (D-0618.b): what was still on its bed goes with it, and the
##   delivery note (D-0614.b, `note`) keeps `lines`, the lines of the day that did not come out even.
##
## What only the shed knows, the station gives: "at" (Vector2, where the jack stands now), "floor" (Rect2, the
## floor in metres), "stand_ok" and "free_ok" (Callable(Vector2) -> bool: the jack may stand there / a pallet may
## lie there), "bed_open" (the truck is parked) and "bed_at" (Vector2, the bed's rear). The book travels in every
## snapshot under SNAPSHOT_KEY. No node and no autoload here.

const PICK: StringName = &"jack_pick"
const PUT: StringName = &"jack_put"
const PUSH: StringName = &"jack_push"
const PICKED: StringName = &"jack_picked"
const PLACED: StringName = &"jack_placed"
const MOVED: StringName = &"jack_moved"
const LOADED: StringName = &"jack_loaded"
const DEPARTED: StringName = &"jack_departed"
const REQUEST_KINDS: Array[StringName] = [PICK, PUT, PUSH]
const EVENT_KINDS: Array[StringName] = [PICKED, PLACED, MOVED, LOADED, DEPARTED]
## The station every request of the jack names: CompanyNet resolves it through its `stations`.
const STATION: StringName = &"jack"
const SNAPSHOT_KEY: String = "pallets"
## Pallets a company's book holds (a snapshot or an event past this is refused).
const MAX_PALLETS: int = 200
const MAX_ID_LENGTH: int = 48
## Lines of one departure's delivery note (a product each) and the biggest count in one (more is refused).
const MAX_NOTE_LINES: int = 64
const MAX_NOTE_UNITS: int = 100000

const REASON_BAD_DATA: StringName = &"bad_data"
const REASON_NO_STATION: StringName = &"no_station"
const REASON_NO_PALLET: StringName = &"no_pallet"
const REASON_JACK_FULL: StringName = &"jack_full"
const REASON_JACK_EMPTY: StringName = &"jack_empty"
const REASON_TRUCK_AWAY: StringName = &"truck_away"
const REASON_UNREACHABLE: StringName = &"unreachable"
const REASON_NO_ROOM: StringName = &"no_room"
const REASON_BLOCKED: StringName = &"blocked"

## Where an event puts a pallet down: any point (the host checked the floor; apply() only checks the data).
const _ANYWHERE: Rect2 = Rect2(-RpcGuard.MAX_COORDINATE, -RpcGuard.MAX_COORDINATE, RpcGuard.MAX_COORDINATE * 2.0,
	RpcGuard.MAX_COORDINATE * 2.0)
const _PLACES: Array[StringName] = [PalletJack.AT_BED, PalletJack.AT_JACK, PalletJack.AT_FLOOR, PalletJack.AT_RACK]

## The pallets and the jack's load.
var book: PalletJack = PalletJack.new()
## Where the jack stands once it was pushed (Vector2, shed frame, metres); null while it never was: the shed
## stands it at its home, by the dock.
var jack_at: Variant = null
## The last day whose truck brought its pallets (jack_loaded), 0 for none.
var loaded_day: int = 0
## The delivery note (D-0614.b): per day, what the truck did not bring or brought extra. It travels in the snapshot.
var note: DeliveryNote = DeliveryNote.new()
## The last day whose truck drove off (jack_departed), 0 for none.
var departed_day: int = 0


## A pallet or jack id that came over the network: letters, digits, '_' and '-', at most MAX_ID_LENGTH long.
static func id_ok(value: Variant) -> bool:
	if not CompanyAsk.is_id(value):
		return false
	var text: String = String(value)
	if text.is_empty() or text.length() > MAX_ID_LENGTH:
		return false
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		var plain: bool = (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57)
		if not (plain or code == 95 or code == 45):
			return false
	return true


static func _point_ok(value: Variant) -> bool:
	return value is Vector2 and RpcGuard.finite_vec3(Vector3((value as Vector2).x, 0.0, (value as Vector2).y))


## {pallet} of a jack_pick request, the id of one pallet; {} otherwise.
static func pick_ask(data: Dictionary) -> Dictionary:
	var pallet: Variant = data.get("pallet")
	return {"pallet": StringName(pallet)} if id_ok(pallet) else {}


## {dir} of a jack_push request, a finite Vector2 (x, z) that is not zero; {} otherwise.
static func push_ask(data: Dictionary) -> Dictionary:
	var dir: Variant = data.get("dir")
	if not _point_ok(dir) or (dir as Vector2).length() < 0.001:
		return {}
	return {"dir": dir}


## Whether the truck of `day` should have its pallets on the bed at game `minute`: it has a delivery and is on its
## way in (SupplierTruckView draws it from CompanyTuning.SUPPLIER_DRIVE_IN_MIN before it parks) or waiting; not
## once it left.
static func load_due(schedule: SupplierSchedule, day: int, minute: int) -> bool:
	var first: int = SupplierSchedule.arrival_minute() - int(CompanyTuning.SUPPLIER_DRIVE_IN_MIN)
	return schedule.has_delivery(day) and minute >= first and minute < SupplierSchedule.departure_minute()


## A jack_loaded event for `day` from the truck's `pallets` (Pallet dictionaries): the ones apply() takes
## (_pallet_of), not in the book already, whose units are not in `stock` yet (the first truck's pallets start in the
## shed, DefaultShed), as many as the book has room for (a warning for the rest). {} when nothing would load.
func loaded_event(day: int, planned: Array[Dictionary], stock: Inventory) -> Dictionary:
	var room: int = MAX_PALLETS - book.places.size() + book.ids_at(PalletJack.AT_BED).size()
	var found: Array = []
	var left_out: int = 0
	for planned_pallet: Dictionary in planned:
		var pallet: Dictionary = _pallet_of(planned_pallet)
		if pallet.is_empty() or book.places.has(pallet["id"]):
			continue
		if not stock.contents_at(Pallet.location(pallet["id"])).is_empty():
			continue
		if found.size() >= room:
			left_out += 1
			continue
		found.append({"id": String(pallet["id"]), "product": String(pallet["product"]), "qty": int(pallet["qty"])})
	if left_out > 0:
		push_warning("CompanyPallets: the book is full (%d pallets); %d of day %d's truck stay off its bed"
			% [MAX_PALLETS, left_out, day])
	return {} if found.is_empty() else {"day": day, "pallets": found}


## Host: the jack_departed event for `day` once its truck has left at `minute` (SupplierDeparture), or {}: no delivery
## that day, or the truck is still there. The pallets of `planned` that are not on the bed (on the floor, on the jack,
## in a rack, or the shed's first ones, which never were) count as unloaded. `schedule` is not touched (the truck
## keeps showing as left); `departed_day` stops a second departure of the same day, and a refused publish asks again.
## `lines` is the whole comparison of the order against what was unloaded, exact or not.
func departed_event(schedule: SupplierSchedule, day: int, minute: int, planned: Array[Dictionary]) -> Dictionary:
	if day <= departed_day or not schedule.has_delivery(day):
		return {}
	var on_bed: Array[StringName] = book.ids_at(PalletJack.AT_BED)
	var unloaded: Array = []
	for pallet: Dictionary in planned:
		if not on_bed.has(StringName(pallet.get("id", &""))):
			unloaded.append(pallet.get("id", &""))
	var scratch: SupplierSchedule = SupplierSchedule.from_dict(schedule.to_dict())
	var result: Dictionary = SupplierDeparture.resolve(scratch, day, minute, planned, unloaded)
	if not bool(result["left"]):
		return {}
	var lines: Array = []
	for line: Dictionary in result["note_lines"]:
		lines.append({"product": String(line["product"]), "ordered": int(line["ordered"]),
			"received": int(line["received"])})
	return {"day": day, "lines": lines}


## Host, once a game minute: publish jack_departed (through `publish`, CompanyNet.publish) when the truck of `day`
## drove off at `minute`; the check is made every minute and departed_event() answers {} until it is due.
static func send_truck_off(pallets: CompanyPallets, schedule: SupplierSchedule, day: int, minute: int,
		publish: Callable) -> void:
	if not schedule.has_delivery(day):
		return
	var event: Dictionary = pallets.departed_event(schedule, day, minute, schedule.pallets_for(day))
	if not event.is_empty():
		publish.call(DEPARTED, event)


## Host: the event a request asks for at `station`, or its refusal: {reason: &"", kind, data} or {reason}.
func check(kind: StringName, data: Dictionary, station: Dictionary) -> Dictionary:
	var at: Variant = station.get("at")
	if not _point_ok(at):
		return {"reason": REASON_NO_STATION}
	match kind:
		PICK:
			return _check_pick(pick_ask(data), at, station)
		PUT:
			return _check_put(at, station)
		PUSH:
			return _check_push(push_ask(data), at, station)
	return {"reason": REASON_BAD_DATA}


func _check_pick(ask: Dictionary, at: Vector2, station: Dictionary) -> Dictionary:
	if ask.is_empty():
		return {"reason": REASON_BAD_DATA}
	var id: StringName = ask["pallet"]
	if book.carrying != &"":
		return {"reason": REASON_JACK_FULL}
	if not book.places.has(id):
		return {"reason": REASON_NO_PALLET}
	match book.places[id]["at"]:
		PalletJack.AT_BED:
			var rear: Variant = station.get("bed_at")
			if not bool(station.get("bed_open")) or not _point_ok(rear):
				return {"reason": REASON_TRUCK_AWAY}
			if at.distance_to(rear) > CompanyTuning.PALLET_JACK_REACH_M:
				return {"reason": REASON_UNREACHABLE}
		PalletJack.AT_FLOOR:
			if not book.can_pick_up(id, at):
				return {"reason": REASON_UNREACHABLE}
		_:
			return {"reason": REASON_NO_PALLET}
	return {"reason": &"", "kind": PICKED, "data": {"pallet": id}}


func _check_put(at: Vector2, station: Dictionary) -> Dictionary:
	if book.carrying == &"":
		return {"reason": REASON_JACK_EMPTY}
	var floor_rect: Variant = station.get("floor")
	var free: Variant = station.get("free_ok")
	if not floor_rect is Rect2 or not book.can_put_down(at, floor_rect):
		return {"reason": REASON_NO_ROOM}
	if free is Callable and not bool((free as Callable).call(at)):
		return {"reason": REASON_NO_ROOM}
	return {"reason": &"", "kind": PLACED, "data": {"pallet": book.carrying, "pos": at}}


func _check_push(ask: Dictionary, at: Vector2, station: Dictionary) -> Dictionary:
	if ask.is_empty():
		return {"reason": REASON_BAD_DATA}
	var stand: Variant = station.get("stand_ok")
	if not (stand is Callable and (stand as Callable).is_valid()):
		return {"reason": REASON_NO_STATION}
	var to: Vector2 = at + (ask["dir"] as Vector2).normalized() * CompanyTuning.JACK_PUSH_STEP_M
	if not bool((stand as Callable).call(to)):
		return {"reason": REASON_BLOCKED}
	return {"reason": &"", "kind": MOVED, "data": {"pos": to}}


## Every peer: applies one of EVENT_KINDS. False, changing nothing, when the data does not fit this book.
func apply(inventory: Inventory, kind: StringName, data: Dictionary) -> bool:
	match kind:
		PICKED:
			var id: Variant = data.get("pallet")
			if not id_ok(id) or not book.places.has(StringName(id)):
				return false
			# Reach was the host's check: the holder is taken to stand at the pallet.
			return book.pick_up(StringName(id), (book.places[StringName(id)] as Dictionary).get("pos", Vector2.ZERO))
		PLACED:
			var pallet: Variant = data.get("pallet")
			if not (id_ok(pallet) and _point_ok(data.get("pos")) and StringName(pallet) == book.carrying):
				return false
			return book.put_down(data["pos"], _ANYWHERE, inventory)
		MOVED:
			if not _point_ok(data.get("pos")):
				return false
			jack_at = data["pos"]
			return true
		LOADED, DEPARTED:
			return _apply_loaded(data) if kind == LOADED else _apply_departed(data)
	return false


func _apply_loaded(data: Dictionary) -> bool:
	var day: Variant = data.get("day")
	var raw: Variant = data.get("pallets")
	if typeof(day) != TYPE_INT or not raw is Array or (raw as Array).size() > MAX_PALLETS:
		return false
	var fresh: Array[Dictionary] = []
	for entry: Variant in raw:
		var pallet: Dictionary = _pallet_of(entry)
		if pallet.is_empty():
			return false
		fresh.append(pallet)
	var stale: Array[StringName] = book.ids_at(PalletJack.AT_BED)
	if book.places.size() - stale.size() + fresh.size() > MAX_PALLETS:
		return false
	for id: StringName in stale:
		book.remove(id)
	book.load_bed(fresh)
	loaded_day = int(day)
	return true


## The truck left: what is still on its bed goes with it and the note keeps the day's lines. The lines are checked
## first; nothing changes when they do not fit.
func _apply_departed(data: Dictionary) -> bool:
	var day: Variant = data.get("day")
	var raw: Variant = data.get("lines")
	var many: bool = raw is Array and (raw as Array).size() > MAX_NOTE_LINES
	if typeof(day) != TYPE_INT or int(day) <= departed_day or not raw is Array or many:
		return false
	var ordered: Dictionary = {}
	var received: Dictionary = {}
	for entry: Variant in raw:
		if not entry is Dictionary:
			return false
		var line: Dictionary = entry
		var product: Variant = line.get("product")
		var want: Variant = line.get("ordered")
		var got: Variant = line.get("received")
		var name_ok: bool = CompanyAsk.is_id(product) and not String(product).is_empty()
		if not (name_ok and String(product).length() <= MAX_ID_LENGTH
			and typeof(want) == TYPE_INT and typeof(got) == TYPE_INT):
			return false
		if int(want) < 0 or int(want) > MAX_NOTE_UNITS or int(got) < 0 or int(got) > MAX_NOTE_UNITS:
			return false
		ordered[StringName(product)] = int(want)
		received[StringName(product)] = int(got)
	for id: StringName in book.ids_at(PalletJack.AT_BED):
		book.remove(id)
	note.check(int(day), ordered, received)
	departed_day = int(day)
	return true


## A sealed pallet from {id, product, qty} as it came over the network ({} when it does not fit).
static func _pallet_of(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var plain: Dictionary = entry
	var qty: Variant = plain.get("qty")
	if not (id_ok(plain.get("id")) and CompanyAsk.is_id(plain.get("product")) and typeof(qty) == TYPE_INT):
		return {}
	if String(plain["product"]).is_empty() or String(plain["product"]).length() > MAX_ID_LENGTH:
		return {}
	var made: Dictionary = Pallet.make(StringName(plain["id"]), StringName(plain["product"]), int(qty))
	if made.is_empty():
		return {}
	var state: Variant = plain.get("state", Pallet.STATE_SEALED)
	if CompanyAsk.is_id(state) and StringName(state) == Pallet.STATE_OPEN:
		made["state"] = Pallet.STATE_OPEN
	return made


## The snapshot part: {book: PalletJack.to_dict(), jack_at, loaded_day, departed_day, note: DeliveryNote.to_dict()}.
func to_dict() -> Dictionary:
	return {"book": book.to_dict(), "jack_at": jack_at, "loaded_day": loaded_day, "departed_day": departed_day,
		"note": note.to_dict()}


## Client: the host's part in place of what is here. False, changing nothing, when it does not fit.
func put_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var plain: Dictionary = value
	var at: Variant = plain.get("jack_at")
	var day: Variant = plain.get("loaded_day")
	var parsed: Variant = _parse_book(plain.get("book"))
	if parsed == null or typeof(day) != TYPE_INT or not (at == null or _point_ok(at)):
		return false
	var left_on: Variant = plain.get("departed_day", 0)
	var kept: Variant = plain.get("note", {})
	if typeof(left_on) != TYPE_INT or int(left_on) < 0 or not kept is Dictionary:
		return false
	book.from_dict(parsed)
	jack_at = at
	loaded_day = int(day)
	departed_day = int(left_on)
	note = DeliveryNote.from_dict(kept)
	return true


## `raw` (PalletJack.to_dict() form) with every field checked and rebuilt from plain values, or null.
static func _parse_book(raw: Variant) -> Variant:
	if not raw is Dictionary:
		return null
	var places: Variant = (raw as Dictionary).get("places")
	var carrying: Variant = (raw as Dictionary).get("carrying")
	if not places is Dictionary or (places as Dictionary).size() > MAX_PALLETS:
		return null
	if not CompanyAsk.is_id(carrying) or (String(carrying) != "" and not id_ok(carrying)):
		return null
	var clean: Dictionary = {}
	var on_jack: int = 0
	for key: Variant in places:
		var place: Variant = (places as Dictionary)[key]
		if not (id_ok(key) and place is Dictionary):
			return null
		var entry: Dictionary = _place_of(place)
		if entry.is_empty() or String(entry["pallet"]["id"]) != String(key):
			return null
		if entry["at"] == String(PalletJack.AT_JACK):
			on_jack += 1
			if StringName(carrying) != StringName(key):
				return null
		clean[String(key)] = entry
	if on_jack != (0 if String(carrying) == "" else 1):
		return null
	return {"places": clean, "carrying": String(carrying)}


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


## One place of a book as a snapshot carries it, in PalletJack.to_dict() form; {} when it does not fit.
static func _place_of(place: Dictionary) -> Dictionary:
	var pallet: Dictionary = _pallet_of(place.get("pallet"))
	var at: Variant = place.get("at")
	var received: Variant = place.get("received", false)
	if pallet.is_empty() or not received is bool or not CompanyAsk.is_id(at) or not _PLACES.has(StringName(at)):
		return {}
	var entry: Dictionary = {"pallet": pallet, "at": String(at), "received": received}
	if StringName(at) == PalletJack.AT_FLOOR or StringName(at) == PalletJack.AT_RACK:
		var xy: Variant = place.get("pos")
		if not (xy is Array and (xy as Array).size() == 2):
			return {}
		var x: Variant = (xy as Array)[0]
		var y: Variant = (xy as Array)[1]
		if not (_is_number(x) and _is_number(y) and _point_ok(Vector2(float(x), float(y)))):
			return {}
		entry["pos"] = [float(x), float(y)]
	if StringName(at) == PalletJack.AT_RACK:
		if not id_ok(place.get("slot")):
			return {}
		entry["slot"] = String(place["slot"])
	return entry
