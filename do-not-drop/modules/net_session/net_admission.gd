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
## (NetSession._host_enet()). Whoever is turned away is cut off shortly after
## (refuse()), so it doesn't hold that spare connection.

## Long enough for a refusal to be acknowledged, or sent again: cutting an ENet
## link drops whatever it still had unacknowledged (enet_peer_reset_queues).
const REFUSED_LINGER_SECONDS: float = 0.5

## Joiners let in that are still authenticating, {peer_id: true}.
var admitted: Dictionary = {}
## Joiners still authenticating that found the room full, {peer_id: true}.
var unplaced: Dictionary = {}
## Joiners turned away that haven't left yet, {peer_id: true}.
var refused: Dictionary = {}
var _identities: NetPeerIdentities


func _init(identities: NetPeerIdentities) -> void:
	_identities = identities


func reset() -> void:
	admitted.clear()
	unplaced.clear()
	refused.clear()


## `id` connected, or never made it in.
func forget(id: int) -> void:
	admitted.erase(id)
	unplaced.erase(id)
	refused.erase(id)


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
## lets it in, else the failure code it hears. A LAN claim the host already
## took is someone repeating what it overheard: turned away, and the one it
## copied stays. One that found the room full gets in if its ghost was here
## (identify() drops it) or someone left while it loaded; else it hears "full"
## before anything moves -- no merit follows it, no slot is handed to it.
func on_identified(session: NetSession, id: int, reply: Dictionary) -> String:
	var identity: String = NetPeerIdentities.identity_of(session.multiplayer.multiplayer_peer, id, reply)
	var was_unplaced: bool = unplaced.erase(id)
	if _identities.is_replay(identity):
		return "connection"
	if was_unplaced and not _is_ghost(session, _identities.peer_of(identity), id):
		var refusal: String = admit(session, id)
		if not refusal.is_empty():
			return refusal
		was_unplaced = false
	identify(session, id, reply)
	return admit(session, id) if was_unplaced else ""


## Who `id` is (its Steam id, or the claim in its ready reply). Someone who was
## here before gets its place back through the game (_peer_returned) and
## peer_rejoined; if its old connection is still up, that one is a ghost and
## goes. False for a replayed LAN claim, which changes nothing.
func identify(session: NetSession, id: int, reply: Dictionary) -> bool:
	var identity: String = NetPeerIdentities.identity_of(session.multiplayer.multiplayer_peer, id, reply)
	if identity.is_empty():
		return true
	if _identities.is_replay(identity):
		return false
	var previous: int = _identities.record(id, identity)
	if previous == 0:
		return true
	if previous == id:
		# Back under the same id (Steam can hand it out again): nothing moves,
		# but the game gives back what it kept.
		session._peer_returned(id, id)
		return true
	_drop_ghost(session, previous, id)
	session._peer_returned(id, previous)
	session.peer_rejoined.emit(previous, id)
	return true


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


## Tells `id`, still authenticating, why it can't come in, and cuts it off
## REFUSED_LINGER_SECONDS later if it hasn't left by then: a joiner that
## ignores the refusal would hold a connection until its authentication timed
## out (NetSession.JOIN_HANDSHAKE_TIMEOUT).
func refuse(session: NetSession, id: int, failure: String) -> void:
	session.multiplayer.send_auth(id, var_to_bytes({"failure": failure}))
	refused[id] = true
	if session.is_inside_tree():
		session.get_tree().create_timer(REFUSED_LINGER_SECONDS).timeout.connect(
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
	var enet: ENetMultiplayerPeer = session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var packet_peer: ENetPacketPeer = enet.get_peer(id) if enet != null else null
	if packet_peer != null:
		packet_peer.set_timeout(NetSession.DROPPED_PEER_TIMEOUT_LIMIT, NetSession.DROPPED_PEER_TIMEOUT_MIN_MSEC,
			NetSession.DROPPED_PEER_TIMEOUT_MAX_MSEC)
	_disconnect(session, id)


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
