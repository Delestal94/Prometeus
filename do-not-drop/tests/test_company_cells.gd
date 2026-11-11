extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_cells.gd
##
## The company map's cells (expansion D-0303, scripts/gameplay/districts/company_cells.gd):
## - CompanyCells takes its numbers from CompanyTuning (256 m cells, load 2, unload 3) and
##   pins the cells of the shed and of the three main streets before anyone moves;
## - driving a van from the shed to the first Centro house (1000 m east at 12 m/s) in 60 fps
##   steps never costs a step over 50 ms, keeps the 5 x 5 square around it loaded, and drops
##   the cells it leaves behind except the pinned ones;
## - ten cells in a row (D-0313) keep the same limit and never touch the loader;
## - coming back to the shed leaves exactly the pinned cells and the square around the shed,
##   no cell node outside the tree's children and no orphan node.
##
## The same drive on the REAL cells (D-0303.1, the measured criterion of corte-vertical.md §4): a
## CompanyCells fed like CompanyRoot._add_cells() feeds its own (use_graph on data/world/road_graph.tres:
## the streets' pieces, CentroDecor's sidewalks, lights and the 30 houses of data/world/houses.tres),
## with the van following RoadNavigator.route() from the shed to the Centro house with the longest way
## there, and back, at 14 m/s:
## - a frame takes ONE heavy thing: a house never enters the tree in the frame a cell with content did,
##   and never two houses in one frame, whatever cells they belong to (CentroDecor.take_frame /
##   hold_houses; before, every cell let one in per frame: a cell and two or three houses took 40 to 47
##   of the 50 ms on the way to Centro);
## - no frame of the drive brings more than 50 ms of work for the cells, and the last house is standing
##   in its cell, with its streets and its Centro node, when the van gets there;
## - back at the shed nothing is left but the pinned cells and the ones around it, and no orphan.
## What it times, and why it is not a whole frame: per 60 fps step, CompanyCells.step() (the cells
## built and put in the tree inside the streamer's slice) plus every house that enters the tree in the
## real process frame that follows (from child_entered_tree to the house's `ready`; the drips run by
## themselves, as in the game). Headless, so no GPU upload: the window's number is bench_company's
## (D-2011.1). The limit is the criterion's own 50 ms, over 2.5 times the worst this measures on a
## busy PC (15 to 19 ms: one house). A whole frame's clock is not used because on a busy machine an
## empty frame takes 50 to 100 ms now and then; for the same reason a frame over the limit is driven
## again, up to three drives, each on new cells: only something that is in a frame over the limit in
## EVERY drive fails. The catch: a cost paid only the first time something is used (a model's first
## load) shows only in the first drive, so the PASS line prints that drive's worst frames. The frames
## while the map settles at the shed, before the van moves, are printed and not limited: they are the
## start's (D-0313), and their worst is one cell of street pieces (30 ms, 90 the first time).

const FRAME_LIMIT_USEC: int = 50000
## The fastest typical speed of a street (CompanyTuning.SURFACE_SPEED, asphalt): the cells come quickest.
const DRIVE_SPEED: float = 14.0
const MAX_DRIVES: int = 3
## Steps a drive waits at most for the cells and their houses to be all in.
const SETTLE_STEPS: int = 2000
const NOTHING_NEW: String = "(nothing entering)"
## The parts of a drive, as the keys of its report.
const START: String = "start"
const OUT: String = "out"
const BACK: String = "back"

