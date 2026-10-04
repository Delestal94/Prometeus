class_name CompanyNet
extends Node
## Business events of the company mode, by reliable RPC with a sequence number (D-2003).
##
## The contract is docs/expansion-distritos/diseno/red-autoridad.md (D-2001). A client never
## writes business state, not even ahead of time: it asks the host (_request, through
## RpcGuard), the host checks the request with what only it knows (stock, reach, hands),
## applies the resulting event and sends it, numbered, to every ready peer (_apply_event),
## where the same code applies it again. A refused request tells only its sender why
## (_rejected); a dropped one (malformed, over budget) tells nobody.
##
## Events carry `seq`. Reliable delivery loses nothing, so the only gap is an event sent
## before this peer's world was up: a peer that sees a number skipped holds what comes next
## and asks for a snapshot (snapshot_request, at most one per SNAPSHOT_INTERVAL_MSEC per peer
## on the host).
##
## The snapshot (D-2004, the contract's section 3) is the whole business state at the host's
## current seq (snapshot()). The host sends it to a peer when that peer's world comes up
## (NetworkManager.peer_level_ready) and when it asks; it travels compressed, in chunks of at
## most SNAPSHOT_CHUNK_BYTES (_snapshot), on the same reliable channel as the events, so it
## lands before any event that comes after it. The peer holds every event until the last
## chunk is in, puts the host's state in place of its own (apply_snapshot(): one
## company_state_restored, no fact signal), drops the held events the snapshot covers and
## applies the rest in order.
##
## Child of the company world (CompanyRoot today, CompanyWorld once it exists), always named
## "CompanyNet" so its RPC path is the same on every peer. The owner hands it the live
## `inventory`, the `company` state, the `stations` lookup and any other snapshot part
## (add_snapshot_part()). It names no autoload (lesson N-919): NetworkManager is reached by
## path, only to know which peers have their world up and when one comes up.
##
## Kinds today: units_take and units_store (rows 5 and 6 of the contract's section 2) and
## snapshot_request. A task that adds an action appends its kind to REQUEST_KINDS (and to
## CRITICAL_KINDS when losing it leaves a player stuck, rule 8), checks it in
## _handle_request() and applies its event in _apply_state().
##
## A host rule that reacts to a business fact listens to event_applied, never to
## Inventory.stock_changed: that one fires in the middle of applying an event, and a request
## made there is refused (it would number its event before the one being applied).

## Every peer, the host too, right after an event changed the state here. Presentation (HUD,
## sounds, the units in a player's hands) listens to this; the simulation never needs it to.
signal event_applied(seq: int, kind: StringName, data: Dictionary)
## The requester only: the host refused request `rid` (what request() returned), and why
## (one of the REASON_* names). Only a notice: nothing changed anywhere.
signal request_rejected(rid: int, reason: StringName)
## Host: `peer` saw an event skipped and asked for the whole state, the rate limit let the
## request through and the snapshot is on its way (send_snapshot()).
signal snapshot_requested(peer: int)
## Every peer but the host: the host's snapshot replaced the business state here (a late join
## or a seq gap). The only signal applying it fires (no event_applied, no
## Inventory.stock_changed): the presentation redraws everything from the state here.
## `snapshot_seq` is the last event the snapshot covers.
signal company_state_restored(snapshot_seq: int)

const HOST_ID: int = 1
const SNAPSHOT_REQUEST: StringName = &"snapshot_request"
## Request kinds the host takes (the contract's section 2 whitelist); anything else is
## dropped. Later tasks append theirs.
const REQUEST_KINDS: Array[StringName] = [&"units_take", &"units_store", SNAPSHOT_REQUEST]
## Requests whose loss leaves a player stuck (rule 8: letting go of something). They spend
## RpcGuard's critical reserve once the sender's budget is gone. units_drop joins with D-2006.
const CRITICAL_KINDS: Array[StringName] = []
## Event kinds every peer applies.
const EVENT_KINDS: Array[StringName] = [&"units_moved"]
## Host: one snapshot request per peer in this long (a broken client would ask once per
## event). The client waits as long before asking again.
const SNAPSHOT_INTERVAL_MSEC: int = 5000
## Events a peer holds while it waits for a snapshot. Past this the oldest go: a snapshot
## taken later covers them anyway.
const MAX_HELD_EVENTS: int = 4096
## A snapshot travels as var_to_bytes, compressed with this and cut into chunks of at most
## SNAPSHOT_CHUNK_BYTES, so one _snapshot RPC stays under 64 KB with its own header.
const SNAPSHOT_COMPRESSION: FileAccess.CompressionMode = FileAccess.COMPRESSION_ZSTD
const SNAPSHOT_CHUNK_BYTES: int = 60 * 1024
## The largest snapshot, uncompressed, that is built or taken: decompress() is told the size
## up front and never gets more than this. 300 units with a full ledger: 34 KB, 2 KB compressed.
const SNAPSHOT_MAX_BYTES: int = 4 * 1024 * 1024
## Chunks one snapshot may take: 480 KB compressed, all queued at once, under the ~512 KB a
## Steam connection buffers by default (a 300-unit shed takes 2 KB).
const SNAPSHOT_MAX_CHUNKS: int = 8
## Longest id (product, location, order) the stock of a snapshot may carry.
const SNAPSHOT_MAX_ID_LENGTH: int = 256
## Keys of the snapshot that CompanyNet fills itself (snapshot()); no part may take them.
const SNAPSHOT_KEYS: Array[String] = ["seq", "inventory", "company"]
const HANDS_PREFIX: String = "hands:"
## Where the product catalog lives: an id in a request must name one of its files.
const PRODUCTS_DIR: String = "res://data/products/"

