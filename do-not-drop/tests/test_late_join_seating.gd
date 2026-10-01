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
## - with every box minded, a seat that would take a box off the neighbour
##   minding it (its owner's) is not chosen while another is free, and the
##   tender of that box doesn't change;
## - with every seat taken the newcomer stands in the bay, not in the depot,
##   on a spot clear of walls, seats and of boxes in every bay (a capsule
##   query on the truck's collision layers);
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
		_expect(String(depot_player.get(&"seat_node_path")).is_empty(),
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
		var stand: Vector3 = truck.to_global(late.call(&"standing_spot", expected))
		var flat := Vector2(joiner.global_position.x - stand.x, joiner.global_position.z - stand.z)
		_expect(flat.length() < 0.3,
				"%s: the newcomer spawns by the seat, not at the depot (got %s, spot %s)"
				% [tag, joiner.global_position, stand])
		_expect(not String(joiner.get(&"seat_node_path")).is_empty(),
				"%s: the newcomer's player took the seat (board_seat reached it)" % tag)
		var next_seat: Node = late.call(&"pick_seat")
		_expect(next_seat != null and next_seat != expected, "%s: the next newcomer is offered another seat" % tag)
		await create_timer(0.3).timeout
		_expect(expected.get(&"occupant") == joiner, "%s: a seated newcomer is never released on a timer" % tag)

		# Every box minded: no seat that would take one from its tender.
		joiner.free()
		await process_frame
		_expect(not is_instance_valid(expected.get(&"occupant")), "%s: the seat frees when the player goes" % tag)
		var owner_seat: Node = null
		for seat: Node in get_nodes_in_group(SEAT_GROUP):
			var mount: Node = seat.get_node_or_null(seat.get(&"required_mount_path"))
			if mount != null and is_instance_valid(mount.get(&"occupied_by")):
				owner_seat = seat
		_expect(owner_seat != null, "%s: a seat owns the loaded bay" % tag)
		if owner_seat != null:
			var box: Node = owner_seat.get_node(owner_seat.get(&"required_mount_path")).get(&"occupied_by")
			box.call(&"set_tender", 7)
			_expect(not bool(owner_seat.call(&"unminded_cargo") > 0) and bool(owner_seat.call(&"would_displace")),
					"%s: the owner's seat would displace the tender" % tag)
			var chosen: Node = late.call(&"pick_seat")
			_expect(chosen != null and chosen != owner_seat,
					"%s: with the box minded, a seat that displaces nobody is chosen" % tag)
			level.call(&"_sync_players", [1])
			_expect(int(box.get(&"tender_peer_id")) == 7, "%s: the tender of the box is unchanged" % tag)
			world.get_node(^"Player_1").free()
			await process_frame
			box.call(&"set_tender", 0)

		# Every seat taken: the bay, not the depot.
		for seat: Node in get_nodes_in_group(SEAT_GROUP):
			if not is_instance_valid(seat.get(&"occupant")):
				seat.set(&"occupant", level)
		_expect(late.call(&"pick_seat") == null, "%s: no free seat when all are taken" % tag)
		var spot: Dictionary = late.call(&"place")
		_expect(spot.seat == null and truck.carries(spot.position),
				"%s: with no seat the newcomer lands inside the cargo bay" % tag)
		_expect(await _hits_at(truck, spot.position, level) == 0,
				"%s: the bay spot is clear of walls, seats and boxes in every bay" % tag)
		for seat: Node in get_nodes_in_group(SEAT_GROUP):
			var stand_here: Vector3 = truck.to_global(late.call(&"standing_spot", seat))
			_expect(truck.carries(stand_here),
					"%s: %s's standing spot is inside the truck" % [tag, seat.get_parent().name])

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


## How many bodies a standing player's capsule at `world_spot` overlaps (walls,
## seats, the loose boxes), with a box dropped in every bay first.
func _hits_at(truck: Node3D, world_spot: Vector3, level: Node) -> int:
	var dummies: Array[Node] = []
	for mount: Node in get_nodes_in_group(&"package_mount"):
		var body := StaticBody3D.new()
		body.collision_layer = 4
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * 0.65
		shape.shape = box
		body.add_child(shape)
		level.add_child(body)
		body.global_position = (mount.get_parent() as Node3D).global_position
		dummies.append(body)
	await physics_frame
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(truck.global_basis, world_spot + truck.global_basis.y * 0.85)
	query.collision_mask = 1 | 4 | 64
	var hits: int = truck.get_world_3d().direct_space_state.intersect_shape(query, 16).size()
	for body: Node in dummies:
		body.free()
	return hits
