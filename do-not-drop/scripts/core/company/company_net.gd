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
## on the host). Sending the snapshot and applying it is D-2004: it answers
## snapshot_requested and calls resume_after_snapshot() on the peer.
##
## Child of the company world (CompanyRoot today, CompanyWorld once it exists), always named
## "CompanyNet" so its RPC path is the same on every peer. The owner hands it the live
## `inventory` and the `stations` lookup. It names no autoload (lesson N-919): NetworkManager
## is reached by path, only to know which peers have their world up.
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
## Host: `peer` saw an event skipped and asked for the whole state, and the rate limit let
## the request through. D-2004 answers with the snapshot.
signal snapshot_requested(peer: int)

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
## there it is also the last one sent. Starts at 0; the first event is 1. Keeping it across a
## loaded day (section 3) is D-0206 / D-2004.
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

## Product ids of the catalog, read once from PRODUCTS_DIR ({StringName: true}).
static var _known_products: Dictionary = {}
static var _catalog_read: bool = false


func _ready() -> void:
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
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
## through less than SNAPSHOT_INTERVAL_MSEC before; then emits snapshot_requested. The host
## never asks itself. True when it went through.
func grant_snapshot(peer: int, now_msec: int) -> bool:
	if peer == multiplayer.get_unique_id():
		return false
	var last: int = int(_snapshot_granted.get(peer, -1))
	if last >= 0 and now_msec - last < SNAPSHOT_INTERVAL_MSEC:
		return false
	_snapshot_granted[peer] = now_msec
	snapshot_requested.emit(peer)
	return true


## Client, joining (CompanyRoot): its stock is not the host's until the snapshot comes, so
## every event is held until resume_after_snapshot(). The host sends that snapshot once this
## peer is ready (D-2004); only if it hasn't come within SNAPSHOT_INTERVAL_MSEC is it asked for.
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


## Client, for D-2004: a snapshot taken at `snapshot_seq` is in place here. Events up to it are
## in the snapshot and dropped; those held since the gap are applied in order. If one is still
## missing, the rest stay held and a snapshot is asked for again at once.
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


static func _is_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME


static func _as_id(value: Variant) -> StringName:
	return StringName(value) if _is_id(value) else &""


static func _as_int(value: Variant) -> int:
	return int(value) if typeof(value) == TYPE_INT else 0
