extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_network_roster.gd
## Covers the session bookkeeping without opening a socket: who is on the
## roster, who is the host, and that offline still behaves like a session of
## one. Real connectivity is a separate manual check (tests/net_smoke.gd).
##
## Colour slots (N-226: color_slots.gd, NetworkManager.color_slot()):
## - with the big random peer ids ENet and Steam hand out, five players get
##   five different slots in arrival order, the host 0 (posmod(peer_id, 5), the
##   old colour, gave two of them the same one);
## - a slot freed by someone who left, or whose join failed, goes to the next
##   one in, and nobody else's slot moves;
## - a slot map from the network (join handshake, _sync_color_slots) with a
##   slot out of range, a repeated slot or odd types is refused whole, and the
##   RPC is only taken from the host;
## - offline, and for an id the host hasn't announced, color_slot() is the old
##   posmod(peer_id, MAX_PLAYERS): solo play keeps its colour.

## ENet/Steam-sized ids. Under the old posmod(peer_id, 5) the host (1) and the
## first of these share a colour, and so do the last two.
const BIG_IDS: Array[int] = [1_874_223_901, 1_802_117_455, 2_093_540_012, 1_955_001_337]
const NEWCOMER_ID: int = 2_001_234_568
const LEVEL: String = "res://scenes/gameplay/level_base.tscn"

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var network: Node = root.get_node(^"/root/NetworkManager")

	# Offline is a session of one, and the local player is the host.
	_expect(not bool(network.call(&"is_online")), "Offline reports no session")
	_expect(bool(network.call(&"is_host")), "Offline counts as host, so single-player uses the same path")
	_expect(int(network.call(&"local_id")) == 1, "Offline local id is the host id")
	_expect((network.get(&"peer_ids") as Array) == [1], "Offline roster holds just the host")

	# Peers joining and leaving keep the roster in order, and announce it.
	var announced: Array = []
	network.connect(&"roster_changed", func(ids: Array) -> void: announced.append(ids.duplicate()))
	network.call(&"_on_peer_connected", 22)
	network.call(&"_on_peer_connected", 33)
	_expect((network.get(&"peer_ids") as Array) == [1, 22, 33], "Joining peers land on the roster in order")
	network.call(&"_on_peer_connected", 22)
	_expect((network.get(&"peer_ids") as Array).size() == 3, "The same peer joining twice isn't counted twice")
	network.call(&"_on_peer_disconnected", 22)
	_expect((network.get(&"peer_ids") as Array) == [1, 33], "A leaving peer drops off the roster")
	_expect(announced.size() == 4, "Every roster change is announced (got %d)" % announced.size())
	_expect(announced[-1] == [1, 33], "The announcement carries the current roster")

	# The enlarged crew van holds a driver plus seven passengers.
	_expect(int(network.get(&"MAX_PLAYERS")) == 8, "The session caps at eight players")

	# Transport picking: Steam when it's really usable, ENet otherwise.
	# "Extension installed" and "Steam usable" are different things -- the
	# extension can be in place while Steam isn't running -- so availability
	# implies the class exists, but not the other way round.
	var steam_here: bool = bool(network.call(&"steam_available"))
	_expect(not steam_here or ClassDB.class_exists(&"SteamMultiplayerPeer"),
		"Steam can only be available when the extension is actually installed")
	var auto_choice: int = int(network.call(&"chosen_transport"))
	_expect(auto_choice == (1 if steam_here else 2),
		"AUTO picks Steam when present and falls back to ENet when not")
	network.set(&"transport", 2)  # ENET
	_expect(int(network.call(&"chosen_transport")) == 2, "Forcing ENet overrides the automatic choice")
	network.set(&"transport", 0)  # back to AUTO

	# Asking for Steam without the extension fails loudly instead of hanging.
	if not steam_here:
		var reasons: Array = []
		network.connect(&"session_failed", func(reason: String) -> void: reasons.append(reason))
		network.set(&"transport", 1)  # STEAM
		var error: int = int(network.call(&"host_session"))
		_expect(error != OK, "Hosting over Steam without the extension reports an error")
		_expect(reasons.size() == 1, "...and says why, instead of failing silently")
		network.set(&"transport", 0)

	network.call(&"leave_session")
	_expect((network.get(&"peer_ids") as Array) == [1], "Leaving resets the roster to a session of one")

	var max_players: int = int(network.get(&"MAX_PLAYERS"))
	_check_slot_rules(max_players)
	_check_random_ids(max_players)
	_check_slot_validation(max_players)
	_check_manager_slots(network, max_players)
	_check_handshake_and_rpc(network, max_players)
	network.call(&"leave_session")

	if _failures == 0:
		print("PASS: roster bookkeeping, host role, offline fallback and host-assigned colour slots")
	quit(_failures)


