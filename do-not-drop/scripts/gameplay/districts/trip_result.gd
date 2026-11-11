class_name TripResult
extends RefCounted
## What a closed trip came to (expansion D-0320, "Modo Empresa").
##
## Pure functions over a closed Trip and its OrderBook: no node, no autoload, no UI. build() gives
## one summary per trip with a line per order (delivered or failed, state of its box, base pay,
## what was paid, the penalty and the reputation change) and the totals. The carrier of an intact
## delivery earns merit (apply()); add_to_day() folds trips into the day's DaySummary dictionary.
## Money and reputation were already settled at the door (OrderPenalties, OrderTips): this only reports.
## The trip's score and the merit of each carrier come from the delivery run's scoring (TripScoring,
## D-0520): the score is a report, not money.

const BOX_INTACT: StringName = &"intact"
const BOX_AT_RISK: StringName = &"at_risk"
const BOX_BROKEN: StringName = &"broken"
## The order never reached its house.
const BOX_UNDELIVERED: StringName = &"undelivered"

const OUTCOME_DELIVERED: StringName = &"delivered"
const OUTCOME_FAILED: StringName = &"failed"


## Summary of a closed trip, empty if it is still out. verdicts maps order id -> what
## OrderPenalties.assess returned for its delivery (pay, kinds, reputation); an order without
## one is read from the book (its paid amount, intact flag and quality). carriers maps order id
## -> peer id of whoever carried that box to the door.
## {trip_id, vehicle_id, depart_min, return_min, depart_clock, return_clock, duration_min,
## orders, delivered, failed, intact,
## at_risk, broken, base_total, pay_total, penalty_total, reputation, returned_units, lost_units,
## merit_by_peer, score, score_points, score_breakdown}. score is never below 0, score_points is
## the raw sum (TripScoring).
static func build(
	trip: Trip, book: OrderBook, verdicts: Dictionary = {}, carriers: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"trip_id": trip.id if trip != null else &"",
		"vehicle_id": trip.vehicle_id if trip != null else &"",
		"depart_min": trip.depart_min if trip != null else -1,
		"return_min": trip.return_min if trip != null else -1,
		"depart_clock": clock_text(trip.depart_min) if trip != null else "",
		"return_clock": clock_text(trip.return_min) if trip != null else "",
		"duration_min": trip.duration_min() if trip != null else -1,
		"orders": [] as Array[Dictionary],
		"delivered": 0,
		"failed": 0,
		"intact": 0,
		"at_risk": 0,
		"broken": 0,
		"base_total": 0,
		"pay_total": 0,
		"penalty_total": 0,
		"reputation": 0.0,
		"returned_units": trip.returned_units if trip != null else 0,
		"lost_units": trip.lost_units if trip != null else 0,
		"merit_by_peer": {},
		"score": 0,
		"score_points": 0,
		"score_breakdown": [] as Array,
	}
	if trip == null or trip.is_out():
		return result
	for order_id: StringName in trip.order_ids:
		var line: Dictionary = _line(trip, book, order_id, verdicts, carriers)
		result["orders"].append(line)
		result["base_total"] += int(line["base"])
		result["pay_total"] += int(line["pay"])
		result["penalty_total"] += int(line["penalty"])
		result["reputation"] += float(line["reputation"])
		if line["outcome"] == OUTCOME_FAILED:
			result["failed"] += 1
			continue
		result["delivered"] += 1
		match line["box"]:
			BOX_INTACT:
				result["intact"] += 1
			BOX_AT_RISK:
				result["at_risk"] += 1
			BOX_BROKEN:
				result["broken"] += 1
		var merit: int = TripScoring.merit_for(line)
		var peer: int = int(line["peer"])
		if merit > 0 and peer > 0:
			var by_peer: Dictionary = result["merit_by_peer"]
			by_peer[peer] = int(by_peer.get(peer, 0)) + merit
	var scored: Dictionary = TripScoring.score(result["orders"])
	result["score"] = scored["score"]
	result["score_points"] = scored["delivery_points"]
	result["score_breakdown"] = scored["breakdown"]
	return result


## Gives each carrier the merit of the summary once (CrewProgression.award_action dedupes by
## action id, so applying the same summary twice pays nothing the second time). Intact boxes pay
## CompanyTuning.TRIP_MERIT_INTACT, dented ones half, ruined or undelivered ones nothing
## (TripScoring.merit_for). Returns the total points awarded.
static func apply(result: Dictionary, crew: Object) -> int:
	if crew == null:
		return 0
	var total: int = 0
	for line: Dictionary in result.get("orders", []):
		var merit: int = TripScoring.merit_for(line)
		var peer: int = int(line["peer"])
		if merit <= 0 or peer <= 0:
			continue
		var action := StringName("trip:%s:%s" % [result["trip_id"], line["order_id"]])
		if crew.award_action(peer, action, merit):
			total += merit
	return total


## Adds the trips of a day to its DaySummary dictionary (keys trips, trip_deliveries, trip_failed,
## trip_penalties, trip_pay and trip_score) and returns it. The financial keys are left as they are.
static func add_to_day(summary: Dictionary, results: Array) -> Dictionary:
	var out: Dictionary = summary
	out["trips"] = results.size()
	out["trip_deliveries"] = 0
	out["trip_failed"] = 0
	out["trip_penalties"] = 0
	out["trip_pay"] = 0
	out["trip_score"] = 0
	for result: Dictionary in results:
		out["trip_deliveries"] += int(result.get("delivered", 0))
		out["trip_failed"] += int(result.get("failed", 0))
		out["trip_penalties"] += int(result.get("penalty_total", 0))
		out["trip_pay"] += int(result.get("pay_total", 0))
		out["trip_score"] += int(result.get("score", 0))
	return out


static func _line(
	trip: Trip, book: OrderBook, order_id: StringName, verdicts: Dictionary, carriers: Dictionary
) -> Dictionary:
	var order: Dictionary = book.get_order(order_id)
	var base: int = int(order.get("pay", 0))
	var line: Dictionary = {
		"order_id": order_id,
		"house_id": StringName(order.get("house_id", "")),
		"outcome": OUTCOME_FAILED,
		"box": BOX_UNDELIVERED,
		"base": base,
		"pay": 0,
		"penalty": base,
		"reputation": 0.0,
		"peer": int(carriers.get(order_id, 0)),
	}
	if not order_id in trip.delivered_ids:
		return line
	var verdict: Dictionary = verdicts.get(order_id, {})
	var pay: int = int(verdict["pay"]) if verdict.has("pay") else int(order.get("paid", 0))
	line["outcome"] = OUTCOME_DELIVERED
	line["pay"] = pay
	line["penalty"] = maxi(base - pay, 0)
	line["reputation"] = float(verdict.get("reputation", 0.0))
	var broken: bool = (
		OrderPenalties.KIND_BROKEN in verdict.get("kinds", [])
		or not bool(order.get("intact", true))
	)
	if broken:
		line["box"] = BOX_BROKEN
	elif int(order.get("quality", 100)) < CompanyTuning.CONDITION_BONUS_MIN_QUALITY:
		line["box"] = BOX_AT_RISK
	else:
		line["box"] = BOX_INTACT
	return line


## "HH:MM" of a game minute (minutes since midnight of day 1, wrapping past midnight); empty for
## a minute that was never set (-1), like a trip that is still out.
static func clock_text(minute: int) -> String:
	if minute < 0:
		return ""
	var of_day: int = minute % CompanyTuning.MINUTES_PER_DAY
	return "%02d:%02d" % [floori(of_day / 60.0), of_day % 60]
