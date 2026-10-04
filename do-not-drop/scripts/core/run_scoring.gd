extends RefCounted
## How a run turns into points (N-225.5), split out of run_manager.gd: the door-by-door resolution, the van's
## cargo tally and the endless distance score. Static and pure over what the autoload hands in (its deliveries,
## cargo, assignments...), so the host-only checks, the leaderboard and the results dictionary stay on the
## autoload, which owns that state. The numbers are provisional for the test route; tune them by editing the
## constants, not the logic.

const DELIVERIES = preload("res://scripts/core/run_deliveries.gd")
const DEADLINES = preload("res://scripts/core/run_deadlines.gd")

## The keys of the results screen's lines (outcomes and rescue kinds).
const OUTCOME_OK: StringName = &"delivered_ok"
const OUTCOME_AT_RISK: StringName = &"delivered_at_risk"
const OUTCOME_RUINED: StringName = &"delivered_ruined"
const RESCUE_REPAIRED: StringName = &"repaired"
const RESCUE_UNCONVINCING: StringName = &"unconvincing"
const RESCUE_SUBSTITUTED: StringName = &"substituted"

const POINTS_INTACT: int = 100
const POINTS_AT_RISK: int = 50
const CHAOS_MULTIPLIER: float = 1.2

## docs/tareas-nacho.md #44/#52: endless never "delivers" (no zone to reach), so
## it can't use the cargo formula above -- distance is what keeps going up.
## Placeholder weight: tune by editing this constant, not the logic.
const DISTANCE_POINTS_PER_METER: float = 1.0

## Handing a box to a resident at their door is worth more than the same
## box merely surviving the trip in the van -- delivering is the goal, not
## hoarding. Showing up with a wrecked box still beats never showing up:
## the resident gets something, and the run gets a story.
const POINTS_DELIVERED_INTACT: int = 150
const POINTS_DELIVERED_AT_RISK: int = 75
const POINTS_DELIVERED_RUINED: int = 20
## Driving past a house nobody ever rang. Deliberately worse than delivering
## a ruined box: the resident waited for nothing.
const PENALTY_MISSED_HOUSE: int = 60
## The delivery photo (see the phone camera): a small reward on its own, and
## the only thing that settles a complaint afterwards.
const POINTS_PHOTO_BONUS: int = 25
## What an unanswered complaint costs. A wrecked or dented box always draws one
## (no dice, N-227.2): only the delivery photo settles it.
const COMPLAINT_PENALTY: int = 40

## Cargo rescue (docs/jugabilidad-paquetes-rescate.md): a repair that holds
## up at the door pays less than intact but well over a dented box; a
## doubtful fix and a deliberate substitute pay little. None of these roll
## dice for a complaint -- the same state always gets the same answer.
const POINTS_DELIVERED_REPAIRED: int = 110
const POINTS_DELIVERED_UNCONVINCING: int = 35
const POINTS_DELIVERED_SUBSTITUTED: int = 10
const CARE_POINTS: Dictionary = {
	&"repaired": POINTS_DELIVERED_REPAIRED,
	&"unconvincing": POINTS_DELIVERED_UNCONVINCING,
	&"substituted": POINTS_DELIVERED_SUBSTITUTED,
}


