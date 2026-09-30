extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_session/tests/test_net_session.gd
##
## The net_session module on its own (docs/modulos.md), with a game-like
## subclass defined here:
## - NetSession offline is a session of one where the local peer is the host;
##   hosting over ENet announces the roster and session_ready(true); the
##   handshake refuses another protocol version, an unknown scene and a state
##   the game's hook rejects, and applies one it accepts; a failure ends the
##   session, says why once, and goes back to an offline peer; leaving resets
##   the game's state through its hook; the restart payload round-trips;
##   failure codes come out worded by the game;
## - NetEventBus relays a fact locally when offline, and a request from the
##   local host lands as `event(peer_id, args...)` subject to its cooldown;
## - NetStats parses --net-sim profiles and grades metrics;
## - SteamVoice never opens the microphone with the switch off, records with
##   push-to-talk over a fake Steam, drops oversize packets, and mutes;
## - NetStatsOverlay builds on first show with the default theme.

var _failures: int = 0


class GameSession extends NetSession:
	var world_seed: int = 0
	var houses: int = 0
	var restarted: Array = []

	func _init() -> void:
		protocol_version = 7
		level_scenes = ["res://levels/one.tscn", "res://levels/two.tscn"]

	func _on_hosting() -> void:
		world_seed = 4242
		houses = 3

	func _session_state() -> Dictionary:
		return {"seed": world_seed, "houses": houses}

	func _validate_session_state(state: Dictionary) -> String:
		return "" if state.has_all(["seed", "houses"]) else "connection"

	func _apply_session_state(state: Dictionary) -> void:
		world_seed = int(state.seed)
		houses = int(state.houses)

	func _reset_session_state() -> void:
		world_seed = 0
		houses = 0

	func _restart_state() -> Dictionary:
		return {"houses": houses}

	func _apply_restart_state(state: Dictionary) -> void:
		restarted.append(state)

	func _failure_text(code: String, args: Array = []) -> String:
		return "Port %d is taken" % args[0] if code == "port" else "worded:" + code


class GameBus extends NetEventBus:
	signal box_dropped(box: String)
	signal ping_sent(peer_id: int, position: Vector3)


# The fake mirrors GodotSteam's camelCase API, so its names can't be snake_case.
# gdlint: disable=function-name
class FakeSteam extends Object:
	var starts: int = 0
	var stops: int = 0
	var recording: bool = false

	func startVoiceRecording() -> void:
		starts += 1
		recording = true

	func stopVoiceRecording() -> void:
		stops += 1
		recording = false

	func getVoice() -> Dictionary:
		return {"result": 0, "buffer": PackedByteArray([1, 2, 3, 4]), "written": 4}

	func getVoiceOptimalSampleRate() -> int:
		return 24000

	func decompressVoice(packet: PackedByteArray, _rate: int) -> Dictionary:
		var pcm := PackedByteArray()
		pcm.resize(packet.size() * 10)
		return {"result": 0, "uncompressed": pcm, "size": pcm.size()}


class TestVoice extends SteamVoice:
	var enabled: bool = false
	var ptt: bool = true

	func _voice_enabled() -> bool:
		return enabled

	func _push_to_talk() -> bool:
		return ptt


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_session()
	_test_event_bus()
	_test_net_stats()
	_test_voice()
	await _test_overlay()
	if _failures == 0:
		print("PASS: a game session, bus, stats, voice and overlay work on the module alone")
	quit(_failures)


func _test_session() -> void:
	var session := GameSession.new()
	root.add_child(session)
	await process_frame
	_expect(not session.is_online() and session.is_host() and session.local_id() == 1,
		"Offline is a session of one, hosted locally")
	_expect(session.peer_ids == [1], "The offline roster holds the host")
	# On a machine with Steam running AUTO would pick it: every test forces ENet.
	_expect(session.chosen_transport() == NetSession.Transport.ENET or session.steam_available(),
		"AUTO picks ENet unless Steam is really usable")
	session.transport = NetSession.Transport.ENET
	var ready_flags: Array = []
	var rosters: Array = []
	var failures: Array = []
	session.session_ready.connect(func(is_host: bool) -> void: ready_flags.append(is_host))
	session.roster_changed.connect(func(ids: Array) -> void: rosters.append(ids))
	session.session_failed.connect(func(reason: String) -> void: failures.append(reason))
	_expect(session.host_session(7811) == OK, "Hosting over ENet works")
	_expect(session.is_online() and session.is_host() and session.active_transport == NetSession.Transport.ENET,
		"The host is online on ENet")
	_expect(ready_flags == [true] and rosters == [[1]], "Hosting announces the roster and session_ready(true)")
	_expect(session.world_seed == 4242 and session.houses == 3, "The game's hosting hook decided the world")
	var handshake: Dictionary = {"version": 7, "scene": "res://levels/two.tscn"}
	handshake.merge(session._session_state())
	_expect(String(session._handshake_error(handshake)).is_empty(), "The host's own handshake is accepted")
	var old: Dictionary = handshake.duplicate()
	old.version = 6
	_expect(session._handshake_error(old) == "version", "Another protocol is rejected as version")
	var elsewhere: Dictionary = handshake.duplicate()
	elsewhere.scene = "res://levels/three.tscn"
	_expect(session._handshake_error(elsewhere) == "connection", "An unknown level is rejected as connection")
	var incomplete: Dictionary = {"version": 7, "scene": "res://levels/one.tscn", "seed": 1}
	_expect(session._handshake_error(incomplete) == "connection", "State the game's hook rejects is rejected")
	_expect(session._ready_reply_error({"ready": true, "version": 7}).is_empty()
		and session._ready_reply_error({"ready": true, "version": 6}) == "version", "Ready replies are versioned")
	_expect(session._failure_text("port", [7811]) == "Port 7811 is taken", "A port failure is worded by the game")
	session.leave_session()
	_expect(not session.is_online() and session.world_seed == 0 and session.houses == 0,
		"Leaving goes offline and resets the game's state through its hook")
	_expect(session.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "The peer becomes an offline one, not null")
	# A joiner applying the host's state, then a failure.
	session._apply_session_state({"seed": 99, "houses": 5})
	_expect(session.world_seed == 99 and session.houses == 5, "A joiner keeps the host's state")
	session._fail("timeout")
	_expect(failures[-1] == "timeout" and session.take_failure_message() == "timeout",
		"A failure says why, and the menu can read it once")
	_expect(session.take_failure_message() == "", "The failure message is read once")
	_expect(session.world_seed == 0, "A failure resets the game's state")
	_expect(session._failure_text("host_lost") == "worded:host_lost", "Failure codes come out worded by the game")
	session.houses = 5
	session._apply_restart_state(session._restart_state())
	_expect(session.restarted == [{"houses": 5}], "The restart payload round-trips through the game's hooks")
	session.free()


