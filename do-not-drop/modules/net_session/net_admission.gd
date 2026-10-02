class_name NetAdmission
extends RefCounted
## Who gets into a NetSession's room, on the host: a place among max_players
## (counting joiners still authenticating) that the game grants too
## (NetSession._admit_peer(): a seat, a colour), and someone back under a new
## peer id (NetPeerIdentities) getting its place again. Portable module
## (docs/modulos.md); NetSession owns one and calls it from its handshake.
##
## A full room isn't the last word. Someone who comes back before the host
## noticed its drop -- the usual case, with timeouts that outlast a level load
## -- finds its old connection still there as a ghost, holding its place: the
## ghost goes (NetSession.drop_peer(), close_dropped()) and it gets the place.
## On Steam who a joiner is is known as it authenticates. On LAN a joiner to a
## full room is asked first (unplaced): the host sends it only the session's
## nonce, it answers with its identity claim (on_identity()), and only once it
## has a place -- its ghost's, or one freed meanwhile -- does it get the
## session's state and load the level; otherwise it hears "full" having loaded
## nothing. The transport takes one connection more than the room for it
## (NetSession._host_enet()). Whoever is turned away is let go of as soon as
## it has the refusal, and cut off soon after if not (refuse()), so it doesn't
## hold that spare connection. Each joiner's ready reply is read once
## (first_reply()), and only from one let in: a turned-away joiner that answers
## anyway gets nowhere, and a flood of replies costs no hashing. An unplaced
## joiner's identity reply is read once too: it stops being unplaced with it.

## The latest a joiner turned away is cut off (refuse()). On ENet its link goes
## as soon as the refusal is acknowledged; this is for one whose
## acknowledgement never comes, and for Steam. Cutting it sooner could drop a
## refusal sent again after a lost packet (enet_peer_reset_queues), and it
## would see "timeout" instead of why.
const REFUSED_GRACE_SECONDS: float = 3.0

## Joiners let in that are still authenticating, {peer_id: true}.
var admitted: Dictionary = {}
## Joiners still authenticating that found the room full and were asked who
## they are (LAN), {peer_id: true}: no place, no state yet.
var unplaced: Dictionary = {}
## How long an unplaced joiner has to say who it is before it hears
## "connection" (refuse()): one that never answers would hold the transport's
## spare connection until its authentication timed out (45 s). Answering takes
## no level load, so a few seconds are plenty. A var so tests can shorten it.
var identify_timeout_seconds: float = 5.0
## Joiners let in from their identity reply (on_identity()), {peer_id: true}:
## who they are is settled, so their ready reply's claim isn't read.
var identified: Dictionary = {}
## Joiners turned away that haven't left yet, {peer_id: true}.
var refused: Dictionary = {}
## Joiners whose ready reply was read, {peer_id: true}: one per joiner.
var answered: Dictionary = {}
var _identities: NetPeerIdentities


func _init(identities: NetPeerIdentities) -> void:
	_identities = identities


func reset() -> void:
	admitted.clear()
	unplaced.clear()
	refused.clear()
	answered.clear()
	identified.clear()


## `id` connected, or never made it in.
func forget(id: int) -> void:
	admitted.erase(id)
	unplaced.erase(id)
	refused.erase(id)
	answered.erase(id)
	identified.erase(id)


## Whether to read `id`'s ready reply: the first one from a joiner not turned
## away. Marks it read.
func first_reply(id: int) -> bool:
	if refused.has(id) or answered.has(id):
		return false
	answered[id] = true
	return true


