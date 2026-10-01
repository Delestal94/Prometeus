extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_session/tests/test_net_session_rejoin.gd
##
## NetSession's rejoin by identity (net_session module, docs/modulos.md), in
## one process without sockets (the host's side, driven through the same
## functions the transport calls):
## - hosting makes a session nonce and leaving forgets it; a joiner's ready
##   reply carries the end of a hash chain rooted in its process token and that
##   nonce, and each rejoin the link before (hashed once, it is the last one);
##   another session, another chain; never the token itself;
## - the host keeps who each peer is (peer_identity()), still readable in the
##   game's _peer_left hook, and forgets it after;
## - someone who left and comes back under a new id: the game's _peer_returned
##   hook and peer_rejoined(old, new);
## - back before the host noticed the drop: the old connection is dropped as
##   a ghost (off the roster, _peer_left for it, once), and its late
##   disconnect does nothing more;
## - back under the same id: _peer_returned(id, id) but no peer_rejoined;
##   claiming nothing usable (not text, too long, empty): nothing at all;
## - a replayed claim (the last one taken, or an older link of that chain) is
##   turned away and the peer it copied stays; the real next link still works;
##   a ready reply from a joiner neither let in nor unplaced is turned away;
## - a failed authentication forgets the identity; however many come and go,
##   the memory of those who left stays bounded (NetPeerIdentities.MEMORY);
## - peer_removed comes once per leave, before roster_changed, for a ghost
##   when it is dropped and not again when its connection closes;
## - a full room (NetAdmission): a joiner who can't be told yet goes on
##   unplaced, gets in once it turns out to be a ghost's player (or someone
##   left meanwhile), and hears "full" otherwise -- before anything moves: no
##   peer_rejoined, no _peer_returned -- while the identity its claim continues
##   moves on to it, so that claim, overheard and sent again, is a replay and
##   its owner's next one still gets in;
## - the same over ENet in this process, in a room of two: a dropped ghost
##   leaves SceneMultiplayer at once, and a restart announced or begun in that
##   frame neither waits for it nor owes it a reload; the transport takes one
##   connection more than the room, so a joiner who went silent (nobody polls
##   its link: a pulled cable) and comes back from the same game reaches the
##   host while its ghost still holds the place, gets in, and the ghost goes;
##   someone replaying its claim hears "connection"; a stranger that ignores
##   "full" hears it and is cut off within the grace (REFUSED_GRACE_SECONDS),
##   however many ready replies it sends; a joiner turned away as it
##   authenticates that answers anyway never gets in; a joiner sending its
##   ready reply several times is read once (one replay check) and gets in once.

const FULL_ROOM_PORT: int = 7816

var _failures: int = 0
## A stand-in joiner per token: its chain of claims, {token: NetPeerIdentities}.
var _chains: Dictionary = {}
## The last claim each token made, {token: String}.
var _last_claim: Dictionary = {}


class GameSession extends NetSession:
	var left: Array = []
	var identities_when_left: Array = []
	var returned: Array = []
	var replies: Array = []
	## Host: what _admit_peer() answers ("" lets everyone in).
	var refuse_with: String = ""
	## Joiner: how many times it sends its ready reply.
	var replies_to_send: int = 1

	func _init() -> void:
		protocol_version = 3
		level_scenes = ["res://levels/one.tscn"]

	func _peer_left(id: int) -> void:
		left.append(id)
		identities_when_left.append(peer_identity(id))

	func _peer_returned(id: int, previous_id: int) -> void:
		returned.append([previous_id, id])

	func _ready_reply() -> Dictionary:
		var reply: Dictionary = super()
		replies.append(reply)
		return reply

	func _admit_peer(_id: int) -> String:
		return refuse_with

	func level_ready() -> void:
		if not _awaiting_handshake or replies_to_send <= 1:
			super()
			return
		_awaiting_handshake = false
		var reply: PackedByteArray = var_to_bytes(_ready_reply())
		for index: int in replies_to_send:
			multiplayer.send_auth(HOST_ID, reply)
		multiplayer.complete_auth(HOST_ID)


