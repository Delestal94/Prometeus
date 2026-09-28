extends Node
## Keeps the local player where the world is built (playtest 2026-09-28:
## walking out past the depot's yard, or away from the route, showed the
## void beyond the terrain). Before the run: the depot and a yard in front of
## its door. On the road: a leash around the truck, long enough for any door
## on the route. Each peer keeps its own player in -- the player's position
## is client-authoritative -- and says why when it stops them.

const DepotLayout = preload("res://scripts/gameplay/depot/depot_layout.gd")
## Metres of yard in front of the depot door that are still walkable.
const YARD_APRON: float = 10.0
## Metres from the truck a player on foot can go during the run.
const LEASH_RADIUS: float = 30.0
## Room kept off the depot's inner walls, so the clamp never pins you in one.
const WALL_CLEARANCE: float = 0.6
const NOTICE_COOLDOWN: float = 4.0

## The level (level_common.gd): its local_player, vehicle and depot.
var level: Node
var _notice_left: float = 0.0


func _physics_process(delta: float) -> void:
	_notice_left = maxf(0.0, _notice_left - delta)
	var player := level.get(&"local_player") as CharacterBody3D
	if not is_instance_valid(player) or not String(player.get(&"seat_node_path")).is_empty():
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
			bus.emit_signal(&"depot_notice", "No te alejes del camión" if _run_started() else "Quedate en el depósito")


## `point` moved back inside the play area (unchanged if already inside).
func keep_inside(point: Vector3) -> Vector3:
	if not _run_started():
		var depot := level.get(&"depot") as Node3D
		if depot == null:
			return point
		var local: Vector3 = depot.to_local(point)
		local.x = clampf(local.x, -DepotLayout.HALF_WIDTH + WALL_CLEARANCE, DepotLayout.HALF_WIDTH - WALL_CLEARANCE)
		local.z = clampf(local.z, -YARD_APRON, DepotLayout.DEPTH - WALL_CLEARANCE)
		var back: Vector3 = depot.to_global(local)
		return Vector3(back.x, point.y, back.z)
	var vehicle := level.get(&"vehicle") as Node3D
	if vehicle == null:
		return point
	var offset := Vector2(point.x - vehicle.global_position.x, point.z - vehicle.global_position.z)
	if offset.length() <= LEASH_RADIUS:
		return point
	offset = offset.limit_length(LEASH_RADIUS)
	return Vector3(vehicle.global_position.x + offset.x, point.y, vehicle.global_position.z + offset.y)


func _run_started() -> bool:
	var run: Node = get_node_or_null(^"/root/RunManager")
	return run != null and (bool(run.get(&"is_running")) or not (run.get(&"results") as Dictionary).is_empty())
