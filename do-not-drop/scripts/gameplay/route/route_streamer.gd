extends Node3D
class_name RouteStreamer
## Base technical piece for Fase 3: instances RouteSegments ahead of a
## tracked node and frees them once they're well behind it, so the world
## never needs to exist all at once.
##
## Segments are chained with a Transform3D cursor, the same way route.gd
## lays out a delivery (tareas de Nacho N-206): each one is built where the
## previous one left the road, so a CurveSegment really turns it. Everything
## that used to be "how far down -Z" is now "how far along the road": the
## lookahead, the culling behind, the deer crossings' spacing and the
## difficulty ramp. distance_along() and distance_from_path() answer those
## for anyone else (level_endless.gd's distance and "off the road" check).
##
## Combination rules (kept deliberately simple): never repeat the same
## segment type twice in a row, no three hard ones in a row, a bend at least
## every MAX_STRAIGHT_STREAK segments when the pool has one, and a heading
## never more than MAX_HEADING_DEG off the start's -Z -- so the road always
## advances down -Z and can never come back across itself.

@export var segment_scripts: Array[Script] = [
	StraightSegment, SpeedBumpSegment, ChicaneSegment, NarrowBridgeSegment,
	SCurveSegment, GravelSegment, ConstructionZoneSegment, TunnelSegment,
	CurveSegment, CurveSegment,  # weighted up: this is the one that turns
]
## "Hard" = needs real steering/braking to survive, matching exactly what
## the tests already treat as unsafe for an un-steered drive (see
## test_level_endless.gd/test_endless_multi_cargo.gd restricting themselves
## to Straight/SpeedBump) -- not a separate, arbitrary judgment call.
## docs/tareas-nacho.md #47: avoid three of these back to back, since the
## pool grew to 7 types and that got a lot more likely to happen by chance.
## Built in _ready(), not as a top-level const -- GDScript can't fold a
## const array referencing several global class_names at parse time (hit
## "Assigned value... isn't a constant expression"), so this is a plain
## @onready-style var populated once instead.
var hard_segments: Array[Script] = []
## Road kept built ahead of / behind the target, in metres along the road.
@export var lookahead_distance: float = 60.0
@export var behind_keep_distance: float = 40.0
## The very first segment ignores the random pick and is always this one
## (default: plain Straight) -- found the hard way while wiring this up to
## a real vehicle for the first time: a chicane or narrow bridge picked as
## segment #1 throws an obstacle at a driver who hasn't even had a second
## to get their bearings yet. Null disables this and goes fully random from
## the start, if a test genuinely needs that.
@export var first_segment_script: Script = StraightSegment

## Same limits as route.gd: past 90 degrees off -Z a run of same-way bends
## would bring the road back onto itself.
const MAX_HEADING_DEG: float = 80.0
const CURVE_TURN_MIN_DEG: float = 25.0
const CURVE_TURN_MAX_DEG: float = 70.0
const MAX_STRAIGHT_STREAK: int = 3
## Spacing of the road's centre-line samples (see _path).
const SAMPLE_SPACING: float = 10.0

var target: Node3D = null

var _active: Array[RouteSegment] = []
## Where the next segment starts: the pose (this node's space) and how far
## along the road that is.
var _cursor: Transform3D = Transform3D.IDENTITY
var _next_distance: float = 0.0
var _heading_deg: float = 0.0
var _last_script: Script = null
var _hard_streak: int = 0
var _straight_streak: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Tracks "has anything ever spawned", separately from _active.is_empty() --
## _active shrinks as segments get culled behind, so it stops meaning
## "nothing has spawned yet" well before the run is actually over.
var _spawned_any: bool = false
## Names every segment the same on every peer (see route.gd): RPCs find a
## RailCrossingSegment by its path.
var _spawn_count: int = 0
## The live road's centre line, [{"position": Vector3 (this node's space),
## "distance": float}, ...] in order, every ~SAMPLE_SPACING metres, for the
## segments still alive.
var _path: Array[Dictionary] = []
## How far along the road the target is, as last worked out.
var _target_distance: float = 0.0


func _ready() -> void:
	# One seed per session, not per machine: see NetworkManager.world_seed.
	# Solo play leaves it at 0, which still means "a different route every
	# time you press play".
	var session_seed: int = _session_seed()
	if session_seed != 0:
		_rng.seed = session_seed
	else:
		_rng.randomize()
	hard_segments = [ChicaneSegment, NarrowBridgeSegment, SCurveSegment, GravelSegment, ConstructionZoneSegment]
	var sky := RouteSky.new()
	sky.name = "Sky"
	add_child(sky)