## Host, from SceneMultiplayer's auth callback (inside its poll): `id`'s answer.
## An unplaced joiner's is its identity reply (receive_identity()), read once;
## anyone else's its ready reply, read once too (first_reply()). Let in, its
## authentication completes; else it hears why (refuse()).
func receive(session: NetSession, id: int, data: PackedByteArray) -> void:
	if unplaced.has(id) and not refused.has(id):
		receive_identity(session, id, data)
		return
	if not first_reply(id):
		return
	# Protocol 0 sent the raw word "ready". Recognize it without asking
	# bytes_to_var() to parse arbitrary UTF-8, then reject it explicitly.
	var reply: Variant = bytes_to_var(data) if data.get_string_from_utf8() != "ready" else null
	var refusal: String = ready_reply_error(reply, session.protocol_version)
	if refusal.is_empty():
		refusal = on_identified(session, id, reply)
	if refusal.is_empty():
		session.multiplayer.complete_auth(id)
	else:
		refuse(session, id, refusal)


## "" when `reply` is a ready reply of `version`, else the failure code.
static func ready_reply_error(reply: Variant, version: int) -> String:
	if not reply is Dictionary or not bool(reply.get("ready", false)):
		return "version"
	return "" if int(reply.get("version", -1)) == version else "version"


## Host: the session's state (NetSession._session_state() and the level), for
## a joiner with a place: it loads the level with it and says ready.
func send_state(session: NetSession, id: int) -> void:
	var state: Dictionary = {"version": session.protocol_version, "scene": session._current_level_scene(),
		"session": _identities.nonce}
	state.merge(session._session_state())
	session.multiplayer.send_auth(id, var_to_bytes(state))


## Host: asks the unplaced `id` who it is, sending only the session's nonce
## (for its claim) and the version; the state follows once it has a place.
func ask_identity(session: NetSession, id: int) -> void:
	session.multiplayer.send_auth(id, var_to_bytes({"version": session.protocol_version,
		"session": _identities.nonce, "identify": true}))
	if session.is_inside_tree():
		session.get_tree().create_timer(identify_timeout_seconds).timeout.connect(
			_identify_overdue.bind(weakref(session), id, session.multiplayer.multiplayer_peer))


## Still unplaced after identify_timeout_seconds: it never said who it is.
func _identify_overdue(session_ref: WeakRef, id: int, peer: MultiplayerPeer) -> void:
	var session: NetSession = session_ref.get_ref() as NetSession
	if session == null or not session.is_inside_tree() or session.multiplayer.multiplayer_peer != peer:
		return
	if unplaced.has(id) and not refused.has(id):
		unplaced.erase(id)
		refuse(session, id, "connection")


## Host: an unplaced joiner said who it is. With a place now (its ghost's, or
## one freed since) it gets the state; else it hears why, having loaded nothing.
func receive_identity(session: NetSession, id: int, data: PackedByteArray) -> void:
	var reply: Variant = bytes_to_var(data) if data.get_string_from_utf8() != "ready" else null
	var refusal: String = identity_reply_error(reply, session.protocol_version)
	if refusal.is_empty():
		refusal = on_identity(session, id, reply)
	if refusal.is_empty():
		send_state(session, id)
	else:
		refuse(session, id, refusal)


## "" when `reply` is an identity reply of `version`, else the failure code.
static func identity_reply_error(reply: Variant, version: int) -> String:
	if not reply is Dictionary or int(reply.get("version", -1)) != version:
		return "version"
	return "" if is_identify(reply) else "connection"


## Whether what the host sent (or a joiner answered) is about who it is.
static func is_identify(message: Variant) -> bool:
	var identify: Variant = message.get("identify", false) if message is Dictionary else false
	return identify is bool and identify


## Joiner: the host asks who this is before anything else (its room is full),
## and gets the next link of its chain. A host on another version gets
## nothing: it is the wrong game.
func answer_identify(session: NetSession, request: Dictionary) -> void:
	if int(request.get("version", -1)) != session.protocol_version:
		session._fail_if_current.call_deferred("version", session.multiplayer.multiplayer_peer)
		return
	var nonce: Variant = request.get("session", "")
	_identities.nonce = String(nonce) if nonce is String and RpcGuard.text_ok(nonce) else ""
	session._identified_early = true
	session.multiplayer.send_auth(NetSession.HOST_ID, var_to_bytes({"identify": true,
		"version": session.protocol_version, "identity": session._claim_identity()}))