## A joiner that ignores being turned away: only the host can cut it off.
class StubbornSession extends GameSession:
	var refusals: Array = []

	func _fail(reason: String) -> void:
		refusals.append(reason)


## A joiner turned away as it authenticates that answers anyway, at once:
## its ready reply and its completion go out before the refusal arrives.
class RogueSession extends StubbornSession:
	func _peer_authenticating(id: int) -> void:
		super(id)
		if id == HOST_ID:
			multiplayer.send_auth(HOST_ID, var_to_bytes(_ready_reply()))
			multiplayer.complete_auth(HOST_ID)


## Counts the host's replay checks (a hash walk over every LAN identity).
class CountingIdentities extends NetPeerIdentities:
	var replay_checks: int = 0

	func is_replay(identity: String) -> bool:
		replay_checks += 1
		return super(identity)


## A joiner that sends someone else's claim.
class ThiefSession extends GameSession:
	var stolen: String = ""

	func _ready_reply() -> Dictionary:
		return {"ready": true, "version": protocol_version, "identity": stolen}


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
	_check_joiner_claims(session)

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
	var a_identity: String = "lan:" + String(_last_claim["tok-a"])
	_join(session, 37, "tok-b")
	var b_identity: String = "lan:" + String(_last_claim["tok-b"])
	_expect(session.peer_identity(22) == a_identity and session.peer_identity(37) == b_identity,
		"The host knows who each peer is")
	_expect(rejoins.is_empty() and session.returned.is_empty(), "Newcomers are nobody's return")

	var rosters_before: int = rosters.size()
	session._on_peer_disconnected(22)
	_expect(session.left == [22] and session.identities_when_left == [a_identity],
		"The game's _peer_left still sees who left (got %s)" % [session.identities_when_left])
	_expect(session.peer_identity(22).is_empty(), "...and the identity is forgotten after it")
	_expect(removed == [[22, rosters_before, a_identity]],
		"peer_removed comes once, before roster_changed, while who it was is known (got %s)" % [removed])

	_join(session, 58, "tok-a")
	_expect(rejoins == [[22, 58]] and session.returned == [[22, 58]],
		"Coming back under a new id: _peer_returned and peer_rejoined(old, new) (got %s)" % [rejoins])

	# Back before the host noticed the drop: 37's connection is a ghost of 69.
	rosters.clear()
	session.left.clear()
	session._identify_peer(69, _reply("tok-b"))
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
	session._identify_peer(69, _reply("tok-b"))
	_expect(session.returned[-1] == [69, 69] and rejoins.size() == 2,
		"Back under the same id: _peer_returned(id, id), no peer_rejoined (got %s)" % [session.returned])
	# No rejoin: nothing usable claimed.
	for bad: Variant in [42, "", "x".repeat(RpcGuard.MAX_TEXT_LENGTH + 1), ["tok-a"], null]:
		session._identify_peer(90, {"ready": true, "identity": bad})
		_expect(session.peer_identity(90).is_empty(), "A claimed identity like %s is ignored" % [bad])
	_expect(rejoins.size() == 2, "...and brings nobody back")
	_check_replays(session, rejoins)

	# A failed authentication.
	session._identify_peer(99, _reply("tok-z"))
	_expect(session.peer_identity(99) == "lan:" + String(_last_claim["tok-z"]),
		"The identity is kept while authenticating")
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
		print("PASS: rejoin by identity: hash-chained claims, replays turned away, returns, ghosts dropped once,"
			+ " bounded memory, full rooms")
	quit(_failures)