## Points and complaints from the doors, kept apart from the van tally in
## settle() so each side stays readable on its own. `line_seed` picks the
## complaints' wording (the world seed online, a fresh one solo).
static func resolve_deliveries(deliveries: Array, house_assignments: Array, refused_houses: Dictionary,
		expected_houses: int, deadlines: Array, line_seed: int) -> Dictionary:
	var points: int = 0
	var delivered_count: int = 0
	var missed: int = 0
	var lost: int = 0
	var photos: int = 0
	var complaints: Array[Dictionary] = []
	var rescued: Dictionary = {}
	for entry: Dictionary in deliveries:
		var outcome: StringName = StringName(entry["outcome"])
		var has_photo: bool = bool(entry["photo"]) and DELIVERIES.handed_over(outcome)
		if has_photo:
			photos += 1
			points += POINTS_PHOTO_BONUS
		var care: StringName = StringName(entry.get("care", ""))
		if DELIVERIES.handed_over(outcome) and CARE_POINTS.has(care):
			# The resident inspected a rescued box: what they saw decides
			# the pay, not the trap's bar or a roll for a complaint.
			points += int(CARE_POINTS[care])
			delivered_count += 1
			rescued[care] = int(rescued.get(care, 0)) + 1
			continue
		match outcome:
			&"delivered_ok":
				points += POINTS_DELIVERED_INTACT
				delivered_count += 1
			&"delivered_ruined":
				points += POINTS_DELIVERED_RUINED
				delivered_count += 1
				complaints.append(ClientComplaints.make(entry, has_photo, house_assignments, line_seed))
			&"missed":
				missed += 1
				points -= PENALTY_MISSED_HOUSE
			&"lost":
				# Its box was left on the road (N-213.4): the resident waited
				# for nothing, same as a door the run drove past.
				lost += 1
				points -= PENALTY_MISSED_HOUSE
			&"delivered_at_risk":
				# Handed over dented: worth less, and the resident always brings it
				# up -- the case the delivery photo exists to answer.
				points += POINTS_DELIVERED_AT_RISK
				delivered_count += 1
				complaints.append(ClientComplaints.make(entry, has_photo, house_assignments, line_seed))
			_:
				push_warning("[Run] Unknown delivery outcome: %s" % outcome)
	complaints.append_array(ClientComplaints.wrong_notes(refused_houses, complaints, house_assignments, line_seed))
	# Doors the run never reached at all: no house ever resolved them, so
	# they have no record of their own, but the resident still waited.
	var unreached: int = maxi(expected_houses - deliveries.size(), 0)
	missed += unreached
	points -= unreached * PENALTY_MISSED_HOUSE
	var tally: Dictionary = DEADLINES.tally(deadlines, deliveries)
	points += int(tally["met"]) * DEADLINES.POINTS_DEADLINE_MET
	points -= int(tally["missed"]) * DEADLINES.PENALTY_DEADLINE_MISSED
	var unanswered: int = 0
	for complaint: Dictionary in complaints:
		if not bool(complaint["dismissed"]):
			points -= COMPLAINT_PENALTY
			unanswered += 1
	# Line by line, for the results screen (tareas de Slatex #89): the same
	# sums as `points`, so the lines always add up to the score shown.
	var counts: Dictionary = {}
	for entry: Dictionary in deliveries:
		if DELIVERIES.handed_over(StringName(entry["outcome"])) and CARE_POINTS.has(StringName(entry.get("care", ""))):
			continue
		counts[StringName(entry["outcome"])] = int(counts.get(StringName(entry["outcome"]), 0)) + 1
	var breakdown: Array = []
	_add_line(breakdown, "HUD_SCORE_PERFECT", int(counts.get(OUTCOME_OK, 0)), POINTS_DELIVERED_INTACT)
	_add_line(breakdown, "HUD_SCORE_DENTED", int(counts.get(OUTCOME_AT_RISK, 0)), POINTS_DELIVERED_AT_RISK)
	_add_line(breakdown, "HUD_SCORE_RUINED", int(counts.get(OUTCOME_RUINED, 0)), POINTS_DELIVERED_RUINED)
	_add_line(breakdown, "HUD_SCORE_REPAIRED", int(rescued.get(RESCUE_REPAIRED, 0)), POINTS_DELIVERED_REPAIRED)
	_add_line(breakdown, "HUD_SCORE_UNCONVINCING", int(rescued.get(RESCUE_UNCONVINCING, 0)),
			POINTS_DELIVERED_UNCONVINCING)
	_add_line(breakdown, "HUD_SCORE_SUBSTITUTED", int(rescued.get(RESCUE_SUBSTITUTED, 0)), POINTS_DELIVERED_SUBSTITUTED)
	_add_line(breakdown, "HUD_SCORE_DEADLINE_MET", int(tally["met"]), DEADLINES.POINTS_DEADLINE_MET)
	_add_line(breakdown, "HUD_SCORE_DEADLINE_MISSED", int(tally["missed"]), -DEADLINES.PENALTY_DEADLINE_MISSED)
	_add_line(breakdown, "HUD_SCORE_PHOTOS", photos, POINTS_PHOTO_BONUS)
	_add_line(breakdown, "HUD_SCORE_MISSED", missed, -PENALTY_MISSED_HOUSE)
	_add_line(breakdown, "HUD_SCORE_LOST", lost, -PENALTY_MISSED_HOUSE)
	_add_line(breakdown, "HUD_SCORE_COMPLAINTS", unanswered, -COMPLAINT_PENALTY)
	return {
		"breakdown": breakdown,
		"delivery_points": points,
		"houses_delivered": delivered_count,
		"houses_missed": missed,
		"houses_lost": lost,
		"photos": photos,
		"complaints": complaints,
	}


