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
##   segment; _limit_candidates takes types out of the draw and _pick_weight
##   sets their odds (a pool of one that is also limited still builds);
## - GripZones: two zones over one vehicle in either order leave the lowest
##   grip while either holds and the original when both are gone; entering
##   twice never compounds;
## - every code-built segment builds without assets, exits where it says,
##   and CurveSegment's exit really turns;
## - a TerrainField with a span builds tiles with the default shader, is
##   flat at its road, falls off outside, and conforms a node to the ground;
## - the sliced build (N-408): build_async() makes the very same tiles as
##   build() (vertices, normals, paint, triangles, walls) with its numbers
##   worked out on worker threads and its scene objects made a frame at a
##   time, and conform_all() warps the very same meshes (and moves the same
##   rigid parts) as conform_geometry() node by node.

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
	await _test_hooks(scene)
	_test_grip_zones(scene)
	await _test_terrain(scene)
	await _test_sliced_terrain(scene)
	await _test_sliced_conform(scene)
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


class LimitedStreamer extends SeededStreamer:
	func _limit_candidates(candidates: Array[Script]) -> Array[Script]:
		var kept: Array[Script] = candidates.filter(func(s: Script) -> bool: return s != GravelSegment)
		return kept if not kept.is_empty() else candidates

	func _pick_weight(script: Script, hard_weight: float) -> float:
		return 0.0 if script == SCurveSegment else super(script, hard_weight)


func _test_hooks(scene: Node3D) -> void:
	var target := Node3D.new()
	scene.add_child(target)
	var streamer := LimitedStreamer.new()
	streamer.seed_value = 4242
	streamer.lookahead_distance = 1500.0
	scene.add_child(streamer)
	await process_frame
	streamer.start(target)
	_expect(streamer.spawned.size() >= 10, "The limited streamer builds a long road (%d)" % streamer.spawned.size())
	_expect(not streamer.spawned.has("GravelSegment"), "_limit_candidates kept a type out of the draw")
	_expect(not streamer.spawned.has("SCurveSegment"), "A zero _pick_weight means never drawn")
	_expect(streamer.spawned.has("StraightSegment") and streamer.spawned.has("CurveSegment"),
		"The rest still get drawn")
	var lone := LimitedStreamer.new()
	lone.seed_value = 1
	lone.segment_scripts = [GravelSegment]
	lone.first_segment_script = null
	lone.lookahead_distance = 50.0
	scene.add_child(lone)
	await process_frame
	lone.start(target)
	_expect(lone.spawned.size() >= 1, "A limit that would leave nothing gives way")
	lone.free()
	streamer.free()
	target.free()


func _test_grip_zones(scene: Node3D) -> void:
	var vehicle := VehicleBody3D.new()
	vehicle.add_to_group(&"vehicle")
	for index: int in range(2):
		var wheel := VehicleWheel3D.new()
		wheel.wheel_friction_slip = 3.5
		vehicle.add_child(wheel)
	scene.add_child(vehicle)
	var wet := Node.new()
	var ice := Node.new()
	GripZones.enter(vehicle, wet, 1.2)
	GripZones.enter(vehicle, wet, 1.2)
	_expect(_slips_are(vehicle, 1.2), "A zone lowers the wheels' grip (%s)" % [_slips(vehicle)])
	GripZones.enter(vehicle, ice, 0.6)
	_expect(_slips_are(vehicle, 0.6), "Two zones: the lowest holds (%s)" % [_slips(vehicle)])
	GripZones.leave(vehicle, ice)
	_expect(_slips_are(vehicle, 1.2), "Leaving the lower one leaves the other's grip (%s)" % [_slips(vehicle)])
	GripZones.leave(vehicle, wet)
	_expect(_slips_are(vehicle, 3.5), "Leaving the last restores the original, once (%s)" % [_slips(vehicle)])
	_expect(not vehicle.has_meta(GripZones.ZONES_META), "...and leaves nothing registered on the vehicle")
	# Other order: the second zone is entered while the first is held, and the first leaves first.
	GripZones.enter(vehicle, ice, 0.6)
	GripZones.enter(vehicle, wet, 1.2)
	GripZones.leave(vehicle, ice)
	_expect(_slips_are(vehicle, 1.2), "The other order: the remaining zone's grip stays (%s)" % [_slips(vehicle)])
	GripZones.leave(vehicle, wet)
	_expect(_slips_are(vehicle, 3.5), "...and the original is still 3.5 at the end (%s)" % [_slips(vehicle)])
	wet.free()
	ice.free()
	vehicle.free()