## The joiner's side of the handshake: a Lamport chain per session.
func _check_joiner_claims(session: GameSession) -> void:
	session._identities.nonce = "abc123"
	var token: String = session._identities.local_token()
	var first: String = String(session._ready_reply().identity)
	var root_value: String = (token + "abc123" + "0").sha256_text()
	var chain_end: String = NetPeerIdentities.chain_link(root_value, NetPeerIdentities.CHAIN_LENGTH)
	_expect(first == chain_end and not first.contains(token),
		"The first ready reply carries the end of a chain rooted in the token and the nonce, not the token")
	var second: Dictionary = session._ready_reply()
	_expect(String(second.identity) != first and String(second.identity).sha256_text() == first,
		"Each rejoin claims the link before: hashed once, it is the last one")
	_expect(session._ready_reply_error(second).is_empty(), "...and is still a valid ready reply")
	session._identities.nonce = "other"
	var elsewhere: String = String(session._ready_reply().identity)
	_expect(elsewhere != first and elsewhere.sha256_text() != first, "...and another session has another chain")
	session._identities.reset()
	_expect(session._identities._claims_made.has("abc123"),
		"A session ending doesn't forget how far down its chain it is")
	session._identities.nonce = ""


## Someone who overheard a claim sends it again: turned away, and the peer it
## copied stays.
func _check_replays(session: GameSession, rejoins: Array) -> void:
	var admission: NetAdmission = session._admission
	var last: String = String(_last_claim["tok-b"])
	var older: String = last.sha256_text()
	var roster: Array = session.peer_ids.duplicate()
	_expect(admission.on_identified(session, 94, {"ready": true, "identity": _claim("tok-x")}) == "connection",
		"A ready reply from a joiner neither let in nor unplaced is turned away")
	_expect(session.peer_identity(94).is_empty(), "...and its claim isn't taken")
	_expect(admission.on_authenticating(session, 95).is_empty(), "The replayer is let in as it authenticates")
	for stolen: String in [last, older]:
		_expect(admission.on_identified(session, 95, {"ready": true, "identity": stolen}) == "connection",
			"A replayed claim is turned away (%s)" % ("the last one" if stolen == last else "an older link"))
		_expect(session.peer_identity(95).is_empty() and session.peer_ids == roster and rejoins.size() == 2,
			"...and nothing moves: the peer it copied stays (roster %s)" % [session.peer_ids])
	session._auth_failed(95)
	session._identify_peer(95, {"ready": true, "identity": last})
	_expect(session.peer_identity(95).is_empty(), "_identify_peer() takes no replay either")
	_expect(session._identities.peer_of("lan:" + last) == 69, "The replayed claim is still its owner's")
	session._identify_peer(96, _reply("tok-b"))
	_expect(rejoins.size() == 3 and rejoins[2] == [69, 96], "The real next link still brings its player back")
	session._on_peer_connected(96)