## One line of the score breakdown; nothing when there were none of that kind.
static func _add_line(breakdown: Array, label: String, count: int, each: int) -> void:
	if count > 0:
		breakdown.append({"label": label, "count": count, "points": count * each})


## The van's side of a delivery run on top of the doors (`doors` is resolve_deliveries()' answer): boxes handed
## over at a door are scored there instead -- they left the van on purpose, so counting them here too would pay
## twice for the same package. Returns the cargo tally (cargo_points, intact, ruined, aboard), whether the run
## counts as successful, the chaos multiplier, the final score and the breakdown lines.
static func settle(cargo: Dictionary, doors: Dictionary, delivered: bool, had_simultaneous_risk: bool) -> Dictionary:
	var cargo_points: int = 0
	var intact: int = 0
	var ruined: int = 0
	var aboard: int = 0
	for entry: Dictionary in cargo.values():
		if bool(entry.get("delivered", false)):
			continue
		aboard += 1
		if not delivered:
			ruined += 1
			continue
		match int(entry.get("state", 0)):
			ITrapBehavior.TrapState.OK:
				cargo_points += POINTS_INTACT
				intact += 1
			ITrapBehavior.TrapState.AT_RISK:
				cargo_points += POINTS_AT_RISK
			_:
				ruined += 1
	var delivery_points: int = int(doors["delivery_points"])
	var houses_delivered: int = int(doors["houses_delivered"])
	var successful: bool = delivered and (cargo_points > 0 or houses_delivered > 0)
	var multiplier: float = CHAOS_MULTIPLIER if (successful and had_simultaneous_risk) else 1.0
	var score: int = maxi(roundi((cargo_points + delivery_points) * multiplier), 0)
	var breakdown: Array = (doors["breakdown"] as Array).duplicate(true)
	if cargo_points > 0:
		breakdown.append({"label": "HUD_SCORE_CARGO_BACK", "count": aboard - ruined, "points": cargo_points})
	return {
		"cargo_points": cargo_points,
		"intact": intact,
		"ruined": ruined,
		"aboard": aboard,
		"successful": successful,
		"multiplier": multiplier,
		"score": score,
		"breakdown": breakdown,
	}


## Endless score (N-118): the meters each box survived, averaged over the
## boxes. All boxes intact scores exactly the distance, as before N-118, so old
## records stay comparable; every box lost early drags the score down, so
## the cargo -- the core of the game -- matters here too, not only as the
## run's lives. No cargo at all scores the plain distance.
static func endless_score(cargo: Dictionary, current_distance: float) -> int:
	if cargo.is_empty():
		return roundi(current_distance * DISTANCE_POINTS_PER_METER)
	var survived: float = 0.0
	for entry: Dictionary in cargo.values():
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.RUINED:
			survived += minf(float(entry.get("ruined_at_m", current_distance)), current_distance)
		else:
			survived += current_distance
	return roundi(survived / cargo.size() * DISTANCE_POINTS_PER_METER)