const REASON_BAD_DATA: StringName = &"bad_data"
const REASON_NO_STATION: StringName = &"no_station"
const REASON_OUT_OF_REACH: StringName = &"out_of_reach"
const REASON_NOT_ENOUGH: StringName = &"not_enough"
const REASON_HANDS_FULL: StringName = &"hands_full"
const REASON_HANDS_BUSY: StringName = &"hands_busy"
const REASON_WRONG_PRODUCT: StringName = &"wrong_product"
const REASON_NO_ROOM: StringName = &"no_room"

## The stock every units event moves. The owner sets it (CompanyRoot: CompanyState.stock());
## the host and each client hold their own copy, kept equal by the events. Writing it back to
## CompanyState before a save is D-0206's.
var inventory: Inventory = Inventory.new()
## The CompanyState node (by reference, never by autoload name), or null. The host puts its
## to_dict() in every snapshot; a client loads the host's into it, its only write there
## (rule 1). The owner sets it on every peer (CompanyRoot).
var company: Object = null
## Host: size of the chunks a snapshot is cut into, up to SNAPSHOT_CHUNK_BYTES (a test forces
## small ones to cut a snapshot in many).
var snapshot_chunk_bytes: int = SNAPSHOT_CHUNK_BYTES
## Host: a station id -> what the host needs to check a request at it (rule 4), as
## Callable(station: StringName) -> Dictionary:
##   location  StringName  where its units are counted (pallet:<id>, shelf:<id>_<slot>...)
##   spot      Vector3     where reach is measured to: the slot or cell, not the furniture
##   accepts   StringName  optional: the only product a store may put there (a slot label)
##   capacity  int         optional: units it holds at most (0 or missing: no limit)
## {} for an unknown station. Unset (no stations exist yet), every request names an unknown
## one. The world that places stations (D-0608, D-0609, D-0611) sets it.
var stations: Callable = Callable()
## Host: where `peer`'s reach starts, as Callable(peer: int) -> Variant (a Vector3, or null
## when that peer has no player). Unset, it is that peer's player node
## (Interactable.player_group), from its reach_origin() if it has one.
var player_origin: Callable = Callable()
## The number of the last event applied here. The host applies each event as it sends it, so
## there it is also the last one sent. Starts at 0; the first event is 1. A client takes the
## snapshot's. Keeping it across a loaded day (section 3) is D-0206's.
var seq: int = 0

var _next_rid: int = 0
## True while an event changes the state here (_apply_state()): no request or event may start.
var _applying: bool = false
## Client: events that came after a skipped number, {seq: [kind, data]}, until a snapshot.
var _held: Dictionary = {}
var _awaiting_snapshot: bool = false
## Client: when it last asked for a snapshot (msec), -1 for never.
var _snapshot_asked_msec: int = -1
## Host: {peer: msec} of the last snapshot request let through, per peer.
var _snapshot_granted: Dictionary = {}
## Host: {peer: Vector3}, where each peer stood at its last units request. D-2006 drops what
## a leaver held there when its player node is already gone (last_known_position()).
var _last_origin: Dictionary = {}
## Snapshot parts kept outside CompanyNet, {key: [take, put]} (add_snapshot_part()).
var _parts: Dictionary = {}
## Host: {peer: true} once a snapshot too big to send was reported for it (one error per peer).
var _oversize_reported: Dictionary = {}
## Host: id of the last snapshot sent. Each one takes the next, so a peer can tell an older
## snapshot's chunks apart.
var _snapshot_id: int = 0
## Client: the newest snapshot id seen and, while that one is put together, its chunk count,
## size uncompressed and {chunk index: bytes}. _rx_total is 0 once it is done or thrown away.
var _rx_id: int = 0
var _rx_total: int = 0
var _rx_size: int = 0
var _rx_chunks: Dictionary = {}

