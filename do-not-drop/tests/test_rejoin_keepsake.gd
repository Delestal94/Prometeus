extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_rejoin_keepsake.gd
##
## N-221: someone who drops out and comes back (same identity: the host's
## NetworkManager.peer_returned) gets back where they were, their seat and
## their box, instead of appearing like any late joiner (rejoin_keepsake.gd,
## spawned from level_common.gd's _sync_players()). In one process, offline:
## the returner is this process' own player (id 1, freed and spawned again),
## so the seat's and the box's RPCs have a peer to reach.
## - the level notes what a player had when it leaves the roster
##   (peer_removed) and hands the note on when it is back (peer_returned);
## - before the run: back on foot where it stood in the depot, its box (let go
##   of when it left) back in its hands;
## - a box someone else picked up meanwhile isn't taken from the crew; nobody
##   back (no peer_returned) spawns at the depot as ever, empty-handed;
## - before the run, its passenger seat taken meanwhile: beside that seat, not
##   in whoever sits there;
## - at the wheel with a box in hand (the wheel won't take it): standing by
##   the cab with the box, the door opened for it shut again;
## - a box taken back mid-run off the road is no rescue (_rescue_pending as it
##   was);
## - mid-run, back to the driver's seat it left even with its door shut since
##   (opened for it, it shuts behind it as ever), the truck's wheel its again;
##   back to the passenger seat it left; that seat taken meanwhile: another
##   seat, as a late joiner; standing in the bay:
##   the same spot of the truck, riding it;
## - on foot mid-run: where it stood if near the truck, a seat aboard if far
##   (the road back there may be gone);
## - back while its old player is still in the tree (a ghost dropped this
##   frame): spawned the next frame, once that one let go of seat and box.

const LEVEL: String = "res://scenes/gameplay/level_base.tscn"
const SEAT_GROUP: StringName = &"cargo_seat"

