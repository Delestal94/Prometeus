extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_road_graph_path.gd
##
## The GPS's path finder (expansion D-0308, scripts/gameplay/districts/road_navigator.gd):
## - on a small map with a short way through a gate and a longer free way round it, the route
##   takes the way round while the gate is closed and the short way once its lock is open (and
##   lists the gate it passes); when there is no free way it is refused with reason gate_closed
##   and the lock that would open it;
## - streets weigh by time: a shorter dirt track loses to a longer asphalt road, and the route's
##   seconds are its meters over the surface speeds;
## - the polyline is continuous (no gap over its step), starts and ends at the snapped points,
##   and works when both points are on the same street or in the middle of streets;
## - guidance() reads a vehicle's position: meters and seconds left fall as it moves along, the
##   waypoint is ahead of it on the route, and it is done at the end;
## - on the real map (data/world/road_graph.tres) the shed reaches a Centro house at once, a Campo
##   house is refused with gate_campo_obra while it is closed, and with it open the route passes it
##   and its meters are no shorter than the straight line.

const STEP_MAX: float = 8.5

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_gate_detour()
	_test_time_weight()
	_test_polyline()
	_test_guidance()
	_test_real_map()
	if _failures == 0:
		print("PASS: the GPS routes by time around closed gates and reads a vehicle's position")
	quit(_failures)


func _node(id: StringName, at: Vector2, kind: StringName = &"junction", lock: StringName = &"") -> RoadNode:
	var node := RoadNode.new()
	node.id = id
	node.position = at
	node.kind = kind
	node.lock_id = lock
	return node


func _edge(id: StringName, from: StringName, to: StringName, surface: StringName = &"asphalt") -> RoadEdge:
	var edge := RoadEdge.new()
	edge.id = id
	edge.from_id = from
	edge.to_id = to
	edge.surface = surface
	return edge


## S - M(gate) - T along y = 0 (100 m), and the way round S - N - T through (50, 60).
func _gate_map(with_detour: bool) -> RoadNetwork:
	var net := RoadNetwork.new()
	net.nodes.assign([
		_node(&"s", Vector2(0, 0)), _node(&"m", Vector2(50, 0), &"gate", &"lock_m"),
		_node(&"t", Vector2(100, 0)), _node(&"n", Vector2(50, 60)),
	])
	net.edges.append(_edge(&"sm", &"s", &"m"))
	net.edges.append(_edge(&"mt", &"m", &"t"))
	if with_detour:
		net.edges.append(_edge(&"sn", &"s", &"n"))
		net.edges.append(_edge(&"nt", &"n", &"t"))
	return net


func _test_gate_detour() -> void:
	var net: RoadNetwork = _gate_map(true)
	var from := Vector2(0, 0)
	var to := Vector2(100, 0)
	var closed: Dictionary = RoadNavigator.route(net, from, to)
	_expect(closed.ok, "With the gate closed there is a way round")
	_expect(closed.nodes.has(&"n") and not closed.nodes.has(&"m"), "The closed gate is avoided: %s" % [closed.nodes])
	_expect(closed.locks.is_empty(), "A way round passes no gate")
	var open: Dictionary = RoadNavigator.route(net, from, to, [&"lock_m"])
	_expect(open.ok and open.nodes.has(&"m") and not open.nodes.has(&"n"),
			"With the lock open the short way through the gate is taken: %s" % [open.nodes])
	_expect(open.locks == [&"lock_m"], "The route lists the gate it passes: %s" % [open.locks])
	_expect(open.seconds < closed.seconds and open.length < closed.length, "Through the gate is quicker and shorter")
	var no_way: Dictionary = RoadNavigator.route(_gate_map(false), from, to)
	_expect(not no_way.ok and no_way.reason == RoadNavigator.REASON_GATE_CLOSED and no_way.locks == [&"lock_m"],
			"No free way: refused with gate_closed and the lock to open: %s" % [no_way])
	_expect(RoadNavigator.route(_gate_map(false), from, to, [&"lock_m"]).ok, "The same map is fine with the lock open")
	var off: Dictionary = RoadNavigator.route(net, from, to, [])
	_expect(off.ok, "A point on a street is not off the map")
	_expect(RoadNavigator.route(RoadNetwork.new(), from, to).get("reason") == RoadNavigator.REASON_OFF_MAP,
			"An empty map is off_map")


func _test_time_weight() -> void:
	# Direct 100 m of dirt (14.3 s) against 2 x 60 m of asphalt (8.6 s).
	var net := RoadNetwork.new()
	net.nodes.assign([
		_node(&"a", Vector2(0, 0)), _node(&"b", Vector2(100, 0)), _node(&"c", Vector2(50, 33)),
	])
	net.edges.append(_edge(&"ab", &"a", &"b", &"dirt"))
	net.edges.append(_edge(&"ac", &"a", &"c"))
	net.edges.append(_edge(&"cb", &"c", &"b"))
	var planned: Dictionary = RoadNavigator.route(net, Vector2(0, 0), Vector2(100, 0))
	_expect(planned.ok and planned.nodes.has(&"c"), "The quicker asphalt way wins over the shorter dirt track")
	var expected: float = 0.0
	for edge_id: StringName in [&"ac", &"cb"]:
		expected += RoadNavigator.seconds_for(net.edge_by_id(edge_id), net.edge_length(edge_id))
	_expect(is_equal_approx(planned.seconds, expected), "The seconds are meters over speeds (%.2f vs %.2f)" % [
			planned.seconds, expected])
	_expect(RoadNavigator.seconds_for(net.edge_by_id(&"ab"), 70.0) > RoadNavigator.seconds_for(net.edge_by_id(&"ac"), 70.0),
			"Dirt is slower than asphalt")


