class_name TripScoring
extends RefCounted
## The score of a closed trip, from the delivery run's own scoring (expansion D-0520, "Modo Empresa").
##
## Pure functions over the lines of a TripResult: no node, no autoload, no UI. Each line is worth what
## the same door is worth in a delivery run (RunScoring: an intact box 150, a dented one 75, a ruined
## one 20, an order that never arrived -60), and the trip's score is the sum, never below 0, put
## together by RunScoring.settle() so both modes close a run the same way (no chaos multiplier here:
## there is no chaos in a trip). The score is NOT money: the pay of an order was already settled at the
## door (OrderSettlement), and paying the points as well would pay each box twice. What the score drives
## is the merit of whoever carried the box (merit_for()) and the "score" line of the trip's summary.
##
## Left out on purpose: the delivery photo and the complaints (a company customer answers with
## reputation, OrderPenalties), the deadlines (the quick tip already pays them, OrderTips) and the
## van's cargo back (a box that returns goes to stock, it is not a score).

const RUN_SCORING = preload("res://scripts/core/run_scoring.gd")


## What one line of a TripResult is worth in score points. A box that was not delivered is a house
## the customer waited for: the delivery run's missed-house penalty.
static func line_points(line: Dictionary) -> int:
	if line.get("outcome", TripResult.OUTCOME_FAILED) != TripResult.OUTCOME_DELIVERED:
		return -RUN_SCORING.PENALTY_MISSED_HOUSE
	match line.get("box", TripResult.BOX_UNDELIVERED):
		TripResult.BOX_INTACT:
			return RUN_SCORING.POINTS_DELIVERED_INTACT
		TripResult.BOX_AT_RISK:
			return RUN_SCORING.POINTS_DELIVERED_AT_RISK
		TripResult.BOX_BROKEN:
			return RUN_SCORING.POINTS_DELIVERED_RUINED
	return -RUN_SCORING.PENALTY_MISSED_HOUSE


## Merit the carrier earns for a delivered line: CompanyTuning.TRIP_MERIT_INTACT for an intact box,
## the same share of it as the box's points for a dented one (half), nothing for a ruined or
## undelivered one, so wrecking boxes never pays merit.
static func merit_for(line: Dictionary) -> int:
	if line.get("outcome", TripResult.OUTCOME_FAILED) != TripResult.OUTCOME_DELIVERED:
		return 0
	var box: StringName = line.get("box", TripResult.BOX_UNDELIVERED)
	if box != TripResult.BOX_INTACT and box != TripResult.BOX_AT_RISK:
		return 0
	return roundi(
		float(CompanyTuning.TRIP_MERIT_INTACT) * line_points(line) / RUN_SCORING.POINTS_DELIVERED_INTACT
	)


## {score, delivery_points, delivered, breakdown} for the lines of a trip. breakdown is the delivery
## run's results format ({label, count, points}, labels HUD_SCORE_*), one entry per kind that happened.
static func score(lines: Array) -> Dictionary:
	var counts: Dictionary = {}
	var points: int = 0
	var delivered: int = 0
	for line: Dictionary in lines:
		var worth: int = line_points(line)
		points += worth
		var label: String = _label(line)
		counts[label] = int(counts.get(label, 0)) + 1
		if line.get("outcome", TripResult.OUTCOME_FAILED) == TripResult.OUTCOME_DELIVERED:
			delivered += 1
	var breakdown: Array = []
	var each: Dictionary = {
		"HUD_SCORE_PERFECT": RUN_SCORING.POINTS_DELIVERED_INTACT,
		"HUD_SCORE_DENTED": RUN_SCORING.POINTS_DELIVERED_AT_RISK,
		"HUD_SCORE_RUINED": RUN_SCORING.POINTS_DELIVERED_RUINED,
		"HUD_SCORE_MISSED": -RUN_SCORING.PENALTY_MISSED_HOUSE,
	}
	for label: String in each:
		if counts.has(label):
			var count: int = int(counts[label])
			breakdown.append({"label": label, "count": count, "points": count * int(each[label])})
	var doors: Dictionary = {"breakdown": breakdown, "delivery_points": points, "houses_delivered": delivered}
	var settled: Dictionary = RUN_SCORING.settle({}, doors, true, false)
	return {
		"score": int(settled["score"]),
		"delivery_points": points,
		"delivered": delivered,
		"breakdown": settled["breakdown"],
	}


static func _label(line: Dictionary) -> String:
	if line.get("outcome", TripResult.OUTCOME_FAILED) != TripResult.OUTCOME_DELIVERED:
		return "HUD_SCORE_MISSED"
	match line.get("box", TripResult.BOX_UNDELIVERED):
		TripResult.BOX_INTACT:
			return "HUD_SCORE_PERFECT"
		TripResult.BOX_AT_RISK:
			return "HUD_SCORE_DENTED"
		TripResult.BOX_BROKEN:
			return "HUD_SCORE_RUINED"
	return "HUD_SCORE_MISSED"
