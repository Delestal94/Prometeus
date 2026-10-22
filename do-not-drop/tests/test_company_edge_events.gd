extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_edge_events.gd
##
## The Campo's animals and events dealt per street of the graph (expansion D-0315,
## scripts/gameplay/districts/edge_events.gd on data/world/road_graph.tres):
## - the same seed deals the same events on every street, and other seeds deal
##   other ones (the five kinds all turn up across seeds);
## - only the Campo's streets (zone campo, loose surface) get events: none on
##   asphalt, none outside the zone;
## - every event lies inside its street: along in [0, length], its point on the
##   curve, the mud on the glass ends before the street does;
## - the deer and the flock stand on a straight piece, the dog only on the farm
##   lanes, at most one of each kind per street;
## - the cargo animals are CargoAnimalPlan's legs over the Campo's streets (the
##   first quiet, none on two in a row) and the mud is LowVisibilityPlan's draws;
## - the Campo's streets carry every kind of piece of today's route (baden,
##   chicane, bridge, gravel, mud, works, rail crossing);
## - EdgeCellContent hands each event to exactly one cell (the one its point lies
##   in), leaves the cell as it was with spawn_events off, and with it on adds the
##   deer, flock and dog nodes at their points, which run a few physics frames.

const SEED: int = 20261022
const SEEDS: int = 40
## Kinds of piece of today's route that the Campo's streets must carry.
const TODAY: Array[StringName] = [&"speed_bump", &"chicane", &"narrow_bridge", &"gravel", &"mud",
		&"construction_zone", &"rail_crossing"]

var _failures: int = 0
var _graph: RoadGraph


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_graph = RoadGraph.load_default()
	_expect(_graph != null, "data/world/road_graph.tres loads")
	if _graph == null:
		quit(1)
		return
	_test_kinds_of_piece()
	_test_deterministic()
	_test_only_field()
	_test_inside_edge()
	_test_rules()
	_test_reused_plans()
	_test_cells()
	await _test_spawned_nodes()
	quit(_failures)


func _test_kinds_of_piece() -> void:
	var present: Dictionary = {}
	for edge_id: StringName in EdgeEvents.field_edges(_graph):
		for piece: Dictionary in EdgePieces.plan(_graph, edge_id):
			present[piece.kind] = true
	for kind: StringName in TODAY:
		_expect(present.has(kind), "The Campo's streets lay a %s piece" % kind)


func _test_deterministic() -> void:
	var first: Dictionary = EdgeEvents.plan_all(_graph, SEED)
	var second: Dictionary = EdgeEvents.plan_all(_graph, SEED)
	var same := first.size() == second.size() and first.size() > 0
	for edge_id: StringName in first:
		same = same and second.has(edge_id) \
				and EdgeEvents.signature(first[edge_id]) == EdgeEvents.signature(second[edge_id])
	_expect(same, "The same seed deals the same events (%d streets with some)" % first.size())
	var seen: Dictionary = {}
	var signatures: Dictionary = {}
	for world_seed in range(1, SEEDS + 1):
		var signature := ""
		for edge_id: StringName in EdgeEvents.field_edges(_graph):
			var events: Array[Dictionary] = EdgeEvents.plan(_graph, edge_id, world_seed)
			signature += "%s:%s;" % [edge_id, EdgeEvents.signature(events)]
			for event: Dictionary in events:
				seen[event.kind] = true
		signatures[signature] = true
	_expect(signatures.size() > SEEDS / 2,
			"Other seeds deal other events (%d different in %d)" % [signatures.size(), SEEDS])
	for kind: StringName in EdgeEvents.KINDS:
		_expect(seen.has(kind), "Some seed deals a %s" % kind)


func _test_only_field() -> void:
	var field: Array[StringName] = EdgeEvents.field_edges(_graph)
	_expect(field.size() > 0 and field.size() < _graph.edges.size(),
			"Only some streets are the Campo's (%d)" % field.size())
	for world_seed in range(1, 11):
		for edge: RoadEdge in _graph.edges:
			var events: Array[Dictionary] = EdgeEvents.plan(_graph, edge.id, world_seed)
			var is_field: bool = edge.area == &"campo" and _graph.is_loose(edge)
			if not is_field:
				_check(events.is_empty(), "No events on %s (zone %s, %s)" % [edge.id, edge.area, edge.surface])
			_check(is_field == field.has(edge.id), "%s is a Campo street only if zone and surface say so" % edge.id)
	_check(EdgeEvents.plan(_graph, &"nowhere", SEED).is_empty(), "A street that is not in the graph has none")
	var asphalt := _graph.edge_by_id(&"camino_campo_1")
	_check(asphalt != null and asphalt.street == &"camino_campo" and not field.has(asphalt.id),
			"The asphalt road to the gate is not the Campo's")