## As `id` starts authenticating: "" lets the handshake go on, else the
## failure code it hears.
func on_authenticating(session: NetSession, id: int) -> String:
	var refusal: String = admit(session, id)
	if refusal != "full":
		return refusal
	var identity: String = NetPeerIdentities.identity_of(session.multiplayer.multiplayer_peer, id, {})
	if identity.is_empty():
		unplaced[id] = true
		return ""
	if not _drop_ghost(session, _identities.peer_of(identity), id):
		return refusal
	return admit(session, id)


## From an unplaced joiner's identity reply (NetSession asked it, the room
## being full): "" gives it a place -- the host then sends it the state -- else
## the failure code it hears, before it loaded anything. A LAN claim the host
## already took is someone repeating what it overheard: turned away, and the
## one it copied stays. It gets in if its ghost was here (its claim drops it)
## or someone left since it knocked; else it hears "full" before anything moves
## -- no merit follows it, no slot is handed to it -- and the identity it
## continues moves on to that claim anyway (NetPeerIdentities.advance()):
## nobody who overheard it can use it first.
func on_identity(session: NetSession, id: int, reply: Dictionary) -> String:
	if not unplaced.erase(id):
		return "connection"
	var identity: String = NetPeerIdentities.identity_of(session.multiplayer.multiplayer_peer, id, reply)
	if _identities.is_replay(identity):
		return "connection"
	var ghost: bool = _is_ghost(session, _identities.peer_of(identity), id)
	if not ghost:
		var refusal: String = admit(session, id)
		if not refusal.is_empty():
			_identities.advance(identity)
			return refusal
	_take(session, id, identity)
	var refusal_after: String = admit(session, id) if ghost else ""
	if refusal_after.is_empty():
		identified[id] = true
	return refusal_after


## From `id`'s ready reply, before the host completes its authentication. ""
## lets it in, else the failure code it hears. Only a joiner let in may answer:
## any other was turned away, is still unplaced (it owes an identity reply,
## not this) or was never seen. One let in from its identity reply is who it
## said then; anyone else is identified now (a replayed LAN claim is turned
## away, and the one it copied stays).
func on_identified(session: NetSession, id: int, reply: Dictionary) -> String:
	if not admitted.has(id):
		return "connection"
	if identified.has(id):
		return ""
	var identity: String = NetPeerIdentities.identity_of(session.multiplayer.multiplayer_peer, id, reply)
	if _identities.is_replay(identity):
		return "connection"
	_take(session, id, identity)
	return ""


## Who `id` is (its Steam id, or the claim in its ready reply). Someone who was
## here before gets its place back through the game (_peer_returned) and
## peer_rejoined; if its old connection is still up, that one is a ghost and
## goes. False for a replayed LAN claim, which changes nothing.
func identify(session: NetSession, id: int, reply: Dictionary) -> bool:
	var identity: String = NetPeerIdentities.identity_of(session.multiplayer.multiplayer_peer, id, reply)
	if _identities.is_replay(identity):
		return false
	_take(session, id, identity)
	return true


## identify() for a claim already checked.
func _take(session: NetSession, id: int, identity: String) -> void:
	if identity.is_empty():
		return
	var previous: int = _identities.record(id, identity)
	if previous == 0:
		return
	if previous == id:
		# Back under the same id (Steam can hand it out again): nothing moves,
		# but the game gives back what it kept.
		session._peer_returned(id, id)
		session.peer_returned.emit(id, id)
		return
	_drop_ghost(session, previous, id)
	session._peer_returned(id, previous)
	session.peer_returned.emit(id, previous)
	session.peer_rejoined.emit(previous, id)


