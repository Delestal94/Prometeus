class_name CompanyForklift
extends RefCounted
## The forklift a player drives in the shed, as the host decides it and every peer keeps it (expansion D-0606.b).
##
## One forklift per company, with the book of pallets it shares with the pallet jack (PalletJack through
## CompanyPallets): who drives it, where it stands when nobody does, the height of its forks and whether the pallet
## the book says is carried is on its forks. The rules of taking and leaving a pallet are PalletForklift's (level of
## the forks, reach); here is the world around them. While somebody drives, the forklift is where their player is
## (every peer draws it there from the player's own replicated pose, so nothing travels per frame); the host
## judges a request by where the shed says the driver stands (station "body" and "yaw").
##
## One request, fork_act {act, ...}, checked by the host at the station `forklift` (CompanyPallets.check() hands it
## here), answered with one event each, applied the same on every peer:
##   board           -> fork_state {driver: the requester, ...}   the forklift is free, the requester's hands too
##   leave           -> fork_state {driver: 0, at: where it stands}   on the floor, where the forklift may stand
##   mast {dir[, at_height]} -> fork_state {dir: -1, 0 or 1, height}  the forks rise, stop or sink; refused
##                      (no_change) when it would change nothing (up at the top, down at the floor, stop when still)
##   work            -> jack_picked {pallet, by} / jack_placed {pallet, pos[, slot]}   take the pallet in front of
##                      the forks or leave the carried one, on the floor or a rack slot at the forks' level
## and one event nobody asks for, the host's when the driver left (let_go(), CompanyNet on peer_removed /
## peer_disconnected, with the leaver's player still there): fork_state {driver: 0}.
## fork_state always carries {driver, at (Vector2, shed frame, metres), yaw, dir, height} and a peer takes it as it is.
##
## The forks move by time: the host says "up" and every peer integrates from its own clock. A mast request moves the
## forks at most FORKLIFT_MAST_BURST_S (the driver asks again while the key is held), and each event carries the
## host's height, so what a peer drew is put right at every event. A stop carries the height the driver drew
## (`at_height`), taken within what the forks cover in the driver's round trip (stop_height()), so the forks stay
## where the driver let go of the key. The station gives: "peer" (the requester), "hands_free" (bool: no units in
## its hands, no box) and "lag" (its round trip, s), the three added by CompanyNet (CompanyPallets.check_for()),
## "body" and "yaw" (Vector2 / float: where the forklift stands now), "racks" (Array of {slot, pos, level}), "floor",
## "stand_ok", "free_ok", "bed_open" and "bed_at" (as the jack's, CompanyPallets). No node and no autoload.

const ACT_BOARD: StringName = &"board"
const ACT_LEAVE: StringName = &"leave"
const ACT_MAST: StringName = &"mast"
const ACT_WORK: StringName = &"work"
const ACTS: Array[StringName] = [ACT_BOARD, ACT_LEAVE, ACT_MAST, ACT_WORK]
## `by` of a jack_picked the forklift made.
const BY: StringName = &"forklift"

const REASON_BAD_DATA: StringName = &"bad_data"
const REASON_NO_STATION: StringName = &"no_station"
const REASON_TAKEN: StringName = &"taken"
const REASON_NOT_DRIVER: StringName = &"not_driver"
const REASON_JACK_FULL: StringName = &"jack_full"
const REASON_NO_PALLET: StringName = &"no_pallet"
const REASON_NO_ROOM: StringName = &"no_room"
const REASON_NO_RACK: StringName = &"no_rack"
const REASON_TRUCK_AWAY: StringName = &"truck_away"
const REASON_HANDS_BUSY: StringName = &"hands_busy"
## A mast request that would change nothing (the forks at the end they are asked to go to, a stop with them still).
const REASON_NO_CHANGE: StringName = &"no_change"

## How close to an end of the mast the forks count as there (m), and the slack a stop's `at_height` gets on top of
## what the forks cover in the driver's round trip (s).
const END_M: float = 0.001
const STOP_SLACK_S: float = 0.1

## Who drives it (a peer id), 0 when nobody does.
var driver: int = 0
## Where it stands (shed frame, metres) and which way it faces, as of the last event; null: at its home.
var at: Variant = null
var yaw: float = 0.0
## -1, 0 or 1: the forks sink, rest or rise, from the height in `mast` at `since_msec`.
var mast_dir: int = 0
var mast: PalletForklift = PalletForklift.new()
var since_msec: int = 0
## Whether the pallet the book says is carried is on the forks (and not on the jack).
var holds: bool = false

