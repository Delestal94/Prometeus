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
##
## N-908: what a late joiner learns about a crewmate already holding a box
## (player_net_visibility.gd refresh_peer(), seat_tending.gd _holder_of()):
## - when a new peer's level is up, the host repeats a crewmate's pick_up to
##   that peer alone (the same reliable RPC, with the box's path), and nothing
##   for a crewmate with empty hands; a client's copy never does;
## - in the late joiner's view (no carrier, and no pick_up yet: replicated
##   fields only) a box on a seated crewmate's lap already reserves its bay
##   (SeatTending.lap_reserves(is_server = false)), its holder being its tender
##   (only for a box bound for a lap: one taken out of a tender's bay is not);
## - the re-sent pick_up alone shows that lap too, and on that copy (not its
##   owner's) it puts the box in hand without the pickup clip or a trap tip.
## The host's RPCs are written down by a stand-in MultiplayerAPI under the
## crewmates' branch of the tree (RpcRecorder), so nothing goes out.

## The seating script is reached by node and get()/call(), not by class name:
## this script is compiled before the autoloads exist, and it talks to RunManager.
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
		_expect(NodePath(joiner.get(&"seat_node_path")) == expected.get_parent().get_path(),
				"%s: the newcomer's player is marked as sitting in that seat" % tag)
		_expect(bool(joiner.get(&"net_in_vehicle")), "%s: the newcomer starts out riding in the truck" % tag)
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

		# Spawned in the truck's own space: wherever the truck is drawn, there.
		var standing: Vector3 = late.call(&"floor_at", late.get_script().get_script_constant_map()["BAY_SPOT"])
		truck.global_position += Vector3(3.0, 0.0, 7.0)
		truck.global_rotation.y += 0.4
		var stray: Node3D = world.get_node(^"PlayerSpawner").spawn(
				{"peer_id": 9, "position": Vector3.ZERO, "vehicle_position": standing})
		_expect(stray != null and stray.global_position.distance_to(truck.to_global(standing)) < 0.01,
				"%s: a spawn with vehicle_position lands at that spot of the truck (got %s, want %s)"
				% [tag, stray.global_position, truck.to_global(standing)])
		_expect(stray != null and bool(stray.get(&"net_in_vehicle"))
				and (stray.get(&"net_position") as Vector3).distance_to(standing) < 0.01,
				"%s: ...riding, in the truck's space" % tag)
		stray.free()

		# The joiner's own truck copy is still where it was built when the
		# player spawns, and is teleported to the road by its first pose from
		# the host: the player goes with it, and is not rescued to the depot.
		truck.freeze = true
		var before: Vector3 = truck.global_position
		var own := world.get_node(^"PlayerSpawner").spawn(
				{"peer_id": 1, "position": Vector3.ZERO, "vehicle_position": standing}) as Node3D
		truck.global_position = before + Vector3(300.0, -20.0, 500.0)
		for frame: int in range(3):
			await physics_frame
		_expect(truck.carries(own.global_position) and own.global_position.y > truck.global_position.y - 1.0,
				"%s: a joiner whose truck jumps before its first tick stays aboard (at %s, truck %s)"
				% [tag, own.global_position, truck.global_position])
		own.free()

		# Results showing: the depot again.
		manager.set(&"results", {"score": 1})
		_expect(not late.call(&"underway"), "%s: nothing is seated once the results are showing" % tag)

		level.queue_free()
		await process_frame
		manager.call(&"reset_run")
	await _late_carry()
	if _failures == 0:
		print("PASS: late joiners are seated in the truck once it is on the road and see what the crew carries")
	quit(_failures)