## A place among max_players, counting the joiners still authenticating, that
## the game grants too (_admit_peer()). "" when `id` is in.
func admit(session: NetSession, id: int) -> String:
	var taken: int = 0
	for peer: int in session.peer_ids:
		taken += int(peer != id)
	for peer: int in admitted:
		taken += int(peer != id and not session.peer_ids.has(peer))
	var refusal: String = "full" if taken >= session.max_players else session._admit_peer(id)
	if refusal.is_empty():
		admitted[id] = true
	return refusal


## Tells `id`, still authenticating, why it can't come in. On ENet its link
## is let go of once that is acknowledged (peer_disconnect_later(); the
## transport's disconnect then fails its authentication as usual); anywhere, it
## is cut off REFUSED_GRACE_SECONDS later if still there. A joiner that ignores
## the refusal would otherwise hold a connection until its authentication timed
## out (NetSession.JOIN_HANDSHAKE_TIMEOUT).
func refuse(session: NetSession, id: int, failure: String) -> void:
	session.multiplayer.send_auth(id, var_to_bytes({"failure": failure}))
	refused[id] = true
	var link: ENetPacketPeer = _enet_link(session, id)
	if link != null:
		link.peer_disconnect_later()
	if session.is_inside_tree():
		session.get_tree().create_timer(REFUSED_GRACE_SECONDS).timeout.connect(
			_cut_off.bind(weakref(session), id, session.multiplayer.multiplayer_peer))


## SceneMultiplayer.disconnect_peer() forgets a peer with its signals blocked:
## what peer_authentication_failed would have undone is undone here.
func _cut_off(session_ref: WeakRef, id: int, peer: MultiplayerPeer) -> void:
	var session: NetSession = session_ref.get_ref() as NetSession
	if session == null or not refused.has(id) or not session.is_inside_tree() \
			or session.multiplayer.multiplayer_peer != peer:
		return
	session._auth_failed(id)
	_disconnect(session, id)


## Deferred from NetSession.drop_peer(), which can run inside SceneMultiplayer's
## poll: the dropped connection is cut. A dead peer answers nothing, so its
## transport timeout is cut short first. SceneMultiplayer forgets it at once
## -- nothing more is sent to a link that is closing ("max channels: 0"), and
## the other clients hear it left -- without peer_disconnected: the roster let
## it go already.
func close_dropped(session_ref: WeakRef, id: int) -> void:
	var session: NetSession = session_ref.get_ref() as NetSession
	if session == null or not session.is_online() or not session.multiplayer.get_peers().has(id):
		return
	var packet_peer: ENetPacketPeer = _enet_link(session, id)
	if packet_peer != null:
		packet_peer.set_timeout(NetSession.DROPPED_PEER_TIMEOUT_LIMIT, NetSession.DROPPED_PEER_TIMEOUT_MIN_MSEC,
			NetSession.DROPPED_PEER_TIMEOUT_MAX_MSEC)
	_disconnect(session, id)


## `id`'s ENet link, or null (another transport).
func _enet_link(session: NetSession, id: int) -> ENetPacketPeer:
	var enet: ENetMultiplayerPeer = session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	return enet.get_peer(id) if enet != null else null


func _disconnect(session: NetSession, id: int) -> void:
	var api: SceneMultiplayer = session.multiplayer as SceneMultiplayer
	if api != null:
		api.disconnect_peer(id)
	else:
		session.multiplayer.multiplayer_peer.disconnect_peer(id)


## `previous` is on the roster but `id` is who it was: a ghost, which goes.
func _drop_ghost(session: NetSession, previous: int, id: int) -> bool:
	if not _is_ghost(session, previous, id):
		return false
	session.drop_peer(previous)
	return true


func _is_ghost(session: NetSession, previous: int, id: int) -> bool:
	return previous != 0 and previous != id and previous != NetSession.HOST_ID and session.peer_ids.has(previous)
