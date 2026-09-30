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
## - The configured auth and ENet timeouts cover a blocking level load, with
##   no earlier ENet MIN that drops an authenticating peer mid-load;
## - N-235, a real host and joiner over ENet in this process: both ends wait
##   out the joiner's load (45 s), drop a silent peer within the session
##   timeout (20 s) settle_delay_seconds after it's admitted, and go back to
##   45 s when a restart is announced (announce_restart(), or begin_restart()
##   alone) -- the notice leaves before the host polls again -- until the
##   client reports its level is back and the margin passes; nobody settles
##   while a restart is announced, a settle already scheduled checks again
##   when it fires, and a report from an earlier restart neither settles nor
##   counts the client ready while another one is owed or under way; a joiner
##   on another version leaves nothing applied behind; leaving forgets it all;
## - NetEventBus relays a fact locally when offline, and a request from the
##   local host lands as `event(peer_id, args...)` subject to its cooldown;
## - NetStats parses --net-sim profiles and grades metrics;
## - SteamVoice never opens the microphone with the switch off, records with
##   push-to-talk over a fake Steam, drops oversize packets, and mutes;
## - NetStatsOverlay builds on first show with the default theme.

const TIMEOUT_PORT: int = 7812
## The host's settle margin here (the default is seconds; the checks wait past it).
const SETTLE_SECONDS: float = 0.4
const SESSION_MSEC: int = NetSession.ENET_PEER_TIMEOUT_SESSION_MSEC

var _failures: int = 0


class GameSession extends NetSession:
	var world_seed: int = 0
	var houses: int = 0
	var restarted: Array = []
	var reloads: int = 0

	## No level here to reload: counts it instead (level_ready() is called by hand).
	func _reload_level() -> void:
		reloads += 1

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
	await _test_enet_timeouts()
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
	var auth_seconds: float = session.multiplayer.auth_timeout
	_expect(auth_seconds >= 40.0,
		"The configured auth timeout covers a slow level load (got %s s)" % auth_seconds)
	_expect(is_equal_approx(auth_seconds, NetSession.JOIN_HANDSHAKE_TIMEOUT),
		"Hosting applies the module's handshake timeout (got %s s)" % auth_seconds)
	_expect(NetSession.ENET_PEER_TIMEOUT_MIN_MSEC == NetSession.ENET_PEER_TIMEOUT_MAX_MSEC,
		"ENet has no earlier MIN that drops an authenticating peer mid-load")
	_expect(NetSession.ENET_PEER_TIMEOUT_MIN_MSEC >= int(auth_seconds * 1000.0),
		"ENet waits at least as long as authentication (got %s ms)" % NetSession.ENET_PEER_TIMEOUT_MIN_MSEC)
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


## N-235: a host and a joiner, each on its own SceneMultiplayer, over ENet on
## localhost. What each end tolerates from the other is read back with
## enet_timeout_msec() (ENet has no getter; the session keeps what it applied).
func _test_enet_timeouts() -> void:
	var load_msec: int = NetSession.ENET_PEER_TIMEOUT_MAX_MSEC
	var session_msec: int = NetSession.ENET_PEER_TIMEOUT_SESSION_MSEC
	_expect(session_msec >= 10000 and session_msec < load_msec,
		"In session a silent peer is dropped sooner than the load budget (got %d ms)" % session_msec)
	var defaults := NetSession.new()
	_expect(defaults.settle_delay_seconds >= 2.0, "By default the load budget holds a few seconds more")
	defaults.free()
	var host := GameSession.new()
	host.name = "TimeoutHost"
	var client := GameSession.new()
	client.name = "TimeoutClient"
	root.add_child(host)
	root.add_child(client)
	set_multiplayer(SceneMultiplayer.new(), host.get_path())
	set_multiplayer(SceneMultiplayer.new(), client.get_path())
	host.transport = NetSession.Transport.ENET
	client.transport = NetSession.Transport.ENET
	host.settle_delay_seconds = SETTLE_SECONDS
	var handshakes: Array = []
	client.session_ready.connect(func(is_host: bool) -> void: handshakes.append(is_host))
	_expect(host.enet_timeout_msec(NetSession.HOST_ID) == 0, "Offline nothing is applied")
	var hosted: bool = host.host_session(TIMEOUT_PORT) == OK
	var joining: bool = client.join_session("127.0.0.1", TIMEOUT_PORT) == OK
	_expect(hosted and joining, "A host and a joiner come up on localhost")
	if not (hosted and joining and await _wait_for(func() -> bool: return not handshakes.is_empty())):
		_expect(false, "The joiner never got the host's handshake")
		_drop_pair(host, client)
		return
	var joiner: int = client.multiplayer.get_unique_id()
	_expect(_pair_at(host, client, joiner, load_msec),
		"While the joiner loads its level both ends wait out the load (host %d, client %d ms)"
		% [host.enet_timeout_msec(joiner), client.enet_timeout_msec(NetSession.HOST_ID)])

	client.level_ready()  # Its level is up: it says ready and completes.
	await _wait_for(func() -> bool: return host.multiplayer.get_peers().has(joiner))
	_expect(host.enet_timeout_msec(joiner) == load_msec, "Just admitted, the host still waits out the joiner's level")
	_expect(await _wait_for(func() -> bool: return _pair_at(host, client, joiner, session_msec)),
		"settle_delay_seconds after it's in, both ends drop a silent peer within %d ms (host %d, client %d)"
		% [session_msec, host.enet_timeout_msec(joiner), client.enet_timeout_msec(NetSession.HOST_ID)])

	await _restart_without_announce(host, client, joiner)
	await _restart_announced(host, client, joiner)
	await _crossing_reports(host, client, joiner)
	await _refused_joiner(host)

	client.leave_session()
	host.leave_session()
	_expect(host.enet_timeout_msec(joiner) == 0 and client.enet_timeout_msec(NetSession.HOST_ID) == 0,
		"Leaving forgets what was applied")
	_drop_pair(host, client)


