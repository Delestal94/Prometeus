extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_play_area.gd
##
## The player never reaches the edge of the built world
## (scripts/gameplay/play_area.gd, playtest 2026-09-28): anywhere within
## ROAD_REACH of the road, plus the depot and its yard, with a notice when
## they're stopped. No leash to the truck.

const PlayArea = preload("res://scripts/gameplay/play_area.gd")
const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")

var _failures: int = 0
var _notices: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	root.get_node("EventBus").depot_notice.connect(func(text: String) -> void: _notices.append(text))
	var area: PlayArea = level.get_node("PlayArea")
	_expect(PlayArea.ROAD_REACH < RouteTerrain.HALO - 10.0, "The reach stops well short of where the terrain ends")
	var depot: Node3D = level.depot
	var inside: Vector3 = depot.to_global(Vector3(0.0, 0.0, 12.0))
	_expect(area.keep_inside(inside).is_equal_approx(inside), "Inside the depot nothing moves")
	var road: Vector3 = level.route.call(&"point_at", 400.0) if level.route.has_method(&"point_at") \
		else level.vehicle.global_position
	var near_road: Vector3 = area.nearest_road_point(road)
	var side := Vector3(1.0, 0.0, 0.0)
	var walkable: Vector3 = near_road + side * (PlayArea.ROAD_REACH - 5.0)
	_expect(area.keep_inside(walkable).is_equal_approx(walkable), "Anywhere near the road is walkable, truck or not")
	var beyond: Vector3 = near_road + side * 200.0
	var kept: Vector3 = area.keep_inside(beyond)
	var reach: float = Vector2(kept.x - area.nearest_road_point(kept).x, kept.z - area.nearest_road_point(kept).z).length()
	_expect(reach <= PlayArea.ROAD_REACH + 0.5, "Walking off towards the map's edge stops at the reach (%.1f m)" % reach)
	var player: CharacterBody3D = level.local_player
	player.global_position = beyond
	for _i: int in 3:
		await physics_frame
	var nearest: Vector3 = area.nearest_road_point(player.global_position)
	_expect(Vector2(player.global_position.x - nearest.x, player.global_position.z - nearest.z).length()
			<= PlayArea.ROAD_REACH + 0.5, "The local player is kept in")
	_expect(not _notices.is_empty(), "...and told why")
	level.free()
	if _failures == 0:
		print("PASS: the player keeps within reach of the road and the depot, never at the map's edge")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
