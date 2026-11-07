extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/world_cells/tests/test_world_cells_parked.gd
##
## Pinned cells far from every anchor (expansion D-2012.1):
## - WorldCellGrid parks a pinned cell past load_radius and wakes it within it, with the same hysteresis a normal
##   cell loads with: once near, it stays awake up to unload_radius. `update` reports each change once. A cell
##   that is not pinned never parks, no anchors change nothing, and unpinning wakes it.
## - impostor_cells counts a parked cell, and only inside impostor_radius.
## - WorldCellStreamer keeps a parked cell's node in the tree, hidden, with its collision (a ray stops on it, and a
##   body tracked on it is not frozen) and its impostor; walking there shows the same node (no second build) and
##   clears the impostor, walking away parks it again. A parked cell keeps its impostor while it arrives, and one
##   with no node (an empty cell) gets one too.

const FAR := Vector2i(6, 0)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_grid()
	await _test_streamer()
	_test_slow_arrival()
	if _failures == 0:
		print("PASS: far pinned cells stay in the world, undrawn, behind their impostor")
	quit(_failures)


func _at(cells_east: int) -> Array[Vector3]:
	var anchors: Array[Vector3] = [Vector3(256.0 * cells_east + 10.0, 0.0, 10.0)]
	return anchors


func _test_grid() -> void:
	var grid := WorldCellGrid.new()
	grid.pin(FAR)
	var first: Dictionary = grid.update(_at(0), 0.0)
	_expect(first["park"].size() == 1 and first["park"].has(FAR),
		"A pinned cell six cells off parks (got %s)" % [first["park"]])
	_expect(grid.is_loaded(FAR) and grid.is_parked(FAR), "...and is still loaded")
	_expect(grid.update(_at(0), 1.0)["park"].is_empty(), "A change is reported once")
	_expect(not grid.impostor_cells(_at(0)).has(FAR), "Past impostor_radius it gets no stand-in")
	_expect(grid.impostor_cells(_at(1)).has(FAR), "Inside impostor_radius it does")
	_expect(not grid.is_parked(Vector2i(0, 0)), "A loaded cell that is not pinned never parks")

	var at_three: Dictionary = grid.update(_at(3), 2.0)
	_expect(at_three["wake"].is_empty() and grid.is_parked(FAR), "Three cells off, past load_radius, it stays parked")
	var at_four: Dictionary = grid.update(_at(4), 3.0)
	_expect(at_four["wake"].has(FAR) and not grid.is_parked(FAR), "Two cells off it wakes")
	_expect(not grid.impostor_cells(_at(4)).has(FAR), "Awake, it shows itself")
	grid.update(_at(3), 4.0)
	_expect(not grid.is_parked(FAR), "Three cells off, inside unload_radius, it stays awake")
	grid.update(_at(2), 5.0)
	_expect(grid.is_parked(FAR), "Four cells off it parks again")

	var none: Array[Vector3] = []
	_expect(grid.update(none, 6.0)["wake"].is_empty() and grid.is_parked(FAR), "No anchors, no change")
	var empty := WorldCellGrid.new()
	empty.pin(FAR)
	_expect(empty.update(none, 0.0)["park"].is_empty() and not empty.is_parked(FAR),
		"Before any anchor, nothing is parked")

	grid.unpin(FAR)
	var unpinned: Dictionary = grid.update(_at(2), 7.0)
	_expect(unpinned["wake"].has(FAR) and not grid.is_parked(FAR), "Unpinned, it wakes: it is a normal cell now")