var _probe: PalletForklift = PalletForklift.new()


## Where the middle of a pallet on the forks lies for a forklift at `body` facing `yaw` (the heading of Node3D
## rotation.y: it faces -Z at 0).
static func tip_of(body: Vector2, heading: float) -> Vector2:
	return body + Vector2(-sin(heading), -cos(heading)) * CompanyTuning.FORKLIFT_TIP_M


## The height of the forks at `now_msec`.
func height_at(now_msec: int) -> float:
	if mast_dir == 0:
		return mast.fork_height
	_probe.set_height(mast.fork_height)
	return _probe.lift(float(mast_dir), minf(maxf(float(now_msec - since_msec) / 1000.0, 0.0),
		CompanyTuning.FORKLIFT_MAST_BURST_S))


## Whether the forks are still going at `now_msec`.
func moving_at(now_msec: int) -> bool:
	return mast_dir != 0 and float(now_msec - since_msec) / 1000.0 < CompanyTuning.FORKLIFT_MAST_BURST_S


## The fork_state event for a forklift that stands at `body` facing `heading`, `peer` driving it (0: nobody), its
## forks moving `dir` from `height`.
static func state_event(peer: int, body: Vector2, heading: float, dir: int, height: float) -> Dictionary:
	return {"driver": peer, "at": body, "yaw": heading, "dir": dir, "height": height}


## Host: the event a fork_act request asks for at `station`, or its refusal: {reason: &"", kind, data} or {reason}.
func check(data: Dictionary, station: Dictionary, book: PalletJack, now_msec: int) -> Dictionary:
	var act: Variant = data.get("act")
	var peer: Variant = station.get("peer")
	var body: Variant = station.get("body")
	var heading: Variant = station.get("yaw")
	if not (CompanyAsk.is_id(act) and ACTS.has(StringName(act))):
		return {"reason": REASON_BAD_DATA}
	if typeof(peer) != TYPE_INT or not CompanyPallets.point_ok(body) or typeof(heading) != TYPE_FLOAT:
		return {"reason": REASON_NO_STATION}
	var height: float = height_at(now_msec)
	var what := StringName(act)
	if what == ACT_BOARD:
		return _check_board(station, peer, body, heading, height)
	if driver != peer:
		return {"reason": REASON_NOT_DRIVER}
	if what == ACT_LEAVE:
		var parks: bool = parks_at(station, body)
		return _state(state_event(0, body, heading, 0, height)) if parks else {"reason": REASON_NO_ROOM}
	if what == ACT_MAST:
		return _check_mast(data, station, body, heading, now_msec)
	return _check_work(station, book, tip_of(body, heading), height)


## Host: the fork_state event that lets the forklift go because `peer`, its driver, left: parked where the station
## says it stands ("body" and "yaw": the leaver's player, still there on peer_removed), else where they got on, its
## forks still. {reason: not_driver} when `peer` does not drive it (the second of peer_removed / peer_disconnected).
func let_go(peer: int, station: Dictionary, now_msec: int) -> Dictionary:
	if peer == 0 or driver != peer:
		return {"reason": REASON_NOT_DRIVER}
	var body: Variant = station.get("body")
	var heading: Variant = station.get("yaw")
	if not (CompanyPallets.point_ok(body) and typeof(heading) == TYPE_FLOAT):
		body = at if CompanyPallets.point_ok(at) else Vector2.ZERO
		heading = yaw
	return _state(state_event(0, body, heading, 0, height_at(now_msec)))


## Whether the forklift may be left with its driver at `body`: on the station's floor, where it may stand.
static func parks_at(station: Dictionary, body: Vector2) -> bool:
	var floor_rect: Variant = station.get("floor")
	var stand: Variant = station.get("stand_ok")
	return floor_rect is Rect2 and (floor_rect as Rect2).has_point(body) and stand is Callable \
		and (stand as Callable).is_valid() and bool((stand as Callable).call(body))


## Where a stop leaves the forks: the height the driver drew (`drawn`) when it lies within what the forks cover in
## the driver's round trip `lag` (s, at most 1) and STOP_SLACK_S of the host's `height`, else the nearest that does.
static func stop_height(height: float, drawn: float, lag: float) -> float:
	var slack: float = CompanyTuning.FORKLIFT_LIFT_SPEED * (clampf(lag, 0.0, 1.0) + STOP_SLACK_S)
	return clampf(clampf(drawn, height - slack, height + slack), 0.0, CompanyTuning.FORKLIFT_MAX_LIFT_M)