## N-908: a crewmate (peer 2) sits at LeftSeat3 holding a box bound for
## RightSeat3's bay; peer 5 joins after that.
func _late_carry() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var crew := Node3D.new()
	crew.name = "LateCarryCrew"
	root.add_child(crew)
	var recorder := RpcRecorder.new()
	set_multiplayer(recorder, crew.get_path())
	var player_scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")
	var lapper: Node = player_scene.instantiate()
	lapper.name = "Player_2"  # Authority from the name, as the spawner's players.
	crew.add_child(lapper)
	var idle: Node = player_scene.instantiate()
	idle.name = "Player_3"
	crew.add_child(idle)
	await process_frame
	var tips: Array[String] = []
	var bus: Node = root.get_node(^"/root/EventBus")
	var on_tip := func(text: String) -> void: tips.append(text)
	bus.connect(&"tutorial_tip_requested", on_tip)
	_expect(lapper.multiplayer == recorder and lapper.multiplayer.is_server() and not lapper.call(&"is_local"),
			"late carry: the crewmates are the host's copies of peers 2 and 3")
	var hook := Callable(lapper, &"_on_peer_level_ready")
	_expect(root.get_node(^"/root/NetworkManager").is_connected(&"peer_level_ready", hook),
			"late carry: each player hears when a peer's level is up")

	# By path, like the seating script: SeatTending's class pulls in scripts that
	# name the autoloads, which don't exist yet when this file compiles.
	var tending: Script = load("res://scripts/gameplay/interaction/seat_tending.gd")
	var vehicle: String = "World/Vehicle/CargoBay/"
	var mount: Node = level.get_node(vehicle + "RightSeat3PackageMount/InteractionArea")
	var lap_seat: Node = level.get_node(vehicle + "LeftSeat3EyePoint/InteractionArea")
	var box: Node = null
	for node: Node in get_nodes_in_group(&"cargo"):
		if node.get(&"trap_definition") != null:
			box = node
			break
	_expect(box != null, "late carry: the level has a box with a trap")
	if box == null:
		await _end_late_carry(level, crew, bus, on_tip)
		return
	box.call(&"take_by", lapper)
	lap_seat.call(&"interact", lapper)
	_expect(lapper.get(&"carried_package") == box and tending.call(&"lap_mount_of", box) == mount
			and int(box.get(&"tender_peer_id")) == 2,
			"late carry: the crewmate sits with the box on the lap, bound for RightSeat3's bay")

	# The host when peer 5's level is up.
	recorder.sent.clear()
	hook.call(5)
	idle.call(&"_on_peer_level_ready", 5)
	_expect(recorder.sent.size() == 1, "late carry: one RPC goes out for the new peer (got %s)" % [recorder.sent])
	var resent: Array = recorder.sent[0] if not recorder.sent.is_empty() else [0, null, &"", []]
	_expect(int(resent[0]) == 5 and resent[1] == lapper and StringName(resent[2]) == &"pick_up"
			and resent[3] == [box.get_path()],
			"late carry: the host repeats the crewmate's pick_up to peer 5 alone, with the box (got %s)" % [resent])
	recorder.client_id = 4
	recorder.sent.clear()
	hook.call(5)
	_expect(recorder.sent.is_empty(), "late carry: a client's copy repeats nothing (got %s)" % [recorder.sent])
	recorder.client_id = 0

	# Peer 5's view before that lands: the host's carrier is unknown there and
	# the crewmate's hands look empty; the seat path, the box's lap bay and its
	# tender are replicated.
	var tree: SceneTree = root.get_tree()
	var host_carrier: Variant = box.get(&"carrier")
	box.set(&"carrier", null)
	lapper.set(&"carried_package", null)
	lapper.set(&"seat_node_path", lap_seat.get_parent().get_path())
	_expect(bool(tending.call(&"lap_reserves", tree, mount, null, false)),
			"late carry: the late joiner sees the lap reserve its bay by the box's tender, before any pick_up")
	box.set(&"tender_peer_id", 0)  # Only the re-sent pick_up left to go by.
	_expect(not bool(tending.call(&"lap_reserves", tree, mount, null, false)),
			"late carry: with neither the tender nor the pick_up the bay looks free (the bug)")
	var state_before: StringName = lapper.get(&"anim_state")
	if StringName(resent[2]) == &"pick_up":
		lapper.callv(&"pick_up", resent[3])  # As peer 5's copy of the crewmate receives it.
	_expect(lapper.get(&"carried_package") == box,
			"late carry: the re-sent pick_up puts the box in the crewmate's hands")
	_expect(bool(tending.call(&"lap_reserves", tree, mount, null, false)),
			"late carry: ...and the late joiner sees the lap reserve the bay from it alone")
	_expect(not bool(tending.call(&"lap_reserves", tree, mount, box, false)),
			"late carry: ...but not against its own box")
	_expect(lapper.get(&"anim_state") == state_before and tips.is_empty(),
			"late carry: on a copy that isn't the owner's it plays no pickup clip (%s) and shows no tip (%d)"
			% [lapper.get(&"anim_state"), tips.size()])
	# Standing up, the same box reserves nothing, by tender or by hands.
	box.set(&"tender_peer_id", 2)
	lapper.set(&"seat_node_path", NodePath())
	_expect(not bool(tending.call(&"lap_reserves", tree, mount, null, false)),
			"late carry: a crewmate standing with the box reserves nothing")
	lapper.set(&"carried_package", null)
	_expect(not bool(tending.call(&"lap_reserves", tree, mount, null, false)),
			"late carry: ...neither by the tender alone")
	_expect(tending.call(&"_holder_of", tree, box) == lapper, "late carry: a lap box's tender is taken for its holder")
	# Taken out of a seated tender's bay by someone else, a box keeps its tender
	# but has no lap bay: the tender is not taken for its holder then.
	box.set(&"lap_mount_path", NodePath())
	_expect(tending.call(&"_holder_of", tree, box) == null,
			"late carry: a held box with a tender and no lap bay has no known holder on a client")
	box.set(&"lap_mount_path", mount.get_path())
	lapper.set(&"carried_package", box)
	box.set(&"carrier", host_carrier)
	lap_seat.call(&"release_occupant", 2)
	await _end_late_carry(level, crew, bus, on_tip)


