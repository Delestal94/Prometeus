extends RefCounted
## Nearest-point lookups over the road route.gd built: how far along it a point is, how far from
## it, which leg it is on (N-223). route.gd owns the arrays (tests read `_path_points` and
## `_progress_samples` from the route) and hands this object the very same ones, so when route.gd
## lifts the points onto the finished terrain this sees it at once; the answers here are plain
## functions of local positions (route space), the route converts world positions.

## How many path points either side of the last hit the nearest-path lookups
## check before falling back to a full scan (N-223): path points are ~10 m
## apart and a tick moves the truck about a metre. The segment boundaries
## (samples, up to ~70 m apart) are not windowed: a hairpin can put
## a later stretch nearer than the truck's own boundaries, and there are few
## enough of them to scan every tick. The trust radius (2 x widest path gap,
## <= ~30 m) must stay under level_base's 42 m off-road limit, so a windowed
## hit never decides a ruin on its own.
const PATH_WINDOW: int = 4

## Denser than the samples (every ~10m along the actual, possibly curved, path instead of only at
## segment boundaries up to 60m apart) -- distance_from_path() needs this resolution, since a
## vehicle perfectly centered mid-segment on a long straight would otherwise read as tens of
## meters "off path" just from boundary sparsity, dangerously close to the safety net's own
## threshold. Shared with route.gd (`_path_points`).
var points: Array[Vector3]
## [{"cumulative": float, "position": Vector3, "leg_index": int}, ...] one entry per segment
## boundary, in build order -- the nearest one stands in for "how far along the road", instead of
## trusting local Z, which stopped meaning that the moment the road started bending. Shared with
## route.gd (`_progress_samples`).
var samples: Array[Dictionary]

## Metres along the road to each of `points`, worked out on first use.
var _distances := PackedFloat32Array()
## Where the last nearest-path-point lookups landed, so the next one (a tick later, the truck a
## metre further on) only looks around there instead of scanning the whole route. -1 = no hint yet.
var _hint: int = -1
var _hint_3d: int = -1
## `samples`' positions as a flat array for the lookup (built on first use, and again after
## route.gd moves them: invalidate_samples()), and the widest gap between path points: a windowed
## hit further than twice that is not trusted.
var _sample_points: Array[Vector3] = []
var _gap: float = -1.0


func _init(path_points: Array[Vector3], progress_samples: Array[Dictionary]) -> void:
	points = path_points
	samples = progress_samples


## Call after the samples' positions changed (the terrain lifted them).
func invalidate_samples() -> void:
	_sample_points.clear()


## Metres along the road to each of the path points.
func cumulative() -> PackedFloat32Array:
	if _distances.size() != points.size():
		_distances.resize(points.size())
		var total: float = 0.0
		for index: int in range(points.size()):
			if index > 0:
				total += points[index].distance_to(points[index - 1])
			_distances[index] = total
	return _distances


## Metres along the road from the start to the path point nearest `local_position`. Resolution is
## the points' ~10 m.
func road_distance(local_position: Vector3) -> float:
	var distances: PackedFloat32Array = cumulative()
	if distances.is_empty():
		return 0.0
	_hint = nearest_index(points, local_position, true, [_hint, PATH_WINDOW, _gap_size()])
	return distances[_hint]


## Metres along the road to the path point nearest a stop (full scan: a stop is asked about rarely).
func stop_distance(stop: Vector3) -> float:
	var distances: PackedFloat32Array = cumulative()
	if distances.is_empty():
		return 0.0
	return distances[nearest_index(points, stop, true)]


## The whole road's length along the path points (0 with no path).
func total_distance() -> float:
	var distances: PackedFloat32Array = cumulative()
	return 0.0 if distances.is_empty() else distances[-1]


## Nearest-boundary lookup rather than exact arc-length math: with segment
## boundaries every ~10-60m, the error this introduces is well under a
## segment's own length -- plenty for a HUD "distance remaining" readout,
## not something gameplay-critical reads.
func nearest_sample(local_position: Vector3) -> Dictionary:
	if samples.is_empty():
		return {}
	if _sample_points.size() != samples.size():
		_sample_points.clear()
		for sample: Dictionary in samples:
			_sample_points.append(sample["position"])
	return samples[nearest_index(_sample_points, local_position, false)]


## How far `local_position` is from the nearest known point on the actual generated path --
## level_base.gd's "you left the route" safety net used to just check abs(world x) > 42, which only
## worked because the old road never left world x~0. A curving road drifts the asphalt itself well
## past that on a wide turn while the vehicle is still perfectly on it, so the safety net needed to
## start measuring distance from the real path instead of from a world axis that stopped meaning
## anything once the road bent.
func distance_from_path(local_position: Vector3) -> float:
	if points.is_empty():
		return INF
	# A truck blown to NaN is off the road (the old full scan answered INF).
	if not local_position.is_finite():
		return INF
	_hint_3d = nearest_index(points, local_position, false, [_hint_3d, PATH_WINDOW, _gap_size()])
	return points[_hint_3d].distance_to(local_position)


## Same result as scanning every point (the first one wins a tie), but when
## `window` has a hint (where the last lookup landed), only the `radius` points
## either side of it are looked at first. The windowed answer is trusted only
## if it isn't at the window's edge (the road may go on getting closer beyond
## it) and isn't further than twice the widest gap between neighbours (a jump:
## teleport, restart, a house's position); otherwise the whole array is
## scanned. `planar` measures on the ground plane only. `window` is
## [hint, radius, widest gap between neighbours], empty for a full scan.
static func nearest_index(candidates: Array[Vector3], query: Vector3, planar: bool, window: Array = []) -> int:
	var count: int = candidates.size()
	if count == 0:
		return 0
	var hint: int = int(window[0]) if not window.is_empty() else -1
	var radius: int = int(window[1]) if not window.is_empty() else 0
	var gap: float = float(window[2]) if not window.is_empty() else 0.0
	var low: int = 0
	var high: int = count - 1
	if hint >= 0 and hint < count:
		low = maxi(0, hint - radius)
		high = mini(count - 1, hint + radius)
	var nearest: int = low
	var best: float = INF
	for index: int in range(low, high + 1):
		var gap_squared: float = _gap_squared(candidates[index], query, planar)
		if gap_squared < best:
			best = gap_squared
			nearest = index
	var windowed: bool = low > 0 or high < count - 1
	var at_edge: bool = (nearest == low and low > 0) or (nearest == high and high < count - 1)
	if windowed and (at_edge or best > 4.0 * gap * gap):
		return nearest_index(candidates, query, planar)
	return nearest


static func _gap_squared(point: Vector3, query: Vector3, planar: bool) -> float:
	if planar:
		return Vector2(point.x - query.x, point.z - query.z).length_squared()
	return point.distance_squared_to(query)


## Widest distance between consecutive points, to size "close enough to trust".
static func _widest_gap(candidates: Array[Vector3]) -> float:
	var widest: float = 1.0
	for index: int in range(1, candidates.size()):
		widest = maxf(widest, candidates[index].distance_to(candidates[index - 1]))
	return widest


func _gap_size() -> float:
	if _gap < 0.0:
		_gap = _widest_gap(points)
	return _gap
