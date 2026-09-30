extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/route_gen/tests/test_route_gen.gd
##
## The route_gen module on its own (docs/modulos.md):
## - a SegmentStreamer seeded through its hook builds the same road twice,
##   keeps the road ahead of and behind its target, culls what's far behind,
##   never repeats a type, never puts three hard segments in a row, forces a
##   bend after MAX_STRAIGHT_STREAK straights, keeps the heading inside
##   MAX_HEADING_DEG, and answers distance_along()/distance_from_path()/
##   point_at() from the live centre line; _on_segment_spawned sees every
##   segment;
## - every code-built segment builds without assets, exits where it says,
##   and CurveSegment's exit really turns;
## - a TerrainField with a span builds tiles with the default shader, is
##   flat at its road, falls off outside, and conforms a node to the ground.

var _failures: int = 0


class SeededStreamer extends SegmentStreamer:
	var seed_value: int = 0
	var spawned: Array[String] = []

	func _session_seed() -> int:
		return seed_value

	func _on_segment_spawned(segment: RouteSegment) -> void:
		spawned.append(String(segment.get_script().get_global_name()))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	await _test_segments(scene)
	await _test_streamer(scene)
	await _test_terrain(scene)
	scene.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: segments, the streamer and the terrain field build on the module alone")
	quit(_failures)


func _test_segments(scene: Node3D) -> void:
	for script: Script in [StraightSegment, SpeedBumpSegment, SCurveSegment, GravelSegment, HillSegment]:
		var segment: RouteSegment = script.new()
		scene.add_child(segment)
		await process_frame
		_expect(segment.get_child_count() > 0 or script == HillSegment,
			"%s builds something" % script.get_global_name())
		var straight_exit: bool = segment.exit_offset.is_equal_approx(Vector3(0.0, 0.0, -segment.length))
		_expect(straight_exit and is_zero_approx(segment.exit_turn),
			"%s exits straight ahead at its length" % script.get_global_name())
		segment.free()
	var curve := CurveSegment.new()
	curve.turn_deg = 40.0
	scene.add_child(curve)
	await process_frame
	_expect(is_equal_approx(rad_to_deg(curve.exit_turn), 40.0),
		"A curve exits turned by its angle (got %.1f)" % rad_to_deg(curve.exit_turn))
	_expect(curve.exit_offset.x < -1.0 and curve.exit_offset.z < -1.0,
		"Its exit moved sideways and ahead (got %s)" % curve.exit_offset)
	_expect(curve.get_dressing_slots(10.0).size() >= 3, "A curve hands out slots along its arc")
	curve.free()