## ColorSlots on its own: arrival order, reuse of the lowest free slot, full room.
func _check_slot_rules(max_players: int) -> void:
	var old_colors: Array = [posmod(1, 5)]
	for id: int in BIG_IDS:
		old_colors.append(posmod(id, 5))
	_expect(_has_repeats(old_colors),
		"These ids share a colour under the old posmod(peer_id, 5) (got %s)" % [old_colors])

	var slots: Dictionary = {}
	_expect(ColorSlots.assign(slots, 1, max_players) == 0, "The host, first in, takes slot 0")
	for i: int in BIG_IDS.size():
		var got: int = ColorSlots.assign(slots, BIG_IDS[i], max_players)
		_expect(got == i + 1,
			"Joiner %d (id %d) takes slot %d in arrival order (got %d)" % [i + 1, BIG_IDS[i], i + 1, got])
	var values: Array = slots.values()
	values.sort()
	_expect(values == [0, 1, 2, 3, 4], "Five players wear five different slots (got %s)" % [values])
	_expect(ColorSlots.assign(slots, BIG_IDS[2], max_players) == 3 and slots.size() == 5,
		"Assigning a peer that already has a slot keeps it (got %s)" % [slots])

	var before: Dictionary = slots.duplicate()
	_expect(ColorSlots.release(slots, BIG_IDS[1]), "A leaving peer frees its slot")
	_expect(not ColorSlots.release(slots, BIG_IDS[1]), "Freeing the same peer twice finds nothing to free")
	for id: int in slots:
		_expect(slots[id] == before[id],
			"Peer %d keeps slot %d when someone else leaves (got %d)" % [id, before[id], slots[id]])
	var reused: int = ColorSlots.assign(slots, NEWCOMER_ID, max_players)
	_expect(reused == 2, "The next one in takes the freed slot 2 (got %d)" % reused)

	ColorSlots.release(slots, BIG_IDS[0])
	ColorSlots.release(slots, BIG_IDS[2])
	var first: int = ColorSlots.assign(slots, 2_100_000_001, max_players)
	var second: int = ColorSlots.assign(slots, 2_100_000_002, max_players)
	_expect(first == 1 and second == 3, "Two freed slots go lowest first: 1 then 3 (got %d, %d)" % [first, second])

	var id: int = 2_110_000_000
	while slots.size() < max_players:
		id += 1
		ColorSlots.assign(slots, id, max_players)
	_expect(ColorSlots.assign(slots, 2_120_000_000, max_players) == -1 and slots.size() == max_players,
		"With every slot taken there is none to give (got %d entries)" % slots.size())

	_expect(ColorSlots.slot_of({}, 1, max_players) == posmod(1, max_players),
		"Without a slot the host falls back to posmod(1, MAX_PLAYERS)")
	_expect(ColorSlots.slot_of({}, BIG_IDS[0], max_players) == posmod(BIG_IDS[0], max_players),
		"Without a slot a peer falls back to posmod(peer_id, MAX_PLAYERS)")