func _test_event_bus() -> void:
	var bus := GameBus.new()
	root.add_child(bus)
	var dropped: Array = []
	var pings: Array = []
	bus.box_dropped.connect(func(box: String) -> void: dropped.append(box))
	bus.ping_sent.connect(func(peer_id: int, position: Vector3) -> void: pings.append([peer_id, position]))
	bus.relay(&"box_dropped", ["vase"])
	_expect(dropped == ["vase"], "Offline, a relayed fact fires the local signal")
	bus.request_cooldowns[&"ping_sent"] = 1.0
	bus.request(&"ping_sent", [Vector3.ONE])
	bus.request(&"ping_sent", [Vector3.ONE * 2.0])
	_expect(pings == [[1, Vector3.ONE]],
		"The host's request lands as event(peer_id, args); the second is within the cooldown (got %s)" % [pings])
	bus.reset_request_cooldowns()
	bus.request(&"ping_sent", [Vector3.ONE * 3.0])
	_expect(pings.size() == 2, "After the cooldown reset the next request goes through")
	bus.free()


func _test_net_stats() -> void:
	var sim: Dictionary = NetStats.parse_net_sim_value("150,20,2")
	_expect(sim == NetStats.STANDARD_SIM, "lag,jitter,loss parses (got %s)" % [sim])
	_expect(NetStats.parse_net_sim_value("standard") == NetStats.STANDARD_SIM, "'standard' is the standard profile")
	_expect(NetStats.parse_net_sim_value("banana").is_empty(), "Nonsense parses to nothing")
	_expect(NetStats.find_net_sim_arg(PackedStringArray(["--x",
		"--net-sim=1,2,3"])) == "1,2,3", "--net-sim is found among the args")
	var grades: Array[int] = []
	for ping: float in [50.0, 150.0, 500.0]:
		grades.append(NetStats.severity(&"ping", ping))
	_expect(grades == [0, 1, 2],
		"Ping is graded fine / worse / bad")
	_expect(not NetStats.describe_sim(sim).is_empty(), "A profile describes itself")


func _test_voice() -> void:
	var voice := TestVoice.new()
	root.add_child(voice)
	var fake := FakeSteam.new()
	voice.backend = fake
	voice.override_steam_session = 1
	var received: Array = []
	voice.voice_received.connect(
		func(peer: int, pcm: PackedByteArray, _rate: int) -> void: received.append([peer, pcm.size()]))
	voice.tick(true)
	_expect(fake.starts == 0 and not voice.talking, "With the switch off the microphone never opens")
	voice.enabled = true
	voice.tick(false)
	_expect(fake.starts == 0, "Push-to-talk: nothing without the key")
	voice.tick(true)
	_expect(fake.starts == 1 and voice.talking, "Holding the key opens the microphone")
	voice.tick(false)
	_expect(fake.stops == 1 and not voice.talking, "Releasing it closes the microphone")
	voice.ptt = false
	voice.tick(false)
	_expect(fake.starts == 2, "Open mic records without the key")
	voice.override_steam_session = 0
	voice.tick(true)
	_expect(fake.stops == 2, "Not over Steam, the microphone closes")
	voice.override_steam_session = 1
	voice.receive_packet(2, PackedByteArray([1, 2, 3]))
	_expect(received == [[2, 30]], "A packet is decompressed and handed out (got %s)" % [received])
	voice.set_peer_muted(2, true)
	voice.receive_packet(2, PackedByteArray([1, 2, 3]))
	_expect(received.size() == 1, "A muted peer is not heard")
	var huge := PackedByteArray()
	huge.resize(SteamVoice.MAX_PACKET_BYTES + 1)
	voice.receive_packet(3, huge)
	_expect(received.size() == 1, "An oversize packet is dropped")
	voice.free()
	fake.free()


func _test_overlay() -> void:
	var session := GameSession.new()
	root.add_child(session)
	var overlay := NetStatsOverlay.new()
	session.add_child(overlay)
	await process_frame
	_expect(not overlay.visible, "The overlay starts hidden")
	overlay.set_shown(true)
	_expect(overlay.visible and overlay.title_label != null and overlay.title_label.text != "",
		"Shown, it builds and draws a title")
	_expect(overlay.last_sample.get("transport", &"") == &"offline", "Offline it reports no transport")
	overlay.set_shown(false)
	_expect(not overlay.visible, "It hides again")
	session.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
