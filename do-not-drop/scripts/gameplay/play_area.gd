extends Node
## Keeps the local player off the edges of the built world (playtest
## 2026-09-28: walking far enough showed the void past the terrain). The
## terrain runs at least RouteTerrain.HALO (64 m) either side of the road and
## rises into a forest ridge from 38 m out, which hides the horizon; the
## player may go anywhere up to ROAD_REACH from the road -- on the ridge's
## slope, never on its crest -- plus the depot and its yard. No leash to the
## truck: the crew walks where it likes inside that. Each peer keeps its own
## player in (the player's position is client-authoritative) and says why.

const DepotLayout = preload("res://scripts/gameplay/depot/depot_layout.gd")
## Metres from the road's centre line a player on foot can go.
const ROAD_REACH: float = 45.0
## Metres of yard in front of the depot door that are always walkable.
const YARD_APRON: float = 10.0
## Room kept off the depot's inner walls, so the clamp never pins you in one.
const WALL_CLEARANCE: float = 0.6
const NOTICE_COOLDOWN: float = 4.0

## The level (level_common.gd): its local_player, depot and road (`route`,
## or `_streamer` in endless).
var level: Node
var _notice_left: float = 0.0


func _physics_process(delta: float) -> void:
	_notice_left = maxf(0.0, _notice_left - delta)
	# Read before casting: while the host reloads the level, a client's
	# player is despawned under a still-running old level.
	var found: Variant = level.get(&"local_player")
	if not is_instance_valid(found):
		return
	var player := found as CharacterBody3D
	if player == null or not String(player.get(&"seat_node_path")).is_empty():
		return
	var kept: Vector3 = keep_inside(player.global_position)
	if kept.is_equal_approx(player.global_position):
		return
	player.global_position = kept
	player.velocity = Vector3(0.0, player.velocity.y, 0.0)
	if _notice_left <= 0.0:
		_notice_left = NOTICE_COOLDOWN
		var bus: Node = get_node_or_null(^"/root/EventBus")
		if bus != null:
			bus.emit_signal(&"depot_notice", "No hay nada más allá: volvé hacia la ruta")


## `point` moved back inside the play area (unchanged if already inside).
func keep_inside(point: Vector3) -> Vector3:
	if _in_depot(point):
		return point
	var road: Variant = nearest_road_point(point)
	if road == null:
		return point
	var offset := Vector2(point.x - (road as Vector3).x, point.z - (road as Vector3).z)
	if offset.length() <= ROAD_REACH:
		return point
	offset = offset.limit_length(ROAD_REACH)
	return Vector3((road as Vector3).x + offset.x, point.y, (road as Vector3).z + offset.y)


## The closest point on the road's centre line (world space, flat), or null
## when this level has no road built yet.
func nearest_road_point(point: Vector3) -> Variant:
	var streamer: Node = level.get(&"_streamer") as Node
	if streamer != null and streamer.has_method(&"_nearest_on_path"):
		var local: Vector3 = (streamer as Node3D).to_local(point)
		var result: Dictionary = streamer.call(&"_nearest_on_path", local)
		return (streamer as Node3D).to_global(result.position) if result.has("position") else null
	var route: Node3D = level.get(&"route") as Node3D
	var terrain: Node3D = route.get(&"terrain") as Node3D if route != null else null
	if terrain == null:
		return null
	var flat: Vector3 = terrain.to_local(point)
	var p := Vector2(flat.x, flat.z)
	var best := Vector2.ZERO
	var best_distance: float = INF
	for span: Dictionary in terrain.get(&"spans"):
		var a: Vector2 = span.a
		var edge: Vector2 = (span.b as Vector2) - a
		var t: float = clampf((p - a).dot(edge) / maxf(edge.length_squared(), 0.001), 0.0, 1.0)
		var candidate: Vector2 = a + edge * t
		var distance: float = candidate.distance_squared_to(p)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	if best_distance == INF:
		return null
	return terrain.to_global(Vector3(best.x, flat.y, best.y))


func _in_depot(point: Vector3) -> bool:
	var depot := level.get(&"depot") as Node3D
	if depot == null:
		return false
	var local: Vector3 = depot.to_local(point)
	return absf(local.x) <= DepotLayout.HALF_WIDTH - WALL_CLEARANCE \
		and local.z >= -YARD_APRON and local.z <= DepotLayout.DEPTH - WALL_CLEARANCE
