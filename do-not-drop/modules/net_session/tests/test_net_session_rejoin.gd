extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_session/tests/test_net_session_rejoin.gd
##
## NetSession's rejoin by identity (net_session module, docs/modulos.md), in
## one process without sockets (the host's side, driven through the same
## functions the transport calls):
## - hosting makes a session nonce and leaving forgets it; a joiner's ready
##   reply carries a hash of its process token with that nonce -- the same on
##   every rejoin, another for another session, never the token itself;
## - the host keeps who each peer is (peer_identity()), still readable in the
##   game's _peer_left hook, and forgets it after;
## - someone who left and comes back under a new id: the game's _peer_returned
##   hook and peer_rejoined(old, new);
## - back before the host noticed the drop: the old connection is dropped as
##   a ghost (off the roster, _peer_left for it, once), and its late
##   disconnect does nothing more;
## - back under the same id: _peer_returned(id, id) but no peer_rejoined;
##   claiming nothing usable (not text, too long, empty): nothing at all;
## - a failed authentication forgets the identity; however many come and go,
##   the memory of those who left stays bounded (NetPeerIdentities.MEMORY);
## - peer_removed comes once per leave, before roster_changed, for a ghost
##   when it is dropped and not again when its connection closes;
## - a full room (NetAdmission): a joiner who can't be told yet goes on
##   unplaced, gets in once it turns out to be a ghost's player (or someone
##   left meanwhile), and hears "full" otherwise;
## - the same over ENet in this process, in a room of two: the transport takes
##   one connection more than the room, so a joiner who went silent (nobody
##   polls its link: a pulled cable) and comes back from the same game reaches
##   the host while its ghost still holds the place, gets in, and the ghost
##   goes -- its late close changes nothing -- while a stranger hears "full".

const FULL_ROOM_PORT: int = 7816

var _failures: int = 0