var _failures: int = 0
var _level: Node
var _world: Node3D
var _keep: Node
var _truck: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var network: Node = root.get_node(^"/root/NetworkManager")
	_level = load(LEVEL).instantiate()
	root.add_child(_level)
	current_scene = _level
	await process_frame
	await physics_frame
	_world = _level.get_node(^"World")
	_keep = _level.get_node(^"RejoinKeepsake")
	_truck = _level.get(&"vehicle")
	var packages: Array = _level.get(&"packages")
	_expect(network.is_connected(&"peer_returned", Callable(_keep, &"on_returned"))
		and network.is_connected(&"peer_removed", Callable(_level, &"_on_peer_removed")),
		"The level notes leavers (peer_removed) and hands the note on to returners (peer_returned)")

	# Before the run, on foot in the depot with a box.
	var depot_spawn: Vector3 = (_level.get(&"depot") as Node3D).call(&"spawn_position", 0)
	var spot: Vector3 = depot_spawn + Vector3(1.6, 0.0, 0.9)
	var player := _player()
	player.global_position = spot
	var box: Node3D = packages[0]
	box.call(&"take_by", player)
	_expect(player.get(&"carried_package") == box, "The player holds a box before leaving")
	_leave(player)
	_expect(not bool(box.get(&"is_held")), "Leaving lets go of the box at once (S-209)")
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and player.global_position.distance_to(spot) < 0.5,
		"Back before the run: where it stood in the depot (at %s, was %s)"
		% [player.global_position if player != null else Vector3.ZERO, spot])
	_expect(player != null and player.get(&"carried_package") == box and box.get(&"carrier") == player,
		"...with its box back in its hands")

	# Someone else had the box meanwhile: it stays where it is.
	_leave(player)
	box.set(&"_last_holder_peer", 7)
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and player.get(&"carried_package") == null and not bool(box.get(&"is_held")),
		"A box someone else had since isn't taken back")

	# Nobody back: a newcomer, at the depot as ever.
	player.global_position = spot
	_leave(player)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and player.global_position.distance_to(depot_spawn) < 0.5,
		"Without peer_returned it spawns at the depot (at %s)"
		% [player.global_position if player != null else Vector3.ZERO])

	# Before the run, its passenger seat taken meanwhile: beside it.
	var pre_seat: Node = null
	for candidate: Node in get_nodes_in_group(SEAT_GROUP):
		if _truck.is_ancestor_of(candidate) and bool(candidate.call(&"can_interact", player)):
			pre_seat = candidate
			break
	_expect(pre_seat != null, "A free passenger seat before the run")
	if pre_seat != null:
		pre_seat.call(&"interact", player)
		_expect(not String(player.get(&"seat_node_path")).is_empty(), "The player sits before the run")
		_leave(player)
		pre_seat.set(&"occupant", _level)
		network.peer_returned.emit(1, 1)
		_level.call(&"_sync_players", [1])
		player = _player()
		var beside: Vector3 = _truck.to_global(_level.get_node(^"LateJoinSeating").call(&"standing_spot", pre_seat))
		_expect(player != null and String(player.get(&"seat_node_path")).is_empty()
			and player.global_position.distance_to(beside) < 0.3,
			"Its seat taken before the run: standing beside it (at %s, want %s)"
			% [player.global_position if player != null else Vector3.ZERO, beside])
		pre_seat.set(&"occupant", null)

	# Mid-run, at the wheel (the debug start seats this player as the driver).
	_level.call(&"start_debug_delivery")
	await physics_frame
	_expect(bool(manager.get(&"is_running")) and int(_truck.get(&"driver_peer_id")) == 1, "The run is on, 1 drives")
	player = _player()
	var driver_anchor: NodePath = player.get(&"seat_node_path")
	_leave(player)
	_expect(int(_truck.get(&"driver_peer_id")) == 0, "Leaving frees the wheel")
	_truck.call(&"set_door_open", &"cab_left", false)
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and NodePath(player.get(&"seat_node_path")) == driver_anchor
		and int(_truck.get(&"driver_peer_id")) == 1,
		"Back at the wheel it left (seat %s)" % [player.get(&"seat_node_path") if player != null else ""])
	_expect(not bool(_truck.call(&"is_door_open", &"cab_left")),
		"...through its door, shut since: opened for it, it shuts behind it as ever")

	# At the wheel with a box in hand: the wheel won't take it back with it.
	var cab_box: Node3D = packages[2]
	cab_box.call(&"take_by", player)
	_leave(player)
	_truck.call(&"set_door_open", &"cab_left", false)
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and player.get(&"carried_package") == cab_box
		and String(player.get(&"seat_node_path")).is_empty() and int(_truck.get(&"driver_peer_id")) == 0,
		"Back at the wheel with its box: the box in hand, standing by the cab")
	_expect(not bool(_truck.call(&"is_door_open", &"cab_left")), "...and the door opened for it shut again")

	# A passenger seat: a newcomer mid-run is seated by the late join.
	_leave(player)
	_level.call(&"_sync_players", [1])
	player = _player()
	var passenger_anchor: NodePath = player.get(&"seat_node_path")
	_expect(not passenger_anchor.is_empty() and passenger_anchor != driver_anchor,
		"A newcomer mid-run takes a passenger seat (late join)")
	_leave(player)
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and NodePath(player.get(&"seat_node_path")) == passenger_anchor,
		"Back to the passenger seat it left")

	# That seat taken meanwhile: another one, as any late joiner.
	_leave(player)
	var taken: Node = (_world.get_node(passenger_anchor) as Node).get_node(^"InteractionArea")
	taken.set(&"occupant", _level)
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	var now_at: NodePath = NodePath(player.get(&"seat_node_path")) if player != null else NodePath()
	_expect(not now_at.is_empty() and now_at != passenger_anchor and now_at != driver_anchor,
		"Its seat taken meanwhile: another free one (got %s)" % now_at)
	taken.set(&"occupant", null)

	# Standing in the bay: the same spot of the truck, riding it.
	player.call(&"leave_seat")
	var bay: Vector3 = Vector3(0.0, 0.3, 0.9)
	player.set(&"net_in_vehicle", true)
	player.set(&"net_position", bay)
	_leave(player)
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and String(player.get(&"seat_node_path")).is_empty()
		and player.global_position.distance_to(_truck.to_global(bay)) < 0.05 and bool(player.get(&"net_in_vehicle")),
		"Back standing where it stood in the bay, riding the truck (at %s, want %s)"
		% [player.global_position if player != null else Vector3.ZERO, _truck.to_global(bay)])

	# On foot near the truck: where it stood. Far: aboard, the late join's way.
	var near: Vector3 = _truck.global_position + _truck.global_basis.x * 6.0
	player.set(&"net_in_vehicle", false)
	player.global_position = near
	var road_box: Node3D = packages[3]
	road_box.call(&"take_by", player)
	road_box.set(&"_rescue_pending", false)  # As if it had never left the truck.
	_leave(player)
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and player.global_position.distance_to(near) < 0.5
		and String(player.get(&"seat_node_path")).is_empty(),
		"On foot near the truck mid-run: back where it stood")
	_expect(player != null and player.get(&"carried_package") == road_box
		and not bool(road_box.get(&"_rescue_pending")),
		"...its box back in hand off the road, and that is no rescue (_rescue_pending as it was)")
	player.global_position = _truck.global_position + Vector3(120.0, 0.0, 0.0)
	_leave(player)
	network.peer_returned.emit(1, 1)
	_level.call(&"_sync_players", [1])
	player = _player()
	_expect(player != null and not String(player.get(&"seat_node_path")).is_empty(),
		"On foot far from the truck mid-run: aboard instead, as a late joiner")

	# Back while its old player (a ghost, under its old id 5) is still in the tree.
	await _check_lingering_ghost(packages[1] as Node3D, network)

	_level.queue_free()
	await process_frame
	manager.call(&"reset_run")
	if _failures == 0:
		print("PASS: a returner gets its spot, seat and box back")
	quit(_failures)


## The ghost case: its player goes at the end of the frame it was dropped in,
## letting go of seat and box then; the returner is spawned after that.
func _check_lingering_ghost(box: Node3D, network: Node) -> void:
	var player := _player()
	player.call(&"leave_seat")
	player.set(&"net_in_vehicle", false)
	player.global_position = _truck.global_position + _truck.global_basis.x * 5.0
	box.call(&"take_by", player)
	await physics_frame
	player.name = "Player_5"  # The ghost's old id; still here this frame.
	box.set(&"_last_holder_peer", 5)
	network.peer_removed.emit(5)
	network.peer_returned.emit(1, 5)
	_level.call(&"_sync_players", [1])
	_expect(_player() == null, "Its old player still here: the returner waits")
	await process_frame
	await process_frame
	player = _player()
	_expect(player != null, "...and is spawned once that one is gone")
	_expect(player != null and player.get(&"carried_package") == box,
		"...with the box the ghost held back in its hands")


## Leaves the roster as the host sees it: noted, then the player goes.
func _leave(player: Node3D) -> void:
	_level.call(&"_on_peer_removed", 1)
	player.free()


func _player() -> Node3D:
	return _world.get_node_or_null(^"Player_1") as Node3D


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
