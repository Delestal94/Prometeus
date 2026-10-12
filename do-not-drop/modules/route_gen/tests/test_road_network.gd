extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/route_gen/tests/test_road_network.gd
##
## RoadNetwork, RoadNode and RoadEdge on their own (docs/modulos.md):
## - Bezier geometry: a straight street is as long as its chord, a curved one is
##   longer, point_at() hits both ends and the middle, tangent_at() follows the
##   direction of travel, sample_every() keeps its spacing and both ends, and
##   moving a node drags the street after invalidate();
## - travel: distances_from() and shortest_path() take the shorter of two ways,
##   a gate whose lock is closed can be reached but not crossed and opens when
##   its lock is listed, and a path from an unknown node is empty;
## - queries: nearest_point() finds the street, the distance along it and the
##   gap; cells_crossed() lists the cells a street goes through, none twice;
## - checks: a sound network validates clean, and every kind of mistake
##   (repeated id, missing node, unknown kind or surface, gate without lock,
##   dead end with two streets, loose node) is named; crossing_pairs() finds two
##   streets that cross without a node and ignores two that meet at one.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_geometry()
	_test_travel()
	_test_queries()
	_test_validation()
	_test_crossings()
	if _failures == 0:
		print("PASS: the road network measures its curves, walks its locks and names what is wrong")
	quit(_failures)


## A small map:        n (0,-100)
##                     |
##   w (-200,0) ---- hub (0,0) ---- gate (200,0) ---- far (400,0)
##                     \_________ curve _________/ (hub to gate, bulging south)
func _map() -> RoadNetwork:
	var net := RoadNetwork.new()
	net.nodes.append(_node(&"hub", Vector2(0, 0), &"junction"))
	net.nodes.append(_node(&"w", Vector2(-200, 0), &"dead_end"))
	net.nodes.append(_node(&"n", Vector2(0, -100), &"dead_end"))
	net.nodes.append(_node(&"gate", Vector2(200, 0), &"gate", &"lock_a"))
	net.nodes.append(_node(&"far", Vector2(400, 0), &"dead_end"))
	net.edges.append(_edge(&"hub_w", &"hub", &"w"))
	net.edges.append(_edge(&"hub_n", &"hub", &"n"))
	net.edges.append(_edge(&"hub_gate", &"hub", &"gate"))
	net.edges.append(_edge(&"gate_far", &"gate", &"far"))
	# A longer way round from the hub to the gate, through a curve.
	var round_way := _edge(&"hub_gate_round", &"hub", &"gate")
	round_way.out_handle = Vector2(0, 150)
	round_way.in_handle = Vector2(0, 150)
	net.edges.append(round_way)
	return net


func _node(id: StringName, at: Vector2, kind: StringName, lock: StringName = &"") -> RoadNode:
	var node := RoadNode.new()
	node.id = id
	node.position = at
	node.kind = kind
	node.lock_id = lock
	return node


func _edge(id: StringName, from: StringName, to: StringName) -> RoadEdge:
	var edge := RoadEdge.new()
	edge.id = id
	edge.from_id = from
	edge.to_id = to
	return edge


func _test_geometry() -> void:
	var net := _map()
	_expect(is_equal_approx(net.edge_length(&"hub_w"), 200.0), "A straight street is as long as its chord")
	_expect(net.edge_length(&"hub_gate_round") > 260.0, "A curved street is longer than its chord")
	_expect(net.edge_length(&"hub_gate_round") < 400.0, "...but not absurdly (%f)" % net.edge_length(&"hub_gate_round"))
	_expect(net.point_at(&"hub_w", 0.0).is_equal_approx(Vector2(0, 0)), "point_at(0) is the from node")
	_expect(net.point_at(&"hub_w", 999.0).is_equal_approx(Vector2(-200, 0)), "point_at() past the end is the to node")
	_expect(net.point_at(&"hub_w", 100.0).is_equal_approx(Vector2(-100, 0)),
			"point_at() in the middle of a straight street")
	var round_len: float = net.edge_length(&"hub_gate_round")
	var mid: Vector2 = net.point_at(&"hub_gate_round", round_len * 0.5)
	_expect(is_equal_approx(mid.x, 100.0) and mid.y > 50.0, "The round way bulges toward +y at its middle: %s" % mid)
	_expect(net.tangent_at(&"hub_w", 50.0).is_equal_approx(Vector2.LEFT),
			"tangent_at() follows the direction of travel")
	_expect(net.tangent_at(&"hub_gate_round", 1.0).y > 0.9, "The round way leaves the hub heading to +y")
	var samples: PackedVector2Array = net.sample_every(&"hub_gate_round", 20.0)
	_expect(samples[0].is_equal_approx(Vector2(0, 0)) and samples[samples.size() - 1].is_equal_approx(Vector2(200, 0)),
			"sample_every() keeps both ends")
	var spacing_ok: bool = true
	for i in samples.size() - 1:
		var gap: float = samples[i].distance_to(samples[i + 1])
		spacing_ok = spacing_ok and gap > 12.0 and gap < 22.0
	_expect(spacing_ok, "sample_every() points are about 20 m apart")
	_expect(is_equal_approx(net.total_length(), 200.0 + 100.0 + 200.0 + 200.0 + round_len),
			"total_length() adds every street")
	net.node_by_id(&"w").position = Vector2(-300, 0)
	net.invalidate()
	_expect(is_equal_approx(net.edge_length(&"hub_w"), 300.0), "Moving a node and invalidating drags the street")
	_expect(net.edge_length(&"no_such") == 0.0 and net.centerline(&"no_such").is_empty(), "An unknown street is empty")


