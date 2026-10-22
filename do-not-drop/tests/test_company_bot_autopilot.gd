extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_bot_autopilot.gd
##
## The company-day bot's autopilot (tests/bot_company_van.gd, D-2016.3 and D-0304.3: the van follows the street
## graph's route to the houses with OFF_ROAD = 0). Two parts:
## - Pure, no physics: closest() (distance, metres along, index; it only looks forward from the index, so a line
##   that comes back near itself does not pull the van back), point_at(), path_length(), reversed(); the
##   steering of pure pursuit (steer_toward(): a target to the east of a van facing north is on its right,
##   positive; to the west, negative; ahead, zero; behind, full lock to the side it is on; symmetric) and its
##   look-ahead and speed (lookahead_for() grows with speed inside its bounds, target_speed() is cruise on a
##   straight, slower before a bend and a creep at the end; turn_ahead() is positive for a right turn); leg()
##   (a Bezier leg that ends at its end, leaves along its start direction and arrives along its end one);
##   plan() over the real street graph (RoadGraph): a route from the first avenue to a house's street point
##   with the leg before and after, where the route's part of the line is (road_from_m / road_to_m), the half
##   width of the narrowest street, and the refusal of a closed gate; the bot's street_entry() (on the avenue,
##   heading away from the shed) and street_point() (every one of the 50 houses is within HOUSE_REACH_M less the
##   arrival radius of the street point the van drives to).
## - Real driving, in real time (about 15 s): the company world, the player at the wheel of the fleet's van,
##   the leg from the yard to the avenue and 60 m of the street past it: it gets there (reason ""), covers
##   about as much as it was asked, stays in the street (off_road_max under OFF_ROAD_LIMIT_M), stands at the
##   end, and the pedal and the wheel are let go.

const BOT: GDScript = preload("res://tests/bot_company_day.gd")
const VAN: GDScript = preload("res://tests/bot_company_van.gd")
const TRIP: GDScript = preload("res://tests/bot_company_trip.gd")
## Metres of the line the real drive covers.
const CAP_M: float = 60.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_geometry()
	_check_pursuit()
	_check_plan()
	await _check_drive()
	if _failures == 0:
		print("PASS: the bot's autopilot follows the street graph: pure pursuit, plan, and a real drive in the street")
	quit(_failures)


func _check_geometry() -> void:
	# An L: 10 m east, then 10 m south (x z, +z south).
	var l := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	_expect(is_equal_approx(VAN.path_length(l), 20.0), "path_length of the L is 20 m (got %s)" % VAN.path_length(l))
	var near: Dictionary = VAN.closest(l, Vector2(4, 3))
	_expect(near["index"] == 0 and is_equal_approx(near["along"], 4.0) and is_equal_approx(near["distance"], 3.0),
		"closest to (4, 3): first segment, 4 m along, 3 m away (got %s)" % [near])
	near = VAN.closest(l, Vector2(12, 6))
	_expect(near["index"] == 1 and is_equal_approx(near["along"], 16.0) and is_equal_approx(near["distance"], 2.0),
		"closest to (12, 6): second segment, 16 m along, 2 m away (got %s)" % [near])
	_expect(is_equal_approx(VAN.distance_to_line(l, Vector2(5, -2)), 2.0), "distance_to_line is 2 m")
	# A U: the end comes back near the start. From index 1 on, the first leg is not the closest.
	var u := PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 2), Vector2(0, 2)])
	var back: Dictionary = VAN.closest(u, Vector2(2, 1.5), 2)
	_expect(back["index"] == 2 and back["along"] > 20.0, "closest only looks forward from the index (got %s)" % [back])
	var plain: Dictionary = VAN.closest(u, Vector2(2, 1.5), 0)
	_expect(plain["index"] == 2 or plain["index"] == 0, "from the start it finds a segment")
	_expect(VAN.point_at(l, 0.0) == Vector2(0, 0) and VAN.point_at(l, 15.0) == Vector2(10, 5),
		"point_at 0 m and 15 m of the L")
	_expect(VAN.point_at(l, 99.0) == Vector2(10, 10), "point_at past the end is the end")
	_expect(VAN.reversed(l) == PackedVector2Array([Vector2(10, 10), Vector2(10, 0), Vector2(0, 0)]), "reversed")
	_expect(VAN.closest(PackedVector2Array(), Vector2(1, 1))["distance"] == 0.0, "closest on an empty line is quiet")


