extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_session_sync.gd
##
## The second round of multiplayer fixes (cazador-bugs sweep, 2026-09-24):
## what a late joiner is told about the run, boxes handed over at a door
## going away everywhere, a box carried or set down in the moving truck
## staying on the host's truck, trap input only from whoever tends the box
## (and not forever), a seated passenger's reach measured from their seat,
## remote interactions only within reach, no photo bonus for a house the run
## drove past, and a session that ends leaving nothing of itself behind.
##
## Offline, so everything here is the host's side or a direct call of what a
## client runs; the two/three-process behaviour is checked with probes.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var network: Node = root.get_node(^"/root/NetworkManager")
	var run: Node = root.get_node(^"/root/RunManager")
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	await physics_frame
	var van = level.vehicle
	var player: Node3D = level.local_player
	var packages: Array[Node] = []
	packages.assign(get_nodes_in_group(&"cargo"))

	# --- the cargo bay has some give for whoever's already aboard ---
	var at_the_doors: Vector3 = van.to_global(Vector3(0.0, 1.0, 4.8))
	_expect(not van.carries(at_the_doors), "Just past the rear doors isn't in the bay")
	_expect(van.carries(at_the_doors, 0.4), "...but still counts for something already aboard")

	# --- a box carried in the bay rides on the host's truck ---
	var box: Node3D = packages[0]
	box.call(&"take_by", player)
	var hold := Transform3D(Basis(), Vector3(0.2, 1.2, 2.0))
	box.call(&"submit_carry_transform", hold, true)
	_expect(box.global_position.distance_to(van.global_transform * hold.origin) < 0.01,
		"A carry pose sent in the truck's space lands on the host's truck")
	van.global_transform = Transform3D(van.global_basis, van.global_position + Vector3(0.0, 0.0, -6.0))
	van.reset_physics_interpolation()
	await physics_frame
	await physics_frame
	_expect(box.global_position.distance_to(van.global_transform * hold.origin) < 0.01,
		"Between the carrier's updates the carried box keeps riding the truck")
	var set_down := Transform3D(Basis(), Vector3(0.3, 0.6, 3.0))
	box.call(&"request_drop", set_down, true)
	_expect(box.global_position.distance_to(van.global_transform * set_down.origin) < 0.01,
		"A box set down in the truck is placed on the host's truck")
	_expect(player.get(&"carried_package") == null, "...and the carrier's hands are empty")

	# --- trap input: only the box's tender, and never stale ---
	var tended: Node = packages[1]
	tended.call(&"submit_tender_input", {"steady": true})
	_expect((tended.get(&"player_input") as Dictionary).is_empty(), "Nobody tending: input is ignored")
	tended.call(&"set_tender", 1)
	tended.call(&"submit_tender_input", {"steady": true})
	_expect(bool((tended.get(&"player_input") as Dictionary).get("steady", false)), "The tender's input is taken")
	for i: int in range(30):
		await physics_frame
	_expect((tended.get(&"player_input") as Dictionary).is_empty(),
		"Input stops counting once the tender stops sending (paused, tabbed out)")
	tended.call(&"submit_tender_input", {"steady": true})
	tended.call(&"set_tender", 0)
	_expect((tended.get(&"player_input") as Dictionary).is_empty(), "Leaving the seat clears what they left behind")
	tended.set(&"tender_peer_id", 5)
	tended.call(&"submit_tender_input", {"steady": true})
	_expect((tended.get(&"player_input") as Dictionary).is_empty(), "Someone else's input for that box is ignored")
	tended.call(&"set_tender", 0)

	# --- a seated player's reach is their seat ---
	var seat: Node3D = van.get_node(^"CargoBay/LeftSeat1EyePoint")
	var standing_at: Vector3 = player.global_position
	player.set(&"seat_node_path", seat.get_path())
	_expect((player.call(&"reach_origin") as Vector3).distance_to(seat.global_position) < 0.001,
		"Seated, a player is within reach from their seat, not from where they sat down")
	player.set(&"seat_node_path", NodePath())
	_expect((player.call(&"reach_origin") as Vector3).distance_to(standing_at) < 0.001, "On foot, from where they stand")

	# --- remote interactions only within reach ---
	var mount: Node3D = get_nodes_in_group(&"package_mount")[0]
	player.global_position = mount.global_position + Vector3(1.0, 0.0, 0.0)
	_expect(bool(mount.call(&"_within_reach", player)), "Something right there is within reach")
	player.global_position = mount.global_position + Vector3(30.0, 0.0, 0.0)
	_expect(not bool(mount.call(&"_within_reach", player)), "Something across the map isn't")

	# --- no photo, and no bonus, for a house the run drove past ---
	run.call(&"reset_run")
	run.call(&"start_run")
	run.call(&"register_delivery", 0, &"missed", &"")
	_expect(not bool(run.call(&"attach_delivery_photo", 0)), "A missed house can't be photographed as a delivery")
	(run.get(&"deliveries") as Array)[0]["photo"] = true  # As an old save or a race could leave it.
	run.set(&"expected_houses", 1)
	run.call(&"finish_run", true)
	_expect(int((run.get(&"results") as Dictionary).get("photos", -1)) == 0, "A photo of a missed house earns nothing")

	# --- what a late joiner is told ---
	run.call(&"reset_run")
	var gone: Node = packages[2]
	var gone_path: String = String(gone.get_path())
	run.call(&"_receive_session_state", {
		"running": true, "mode": &"delivery", "event_id": &"", "elapsed": 12.5, "distance": 0.0,
		"expected_houses": 1, "deliveries": [{"house": 0, "outcome": &"delivered_ok", "package_id": &"x", "photo": false}],
		"cargo": {&"box_a": {"integrity": 80.0, "maximum": 100.0, "state": 0}}, "names": {&"box_a": "Frágil"},
		"consumed": [gone_path], "door_open": false, "results": {},
	})
	await process_frame
	_expect(bool(run.get(&"is_running")), "A joiner arriving mid-run is in the run")
	# The clock keeps running for the frame this test waited.
	var clock: float = float(run.get(&"elapsed_seconds"))
	_expect(clock >= 12.5 and clock < 13.0, "...with the host's clock (got %.3f)" % clock)
	_expect((run.get(&"deliveries") as Array).size() == 1, "...and the deliveries already made")
	_expect(not is_instance_valid(gone) or gone.is_queued_for_deletion(), "Boxes already handed over go away on the joiner")
	_expect(not bool(level.depot.door.get(&"is_open")), "The depot door is shut if it's shut on the host")
	run.call(&"reset_run")
	run.call(&"_receive_session_state", {"running": false, "results": {"score": 10}, "mode": &"delivery"})
	_expect(not bool(run.get(&"is_running")) and not (run.get(&"results") as Dictionary).is_empty(),
		"Arriving after the run ended: no run, and no new one can start until the host restarts")
	run.call(&"reset_run")

	# --- a box handed over at a door is recorded for late joiners ---
	var delivered: Node = packages[3]
	var delivered_path: String = String(delivered.get_path())
	delivered.call(&"consume", (delivered as Node3D).global_position)
	_expect((run.get(&"consumed_packages") as Array).has(delivered_path), "A handed-over box is recorded as gone")
	_expect(not delivered.is_in_group(&"cargo"), "...and stops being cargo at once")

	# --- a session that ends leaves nothing behind ---
	network.set(&"world_seed", 777)
	network.set(&"world_house_count", 3)
	network.set(&"world_locked_traps", [&"hostile"])
	network.set(&"world_completed_runs", 6)
	network.call(&"_fail", "Se cortó la conexión con el anfitrión.")
	_expect(int(network.get(&"world_seed")) == 0 and int(network.get(&"world_house_count")) == 0
		and (network.get(&"world_locked_traps") as Array).is_empty()
		and int(network.get(&"world_completed_runs")) == 0,
		"The next solo run doesn't keep building the old room's world")
	_expect(root.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "An offline peer, not none (no error spam)")
	_expect(String(network.call(&"take_failure_message")) == "Se cortó la conexión con el anfitrión."
		and String(network.call(&"take_failure_message")).is_empty(), "The menu is told why, once")
	_expect(level.local_player != null and is_instance_valid(level.local_player), "Players aren't deleted when a session ends")
	_expect(bool(network.call(&"is_peer_ready", 9)), "Offline, everyone counts as ready")

	# --- a player's sync is limited to ready peers before it registers ---
	# The synchronizer registers with the network the moment it enters the
	# tree; without the filter by then it counted as public and started
	# sending to peers still reloading after a host restart. Those never
	# resolved it, and never saw the host's player move again (3-process
	# probe, 2026-09-24). Same function installs both, so the connection
	# proves the filter.
	var fresh: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	fresh.name = "Player_7"
	var limited_in_time: Array[bool] = [false]
	fresh.get_node(^"MultiplayerSynchronizer").tree_entered.connect(func() -> void:
		limited_in_time[0] = network.peer_level_ready.is_connected(fresh._on_peer_level_ready))
	level.get_node(^"World").add_child(fresh)
	_expect(limited_in_time[0], "A player's sync is already limited to ready peers when it enters the tree")
	fresh.free()
	# Boxes too: after a host restart the new level's boxes were synced to
	# clients still on the old one, where a box handed over last run no longer
	# existed. That client never resolved it, and never saw that box move
	# again for the rest of the session.
	var box_scene: Node = load("res://scenes/gameplay/package/package.tscn").instantiate()
	box_scene.set(&"package_id", &"test_ready_box")
	var box_limited: Array[bool] = [false]
	box_scene.get_node(^"MultiplayerSynchronizer").tree_entered.connect(func() -> void:
		box_limited[0] = network.peer_level_ready.is_connected(box_scene._on_peer_level_ready))
	level.get_node(^"World").add_child(box_scene)
	_expect(box_limited[0], "A box's sync is already limited to ready peers when it enters the tree")
	box_scene.free()

	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: late joiners, handed-over boxes, carrying in the truck, tending, reach, photos and session end")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