## Every peer: a fork_state event. False, changing nothing, when its data does not fit.
func apply(data: Dictionary, now_msec: int) -> bool:
	var fresh: Dictionary = _parse(data)
	if fresh.is_empty():
		return false
	driver = fresh["driver"]
	at = fresh["at"]
	yaw = fresh["yaw"]
	mast_dir = fresh["dir"]
	mast.set_height(fresh["height"])
	since_msec = now_msec
	return true


## The snapshot part: the state as of `now_msec` (forks whose burst is over go as still: the late peer would
## integrate a whole burst more from the height they stopped at).
func to_dict(now_msec: int) -> Dictionary:
	return {"driver": driver, "at": at, "yaw": yaw, "dir": mast_dir if moving_at(now_msec) else 0,
		"height": height_at(now_msec), "holds": holds}


## Client: the host's part in place of what is here. False, changing nothing, when it does not fit.
func put_snapshot(value: Variant, now_msec: int) -> bool:
	if not value is Dictionary:
		return false
	var plain: Dictionary = value
	var held: Variant = plain.get("holds", false)
	var at_value: Variant = plain.get("at")
	var data: Dictionary = plain.duplicate()
	if at_value == null:
		data["at"] = Vector2.ZERO
	if not held is bool or _parse(data).is_empty() or not (at_value == null or CompanyPallets.point_ok(at_value)):
		return false
	apply(data, now_msec)
	if at_value == null:
		at = null
	holds = held
	return true


func _state(event: Dictionary) -> Dictionary:
	return {"reason": &"", "kind": CompanyPallets.FORK, "data": event}


## Getting on: a free forklift, and the requester's hands free (no units, no box: the station's "hands_free").
func _check_board(station: Dictionary, peer: int, body: Vector2, heading: float, height: float) -> Dictionary:
	if driver != 0:
		return {"reason": REASON_TAKEN}
	if not (station.get("hands_free") is bool and bool(station["hands_free"])):
		return {"reason": REASON_HANDS_BUSY}
	return _state(state_event(peer, body, heading, 0, height))


## The mast: the forks go `dir` from where they are now, a stop from the height the driver drew (stop_height(),
## within the requester's round trip, the station's "lag"). no_change for a request that would change nothing.
func _check_mast(data: Dictionary, station: Dictionary, body: Vector2, heading: float, now_msec: int) -> Dictionary:
	var dir: Variant = data.get("dir")
	var drawn: Variant = data.get("at_height")
	if typeof(dir) != TYPE_INT or absi(dir) > 1:
		return {"reason": REASON_BAD_DATA}
	if drawn != null and not (CompanyPallets.is_number(drawn) and is_finite(float(drawn))):
		return {"reason": REASON_BAD_DATA}
	var height: float = height_at(now_msec)
	var target: float = height
	if dir == 0 and drawn != null:
		var lag: Variant = station.get("lag")
		var seconds: float = float(lag) if CompanyPallets.is_number(lag) and is_finite(float(lag)) else 0.0
		target = stop_height(height, float(drawn), seconds)
	var going: int = mast_dir if moving_at(now_msec) else 0
	var top: float = CompanyTuning.FORKLIFT_MAX_LIFT_M - END_M
	var at_end: bool = (dir > 0 and target >= top) or (dir < 0 and target <= END_M)
	if at_end or (dir == 0 and going == 0 and absf(target - height) <= END_M):
		return {"reason": REASON_NO_CHANGE}
	return _state(state_event(driver, body, heading, dir, target))


## The fields of a fork_state event checked and rebuilt from plain values; {} when one does not fit.
static func _parse(data: Dictionary) -> Dictionary:
	var peer: Variant = data.get("driver")
	var body: Variant = data.get("at")
	var heading: Variant = data.get("yaw")
	var dir: Variant = data.get("dir")
	var height: Variant = data.get("height")
	if typeof(peer) != TYPE_INT or peer < 0 or peer > 2147483647 or not CompanyPallets.point_ok(body):
		return {}
	if not (CompanyPallets.is_number(heading) and is_finite(float(heading))):
		return {}
	if typeof(dir) != TYPE_INT or absi(dir) > 1 or not CompanyPallets.is_number(height) or not is_finite(float(height)):
		return {}
	return {"driver": peer, "at": body, "yaw": float(heading), "dir": dir,
		"height": clampf(float(height), 0.0, CompanyTuning.FORKLIFT_MAX_LIFT_M)}