func _check_pursuit() -> void:
	var north := Vector2(0, -1)
	var right: float = VAN.steer_toward(north, Vector2(10, -10), 14.0)
	var left: float = VAN.steer_toward(north, Vector2(-10, -10), 14.0)
	_expect(right > 0.2 and right <= 1.0, "A target to the east of a van facing north is on its right (got %f)" % right)
	_expect(left < -0.2 and left >= -1.0, "... and one to the west on its left (got %f)" % left)
	_expect(is_equal_approx(right, -left), "Steering is symmetric (%f, %f)" % [right, left])
	_expect(is_zero_approx(VAN.steer_toward(north, Vector2(0, -12), 12.0)), "Dead ahead: no steering")
	_expect(VAN.steer_toward(north, Vector2(-1, 12), 12.0) == -1.0, "Behind to the left: full lock to the left")
	_expect(VAN.steer_toward(north, Vector2(2, 12), 12.0) == 1.0, "Behind to the right: full lock to the right")
	_expect(is_zero_approx(VAN.steer_toward(Vector2.ZERO, Vector2(1, 1), 3.0)), "No heading: no steering")
	# Same target, a van facing east: it is on its left (north of it, -z).
	_expect(VAN.steer_toward(Vector2(1, 0), Vector2(10, -10), 14.0) < 0.0,
		"A van facing east has the north on its left")
	var near_aim: float = VAN.steer_toward(north, Vector2(3, -10), 10.0)
	var far_aim: float = VAN.steer_toward(north, Vector2(3, -10), 20.0)
	_expect(absf(near_aim) > absf(far_aim), "The same offset asks less steering from a farther aim")

	var slow: float = VAN.lookahead_for(0.0)
	var fast: float = VAN.lookahead_for(12.0)
	_expect(slow == VAN.LOOKAHEAD_MIN_M and fast > slow and fast <= VAN.LOOKAHEAD_MAX_M,
		"The look-ahead grows with speed inside its bounds (%f, %f)" % [slow, fast])
	_expect(VAN.lookahead_for(-5.0) == VAN.LOOKAHEAD_MIN_M and VAN.lookahead_for(99.0) == VAN.LOOKAHEAD_MAX_M,
		"... reversing or flying changes neither bound")

	var straight := PackedVector2Array([Vector2(0, 0), Vector2(300, 0)])
	var corner := PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(30, 300)])
	_expect(is_equal_approx(VAN.target_speed(straight, 50.0, 300.0, 0.0, 10.0), VAN.CRUISE_MPS),
		"Cruise speed on a straight")
	var before_bend: float = VAN.target_speed(corner, 10.0, 330.0, 0.0, 10.0)
	_expect(before_bend < VAN.CRUISE_MPS and before_bend >= VAN.BEND_MPS,
		"Slower before a right angle (got %f)" % before_bend)
	_expect(VAN.target_speed(straight, 50.0, 300.0, 1.0, 10.0) < VAN.CRUISE_MPS, "Slower with the wheel hard over")
	_expect(VAN.target_speed(straight, 299.0, 300.0, 0.0, 5.0) <= VAN.CREEP_MPS + 0.5, "A creep at the end")
	_expect(VAN.target_speed(straight, 285.0, 300.0, 0.0, 12.0) < VAN.target_speed(straight, 100.0, 300.0, 0.0, 12.0),
		"Slower as the end comes")
	var east_south := PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 60)])
	var to_the_right: float = VAN.turn_ahead(east_south, 10.0, 30.0)
	var east_north := PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, -60)])
	var to_the_left: float = VAN.turn_ahead(east_north, 10.0, 30.0)
	_expect(to_the_right > 1.4 and to_the_left < -1.4, "turn_ahead: east then south is right (%f), then north left (%f)"
		% [to_the_right, to_the_left])
	_expect(is_zero_approx(VAN.turn_ahead(straight, 10.0, 30.0)), "turn_ahead: a straight does not turn")
	_expect(VAN.bend_span_for(0.0) == VAN.BEND_SPAN_MIN_M and VAN.bend_span_for(99.0) == VAN.BEND_SPAN_MAX_M,
		"The bend is read farther ahead at speed, within bounds")
	_expect(VAN.ticks_for(100.0) < VAN.ticks_for(800.0) and VAN.ticks_for(0.0) > 0, "ticks_for grows with the line")

	var a := Vector2(0, -19)
	var b := Vector2(40, 0)
	var leg: PackedVector2Array = VAN.leg(a, Vector2(0, -1), b, Vector2(1, 0))
	_expect(leg.size() >= 2 and leg[leg.size() - 1] == b, "leg ends at its end (%d points)" % leg.size())
	_expect(leg[0] != a and (leg[0] - a).normalized().dot(Vector2(0, -1)) > 0.9, "leg leaves along its start direction")
	var last: Vector2 = leg[leg.size() - 1] - leg[leg.size() - 2]
	_expect(last.normalized().dot(Vector2(1, 0)) > 0.8,
		"leg arrives along its end direction (got %s)" % last.normalized())
	var worst_step: float = 0.0
	for i: int in leg.size() - 1:
		worst_step = maxf(worst_step, leg[i].distance_to(leg[i + 1]))
	_expect(worst_step <= VAN.LEG_STEP_M * 2.0, "leg points are close together (%f m)" % worst_step)


