extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_network_roster.gd
## Covers the session bookkeeping without opening a socket: who is on the
## roster, who is the host, and that offline still behaves like a session of
## one. Real connectivity is a separate manual check (tests/net_smoke.gd).

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

	# The van seats five, so that's the cap the session advertises.
	_expect(int(network.get(&"MAX_PLAYERS")) == 5, "The session caps at the five seats in the van")

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

	if _failures == 0:
		print("PASS: roster bookkeeping, host role and offline fallback")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
