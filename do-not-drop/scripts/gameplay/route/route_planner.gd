class_name RoutePlanner
extends RefCounted
## Plans a delivery route's spine before anything is built: which segment
## goes where, where the road bends, where each house stops the truck. Pure
## and static -- every draw comes from its own stream off the session seed, so
## every peer plans the same road and a test can check hundreds of seeds
## without building one. Route builds exactly what plan_spine() returns.

const CURVE_TURN_MAX_DEG: float = 70.0
const CURVE_TURN_MIN_DEG: float = 25.0
## How far before a house its "entrega adelante" sign goes up.
const DELIVERY_SIGN_LEAD: float = 80.0
const GENTLE_CURVE_DEG: float = 30.0
## Stopping at a house: get out, walk, ring, come back.
const HOUSE_STOP_SECONDS: float = 25.0
## Each leg varies this much around its budget, so they don't all match.
const LEG_LENGTH_JITTER: float = 0.1
const LEG_MAX_LENGTH: float = 700.0
## Bounds on a leg (start->house, house->house, house->goal): under the
## floor a leg is over before anything happens on it; over the cap one house
## alone would be a long, empty drive. The cap was 600 m, but one house then
## came to 1.9 minutes, under the 2-minute floor: 700 keeps it at ~2.2.
const LEG_MIN_LENGTH: float = 250.0
## How far the road may ever head away from the start's -Z. Past 90 degrees
## a run of same-way curves brought it back around onto road already built:
## two stretches overlapping, lines crossing the asphalt and roadworks
## standing on the other lane. Kept under 90, every stretch still advances
## along -Z, so the road can never cross itself.
const MAX_HEADING_DEG: float = 80.0
## The longest spine segment (HillSegment): how far one pick can run before
## the next rule gets a say.
const MAX_SEGMENT_LENGTH: float = 70.0
## How many segments in a row are allowed to leave the heading unchanged
## before a CurveSegment is forced -- this is the actual fix for "no quiero
## tramos rectos": without it, the "never repeat the same type twice" rule
## alone still allows Straight, Bump, Straight, Gravel, Straight... for as
## long as the RNG allows, all dead straight in world space.
const MAX_STRAIGHT_STREAK: int = 2
## Fewest houses a crew gets, alone or as a pair (see crew_house_count()).
const MIN_CREW_HOUSES: int = 2
## Pacing inside each leg (tareas de Nacho N-103), see plan_spine(): something
## happens at least every MOMENT_SPACING metres -- a hard segment, a bend of
## SHARP_CURVE_DEG or more, or a house stop -- and the last QUIET_ZONE metres
## before a house are straight or bend at most GENTLE_CURVE_DEG, so the crew
## gets out without a bump throwing a box.
const MOMENT_SPACING: float = 250.0
const QUIET_ZONE: float = 80.0
## Average driving speed over a whole route, m/s: the bench's autopilot
## cruising at 50 km/h, easing off in bends and braking for every stop,
## averaged 46 km/h on every house count.
const ROUTE_CRUISE_SPEED: float = 12.8
## The golden rule: a delivery lasts 2-5 minutes whatever the house count
## (tareas de Nacho N-102). The road is cut to a time budget instead of a
## fixed length per leg, so one house gets long legs (a mini adventure) and
## four get short ones. Measured with tests/bench_route_duration.gd; the
## table is in docs/parametros-diseno.md ("Duración de la entrega").
const ROUTE_TARGET_SECONDS: float = 240.0
## Distance from the very start that only gets Straight/SpeedBump/Hill/
## Tunnel -- segments that don't need steering input to survive. Below this
## length the plan never picks a hard segment or a CurveSegment. It was
## 150 m; 100 still covers the runway below, and leaves room for the first
## leg's "something happens" before the approach to the first house (N-103). Same problem RouteStreamer's
## first_segment_script already solved for its own pool (a driver needs a
## second to get their bearings) -- this route needed a longer buffer, not
## just one segment, because test_vehicle_presentation.gd and
## test_dust_and_ambience.gd drive 90-100 physics ticks at full throttle
## with zero steering input to check headlights/dust, and caught it when a
## single straight segment wasn't enough runway.
const SAFE_START_LENGTH: float = 100.0
const SHARP_CURVE_DEG: float = 45.0
## MudSegment (N-108) is rare: a fraction of an ordinary segment's odds, at
## most one per route, and it counts as a hard segment (a moment for the
## pacing, never in the calm approach to a house, never back to back with
## another hard one).
const MUD_WEIGHT: float = 0.2
## How long each leg aims to be for this many houses: the driving time left
## once every stop is paid for, shared out over the legs, in metres. Actual
## legs vary LEG_LENGTH_JITTER around it, and overshoot a little since a leg
## only ends once the segment that crosses its target finishes.
static func leg_target_length(houses: int) -> float:
	var driving_seconds: float = ROUTE_TARGET_SECONDS - houses * HOUSE_STOP_SECONDS
	return clampf(driving_seconds * ROUTE_CRUISE_SPEED / float(houses + 1), LEG_MIN_LENGTH, LEG_MAX_LENGTH)


