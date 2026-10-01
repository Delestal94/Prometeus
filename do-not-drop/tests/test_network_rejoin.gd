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
## N-221 follow-ups:
## - a ghost dropped for its rejoin while its player carries a box in crisis:
##   the rescue window is held right then (NetworkManager.peer_removed), and
##   its connection closing later holds nothing again;
## - a room full with eight, one of them a ghost: its player coming back is
##   let in once it says who it is, with the ghost's slot and merit, and a
##   stranger hears "full" (NetAdmission; the transport's spare connection is
##   in modules/net_session/tests/test_net_session_rejoin.gd);
## - a newcomer who takes the slot kept for someone who left doesn't overwrite
##   their campaign entry: it is set aside and given back when they return;
## - a joiner handed the slot kept for someone else gives the reservation back
##   if it never makes it in, or turns out to be someone back for another.

const A: int = 1_874_223_901
const B: int = 1_802_117_455

## Loaded twice (the suit, the ghost's box): a path, so it is named once.
const PLAYER_SCENE: String = "res://scenes/gameplay/player/player.tscn"

var _failures: int = 0
## A stand-in joiner per token: its hash chain of claims (NetPeerIdentities),
## so each join of the same "running game" sends the next link.
var _chains: Dictionary = {}


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
	var player: Node = load(PLAYER_SCENE).instantiate()
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

	await _check_ghost_holds_box(network)
	_check_full_room(network, crew)
	_check_turned_away_before_anything_moves(network, crew)
	_check_displaced_entry(network, crew)
	_check_borrowed_reservations(network)
	network.call(&"leave_session")
	crew.call(&"reset_campaign")
	if _failures == 0:
		print("PASS: a returning player gets its slot and merit back; ghosts go, holding their box's rescue;"
			+ " full rooms take back a ghost's player and start newcomers clean")
	quit(_failures)


## A ghost's box: held at the drop, while its player still holds it -- the
## connection only closes 0.5-2 s later, after the level freed that player.
func _check_ghost_holds_box(network: Node) -> void:
	network.call(&"leave_session")
	var ghost: int = 1_201_000_001
	_join(network, ghost, "tok-ghost")
	var package: Node = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	var player: Node = load(PLAYER_SCENE).instantiate()
	player.name = "Player_%d" % ghost
	player.set_multiplayer_authority(ghost)
	root.add_child(player)
	await process_frame
	package.call(&"take_by", player)
	var care: Object = package.get(&"care")
	care.call(&"begin_crisis", &"fragile")
	care.set(&"crisis_left", 5.0)
	_expect(package.get(&"carrier") == player, "The ghost's player holds a box in crisis")
	# Back before the drop was noticed: its ready reply drops the ghost. (Not
	# connected after: with no real peer, a box can't update its visibility.)
	var back: int = 1_201_000_002
	network.call(&"_admit_peer", back)
	network.call(&"_identify_peer", back, _reply("tok-ghost"))
	_expect(not (network.get(&"peer_ids") as Array).has(ghost), "Back before the drop was noticed: the ghost goes")
	var window: float = float(care.get(&"crisis_left"))
	_expect(window >= 14.9, "The box's rescue window is held as the ghost is dropped (%.1f s left)" % window)
	player.free()  # What the level does on roster_changed.
	_expect(package.get(&"carrier") == null and not bool(package.get(&"is_held")), "...and the box drops loose")
	care.set(&"crisis_left", 9.0)
	network.call(&"_on_peer_disconnected", ghost)
	network.multiplayer.peer_disconnected.emit(ghost)
	_expect(is_equal_approx(float(care.get(&"crisis_left")), 9.0),
		"The ghost's connection closing later holds nothing again (%.1f s left)" % float(care.get(&"crisis_left")))
	package.free()
	network.call(&"leave_session")


