class_name ColorSlots
extends RefCounted
## Which colour each player wears (N-226): a slot 0..count-1 the host hands out
## in arrival order and NetworkManager replicates (the join handshake, then
## `_sync_color_slots` whenever it changes). NetworkManager.color_slot() reads it.
##
## Why not the peer id: ENet and Steam give random ids up to 2^31, so
## posmod(peer_id, 5) changed a player's colour every session and, with five
## players, two of them shared one about 96 % of the time. Merit and route
## cards are kept by colour (docs/cartas-y-eventos-de-ruta.md), so a returning
## player could inherit someone else's.
##
## Pure functions over a {peer_id: slot} Dictionary of ints, so the rules are
## tested without sockets (test_network_roster.gd).

## The host is peer 1 and always wears slot 1 (yellow, the colour the
## wardrobe and the face preview show for your own shirt): playing solo, as
## posmod(1, count) always gave it, and in a session, placed there before
## anyone joins (place_host()). So the player whose machine keeps the campaign
## (crew_progression.gd) has one colour and one entry in it whether they play
## alone or host (N-226.2). Joiners take the lowest free slot: 0, 2, 3...
const HOST_ID: int = 1
const HOST_SLOT: int = 1


## The slot `peer_id` holds, or else the lowest free one, which it now holds: a
## slot freed by someone who left goes to the next one in, and nobody else's
## changes. -1 when all `count` slots are taken.
static func assign(slots: Dictionary, peer_id: int, count: int) -> int:
	if slots.has(peer_id):
		return int(slots[peer_id])
	var taken: Array = slots.values()
	for slot: int in count:
		if not taken.has(slot):
			slots[peer_id] = slot
			return slot
	return -1


## Puts the host on HOST_SLOT, or keeps the slot it has. Only if HOST_SLOT is
## somehow taken (or past `count`) does it get the lowest free one instead.
static func place_host(slots: Dictionary, count: int) -> int:
	if slots.has(HOST_ID):
		return int(slots[HOST_ID])
	if HOST_SLOT < count and not slots.values().has(HOST_SLOT):
		slots[HOST_ID] = HOST_SLOT
		return HOST_SLOT
	return assign(slots, HOST_ID, count)


## Like assign(), but a free slot in `reserved` (kept for someone who left and
## may come back, N-221) is only handed out when no other slot is free.
static func assign_avoiding(slots: Dictionary, peer_id: int, count: int, reserved: Array) -> int:
	if slots.has(peer_id):
		return int(slots[peer_id])
	var taken: Array = slots.values()
	for slot: int in count:
		if not taken.has(slot) and not reserved.has(slot):
			slots[peer_id] = slot
			return slot
	return assign(slots, peer_id, count)


## Frees `peer_id`'s slot for the next one in. True when it had one.
static func release(slots: Dictionary, peer_id: int) -> bool:
	return slots.erase(peer_id)


## `peer_id`'s slot or, when it has none (solo play, offline, a peer the
## host hasn't announced yet), HOST_SLOT for the host and posmod(peer_id,
## count) for anyone else, what the colour readers computed before slots.
static func slot_of(slots: Dictionary, peer_id: int, count: int) -> int:
	if slots.has(peer_id):
		return int(slots[peer_id])
	if peer_id == HOST_ID:
		return HOST_SLOT
	return posmod(peer_id, count)


## Whether a map that came over the network can be used as it is: a
## Dictionary of int peer ids (> 0) to int slots in 0..count-1, no two peers on
## one slot. Anything else -- floats, strings, a slot out of range, a repeated
## slot -- rejects the whole map: half of one would be worse than the old one.
static func is_valid(raw: Variant, count: int) -> bool:
	if not raw is Dictionary:
		return false
	var map: Dictionary = raw
	if map.size() > count:
		return false
	var seen: Dictionary = {}
	for key: Variant in map:
		var value: Variant = map[key]
		if typeof(key) != TYPE_INT or typeof(value) != TYPE_INT:
			return false
		if int(key) <= 0 or int(value) < 0 or int(value) >= count or seen.has(value):
			return false
		seen[value] = true
	return true
