class_name TripTow
extends RefCounted
## "Volver con grua": the way home for a vehicle that cannot drive any more (expansion D-0307).
##
## Pure rules, like DispatchRules: no node, no autoload, no UI, no RPC. When the vehicle of an open
## Trip is STUCK or BROKEN and the company can pay CompanyTuning.TOW_COST, tow_home() takes the money
## from the wallet (ledger reason `tow`) and closes the Trip with Trip.close(): the orders not delivered
## become FAILED (and, with an Inventory, the products of a sound box go back to the dock). Any refusal
## changes nothing. The host calls it; the black screen and the teleport to the yard are the world's job
## (D-0307.1) and only read `black_screen_s` from the answer.

const VEHICLE_OK: StringName = &"ok"
const VEHICLE_STUCK: StringName = &"stuck"
const VEHICLE_BROKEN: StringName = &"broken"

## Ledger reason of the tow; the day summary shows an unknown reason as its own id.
const LEDGER_REASON: StringName = &"tow"

const NO_TRIP: String = "WORLD_TOW_NO_TRIP"
const NOT_STUCK: String = "WORLD_TOW_NOT_STUCK"
const NO_MONEY: String = "WORLD_TOW_NO_MONEY"
const DONE: String = "WORLD_TOW_DONE"


## True when the vehicle may be towed: it cannot go on by itself.
static func can_tow(vehicle_state: StringName) -> bool:
	return vehicle_state == VEHICLE_STUCK or vehicle_state == VEHICLE_BROKEN


## {"ok": bool, "key": translation key, "args": values to format it with, "cost": money taken,
## "failed_ids": orders that failed with the trip, "black_screen_s": seconds of black screen}.
## `wallet` is the company wallet (CompanyState: can_afford() and spend()). Refused, nothing changes, when
## there is no open trip (TOW_NO_TRIP), the vehicle can still drive (TOW_NOT_STUCK) or the wallet does not
## cover CompanyTuning.TOW_COST (TOW_NO_MONEY, args [cost]). `broken_boxes` are the boxes that lose their
## products when the trip closes with an `inventory`.
static func tow_home(
	trip: Trip,
	vehicle_state: StringName,
	wallet: Object,
	book: OrderBook,
	now_min: int,
	inventory: Inventory = null,
	broken_boxes: Array[StringName] = [],
) -> Dictionary:
	if trip == null or not trip.is_out() or book == null:
		return _answer(false, NO_TRIP)
	if not can_tow(vehicle_state):
		return _answer(false, NOT_STUCK)
	var cost: int = CompanyTuning.TOW_COST
	if wallet == null or not wallet.can_afford(cost) or not wallet.spend(cost, LEDGER_REASON):
		return _answer(false, NO_MONEY, [cost])
	var failed: Array[StringName] = trip.close(book, now_min, inventory, broken_boxes)
	var done: Dictionary = _answer(true, DONE, [cost])
	done["cost"] = cost
	done["failed_ids"] = failed
	done["black_screen_s"] = CompanyTuning.TOW_BLACK_SCREEN_SECONDS
	return done


static func _answer(ok: bool, key: String, args: Array = []) -> Dictionary:
	var failed: Array[StringName] = []
	return {
		"ok": ok, "key": key, "args": args, "cost": 0, "failed_ids": failed, "black_screen_s": 0.0,
	}