func _check_plan() -> void:
	var net: RoadGraph = RoadGraph.load_default()
	_expect(net != null, "The street graph loads")
	if net == null:
		return
	var entry: Dictionary = TRIP.street_entry(net)
	var point: Vector2 = entry["point"]
	var dir: Vector2 = entry["dir"]
	_expect(absf(point.y) < 1.0 and point.x > 20.0 and dir.x > 0.9,
		"The yard's leg joins the avenue away from the shed, heading east (got %s, %s)" % [point, dir])
	var out_leg: PackedVector2Array = VAN.leg(Vector2(0, -19), Vector2(0, -1), point, dir)
	var houses: HouseMap = HouseMap.load_default()
	var far: HouseSpot = houses.spot(&"centro_18")
	_expect(far != null, "centro_18 is on the map")
	if far == null:
		return
	var target: Vector2 = TRIP.street_point(net, far)
	var home: PackedVector2Array = VAN.leg(point, -dir, Vector2(0, -11), Vector2(0, 1))
	var planned: Dictionary = VAN.plan(net, Vector2(0, -19), target, out_leg, home)
	_expect(planned["ok"], "A route to a house of Centro (got %s)" % [planned.get("why")])
	if not planned["ok"]:
		return
	var line: PackedVector2Array = planned["line"]
	_expect(line[0] == out_leg[0], "The line starts with the leg")
	_expect(line[line.size() - 1] == Vector2(0, -11), "... and ends with the way home")
	_expect(is_equal_approx(planned["length"], VAN.path_length(line)), "The planned length is the line's")
	_expect(is_equal_approx(planned["road_from_m"], VAN.path_length(out_leg)),
		"The route's part starts where the leg ends (%f)" % planned["road_from_m"])
	_expect(planned["road_to_m"] > planned["road_from_m"] + 300.0 and planned["road_to_m"] < planned["length"],
		"... and the way home comes after it (%f to %f of %f)"
		% [planned["road_from_m"], planned["road_to_m"], planned["length"]])
	_expect(planned["half_width"] >= 4.0 and planned["half_width"] <= 6.0,
		"The narrowest street used has a half width of 4 to 6 m (got %f)" % planned["half_width"])
	# The route alone, from the van's place on a street.
	var plain: Dictionary = VAN.plan(net, point, target)
	_expect(plain["ok"] and is_zero_approx(plain["road_from_m"])
		and is_equal_approx(plain["road_to_m"], plain["length"]),
		"Without legs the line is the route")
	_expect(plain["length"] > 300.0 and plain["length"] < 1500.0,
		"... of a plausible length (got %f)" % plain["length"])
	# A gate that is closed refuses.
	var field: RoadNode = net.node_by_id(&"campo_a")
	var refused: Dictionary = VAN.plan(net, point, field.position)
	_expect(not refused["ok"] and refused["why"] == "gate_closed", "A closed gate is refused (got %s)" % [refused])
	_expect(not VAN.plan(null, point, point)["ok"], "No graph, no route")
	# Every house: the street point is close enough that the arrival radius reaches the house.
	var worst: float = 0.0
	for house: HouseSpot in houses.houses:
		worst = maxf(worst, house.position.distance_to(TRIP.street_point(net, house)))
	_expect(worst <= TRIP.HOUSE_REACH_M - VAN.ARRIVE_M,
		"Every house is within the reach of its street point (worst %f m of %f)"
		% [worst, TRIP.HOUSE_REACH_M - VAN.ARRIVE_M])