## Product ids of the catalog, read once from PRODUCTS_DIR ({StringName: true}).
static var _known_products: Dictionary = {}
static var _catalog_read: bool = false


func _ready() -> void:
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"peer_level_ready"):
		if not network.is_connected(&"peer_level_ready", _on_peer_level_ready):
			network.connect(&"peer_level_ready", _on_peer_level_ready)
	# Peers already up when this world came up won't fire peer_level_ready again. Deferred: the
	# owner hands over the stock and the company right after adding this node.
	_snapshot_ready_peers.call_deferred()
	set_process(_awaiting_snapshot)


## Client: while it waits for a snapshot, asks again every SNAPSHOT_INTERVAL_MSEC (one lost,
## dropped by the host's limit, or never sent).
func _process(_delta: float) -> void:
	poll_snapshot(Time.get_ticks_msec())


## Asks the host for `kind` with `data` and returns the request id a refusal will carry
## (request_rejected), 0 when there is nobody to ask (no tree, or a connection not up). On the
## host, and playing solo, it goes through the same checks at once, as this peer's own
## request (also when called while handling another peer's RPC). Nothing changes here until
## the host's event comes back (rule 1: no prediction). The actor is whoever sends it: a peer
## field in `data` means nothing. Called while an event is being applied (a stock_changed
## listener), it is refused with an error and returns 0.
func request(kind: StringName, data: Dictionary = {}) -> int:
	if not is_inside_tree():
		return 0
	if _applying:
		push_error("CompanyNet: request %s while an event is applied; listen to event_applied"
			% kind)
		return 0
	var host: bool = is_host()
	if not host and not _connected_client():
		return 0
	_next_rid += 1
	var sent: Dictionary = data.duplicate()
	sent["rid"] = _next_rid
	if host:
		_take_request(multiplayer.get_unique_id(), kind, sent)
	else:
		_request.rpc_id(HOST_ID, kind, sent)
	return _next_rid


## True on the host and when playing solo: the only place business state is decided.
func is_host() -> bool:
	if not is_inside_tree():
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return true
	return (
		peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		and multiplayer.is_server()
	)


## Inventory location of what `peer` holds. Built by the host from the sender (rule 3).
static func hands_location(peer: int) -> StringName:
	return StringName(HANDS_PREFIX + str(peer))


## Rule 4's shared check: a spot (a pallet, a shelf slot, a grid cell) is within reach of
## `origin` (the player's reach origin) up to Interactable.REMOTE_REACH plus `slack`.
static func within_reach(origin: Vector3, spot: Vector3, slack: float = 0.0) -> bool:
	return origin.distance_to(spot) <= Interactable.REMOTE_REACH + slack


## A product id that came over the network names a product of the catalog: exactly the
## name of one of its files (case included), never a path.
static func product_exists(product: StringName) -> bool:
	if not _catalog_read:
		_catalog_read = true
		# ResourceLoader lists exported files by their original names (no .remap).
		for file: String in ResourceLoader.list_directory(PRODUCTS_DIR):
			if file.ends_with(".tres") or file.ends_with(".res"):
				_known_products[StringName(file.get_basename())] = true
	return _known_products.has(product)


## Host: where `peer` stood at its last units request, null if it never made one (D-2006).
func last_known_position(peer: int) -> Variant:
	return _last_origin.get(peer)


## Host: lets a snapshot request from `peer` through at `now_msec` unless one already went
## through less than SNAPSHOT_INTERVAL_MSEC before; then sends it the snapshot and emits
## snapshot_requested. The host never asks itself. True when it went through; a snapshot that
## could not be sent (send_snapshot()) doesn't count, so the next request may try again.
func grant_snapshot(peer: int, now_msec: int) -> bool:
	if peer == multiplayer.get_unique_id():
		return false
	var last: int = int(_snapshot_granted.get(peer, -1))
	if last >= 0 and now_msec - last < SNAPSHOT_INTERVAL_MSEC:
		return false
	if not send_snapshot(peer):
		return false
	_snapshot_granted[peer] = now_msec
	snapshot_requested.emit(peer)
	return true


## Adds a part to the snapshot under `key`: state an event of section 2 changes that lives
## outside CompanyNet's stock and `company` (the order book, the day phase and clock anchor,
## pallets, packing tables, live boxes, units on the floor). `take` (host) is
## Callable() -> Variant and returns that part as plain data var_to_bytes keeps (no Object,
## no Callable); `put` (client) is Callable(value: Variant) -> bool, puts the host's value in
## place of what is there without firing fact signals, checks it like any data from the
## network (rule 5) and returns false when it doesn't fit (the client then waits for another
## snapshot). Every peer adds the same parts before its world is up. False, adding nothing,
## when `key` is taken or a callable isn't valid.
func add_snapshot_part(key: String, take: Callable, put: Callable) -> bool:
	if key.is_empty() or SNAPSHOT_KEYS.has(key) or _parts.has(key):
		return false
	if not take.is_valid() or not put.is_valid():
		return false
	_parts[key] = [take, put]
	return true