var _failures: int = 0
## The real cells of the drive under way, their drips with houses still to come, and what entered the
## tree in the step being timed.
var _real: CompanyCells
var _drips: Array[Node] = []
var _step_cells: PackedStringArray = []
var _step_houses: PackedStringArray = []
var _house_started_usec: int = 0
var _house_usec: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cells := CompanyCells.new()
	root.add_child(cells)
	_expect(is_equal_approx(cells.grid.cell_size, CompanyTuning.CELL_SIZE), "Cells are CELL_SIZE wide")
	_expect(cells.grid.load_radius == 2 and cells.grid.unload_radius == 3, "Radius 2, unload 3")
	for z in range(-1, 2):
		for x in range(-1, 2):
			_expect(cells.grid.is_pinned(Vector2i(x, z)), "The shed's cell (%d, %d) is pinned" % [x, z])
	_expect(cells.grid.is_pinned(Vector2i(4, 0)), "The Avenida Este is pinned up to the port")
	_expect(cells.grid.is_pinned(Vector2i(0, 3)), "The Camino del Campo is pinned")
	_expect(cells.grid.is_pinned(Vector2i(-4, -1)), "The Calle Oeste is pinned")
	_expect(not cells.grid.is_pinned(Vector2i(0, -6)), "The mountains are not")

	var orphans_before := _orphans()
	var van := Vector3(0, 0, 0)
	cells.anchors = [van]
	var now := 0.0
	var worst := 0
	var fine := true
	var steps := int(1000.0 / 12.0 * 60.0)
	for i in steps:
		now += 1.0 / 60.0
		van.x += 12.0 / 60.0
		cells.anchors = [van]
		var t0 := Time.get_ticks_usec()
		cells.step(now)
		worst = maxi(worst, Time.get_ticks_usec() - t0)
		if i % 60 == 59:
			fine = fine and _square_loaded(cells, van, 1)
	_expect(worst < FRAME_LIMIT_USEC, "No step over 50 ms driving to Centro (worst %d us)" % worst)
	_expect(fine, "The cells around the van were loaded every second")
	_expect(cells.is_loaded(Vector2i(0, 0)), "The shed's cell is still there (pinned)")
	_expect(not cells.is_loaded(Vector2i(-2, 2)), "A cell the van left behind is gone")

	# D-0313: ten cells in a row (2560 m), also worst frame under the limit; the loader is not used.
	var long_van := Vector3(0, 0, 0)
	cells.anchors = [long_van]
	cells.step(now + 1.0)
	var far_worst := 0
	for i in int(2560.0 / 12.0 * 60.0):
		now += 1.0 / 60.0
		long_van.x += 12.0 / 60.0
		cells.anchors = [long_van]
		var t1 := Time.get_ticks_usec()
		cells.step(now)
		far_worst = maxi(far_worst, Time.get_ticks_usec() - t1)
	_expect(far_worst < FRAME_LIMIT_USEC, "No step over 50 ms crossing 10 cells (worst %d us)" % far_worst)
	_expect(_square_loaded(cells, long_van, 1), "The cells around the van after 10 cells are loaded")
	_expect(root.get_node_or_null(^"SceneLoader") == null, "Streaming never goes through the loader")
	van = Vector3(0, 0, 0)

	# Back to the shed.
	van = Vector3(10, 0, 10)
	cells.anchors = [van]
	cells.step(now + 1.0)
	cells.step(now + 2.0)
	_expect_only_near_or_pinned(cells, "the empty cells")
	cells.queue_free()
	for i in 3:
		await process_frame
	_expect(_orphans() <= orphans_before, "No orphan node is left")

	var summary: String = await _check_real_cells()
	if _failures == 0:
		print("PASS: the company cells follow the van to Centro and back without a long step or leftovers; "
				+ summary)
	quit(_failures)


# --- The real cells (D-0303.1) ----------------------------------------------------------------------


## Drives to the last house of Centro and back on the real cells, again when a frame went over the limit
## (see the header). Returns what the first drive measured, for the PASS line.
func _check_real_cells() -> String:
	var graph: RoadGraph = RoadGraph.load_default()
	var map: HouseMap = HouseMap.load_default()
	_expect(graph != null and map != null, "The road graph and the houses load")
	if graph == null or map == null:
		return ""
	var way: Dictionary = {}
	var last: HouseSpot = null
	for spot: HouseSpot in map.in_zone(CentroDecor.ZONE):
		var found: Dictionary = RoadNavigator.route(graph, Vector2.ZERO, spot.position)
		if found.get("ok", false) and (way.is_empty() or float(found.length) > float(way.length)):
			way = found
			last = spot
	_expect(last != null and float(way.get("length", 0.0)) > 2.0 * CompanyTuning.CELL_SIZE,
			"The GPS finds the way from the shed to the last house of Centro, cells away (%.0f m)"
			% float(way.get("length", 0.0)))
	if last == null:
		return ""
	var orphans_before := _orphans()
	# What was in a frame over the limit in every drive so far: { name: worst usec }.
	var suspects: Dictionary = {}
	var first: Dictionary = {}
	var drives: int = 0
	while drives < MAX_DRIVES:
		var drive: Dictionary = await _drive(graph, way.polyline, last)
		drives += 1
		var over: Dictionary = drive.over
		if drives == 1:
			first = drive
			suspects = over
		else:
			for item: String in suspects.keys():
				if over.has(item):
					suspects[item] = maxi(int(suspects[item]), int(over[item]))
				else:
					suspects.erase(item)
		if suspects.is_empty():
			break
	_expect(suspects.is_empty(),
			"No frame of the drive on the real cells brings 50 ms of work (in each of %d drives these did, usec: %s)"
			% [drives, suspects])
	_expect(_orphans() <= orphans_before,
			"No orphan node is left by the real cells (%d, were %d)" % [_orphans(), orphans_before])
	return ("on the real cells the worst frame was %.1f ms out to %s and %.1f ms back"
			+ " (%.1f ms settling at the shed, %d drive(s))") % [int(first[OUT]) / 1000.0, last.id,
			int(first[BACK]) / 1000.0, int(first[START]) / 1000.0, drives]


