class_name SegmentStreamer
extends Node3D
## Instances RouteSegments ahead of a tracked node and frees them once they
## are well behind it, so the world never needs to exist all at once.
## Portable module (docs/modulos.md): the game extends it to add its own
## segment types to the pools, seed it from its session and hang things off
## fresh segments (_on_segment_spawned).
##
## Segments are chained with a Transform3D cursor: each one is built where
## the previous one left the road, so a CurveSegment really turns it.
## Everything is measured "how far along the road": the lookahead, the
## culling behind, the difficulty ramp. distance_along() and
## distance_from_path() answer those for anyone else (a level's distance and
## "off the road" check).
##
## Combination rules (kept deliberately simple): never repeat the same
## segment type twice in a row, no three hard ones in a row, a bend at least
## every MAX_STRAIGHT_STREAK segments when the pool has one, and a heading
## never more than MAX_HEADING_DEG off the start's -Z -- so the road always
## advances down -Z and can never come back across itself.

## The pool a segment is drawn from. The game's subclass adds its own
## types; CurveSegment twice weights up the one that turns.
@export var segment_scripts: Array[Script] = [
	StraightSegment, SpeedBumpSegment, SCurveSegment, GravelSegment, CurveSegment, CurveSegment,
]
## "Hard" = needs real steering/braking to survive. Never three in a row.
@export var hard_segments: Array[Script] = [SCurveSegment, GravelSegment]
## Road kept built ahead of / behind the target, in metres along the road.
@export var lookahead_distance: float = 60.0
@export var behind_keep_distance: float = 40.0
## Merge each segment's static boxes (DressingBatcher), the tick after it
## spawns. Off only for benches that measure the unmerged parts.
@export var batch_geometry: bool = true
## The very first segment ignores the random pick and is always this one
## (default: plain Straight): an obstacle picked as segment #1 throws itself
## at a driver who hasn't had a second to get their bearings yet. Null goes
## fully random from the start, if a test genuinely needs that.
@export var first_segment_script: Script = StraightSegment

## Past this angle off -Z a run of same-way bends would bring the road back
## onto itself.
const MAX_HEADING_DEG: float = 80.0
const CURVE_TURN_MIN_DEG: float = 25.0
const CURVE_TURN_MAX_DEG: float = 70.0
const MAX_STRAIGHT_STREAK: int = 3
## Spacing of the road's centre-line samples (see _path).
const SAMPLE_SPACING: float = 10.0
## Spans either side of the last hit that _nearest_on_path() checks first, and
## how far (m) a hit may be for that window to be trusted over a full scan.
const NEAREST_WINDOW: int = 3
const NEAREST_TRUST: float = 4.0 * SAMPLE_SPACING
## Difficulty ramp: hard segments start at a quarter of the odds of an easy
## one and reach 2.5x the odds by DIFFICULTY_RAMP_METERS, so the first
## minutes teach and the long run tests. The no-repeat and no-three-hard-in-
## a-row rules still apply on top.
const HARD_WEIGHT_START: float = 0.25
const HARD_WEIGHT_END: float = 2.5
const DIFFICULTY_RAMP_METERS: float = 2000.0

var target: Node3D = null

var _active: Array[RouteSegment] = []
## Spawned segments whose geometry is not merged yet: one is merged per
## physics tick that spawned nothing, so building a segment and merging it
## (~4 and ~8 ms for the heavy ones) never land in the same tick (N-219).
var _unbatched: Array[RouteSegment] = []
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
## Names every segment the same on every peer: RPCs can find a segment by
## its path.
var _spawn_count: int = 0
## The live road's centre line, [{"position": Vector3 (this node's space),
## "distance": float}, ...] in order, every ~SAMPLE_SPACING metres, for the
## segments still alive.
var _path: Array[Dictionary] = []
## Bumped whenever _path changes, so a remembered lookup is not reused; the
## span the last lookup landed in (moved back as the old road is culled); the
## last point asked about and its answer (see _nearest_on_path()).
var _path_version: int = 0
var _nearest_hint: int = -1
var _memo_query: Vector3 = Vector3.INF
var _memo_version: int = -1
var _memo_result: Dictionary = {}
## How far along the road the target is, as last worked out.
var _target_distance: float = 0.0


func _ready() -> void:
	# One seed per session, not per machine. 0 still means "a different
	# route every time you press play".
	var session_seed: int = _session_seed()
	if session_seed != 0:
		_rng.seed = session_seed
	else:
		_rng.randomize()


func start(tracked: Node3D) -> void:
	target = tracked
	_fill_ahead()
	flush_batches()


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	var spawned_before: int = _spawn_count
	_fill_ahead()
	if _spawn_count == spawned_before:
		_batch_next()
	_cull_behind()


## Merges every segment still waiting for it, now (level start, tests).
func flush_batches() -> void:
	while not _unbatched.is_empty():
		_batch_next()


## Metres along the road to the point on it nearest `world_position` (0 for
## anything before the start).
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


## How far along the road the next segment starts.
func next_distance() -> float:
	return _next_distance


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
	_on_segment_spawned(segment)
	# Its static boxes get folded into one mesh per material (_batch_next):
	# unmerged, each spawn added some 500 nodes.
	if batch_geometry:
		_unbatched.append(segment)
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
		_path_version += 1