func _slips_are(vehicle: Node, expected: float) -> bool:
	for slip: Variant in _slips(vehicle):
		if not is_equal_approx(float(slip), expected):
			return false
	return true


func _slips(vehicle: Node) -> Array:
	var out: Array = []
	for child: Node in vehicle.get_children():
		if child is VehicleWheel3D:
			out.append((child as VehicleWheel3D).wheel_friction_slip)
	return out


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
	_expect(again._unbatched.is_empty(), "start() leaves every starting segment merged")
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
	# A segment is merged on a tick after the one that built it, one per tick
	# (N-219): start() leaves none waiting, a spawning tick leaves its own
	# waiting, quiet ticks drain them, and flush_batches() clears the rest.
	again.flush_batches()
	target.global_position = again.point_at(again.next_distance() - 10.0)
	again._physics_process(0.0)
	_expect(not again._unbatched.is_empty(), "A tick that spawns leaves its segment to merge on the next one")
	var waiting: int = again._unbatched.size()
	again._physics_process(0.0)
	_expect(again._unbatched.size() == waiting - 1,
		"The next tick merges one (%d -> %d)" % [waiting, again._unbatched.size()])
	for _tick: int in range(waiting):
		again._physics_process(0.0)
	_expect(again._unbatched.is_empty(), "Quiet ticks drain the queue")
	again._spawn_next()
	again._spawn_next()
	_expect(again._unbatched.size() == 2, "Fresh segments wait to be merged")
	again.flush_batches()
	_expect(again._unbatched.is_empty(), "flush_batches() merges everything pending")
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


## A bendy road with the lot: a river under a bridge, a crest, a pad, a flat zone,
## a platform, a tunnel and a footpath, so every term of the height field is there.
func _fill_terrain(terrain: TerrainField) -> void:
	terrain.add_span(Vector3(0.0, 0.0, 20.0), Vector3(0.0, 0.0, -90.0))
	terrain.add_span(Vector3(0.0, 0.0, -90.0), Vector3(60.0, 0.0, -170.0), true, 7.0)
	terrain.add_span(Vector3(60.0, 0.0, -170.0), Vector3(70.0, 0.0, -300.0))
	terrain.paths.append({"a": Vector2(3.0, -20.0), "b": Vector2(14.0, -34.0)})
	terrain.paths.append({"a": Vector2(300.0, 300.0), "b": Vector2(310.0, 300.0)})  # Nowhere near.
	terrain.rivers.append({"a": Vector2(-20.0, -50.0), "b": Vector2(20.0, -50.0), "depth": 2.0,
		"full_width": 12.0, "bank_width": 30.0})
	terrain.crests.append({"a": Vector2(60.0, -170.0), "b": Vector2(70.0, -250.0), "height": 4.0})
	terrain.pads.append(Vector3(12.0, 0.7, -10.0))
	terrain.flat_zones.append(Rect2(-15.0, 4.0, 30.0, 16.0))
	terrain.platforms.append({"centre": Vector2(70.0, -300.0), "along": Vector2(0.0, -1.0),
		"half": Vector2(10.0, 20.0), "height": 1.5})
	terrain.tunnels.append({"at": Vector2(66.0, -230.0), "dir": Vector2(0.0, -1.0), "level": 0.5,
		"bore_half": 3.0, "bore_length": 20.0, "crown": 5.0, "face_half": 6.0, "height": 9.0})


## Every tile body of `terrain` by name, with its mesh's arrays and how many shapes it carries.
func _tiles_of(terrain: TerrainField) -> Dictionary:
	var tiles: Dictionary = {}
	for body: Node in terrain.find_children("Terrain_*", "StaticBody3D", true, false):
		var entry: Dictionary = {"shapes": 0}
		for child: Node in body.get_children():
			if child is MeshInstance3D:
				entry["arrays"] = (child as MeshInstance3D).mesh.surface_get_arrays(0)
			elif child is CollisionShape3D:
				entry["shapes"] = int(entry["shapes"]) + 1
		tiles[body.name] = entry
	return tiles