## One drive on new cells: settle at the shed, out along `line`, back. Returns the worst frame (usec) of each
## part (START, OUT, BACK) and `over`: { what entered: usec } of the frames of OUT and BACK over the limit.
func _drive(graph: RoadGraph, line: PackedVector2Array, last: HouseSpot) -> Dictionary:
	# From here every step runs in a process frame's own signal: the step and the nodes' _process that
	# follows it share the frame, as CompanyCells._process and the drips' do in the game.
	await process_frame
	var lengths := PackedFloat32Array([0.0])
	for i in line.size() - 1:
		lengths.append(lengths[i] + line[i].distance_to(line[i + 1]))
	var total: float = lengths[lengths.size() - 1]
	# The cells as CompanyRoot._add_cells() makes them: the graph's streets, Centro's decor, no events,
	# the shed's ground left clear. Stepped here on the drive's clock, not by _process on the real one
	# (turned off once in the tree: entering it turns it on).
	var shed := Node3D.new()
	var clear: Rect2 = CompanyCells.shed_ground(shed)
	shed.free()
	_real = CompanyCells.new()
	root.add_child(_real)
	_real.set_process(false)
	_real.cell_loaded.connect(_on_real_cell)
	_real.use_graph(graph, 0, false, clear)
	_drips.clear()
	var report: Dictionary = {START: 0, OUT: 0, BACK: 0, "over": {}, "crowded": 0, "example": ""}
	var now: float = 0.0
	_real.anchors = [_ground(line[0])]
	now = await _settle(now, report, START, false)
	var end: Vector3 = _ground(line[line.size() - 1])
	for leg: String in [OUT, BACK]:
		var along: float = 0.0
		while along < total:
			along = minf(total, along + DRIVE_SPEED / 60.0)
			now += 1.0 / 60.0
			_real.anchors = [_ground(_point_at(line, lengths, along if leg == OUT else total - along))]
			await _step(now, report, leg, true)
		now = await _settle(now, report, leg, true)
		if leg == OUT:
			_expect_arrived(end, last)
	_expect(int(report.crowded) == 0,
			("A frame takes one house, and none with a cell that has content (%d frames did not; the first: %s;"
			+ " worst frame %.1f ms out, %.1f ms back, %.1f ms settling at the shed)")
			% [int(report.crowded), report.example, int(report[OUT]) / 1000.0, int(report[BACK]) / 1000.0,
			int(report[START]) / 1000.0])
	_expect_only_near_or_pinned(_real, "the real cells")
	_real.queue_free()
	_real = null
	_drips.clear()
	for i in 3:
		await process_frame
	return report


## One 60 fps step: the streamer's own, then, with houses waiting, the real frame in which the drips let
## them in. Adds up what it cost and writes down what entered.
func _step(now: float, report: Dictionary, phase: String, limited: bool) -> void:
	_step_cells.clear()
	_step_houses.clear()
	_house_usec = 0
	var started: int = Time.get_ticks_usec()
	_real.step(now)
	var usec: int = Time.get_ticks_usec() - started
	if _houses_waiting():
		await process_frame
		usec += _house_usec
	report[phase] = maxi(int(report[phase]), usec)
	var houses: int = _step_houses.size()
	if houses > CentroDecor.HOUSES_PER_FRAME or (houses > 0 and not _step_cells.is_empty()):
		report.crowded = int(report.crowded) + 1
		if String(report.example).is_empty():
			report.example = "%s with %s" % [_step_houses, _step_cells]
	if limited and usec >= FRAME_LIMIT_USEC:
		var entered: PackedStringArray = _step_cells + _step_houses
		if entered.is_empty():
			entered.append(NOTHING_NEW)
		var over: Dictionary = report.over
		for item: String in entered:
			over[item] = maxi(int(over.get(item, 0)), usec)


