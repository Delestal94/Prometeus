class_name CameraRail
extends RefCounted
## A camera move as data: 1 or more poses, each reached at a second, and the
## pose in between at any time. Pure (no nodes): the caller resolves its own
## spaces into world vectors first and puts the camera where pose_at() says.
##
## A point is {"at": Vector3, "look": Vector3, "t": seconds} plus, optionally,
## "up": Vector3 (Vector3.UP if missing) and "fov": degrees (kept from the
## point before if missing; DEFAULT_FOV if none says). Between points the
## position and the aim follow a Catmull-Rom curve through all of them, so a
## middle point is a control the camera passes by, not a stop; the time along
## the whole rail is eased once (`ease`), so the move starts and stops softly
## however many points it has. After the last point the camera holds there.
##
## Eases: "smooth" (in-out cubic, the default), "linear", "out" (a fast start
## that settles exponentially: a snap zoom) and "cut" (no travel: the pose
## jumps to the next point at its second).

const DEFAULT_FOV: float = 50.0
const EASES: Array[String] = ["smooth", "linear", "out", "cut"]


## {at, look, up, fov} at `time` seconds along `points` (sorted by "t").
static func pose_at(points: Array, time: float, ease_name: String = "smooth") -> Dictionary:
	if points.is_empty():
		return {"at": Vector3.ZERO, "look": Vector3.FORWARD, "up": Vector3.UP, "fov": DEFAULT_FOV}
	var count: int = points.size()
	var first: float = float(points[0].get("t", 0.0))
	var last: float = float(points[count - 1].get("t", 0.0))
	if count == 1 or time <= first:
		return _pose(points, 0, 0, 0.0)
	if time >= last:
		return _pose(points, count - 1, count - 1, 0.0)
	var length: float = maxf(last - first, 0.0001)
	var eased: float = first + eased_fraction((time - first) / length, ease_name) * length
	var index: int = 0
	while index < count - 2 and eased > float(points[index + 1].get("t", 0.0)):
		index += 1
	var start: float = float(points[index].get("t", 0.0))
	var end: float = float(points[index + 1].get("t", 0.0))
	if ease_name == "cut":
		return _pose(points, index, index, 0.0)
	var u: float = clampf((eased - start) / maxf(end - start, 0.0001), 0.0, 1.0)
	return _pose(points, index, index + 1, u)


## The second the rail reaches its last point.
static func length(points: Array) -> float:
	return float(points[-1].get("t", 0.0)) if not points.is_empty() else 0.0


## 0..1 of the way along a move after `fraction` (0..1) of its time.
static func eased_fraction(fraction: float, ease_name: String) -> float:
	var x: float = clampf(fraction, 0.0, 1.0)
	match ease_name:
		"linear", "cut":
			return x
		"out":
			return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


static func _pose(points: Array, from: int, to: int, u: float) -> Dictionary:
	var count: int = points.size()
	var before: int = maxi(from - 1, 0)
	var after: int = mini(to + 1, count - 1)
	var pose: Dictionary = {}
	for key: String in ["at", "look"]:
		pose[key] = catmull(_vector(points[before], key), _vector(points[from], key),
				_vector(points[to], key), _vector(points[after], key), u)
	var up_from: Vector3 = _vector(points[from], "up", Vector3.UP)
	var up_to: Vector3 = _vector(points[to], "up", Vector3.UP)
	var up: Vector3 = up_from.lerp(up_to, u)
	pose["up"] = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	pose["fov"] = lerpf(_fov(points, from), _fov(points, to), u)
	return pose


## The field of view at a point: its own, or the last one said before it.
static func _fov(points: Array, index: int) -> float:
	for back: int in range(index, -1, -1):
		if (points[back] as Dictionary).has("fov"):
			return float(points[back]["fov"])
	return DEFAULT_FOV


static func _vector(point: Dictionary, key: String, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var value: Variant = point.get(key, fallback)
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


static func catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