func _test_travel() -> void:
	var net := _map()
	var closed: Dictionary = net.distances_from(&"hub")
	_expect(is_equal_approx(closed[&"gate"], 200.0), "The shorter of two ways to the gate wins")
	_expect(closed.has(&"gate") and not closed.has(&"far"), "A closed gate is reached but not crossed")
	var open: Dictionary = net.distances_from(&"hub", [&"lock_a"])
	_expect(open.has(&"far") and is_equal_approx(open[&"far"], 400.0), "An open lock lets the way go on")
	_expect(net.distances_from(&"far").has(&"gate") and not net.distances_from(&"far").has(&"hub"),
			"From beyond the gate you leave the same way: the gate stops you")
	_expect(net.distances_from(&"gate").has(&"far") and net.distances_from(&"gate").has(&"hub"),
			"Starting on the gate itself you can go either way")
	var path: Array[StringName] = net.shortest_path(&"w", &"far", [&"lock_a"])
	_expect(Array(path) == [&"w", &"hub", &"gate", &"far"], "shortest_path() lists the nodes: %s" % [path])
	_expect(net.shortest_path(&"w", &"far").is_empty(), "No path through a closed lock")
	_expect(net.shortest_path(&"nowhere", &"far").is_empty(), "No path from an unknown node")
	_expect(Array(net.shortest_path(&"hub", &"hub")) == [&"hub"], "A node's path to itself is itself")


func _test_queries() -> void:
	var net := _map()
	var hit: Dictionary = net.nearest_point(Vector2(-50, 7))
	_expect(hit.get("edge") == &"hub_w", "nearest_point() finds the street")
	_expect(absf(float(hit.get("along", -1.0)) - 50.0) < 0.5, "...and how far along it is (%s)" % hit.get("along"))
	_expect(absf(float(hit.get("distance", -1.0)) - 7.0) < 0.1, "...and the gap")
	_expect(net.nearest_point(Vector2(0, -3000), 50.0).is_empty(), "Nothing within reach is an empty answer")
	var cells: Array[Vector2i] = net.cells_crossed(&"hub_w", 64.0)
	_expect(cells.has(Vector2i(0, 0)) and cells.has(Vector2i(-1, 0)) and cells.has(Vector2i(-4, 0)),
			"cells_crossed() lists the cells of the street: %s" % [cells])
	var unique: Dictionary = {}
	for cell in cells:
		unique[cell] = true
	_expect(unique.size() == cells.size(), "...none twice")
	_expect(net.edges_at(&"hub").size() == 4 and net.edges_at(&"nowhere").is_empty(),
			"edges_at() lists a node's streets")
	var hub_gate: RoadEdge = net.edge_by_id(&"hub_gate")
	_expect(net.other_end(hub_gate, &"hub") == &"gate" and net.other_end(hub_gate, &"gate") == &"hub",
			"other_end() gives the far node")


func _test_validation() -> void:
	_expect(_map().validate().is_empty(), "A sound network validates clean: %s" % [_map().validate()])
	var cases: Dictionary = {
		"repeated node": func(net: RoadNetwork) -> void: net.nodes.append(_node(&"hub", Vector2.ONE, &"junction")),
		"missing node": func(net: RoadNetwork) -> void: net.edges.append(_edge(&"bad", &"hub", &"ghost")),
		"unknown kind": func(net: RoadNetwork) -> void: net.node_by_id(&"hub").kind = &"roundabout",
		"gate without lock": func(net: RoadNetwork) -> void: net.node_by_id(&"gate").lock_id = &"",
		"lock on a junction": func(net: RoadNetwork) -> void: net.node_by_id(&"hub").lock_id = &"x",
		"unknown surface": func(net: RoadNetwork) -> void: net.edge_by_id(&"hub_w").surface = &"lava",
		"zero width": func(net: RoadNetwork) -> void: net.edge_by_id(&"hub_w").width = 0.0,
		"repeated edge": func(net: RoadNetwork) -> void: net.edges.append(_edge(&"hub_w", &"hub", &"n")),
		"loop": func(net: RoadNetwork) -> void: net.edges.append(_edge(&"loop", &"hub", &"hub")),
		"loose node": func(net: RoadNetwork) -> void: net.nodes.append(_node(&"lonely", Vector2(9, 9), &"junction")),
		"dead end with two": func(net: RoadNetwork) -> void: net.edges.append(_edge(&"extra", &"w", &"n")),
		"zero length": func(net: RoadNetwork) -> void: net.node_by_id(&"n").position = Vector2.ZERO,
	}
	for label: String in cases:
		var net := _map()
		(cases[label] as Callable).call(net)
		net.invalidate()
		_expect(not net.validate().is_empty(), "validate() names the mistake: %s" % label)


func _test_crossings() -> void:
	_expect(_map().crossing_pairs().is_empty(), "Streets that meet at a node do not cross")
	var net := _map()
	net.nodes.append(_node(&"s1", Vector2(-100, -50), &"dead_end"))
	net.nodes.append(_node(&"s2", Vector2(-100, 50), &"dead_end"))
	net.edges.append(_edge(&"across", &"s1", &"s2"))
	var pairs: Array = net.crossing_pairs()
	_expect(pairs.size() == 1 and (pairs[0] as Array).has(&"hub_w") and (pairs[0] as Array).has(&"across"),
			"A street across another without a node is found: %s" % [pairs])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