## Work: take the pallet in front of the forks or leave the one they carry.
func _check_work(station: Dictionary, book: PalletJack, tip: Vector2, height: float) -> Dictionary:
	_probe.set_height(height)
	if book.carrying == &"":
		return _check_pick(station, book, tip)
	return _check_put(station, book, tip) if holds else {"reason": REASON_JACK_FULL}


## Taking a pallet: with the forks down, the first of the truck's bed when it is parked and in reach, else the
## nearest on the floor in reach; with them at a rack slot's level, the pallet on the nearest slot in reach.
func _check_pick(station: Dictionary, book: PalletJack, tip: Vector2) -> Dictionary:
	var reach: float = CompanyTuning.PALLET_JACK_REACH_M
	if _probe.at_level(0.0):
		var rear: Variant = station.get("bed_at")
		var on_bed: Array[StringName] = book.ids_at(PalletJack.AT_BED)
		if bool(station.get("bed_open")) and CompanyPallets.point_ok(rear) and tip.distance_to(rear) <= reach \
				and not on_bed.is_empty():
			return _picked(on_bed[0])
		var nearest: StringName = &""
		var best: float = reach
		for id: StringName in book.ids_at(PalletJack.AT_FLOOR):
			var apart: float = tip.distance_to(book.places[id]["pos"])
			if apart <= best:
				best = apart
				nearest = id
		if nearest != &"":
			return _picked(nearest)
	var rack: Dictionary = _rack_near(station, tip, book, true)
	if not rack.is_empty():
		return _picked(book.rack_pallet(rack["slot"]))
	if book.ids_at(PalletJack.AT_BED).size() > 0 and not bool(station.get("bed_open")) and _probe.at_level(0.0):
		return {"reason": REASON_TRUCK_AWAY}
	return {"reason": REASON_NO_PALLET}


## Leaving the carried pallet: with the forks down, on the floor in front of them; else on the free rack slot in
## reach at the forks' level.
func _check_put(station: Dictionary, book: PalletJack, tip: Vector2) -> Dictionary:
	if _probe.at_level(0.0):
		var floor_rect: Variant = station.get("floor")
		var stand: Variant = station.get("stand_ok")
		var free: Variant = station.get("free_ok")
		var fits: bool = floor_rect is Rect2 and book.can_put_down(tip, floor_rect)
		fits = fits and not (stand is Callable and not bool((stand as Callable).call(tip)))
		fits = fits and not (free is Callable and not bool((free as Callable).call(tip)))
		if fits:
			return {"reason": &"", "kind": CompanyPallets.PLACED, "data": {"pallet": book.carrying, "pos": tip}}
	var rack: Dictionary = _rack_near(station, tip, book, false)
	if not rack.is_empty():
		return {"reason": &"", "kind": CompanyPallets.PLACED,
			"data": {"pallet": book.carrying, "pos": rack["pos"], "slot": rack["slot"]}}
	return {"reason": REASON_NO_ROOM if _probe.at_level(0.0) else REASON_NO_RACK}


func _picked(id: StringName) -> Dictionary:
	return {"reason": &"", "kind": CompanyPallets.PICKED, "data": {"pallet": id, "by": BY}}


## The nearest rack slot of the station within reach of `tip` at the level of the forks that holds a pallet
## (`taken`) or is free; {} for none.
func _rack_near(station: Dictionary, tip: Vector2, book: PalletJack, taken: bool) -> Dictionary:
	var found: Dictionary = {}
	var best: float = CompanyTuning.PALLET_JACK_REACH_M
	var racks: Variant = station.get("racks")
	if not racks is Array:
		return found
	for rack: Variant in racks:
		if not (rack is Dictionary and CompanyPallets.point_ok((rack as Dictionary).get("pos"))):
			continue
		var apart: float = tip.distance_to((rack as Dictionary)["pos"])
		var level: float = float((rack as Dictionary).get("level", -1.0))
		var slot: StringName = StringName(str((rack as Dictionary).get("slot", "")))
		if apart <= best and level >= 0.0 and _probe.at_level(level) and (book.rack_pallet(slot) != &"") == taken:
			found = rack
			best = apart
	return found