class GameSession extends NetSession:
	var left: Array = []
	var identities_when_left: Array = []
	var returned: Array = []

	func _init() -> void:
		protocol_version = 3
		level_scenes = ["res://levels/one.tscn"]

	func _peer_left(id: int) -> void:
		left.append(id)
		identities_when_left.append(peer_identity(id))

	func _peer_returned(id: int, previous_id: int) -> void:
		returned.append([previous_id, id])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session := GameSession.new()
	root.add_child(session)
	await process_frame
	session.transport = NetSession.Transport.ENET

	_expect(session.host_session(7813) == OK, "Hosting over ENet works")
	var nonce: String = session._identities.nonce
	_expect(nonce.length() == 16, "Hosting makes a session nonce (got '%s')" % nonce)
	session.leave_session()
	_expect(session._identities.nonce.is_empty(), "Leaving forgets it")

	# The joiner's side of the handshake.
	session._identities.nonce = "abc123"
	var token: String = session._identities.local_token()
	var reply: Dictionary = session._ready_reply()
	_expect(String(reply.identity) == (token + "abc123").sha256_text() and not String(reply.identity).contains(token),
		"The ready reply carries the token hashed with the session nonce, not the token")
	_expect(String(session._ready_reply().identity) == String(reply.identity), "...the same on every rejoin")
	_expect(session._ready_reply_error(reply).is_empty(), "...and is still a valid ready reply")
	session._identities.nonce = "other"
	_expect(String(session._ready_reply().identity) != String(reply.identity), "...and another for another session")
	session._identities.nonce = ""

	# The host's side: joiners identify themselves before they connect.
	var rejoins: Array = []
	var rosters: Array = []
	var removed: Array = []
	session.peer_rejoined.connect(func(old_id: int, new_id: int) -> void: rejoins.append([old_id, new_id]))
	session.roster_changed.connect(func(ids: Array) -> void: rosters.append(ids.duplicate()))
	# What a listener sees when it hears: the roster still unannounced, and who it was.
	session.peer_removed.connect(func(id: int) -> void:
		removed.append([id, rosters.size(), session.peer_identity(id)]))
	_join(session, 22, "tok-a")
	_join(session, 37, "tok-b")
	_expect(session.peer_identity(22) == "lan:tok-a" and session.peer_identity(37) == "lan:tok-b",
		"The host knows who each peer is")
	_expect(rejoins.is_empty() and session.returned.is_empty(), "Newcomers are nobody's return")

	var rosters_before: int = rosters.size()
	session._on_peer_disconnected(22)
	_expect(session.left == [22] and session.identities_when_left == ["lan:tok-a"],
		"The game's _peer_left still sees who left (got %s)" % [session.identities_when_left])
	_expect(session.peer_identity(22).is_empty(), "...and the identity is forgotten after it")
	_expect(removed == [[22, rosters_before, "lan:tok-a"]],
		"peer_removed comes once, before roster_changed, while who it was is known (got %s)" % [removed])

	_join(session, 58, "tok-a")
	_expect(rejoins == [[22, 58]] and session.returned == [[22, 58]],
		"Coming back under a new id: _peer_returned and peer_rejoined(old, new) (got %s)" % [rejoins])

	# Back before the host noticed the drop: 37's connection is a ghost of 69.
	rosters.clear()
	session.left.clear()
	session._identify_peer(69, {"ready": true, "identity": "tok-b"})
	_expect(not session.peer_ids.has(37), "The ghost connection leaves the roster (got %s)" % [session.peer_ids])
	_expect(session.left == [37] and rosters.size() == 1 and not (rosters[0] as Array).has(37),
		"...as any leave: _peer_left and roster_changed, once (left %s, rosters %s)" % [session.left, rosters])
	_expect(rejoins.size() == 2 and rejoins[1] == [37, 69], "...and its place goes to the new one (got %s)" % [rejoins])
	_expect(removed.size() == 2 and int(removed[1][0]) == 37,
		"A ghost is removed (peer_removed) when it is dropped, not when it closes (got %s)" % [removed])
	session._on_peer_connected(69)
	session._on_peer_disconnected(37)
	_expect(session.left == [37] and rosters.size() == 2, "The ghost's late disconnect does nothing more")
	_expect(removed.size() == 2, "...not even a second peer_removed (got %s)" % [removed])

	# Back under the same id (Steam can hand it out again): the game gives back
	# what it kept, but nothing moved, so no peer_rejoined.
	session._identify_peer(69, {"ready": true, "identity": "tok-b"})
	_expect(session.returned[-1] == [69, 69] and rejoins.size() == 2,
		"Back under the same id: _peer_returned(id, id), no peer_rejoined (got %s)" % [session.returned])
	# No rejoin: nothing usable claimed.
	for bad: Variant in [42, "", "x".repeat(RpcGuard.MAX_TEXT_LENGTH + 1), ["tok-a"], null]:
		session._identify_peer(90, {"ready": true, "identity": bad})
		_expect(session.peer_identity(90).is_empty(), "A claimed identity like %s is ignored" % [bad])
	_expect(rejoins.size() == 2, "...and brings nobody back")

	# A failed authentication.
	session._identify_peer(99, {"ready": true, "identity": "tok-z"})
	_expect(session.peer_identity(99) == "lan:tok-z", "The identity is kept while authenticating")
	session._auth_failed(99)
	_expect(session.peer_identity(99).is_empty(), "A failed authentication forgets it")

	# Churn: a peer reconnecting under a new identity every time.
	for index: int in 200:
		_join(session, 1000 + index, "churn-%d" % index)
		session._on_peer_disconnected(1000 + index)
	var here: int = session.peer_ids.size()
	var remembered: int = session._identities.peer_by_identity.size()
	_expect(remembered <= here + NetPeerIdentities.MEMORY,
		"200 comings and goings leave %d identities remembered (crew %d)" % [remembered, here])

	session.leave_session()
	_expect(session._identities.peer_by_identity.is_empty() and session._identities.by_peer.is_empty(),
		"Leaving forgets everyone")
	_check_full_room(session)
	session.free()
	await _check_full_room_over_enet()
	if _failures == 0:
		print("PASS: rejoin by identity: hashed tokens, returns, ghosts dropped once, bounded memory, full rooms")
	quit(_failures)