## Host and seven, one of them a ghost: the transport let one more reach the
## host (NetSession._host_enet), and NetAdmission decides from its ready reply.
func _check_full_room(network: Node, crew: Node) -> void:
	network.call(&"leave_session")
	crew.call(&"reset_campaign")
	var admission: Object = network.get(&"_admission")
	var max_players: int = int(network.get(&"MAX_PLAYERS"))
	var aboard: Array[int] = []
	for index: int in max_players - 1:
		var id: int = 1_300_000_000 + index
		_expect(_admit(network, admission, id, "tok-full-%d" % index).is_empty(), "Joiner %d is let in" % index)
		aboard.append(id)
	_expect((network.get(&"peer_ids") as Array).size() == max_players, "The room is full")
	var ghost: int = aboard[3]
	var ghost_slot: int = _slot(network, ghost)
	crew.call(&"award_action", ghost, &"test:full-ghost", 25)
	var back: int = 1_310_000_000
	var stranger: int = 1_320_000_000
	_expect(String(admission.call(&"on_authenticating", network, back)).is_empty(),
		"Back while its ghost holds a place, a joiner goes on unplaced")
	_expect(not (network.get(&"_color_slots") as Dictionary).has(back), "...without a slot of its own yet")
	_expect(String(admission.call(&"on_authenticating", network, stranger)).is_empty(), "...and so does a stranger")
	var reply: Dictionary = _reply("tok-full-3")
	_expect(String(admission.call(&"on_identified", network, back, reply)).is_empty(),
		"Its ready reply says it is the ghost's player: it is let in")
	crew.call(&"_capture_player", ghost)  # The online host captures a leaver at roster_changed.
	network.call(&"_on_peer_connected", back)
	var roster: Array = network.get(&"peer_ids")
	_expect(roster.size() == max_players and roster.has(back) and not roster.has(ghost),
		"The ghost made room for it (roster %s)" % [roster])
	_expect(_slot(network, back) == ghost_slot and bool(network.call(&"inherits_color_slot", back)),
		"It wears the ghost's slot and inherits it (slot %d, was %d)" % [_slot(network, back), ghost_slot])
	crew.call(&"_apply_saved_player", back)
	_expect(int((crew.get(&"merit") as Dictionary).get(back, 0)) == 25, "...and its merit comes back with it")
	_expect(String(admission.call(&"on_identified", network, stranger, _reply("tok-z"))) == "full",
		"The stranger hears full once it says who it is")
	network.call(&"_auth_failed", stranger)
	_expect(not (network.get(&"_color_slots") as Dictionary).has(stranger), "...holding no slot")
	network.call(&"leave_session")
	crew.call(&"reset_campaign")


## N-221 follow-up: someone who left comes back to a room that filled up
## again, with no ghost of its own to make room. It hears "full" before
## anything moves: identify() used to run first, and peer_rejoined moved this
## run's merit to a peer id that never got in.
func _check_turned_away_before_anything_moves(network: Node, crew: Node) -> void:
	network.call(&"leave_session")
	crew.call(&"reset_campaign")
	var admission: Object = network.get(&"_admission")
	var aboard: Array[int] = _fill_room(network, "tok-away")
	var gone: int = aboard[2]
	crew.call(&"award_action", gone, &"test:turned-away", 30)
	network.call(&"_on_peer_disconnected", gone)
	_join(network, 1_420_000_001, "tok-away-new")  # The room fills up again.
	var rejoins: Array = []
	var on_rejoined: Callable = func(old_id: int, new_id: int) -> void: rejoins.append([old_id, new_id])
	network.connect(&"peer_rejoined", on_rejoined)
	var back: int = 1_420_000_002
	_expect(String(admission.call(&"on_authenticating", network, back)).is_empty(), "Back to a full room: unplaced")
	_expect(String(admission.call(&"on_identified", network, back, _reply("tok-away-2"))) == "full",
		"With no ghost of its own to make room it hears full")
	var run_merit: Dictionary = crew.get(&"_run_merit")
	_expect(rejoins.is_empty() and int(run_merit.get(gone, 0)) == 30 and not run_merit.has(back),
		"...before anything moves: its run's merit stays where it was (rejoins %s, merit %s)" % [rejoins, run_merit])
	_expect(not (network.get(&"_color_slots") as Dictionary).has(back), "...and no slot is handed to it")
	network.call(&"_auth_failed", back)
	network.disconnect(&"peer_rejoined", on_rejoined)
	network.call(&"leave_session")
	crew.call(&"reset_campaign")


## N-221 follow-up: the newcomer's own entry used to be captured over the one
## kept under the slot for whoever left it.
func _check_displaced_entry(network: Node, crew: Node) -> void:
	network.call(&"leave_session")
	crew.call(&"reset_campaign")
	var aboard: Array[int] = _fill_room(network, "tok-disp")
	var gone: int = aboard[2]
	var gone_slot: int = _slot(network, gone)
	crew.call(&"award_action", gone, &"test:displaced", 40)
	(crew.get(&"cards") as Dictionary)[gone] = 2
	network.call(&"_on_peer_disconnected", gone)
	crew.call(&"_capture_player", gone)
	var newcomer: int = 1_410_000_001
	_join(network, newcomer, "tok-disp-new")
	_expect(_slot(network, newcomer) == gone_slot and not bool(network.call(&"inherits_color_slot", newcomer)),
		"A newcomer to the otherwise full room takes the kept slot, without inheriting it")
	_expect(int(network.call(&"slot_kept_for", newcomer)) == gone, "...and the host knows whose it was")
	crew.call(&"_apply_saved_player", newcomer)
	crew.call(&"_capture_player", newcomer)
	var saved: Dictionary = crew.get(&"_saved_players_by_slot")
	var palette_slot: int = int(crew.call(&"player_slot", newcomer))
	_expect(int((saved.get(palette_slot, {}) as Dictionary).get("merit", -1)) == 0,
		"The newcomer's own entry is what the slot keeps now")
	var displaced: Dictionary = (crew.get(&"_displaced_players") as Dictionary).get(gone, {})
	_expect(int(displaced.get("merit", 0)) == 40 and int(displaced.get("card", -1)) == 2,
		"The one it pushed out is set aside, merit and card (got %s)" % [displaced])
	# The newcomer leaves; the one who left comes back.
	network.call(&"_on_peer_disconnected", newcomer)
	crew.call(&"_capture_player", newcomer)
	var back: int = 1_410_000_002
	_join(network, back, "tok-disp-2")
	crew.call(&"_apply_saved_player", back)
	_expect(int((crew.get(&"merit") as Dictionary).get(back, 0)) == 40
		and int((crew.get(&"cards") as Dictionary).get(back, -1)) == 2,
		"Back again, it gets its own merit and card, not the slot's (merit %s)"
		% (crew.get(&"merit") as Dictionary).get(back))
	network.call(&"leave_session")
	crew.call(&"reset_campaign")


