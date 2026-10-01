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
## On Steam who a joiner is is known as it authenticates; on LAN only from its
## ready reply, so it loads the level unplaced and is decided then. The
## transport takes one connection more than the room for it
## (NetSession._host_enet()). Whoever is turned away is let go of as soon as
## it has the refusal, and cut off soon after if not (refuse()), so it doesn't
## hold that spare connection. Each joiner's ready reply is read once
## (first_reply()), and only from one let in or unplaced: a turned-away joiner
## that answers anyway gets nowhere, and a flood of replies costs no hashing.

## The latest a joiner turned away is cut off (refuse()). On ENet its link goes
## as soon as the refusal is acknowledged; this is for one whose
## acknowledgement never comes, and for Steam. Cutting it sooner could drop a
## refusal sent again after a lost packet (enet_peer_reset_queues), and it
## would see "timeout" instead of why.
const REFUSED_GRACE_SECONDS: float = 3.0

## Joiners let in that are still authenticating, {peer_id: true}.
var admitted: Dictionary = {}
## Joiners still authenticating that found the room full, {peer_id: true}.
var unplaced: Dictionary = {}
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


## `id` connected, or never made it in.
func forget(id: int) -> void:
	admitted.erase(id)
	unplaced.erase(id)
	refused.erase(id)
	answered.erase(id)


## Whether to read `id`'s ready reply: the first one from a joiner not turned
## away. Marks it read.
func first_reply(id: int) -> bool:
	if refused.has(id) or answered.has(id):
		return false
	answered[id] = true
	return true


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


## From `id`'s ready reply, before the host completes its authentication. ""
## lets it in, else the failure code it hears. Only a joiner let in or
## unplaced as it authenticated may answer: any other was turned away (or was
## never seen). A LAN claim the host already took is someone repeating what it
## overheard: turned away, and the one it copied stays. One that found the room
## full gets in if its ghost was here (its claim drops it) or someone left while
## it loaded; else it hears "full" before anything moves -- no merit follows
## it, no slot is handed to it -- and the identity it continues moves on to that
## claim anyway (NetPeerIdentities.advance()): nobody who overheard it can use
## it first.
func on_identified(session: NetSession, id: int, reply: Dictionary) -> String:
	var was_unplaced: bool = unplaced.erase(id)
	if not was_unplaced and not admitted.has(id):
		return "connection"
	var identity: String = NetPeerIdentities.identity_of(session.multiplayer.multiplayer_peer, id, reply)
	if _identities.is_replay(identity):
		return "connection"
	if was_unplaced and not _is_ghost(session, _identities.peer_of(identity), id):
		var refusal: String = admit(session, id)
		if not refusal.is_empty():
			_identities.advance(identity)
			return refusal
		was_unplaced = false
	_take(session, id, identity)
	return admit(session, id) if was_unplaced else ""


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
		return
	_drop_ghost(session, previous, id)
	session._peer_returned(id, previous)
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
