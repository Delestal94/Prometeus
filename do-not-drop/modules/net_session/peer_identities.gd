class_name NetPeerIdentities
extends RefCounted
## Who a peer is across reconnections, for NetSession's rejoin (host side),
## and the joiner's own claim. Portable module (docs/modulos.md).
##
## "steam:<id>" on Steam, which Valve vouches for and survives a restart of
## the game. On LAN "lan:<claim>", where the claims of one running game in one
## session are a hash chain (Lamport): the root is a hash of the process token
## with the session's nonce, the first claim is H^CHAIN_LENGTH(root) and each
## rejoin one step back, H^(N-k)(root). The host takes a claim when hashing it
## forward reaches the last one it took for someone, and keeps the new one.
## What travels is of no use to whoever overhears it: the host already has it,
## and the next one is a preimage only that game can compute; the token never
## travels. `by_peer`: peer id -> identity while the peer is here;
## `peer_by_identity`: identity (a LAN one under its last claim) -> the last
## peer id that had it, also after it left (a bounded memory, MEMORY past the
## crew).

const MEMORY: int = 16
## Claims one running game can make in one session before it starts a new
## chain -- and is someone new to the host.
const CHAIN_LENGTH: int = 64
const LAN_PREFIX: String = "lan:"

var by_peer: Dictionary = {}
var peer_by_identity: Dictionary = {}
## Host: made when the room is created and sent in the handshake ("session");
## a joiner hashes its token with it. Empty outside a session.
var nonce: String = ""
## This process's LAN identity, made once: rejoining from the same running
## game (a Wi-Fi hiccup, a timeout) is recognised; restarting it is a new
## player. Never sent, only the chain it roots.
var _token: String = ""
## Joiner: how many claims this process made in each session, {nonce: count},
## the MEMORY most recent sessions. Kept when a session ends: a rejoin goes on
## down the same chain.
var _claims_made: Dictionary = {}


## Forgets everyone, and the nonce. A new one when `new_nonce` (hosting).
func reset(new_nonce: bool = false) -> void:
	by_peer.clear()
	peer_by_identity.clear()
	nonce = Crypto.new().generate_random_bytes(8).hex_encode() if new_nonce else ""


func local_token() -> String:
	if _token.is_empty():
		_token = Crypto.new().generate_random_bytes(16).hex_encode()
	return _token


## What a joiner claims in its ready reply: the next link of its chain for
## this session, one step closer to the root than the last one. A chain used
## up starts a new one.
func claim() -> String:
	var made: int = int(_claims_made.get(nonce, 0))
	_claims_made.erase(nonce)
	_claims_made[nonce] = made + 1  # Most recent last, for the pruning.
	while _claims_made.size() > MEMORY:
		_claims_made.erase(_claims_made.keys()[0])
	var chain: int = floori(made / float(CHAIN_LENGTH))
	var root: String = (local_token() + nonce + str(chain)).sha256_text()
	return chain_link(root, CHAIN_LENGTH - made % CHAIN_LENGTH)


## `value` hashed `steps` times (SHA-256, as hex text).
static func chain_link(value: String, steps: int) -> String:
	for step: int in steps:
		value = value.sha256_text()
	return value


## Host: `id` is `identity`. Returns the peer id that had it before (0 if
## none; `id` itself when Steam hands the same id out again). A LAN identity
## is kept under its newest claim from now on.
func record(id: int, identity: String) -> int:
	var known: String = known_as(identity)
	var previous: int = int(peer_by_identity.get(known, 0)) if not known.is_empty() else 0
	peer_by_identity.erase(known)
	by_peer[id] = identity
	peer_by_identity.erase(identity)
	peer_by_identity[identity] = id  # Most recent last, for the pruning.
	prune()
	return previous


## Host: the peer id that last had the identity `identity` is (or continues),
## here or gone; 0 if none. Unlike record(), only looks.
func peer_of(identity: String) -> int:
	var known: String = known_as(identity)
	return int(peer_by_identity.get(known, 0)) if not known.is_empty() else 0


## Host: the identity already known that `identity` is: a Steam id itself, a
## LAN claim the one whose last claim it reaches when hashed forward 1 to
## CHAIN_LENGTH times. "" for someone new.
func known_as(identity: String) -> String:
	if not identity.begins_with(LAN_PREFIX):
		return identity if peer_by_identity.has(identity) else ""
	var value: String = identity.trim_prefix(LAN_PREFIX)
	for step: int in CHAIN_LENGTH:
		value = value.sha256_text()
		if peer_by_identity.has(LAN_PREFIX + value):
			return LAN_PREFIX + value
	return ""


## Host: a LAN claim the host already took for someone, or an older link of
## that chain: whoever sends it is repeating what it overheard.
func is_replay(identity: String) -> bool:
	if not identity.begins_with(LAN_PREFIX):
		return false
	var claimed: String = identity.trim_prefix(LAN_PREFIX)
	for known: String in peer_by_identity:
		if not known.begins_with(LAN_PREFIX):
			continue
		var value: String = known.trim_prefix(LAN_PREFIX)
		for step: int in CHAIN_LENGTH + 1:
			if value == claimed:
				return true
			value = value.sha256_text()
	return false


## `id` left (or never made it in): it stays remembered among those who left.
func forget(id: int) -> void:
	by_peer.erase(id)
	prune()


## On Steam the peer's Steam id; on LAN the claim in its ready reply, if it is one.
static func identity_of(multiplayer_peer: Object, id: int, reply: Dictionary) -> String:
	if multiplayer_peer != null and multiplayer_peer.has_method(&"get_steam_id_for_peer_id"):
		var steam_id: int = int(multiplayer_peer.call(&"get_steam_id_for_peer_id", id))
		if steam_id != 0:
			return "steam:%d" % steam_id
	var claimed: Variant = reply.get("identity", "")
	if claimed is String and not String(claimed).is_empty() and RpcGuard.text_ok(claimed):
		return LAN_PREFIX + String(claimed)
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