## Steps in place until every cell asked for and every house of theirs is in.
func _settle(now: float, report: Dictionary, phase: String, limited: bool) -> float:
	var steps: int = 0
	while steps < SETTLE_STEPS:
		now += 1.0 / 60.0
		await _step(now, report, phase, limited)
		steps += 1
		if not _real.is_busy() and not _houses_waiting():
			break
	_expect(steps < SETTLE_STEPS, "The real cells and their houses are all in (%d steps)" % steps)
	return now


func _houses_waiting() -> bool:
	var waiting: Array[Node] = []
	for drip: Node in _drips:
		if is_instance_valid(drip) and drip.is_inside_tree() and not (drip.get(&"pending") as Array).is_empty():
			waiting.append(drip)
	_drips = waiting
	return not _drips.is_empty()


func _on_real_cell(_cell: Vector2i, node: Node3D) -> void:
	if node == null or node.get_child_count() == 0:
		return
	_step_cells.append(String(node.name))
	var drip: Node = node.get_node_or_null(^"Centro/Houses")
	if drip != null:
		drip.child_entered_tree.connect(_on_house_entering)
		_drips.append(drip)


## A house's whole cost is its _ready (walls, model, doorbell, resident): from here to its `ready`.
func _on_house_entering(house: Node) -> void:
	_house_started_usec = Time.get_ticks_usec()
	house.ready.connect(_on_house_ready.bind(house), CONNECT_ONE_SHOT)


func _on_house_ready(house: Node) -> void:
	_house_usec += Time.get_ticks_usec() - _house_started_usec
	_step_houses.append(String(house.name))


## With the van at the end of the way: the cells around it are in, the one it stands on is a real one
## (streets and Centro) and the last house stands in its own.
func _expect_arrived(at: Vector3, last: HouseSpot) -> void:
	_expect(_square_loaded(_real, at, _real.grid.load_radius),
			"The cells around the van at the last house are loaded")
	var here: Node3D = _real.cell_node(_real.grid.cell_of(at))
	var streets: int = 0
	if here != null:
		for piece: Node in here.get_children():
			if piece is RouteSegment:
				streets += 1
	_expect(streets > 0 and here.get_node_or_null(^"Centro") != null,
			"The van's cell holds its streets and Centro's decor (%d pieces)" % streets)
	var home: Node3D = _real.cell_node(_real.grid.cell_of(_ground(last.position)))
	var house: Node = home.get_node_or_null("Centro/Houses/%s" % last.id) if home != null else null
	_expect(house is DeliveryHouse and house.is_inside_tree(),
			"%s stands in its cell when the van gets there" % last.id)


func _ground(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)


## The point `distance` meters along the polyline (`lengths`: meters walked at each of its points).
func _point_at(line: PackedVector2Array, lengths: PackedFloat32Array, distance: float) -> Vector2:
	var next: int = clampi(lengths.bsearch(distance), 1, line.size() - 1)
	var piece: float = lengths[next] - lengths[next - 1]
	if piece <= 0.0:
		return line[next]
	return line[next - 1].lerp(line[next], clampf((distance - lengths[next - 1]) / piece, 0.0, 1.0))


# --- Helpers ---------------------------------------------------------------------------------------


## Back at the shed: nothing loaded but the pinned cells and the ones near the anchor, one node each.
func _expect_only_near_or_pinned(cells: CompanyCells, which: String) -> void:
	for cell: Vector2i in cells.loaded_cells():
		if cells.grid.distance_to_anchors(cell, cells.anchors) > 3 and not cells.grid.is_pinned(cell):
			_expect(false, "Cell %s of %s should be gone back at the shed" % [cell, which])
	var nodes := 0
	for child in cells.get_children():
		if child.name.begins_with("Cell_"):
			nodes += 1
	_expect(nodes == cells.loaded_cells().size(),
			"Every loaded cell of %s is one node, nothing else stays (%d nodes, %d cells)"
			% [which, nodes, cells.loaded_cells().size()])


func _square_loaded(cells: CompanyCells, pos: Vector3, radius: int) -> bool:
	var own := cells.grid.cell_of(pos)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if not cells.is_loaded(Vector2i(own.x + dx, own.y + dz)):
				return false
	return true


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