func _test_polyline() -> void:
	var net: RoadNetwork = _gate_map(true)
	# From the middle of the first street to the middle of the last one.
	var planned: Dictionary = RoadNavigator.route(net, Vector2(20, 1), Vector2(80, -1), [&"lock_m"])
	_expect(planned.ok, "A route between two mid-street points exists")
	var line: PackedVector2Array = planned.polyline
	_expect(line[0].distance_to(Vector2(20, 0)) < 0.5 and line[line.size() - 1].distance_to(Vector2(80, 0)) < 0.5,
			"The polyline runs from the snapped start to the snapped end")
	var widest: float = 0.0
	for i in line.size() - 1:
		widest = maxf(widest, line[i].distance_to(line[i + 1]))
	_expect(widest <= STEP_MAX, "The polyline has no gap (widest %.2f m)" % widest)
	_expect(is_equal_approx(planned.length, 60.0), "Its length is the 60 m driven (%.2f)" % planned.length)
	var same: Dictionary = RoadNavigator.route(net, Vector2(10, 0), Vector2(40, 0))
	_expect(same.ok and is_equal_approx(same.length, 30.0) and same.nodes.is_empty(),
			"Two points on one street: straight along it (%s m)" % same.get("length"))
	var back: Dictionary = RoadNavigator.route(net, Vector2(40, 0), Vector2(10, 0))
	_expect(back.ok and back.polyline[0].distance_to(Vector2(40, 0)) < 0.5, "Going back along a street starts at the vehicle")


func _test_guidance() -> void:
	var net: RoadNetwork = _gate_map(true)
	var planned: Dictionary = RoadNavigator.route(net, Vector2(0, 0), Vector2(100, 0), [&"lock_m"])
	var start: Dictionary = RoadNavigator.guidance(planned, Vector2(0, 0), 30.0)
	var middle: Dictionary = RoadNavigator.guidance(planned, Vector2(50, 3), 30.0)
	var end: Dictionary = RoadNavigator.guidance(planned, Vector2(100, 0), 30.0)
	_expect(is_equal_approx(start.distance, 100.0) and is_equal_approx(start.seconds, planned.seconds),
			"At the start the whole route is left")
	_expect(is_equal_approx(middle.distance, 50.0) and middle.seconds < start.seconds and middle.seconds > end.seconds,
			"Half way, half is left (%.1f m)" % middle.distance)
	_expect(is_equal_approx(middle.waypoint.x, 80.0) and middle.waypoint.y == 0.0,
			"The waypoint is 30 m ahead on the route: %s" % [middle.waypoint])
	_expect(end.done and not start.done and is_equal_approx(end.distance, 0.0), "At the end it is done")
	_expect(RoadNavigator.guidance({"ok": false}, Vector2.ZERO).is_empty(), "No route, no guidance")


func _test_real_map() -> void:
	var graph: RoadGraph = RoadGraph.load_default()
	var houses: HouseMap = HouseMap.load_default()
	_expect(graph != null and houses != null, "The real map loads")
	if graph == null or houses == null:
		return
	var shed: Vector2 = graph.node_by_id(RoadGraph.SHED_NODE).position
	var centro: Array[HouseSpot] = houses.in_zone(&"centro")
	var campo: Array[HouseSpot] = houses.in_zone(&"campo")
	_expect(not centro.is_empty() and not campo.is_empty(), "There are houses in Centro and Campo")
	for house: HouseSpot in centro:
		var planned: Dictionary = RoadNavigator.route(graph, shed, house.position)
		_expect(planned.ok and planned.locks.is_empty(), "The shed reaches %s with every gate closed" % house.id)
	var far: HouseSpot = campo[0]
	var refused: Dictionary = RoadNavigator.route(graph, shed, far.position)
	_expect(not refused.ok and refused.reason == RoadNavigator.REASON_GATE_CLOSED and refused.locks.has(&"gate_campo_obra"),
			"%s in Campo is refused behind gate_campo_obra: %s" % [far.id, refused])
	var allowed: Dictionary = RoadNavigator.route(graph, shed, far.position, [&"gate_campo_obra"])
	_expect(allowed.ok and allowed.locks.has(&"gate_campo_obra"),
			"With the works gate open the route to %s passes it" % far.id)
	if allowed.ok:
		_expect(allowed.length >= shed.distance_to(far.position), "The route is no shorter than the straight line")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
