extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/world_cells/tests/test_world_cells_finish.gd
##
## WorldCellStreamer's second pass over a loaded cell, `finish_for` (expansion D-2012.2, the street pieces merged
## per cell):
## - It runs in the step after the one that instanced the cell, never in the same step: a step that finishes a
##   cell instances nothing more.
## - Until it is done the cell is in the tree and not drawn; then it is drawn (or stays hidden if it was parked
##   meanwhile) and `cell_finished` is emitted once. is_busy() and is_finished() say so.
## - A pass that answers `false` is not done: it is called again the next step, before any other cell; anything
##   else (true, nothing) means done.
## - A cell unloaded halfway through its pass is dropped: its pass is never called again.
## - The impostor of a cell that comes into reach stays while the cell waits for its pass (in the tree, hidden),
##   and goes in the step the cell is drawn: the cell's place is never left empty.
## - Without a finish_for a cell is drawn as soon as it is instanced, as before.

const CELL := Vector2i(0, 0)

var _failures: int = 0
## cell -> how many more times the pass answers false before it is done.
var _rounds: Dictionary = {}
var _calls: Array[Vector2i] = []
var _finished: Array[Vector2i] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_order()
	await _test_resumable()
	await _test_unload_midway()
	await _test_impostor_holds()
	await _test_without_pass()
	if _failures == 0:
		print("PASS: a streamed cell gets its second pass a step later, in slices, and is drawn only after it")
	quit(_failures)


func _streamer() -> WorldCellStreamer:
	var streamer := WorldCellStreamer.new()
	streamer.grid.cell_size = 256.0
	streamer.grid.load_radius = 0
	streamer.grid.unload_radius = 1
	streamer.grid.impostor_radius = 0
	streamer.update_interval_sec = 0.0
	streamer.build_for = func(cell: Vector2i) -> Node3D:
		var node := Node3D.new()
		node.name = "cell_%d_%d" % [cell.x, cell.y]
		return node
	streamer.finish_for = _pass
	streamer.cell_finished.connect(func(cell: Vector2i, _node: Node3D) -> void: _finished.append(cell))
	_calls.clear()
	_finished.clear()
	_rounds.clear()
	root.add_child(streamer)
	streamer.set_process(false)
	return streamer


func _pass(cell: Vector2i, _node: Node3D) -> Variant:
	_calls.append(cell)
	var left: int = int(_rounds.get(cell, 0))
	if left > 0:
		_rounds[cell] = left - 1
		return false
	return null


func _anchor_at(streamer: WorldCellStreamer, cell: Vector2i) -> void:
	var anchors: Array[Vector3] = [Vector3(cell.x * 256.0 + 128.0, 0.0, cell.y * 256.0 + 128.0)]
	streamer.anchors = anchors


func _test_order() -> void:
	var streamer := _streamer()
	_anchor_at(streamer, CELL)
	streamer.step(1.0)
	var node: Node3D = streamer.cell_node(CELL)
	_expect(node != null and node.is_inside_tree(), "The first step instances the cell")
	_expect(node != null and not node.visible, "...not drawn before its second pass")
	_expect(_calls.is_empty(), "...and its pass waits for the next step (calls %s)" % [_calls])
	_expect(streamer.is_busy() and not streamer.is_finished(CELL), "A cell owed its pass keeps the streamer busy")
	streamer.step(2.0)
	_expect(_calls == [CELL], "The next step runs the pass once (calls %s)" % [_calls])
	_expect(node != null and node.visible, "...and the cell is drawn from then on")
	_expect(_finished == [CELL], "cell_finished comes once (%s)" % [_finished])
	_expect(not streamer.is_busy() and streamer.is_finished(CELL), "Nothing more is owed")
	streamer.step(3.0)
	_expect(_calls.size() == 1 and _finished.size() == 1, "A finished cell is never passed again")
	streamer.free()


