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
## ghost goes (NetSession.drop_peer()) and it gets the place. On Steam who a
## joiner is is known as it authenticates; on LAN only from its ready reply,
## so it loads the level unplaced and is decided then. The transport takes one
## connection more than the room for it (NetSession._host_enet()).

## Joiners let in that are still authenticating, {peer_id: true}.
var admitted: Dictionary = {}
## Joiners still authenticating that found the room full, {peer_id: true}.
var unplaced: Dictionary = {}
var _identities: NetPeerIdentities


func _init(identities: NetPeerIdentities) -> void:
	_identities = identities


func reset() -> void:
	admitted.clear()
	unplaced.clear()


## `id` connected, or never made it in.
func forget(id: int) -> void:
	admitted.erase(id)
	unplaced.erase(id)


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


## From `id`'s ready reply, before the host completes its authentication:
## who it is (identify()), then whether one that found the room full gets in
## after all -- its ghost went, or someone left while it loaded. "" lets it in,
## else the failure code it hears ("full").
func on_identified(session: NetSession, id: int, reply: Dictionary) -> String:
	identify(session, id, reply)
	if not unplaced.has(id):
		return ""
	unplaced.erase(id)
	return admit(session, id)


## Who `id` is (its Steam id, or the hash in its ready reply). Someone who was
## here before gets its place back through the game (_peer_returned) and
## peer_rejoined; if its old connection is still up, that one is a ghost and
## goes.
func identify(session: NetSession, id: int, reply: Dictionary) -> void:
	var identity: String = NetPeerIdentities.identity_of(session.multiplayer.multiplayer_peer, id, reply)
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


## `previous` is on the roster but `id` is who it was: a ghost, which goes.
func _drop_ghost(session: NetSession, previous: int, id: int) -> bool:
	if previous == 0 or previous == id or previous == NetSession.HOST_ID or not session.peer_ids.has(previous):
		return false
	session.drop_peer(previous)
	return true