func _end_late_carry(level: Node, crew: Node, bus: Node, on_tip: Callable) -> void:
	bus.disconnect(&"tutorial_tip_requested", on_tip)
	for player: Node in crew.get_children():
		player.free()
	set_multiplayer(null, crew.get_path())
	crew.free()
	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")


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


## Stands in for the host's MultiplayerAPI under one branch of the tree: an
## offline SceneMultiplayer (peer 1, the server) does the work and every RPC is
## written down. Calls to other peers stop here, there is nobody at the other
## end; `client_id` other than 0 makes this branch a client with that id.
class RpcRecorder extends MultiplayerAPIExtension:
	var base := SceneMultiplayer.new()
	var sent: Array = []
	var client_id: int = 0

	func _init() -> void:
		base.multiplayer_peer = OfflineMultiplayerPeer.new()

	func _poll() -> Error:
		return base.poll()

	func _set_multiplayer_peer(peer: MultiplayerPeer) -> void:
		base.multiplayer_peer = peer

	func _get_multiplayer_peer() -> MultiplayerPeer:
		return base.multiplayer_peer

	func _get_unique_id() -> int:
		return client_id if client_id != 0 else base.get_unique_id()

	func _get_peer_ids() -> PackedInt32Array:
		return base.get_peers()

	func _get_remote_sender_id() -> int:
		return base.get_remote_sender_id()

	func _rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
		sent.append([peer, object, method, args])
		if peer == 0 or peer == base.get_unique_id():
			return base.rpc(peer, object, method, args)
		return OK

	## Only the branch's root path reaches the real one: the synchronizers of
	## these players have nobody to sync to.
	func _object_configuration_add(object: Object, config: Variant) -> Error:
		return base.object_configuration_add(object, config) if object == null else OK

	func _object_configuration_remove(object: Object, config: Variant) -> Error:
		return base.object_configuration_remove(object, config) if object == null else OK