## Host: the business state as a snapshot carries it (section 3), as plain data:
##   seq        int: the last event it covers; the peer drops every event up to it
##   inventory  the live stock with its reservations (Inventory.to_dict())
##   company    CompanyState.to_dict() without its stored stock (the live one is `inventory`):
##              money, day and clock, reputation, gates (the locks), fleet, employees,
##              milestones, layout, ledger. Missing without a `company`
##   <part>     one per add_snapshot_part()
func snapshot() -> Dictionary:
	var stock: Inventory = inventory if inventory != null else Inventory.new()
	var data: Dictionary = {"seq": seq, "inventory": stock.to_dict()}
	if company != null and company.has_method(&"to_dict"):
		var state: Variant = company.call(&"to_dict")
		if state is Dictionary:
			var stored: Dictionary = state
			stored.erase("inventory")
			data["company"] = stored
	for key: String in _parts:
		var take: Callable = _parts[key][0]
		data[key] = take.call()
	return data


## Host: sends `peer` the snapshot as it stands now, cut in chunks (_snapshot), on the events'
## reliable channel: it reaches the peer after every event sent before it and before any sent
## after it. Sent when the peer's world comes up (NetworkManager.peer_level_ready) and when it
## asks (grant_snapshot()). False when this isn't the host, `peer` isn't connected, an event
## is being applied (the state is half changed and its seq not yet counted) or the snapshot
## is over SNAPSHOT_MAX_BYTES or SNAPSHOT_MAX_CHUNKS (an error, once per peer until one fits).
func send_snapshot(peer: int) -> bool:
	if not is_host() or peer == multiplayer.get_unique_id():
		return false
	if not multiplayer.get_peers().has(peer):
		return false
	if _applying:
		push_error("CompanyNet: a snapshot for peer %d while an event is applied" % peer)
		return false
	var packed: Dictionary = pack_snapshot(snapshot(), snapshot_chunk_bytes)
	if packed.is_empty():
		if not _oversize_reported.has(peer):
			_oversize_reported[peer] = true
			push_error("CompanyNet: the snapshot for peer %d is over %d bytes or %d chunks; not sent"
				% [peer, SNAPSHOT_MAX_BYTES, SNAPSHOT_MAX_CHUNKS])
		return false
	_oversize_reported.erase(peer)
	_snapshot_id += 1
	var chunks: Array[PackedByteArray] = packed["chunks"]
	var size: int = packed["size"]
	for index: int in range(chunks.size()):
		_snapshot.rpc_id(peer, _snapshot_id, index, chunks.size(), size, chunks[index])
	return true


## A snapshot as _snapshot carries it: {size: its var_to_bytes size, chunks: the compressed
## bytes cut every `chunk_bytes` (1 to SNAPSHOT_CHUNK_BYTES)}. {} when it is over
## SNAPSHOT_MAX_BYTES or takes more than SNAPSHOT_MAX_CHUNKS.
static func pack_snapshot(data: Dictionary, chunk_bytes: int = SNAPSHOT_CHUNK_BYTES) -> Dictionary:
	var raw: PackedByteArray = var_to_bytes(data)
	if raw.size() > SNAPSHOT_MAX_BYTES:
		return {}
	var packed: PackedByteArray = raw.compress(SNAPSHOT_COMPRESSION)
	var step: int = clampi(chunk_bytes, 1, SNAPSHOT_CHUNK_BYTES)
	var chunks: Array[PackedByteArray] = []
	for start: int in range(0, packed.size(), step):
		chunks.append(packed.slice(start, start + step))
	if chunks.is_empty() or chunks.size() > SNAPSHOT_MAX_CHUNKS:
		return {}
	return {"size": raw.size(), "chunks": chunks}


## The snapshot back from its joined chunks and its uncompressed `size`, or {} when they don't
## make one: a size out of range, bytes that don't decompress to exactly `size`, or anything
## but a Dictionary. Objects never come back (bytes_to_var, not bytes_to_var_with_objects).
static func unpack_snapshot(packed: PackedByteArray, size: int) -> Dictionary:
	if packed.is_empty() or size < 1 or size > SNAPSHOT_MAX_BYTES:
		return {}
	var raw: PackedByteArray = packed.decompress(size, SNAPSHOT_COMPRESSION)
	if raw.size() != size:
		return {}
	var data: Variant = bytes_to_var(raw)
	return data if data is Dictionary else {}