## The real thing, in real time: the van at the wheel drives the leg and CAP_M metres of the avenue.
func _check_drive() -> void:
	var level := await BOT.open_world(self, 2) as CompanyRoot
	_expect(level != null and await BOT.wait_opening(self, level, 10.0), "The company world opens")
	if level == null:
		return
	var id: StringName = &"van_classic"
	var van: VehicleBody3D = VAN.van_of(level, id)
	_expect(van != null, "The fleet's van is there")
	if van == null:
		BOT.close_world(self, level)
		return
	var seated: String = await VAN.take_wheel(self, level, id)
	_expect(seated == "", "The player takes the wheel (got %s)" % seated)
	var start: Vector2 = VAN.ground_of(van)
	var net: RoadGraph = RoadGraph.load_default()
	var entry: Dictionary = TRIP.street_entry(net)
	# Out of the playon as the bot does: the yard's exit is the van's nose ahead, past the gate.
	var gate_out: Vector2 = start + VAN.forward_of(van) * 10.0
	var out_leg: PackedVector2Array = VAN.leg(gate_out, VAN.forward_of(van), entry["point"], entry["dir"])
	var before: PackedVector2Array = PackedVector2Array([gate_out])
	before.append_array(out_leg)
	var far: Vector2 = TRIP.street_point(net, HouseMap.load_default().spot(&"centro_18"))
	var started: int = Time.get_ticks_msec()
	var report: Dictionary = await VAN.drive_to(self, level, id, far, before, PackedVector2Array(), CAP_M)
	var seconds: float = (Time.get_ticks_msec() - started) / 1000.0
	_expect(report["reason"] == "", "The autopilot drives its line to the cap (got %s)" % [report])
	var leg_m: float = VAN.path_length(before)
	_expect(report["metres"] > (leg_m + CAP_M) * 0.85 and report["metres"] < (leg_m + CAP_M) * 1.3,
		"It covered the leg and the 60 m asked (%.1f m of %.1f)" % [report["metres"], leg_m + CAP_M])
	_expect(report["off_road_max"] <= VAN.OFF_ROAD_LIMIT_M,
		"It stayed in the street: %.2f m outside the roadway (limit %.1f, %.2f m from the centre line)"
		% [report["off_road_max"], VAN.OFF_ROAD_LIMIT_M, report["line_max"]])
	_expect(report["length"] > 500.0, "The line is the whole way to the house (%.0f m)" % report["length"])
	_expect(absf(VAN.forward_speed(van)) < 2.0,
		"The van stands at the end of the drive (%.1f m/s)" % VAN.forward_speed(van))
	_expect(not Input.is_action_pressed(VAN.ACCELERATE) and not Input.is_action_pressed(VAN.STEER_RIGHT)
		and not Input.is_action_pressed(VAN.STEER_LEFT) and not Input.is_action_pressed(VAN.BRAKE),
		"The pedals and the wheel are let go")
	_expect(van.global_position.y > -1.0 and van.global_position.y < 3.0, "The van is on the ground")
	_expect(seconds < 30.0, "The drive is bounded (took %.1f s)" % seconds)
	print("  autopilot drive: %.0f m of a %.0f m line in %.1f s, off_road_max %.2f m" %
		[report["metres"], report["length"], seconds, report["off_road_max"]])
	Input.action_release(VAN.HANDBRAKE)
	BOT.close_world(self, level)
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