func _test_sliced_terrain(scene: Node3D) -> void:
	var blocking := TerrainField.new()
	var sliced := TerrainField.new()
	scene.add_child(blocking)
	scene.add_child(sliced)
	_fill_terrain(blocking)
	_fill_terrain(sliced)
	blocking.build()
	# A budget of nothing: every step gives the frame back, so this really is sliced.
	var slicer := FrameSlicer.new(self, 0.0)
	await sliced.build_async(slicer)
	var expected: Dictionary = _tiles_of(blocking)
	var got: Dictionary = _tiles_of(sliced)
	_expect(expected.size() > 20, "The test field has tiles (%d)" % expected.size())
	_expect(got.keys() == expected.keys(), "The sliced build makes the same tiles, in the same order")
	_expect(slicer.frames_waited >= expected.size(),
		"It gave the frame back between tiles (%d frames for %d tiles)" % [slicer.frames_waited, expected.size()])
	var different: int = 0
	var holes: int = 0
	for tile_name: Variant in expected:
		var a: Dictionary = expected[tile_name]
		var b: Dictionary = got.get(tile_name, {})
		if b.is_empty() or a.arrays != b.arrays or a.shapes != b.shapes:
			different += 1
		if (a.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() < 16 * 16 * 6:
			holes += 1
	_expect(different == 0, "Every tile is identical to the blocking build's (%d differ)" % different)
	_expect(holes > 0, "Some tiles have holes where the tunnel's bore is, so that path was compared too")
	_expect(is_equal_approx(sliced.build_progress, 1.0), "build_progress ends at 1")
	_expect(sliced.find_children("RiverWater", "MeshInstance3D", true, false).size() == 1,
		"The river's water was built")
	for point: Vector3 in [Vector3(0.0, 0.0, -40.0), Vector3(25.0, 0.0, -50.0), Vector3(31.3, 0.0, -140.7),
			Vector3(70.0, 0.0, -220.0), Vector3(-45.0, 0.0, 12.0)]:
		_expect(blocking.height_at(point) == sliced.height_at(point), "The same ground at %s" % point)
	blocking.free()
	sliced.free()
	# Freed (queue_free, as a scene change does) while its workers still run: it
	# waits for them instead of pulling the field from under their feet.
	var dropped := TerrainField.new()
	scene.add_child(dropped)
	_fill_terrain(dropped)
	dropped.build_async(FrameSlicer.new(self, 0.0))
	await process_frame
	dropped.queue_free()
	await process_frame
	await process_frame
	_expect(not is_instance_valid(dropped), "A field dropped mid-build goes away")


## A little of everything conform_geometry() meets under one parent.
func _conform_props(parent: Node3D) -> void:
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.0, 0.2, 9.0)
	board.mesh = box
	board.name = "Board"
	board.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(18.0, 0.3, -30.0))
	parent.add_child(board)
	# A solid with a collision shape, two meshes under it (the last one's shape stays).
	var body := StaticBody3D.new()
	body.name = "Solid"
	parent.add_child(body)
	for index: int in range(2):
		var strip := MeshInstance3D.new()
		var surface := PlaneMesh.new()
		surface.size = Vector2(6.0, 11.0)
		strip.mesh = surface
		strip.name = "Strip%d" % index
		strip.position = Vector3(10.0 + float(index) * 7.0, 0.0, -60.0)
		body.add_child(strip)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	# A bridge's furniture measures itself against the ground without the river.
	var bridge := Node3D.new()
	bridge.name = "Bridge"
	bridge.set_meta(&"ignore_river", true)
	bridge.position = Vector3(-4.0, 0.0, -50.0)
	parent.add_child(bridge)
	var deck := MeshInstance3D.new()
	var deck_box := BoxMesh.new()
	deck_box.size = Vector3(6.0, 0.3, 40.0)
	deck.mesh = deck_box
	deck.name = "Deck"
	bridge.add_child(deck)
	var trigger := Area3D.new()
	trigger.name = "Trigger"
	trigger.position = Vector3(8.0, 0.0, -25.0)
	parent.add_child(trigger)
	var label := Label3D.new()
	label.position = Vector3(-9.0, 2.0, -75.0)
	parent.add_child(label)
	var rigid := Node3D.new()
	rigid.name = "Rigid"
	rigid.set_meta(&"rigid", true)
	rigid.position = Vector3(25.0, 0.0, -100.0)
	parent.add_child(rigid)
	var rigid_part := MeshInstance3D.new()
	rigid_part.mesh = BoxMesh.new()
	rigid.add_child(rigid_part)  # Not warped: it rides with its parent.


