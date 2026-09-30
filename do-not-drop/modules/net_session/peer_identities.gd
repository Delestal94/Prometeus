class_name NetPeerIdentities
extends RefCounted
## Who a peer is across reconnections, for NetSession's rejoin (host side),
## and the joiner's own claim. Portable module (docs/modulos.md).
##
## "steam:<id>" on Steam, which Valve vouches for and survives a restart of
## the game; on LAN "lan:<hash>", a hash of the joiner's process token with
## the session's nonce, so rejoining from the same running game is recognised
## and the token itself never travels. `by_peer`: peer id -> identity while
## the peer is here; `peer_by_identity`: identity -> the last peer id that had
## it, also after it left (a bounded memory, MEMORY past the crew).

const MEMORY: int = 16

var by_peer: Dictionary = {}
var peer_by_identity: Dictionary = {}
## Host: made when the room is created and sent in the handshake ("session");
## a joiner hashes its token with it. Empty outside a session.
var nonce: String = ""
## This process's LAN identity, made once: rejoining from the same running
## game (a Wi-Fi hiccup, a timeout) is recognised; restarting it is a new
## player. Only ever sent hashed, to the host.
var _token: String = ""


## Forgets everyone, and the nonce. A new one when `new_nonce` (hosting).
func reset(new_nonce: bool = false) -> void:
	by_peer.clear()
	peer_by_identity.clear()
	nonce = Crypto.new().generate_random_bytes(8).hex_encode() if new_nonce else ""


func local_token() -> String:
	if _token.is_empty():
		_token = Crypto.new().generate_random_bytes(16).hex_encode()
	return _token


## What a joiner claims in its ready reply: not the token itself but a hash of
## it with the host's nonce, the same on every rejoin to this session and of
## no use to anyone else's.
func claim() -> String:
	return (local_token() + nonce).sha256_text()


## Host: `id` is `identity`. Returns the peer id that had it before (0 if
## none; `id` itself when Steam hands the same id out again).
func record(id: int, identity: String) -> int:
	var previous: int = int(peer_by_identity.get(identity, 0))
	by_peer[id] = identity
	peer_by_identity.erase(identity)
	peer_by_identity[identity] = id  # Most recent last, for the pruning.
	prune()
	return previous


## `id` left (or never made it in): it stays remembered among those who left.
func forget(id: int) -> void:
	by_peer.erase(id)
	prune()


## On Steam the peer's Steam id; on LAN the hash it claimed, if it is one.
static func identity_of(multiplayer_peer: Object, id: int, reply: Dictionary) -> String:
	if multiplayer_peer != null and multiplayer_peer.has_method(&"get_steam_id_for_peer_id"):
		var steam_id: int = int(multiplayer_peer.call(&"get_steam_id_for_peer_id", id))
		if steam_id != 0:
			return "steam:%d" % steam_id
	var claimed: Variant = reply.get("identity", "")
	if claimed is String and not String(claimed).is_empty() and RpcGuard.text_ok(claimed):
		return "lan:" + String(claimed)
	return ""


## Keeps the identities of everyone here plus the MEMORY most recent of those
## who left: a peer reconnecting under new identities can't grow it.
func prune() -> void:
	var departed: Array = []
	for identity: String in peer_by_identity:
		if not by_peer.has(int(peer_by_identity[identity])):
			departed.append(identity)
	for index: int in maxi(0, departed.size() - MEMORY):
		peer_by_identity.erase(departed[index])