## NetAdmission with no sockets, the way the transport drives it: a room of
## three (host, 22 and 37) where 22's connection is a ghost.
func _check_full_room(session: GameSession) -> void:
	session.max_players = 3
	var admission: NetAdmission = session._admission
	# 44 was here and left: it is remembered.
	_join(session, 44, "tok-c")
	session._on_peer_disconnected(44)
	_expect(admission.on_authenticating(session, 22).is_empty(), "A joiner with room is let in")
	_expect(admission.admitted.has(22), "...and counts while it authenticates")
	_expect(admission.on_authenticating(session, 37).is_empty() and admission.admitted.size() == 2,
		"So does the next one, up to max_players")
	_expect(admission.on_identified(session, 22, _reply("tok-a")).is_empty(), "Its ready reply lets it in")
	session._on_peer_connected(22)
	_expect(admission.on_identified(session, 37, _reply("tok-b")).is_empty(), "...and 37")
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
	_expect(admission.on_identified(session, 58, _reply("tok-a")).is_empty(),
		"The one who turns out to be a ghost's player gets in")
	_expect(not session.peer_ids.has(22) and rejoins == [[22, 58]], "...and the ghost goes (got %s, %s)"
		% [session.peer_ids, rejoins])
	session._on_peer_connected(58)
	_expect(admission.on_identified(session, 77, _reply("tok-z")) == "full",
		"The stranger hears full once it says who it is")
	session._auth_failed(77)
	_expect(admission.unplaced.is_empty() and admission.admitted.is_empty(), "...and is forgotten")

	# 44 comes back with no ghost to make room: "full" before anything moves.
	var returned_before: int = session.returned.size()
	_expect(admission.on_authenticating(session, 45).is_empty() and admission.unplaced.has(45), "Full again")
	_expect(admission.on_identified(session, 45, _reply("tok-c")) == "full",
		"Someone who left, back to a full room with no ghost of its own, hears full")
	_expect(rejoins.size() == 1 and session.returned.size() == returned_before,
		"...before anything moves: no peer_rejoined, no _peer_returned (rejoins %s)" % [rejoins])
	var turned_away: String = "lan:" + String(_last_claim["tok-c"])
	_expect(session.peer_identity(45).is_empty() and session._identities.peer_of(turned_away) == 44,
		"...its claim isn't 45's: it is still 44's")
	_expect(session._identities.is_replay(turned_away),
		"...but 44's identity moved on to it: it has been on the wire, so nobody can use it first")
	session._auth_failed(45)
	_expect(admission.on_authenticating(session, 47).is_empty() and admission.unplaced.has(47), "Full")
	_expect(admission.on_identified(session, 47, {"ready": true, "identity": String(_last_claim["tok-c"])})
		== "connection", "Whoever overheard the turned-away claim and sends it from elsewhere hears connection")
	session._auth_failed(47)

	# Someone leaves while an unplaced joiner loads: there's a place after all.
	_expect(admission.on_authenticating(session, 46).is_empty() and admission.unplaced.has(46), "Full again")
	session._on_peer_disconnected(37)
	_expect(admission.on_identified(session, 46, _reply("tok-c")).is_empty(),
		"A joiner unplaced when the room was full gets in if someone left while it loaded")
	_expect(rejoins.size() == 2 and rejoins[1] == [44, 46],
		"...and its owner's next link is still 44's (rejoins %s)" % [rejoins])
	session.leave_session()
	_expect(admission.admitted.is_empty() and admission.unplaced.is_empty(), "Leaving forgets who was getting in")
	session.max_players = 8