func _test_resumable() -> void:
	var streamer := _streamer()
	var order: Array[Vector2i] = []
	streamer.cell_loaded.connect(func(cell: Vector2i, _node: Node3D) -> void: order.append(cell))
	# Two cells in reach, one anchor in each: the first step instances both (an empty build is far under the slice).
	var anchors: Array[Vector3] = [Vector3(128.0, 0.0, 128.0), Vector3(384.0, 0.0, 128.0)]
	streamer.anchors = anchors
	streamer.step(1.0)
	_expect(order.size() == 2, "Two cells instanced in one step (%s)" % [order])
	if order.size() != 2:
		streamer.free()
		return
	var first: Vector2i = order[0]
	var second: Vector2i = order[1]
	_rounds[first] = 2
	var first_node: Node3D = streamer.cell_node(first)
	var second_node: Node3D = streamer.cell_node(second)
	streamer.step(2.0)
	streamer.step(3.0)
	_expect(_calls == [first, first], "A pass that answers false is called again, before any other (%s)" % [_calls])
	_expect(not first_node.visible and not second_node.visible, "...and nothing is drawn meanwhile")
	streamer.step(4.0)
	_expect(_calls.slice(0, 3) == [first, first, first], "The third call of the first cell's pass is its last")
	_expect(first_node.visible, "...then it is drawn")
	if not _calls.has(second):
		streamer.step(5.0)
	_expect(_calls.count(second) == 1 and second_node.visible, "The second cell's pass runs after it (%s)" % [_calls])
	_expect(_finished == [first, second], "cell_finished in that order (%s)" % [_finished])
	streamer.free()


func _test_unload_midway() -> void:
	var streamer := _streamer()
	_rounds[CELL] = 100
	_anchor_at(streamer, CELL)
	streamer.step(1.0)
	streamer.step(2.0)
	_expect(_calls.size() == 1, "The pass started")
	_anchor_at(streamer, Vector2i(5, 0))
	streamer.step(3.0)
	_expect(not streamer.is_loaded(CELL), "Far off, the cell unloads halfway through its pass")
	var calls: int = _calls.count(CELL)
	streamer.step(4.0)
	streamer.step(5.0)
	_expect(_calls.count(CELL) == calls, "...and its pass is never called again (%d calls)" % _calls.count(CELL))
	_expect(not _finished.has(CELL), "...nor reported finished")
	streamer.free()


func _test_impostor_holds() -> void:
	var streamer := _streamer()
	streamer.grid.impostor_radius = 2
	streamer.impostor_for = func(cell: Vector2i) -> Node3D:
		var block := Node3D.new()
		block.name = "imp_%d_%d" % [cell.x, cell.y]
		return block
	var next_door := Vector2i(1, 0)
	_anchor_at(streamer, next_door)
	streamer.step(1.0)
	streamer.step(2.0)
	_expect(streamer.get_node_or_null(^"imp_0_0") != null, "A cell near the anchor but out of reach has an impostor")
	_rounds[CELL] = 2
	_anchor_at(streamer, CELL)
	streamer.step(3.0)
	var node: Node3D = streamer.cell_node(CELL)
	_expect(node != null and not node.visible, "In reach, the cell is instanced and waits for its pass, hidden")
	_expect(streamer.get_node_or_null(^"imp_0_0") != null, "...and its impostor holds its place meanwhile")
	streamer.step(4.0)
	streamer.step(5.0)
	_expect(not streamer.is_finished(CELL) and streamer.get_node_or_null(^"imp_0_0") != null,
		"...through every step its pass answers false")
	streamer.step(6.0)
	_expect(streamer.is_finished(CELL) and node.visible, "The pass done, the cell is drawn")
	_expect(streamer.get_node_or_null(^"imp_0_0") == null, "...and its impostor goes in that same step")
	streamer.free()


func _test_without_pass() -> void:
	var streamer := _streamer()
	streamer.finish_for = Callable()
	_anchor_at(streamer, CELL)
	streamer.step(1.0)
	var node: Node3D = streamer.cell_node(CELL)
	_expect(node != null and node.visible, "Without a second pass a cell is drawn as soon as it is instanced")
	_expect(not streamer.is_busy() and streamer.is_finished(CELL), "...and owes nothing")
	_expect(_finished.is_empty(), "...and no cell_finished is emitted")
	streamer.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
