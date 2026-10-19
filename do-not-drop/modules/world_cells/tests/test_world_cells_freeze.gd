extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/world_cells/tests/test_world_cells_freeze.gd
##
## WorldCellStreamer.track_body (expansion D-0318): a crate left on a sidewalk
## far away stays where it is. While its cell is not instanced (no floor under
## it) the crate is frozen with its velocities saved, an untracked twin falls
## into the void, and when the cell is back the crate thaws at the same place
## (within 5 cm) and keeps resting on the floor. A crate the game had frozen
## itself stays frozen after the round trip, and a freed crate is forgotten.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_freeze_far_away()
	_test_game_frozen_stays_frozen()
	if _failures == 0:
		print("PASS: a crate in an unloaded cell stays put and thaws when the cell is back")
	quit(_failures)


func _floor_cell(cell: Vector2i) -> Node3D:
	var node := Node3D.new()
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


func _test_freeze_far_away() -> void:
	var streamer := WorldCellStreamer.new()
	streamer.build_for = _floor_cell
	streamer.slice_msec = 1000.0
	root.add_child(streamer)
	streamer.anchors = [Vector3(50, 0, 50)]
	var now := 0.0
	streamer.step(now)
	var tracked := _crate(Vector3(100, 0.26, 100))
	var twin := _crate(Vector3(110, 0.26, 100))
	root.add_child(tracked)
	twin.can_sleep = false
	root.add_child(twin)
	streamer.track_body(tracked)
	for i in 30:
		await physics_frame
	streamer.step(now)
	_expect(not streamer.is_body_frozen(tracked), "In a loaded cell the crate runs")
	var rest := tracked.global_position
	_expect(absf(rest.y - 0.25) < 0.05, "...and rests on the floor")
	tracked.linear_velocity = Vector3(0.0, 0.0, 0.0)
	# The crew drives 8 cells away: cell (0, 0) unloads, nothing is under the crate.
	streamer.anchors = [Vector3(256 * 8 + 50, 0, 50)]
	now += 5.0
	streamer.step(now)
	_expect(not streamer.is_loaded(Vector2i(0, 0)), "The far cell unloaded")
	_expect(streamer.is_body_frozen(tracked), "The crate in it froze")
	for i in 60:
		await physics_frame
	_expect(tracked.global_position.distance_to(rest) < 0.05, "The frozen crate did not move")
	_expect(twin.global_position.y < -1.0, "An untracked crate fell through the missing floor")
	# Back home: the cell loads again and the crate thaws where it was.
	streamer.anchors = [Vector3(50, 0, 50)]
	now += 5.0
	for i in 5:
		now += 0.5
		streamer.step(now)
	_expect(streamer.is_loaded(Vector2i(0, 0)), "The cell is back")
	_expect(not streamer.is_body_frozen(tracked) and not tracked.freeze, "The crate thawed")
	for i in 30:
		await physics_frame
	_expect(tracked.global_position.distance_to(rest) < 0.05, "It is where it was, on the floor")
	streamer.untrack_body(tracked)
	streamer.queue_free()
	tracked.queue_free()
	twin.queue_free()
	await process_frame


func _test_game_frozen_stays_frozen() -> void:
	var streamer := WorldCellStreamer.new()
	streamer.build_for = _floor_cell
	streamer.slice_msec = 1000.0
	root.add_child(streamer)
	streamer.anchors = [Vector3(50, 0, 50)]
	var held := _crate(Vector3(100, 0.26, 100))
	held.freeze = true
	held.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	root.add_child(held)
	streamer.track_body(held)
	var now := 0.0
	streamer.step(now)
	streamer.step(now)
	_expect(held.freeze and held.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC,
		"A crate the game froze keeps its mode while its cell is loaded")
	streamer.anchors = [Vector3(256 * 8 + 50, 0, 50)]
	now += 5.0
	streamer.step(now)
	streamer.anchors = [Vector3(50, 0, 50)]
	for i in 6:
		now += 1.0
		streamer.step(now)
	_expect(held.freeze and held.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC,
		"...and after the round trip: the game's own freeze is not undone")
	held.free()
	streamer.step(now + 1.0)
	streamer.queue_free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