func start(tracked: Node3D) -> void:
	target = tracked
	_fill_ahead()


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	_fill_ahead()
	_cull_behind()


## Metres along the road to the point on it nearest `world_position` (0 for
## anything before the start, like the depot).
func distance_along(world_position: Vector3) -> float:
	return float(_nearest_on_path(to_local(world_position)).distance)


## How far `world_position` is from the road's centre line, flat (x/z).
func distance_from_path(world_position: Vector3) -> float:
	var local: Vector3 = to_local(world_position)
	var nearest: Vector3 = _nearest_on_path(local).position
	return Vector2(local.x - nearest.x, local.z - nearest.z).length()


## The road's centre `distance` metres along it, in world space (clamped to
## the road that exists).
func point_at(distance: float) -> Vector3:
	if _path.is_empty():
		return global_position
	for index: int in range(1, _path.size()):
		var a: Dictionary = _path[index - 1]
		var b: Dictionary = _path[index]
		if float(b.distance) >= distance:
			var span: float = maxf(float(b.distance) - float(a.distance), 0.001)
			return to_global((a.position as Vector3).lerp(b.position, clampf((distance - float(a.distance)) / span, 0.0, 1.0)))
	return to_global(_path[-1].position)


func _fill_ahead() -> void:
	_target_distance = distance_along(target.global_position) if not _path.is_empty() else 0.0
	while _active.is_empty() or _next_distance < _target_distance + lookahead_distance:
		_spawn_next()


func _spawn_next() -> void:
	var script: Script = first_segment_script if (first_segment_script != null and not _spawned_any) else _pick_next_script()
	_spawned_any = true
	var segment: RouteSegment
	if script == CurveSegment:
		var curve := CurveSegment.new()
		curve.turn_deg = _next_turn()
		segment = curve
	else:
		segment = script.new()
	segment.transform = _cursor
	segment.name = "Segment%d" % _spawn_count
	segment.set_meta(&"route_distance", _next_distance)
	_spawn_count += 1
	add_child(segment)
	_active.append(segment)
	_record_path(segment)
	_maybe_add_crossing(segment)
	_next_distance += segment.length
	segment.set_meta(&"route_end", _next_distance)
	_cursor = _cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset)
	_heading_deg += rad_to_deg(segment.exit_turn)
	_last_script = script
	_hard_streak = _hard_streak + 1 if hard_segments.has(script) else 0
	_straight_streak = 0 if script == CurveSegment else _straight_streak + 1


## A bend's angle: turns back the other way rather than head more than
## MAX_HEADING_DEG off -Z (same draws either way, so every peer agrees).
func _next_turn() -> float:
	var sign_: float = -1.0 if _rng.randf() < 0.5 else 1.0
	var turn: float = sign_ * _rng.randf_range(CURVE_TURN_MIN_DEG, CURVE_TURN_MAX_DEG)
	if absf(_heading_deg + turn) > MAX_HEADING_DEG:
		turn = -turn
	return clampf(turn, -MAX_HEADING_DEG - _heading_deg, MAX_HEADING_DEG - _heading_deg)


## Adds a just-built segment's centre line to _path.
func _record_path(segment: RouteSegment) -> void:
	var slots: Array[Transform3D] = segment.get_dressing_slots(SAMPLE_SPACING)
	slots.append(Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset))
	var distance: float = _next_distance
	var previous: Vector3 = segment.transform * slots[0].origin
	for slot: Transform3D in slots:
		var at: Vector3 = segment.transform * slot.origin
		distance += at.distance_to(previous)
		previous = at
		if not _path.is_empty() and (_path[-1].position as Vector3).distance_to(at) < 0.01:
			continue
		_path.append({"position": at, "distance": distance})


