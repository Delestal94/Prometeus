class_name ServiceStopRules
extends RefCounted
## When and where a service station shows up on the road (tareas de Nacho
## N-110). Pure and static, like RoutePlanner: every peer works out the same
## answer from the plan or the session seed, so nobody is told about it and a
## late joiner sees the station too.
##
## Delivery: only a long route gets one (LONG_ROUTE_HOUSES houses or more, or
## LONG_ROUTE_METERS of road), at most one, in the boundary between two
## planned segments closest to the middle of the road that leaves room around
## it (see fits()): never in the calm approach to a house, nor right after one,
## nor in the first stretch, nor at the goal. The station is a segment of its
## own (ServiceStopSegment) inserted into the plan, so every distance after it
## moves by the segment's length. Endless: every so often (see endless_next_at()).
##
## Stopping is a decision, not a free breather: nothing here pauses or
## extends a deadline (RunManager.plan_deadlines() keeps running while the
## crew shops).

## The station's segment, loaded as a script so nothing here needs the class
## cache (the same reason RouteStreamer keeps its script lists in code).
const SEGMENT = preload("res://scripts/gameplay/route/segments/service_stop_segment.gd")
## A route is long from this many houses on, or from this many metres (the
## planner's total, station excluded). 2-house routes come to ~2100 m, so they
## qualify some of the time; five houses is the shortest road, ~1500 m.
const LONG_ROUTE_HOUSES: int = 3
const LONG_ROUTE_METERS: float = 2000.0
## Room the station needs in a delivery, in metres of road: from the start
## (past the safe runway), after a house (the truck pulling away), before the
## next house (RoutePlanner.QUIET_ZONE + a margin, so the calm approach and
## its "entrega adelante" sign are never in the station) and before the goal.
const MIN_START: float = 150.0
const AFTER_HOUSE_GAP: float = 40.0
const BEFORE_HOUSE_GAP: float = 110.0
const BEFORE_GOAL_GAP: float = 60.0
## Endless: the first station lies between ENDLESS_FIRST_* metres, each
## next one ENDLESS_GAP_* metres after the one before (measured start to start).
const ENDLESS_FIRST_MIN: float = 450.0
const ENDLESS_FIRST_MAX: float = 800.0
const ENDLESS_GAP_MIN: float = 900.0
const ENDLESS_GAP_MAX: float = 1500.0
## Delivery: where the yard is levelled, in the segment's space (terrain pads:
## flat for 5 m round each, faded out by 11 m -- the forecourt's pad barely
## reaches the right lane's edge, never the lane). Under the forecourt and
## under the kiosk; the price pole is one post and rides whatever is there.
const YARD_PADS: Array[Vector3] = [Vector3(14.6, 0.0, -70.0), Vector3(19.9, 0.0, -70.0)]


static func segment_length() -> float:
	return SEGMENT.LENGTH


static func is_long_route(houses: int, total_length: float) -> bool:
	return houses >= LONG_ROUTE_HOUSES or total_length >= LONG_ROUTE_METERS


## Whether a station that starts `at` metres along a delivery leaves room
## around it: `stops` are the house distances, `total` the road's length.
static func fits(at: float, stops: Array, total: float) -> bool:
	var length: float = segment_length()
	if at < MIN_START or at + length > total - BEFORE_GOAL_GAP:
		return false
	for stop: float in stops:
		if at + length > stop - BEFORE_HOUSE_GAP and at < stop + AFTER_HOUSE_GAP:
			return false
	return true


## `plan` (RoutePlanner.plan_spine()) with the station inserted when the
## route is long and there is room: the entry has the same keys as any other
## planned segment plus "service_stop", it counts as a "moment" (a stop is
## something happening) and every distance after it moves by its length.
## Returns `plan` itself when there is no station.
static func insert_into_plan(plan: Dictionary, houses: int) -> Dictionary:
	if not is_long_route(houses, float(plan.total)):
		return plan
	var segments: Array = plan.segments
	var stops: Array = plan.house_distances
	var total: float = float(plan.total)
	var length: float = segment_length()
	var best: int = -1
	var best_gap: float = INF
	for index: int in range(1, segments.size()):
		var at: float = float(segments[index].start)
		if not fits(at, stops, total) or _rough_neighbour(segments[index - 1].script) \
				or _rough_neighbour(segments[index].script):
			continue
		var gap: float = absf(at + length * 0.5 - total * 0.5)
		if gap < best_gap:
			best = index
			best_gap = gap
	if best < 0:
		return plan
	var placed: Array = segments.duplicate()
	var at_best: float = float(segments[best].start)
	for index: int in range(best, placed.size()):
		var moved: Dictionary = (placed[index] as Dictionary).duplicate()
		moved.start = float(moved.start) + length
		placed[index] = moved
	placed.insert(best, {
		"script": SEGMENT, "turn_deg": 0.0, "length": length, "leg": segments[best - 1].leg,
		"start": at_best, "hard": false, "moment": true, "delivery_sign": false, "service_stop": true,
	})
	var moved_stops: Array = stops.map(func(stop: float) -> float: return stop + length if stop >= at_best else stop)
	return {"segments": placed, "house_distances": moved_stops, "total": total + length}


## A bridge, a tunnel, a rail crossing or a hill on either side: their
## terrain (a riverbed, a cutting, a crest) reaches over the roadside where
## the station's yard would stand.
static func _rough_neighbour(script: Script) -> bool:
	return script == NarrowBridgeSegment or script == TunnelSegment or script == RailCrossingSegment \
			or script == HillSegment


## Endless: how far along the road the next station starts. `index` counts the
## stations so far (0 for the first) and `previous` is where the last one
## started. Drawn from the seed and the index alone, so it never touches the
## streamer's own RNG (the road it lays stays the road it always laid).
static func endless_next_at(seed_value: int, index: int, previous: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"service_stop", index])
	if index == 0:
		return rng.randf_range(ENDLESS_FIRST_MIN, ENDLESS_FIRST_MAX)
	return previous + rng.randf_range(ENDLESS_GAP_MIN, ENDLESS_GAP_MAX)


## Whether Endless may lay the station now: not on a hard stretch nor right
## after one (`hard_streak` is how many hard segments came just before), so it
## is a breather the crew can actually use.
static func endless_can_start(hard_streak: int, previous_was_hard: bool) -> bool:
	return hard_streak == 0 and not previous_was_hard
