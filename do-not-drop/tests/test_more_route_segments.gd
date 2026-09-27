extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_more_route_segments.gd
## The newer route segments (docs/tareas-nacho.md #56/#58/#63):
##   - a HillSegment really lifts the road (terrain crest), smoothly back to
##     level at both ends;
##   - a NarrowBridgeSegment on the main route (continuous terrain) carves a
##     real riverbed under itself -- deck and water both actually build, the
##     ground drops away well past just under the deck, fades back to level
##     exactly at both of the segment's own edges (no seam with the straight
##     road on either side), and the deck floats over the drop instead of
##     sinking into it;
##   - a TunnelSegment has solid walls and roof, and light inside;
##   - a RailCrossingSegment that's due to close runs the whole cycle when the
##     truck comes up to it -- warning, arms down (and solid), train across,
##     arms up -- and one that isn't due never moves.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Hill: a crest registered on the terrain height field.
	var terrain: Node3D = load("res://scripts/gameplay/route/route_terrain.gd").new()
	terrain.crests.append({"a": Vector2(0.0, 0.0), "b": Vector2(0.0, -70.0), "height": 6.0})
	var start: float = terrain.base_height(Vector2(0.0, 0.0))
	var top: float = terrain.base_height(Vector2(0.0, -35.0))
	var end: float = terrain.base_height(Vector2(0.0, -70.0))
	var beside: float = terrain.base_height(Vector2(80.0, -35.0))
	_expect(top - start > 5.5, "The road climbs to the crest (%.1f m up)" % (top - start))
	_expect(absf(end - start) < 0.3, "It comes back down to level at the far end")
	_expect(absf(beside - start) < 0.3, "Far off to the side the ground isn't lifted")
	terrain.free()

	# Narrow bridge on the main route: the ground itself is carved into a
	# riverbed under it (route.gd registers the span with route_terrain.gd's
	# `rivers`, same as it does for a hill's crest above).
	var river_terrain: Node3D = load("res://scripts/gameplay/route/route_terrain.gd").new()
	root.add_child(river_terrain)
	river_terrain.add_span(Vector3(0.0, 0.0, 20.0), Vector3(0.0, 0.0, -400.0), false, 3.0)
	var bridge := NarrowBridgeSegment.new()
	bridge.continuous_terrain = true
	bridge.position = Vector3(0.0, 0.0, -180.0)
	root.add_child(bridge)
	await process_frame
	var bridge_exit: Vector3 = bridge.position + Vector3(0.0, 0.0, -bridge.length)
	river_terrain.rivers.append({"a": Vector2(bridge.position.x, bridge.position.z), "b": Vector2(bridge_exit.x, bridge_exit.z), "depth": bridge.river_depth})
	river_terrain.build()
	_expect(bridge.get_node_or_null(^"BridgeDeckModule") != null, "The deck GLB builds on the main route too, not just standalone")
	_expect(bridge.get_node_or_null(^"BridgeWater") != null, "The river GLB builds on the main route too")
	_expect(bridge.get_node_or_null(^"BridgeGuardRailCollision") != null, "Guard rail collision is still there with the river carved in")
	_expect(bridge.has_meta(&"ignore_river"), "The whole segment is flagged so its own furniture floats over the drop")
	var mid_z: float = bridge.position.z - bridge.length * 0.5
	var river_under_deck: float = river_terrain.height_at(Vector3(0.0, 0.0, mid_z))
	var river_beside: float = river_terrain.height_at(Vector3(10.0, 0.0, mid_z))
	var river_natural: float = river_terrain.height_without_rivers(Vector3(0.0, 0.0, mid_z))
	_expect(not is_nan(river_under_deck) and not is_nan(river_beside) and not is_nan(river_natural), "No NaN in the carved riverbed")
	_expect(river_natural - river_under_deck > 1.0, "The ground actually drops away under the middle of the bridge (%.2f m)" % (river_natural - river_under_deck))
	_expect(absf(river_under_deck - river_beside) < 0.6, "It's a real valley crossing under the bridge, not a hole only right under the deck (%.2f vs %.2f)" % [river_under_deck, river_beside])
	var entry_gap: float = absf(river_terrain.height_at(bridge.position) - river_terrain.height_without_rivers(bridge.position))
	var exit_gap: float = absf(river_terrain.height_at(bridge_exit) - river_terrain.height_without_rivers(bridge_exit))
	_expect(entry_gap < 0.01 and exit_gap < 0.01, "The riverbed fades out exactly at the segment's own edges -- no seam with the straight road (%.3f / %.3f)" % [entry_gap, exit_gap])
	river_terrain.conform_geometry(bridge)
	await physics_frame
	await physics_frame
	var river_space := root.world_3d.direct_space_state
	var deck_ray := PhysicsRayQueryParameters3D.create(Vector3(0.0, river_natural + 6.0, mid_z), Vector3(0.0, river_under_deck - 3.0, mid_z))
	var deck_hit: Dictionary = river_space.intersect_ray(deck_ray)
	_expect(not deck_hit.is_empty() and deck_hit.position.y - river_under_deck > 1.0,
		"A raycast down the middle of the span lands on the deck, well above the carved riverbed, not in the gap")
	var gorge_ray := PhysicsRayQueryParameters3D.create(Vector3(10.0, river_natural + 6.0, mid_z), Vector3(10.0, river_beside - 3.0, mid_z))
	var gorge_hit: Dictionary = river_space.intersect_ray(gorge_ray)
	_expect(not gorge_hit.is_empty() and absf(gorge_hit.position.y - river_beside) < 0.05, "Beside the deck a raycast finds the real dropped ground, not empty air or a hole")
	bridge.free()
	river_terrain.free()

	# Tunnel.
	var tunnel: RouteSegment = TunnelSegment.new()
	root.add_child(tunnel)
	await process_frame
	var walls: int = 0
	# Sibling names get uniquified, so walls are told by shape: tall, thin, long.
	for shape: Node in tunnel.find_children("*", "CollisionShape3D", true, false):
		var box := (shape as CollisionShape3D).shape as BoxShape3D
		if box != null and box.size.y >= 4.0 and box.size.x < 1.0 and box.size.z >= tunnel.length:
			walls += 1
	_expect(walls == 2 and tunnel.get_node_or_null(^"TunnelRoof") is StaticBody3D, "Two solid walls and a solid roof")
	_expect(not tunnel.find_children("*", "SpotLight3D", true, false).is_empty(), "Lit inside")
	tunnel.free()

	# Rail crossing: a truck stand-in coming up the road.
	var truck := Node3D.new()
	truck.add_to_group(&"vehicle")
	root.add_child(truck)
	var crossing: RailCrossingSegment = RailCrossingSegment.new()
	root.add_child(crossing)
	await process_frame
	crossing.will_close = true
	truck.global_position = crossing.global_transform * Vector3(0.0, 0.0, crossing.track_z + 30.0)
	var seen: Dictionary = {}
	var arm: Node3D = crossing.get_node(^"BarrierArm")
	# N-129 / N-130: the crossing and the train are the imported models, the
	# lamps are the signal's named lenses, and the collision is still the boxes.
	_expect(crossing.get_node_or_null(^"RailTrack") != null, "The track is the imported model")
	_expect(crossing.find_children("CrossingSignal*", "", false, false).size() == 2, "Two imported crossing signals")
	var lamps: Array = crossing.get("_lamps")
	_expect(lamps.size() == 4, "Four flashing lenses found in the signal models (%d)" % lamps.size())
	_expect(arm.get_node_or_null(^"ArmModel") != null, "The barrier arm hangs its model from the hinge")
	for index: int in range(4):
		var car: Node3D = crossing.get_node(NodePath("TrainCar%d" % index))
		var car_shape := car.find_children("*", "CollisionShape3D", false, false)
		var car_box: BoxShape3D = (car_shape[0] as CollisionShape3D).shape as BoxShape3D if not car_shape.is_empty() else null
		_expect(car.get_node_or_null(^"CarModel") != null and car_box != null and car_box.size.is_equal_approx(Vector3(7.5, 3.0, 2.6)),
			"Train car %d: imported model, same 7.5 x 3 x 2.6 m collision box" % index)
	var arm_down_seen: bool = false
	for _i: int in range(60 * 14):
		await physics_frame
		seen[crossing.state] = true
		if crossing.state == RailCrossingSegment.State.TRAIN:
			arm_down_seen = arm_down_seen or absf(arm.rotation.z) < 0.05
	_expect(seen.has(RailCrossingSegment.State.WARNING) and seen.has(RailCrossingSegment.State.TRAIN) and crossing.state == RailCrossingSegment.State.DONE,
		"Warning, train, done (states seen: %s, now %d)" % [str(seen.keys()), crossing.state])
	_expect(arm_down_seen and arm is StaticBody3D, "The arms are down across the road while the train passes, and solid")
	_expect(absf(absf(arm.rotation.z) - PI * 0.5) < 0.05, "The arms are back up once it's gone")
	crossing.free()

	# A client loading in while the host's train is passing: it jumps
	# straight to that phase (what the host answers _request_state with)
	# instead of starting the cycle from scratch, and finishes it from there.
	var joined: RailCrossingSegment = RailCrossingSegment.new()
	root.add_child(joined)
	await process_frame
	joined.will_close = true
	joined.call(&"_apply_state", RailCrossingSegment.State.TRAIN, 0.0, 0.0)
	var joined_arm: Node3D = joined.get_node(^"BarrierArm")
	var first_car: Node3D = joined.get_node(^"TrainCar0")
	_expect(absf(joined_arm.rotation.z) < 0.05 and first_car.visible, "Joining mid-train: arms already down, train already on the tracks")
	for _i: int in range(60 * 6):
		await physics_frame
	_expect(joined.state == RailCrossingSegment.State.DONE and absf(absf(joined_arm.rotation.z) - PI * 0.5) < 0.05, "...and it finishes the cycle from there (now %d)" % joined.state)
	joined.free()

	var quiet: RailCrossingSegment = RailCrossingSegment.new()
	root.add_child(quiet)
	await process_frame
	quiet.will_close = false
	for _i: int in range(60):
		await physics_frame
	_expect(quiet.state == RailCrossingSegment.State.WAITING, "A crossing that isn't due stays open")
	quiet.free()
	truck.free()
	await process_frame
	if _failures == 0:
		print("PASS: crests lift the road, a narrow bridge carves a real riverbed under itself, tunnels are solid and lit, crossings close for a passing train and reopen")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