## NetAdmission with no sockets, the way the transport drives it: a room of
## three (host, 22 and 37) where 22's connection is a ghost.
func _check_full_room(session: GameSession) -> void:
	session.max_players = 3
	var admission: NetAdmission = session._admission
	_expect(admission.on_authenticating(session, 22).is_empty(), "A joiner with room is let in")
	_expect(admission.admitted.has(22), "...and counts while it authenticates")
	_expect(admission.on_authenticating(session, 37).is_empty() and admission.admitted.size() == 2,
		"So does the next one, up to max_players")
	_expect(admission.on_identified(session, 22, {"ready": true, "identity": "tok-a"}).is_empty(),
		"Its ready reply lets it in")
	session._on_peer_connected(22)
	_expect(admission.on_identified(session, 37, {"ready": true, "identity": "tok-b"}).is_empty(), "...and 37")
	session._on_peer_connected(37)
	_expect(admission.admitted.is_empty(), "Once connected they count on the roster instead")

	# 22 comes back before the host noticed its drop: the room is full.
	var rejoins: Array = []
	session.peer_rejoined.connect(func(old_id: int, new_id: int) -> void: rejoins.append([old_id, new_id]))
	_expect(admission.on_authenticating(session, 58).is_empty() and admission.unplaced.has(58),
		"With the room full a joiner who can't be told yet goes on unplaced (LAN)")
	_expect(admission.on_authenticating(session, 77).is_empty() and admission.unplaced.has(77),
		"...as does a stranger")
	_expect(not admission.admitted.has(58) and not admission.admitted.has(77), "...holding no place meanwhile")
	_expect(admission.on_identified(session, 58, {"ready": true, "identity": "tok-a"}).is_empty(),
		"The one who turns out to be a ghost's player gets in")
	_expect(not session.peer_ids.has(22) and rejoins == [[22, 58]], "...and the ghost goes (got %s, %s)"
		% [session.peer_ids, rejoins])
	session._on_peer_connected(58)
	_expect(admission.on_identified(session, 77, {"ready": true, "identity": "tok-z"}) == "full",
		"The stranger hears full once it says who it is")
	session._auth_failed(77)
	_expect(admission.unplaced.is_empty() and admission.admitted.is_empty(), "...and is forgotten")

	# Someone leaves while an unplaced joiner loads: there's a place after all.
	_expect(admission.on_authenticating(session, 81).is_empty() and admission.unplaced.has(81), "Full again")
	session._on_peer_disconnected(37)
	_expect(admission.on_identified(session, 81, {"ready": true, "identity": "tok-y"}).is_empty(),
		"A joiner unplaced when the room was full gets in if someone left while it loaded")
	session.leave_session()
	_expect(admission.admitted.is_empty() and admission.unplaced.is_empty(), "Leaving forgets who was getting in")
	session.max_players = 8