## Many crews of five random big ids: always slots 0..4, host 0, in arrival order.
func _check_random_ids(max_players: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 226
	var bad_rounds: int = 0
	for round_index: int in 200:
		var slots: Dictionary = {}
		var order: Array[int] = [1]
		ColorSlots.assign(slots, 1, max_players)
		while order.size() < 5:
			var id: int = rng.randi_range(1_800_000_000, 2_147_483_647)
			if order.has(id):
				continue
			order.append(id)
			ColorSlots.assign(slots, id, max_players)
		for i: int in order.size():
			if int(slots.get(order[i], -1)) != i:
				bad_rounds += 1
				break
	_expect(bad_rounds == 0,
		"200 crews of random big ids all get slots 0..4 in arrival order (%d didn't)" % bad_rounds)


## A slot map from the network is used whole or not at all.
func _check_slot_validation(max_players: int) -> void:
	_expect(ColorSlots.is_valid({1: 0, BIG_IDS[0]: 1}, max_players), "A proper slot map is accepted")
	var rejected: Array = [
		[[0, 1], "an Array"],
		["1:0", "a String"],
		[null, "null"],
		[{1: max_players}, "a slot past MAX_PLAYERS - 1"],
		[{1: -1}, "a negative slot"],
		[{1: 0.0}, "a float slot"],
		[{1: "0"}, "a String slot"],
		[{"1": 0}, "a String peer id"],
		[{1.0: 0}, "a float peer id"],
		[{0: 0}, "peer id 0"],
		[{-5: 1}, "a negative peer id"],
		[{1: 0, BIG_IDS[0]: 0}, "two peers on one slot"],
		[{1: [0]}, "an Array slot"],
	]
	for entry: Array in rejected:
		_expect(not ColorSlots.is_valid(entry[0], max_players), "A slot map with %s is refused" % entry[1])
	var crowded: Dictionary = {}
	for i: int in max_players + 1:
		crowded[100 + i] = i
	_expect(not ColorSlots.is_valid(crowded, max_players), "A slot map with more entries than players is refused")


## NetworkManager as the host (simulated offline, like the roster checks above).
func _check_manager_slots(network: Node, max_players: int) -> void:
	var offline_host: int = int(network.call(&"color_slot", 1))
	_expect(offline_host == posmod(1, max_players),
		"Offline the host's colour slot is the old posmod(1, MAX_PLAYERS) (got %d)" % offline_host)
	_expect(int(network.call(&"color_slot", BIG_IDS[0])) == posmod(BIG_IDS[0], max_players),
		"Offline an unknown peer falls back to posmod(peer_id, MAX_PLAYERS)")

	var changes: Array = []
	var on_changed: Callable = func(slots: Dictionary) -> void: changes.append(slots.duplicate())
	network.connect(&"color_slots_changed", on_changed)
	for id: int in BIG_IDS:
		network.call(&"_on_peer_connected", id)
	_expect(int(network.call(&"color_slot", 1)) == 0, "In a session the host wears slot 0")
	for i: int in BIG_IDS.size():
		var got: int = int(network.call(&"color_slot", BIG_IDS[i]))
		_expect(got == i + 1, "Big-id joiner %d gets slot %d on the host (got %d)" % [i + 1, i + 1, got])
	var expected: Dictionary = {1: 0, BIG_IDS[0]: 1, BIG_IDS[1]: 2, BIG_IDS[2]: 3, BIG_IDS[3]: 4}
	var last: Variant = changes[-1] if not changes.is_empty() else null
	_expect(last == expected, "color_slots_changed carries the whole current map (got %s)" % [last])

	network.call(&"_on_peer_disconnected", BIG_IDS[1])
	_expect(int(network.call(&"color_slot", BIG_IDS[1])) == posmod(BIG_IDS[1], max_players),
		"A peer that left has no slot any more")
	network.call(&"_on_peer_connected", NEWCOMER_ID)
	_expect(int(network.call(&"color_slot", NEWCOMER_ID)) == 2, "The next joiner reuses the freed slot 2")
	var kept: Array = [int(network.call(&"color_slot", 1)), int(network.call(&"color_slot", BIG_IDS[0])),
		int(network.call(&"color_slot", BIG_IDS[2])), int(network.call(&"color_slot", BIG_IDS[3]))]
	_expect(kept == [0, 1, 3, 4], "Nobody else's slot moves when one leaves and one joins (got %s)" % [kept])

	# A joiner gets its slot as soon as it starts authenticating (the handshake
	# carries it); if the join fails the slot is free again.
	var pending: int = 2_055_555_555
	var early: int = int(network.call(&"_assign_color_slot", pending))
	_expect(early == 5 and int(network.call(&"color_slot", pending)) == 5,
		"A joiner still authenticating already holds the next slot (got %d)" % early)
	network.call(&"_auth_failed", pending)
	_expect(int(network.call(&"color_slot", pending)) == posmod(pending, max_players),
		"A joiner whose authentication failed gives its slot back")
	_expect(int(network.call(&"_assign_color_slot", 2_066_666_666)) == 5, "...and the next one in takes it")

	network.call(&"leave_session")
	_expect(int(network.call(&"color_slot", 1)) == posmod(1, max_players),
		"Leaving the session puts the host back on the offline fallback")
	_expect(int(network.call(&"color_slot", NEWCOMER_ID)) == posmod(NEWCOMER_ID, max_players),
		"Leaving the session forgets every peer's slot")
	_expect(not changes.is_empty() and (changes[-1] as Dictionary).is_empty(), "Leaving announces the emptied map")
	network.disconnect(&"color_slots_changed", on_changed)


## A client takes the map from the join handshake and from the host's RPC, and
## only when it checks out.
func _check_handshake_and_rpc(network: Node, max_players: int) -> void:
	var state: Dictionary = {"version": int(network.get(&"PROTOCOL_VERSION")), "seed": 42, "houses": 2,
		"locked": [], "runs": 3, "scene": LEVEL, "colors": {1: 0, BIG_IDS[0]: 1}}
	_expect(String(network.call(&"_handshake_error", state)).is_empty(),
		"A handshake with a proper slot map is accepted")
	for bad: Variant in [{1: max_players}, {1: 0.5}, {"1": 0}, {1: 0, BIG_IDS[0]: 0}, [0, 1], "0"]:
		var broken: Dictionary = state.duplicate(true)
		broken.colors = bad
		_expect(String(network.call(&"_handshake_error", broken)) == "connection",
			"A handshake whose slot map is %s is refused as a connection error" % [bad])
	var missing: Dictionary = state.duplicate(true)
	missing.erase("colors")
	_expect(String(network.call(&"_handshake_error", missing)) == "connection",
		"A handshake without a slot map is refused as a connection error")

	var good: Dictionary = {1: 0, BIG_IDS[0]: 1, BIG_IDS[1]: 2}
	_expect(bool(network.call(&"_apply_color_slots", good)), "A client applies a proper map from the host")
	_expect(int(network.call(&"color_slot", BIG_IDS[1])) == 2, "...and reads its slots from it")
	for bad: Variant in [{1: max_players}, {1: -1}, {1: 1.0}, {"x": 1}, {1: 0, 7: 0}, null]:
		_expect(not bool(network.call(&"_apply_color_slots", bad)), "A client refuses the map %s" % [bad])
	_expect(int(network.call(&"color_slot", BIG_IDS[1])) == 2 and int(network.call(&"color_slot", 1)) == 0,
		"A refused map leaves the previous one in place")
	# Called straight, not through the network: this process counts as the
	# host, so the call is a no-op. The client-side sender check needs two
	# processes (net_trio).
	network.call(&"_sync_color_slots", {1: 3})
	_expect(int(network.call(&"color_slot", 1)) == 0, "On the host the slot RPC is a no-op")


func _has_repeats(values: Array) -> bool:
	for i: int in values.size():
		if values.find(values[i]) != i:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