func _test_inside_edge() -> void:
	var checked: int = 0
	for world_seed in range(1, SEEDS + 1):
		for edge_id: StringName in EdgeEvents.field_edges(_graph):
			var total: float = _graph.edge_length(edge_id)
			var last: float = -1.0
			for event: Dictionary in EdgeEvents.plan(_graph, edge_id, world_seed):
				checked += 1
				var along: float = event.along
				var ok: bool = along >= 0.0 and along <= total and along >= last and event.edge == edge_id
				var point: Vector2 = event.position
				ok = ok and point.distance_to(_graph.point_at(edge_id, along)) < 0.01
				ok = ok and float(event.length) >= 0.0 and along + float(event.length) <= total + 0.01
				_check(ok, "%s of %s at %.0f m lies inside the street (%.0f m)" % [event.kind, edge_id, along, total])
				last = along
	_expect(checked > 0, "Some events were checked (%d)" % checked)


func _test_rules() -> void:
	for world_seed in range(1, SEEDS + 1):
		for edge_id: StringName in EdgeEvents.field_edges(_graph):
			var edge := _graph.edge_by_id(edge_id)
			var pieces: Array[Dictionary] = EdgePieces.plan(_graph, edge_id)
			var counts: Dictionary = {}
			for event: Dictionary in EdgeEvents.plan(_graph, edge_id, world_seed):
				counts[event.kind] = int(counts.get(event.kind, 0)) + 1
				var kind_here: StringName = _piece_kind_at(pieces, event.along)
				if event.kind == EdgeEvents.DEER or event.kind == EdgeEvents.FLOCK:
					_check(kind_here == &"straight",
							"%s on %s stands on a straight, not on a %s" % [event.kind, edge_id, kind_here])
					_check(absf(float(event.side)) == 1.0, "%s has a side" % event.kind)
				if event.kind == EdgeEvents.FLOCK:
					_check(int(event.seed) != 0, "The flock carries a seed for its members")
				if event.kind == EdgeEvents.DOG:
					_check(edge.street == EdgeEvents.DOG_STREET, "The dog waits on the farm lanes, not on %s" % edge_id)
			for kind: StringName in counts:
				_check(int(counts[kind]) <= EdgeEvents.MAX_PER_EDGE, "At most one %s on %s" % [kind, edge_id])


func _test_reused_plans() -> void:
	var field: Array[StringName] = EdgeEvents.field_edges(_graph)
	for world_seed in range(1, SEEDS + 1):
		var previous_had: bool = false
		for leg in field.size():
			var planned: Dictionary = CargoAnimalPlan.for_leg(world_seed, leg)
			var found: Array[Dictionary] = []
			for event: Dictionary in EdgeEvents.plan(_graph, field[leg], world_seed):
				if event.kind == EdgeEvents.CARGO_ANIMAL:
					found.append(event)
			_check(found.size() == (0 if planned.is_empty() else 1),
					"Leg %d (%s) has CargoAnimalPlan's animal or none" % [leg, field[leg]])
			if not found.is_empty():
				_check(found[0].animal == planned.kind, "The animal of leg %d is the planned %s" % [leg, planned.kind])
				_check(not previous_had and leg >= CargoAnimalPlan.FIRST_EVENT_LEG,
						"No animal on the first leg nor two in a row")
			previous_had = not found.is_empty()
		var draws: Array[bool] = []
		for edge_id: StringName in field:
			var hit: bool = false
			var total: float = _graph.edge_length(edge_id)
			var index: int = 1
			var at: float = EdgeEvents.LOW_VISIBILITY_SPACING
			while at <= total - EdgeEvents.LOW_VISIBILITY_MARGIN:
				hit = hit or bool(LowVisibilityPlan.draw(world_seed, hash(edge_id), index).hit)
				index += 1
				at += EdgeEvents.LOW_VISIBILITY_SPACING
			var mud: int = 0
			for event: Dictionary in EdgeEvents.plan(_graph, edge_id, world_seed):
				if event.kind == EdgeEvents.LOW_VISIBILITY:
					mud += 1
					_check(float(event.duration) >= LowVisibilityPlan.MIN_DURATION
							and float(event.duration) <= LowVisibilityPlan.MAX_DURATION,
							"The mud on %s lasts a duration the plan allows" % edge_id)
			draws.append(hit == (mud == 1))
		_check(not draws.has(false),
				"The mud on the glass is LowVisibilityPlan's first hit of each street (seed %d)" % world_seed)