## The whole spine, decided before anything is built, from its own stream
## off the session seed so every peer plans the same road (and a test can
## check hundreds of seeds without building one). Returns
## {"segments": [{"script", "turn_deg", "length", "leg", "start", "hard",
## "moment", "delivery_sign"}, ...], "house_distances": [...], "total"}.
##
## Rules: no repeat of the previous type; the first SAFE_START_LENGTH metres
## easy and straight; never two hard segments in a row; at most
## MAX_STRAIGHT_STREAK segments without a bend; something happening at least
## every MOMENT_SPACING metres (a house stop counts); a calm last QUIET_ZONE
## metres before every house; and hard segments getting likelier from the
## first house to the last, on the same curve as Endless
## (RouteStreamer.hard_weight_at()) stretched over this delivery's length.
static func plan_spine(session_seed: int, houses: int, avoid_tunnel_at_start: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([session_seed, &"route_spine"])
	# Not a const: GDScript can't fold an array of global class_names.
	var pool: Array[Script] = [
		StraightSegment, SpeedBumpSegment, ChicaneSegment, NarrowBridgeSegment,
		SCurveSegment, GravelSegment, ConstructionZoneSegment,
		CurveSegment, CurveSegment,  # weighted up: this is the one that turns
		HillSegment, TunnelSegment, RailCrossingSegment, MudSegment,
	]
	# Same "needs real steering/braking" set RouteStreamer uses, plus the
	# rail crossing. CurveSegment isn't on it: turning is what driving here
	# is; only a sharp bend counts as a moment.
	var hard: Array[Script] = [ChicaneSegment, NarrowBridgeSegment, SCurveSegment, GravelSegment,
			ConstructionZoneSegment, RailCrossingSegment, MudSegment]
	var leg_length_target: float = leg_target_length(houses)
	var planned_total: float = leg_length_target * (houses + 1)
	var state := {"distance": 0.0, "heading": 0.0, "last": null, "straight_streak": 0, "since_moment": 0.0,
			"after_house": false, "mud_placed": false}
	var segments: Array[Dictionary] = []
	var stops: Array[float] = []
	for leg: int in range(houses + 1):
		var jitter: float = rng.randf_range(1.0 - LEG_LENGTH_JITTER, 1.0 + LEG_LENGTH_JITTER)
		var target: float = clampf(leg_length_target * jitter, LEG_MIN_LENGTH, LEG_MAX_LENGTH)
		var to_house: bool = leg < houses
		# The last leg ends at the goal, not at a house: no warning sign.
		var sign_placed: bool = not to_house
		var leg_length: float = 0.0
		while leg_length < target:
			var remaining: float = target - leg_length
			# Whatever comes now could reach into the last QUIET_ZONE metres
			# (a leg ends once the segment crossing its target finishes). The
			# goal's leg is calm at its end too: the base's lot is levelled
			# ground with nothing to cross (a river, a rail, a tunnel), N-116.
			var quiet: bool = remaining <= QUIET_ZONE + MAX_SEGMENT_LENGTH
			# Something has to happen now if one more uneventful segment could
			# leave MOMENT_SPACING without anything, or if what's left before
			# the house (the calm approach included) would.
			var since: float = state.since_moment
			var gap_ahead: bool = since + MAX_SEGMENT_LENGTH > MOMENT_SPACING
			var near_house: bool = remaining <= QUIET_ZONE + 2.0 * MAX_SEGMENT_LENGTH
			var calm_approach_too_long: bool = near_house and since + remaining + MAX_SEGMENT_LENGTH > MOMENT_SPACING
			var must_move: bool = not quiet and (gap_ahead or calm_approach_too_long)
			var progress: float = clampf(float(state.distance) / planned_total, 0.0, 1.0)
			var hard_weight: float = lerpf(RouteStreamer.HARD_WEIGHT_START, RouteStreamer.HARD_WEIGHT_END, progress)
			var script: Script = _plan_pick(rng, pool, hard, state, quiet, must_move, hard_weight,
					avoid_tunnel_at_start)
			var turn: float = _plan_turn(rng, state.heading, quiet, must_move) if script == CurveSegment else 0.0
			var length: float
			if script == CurveSegment:
				length = CurveSegment.length_for_turn(turn)
			else:
				length = _segment_length(script)
			var is_hard: bool = hard.has(script)
			var entry := {
				"script": script, "turn_deg": turn, "length": length, "leg": leg,
				"start": state.distance, "hard": is_hard,
				"moment": is_hard or (script == CurveSegment and absf(turn) >= SHARP_CURVE_DEG),
				# "Entrega adelante" lands on whichever segment covers the last
				# DELIVERY_SIGN_LEAD metres before the house.
				"delivery_sign": not sign_placed and leg_length + length >= target - DELIVERY_SIGN_LEAD,
			}
			sign_placed = sign_placed or entry.delivery_sign
			segments.append(entry)
			leg_length += length
			state.distance += length
			state.heading += turn
			state.since_moment = 0.0 if entry.moment else float(state.since_moment) + length
			state.last = script
			state.mud_placed = bool(state.mud_placed) or script == MudSegment
			state.after_house = false
			state.straight_streak = 0 if script == CurveSegment else int(state.straight_streak) + 1
		if to_house:
			stops.append(state.distance)
			state.since_moment = 0.0
			state.after_house = true
	return {"segments": segments, "house_distances": stops, "total": state.distance}


static func _plan_pick(rng: RandomNumberGenerator, pool: Array[Script], hard: Array[Script], state: Dictionary,
		quiet: bool, must_move: bool, hard_weight: float, avoid_tunnel_at_start: bool) -> Script:
	var candidates: Array[Script] = pool.duplicate()
	var rules: Array[Callable] = []
	if quiet:
		rules.append(func(s: Script) -> bool: return s == StraightSegment or s == CurveSegment)
	if float(state.distance) < SAFE_START_LENGTH:
		rules.append(func(s: Script) -> bool: return not hard.has(s) and s != CurveSegment)
	# Nor a tunnel mouth right in front of the depot's door: its portal would
	# stand against the forecourt and wall off the view of the building. Nor a
	# hill: the yard's flat zone (route_terrain.gd) squeezed its first 12 m
	# into a 0 -> 27 % ramp right where the truck reaches ~15 m/s out of the
	# depot, and it pitched hard enough to throw loose cargo (#170).
	if avoid_tunnel_at_start and float(state.distance) < 1.0:
		rules.append(func(s: Script) -> bool: return s != TunnelSegment and s != HillSegment)
	# Nor right past a house: the portal stood against its yard and hid it.
	if bool(state.after_house):
		rules.append(func(s: Script) -> bool: return s != TunnelSegment)
	# One mud pit per delivery is plenty.
	if bool(state.mud_placed):
		rules.append(func(s: Script) -> bool: return s != MudSegment)
	var last: Script = state.last
	if last != null:
		rules.append(func(s: Script) -> bool: return s != last)
		if hard.has(last):
			rules.append(func(s: Script) -> bool: return not hard.has(s))
	if must_move:
		rules.append(func(s: Script) -> bool: return hard.has(s) or s == CurveSegment)
	elif int(state.straight_streak) >= MAX_STRAIGHT_STREAK:
		rules.append(func(s: Script) -> bool: return s == CurveSegment)
	# In order of importance: a rule that would leave nothing is skipped.
	for rule: Callable in rules:
		var kept: Array[Script] = candidates.filter(rule)
		if not kept.is_empty():
			candidates = kept
	var total: float = 0.0
	for script: Script in candidates:
		total += _pick_weight(script, hard, hard_weight)
	var roll: float = rng.randf() * total
	for script: Script in candidates:
		roll -= _pick_weight(script, hard, hard_weight)
		if roll <= 0.0:
			return script
	return candidates[-1]


static func _pick_weight(script: Script, hard: Array[Script], hard_weight: float) -> float:
	if script == MudSegment:
		return MUD_WEIGHT
	return hard_weight if hard.has(script) else 1.0


## A bend's angle in degrees: gentle on a house's approach, sharp when it's
## the moment the pacing asked for. It turns back the other way rather than
## head more than MAX_HEADING_DEG off the start's -Z, so the road can never
## come round and cross itself.
static func _plan_turn(rng: RandomNumberGenerator, heading: float, gentle: bool, sharp: bool) -> float:
	var sign_: float = -1.0 if rng.randf() < 0.5 else 1.0
	var smallest: float = SHARP_CURVE_DEG if sharp else CURVE_TURN_MIN_DEG
	var largest: float = GENTLE_CURVE_DEG if gentle else CURVE_TURN_MAX_DEG
	var turn: float = sign_ * rng.randf_range(smallest, largest)
	if absf(heading + turn) > MAX_HEADING_DEG:
		turn = -turn
	return clampf(turn, -MAX_HEADING_DEG - heading, MAX_HEADING_DEG - heading)


static func _segment_length(script: Script) -> float:
	var probe := script.new() as RouteSegment
	var length: float = probe.length
	probe.free()
	return length


## Players minus the driver, but never under MIN_CREW_HOUSES: with one house
## a solo run (the first thing a newcomer plays) was the emptiest route in
## the game, 1400 m with a single stop (N-119).
static func crew_house_count(player_count: int) -> int:
	return maxi(player_count - 1, MIN_CREW_HOUSES)