## The same over ENet in this process: host, a joiner that goes silent and
## comes back from the same game, someone replaying its claim and a stranger,
## each on its own SceneMultiplayer. A room of two: one client, plus the
## transport's spare.
func _check_full_room_over_enet() -> void:
	var host := _enet_session("FullHost", GameSession.new())
	host.max_players = 2
	host.settle_delay_seconds = 0.0
	var removed: Array = []
	var rejoins: Array = []
	host.peer_removed.connect(func(id: int) -> void: removed.append(id))
	host.peer_rejoined.connect(func(old_id: int, new_id: int) -> void: rejoins.append([old_id, new_id]))
	_expect(host.host_session(FULL_ROOM_PORT) == OK, "A room of two is hosted on ENet")
	await _check_dropped_mid_restart(host)
	await _check_one_reply_each(host)
	await _check_rogue(host)
	removed.clear()

	var first := _enet_session("FullFirst", GameSession.new())
	var first_id: int = await _enet_join(first, true)
	if first_id == 0 or not await _wait_for(func() -> bool: return host.peer_ids.has(first_id)):
		_expect(false, "The first joiner never made it in")
		_free_sessions([first, host])
		return
	# A pulled cable: its link stays open but nobody polls it any more.
	var silent: MultiplayerAPI = first.multiplayer
	set_multiplayer(null, first.get_path())

	# The same running game: same token, and as far down its chain.
	var again := _enet_session("FullAgain", GameSession.new())
	again._identities._token = first._identities.local_token()
	again._identities._claims_made = first._identities._claims_made.duplicate()
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
		await process_frame
		_expect(not host.multiplayer.get_peers().has(first_id), "SceneMultiplayer lets go of the ghost at once")
		await _pump(0.5)
		_expect(removed == [first_id], "...and its link closing removes nothing more (got %s)" % [removed])
		await _check_thief(host, again)

	var stranger := _enet_session("FullStranger", StubbornSession.new()) as StubbornSession
	stranger.replies_to_send = 3
	var stranger_id: int = await _enet_join(stranger, false)
	_expect(stranger_id != 0 and host._admission.unplaced.has(stranger_id),
		"A stranger to the full room goes on unplaced too")
	if stranger_id != 0:
		var refused_at: int = Time.get_ticks_msec()
		stranger.level_ready()
		var cut_off: bool = await _wait_for(func() -> bool:
			var status: int = stranger.multiplayer.multiplayer_peer.get_connection_status()
			return status == MultiplayerPeer.CONNECTION_DISCONNECTED)
		var took: int = Time.get_ticks_msec() - refused_at
		var grace_msec: int = int(NetAdmission.REFUSED_GRACE_SECONDS * 1000.0) + 500
		_expect(stranger.refusals.has("full"), "...hears full once it says who it is (got %s)" % [stranger.refusals])
		_expect(cut_off and took < grace_msec,
			"...and, ignoring it, is let go of within the grace (%d ms, at most %d)" % [took, grace_msec])
		_expect(not host.peer_ids.has(stranger_id) and not stranger.multiplayer.get_peers().has(NetSession.HOST_ID),
			"Its two extra ready replies didn't get it in")
		_expect(await _wait_for(func() -> bool:
			return not host._admission.unplaced.has(stranger_id) and not host._admission.refused.has(stranger_id)),
			"The host forgets it once its link is gone")
		_expect(host.peer_ids == [NetSession.HOST_ID, again_id], "The room is the host and the one who came back")
	silent.multiplayer_peer.close()
	first.free()  # Its multiplayer was taken off it already.
	_free_sessions([host, again, stranger])


## A ghost dropped (drop_peer()) and, in the same frame, a restart announced
## and begun: neither waits out a load from the ghost nor owes it a reload --
## it is still on SceneMultiplayer's list until the end of that frame.
func _check_dropped_mid_restart(host: GameSession) -> void:
	var dropped := _enet_session("FullDropped", GameSession.new())
	var dropped_id: int = await _enet_join(dropped, true)
	if dropped_id == 0 or not await _wait_for(func() -> bool: return host.peer_ids.has(dropped_id)):
		_expect(false, "The joiner to drop never made it in")
		_free_sessions([dropped])
		return
	host.drop_peer(dropped_id)
	_expect(host.multiplayer.get_peers().has(dropped_id), "Right after the drop its link is still listed")
	host.announce_restart()
	_expect(host.enet_timeout_msec(dropped_id) == 0,
		"An announced restart doesn't put a dropped ghost back on the load budget (%d ms)"
		% host.enet_timeout_msec(dropped_id))
	host.begin_restart()
	host.level_ready()
	_expect(not host._reloads_owed.has(dropped_id) and not host._enet_timeouts.has(dropped_id),
		"...and the restart owes it no reload (owed %s)" % [host._reloads_owed])
	await process_frame
	_expect(not host.multiplayer.get_peers().has(dropped_id), "A dropped ghost leaves SceneMultiplayer within a frame")
	_expect(await _wait_for(func() -> bool: return not dropped.is_online()), "...and its link is cut")
	_expect(not host._reloads_owed.has(dropped_id) and host.enet_timeout_msec(dropped_id) == 0,
		"Nothing is left behind for it")
	_free_sessions([dropped])
	await _pump(0.3)