## A stock in Inventory.to_dict() form that came over the network (rule 5): a Dictionary with
## at most `stock` ({product: {location: qty}}) and `reserved` ({order: {product: qty}}), ids
## as text up to SNAPSHOT_MAX_ID_LENGTH, quantities as positive ints.
static func stock_ok(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var stock: Dictionary = value
	for part: Variant in stock:
		if typeof(part) != TYPE_STRING or not ["stock", "reserved"].has(part):
			return false
		if not stock[part] is Dictionary:
			return false
		var outer: Dictionary = stock[part]
		for id: Variant in outer:
			if not _snapshot_name_ok(id) or not outer[id] is Dictionary:
				return false
			var inner: Dictionary = outer[id]
			for sub: Variant in inner:
				if not _snapshot_name_ok(sub) or typeof(inner[sub]) != TYPE_INT or int(inner[sub]) < 1:
					return false
	return true


## Client: puts the host's snapshot (snapshot()) in place of the business state here: the
## stock with its reservations, the company and every part, without a fact signal; emits
## company_state_restored once, then drops the held events the snapshot covers and applies the
## rest in order (resume_after_snapshot()). False, changing nothing, when it is malformed,
## older than what is applied here or this is the host. A part that refuses its value comes
## after the rest changed: then it is false too, and this peer waits for the next snapshot.
func apply_snapshot(data: Dictionary) -> bool:
	if is_host() or _applying:
		return false
	var snapshot_seq: Variant = data.get("seq")
	if typeof(snapshot_seq) != TYPE_INT or int(snapshot_seq) < seq:
		return false
	var stock: Variant = data.get("inventory")
	var state: Variant = data.get("company", {})
	if not stock_ok(stock) or not state is Dictionary or inventory == null:
		return false
	_applying = true
	inventory.from_dict(stock)
	if company != null and company.has_method(&"from_dict") and not (state as Dictionary).is_empty():
		var with_stock: Dictionary = (state as Dictionary).duplicate()
		with_stock["inventory"] = inventory.to_dict()
		company.call(&"from_dict", with_stock)
	var whole: bool = true
	for key: String in _parts:
		if data.has(key):
			var put: Callable = _parts[key][1]
			whole = bool(put.call(data[key])) and whole
	_applying = false
	if not whole:
		push_warning("CompanyNet: a part of the snapshot at seq %d does not fit" % snapshot_seq)
		_start_waiting()
		return false
	company_state_restored.emit(int(snapshot_seq))
	resume_after_snapshot(int(snapshot_seq))
	return true


## Client, joining (CompanyRoot): its stock is not the host's until the snapshot comes, so
## every event is held until resume_after_snapshot(). The host sends that snapshot once this
## peer is ready; only if it hasn't come within SNAPSHOT_INTERVAL_MSEC is it asked for.
func wait_for_snapshot() -> void:
	_start_waiting()
	_snapshot_asked_msec = Time.get_ticks_msec()


## Client: while waiting for a snapshot, asks for one if SNAPSHOT_INTERVAL_MSEC passed since
## the last time (or it never asked). `now_msec` is Time.get_ticks_msec() (_process), or a
## clock a test drives. True when it asked.
func poll_snapshot(now_msec: int) -> bool:
	if not _awaiting_snapshot or is_host():
		return false
	if _snapshot_asked_msec >= 0 and now_msec - _snapshot_asked_msec < SNAPSHOT_INTERVAL_MSEC:
		return false
	_snapshot_asked_msec = now_msec
	return request(SNAPSHOT_REQUEST) > 0


## Client: a snapshot taken at `snapshot_seq` is in place here (apply_snapshot()). Events up to
## it are in the snapshot and dropped; those held since the gap are applied in order. If one is
## still missing, the rest stay held and a snapshot is asked for again at once.
func resume_after_snapshot(snapshot_seq: int) -> void:
	seq = snapshot_seq
	_awaiting_snapshot = false
	_snapshot_asked_msec = -1
	set_process(false)
	var pending: Dictionary = _held
	_held = {}
	var numbers: Array = pending.keys()
	numbers.sort()
	for number: int in numbers:
		var entry: Array = pending[number]
		_receive(number, entry[0], entry[1])


## Client: true while it holds events waiting for a snapshot.
func awaiting_snapshot() -> bool:
	return _awaiting_snapshot


## Host: a request from another peer. Dropped silently when it reaches a client or the
## sender is over its budget; the rest is _take_request()'s, on behalf of the sender. The
## host's own requests skip this (request() calls _take_request() directly), so one made
## while handling another peer's RPC is still the host's.
@rpc("any_peer", "call_local", "reliable")
func _request(kind: StringName, data: Dictionary) -> void:
	if not is_host():
		return
	var budget_left: bool = (
		RpcGuard.allow_critical_request(self)
		if CRITICAL_KINDS.has(kind)
		else RpcGuard.allow_request(self)
	)
	if budget_left:
		_take_request(RpcGuard.sender(self), kind, data)


## Host: a request made by `peer`. Dropped silently when malformed, of an unknown kind or
## without an int rid; refused with a reason (_rejected) when the game says no.
func _take_request(peer: int, kind: StringName, data: Dictionary) -> void:
	if not RpcGuard.name_ok(kind) or not RpcGuard.dict_ok(data):
		return
	if not REQUEST_KINDS.has(kind) or typeof(data.get("rid")) != TYPE_INT:
		return
	var reason: StringName = _handle_request(peer, kind, data)
	if reason != &"":
		_refuse(peer, int(data["rid"]), reason)


## Every peer but the host: one event from the host, applied in order. An old or repeated
## number changes nothing; a skipped one holds this and what follows until a snapshot.
@rpc("authority", "call_local", "reliable")
func _apply_event(event_seq: int, kind: StringName, data: Dictionary) -> void:
	if not RpcGuard.from_host(self) or is_host() or not EVENT_KINDS.has(kind):
		return
	_receive(event_seq, kind, data)


## Every peer but the host: chunk `chunk` of `total` of snapshot `id` (the host numbers them,
## so a chunk of an older one is dropped), `size` bytes once joined and decompressed
## (decompress() needs it). Same channel as _apply_event, so it is in order with the events.
@rpc("authority", "call_remote", "reliable")
func _snapshot(id: int, chunk: int, total: int, size: int, bytes: PackedByteArray) -> void:
	if not RpcGuard.from_host(self) or is_host():
		return
	_take_chunk(id, chunk, total, size, bytes)


## The requester: the host refused request `rid`. Draws a notice at most; no state changes.
@rpc("authority", "call_remote", "reliable")
func _rejected(rid: int, reason: StringName) -> void:
	if not RpcGuard.from_host(self):
		return
	request_rejected.emit(rid, reason)


## Host: what a valid request does, or the reason it is refused (&"" when it went through).
func _handle_request(peer: int, kind: StringName, data: Dictionary) -> StringName:
	match kind:
		&"units_take":
			return _take_units(peer, data)
		&"units_store":
			return _store_units(peer, data)
		SNAPSHOT_REQUEST:
			# Over the limit it is dropped, not refused: the client asks again on its own.
			grant_snapshot(peer, Time.get_ticks_msec())
	return &""


## Host, section 2 row 5: units from a station (pallet, shelf slot, floor bundle) into the
## sender's hands, free or empty hands holding only that product, up to the hand's limit.
## Reserved units may be taken too: a reservation is per product and stays where it is (who
## may put a reserved unit in which box is checked at box_place, D-0807 / D-0703).
func _take_units(peer: int, data: Dictionary) -> StringName:
	var ask: Dictionary = _units_ask(data)
	var station: Dictionary = _lookup_station(ask)
	var problem: StringName = _station_problem(peer, ask, station)
	if problem != &"":
		return problem
	var product: StringName = ask["product"]
	var qty: int = ask["qty"]
	var from: StringName = _as_id(station["location"])
	var hands: StringName = hands_location(peer)
	if inventory.count(product, from) < qty:
		return REASON_NOT_ENOUGH
	var held: Dictionary = inventory.contents_at(hands)
	if held.size() > 1 or (held.size() == 1 and not held.has(product)):
		return REASON_HANDS_BUSY
	if inventory.count(product, hands) + qty > CompanyTuning.HAND_MAX_UNITS:
		return REASON_HANDS_FULL
	var moved: Dictionary = {"product": product, "qty": qty, "from": from, "to": hands}
	return &"" if _publish(&"units_moved", moved) else REASON_BAD_DATA


## Host, section 2 row 6: units from the sender's hands into a station that takes them (a
## shelf slot labeled for that product, with room, D-0608).
func _store_units(peer: int, data: Dictionary) -> StringName:
	var ask: Dictionary = _units_ask(data)
	var station: Dictionary = _lookup_station(ask)
	var problem: StringName = _station_problem(peer, ask, station)
	if problem != &"":
		return problem
	var product: StringName = ask["product"]
	var qty: int = ask["qty"]
	var to: StringName = _as_id(station["location"])
	var hands: StringName = hands_location(peer)
	if inventory.count(product, hands) < qty:
		return REASON_NOT_ENOUGH
	var accepts: StringName = _as_id(station.get("accepts"))
	if accepts != &"" and accepts != product:
		return REASON_WRONG_PRODUCT
	var capacity: int = _as_int(station.get("capacity"))
	if capacity > 0 and _units_at(to) + qty > capacity:
		return REASON_NO_ROOM
	var moved: Dictionary = {"product": product, "qty": qty, "from": hands, "to": to}
	return &"" if _publish(&"units_moved", moved) else REASON_BAD_DATA


## Host: the one way an event happens. Numbers it, applies it here first, sends it to every
## ready peer but this one (rule 2: rpc_id, never .rpc(), which would also reach peers whose
## world isn't up; those get the snapshot, D-2004) and only then tells the presentation, so an
## event a listener publishes in turn goes out after this one. False, with nothing sent, when
## the state doesn't take it or another event is being applied right now.
func _publish(kind: StringName, data: Dictionary) -> bool:
	if _applying:
		push_error("CompanyNet: %s event published while another is applied" % kind)
		return false
	if not _apply_state(kind, data):
		push_error("CompanyNet: the host could not apply its own %s event %s" % [kind, data])
		return false
	seq += 1
	for peer: int in _event_targets():
		_apply_event.rpc_id(peer, seq, kind, data)
	event_applied.emit(seq, kind, data)
	return true


## Client: an event from the host, in order or held (section 3).
func _receive(event_seq: int, kind: StringName, data: Dictionary) -> void:
	if event_seq <= seq or _held.has(event_seq):
		return
	if _awaiting_snapshot or event_seq != seq + 1:
		_hold(event_seq, kind, data)
		return
	seq = event_seq
	if not _apply_state(kind, data):
		# This copy no longer matches the host's: only a snapshot puts it right.
		push_warning("CompanyNet: event %d (%s) does not fit this peer's state" % [event_seq, kind])
		_start_waiting()
		poll_snapshot(Time.get_ticks_msec())
		return
	event_applied.emit(seq, kind, data)


## The one place an event changes state, with the same code on every peer (rule 6: no game
## rule is checked again, only that the data fits). False when it doesn't. While it runs
## (Inventory signals fire inside it) no request or event may start: _applying.
func _apply_state(kind: StringName, data: Dictionary) -> bool:
	if inventory == null or not EVENT_KINDS.has(kind):
		return false
	_applying = true
	var applied: bool = false
	match kind:
		&"units_moved":
			applied = inventory.move(
				_as_id(data.get("product")),
				_as_int(data.get("qty")),
				_as_id(data.get("from")),
				_as_id(data.get("to"))
			)
	_applying = false
	return applied


func _hold(event_seq: int, kind: StringName, data: Dictionary) -> void:
	if _held.size() >= MAX_HELD_EVENTS:
		_held.erase(_held.keys().min())
	_held[event_seq] = [kind, data]
	_start_waiting()
	poll_snapshot(Time.get_ticks_msec())


func _start_waiting() -> void:
	_awaiting_snapshot = true
	set_process(true)


## Client: keeps one chunk (checked first, rule 5: ids and counts in range, at most
## SNAPSHOT_CHUNK_BYTES, the same total and size as the rest of its snapshot) and, with the
## last one in, joins them and applies the snapshot. The first chunk of a newer snapshot drops
## what was kept of the one before, starts holding events and restarts the wait before asking
## again. A repeated chunk, or one of an older or finished snapshot, changes nothing. A
## snapshot that doesn't unpack or apply leaves this peer waiting: it asks again
## (poll_snapshot()).
func _take_chunk(id: int, chunk: int, total: int, size: int, bytes: PackedByteArray) -> void:
	if id < 1 or total < 1 or total > SNAPSHOT_MAX_CHUNKS or chunk < 0 or chunk >= total:
		return
	if size < 1 or size > SNAPSHOT_MAX_BYTES:
		return
	if bytes.is_empty() or bytes.size() > SNAPSHOT_CHUNK_BYTES or id < _rx_id:
		return
	if id > _rx_id:
		_rx_id = id
		_rx_total = total
		_rx_size = size
		_rx_chunks = {}
		_start_waiting()
		_snapshot_asked_msec = Time.get_ticks_msec()
	elif _rx_total == 0 or total != _rx_total or size != _rx_size or _rx_chunks.has(chunk):
		return
	_rx_chunks[chunk] = bytes
	if _rx_chunks.size() < _rx_total:
		return
	var joined := PackedByteArray()
	for index: int in range(_rx_total):
		joined.append_array(_rx_chunks[index])
	_rx_total = 0
	_rx_chunks = {}
	var data: Dictionary = unpack_snapshot(joined, _rx_size)
	if data.is_empty() or not apply_snapshot(data):
		push_warning("CompanyNet: snapshot %d could not be applied; waiting for another" % id)
		_start_waiting()


## Host: tells the requester why nothing happened. The host's own request hears it here at once
## (_rejected is call_remote and would not reach it). A refusal spends no seq.
func _refuse(peer: int, rid: int, reason: StringName) -> void:
	if peer == multiplayer.get_unique_id():
		request_rejected.emit(rid, reason)
	elif multiplayer.get_peers().has(peer):
		_rejected.rpc_id(peer, rid, reason)


## Host: the peers an event goes to now: connected, not this one, with their world up
## (NetworkManager.is_peer_ready(); without a NetworkManager, every connected peer).
func _event_targets() -> Array[int]:
	var targets: Array[int] = []
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return targets
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	var ready_check: bool = network != null and network.has_method(&"is_peer_ready")
	var me: int = multiplayer.get_unique_id()
	for id: int in multiplayer.get_peers():
		if id != me and (not ready_check or bool(network.call(&"is_peer_ready", id))):
			targets.append(id)
	return targets


func _connected_client() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return (
		peer != null
		and not peer is OfflineMultiplayerPeer
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		and not multiplayer.is_server()
	)


## The station, product and quantity of a units request, checked (rule 5: plain, bounded, a
## product of the catalog), or {} when any is missing, of the wrong type or out of range.
static func _units_ask(data: Dictionary) -> Dictionary:
	var station: Variant = data.get("station")
	var product: Variant = data.get("product")
	var qty: Variant = data.get("qty")
	if not (_is_id(station) and _is_id(product) and typeof(qty) == TYPE_INT):
		return {}
	if int(qty) < 1 or int(qty) > CompanyTuning.PALLET_MAX_UNITS or String(station).is_empty():
		return {}
	if not product_exists(StringName(product)):
		return {}
	return {"station": StringName(station), "product": StringName(product), "qty": int(qty)}


## The station a checked request names, as the owner describes it (`stations`), or {} when it
## is unknown or the description is unusable.
func _lookup_station(ask: Dictionary) -> Dictionary:
	if ask.is_empty() or not stations.is_valid():
		return {}
	var found: Variant = stations.call(ask["station"])
	if not found is Dictionary:
		return {}
	var station: Dictionary = found
	var location: StringName = _as_id(station.get("location"))
	if location == &"" or String(location).begins_with(HANDS_PREFIX):
		return {}
	return station if station.get("spot") is Vector3 else {}


## Why a units request can't be done at that station: bad data, an unknown station or one out
## of the sender's reach (rule 4, measured to the station's spot). &"" when it can.
func _station_problem(peer: int, ask: Dictionary, station: Dictionary) -> StringName:
	if ask.is_empty():
		return REASON_BAD_DATA
	if station.is_empty():
		return REASON_NO_STATION
	var origin: Variant = _origin_of(peer)
	if not (origin is Vector3 and RpcGuard.finite_vec3(origin)):
		return REASON_OUT_OF_REACH
	_last_origin[peer] = origin
	var slack: float = NetStats.reach_slack(multiplayer.multiplayer_peer, peer)
	if not within_reach(origin, station["spot"], slack):
		return REASON_OUT_OF_REACH
	return &""


func _origin_of(peer: int) -> Variant:
	if player_origin.is_valid():
		return player_origin.call(peer)
	for player: Node in get_tree().get_nodes_in_group(Interactable.player_group):
		if player.get_multiplayer_authority() == peer and player is Node3D:
			if player.has_method(&"reach_origin"):
				return player.call(&"reach_origin")
			return (player as Node3D).global_position
	return null


func _units_at(location: StringName) -> int:
	var total: int = 0
	for qty: int in inventory.contents_at(location).values():
		total += qty
	return total


func _on_peer_disconnected(peer: int) -> void:
	_snapshot_granted.erase(peer)
	_oversize_reported.erase(peer)


## Host: `peer`'s world is up and it gets events from now on (is_peer_ready()); the snapshot
## brings it to the current seq first.
func _on_peer_level_ready(peer: int) -> void:
	if is_host():
		send_snapshot(peer)


## Host, once this node is up: a snapshot to every peer that was ready before it (the events
## reach them from now on, _event_targets()).
func _snapshot_ready_peers() -> void:
	if not is_inside_tree() or not is_host():
		return
	for peer: int in _event_targets():
		send_snapshot(peer)


static func _is_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME


static func _snapshot_name_ok(value: Variant) -> bool:
	return _is_id(value) and String(value).length() <= SNAPSHOT_MAX_ID_LENGTH


static func _as_id(value: Variant) -> StringName:
	return StringName(value) if _is_id(value) else &""


static func _as_int(value: Variant) -> int:
	return int(value) if typeof(value) == TYPE_INT else 0
