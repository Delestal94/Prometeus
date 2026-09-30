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
##   the memory of those who left stays bounded (NetPeerIdentities.MEMORY).

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
	session.peer_rejoined.connect(func(old_id: int, new_id: int) -> void: rejoins.append([old_id, new_id]))
	session.roster_changed.connect(func(ids: Array) -> void: rosters.append(ids.duplicate()))
	_join(session, 22, "tok-a")
	_join(session, 37, "tok-b")
	_expect(session.peer_identity(22) == "lan:tok-a" and session.peer_identity(37) == "lan:tok-b",
		"The host knows who each peer is")
	_expect(rejoins.is_empty() and session.returned.is_empty(), "Newcomers are nobody's return")

	session._on_peer_disconnected(22)
	_expect(session.left == [22] and session.identities_when_left == ["lan:tok-a"],
		"The game's _peer_left still sees who left (got %s)" % [session.identities_when_left])
	_expect(session.peer_identity(22).is_empty(), "...and the identity is forgotten after it")

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
	session._on_peer_connected(69)
	session._on_peer_disconnected(37)
	_expect(session.left == [37] and rosters.size() == 2, "The ghost's late disconnect does nothing more")

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
	_expect(session._identities.peer_by_identity.size() <= here + NetPeerIdentities.MEMORY,
		"200 comings and goings leave %d identities remembered (crew %d)" % [session._identities.peer_by_identity.size(), here])

	session.leave_session()
	_expect(session._identities.peer_by_identity.is_empty() and session._identities.by_peer.is_empty(), "Leaving forgets everyone")
	session.free()
	if _failures == 0:
		print("PASS: rejoin by identity: hashed tokens, returns, ghosts dropped once, bounded memory")
	quit(_failures)


## What the host does when a joiner's ready reply arrives, then its connection.
func _join(session: NetSession, id: int, token: String) -> void:
	session._identify_peer(id, {"ready": true, "version": 3, "identity": token})
	session._on_peer_connected(id)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
