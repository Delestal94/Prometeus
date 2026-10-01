extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_late_join_seating.gd
##
## N-228.7: whoever joins with the truck already on the road is spawned aboard
## it instead of in the empty depot (late_join_seating.gd, spawned from
## level_common.gd's _sync_players()).
## - before the run starts a newcomer spawns at the depot's spawn spot, as ever;
## - with the run on, the newcomer spawns at a free passenger seat of the truck
##   and the host seats it there (SeatPoint.interact), preferring a seat that
##   faces a box nobody minds (seat_point.gd unminded_cargo());
## - two newcomers never get the same seat;
## - when a client never reports sitting, the host boards it again, and after
##   the last attempt leaves it standing in the cargo bay, seat released;
## - with every seat taken the newcomer stands in the bay, not in the depot;
## - once results are showing the depot is the place again (no seating);
## - Endless, which has no depot to go back to, seats newcomers the same way.

## Loaded by path, not by class name: this script is compiled before the
## autoloads exist, and the seating script talks to RunManager.
const SEAT_GROUP: StringName = &"cargo_seat"
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	for scene_path: String in ["res://scenes/gameplay/level_base.tscn", "res://scenes/gameplay/level_endless.tscn"]:
		var tag: String = scene_path.get_file()
		var level: Node = load(scene_path).instantiate()
		root.add_child(level)
		current_scene = level
		await process_frame
		await physics_frame
		var truck: Node3D = level.get(&"vehicle")
		var late: Node = level.get_node(^"LateJoinSeating")
		late.set(&"retry_seconds", 0.05)
		var attempts: int = int(late.get_script().get_script_constant_map()["ATTEMPTS"])
		var world: Node3D = level.get_node(^"World")

		# The newcomer is this process' own player (id 1, freed and spawned
		# again): the board_seat RPC then has a peer to reach offline.
		var spawn_point: Vector3 = (level.get(&"depot") as Node3D).call(&"spawn_position", 0)

		# Before the run: the depot, as ever.
		_expect(not late.call(&"underway"), "%s: nothing is underway before the run starts" % tag)
		world.get_node(^"Player_1").free()
		level.call(&"_sync_players", [1])
		var depot_player := world.get_node_or_null(^"Player_1") as Node3D
		_expect(depot_player != null, "%s: the newcomer is spawned" % tag)
		if depot_player == null:
			break
		_expect(String(depot_player.get(&"seat_node_path")).is_empty() and int(late.get(&"boarding_attempts")) == 0,
				"%s: before the run nobody is sat" % tag)
		_expect(depot_player.global_position.distance_to(spawn_point) < 0.5,
				"%s: before the run the newcomer lands at the depot (got %s)" % [tag, depot_player.global_position])

		# The run on (the debug start loads a box and takes the wheel).
		level.call(&"start_debug_delivery")
		await physics_frame
		_expect(bool(manager.get(&"is_running")) and late.call(&"underway"), "%s: the run is on" % tag)
		world.get_node(^"Player_1").free()
		await physics_frame

		var expected: Node = late.call(&"pick_seat")
		_expect(expected != null, "%s: a free passenger seat exists" % tag)
		_expect(expected != null and int(expected.call(&"unminded_cargo")) >= 1,
				"%s: the seat chosen faces the loaded box nobody minds" % tag)
		level.call(&"_sync_players", [1])
		var joiner := world.get_node_or_null(^"Player_1") as Node3D
		_expect(joiner != null, "%s: the late joiner is spawned" % tag)
		if joiner == null or expected == null:
			break
		_expect(expected.get(&"occupant") == joiner, "%s: the host sat the late joiner in the seat it chose" % tag)
		var eye: Vector3 = (expected.get_parent() as Node3D).global_position
		_expect(Vector2(joiner.global_position.x, joiner.global_position.z).distance_to(Vector2(eye.x, eye.z)) < 0.2,
				"%s: the newcomer spawns at the seat, not the depot (got %s, seat %s)"
				% [tag, joiner.global_position, eye])
		_expect(int(late.get(&"boarding_attempts")) == 1,
				"%s: one boarding (got %d)" % [tag, int(late.get(&"boarding_attempts"))])
		_expect(not String(joiner.get(&"seat_node_path")).is_empty(),
				"%s: the newcomer's player took the seat (board_seat reached it)" % tag)
		var next_seat: Node = late.call(&"pick_seat")
		_expect(next_seat != null and next_seat != expected, "%s: the next newcomer is offered another seat" % tag)
		await create_timer(0.3).timeout
		_expect(int(late.get(&"boarding_attempts")) == 1 and expected.get(&"occupant") == joiner,
				"%s: a newcomer who did sit is left alone" % tag)

		# board_seat lost on the way: the host boards them again.
		joiner.set(&"seat_node_path", NodePath())
		expected.call(&"release_occupant", 1)
		joiner.set(&"seat_node_path", NodePath())
		late.call(&"seat_player", joiner, expected)
		_expect(int(late.get(&"boarding_attempts")) == 2, "%s: boarding again" % tag)
		var clear_path: Callable = func() -> void: joiner.set(&"seat_node_path", NodePath())
		process_frame.connect(clear_path)
		await create_timer(0.5).timeout
		process_frame.disconnect(clear_path)
		_expect(int(late.get(&"boarding_attempts")) == attempts + 1,
				"%s: with the owner never reporting, the host stops after %d attempts (got %d)"
				% [tag, attempts, int(late.get(&"boarding_attempts")) - 1])
		_expect(not is_instance_valid(expected.get(&"occupant")), "%s: ...and the seat is released" % tag)

		# Every seat taken: the bay, not the depot.
		for seat: Node in get_nodes_in_group(SEAT_GROUP):
			if not is_instance_valid(seat.get(&"occupant")):
				seat.set(&"occupant", level)
		_expect(late.call(&"pick_seat") == null, "%s: no free seat when all are taken" % tag)
		var spot: Dictionary = late.call(&"place")
		_expect(spot.seat == null and truck.carries(spot.position),
				"%s: with no seat the newcomer lands inside the cargo bay" % tag)

		# Results showing: the depot again.
		manager.set(&"results", {"score": 1})
		_expect(not late.call(&"underway"), "%s: nothing is seated once the results are showing" % tag)

		level.queue_free()
		await process_frame
		manager.call(&"reset_run")
	if _failures == 0:
		print("PASS: late joiners are seated in the truck once it is on the road")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
