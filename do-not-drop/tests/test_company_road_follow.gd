extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_road_follow.gd
##
## The company-day bot follows the GPS's route with the van (expansion D-0304.3, tests/bot_company_road.gd).
## - Pure: steer_toward() is proportional to the angle off the nose, -1..1, positive to the right, 0 straight
##   ahead and on a degenerate target; map_point() / world_point() are inverse; off_road_m() measures to the
##   route's center line; half_width() is the narrowest street's half on the route (RoadGraph, shed -> Centro).
## - The map: RoadNavigator.route() from the shed to Barrio Centro's entrance is ok and runs on streets 12 m wide.
## - In the company world (company_root.tscn, solo): the player takes the wheel of the fleet's van and the bot
##   drives it from the playon along that route to Centro's entrance: it gets there (within 12 m) and, once
##   on the road, never leaves it (OFF_ROAD 0: off_road_ticks == 0).

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_road_follow"
const BOT := preload("res://tests/bot_company_road.gd")
const CENTRO_IN: Vector2 = Vector2(256.0, 0.0)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	run.set(&"is_running", false)
	var graph: RoadGraph = RoadGraph.load_default()
	_check_pure(graph)
	await _check_world(graph)
	if _failures == 0:
		print("PASS: the bot steers for the route's waypoint and drives the van from the playon to Barrio Centro"
			+ " without leaving the road")
	quit(_failures)


func _check_pure(graph: RoadGraph) -> void:
	var at := Transform3D(Basis.IDENTITY, Vector3.ZERO)  # nose to -Z
	_expect(is_zero_approx(BOT.steer_toward(at, Vector3(0.0, 0.0, -20.0))), "Straight ahead: no steering")
	_expect(BOT.steer_toward(at, Vector3(10.0, 0.0, -10.0)) > 0.0, "A target to the right steers right (+)")
	_expect(BOT.steer_toward(at, Vector3(-10.0, 0.0, -10.0)) < 0.0, "...to the left steers left (-)")
	_expect(is_equal_approx(absf(BOT.steer_toward(at, Vector3(20.0, 0.0, 0.0))), 1.0), "A right angle is full lock")
	var small: float = BOT.steer_toward(at, Vector3(2.0, 0.0, -20.0))
	_expect(small > 0.0 and small < 0.5, "A small angle is a small steering (%.2f)" % small)
	_expect(is_zero_approx(BOT.steer_toward(at, at.origin)), "A target under the nose gives 0")
	var right: float = BOT.steer_toward(at, Vector3(3.0, 0.0, -9.0))
	_expect(is_equal_approx(right, -BOT.steer_toward(at, Vector3(-3.0, 0.0, -9.0))), "The steering is symmetric")
	var shed := Vector3(5.0, 1.0, -7.0)
	var map := Vector2(40.0, -12.0)
	_expect(BOT.map_point(BOT.world_point(map, shed), shed).is_equal_approx(map), "map_point() undoes world_point()")
	var planned: Dictionary = RoadNavigator.route(graph, Vector2.ZERO, CENTRO_IN)
	_expect(planned.ok, "The GPS finds a way from the shed to Barrio Centro's entrance")
	if not planned.ok:
		return
	_expect(is_equal_approx(BOT.half_width(graph, planned), 6.0), "The route runs on 12 m streets (half %.1f)"
		% BOT.half_width(graph, planned))
	_expect(BOT.off_road_m(planned, Vector2(100.0, 0.0)) < 0.5, "A point on the avenue is on the center line")
	_expect(is_equal_approx(BOT.off_road_m(planned, Vector2(100.0, 9.0)), 9.0), "9 m beside it is 9 m off")


func _check_world(graph: RoadGraph) -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	for _tick: int in range(40):
		await physics_frame
	var result: Dictionary = await BOT.follow(self, level, &"van_classic", graph, CENTRO_IN)
	print("ROAD_FOLLOW ", result)
	_expect(bool(result.ok), "The bot gets the van to Barrio Centro's entrance (%s; %.0f m left after %d ticks)"
		% [result.reason, result.remaining_m, result.ticks])
	_expect(bool(result.joined), "...after joining the road")
	_expect(int(result.off_road_ticks) == 0, "...and never leaves it: %d ticks off, at most %.1f m from the center"
		% [result.off_road_ticks, result.off_road_max_m])
	Input.action_release(&"drive_accelerate")
	level.queue_free()
	current_scene = null
	state.call(&"reset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