func _floor_cell(cell: Vector2i) -> Node3D:
	var node := Node3D.new()
	node.name = "cell_%d_%d" % [cell.x, cell.y]
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(250.0, 1.0, 250.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(cell.x * 256.0 + 128.0, -0.5, cell.y * 256.0 + 128.0)
	node.add_child(body)
	return node


func _crate(pos: Vector3) -> RigidBody3D:
	var crate := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	shape.shape = box
	crate.add_child(shape)
	crate.position = pos
	return crate


func _settle(streamer: WorldCellStreamer, now: float) -> float:
	for i in 80:
		now += 0.3
		streamer.step(now)
		if not streamer.is_busy() and i > 2:
			break
	return now


func _impostor_at(streamer: WorldCellStreamer, cell: Vector2i) -> bool:
	var centre: Vector3 = streamer.grid.center_of(cell)
	for child: Node in streamer.get_children():
		if child is MeshInstance3D and is_equal_approx((child as Node3D).position.x, centre.x) \
				and is_equal_approx((child as Node3D).position.z, centre.z):
			return true
	return false


func _test_streamer() -> void:
	var built: Array[Vector2i] = []
	var streamer := WorldCellStreamer.new()
	streamer.grid.pin(FAR)
	streamer.build_for = func(cell: Vector2i) -> Node3D:
		built.append(cell)
		return _floor_cell(cell)
	root.add_child(streamer)
	streamer.set_process(false)  # After add_child: entering the tree turns it on. This test's clock runs step().
	streamer.grid.impostor_radius = 6
	streamer.anchors = _at(0)
	var now: float = _settle(streamer, 0.0)
	var node: Node3D = streamer.cell_node(FAR)
	_expect(node != null and node.get_parent() == streamer, "The parked cell is in the tree")
	_expect(node != null and not node.is_visible_in_tree(), "...hidden")
	_expect(_impostor_at(streamer, FAR), "...behind its impostor")
	_expect(not _impostor_at(streamer, Vector2i(1, 0)), "A normal loaded cell has no impostor")
	_expect(streamer.cell_node(Vector2i(1, 0)).visible, "...and is drawn")

	var crate := _crate(streamer.grid.center_of(FAR) + Vector3(0.0, 0.25, 0.0))
	root.add_child(crate)
	streamer.track_body(crate)
	await physics_frame
	await physics_frame
	var spot: Vector3 = streamer.grid.center_of(FAR) + Vector3(40.0, 0.0, 40.0)
	var ray := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 5.0, spot + Vector3.DOWN * 5.0)
	var hit: Dictionary = root.get_viewport().world_3d.direct_space_state.intersect_ray(ray)
	_expect(not hit.is_empty() and node.is_ancestor_of(hit.get("collider") as Node), "Its collision still stops a ray")
	now += 0.3
	streamer.step(now)
	_expect(not streamer.is_body_frozen(crate), "A body on it keeps running")

	var builds: int = built.size()
	streamer.anchors = _at(5)
	now = _settle(streamer, now + 2.0)
	_expect(streamer.cell_node(FAR) == node and node.is_visible_in_tree(), "Walking there shows the same node")
	_expect(built.count(FAR) == 1, "...without building it again (%d builds)" % built.count(FAR))
	_expect(built.size() > builds, "The cells around it load as usual")
	_expect(not _impostor_at(streamer, FAR), "...and its impostor is gone")

	streamer.anchors = _at(0)
	now = _settle(streamer, now + 2.0)
	_expect(streamer.is_loaded(FAR) and not node.is_visible_in_tree() and _impostor_at(streamer, FAR),
		"Walking away parks it again, impostor included")
	crate.queue_free()
	streamer.queue_free()
	await process_frame


## A parked cell that arrives late keeps the impostor it already had, and an empty one gets it.
func _test_slow_arrival() -> void:
	var streamer := WorldCellStreamer.new()
	root.add_child(streamer)
	streamer.grid.load_radius = 0
	streamer.grid.unload_radius = 0
	streamer.grid.impostor_radius = 7
	var empty := Vector2i(0, 3)
	streamer.grid.pin(FAR)
	streamer.grid.pin(empty)
	streamer.build_for = func(cell: Vector2i) -> Node3D:
		return null if cell == empty else _floor_cell(cell)
	streamer.slice_msec = 0.0
	streamer.anchors = _at(0)
	streamer.step(0.0)
	_expect(streamer.is_busy() and _impostor_at(streamer, FAR), "Waiting for its slice, it has its impostor")
	_settle(streamer, 0.0)
	_expect(_impostor_at(streamer, FAR), "...and keeps it when it arrives")
	_expect(not streamer.cell_node(FAR).visible, "It arrives hidden")
	_expect(streamer.is_loaded(empty) and _impostor_at(streamer, empty), "An empty parked cell has its impostor too")
	streamer.free()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)
