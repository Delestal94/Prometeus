extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_more_route_segments.gd
## The newer route segments (docs/tareas-nacho.md #56/#58/#63):
##   - a HillSegment really lifts the road (terrain crest), smoothly back to
##     level at both ends;
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
		print("PASS: crests lift the road, tunnels are solid and lit, crossings close for a passing train and reopen")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