func _test_sliced_conform(scene: Node3D) -> void:
	var one := TerrainField.new()
	var other := TerrainField.new()
	one.position = Vector3(3.0, 0.0, 0.0)
	other.position = Vector3(3.0, 0.0, 0.0)
	var left := Node3D.new()
	var right := Node3D.new()
	left.rotation.y = 0.2
	right.rotation.y = 0.2
	scene.add_child(one)
	scene.add_child(other)
	scene.add_child(left)
	scene.add_child(right)
	_fill_terrain(one)
	_fill_terrain(other)
	_conform_props(left)
	_conform_props(right)
	one.build()
	other.build()
	for child: Node in left.get_children():
		one.conform_geometry(child)
	var slicer := FrameSlicer.new(self, 0.0)
	var roots: Array[Node] = []
	for child: Node in right.get_children():
		roots.append(child)
	await other.conform_all(roots, slicer)
	var meshes: int = 0
	for path: String in ["Board", "Solid/Strip0", "Solid/Strip1", "Bridge/Deck"]:
		var a: MeshInstance3D = left.get_node(path) as MeshInstance3D
		var b: MeshInstance3D = right.get_node(path) as MeshInstance3D
		_expect(a != null and b != null and a.mesh is ArrayMesh and b.mesh is ArrayMesh,
			"%s was conformed on both sides" % path)
		if a == null or b == null:
			continue
		_expect(a.mesh.surface_get_arrays(0) == b.mesh.surface_get_arrays(0),
			"%s is warped to the very same vertices" % path)
		meshes += 1
	_expect(meshes == 4, "Four meshes were compared (%d)" % meshes)
	var solid_shape: CollisionShape3D = left.get_node("Solid").find_children("*", "CollisionShape3D", false, false)[0]
	_expect(solid_shape.shape is ConcavePolygonShape3D, "The solid got a trimesh shape")
	solid_shape = right.get_node("Solid").find_children("*", "CollisionShape3D", false, false)[0]
	_expect(solid_shape.shape is ConcavePolygonShape3D, "...on both sides")
	for path: String in ["Trigger", "Rigid"]:
		var moved: Vector3 = left.get_node(path).position
		_expect(moved == right.get_node(path).position and absf(moved.y) > 0.01,
			"%s moved up onto the ground, the same on both sides" % path)
	var left_label: Node3D = left.find_children("*", "Label3D", false, false)[0] as Node3D
	var right_label: Node3D = right.find_children("*", "Label3D", false, false)[0] as Node3D
	_expect(left_label.position == right_label.position, "The label rides the ground the same")
	var rigid_part: MeshInstance3D = right.get_node("Rigid").get_child(0) as MeshInstance3D
	_expect(rigid_part.mesh is BoxMesh, "A rigid part's own meshes are not warped")
	_expect(slicer.frames_waited >= meshes,
		"conform_all() gave the frame back along the way (%d frames)" % slicer.frames_waited)
	_expect(is_equal_approx(other.conform_progress, 1.0), "conform_progress ends at 1")
	# With no slicer it is conform_geometry() over the roots.
	var plain := Node3D.new()
	scene.add_child(plain)
	_conform_props(plain)
	var plain_roots: Array[Node] = []
	for child: Node in plain.get_children():
		plain_roots.append(child)
	await other.conform_all(plain_roots, null)
	_expect((plain.get_node("Board") as MeshInstance3D).mesh is ArrayMesh,
		"Without a slicer conform_all() conforms in one go")
	for node: Node in [one, other, left, right, plain]:
		node.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