func _test_streamer(scene: Node3D) -> void:
	var target := Node3D.new()
	scene.add_child(target)
	var first := SeededStreamer.new()
	first.seed_value = 777
	first.lookahead_distance = 300.0
	scene.add_child(first)
	await process_frame
	first.start(target)
	var again := SeededStreamer.new()
	again.seed_value = 777
	again.lookahead_distance = 300.0
	scene.add_child(again)
	await process_frame
	again.start(target)
	_expect(first.spawned == again.spawned and first.spawned.size() >= 5,
		"The same seed builds the same road (%d segments)" % first.spawned.size())
	_expect(first.spawned[0] == "StraightSegment", "The first segment is the safe one")
	var no_repeat: bool = true
	var hard_run: int = 0
	var worst_hard_run: int = 0
	var straight_run: int = 0
	var worst_straight_run: int = 0
	for index: int in range(first.spawned.size()):
		var name: String = first.spawned[index]
		if index > 0 and name == first.spawned[index - 1]:
			no_repeat = false
		var hard: bool = name in ["SCurveSegment", "GravelSegment"]
		hard_run = hard_run + 1 if hard else 0
		worst_hard_run = maxi(worst_hard_run, hard_run)
		straight_run = 0 if name == "CurveSegment" else straight_run + 1
		worst_straight_run = maxi(worst_straight_run, straight_run)
	_expect(no_repeat, "No segment type repeats back to back (%s)" % [first.spawned])
	_expect(worst_hard_run <= 2, "Never three hard segments in a row (worst %d)" % worst_hard_run)
	_expect(worst_straight_run <= SegmentStreamer.MAX_STRAIGHT_STREAK + 1,
		"A bend comes after at most MAX_STRAIGHT_STREAK straights (worst %d)" % worst_straight_run)
	_expect(absf(first._heading_deg) <= SegmentStreamer.MAX_HEADING_DEG + 0.01,
		"The heading stays inside the limit (%.1f)" % first._heading_deg)
	_expect(first.next_distance() >= 300.0, "The road is built ahead of the target (%.0f m)" % first.next_distance())
	var mid: Vector3 = first.point_at(150.0)
	_expect(absf(first.distance_along(mid) - 150.0) < 1.0,
		"A point on the road is that far along it (got %.1f)" % first.distance_along(mid))
	_expect(first.distance_from_path(mid) < 0.5,
		"A point on the centre line is on the road (got %.2f)" % first.distance_from_path(mid))
	var side: Vector3 = first.point_at(60.0) + Vector3(6.0, 0.0, 0.0)
	_expect(first.distance_from_path(side) > 3.0,
		"A point beside the road is off it (got %.1f)" % first.distance_from_path(side))
	# Drive the target far down the road: what's well behind is culled.
	target.global_position = first.point_at(first.next_distance() - 10.0)
	first._physics_process(0.0)
	await process_frame
	var alive: int = 0
	for child: Node in first.get_children():
		if child is RouteSegment and not child.is_queued_for_deletion():
			alive += 1
	_expect(alive < first.spawned.size(),
		"Segments far behind the target are culled (%d alive of %d)" % [alive, first.spawned.size()])
	_expect(first.next_distance() > 500.0,
		"The road keeps growing ahead of the target (%.0f m)" % first.next_distance())
	first.free()
	again.free()
	target.free()


func _test_terrain(scene: Node3D) -> void:
	var terrain := TerrainField.new()
	scene.add_child(terrain)
	terrain.add_span(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -80.0))
	terrain.build()
	await process_frame
	var tiles: int = terrain.find_children("Terrain_*", "StaticBody3D", true, false).size()
	_expect(tiles > 0, "A span builds terrain tiles (got %d)" % tiles)
	var tile_mesh: MeshInstance3D = null
	for body: Node in terrain.find_children("Terrain_*", "StaticBody3D", true, false):
		for child: Node in body.get_children():
			if child is MeshInstance3D:
				tile_mesh = child
	_expect(tile_mesh != null and tile_mesh.material_override is ShaderMaterial
		and (tile_mesh.material_override as ShaderMaterial).shader != null, "Tiles carry the default shader material")
	_expect(is_zero_approx(terrain.height_at(Vector3(0.0, 0.0, -40.0))),
		"The ground is flat at the road (got %.2f)" % terrain.height_at(Vector3(0.0, 0.0, -40.0)))
	var far_height: float = terrain.height_at(Vector3(TerrainField.HALO - 4.0, 0.0, -40.0))
	_expect(not is_zero_approx(far_height), "Away from the road the ground rolls (got %.2f)" % far_height)
	# conform_geometry() warps a mesh's vertices onto the ground, so a box
	# placed at y=0 off the road ends up sitting on the rolling terrain.
	var prop := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.2, 1.0)
	prop.mesh = box
	prop.position = Vector3(30.0, 0.0, -40.0)
	scene.add_child(prop)
	await process_frame
	terrain.conform_geometry(prop)
	var ground: float = terrain.height_at(Vector3(30.0, 0.0, -40.0))
	var top: float = prop.mesh.get_aabb().position.y + prop.mesh.get_aabb().size.y
	_expect(prop.mesh is ArrayMesh and absf(top - (ground + 0.1)) < 0.5,
		"A mesh conforms to the ground (top %.2f, ground %.2f)" % [top, ground])
	prop.free()
	terrain.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