func _test_cells() -> void:
	var size: float = 256.0
	var content := EdgeCellContent.new(_graph, size, SEED)
	var all: Dictionary = EdgeEvents.plan_all(_graph, SEED)
	var planned: int = 0
	for edge_id: StringName in all:
		planned += (all[edge_id] as Array).size()
	var held: int = 0
	var right_cell := true
	for cell: Vector2i in content.event_cells():
		for event: Dictionary in content.events_in(cell):
			held += 1
			var ground: Vector2 = event.position
			right_cell = right_cell and content.cell_of(Vector3(ground.x, 0.0, ground.y)) == cell
	_expect(planned > 0 and held == planned, "Every event (%d) is in exactly one cell (%d)" % [planned, held])
	_expect(right_cell, "Each event is in the cell its point lies in")
	_expect(content.events_in(Vector2i(400, 400)).is_empty(), "A cell with no street has no events")
	# Nothing existing changes with the events off: one segment per piece.
	for cell: Vector2i in content.cells():
		var node: Node3D = content.build_cell(cell)
		_check(node.get_child_count() == content.piece_count(cell),
				"Cell %s has only its pieces with spawn_events off" % cell)
		node.free()
	var cells := CompanyCells.new()
	root.add_child(cells)
	var wired: EdgeCellContent = cells.use_graph(_graph, SEED, true)
	_expect(wired.session_seed == SEED and wired.spawn_events,
			"CompanyCells.use_graph() passes the seed and the flag on")
	cells.free()


func _test_spawned_nodes() -> void:
	var content := EdgeCellContent.new(_graph, 256.0, SEED, true)
	var holder := Node3D.new()
	root.add_child(holder)
	var spawned: int = 0
	var expected: int = 0
	var placed := true
	for cell: Vector2i in content.event_cells():
		var node: Node3D = content.build_cell(cell)
		holder.add_child(node)
		var pieces: int = content.piece_count(cell)
		var made: int = node.get_child_count() - pieces
		var wanted: int = 0
		for event: Dictionary in content.events_in(cell):
			if event.kind == EdgeEvents.DEER or event.kind == EdgeEvents.FLOCK or event.kind == EdgeEvents.DOG:
				wanted += 1
		expected += wanted
		spawned += made
		_check(made == wanted, "Cell %s builds the %d deer, flock and dog nodes of its events" % [cell, wanted])
		for event: Dictionary in content.events_in(cell):
			var named: String = "%s_%s_%d" % [event.kind, event.edge, roundi(float(event.along))]
			var found: Node3D = node.get_node_or_null(NodePath(named)) as Node3D
			if found != null:
				var ground: Vector2 = event.position
				placed = placed and Vector2(found.position.x, found.position.z).distance_to(ground) < 0.01
	_expect(expected > 0 and spawned == expected, "Nodes were built for the events that have one (%d)" % spawned)
	_expect(placed, "Each node sits at its event's point")
	for i in 5:
		await physics_frame
	_expect(is_instance_valid(holder) and holder.get_child_count() > 0,
			"The cells hold their nodes after a few physics frames")
	holder.free()


func _piece_kind_at(pieces: Array[Dictionary], along: float) -> StringName:
	for piece: Dictionary in pieces:
		if along >= float(piece.start) - 0.01 and along <= float(piece.start) + float(piece.length) + 0.01:
			return piece.kind
	return &""


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: ", message)
	else:
		_failures += 1
		printerr("  FAIL: ", message)


## Like _expect() for what is checked in a loop: only a failure prints.
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FAIL: ", message)