## N-221 follow-up: _assign_color_slot() used to lose the reservation of the
## one a slot was kept for, whatever became of the joiner it was handed to.
func _check_borrowed_reservations(network: Node) -> void:
	network.call(&"leave_session")
	var aboard: Array[int] = _fill_room(network, "tok-borrow")
	var first: int = aboard[0]
	var second: int = aboard[1]
	var first_slot: int = _slot(network, first)
	var second_slot: int = _slot(network, second)
	network.call(&"_on_peer_disconnected", first)
	network.call(&"_on_peer_disconnected", second)
	var reservations: Dictionary = network.get(&"_slot_reservations")
	_expect(reservations.has(first_slot) and reservations.has(second_slot), "Both slots are kept")
	var stray: int = 1_510_000_001
	_expect(int(network.call(&"_assign_color_slot", stray)) == first_slot,
		"A joiner to the otherwise full room is handed the lowest kept slot")
	network.call(&"_auth_failed", stray)
	reservations = network.get(&"_slot_reservations")
	_expect(int((reservations.get(first_slot, {}) as Dictionary).get("peer", 0)) == first,
		"It never made it in: the slot is kept for whoever it was kept for again (got %s)" % [reservations])
	var second_back: int = 1_510_000_002
	_expect(String(network.call(&"_admit_peer", second_back)).is_empty() and _slot(network, second_back) == first_slot,
		"Someone coming back is handed the lowest kept slot while it authenticates")
	network.call(&"_identify_peer", second_back, _reply("tok-borrow-1"))
	network.call(&"_on_peer_connected", second_back)
	reservations = network.get(&"_slot_reservations")
	_expect(_slot(network, second_back) == second_slot and bool(network.call(&"inherits_color_slot", second_back)),
		"...moves to its own once it says who it is")
	_expect(int((reservations.get(first_slot, {}) as Dictionary).get("peer", 0)) == first,
		"...and the slot it was handed is kept for its owner again (got %s)" % [reservations])
	var first_back: int = 1_510_000_003
	_join(network, first_back, "tok-borrow-0")
	_expect(_slot(network, first_back) == first_slot and bool(network.call(&"inherits_color_slot", first_back)),
		"Its owner comes back to it")
	network.call(&"leave_session")


## The host and MAX_PLAYERS - 1 joiners, `prefix-<index>` each.
func _fill_room(network: Node, prefix: String) -> Array[int]:
	var aboard: Array[int] = []
	for index: int in int(network.get(&"MAX_PLAYERS")) - 1:
		var id: int = 1_400_000_000 + index * 7 + prefix.length()
		_join(network, id, "%s-%d" % [prefix, index])
		aboard.append(id)
	return aboard


## The next claim of the stand-in joiner `token`: the first time the end of
## its chain, then each time the link before (NetPeerIdentities.claim()).
func _reply(token: String) -> Dictionary:
	if not _chains.has(token):
		var chain := NetPeerIdentities.new()
		chain._token = token
		_chains[token] = chain
	return {"ready": true, "identity": (_chains[token] as NetPeerIdentities).claim()}


## What the host does for a joiner through NetAdmission (NetSession's
## handshake): a place as it authenticates, who it is from its ready reply,
## then its connection. "" when it got in.
func _admit(network: Node, admission: Object, id: int, token: String) -> String:
	var refusal: String = admission.call(&"on_authenticating", network, id)
	if refusal.is_empty():
		refusal = admission.call(&"on_identified", network, id, _reply(token))
	if refusal.is_empty():
		network.call(&"_on_peer_connected", id)
	return refusal


## What the host does for a joiner: a slot while it authenticates, who it is
## from its ready reply, then its connection.
func _join(network: Node, id: int, token: String) -> void:
	_expect(String(network.call(&"_admit_peer", id)).is_empty(), "Peer %d is admitted" % id)
	network.call(&"_identify_peer", id, _reply(token))
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
