extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_road_follow.gd
##
## The bot's autopilot drives the whole way from the yard into Barrio Centro without leaving the roadway
## (expansion D-0304's test: "the bot's autopilot (D-2016) goes shed -> Centro with OFF_ROAD = 0"). It takes
## over the road follower of the abandoned PR #735 (D-0304.3) with the autopilot that does that job since
## D-2016.3 (tests/bot_company_van.gd's drive_to); test_company_bot_autopilot only drives 60 m of the avenue.
## - The map, no physics: RoadNavigator.route() from the avenue's entry (bot_company_trip.street_entry) to
##   TARGET, 60 m up the first street of Centro north of its first corner (c_384_0), is ok and runs on
##   avenida_este_1, avenida_este_2 and calle_v_384_m384 (8 m, Centro); VAN.plan() of the yard's leg plus that
##   route is one line with no jump between its points, whose narrowest street is 8 m (half width 4).
## - In the company world (company_root.tscn, solo, real time, about 50 s: 460 m): the player takes the wheel of the
##   fleet's van and the autopilot drives the leg out of the yard, the avenue to Centro and round its first
##   corner (left onto the 8 m street) to TARGET: it gets there (reason ""), stands within a few metres of
##   it, and on the route's part the van's centre was never outside the roadway more than
##   VAN.OFF_ROAD_LIMIT_M (OFF_ROAD = 0: in the street).

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_road_follow"
const VAN: GDScript = preload("res://tests/bot_company_van.gd")
const TRIP: GDScript = preload("res://tests/bot_company_trip.gd")
## 60 m north of Centro's first corner (c_384_0) on calle_v_384_m384.
const TARGET: Vector2 = Vector2(384.0, -60.0)
const ROUTE_EDGES: Array[StringName] = [&"avenida_este_1", &"avenida_este_2", &"calle_v_384_m384"]
## The most two points of the line may be apart (m): the route's points are POLYLINE_STEP apart, the leg's LEG_STEP_M.
const MAX_GAP_M: float = 10.0
## How close to TARGET the van stands at the end (m): it stops ARRIVE_M short and rolls a little on the brake.
const END_WITHIN_M: float = 10.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run: Node = root.get_node_or_null(^"/root/RunManager")
	if run != null:
		run.set(&"is_running", false)
	var net: RoadGraph = RoadGraph.load_default()
	_check_map(net)
	await _check_drive(net)
	if _failures == 0:
		print("PASS: the autopilot drives the van from the yard into Barrio Centro and round its first corner"
			+ " without leaving the roadway")
	quit(_failures)


## The out-of-the-yard leg the bot drives (as test_company_bot_autopilot): from 10 m ahead of the van's nose to
## the avenue's entry, arriving along it.
func _yard_leg(start: Vector2, forward: Vector2, net: RoadGraph) -> PackedVector2Array:
	var entry: Dictionary = TRIP.street_entry(net)
	var gate_out: Vector2 = start + forward * 10.0
	var before := PackedVector2Array([gate_out])
	before.append_array(VAN.leg(gate_out, forward, entry["point"], entry["dir"]))
	return before


func _check_map(net: RoadGraph) -> void:
	var entry: Dictionary = TRIP.street_entry(net)
	var planned: Dictionary = RoadNavigator.route(net, entry["point"], TARGET)
	_expect(bool(planned.get("ok", false)), "The GPS finds a way from the avenue's entry into Centro (%s)"
		% planned.get("reason", ""))
	if not bool(planned.get("ok", false)):
		return
	var edges: Array = planned["edges"]
	_expect(edges == ROUTE_EDGES, "It runs on the avenue and turns onto Centro's first street (got %s)" % [edges])
	var street: RoadEdge = net.edge_by_id(&"calle_v_384_m384")
	_expect(street != null and street.area == &"centro" and is_equal_approx(street.width, 8.0),
		"The street after the corner is Centro's, 8 m wide")
	# A van parked facing north in the yard, as CompanyFleet leaves it: the leg leaves along its nose.
	var line_plan: Dictionary = VAN.plan(net, Vector2(0.0, -20.0), TARGET,
		_yard_leg(Vector2(0.0, -20.0), Vector2(0.0, -1.0), net))
	_expect(bool(line_plan["ok"]), "VAN.plan() joins the yard's leg and the route (%s)" % line_plan["why"])
	if not bool(line_plan["ok"]):
		return
	var line: PackedVector2Array = line_plan["line"]
	var widest: float = 0.0
	for i in line.size() - 1:
		widest = maxf(widest, line[i].distance_to(line[i + 1]))
	_expect(widest <= MAX_GAP_M, "The line has no jump (largest gap %.1f m)" % widest)
	_expect(line[line.size() - 1].distance_to(TARGET) < 1.0, "The line ends at the target")
	_expect(is_equal_approx(float(line_plan["half_width"]), 4.0),
		"Its narrowest street is the 8 m one (half width %.1f)" % float(line_plan["half_width"]))
	_expect(float(line_plan["road_to_m"]) - float(line_plan["road_from_m"]) > 350.0,
		"The route's part is the whole avenue and the corner (%.0f m)"
		% (float(line_plan["road_to_m"]) - float(line_plan["road_from_m"])))


func _check_drive(net: RoadGraph) -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	for _tick: int in range(40):
		await physics_frame
	var id: StringName = &"van_classic"
	var van: VehicleBody3D = VAN.van_of(level, id)
	_expect(van != null, "The fleet's van is there")
	if van != null:
		var seated: String = await VAN.take_wheel(self, level, id)
		_expect(seated == "", "The player takes the wheel (got %s)" % seated)
		var before: PackedVector2Array = _yard_leg(VAN.ground_of(van), VAN.forward_of(van), net)
		var started: int = Time.get_ticks_msec()
		var report: Dictionary = await VAN.drive_to(self, level, id, TARGET, before)
		var seconds: float = (Time.get_ticks_msec() - started) / 1000.0
		print("ROAD_FOLLOW %.0f m of a %.0f m line in %.1f s, off_road_max %.2f m at %s, line_max %.1f m, end %s" % [
			float(report["metres"]), float(report["length"]), seconds, float(report["off_road_max"]),
			report.get("off_road_at", Vector2.ZERO), float(report.get("line_max", 0.0)), report["end"]])
		_expect(str(report["reason"]) == "", "The autopilot gets the van into Centro (got %s)" % report["reason"])
		var short_of: float = (report["end"] as Vector2).distance_to(TARGET)
		_expect(short_of <= END_WITHIN_M, "It stands at the target, round the corner (%.1f m from it)" % short_of)
		_expect(float(report["off_road_max"]) <= VAN.OFF_ROAD_LIMIT_M,
			"It never left the roadway: %.2f m outside it at most (limit %.1f m; OFF_ROAD = 0)"
			% [float(report["off_road_max"]), VAN.OFF_ROAD_LIMIT_M])
		_expect(not Input.is_action_pressed(VAN.ACCELERATE) and not Input.is_action_pressed(VAN.STEER_RIGHT)
			and not Input.is_action_pressed(VAN.STEER_LEFT), "The pedal and the wheel are let go")
	Input.action_release(VAN.HANDBRAKE)
	root.remove_child(level)
	level.free()
	current_scene = null
	state.call(&"reset")
	_remove_dir(DIR)
	await process_frame


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir != null:
		for file: String in dir.get_files():
			dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