## The same over ENet in this process: host, a joiner that goes silent and
## comes back from the same game, and a stranger, each on its own
## SceneMultiplayer. A room of two: one client, plus the transport's spare.
func _check_full_room_over_enet() -> void:
	var host := _enet_session("FullHost")
	host.max_players = 2
	host.settle_delay_seconds = 0.0
	var removed: Array = []
	var rejoins: Array = []
	host.peer_removed.connect(func(id: int) -> void: removed.append(id))
	host.peer_rejoined.connect(func(old_id: int, new_id: int) -> void: rejoins.append([old_id, new_id]))
	_expect(host.host_session(FULL_ROOM_PORT) == OK, "A room of two is hosted on ENet")
	var first := _enet_session("FullFirst")
	var first_id: int = await _enet_join(first, true)
	if first_id == 0 or not await _wait_for(func() -> bool: return host.peer_ids.has(first_id)):
		_expect(false, "The first joiner never made it in")
		_free_sessions([first, host])
		return
	# A pulled cable: its link stays open but nobody polls it any more.
	var silent: MultiplayerAPI = first.multiplayer
	set_multiplayer(null, first.get_path())

	var again := _enet_session("FullAgain")
	again._identities._token = first._identities.local_token()  # The same running game.
	var again_id: int = await _enet_join(again, false)
	_expect(again_id != 0, "Back while its ghost still holds the room's place, the transport lets it reach the host")
	if again_id != 0:
		_expect(host._admission.unplaced.has(again_id), "...unplaced: on LAN only its ready reply says who it is")
		again.level_ready()
		_expect(await _wait_for(func() -> bool: return host.peer_ids.has(again_id)),
			"It gets in once it says who it is")
		_expect(not host.peer_ids.has(first_id) and rejoins == [[first_id, again_id]],
			"...and its ghost leaves the roster (roster %s, rejoins %s)" % [host.peer_ids, rejoins])
		_expect(removed == [first_id], "The ghost is removed once, when dropped (got %s)" % [removed])
		_expect(await _wait_for(func() -> bool: return not host.multiplayer.get_peers().has(first_id)),
			"The ghost's connection closes soon after")
		_expect(removed == [first_id], "...and its close removes nothing more (got %s)" % [removed])

	var stranger := _enet_session("FullStranger")
	var failures: Array = []
	stranger.session_failed.connect(func(reason: String) -> void: failures.append(reason))
	var stranger_id: int = await _enet_join(stranger, false)
	_expect(stranger_id != 0 and host._admission.unplaced.has(stranger_id),
		"A stranger to the full room goes on unplaced too")
	if stranger_id != 0:
		stranger.level_ready()
		_expect(await _wait_for(func() -> bool: return failures.has("full")),
			"...and hears full once it says who it is (got %s)" % [failures])
		_expect(await _wait_for(func() -> bool: return not host._admission.unplaced.has(stranger_id)),
			"The host forgets it")
		_expect(host.peer_ids == [NetSession.HOST_ID, again_id], "The room is the host and the one who came back")
	silent.multiplayer_peer.close()
	first.free()  # Its multiplayer was taken off it already.
	_free_sessions([host, again, stranger])


func _enet_session(node_name: String) -> GameSession:
	var session := GameSession.new()
	session.name = node_name
	root.add_child(session)
	set_multiplayer(SceneMultiplayer.new(), session.get_path())
	session.transport = NetSession.Transport.ENET
	return session


## Joins the host on localhost and waits for its handshake; with `complete`,
## also says ready and waits to be in. Its peer id, or 0 if it never got there.
func _enet_join(session: GameSession, complete: bool) -> int:
	var handshakes: Array = []
	session.session_ready.connect(func(is_host: bool) -> void: handshakes.append(is_host))
	if session.join_session("127.0.0.1", FULL_ROOM_PORT) != OK:
		return 0
	if not await _wait_for(func() -> bool: return not handshakes.is_empty()):
		return 0
	var id: int = session.multiplayer.get_unique_id()
	if complete:
		session.level_ready()
		if not await _wait_for(func() -> bool: return session.multiplayer.get_peers().has(NetSession.HOST_ID)):
			return 0
	return id


func _free_sessions(sessions: Array) -> void:
	for session: GameSession in sessions:
		if session.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			session.leave_session()
		set_multiplayer(null, session.get_path())
		session.free()


func _wait_for(done: Callable, seconds: float = 6.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


## What the host does when a joiner's ready reply arrives, then its connection.
func _join(session: NetSession, id: int, token: String) -> void:
	session._identify_peer(id, {"ready": true, "version": 3, "identity": token})
	session._on_peer_connected(id)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
