class_name RoadImpacts
extends RefCounted
## The bumps the road announces (N-117, Fragile's "Amortiguá"): a segment that
## has one lists where it hits in announced_impacts() and joins the
## GROUP; this finds the next one ahead of a box, so the host can tell the
## trap "a bump in 0.5 s" and the box can show it.
##
## Simulation only, no presentation. A bump the road doesn't list (a crash
## into a block, a train) is not announced and cannot be softened.

## Segments with something to announce (RouteSegment._ready() adds them).
const GROUP: StringName = &"announced_impacts"
## Slower than this there is no direction to look along (m/s).
const MIN_SPEED: float = 1.5
## How far off the line of travel a bump still counts, m (the road is 12 m
## wide and the bump spans it).
const LATERAL_REACH: float = 8.0
## Just past the bump still counts as on it, so a tick that steps over the
## exact point doesn't skip it (a truck moves under 0.3 m per tick).
const PASSED_MARGIN: float = 0.5


## The nearest announced impact ahead of `from` along `velocity`, within
## `max_seconds`: {id: int, eta: seconds (0 once on it), distance: metres,
## negative once past}. Empty when there is none.
static func nearest_ahead(tree: SceneTree, from: Vector3, velocity: Vector3, max_seconds: float) -> Dictionary:
	var heading := Vector3(velocity.x, 0.0, velocity.z)
	var speed: float = heading.length()
	if tree == null or speed < MIN_SPEED:
		return {}
	heading /= speed
	var best: Dictionary = {}
	for node: Node in tree.get_nodes_in_group(GROUP):
		var segment := node as Node3D
		if segment == null or not segment.has_method(&"announced_impacts"):
			continue
		var points: Array = segment.call(&"announced_impacts")
		for index: int in range(points.size()):
			var offset: Vector3 = segment.to_global(points[index] as Vector3) - from
			offset.y = 0.0
			var along: float = offset.dot(heading)
			if along < -PASSED_MARGIN or (offset - heading * along).length() > LATERAL_REACH:
				continue
			var eta: float = maxf(along, 0.0) / speed
			if eta > max_seconds or (not best.is_empty() and along >= float(best["distance"])):
				continue
			best = {"id": segment.get_instance_id() * 16 + index, "eta": eta, "distance": along}
	return best