## A joiner sends its ready reply four times: read once -- one replay check,
## the hash walk -- and in once.
func _check_one_reply_each(host: GameSession) -> void:
	var counting := CountingIdentities.new()
	counting.nonce = host._identities.nonce
	counting.by_peer = host._identities.by_peer
	counting.peer_by_identity = host._identities.peer_by_identity
	host._identities = counting
	host._admission = NetAdmission.new(counting)
	var chatty := _enet_session("FullChatty", GameSession.new())
	chatty.replies_to_send = 4
	var chatty_id: int = await _enet_join(chatty, true)
	_expect(chatty_id != 0 and await _wait_for(func() -> bool: return host.peer_ids.has(chatty_id)),
		"A joiner that sends its ready reply four times gets in")
	await _pump(0.3)
	_expect(counting.replay_checks == 1, "...its ready reply is read once (%d replay checks)" % counting.replay_checks)
	_expect(host.peer_ids.count(chatty_id) == 1, "...and it is on the roster once (%s)" % [host.peer_ids])
	chatty.leave_session()
	_expect(await _wait_for(func() -> bool: return not host.peer_ids.has(chatty_id)), "It leaves")
	_free_sessions([chatty])
	await _pump(0.3)


## A joiner turned away as it authenticates (the game's _admit_peer says no)
## that sends a ready reply and completes anyway never gets in: not over
## max_players, not without a colour.
func _check_rogue(host: GameSession) -> void:
	host.refuse_with = "closed"
	var rogue := _enet_session("FullRogue", RogueSession.new()) as RogueSession
	_expect(rogue.join_session("127.0.0.1", FULL_ROOM_PORT) == OK, "A joiner to turn away connects")
	var rogue_id: int = rogue.multiplayer.get_unique_id()
	_expect(await _wait_for(func() -> bool: return rogue.refusals.has("closed")),
		"...and hears why it can't come in (got %s)" % [rogue.refusals])
	await _pump(0.5)
	_expect(not host.peer_ids.has(rogue_id) and not host.multiplayer.get_peers().has(rogue_id),
		"Its ready reply gets it nowhere: the host never lets it in (roster %s)" % [host.peer_ids])
	_expect(not rogue.multiplayer.get_peers().has(NetSession.HOST_ID), "...nor does it ever see the host in")
	_expect(await _wait_for(func() -> bool:
		return rogue.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED),
		"...and it is cut off")
	host.refuse_with = ""
	_free_sessions([rogue])
	await _pump(0.3)


## Someone overheard the claim `victim` came back with and sends it: turned
## away with "connection", and the victim stays.
func _check_thief(host: GameSession, victim: GameSession) -> void:
	var thief := _enet_session("FullThief", ThiefSession.new()) as ThiefSession
	thief.stolen = String((victim.replies[-1] as Dictionary).identity)
	var failures: Array = []
	thief.session_failed.connect(func(reason: String) -> void: failures.append(reason))
	var thief_id: int = await _enet_join(thief, false)
	_expect(thief_id != 0, "Someone replaying a claim reaches the host")
	if thief_id != 0:
		thief.level_ready()
		_expect(await _wait_for(func() -> bool: return failures.has("connection")),
			"...and is turned away (got %s)" % [failures])
		_expect(host.peer_ids.has(victim.multiplayer.get_unique_id()) and host.peer_ids.size() == 2,
			"The one it copied stays (roster %s)" % [host.peer_ids])
		_expect(await _wait_for(func() -> bool: return not host._admission.refused.has(thief_id)),
			"The host forgets it")
	_free_sessions([thief])
	await _pump(0.5)


func _enet_session(node_name: String, session: GameSession) -> GameSession:
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


func _pump(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


## The next claim of the stand-in joiner `token` (the host's nonce is empty
## here, outside a session).
func _claim(token: String) -> String:
	if not _chains.has(token):
		var chain := NetPeerIdentities.new()
		chain._token = token
		_chains[token] = chain
	var claimed: String = (_chains[token] as NetPeerIdentities).claim()
	_last_claim[token] = claimed
	return claimed


func _reply(token: String) -> Dictionary:
	return {"ready": true, "version": 3, "identity": _claim(token)}


## What the host does when a joiner's ready reply arrives, then its connection.
func _join(session: NetSession, id: int, token: String) -> void:
	session._identify_peer(id, _reply(token))
	session._on_peer_connected(id)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