## The point on the live road nearest `local` (this node's space), and how
## far along the road it is.
func _nearest_on_path(local: Vector3) -> Dictionary:
	if _path.is_empty():
		return {"position": Vector3.ZERO, "distance": 0.0}
	var flat := Vector2(local.x, local.z)
	var best: Dictionary = {"position": _path[0].position, "distance": _path[0].distance}
	var best_gap: float = INF
	for index: int in range(maxi(_path.size() - 1, 1)):
		var a: Dictionary = _path[index]
		var b: Dictionary = _path[mini(index + 1, _path.size() - 1)]
		var a2 := Vector2((a.position as Vector3).x, (a.position as Vector3).z)
		var b2 := Vector2((b.position as Vector3).x, (b.position as Vector3).z)
		var span: Vector2 = b2 - a2
		var t: float = clampf((flat - a2).dot(span) / maxf(span.length_squared(), 0.0001), 0.0, 1.0)
		var on: Vector2 = a2 + span * t
		var gap: float = flat.distance_squared_to(on)
		if gap < best_gap:
			best_gap = gap
			best = {"position": (a.position as Vector3).lerp(b.position, t), "distance": lerpf(float(a.distance), float(b.distance), t)}
	return best


## Endless mode's deer crossings: same odds for every peer (the streamer's
## RNG is seeded from the session seed), never in the first stretch, and
## spaced out so they stay a surprise.
const CROSSING_CHANCE: float = 0.12
const CROSSING_MIN_GAP: float = 300.0
const CROSSING_FIRST_AT: float = 120.0
var _last_crossing_distance: float = -INF


func _maybe_add_crossing(segment: RouteSegment) -> void:
	var roll: float = _rng.randf()
	var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
	if not segment is StraightSegment or _next_distance < CROSSING_FIRST_AT:
		return
	if _next_distance - _last_crossing_distance < CROSSING_MIN_GAP or roll > CROSSING_CHANCE:
		return
	var crossing := WildlifeCrossing.new()
	crossing.name = "DeerCrossing"
	crossing.side = side
	crossing.with_sign = true
	crossing.position = Vector3(0.0, 0.0, -segment.length * 0.5)
	segment.add_child(crossing)
	_last_crossing_distance = _next_distance


## Endless difficulty ramp (docs/tareas-nacho.md #49): hard segments start
## at a quarter of the odds of an easy one and reach 2.5x the odds by
## DIFFICULTY_RAMP_METERS, so the first minutes teach and the long run tests.
## The no-repeat and no-three-hard-in-a-row rules still apply on top.
const HARD_WEIGHT_START: float = 0.25
const HARD_WEIGHT_END: float = 2.5
const DIFFICULTY_RAMP_METERS: float = 2000.0


func hard_weight_at(distance: float) -> float:
	return lerpf(HARD_WEIGHT_START, HARD_WEIGHT_END, clampf(distance / DIFFICULTY_RAMP_METERS, 0.0, 1.0))


func _pick_next_script() -> Script:
	var candidates: Array[Script] = segment_scripts
	if segment_scripts.size() > 1 and _last_script != null:
		candidates = candidates.filter(func(s: Script) -> bool: return s != _last_script)
	if _hard_streak >= 2:
		# Two hard segments back to back already -- force a breather instead
		# of risking a third, unless the pool genuinely has nothing easy left.
		var easy_candidates: Array[Script] = candidates.filter(func(s: Script) -> bool: return not hard_segments.has(s))
		if not easy_candidates.is_empty():
			candidates = easy_candidates
	if _straight_streak >= MAX_STRAIGHT_STREAK and candidates.has(CurveSegment):
		candidates = [CurveSegment]
	var hard_weight: float = hard_weight_at(_next_distance)
	var total: float = 0.0
	for script: Script in candidates:
		total += hard_weight if hard_segments.has(script) else 1.0
	var roll: float = _rng.randf() * total
	for script: Script in candidates:
		roll -= hard_weight if hard_segments.has(script) else 1.0
		if roll <= 0.0:
			return script
	return candidates[-1]


func _cull_behind() -> void:
	for segment: RouteSegment in _active.duplicate():
		if float(segment.get_meta(&"route_end", 0.0)) < _target_distance - behind_keep_distance:
			_active.erase(segment)
			segment.queue_free()
	# Its stretch of centre line goes with it (keeping the point where the
	# live road begins).
	var first_alive: float = float(_active[0].get_meta(&"route_distance", 0.0)) if not _active.is_empty() else _next_distance
	while _path.size() > 2 and float(_path[1].distance) <= first_alive:
		_path.pop_front()


## Looked up by node path rather than by the NetworkManager identifier on
## purpose. A test that names this script's class_name compiles it before
## the autoloads exist, and a bare `NetworkManager.world_seed` is a compile
## error at that point -- the same node-path pattern the rest of the project
## already uses for EventBus.
func _session_seed() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return int(network.get(&"world_seed")) if network != null else 0
