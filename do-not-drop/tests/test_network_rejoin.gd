extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_network_rejoin.gd
##
## Covers N-221's reconnection on top of N-226's colour slots, in one process
## without sockets (network_manager.gd reservations over ColorSlots,
## NetSession's identities, crew_progression.gd merit by slot, player.gd suit).
## A join is driven the way the transport does it: _admit_peer (slot while
## authenticating), _identify_peer (the ready reply), _on_peer_connected. The
## two-process version, with a real client dropping and joining again, is the
## last stage of tests/net_pair.gd.
## - a peer who leaves keeps showing its last slot (results) and, if the host
##   knows who it was, the slot is kept for it while others are free;
## - back under a new id with the same identity it gets that slot again, and
##   with it the merit the campaign keeps under the slot; peer_rejoined(old,
##   new) moves the merit earned this run;
## - back before the host noticed the drop: the old connection leaves the
##   roster as a ghost and the new one takes its slot;
## - with the room full a newcomer takes a kept slot but starts clean, without
##   that player's merit and card -- unless it is that player, back under the
##   same id (Steam);
## - however many come and go, reservations and remembered slots stay bounded;
## - the suit follows the host's map, also when it arrives after the spawn;
##   leaving the session forgets all of it.

const A: int = 1_874_223_901
const B: int = 1_802_117_455

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var crew: Node = root.get_node(^"/root/CrewProgression")
	network.call(&"leave_session")
	crew.call(&"reset_campaign")
	var max_players: int = int(network.get(&"MAX_PLAYERS"))

	var rejoins: Array = []
	network.connect(&"peer_rejoined", func(old_id: int, new_id: int) -> void: rejoins.append([old_id, new_id]))
	var changes: Array[int] = [0]
	network.connect(&"color_slots_changed", func(_slots: Dictionary) -> void: changes[0] += 1)

	_expect(int(crew.call(&"player_slot", 1)) == 0, "The host wears slot 0 (PlayerColorSlot), solo play included")
	_join(network, A, "tok-a")
	_join(network, B, "tok-b")
	_expect(_slot(network, 1) == 0 and _slot(network, A) == 1 and _slot(network, B) == 2,
		"Joiners take the free slots in arrival order (got %d, %d)" % [_slot(network, A), _slot(network, B)])

	# A earns merit and drops. The online host captures a leaver at
	# roster_changed (crew_progression.gd _on_roster_changed); done by hand here.
	crew.call(&"award_action", A, &"test:rejoin", 30)
	network.call(&"_on_peer_disconnected", A)
	crew.call(&"_capture_player", A)
	_expect(_slot(network, A) == 1, "Someone who left still reads its last slot (got %d)" % _slot(network, A))
	var saved: Dictionary = crew.get(&"_saved_players_by_slot")
	_expect(int((saved.get(1, {}) as Dictionary).get("merit", 0)) == 30,
		"The leaver's merit is kept under its slot, captured after the slot was released (got %s)" % [saved])
	_expect((network.get(&"_slot_reservations") as Dictionary).has(1), "Its slot is kept for it")

	# A newcomer leaves slot 1 for whoever might come back.
	var c: int = 1_955_001_337
	_join(network, c, "tok-c")
	_expect(_slot(network, c) == 3, "A newcomer skips a kept slot while others are free (got %d)" % _slot(network, c))

	# A comes back under a new id: same identity, same slot, same merit.
	var a2: int = 2_001_234_568
	_join(network, a2, "tok-a")
	_expect(_slot(network, a2) == 1, "The returning player gets its slot back (got %d)" % _slot(network, a2))
	_expect(rejoins == [[A, a2]], "The host announces who came back as whom (got %s)" % [rejoins])
	_expect(bool(network.call(&"inherits_color_slot", a2)), "A returning player inherits its slot")
	_expect(String(crew.call(&"player_color_key", a2)) == String((crew.get(&"PLAYER_COLOR_KEYS") as Array)[1]),
		"Its colour name follows the slot")
	crew.call(&"_apply_saved_player", a2)
	_expect(int((crew.get(&"merit") as Dictionary).get(a2, 0)) == 30,
		"Its merit comes back with the slot (got %s)" % (crew.get(&"merit") as Dictionary).get(a2))
	var run_merit: Dictionary = crew.get(&"_run_merit")
	_expect(int(run_merit.get(a2, 0)) == 30 and not run_merit.has(A),
		"This run's merit moves to the new peer id (got %s)" % [run_merit])
	_expect(not (network.get(&"_slot_reservations") as Dictionary).has(1), "The reservation is used up")

	# Back before the host noticed the drop: B's connection is a ghost of b2.
	var b2: int = 2_093_540_012
	_join(network, b2, "tok-b")
	var roster: Array = network.get(&"peer_ids")
	_expect(not roster.has(B) and roster.has(b2), "The ghost connection leaves the roster (got %s)" % [roster])
	_expect(_slot(network, b2) == 2, "The new connection takes the ghost's slot (got %d)" % _slot(network, b2))
	_expect(rejoins.size() == 2 and rejoins[1] == [B, b2], "...and its place (got %s)" % [rejoins])

	# The room fills up: eight players, eight slots.
	var extra: Array[int] = [2_100_000_004, 2_100_000_005, 2_100_000_006, 2_100_000_007]
	for index: int in extra.size():
		_join(network, extra[index], "tok-extra-%d" % index)
	var used: Dictionary = {}
	for peer: int in network.get(&"peer_ids"):
		used[_slot(network, peer)] = true
	_expect(used.size() == max_players,
		"%d players, %d different slots (got %s)" % [max_players, max_players, used.keys()])

	# The last one leaves with merit and a card; with the room otherwise full,
	# a newcomer gets the only free slot, kept for it -- and starts clean.
	var gone: int = extra[3]
	var gone_slot: int = _slot(network, gone)
	crew.call(&"award_action", gone, &"test:full", 40)
	(crew.get(&"cards") as Dictionary)[gone] = 2
	network.call(&"_on_peer_disconnected", gone)
	crew.call(&"_capture_player", gone)
	var newcomer: int = 2_110_000_001
	_join(network, newcomer, "tok-new")
	_expect(_slot(network, newcomer) == gone_slot,
		"A newcomer to a full room takes the free slot (got %d)" % _slot(network, newcomer))
	_expect(not bool(network.call(&"inherits_color_slot", newcomer)), "...which isn't its to inherit")
	crew.call(&"_apply_saved_player", newcomer)
	_expect(int((crew.get(&"merit") as Dictionary).get(newcomer, -1)) == 0
		and not (crew.get(&"cards") as Dictionary).has(newcomer),
		"...so it starts without the merit and card of the one who left")
	_expect(not (network.get(&"_slot_reservations") as Dictionary).has(gone_slot),
		"The one who left loses the reservation")

	# Full room, and one comes back under the same id (Steam): its own slot was
	# the only free one, so it isn't a newcomer.
	var c_slot: int = _slot(network, c)
	network.call(&"_on_peer_disconnected", c)
	var sent_before: int = changes[0]
	_join(network, c, "tok-c")
	_expect(_slot(network, c) == c_slot, "Same id, same slot (got %d)" % _slot(network, c))
	_expect(bool(network.call(&"inherits_color_slot", c)), "...and it inherits it: it's the same player")
	_expect(changes[0] > sent_before, "The slot map goes out to a peer back under its old id")
	_expect(rejoins.size() == 2, "Coming back under the same id has nothing to move")

	# However many come and go, the host's memory stays bounded.
	network.call(&"_on_peer_disconnected", newcomer)
	for index: int in 300:
		_join(network, 3_000_000 + index, "churn-%d" % index)
		network.call(&"_on_peer_disconnected", 3_000_000 + index)
	_expect((network.get(&"_slot_reservations") as Dictionary).size() <= max_players,
		"Reservations stay one per slot at most (got %d)" % (network.get(&"_slot_reservations") as Dictionary).size())
	_expect((network.get(&"_departed_slots") as Dictionary).size() <= int(network.get(&"DEPARTED_MEMORY")),
		"Remembered slots stay bounded (got %d)" % (network.get(&"_departed_slots") as Dictionary).size())

	# The suit follows the host's decision, also when it arrives after the spawn.
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.set_multiplayer_authority(a2)
	root.add_child(player)
	await process_frame
	# Not Player.PLAYER_COLORS: naming the class would compile player.gd with
	# this script, before the autoloads it names exist (see test_player_colors).
	var palette: Array = player.get_script().get_script_constant_map()["PLAYER_COLORS"]
	_expect(_suit(player) == palette[1], "The rejoined player's suit is its slot's colour again")
	var map: Dictionary = {1: 0, a2: 4}
	_expect(bool(network.call(&"_apply_color_slots", map)), "A client takes the host's map")
	_expect(_suit(player) == palette[4], "The suit changes when the host's map arrives after the spawn")
	_expect(_slot(network, b2) == 2, "A peer missing from the new map keeps its last slot for the results")
	player.queue_free()
	await process_frame

	network.call(&"leave_session")
	_expect((network.get(&"_color_slots") as Dictionary).is_empty()
		and (network.get(&"_slot_reservations") as Dictionary).is_empty()
		and (network.get(&"_departed_slots") as Dictionary).is_empty(), "Leaving the session forgets every slot")
	_expect(_slot(network, a2) == posmod(a2, max_players), "...so ids fall back to posmod(peer_id, MAX_PLAYERS)")
	crew.call(&"reset_campaign")
	if _failures == 0:
		print("PASS: a returning player gets its slot and merit back; ghosts go; full rooms start newcomers clean")
	quit(_failures)


## What the host does for a joiner: a slot while it authenticates, who it is
## from its ready reply, then its connection.
func _join(network: Node, id: int, token: String) -> void:
	_expect(String(network.call(&"_admit_peer", id)).is_empty(), "Peer %d is admitted" % id)
	network.call(&"_identify_peer", id, {"ready": true, "identity": token})
	network.call(&"_on_peer_connected", id)


func _slot(network: Node, peer: int) -> int:
	return int(network.call(&"color_slot", peer))


func _suit(player: Node) -> Color:
	var meshes: Array[Node] = player.get_node(^"BodyVisual").find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		var material := mesh.get_surface_override_material(0) as StandardMaterial3D
		if material != null:
			return material.albedo_color
	return Color.BLACK


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