## The point on the live road nearest `local` (this node's space), and how
## far along the road it is. Asked several times a tick with the same point
## (the streamer, the level's progress, its out-of-bounds check), so the last
## answer is kept until the point or the road changes; and a new point is
## first looked for only around where the last one landed, falling back to
## the whole road at the window's edge or on a jump (respawn, far away), so
## the answer is always the one a full scan gives.
func _nearest_on_path(local: Vector3) -> Dictionary:
	if _path.is_empty():
		return {"position": Vector3.ZERO, "distance": 0.0}
	if _memo_version == _path_version and local == _memo_query:
		return _memo_result
	var flat := Vector2(local.x, local.z)
	var count: int = maxi(_path.size() - 1, 1)
	var low: int = 0
	var high: int = count - 1
	if _nearest_hint >= 0 and _nearest_hint < count:
		low = maxi(0, _nearest_hint - NEAREST_WINDOW)
		high = mini(count - 1, _nearest_hint + NEAREST_WINDOW)
	var best: Vector3 = _closest_span(flat, low, high)
	if (low > 0 or high < count - 1) \
			and (int(best.x) == low and low > 0 or int(best.x) == high and high < count - 1 \
			or best.y > NEAREST_TRUST * NEAREST_TRUST):
		best = _closest_span(flat, 0, count - 1)
	_nearest_hint = int(best.x)
	var a: Dictionary = _path[_nearest_hint]
	var b: Dictionary = _path[mini(_nearest_hint + 1, _path.size() - 1)]
	_memo_query = local
	_memo_version = _path_version
	_memo_result = {"position": (a.position as Vector3).lerp(b.position, best.z), "distance": lerpf(float(a.distance), float(b.distance), best.z)}
	return _memo_result


## The span between path[low] and path[high + 1] closest to `flat`, as
## Vector3(index, squared gap, t along the span); the first of equals wins.
func _closest_span(flat: Vector2, low: int, high: int) -> Vector3:
	var best := Vector3(low, INF, 0.0)
	for index: int in range(low, high + 1):
		var a_position: Vector3 = _path[index].position
		var b_position: Vector3 = _path[mini(index + 1, _path.size() - 1)].position
		var a2 := Vector2(a_position.x, a_position.z)
		var span := Vector2(b_position.x, b_position.z) - a2
		var t: float = clampf((flat - a2).dot(span) / maxf(span.length_squared(), 0.0001), 0.0, 1.0)
		var gap: float = flat.distance_squared_to(a2 + span * t)
		if gap < best.y:
			best = Vector3(index, gap, t)
	return best


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
	candidates = _limit_candidates(candidates)
	var hard_weight: float = hard_weight_at(_next_distance)
	var total: float = 0.0
	for script: Script in candidates:
		total += _pick_weight(script, hard_weight)
	var roll: float = _rng.randf() * total
	for script: Script in candidates:
		roll -= _pick_weight(script, hard_weight)
		if roll <= 0.0:
			return script
	return candidates[-1]


## Merges the oldest segment still waiting for it.
func _batch_next() -> void:
	if _unbatched.is_empty():
		return
	var segment: RouteSegment = _unbatched.pop_front()
	if is_instance_valid(segment) and not segment.is_queued_for_deletion():
		# Without a slicer it never waits for a frame: this stays one step.
		await DressingBatcher.merge_segment_geometry([segment])


func _cull_behind() -> void:
	for segment: RouteSegment in _active.duplicate():
		if float(segment.get_meta(&"route_end", 0.0)) < _target_distance - behind_keep_distance:
			_active.erase(segment)
			_unbatched.erase(segment)
			segment.queue_free()
	# Its stretch of centre line goes with it (keeping the point where the
	# live road begins).
	var first_alive: float = float(_active[0].get_meta(&"route_distance", 0.0)) if not _active.is_empty() else _next_distance
	while _path.size() > 2 and float(_path[1].distance) <= first_alive:
		_path.pop_front()
		_path_version += 1
		_nearest_hint = maxi(_nearest_hint - 1, -1)


# --- Hooks the game fills in ---------------------------------------------------

## The odds of a type in the draw: a hard one weighs `hard_weight` (the ramp
## at this distance), an easy one 1. The game overrides it for rarities.
func _pick_weight(script: Script, hard_weight: float) -> float:
	return hard_weight if hard_segments.has(script) else 1.0


## Last word on the candidates after the built-in rules (no repeat, no three
## hard in a row, the forced bend): the game takes out types that are not
## allowed yet (a rare one too soon after the last). Must not return an empty
## array; if nothing is left, return `candidates` as it came.
func _limit_candidates(candidates: Array[Script]) -> Array[Script]:
	return candidates


## The number every peer's road is built from; 0 randomizes.
func _session_seed() -> int:
	return 0


## A segment was just built and its centre line recorded, before its
## geometry is batched: hang crossings, signs or events off it here. The
## streamer's `_rng` is the one to draw from, so every peer agrees.
func _on_segment_spawned(_segment: RouteSegment) -> void:
	pass