## begin_restart() with nobody announcing it first: the host reloads right
## after, blocking its polling, so its notice has to be on the wire already.
## Only the client is polled here.
func _restart_without_announce(host: GameSession, client: GameSession, joiner: int) -> void:
	var load_msec: int = NetSession.ENET_PEER_TIMEOUT_MAX_MSEC
	host.begin_restart()
	_expect(host.enet_timeout_msec(joiner) == load_msec, "The host waits out its clients again before it reloads")
	_expect(_client_told(client, load_msec), "The client waits out the host's reload, told before the host polls again")
	host.level_ready()  # The host's new level is up: every client reloads.
	_expect(await _wait_for(func() -> bool: return client.reloads == 1), "The client reloads for the restart")
	_expect(_pair_at(host, client, joiner, load_msec), "While the client reloads both ends still wait out the load")
	client.level_ready()  # Back from its reload: reports to the host.
	await _wait_for(func() -> bool: return host.is_peer_ready(joiner))
	_expect(_pair_at(host, client, joiner, load_msec), "Right after its report the load budget still holds")
	_expect(await _wait_for(func() -> bool: return _pair_at(host, client, joiner, SESSION_MSEC)),
		"Once the client is back both ends drop a silent peer within the session timeout again")


## announce_restart() ahead of the reload (restart_delivery() does it before
## its fade): both ends on the budget at once, nobody settles until the
## restart runs, and a settle already scheduled checks again when it fires.
func _restart_announced(host: GameSession, client: GameSession, joiner: int) -> void:
	var load_msec: int = NetSession.ENET_PEER_TIMEOUT_MAX_MSEC
	host.announce_restart()
	_expect(host.enet_timeout_msec(joiner) == load_msec, "An announced restart puts the host on the load budget")
	_expect(_client_told(client, load_msec), "An announced restart reaches the client while the host still polls")
	client.level_ready()  # A report while the restart is only announced.
	await _pump(SETTLE_SECONDS * 2.0)
	_expect(_pair_at(host, client, joiner, load_msec), "While a restart is announced nobody settles")
	host.announce_restart()
	host.begin_restart()
	_expect(_pair_at(host, client, joiner, load_msec) and not host.is_peer_ready(joiner),
		"begin_restart() after an announce keeps the budget and waits for the client's level")
	host.level_ready()
	_expect(await _wait_for(func() -> bool: return client.reloads == 2), "The client reloads for the announced restart")
	client.level_ready()
	await _wait_for(func() -> bool: return host.is_peer_ready(joiner))
	host.begin_restart()  # Within the settle margin: the scheduled settle must not go through.
	await _pump(SETTLE_SECONDS * 2.0)
	_expect(_pair_at(host, client, joiner, load_msec), "A settle scheduled before a restart began doesn't go through")
	host.level_ready()
	_expect(await _wait_for(func() -> bool: return client.reloads == 3), "The client reloads again")
	client.level_ready()
	_expect(await _wait_for(func() -> bool: return _pair_at(host, client, joiner, SESSION_MSEC)),
		"After the restart runs, the client's report settles both ends")


## Reports that cross a newer restart settle nothing and don't count the
## client ready: it reloads again and reports again.
func _crossing_reports(host: GameSession, client: GameSession, joiner: int) -> void:
	var load_msec: int = NetSession.ENET_PEER_TIMEOUT_MAX_MSEC
	host.begin_restart()
	client.level_ready()
	await _pump(0.3)
	_expect(_pair_at(host, client, joiner, load_msec) and not host.is_peer_ready(joiner),
		"A report arriving mid-restart keeps the load budget and doesn't count the client ready")
	host.level_ready()
	_expect(await _wait_for(func() -> bool: return client.reloads == 4), "The client reloads for the next restart")
	# Two restarts back to back: the first one's report still owes the second.
	host.begin_restart()
	host.level_ready()
	_expect(await _wait_for(func() -> bool: return client.reloads == 5), "The client reloads for a second restart")
	host.begin_restart()
	host.level_ready()
	_expect(await _wait_for(func() -> bool: return client.reloads == 6), "The client reloads for a third restart")
	client.level_ready()
	client.level_ready()
	await _pump(SETTLE_SECONDS * 2.0)
	_expect(_pair_at(host, client, joiner, load_msec) and not host.is_peer_ready(joiner),
		"A client still owing a reload keeps the load budget and isn't ready yet")
	client.level_ready()
	_expect(await _wait_for(func() -> bool: return _pair_at(host, client, joiner, SESSION_MSEC)),
		"Its last report brings both ends back to the session timeout")
	_expect(host.is_peer_ready(joiner), "Its last report counts it ready")


## A joiner on another protocol version never makes it in: what the host had
## applied to its link goes with it.
func _refused_joiner(host: GameSession) -> void:
	var stale := GameSession.new()
	stale.name = "TimeoutStale"
	stale.protocol_version = 6
	root.add_child(stale)
	set_multiplayer(SceneMultiplayer.new(), stale.get_path())
	stale.transport = NetSession.Transport.ENET
	var seen: Dictionary = {}
	var failed: Array = []
	var on_authenticating: Callable = func(id: int) -> void: seen[id] = host.enet_timeout_msec(id)
	var on_failed: Callable = func(id: int) -> void: failed.append(id)
	host.multiplayer.peer_authenticating.connect(on_authenticating)
	host.multiplayer.peer_authentication_failed.connect(on_failed)
	_expect(stale.join_session("127.0.0.1", TIMEOUT_PORT) == OK, "A joiner on another version can try")
	var stale_id: int = stale.multiplayer.get_unique_id()
	_expect(await _wait_for(func() -> bool: return failed.has(stale_id)), "The host sees its authentication fail")
	_expect(int(seen.get(stale_id, 0)) == NetSession.ENET_PEER_TIMEOUT_MAX_MSEC,
		"While it authenticated the host waited out its load")
	_expect(host.enet_timeout_msec(stale_id) == 0, "Once it failed the host forgets what it applied to it")
	host.multiplayer.peer_authenticating.disconnect(on_authenticating)
	host.multiplayer.peer_authentication_failed.disconnect(on_failed)
	stale.leave_session()
	set_multiplayer(null, stale.get_path())
	stale.free()


## Polls only the client (the host stands still, as if blocked) until it
## applies `msec` to the host, or a second passes.
func _client_told(client: GameSession, msec: int) -> bool:
	for attempt: int in 100:
		OS.delay_msec(10)
		client.multiplayer.poll()
		if client.enet_timeout_msec(NetSession.HOST_ID) == msec:
			return true
	return false


func _pair_at(host: NetSession, client: NetSession, joiner: int, msec: int) -> bool:
	return host.enet_timeout_msec(joiner) == msec and client.enet_timeout_msec(NetSession.HOST_ID) == msec


func _drop_pair(host: NetSession, client: NetSession) -> void:
	client.leave_session()
	host.leave_session()
	set_multiplayer(null, host.get_path())
	set_multiplayer(null, client.get_path())
	host.free()
	client.free()


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _pump(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


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
