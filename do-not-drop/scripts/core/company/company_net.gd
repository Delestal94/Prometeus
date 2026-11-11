class_name CompanyNet
extends Node
## Business events of the company mode, by reliable RPC with a sequence number (D-2003).
##
## The contract is docs/expansion-distritos/diseno/red-autoridad.md (D-2001). A client never writes business state, not
## even ahead of time: it asks the host (_request, through RpcGuard), the host checks the request with what only it
## knows (stock, reach, hands), applies the resulting event and sends it, numbered, to every ready peer (_apply_event),
## where the same code applies it again. A refused request tells only its sender why (_rejected); a dropped one
## (malformed, over budget) tells nobody. Events carry `seq`. Reliable delivery loses nothing, so the only gap is an
## event sent before this peer's world was up: a peer that sees a number skipped holds what comes next and asks for a
## snapshot (snapshot_request, at most one per SNAPSHOT_INTERVAL_MSEC per peer on the host).
##
## The snapshot (D-2004, the contract's section 3) is the whole business state at the host's current seq (snapshot()).
## The host sends it to a peer when that peer's world comes up (NetworkManager.peer_level_ready) and when it asks; it
## travels compressed, in chunks of at most SNAPSHOT_CHUNK_BYTES (_snapshot), on the same reliable channel as the
## events, so it lands before any event that comes after it. The peer holds every event until the last chunk is in, puts
## the host's state in place of its own (apply_snapshot(): one company_state_restored, no fact signal), drops the held
## events the snapshot covers and applies the rest in order.
##
## Child of the company world (CompanyRoot today, CompanyWorld once it exists), always named "CompanyNet" so its RPC
## path is the same on every peer. The owner hands it the live `inventory`, the `company` state, the `stations` lookup
## and any other snapshot part (add_snapshot_part()). It names no autoload (lesson N-919): NetworkManager is reached
## by path, only to know which peers have their world up.
##
## Every kind belongs to one domain, and CompanyNet only puts them together and routes them (D-0254). A domain is a
## script that declares its kinds (REQUEST_KINDS, CRITICAL_KINDS when losing one leaves a player stuck, rule 8,
## EVENT_KINDS, and HOST_EVENT_KINDS for the events its host rules publish()) and checks and applies them itself:
## the units (rows 5 to 7), the shed layout (D-0910), the packing tables' box_* (rows 9 to 15b, D-0715) and
## package_ack (D-0715.b), cart_push (D-0610.b; units move with units_take / units_store at the station cart:<id>),
## the pallet jack, the forklift and the truck's pallets (D-0605.b), the trips out (D-0302.2.a), the day's orders
## (D-0813, D-0851), supplier_order (D-0603.b.2), wallet_moved (D-0517), shop_buy (D-0518, the host's only), trip_tow
## (D-0307.1: its effects go out as wallet_moved and trip_closed) and units_spoiled (D-0616.b, CompanyColdNet); each
## is one of the variables below. CompanyNet's own kinds are snapshot_request, clock_anchor and day_phase.
## A task that adds an action adds its kinds to its domain's lists and to that domain's check and apply: nothing
## here changes, as long as the domain already has its branch for that direction and its call takes `kind`. This
## file still changes for a new domain (its lists in the four constants below and its branches), for a domain's first
## request (Trips, Orders, Wallet, Cold) or first event (Packages, Tow) and for a second kind of a domain whose call
## here takes no `kind` (requests: Packages, Carts, Supplier, Shop, Tow; events: Units, Carts, Supplier, Wallet,
## Shop, Cold). test_company_net_domains fails if a kind has no branch.
##
## Units on the floor (D-2006) lie in bundles, floor:<n>, each made by a units_moved with its `pos` (a drop, or
## what a peer that left held), kept on every peer (floor_bundles) and taken back with units_take.
##
## Events nobody asks for (the contract's "without a client request") are the host's own rules: they go out
## through publish(), the same path, and only the kinds of HOST_EVENT_KINDS may.
##
## A host rule that reacts to a business fact listens to event_applied, never to Inventory.stock_changed: that one
## fires in the middle of applying an event, and a request made there is refused (it would number its event first).

## Every peer, the host too, right after an event changed the state here: presentation (HUD, sounds)
## and the host's rules that react to a fact (see above: save_closed_day, CompanyDayOrders.plan) listen to this.
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
## Units from the sender's hands onto the floor (CompanyUnitsNet.DROP): {product, qty, pos: Vector3, rid}.
const UNITS_DROP: StringName = CompanyUnitsNet.DROP
## The host's day clock changed pace: {minute, speed, paused} (D-0219, GameClock.apply_anchor()).
const CLOCK_ANCHOR: StringName = &"clock_anchor"
## The day moved on, or the shed froze or thawed: {day, phase, frozen, lag, frozen_at[, summary]}
## (D-0203, DayCycle.apply_phase()).
const DAY_PHASE: StringName = &"day_phase"
## The host's wallet moved: {amount (signed), reason, money (its balance after), minute} (D-0517, CompanyWalletNet).
const WALLET: StringName = CompanyWalletNet.MOVED
## CompanyNet's own kinds: asking for a snapshot; the clock's pace and the day's phases, host events both.
const OWN_REQUEST_KINDS: Array[StringName] = [SNAPSHOT_REQUEST]
const OWN_EVENT_KINDS: Array[StringName] = [CLOCK_ANCHOR, DAY_PHASE]
## Request kinds the host takes (the contract's section 2 whitelist): its own and each domain's. Anything else
## is dropped. A kind is in one list only, so _handle_request() hands it to one domain (test_company_net_domains).
## Every domain declares the four lists (empty where it has none) and each list below sums all thirteen, so a
## domain's first critical or host kind changes nothing here either.
const REQUEST_KINDS: Array[StringName] = (
	OWN_REQUEST_KINDS + CompanyUnitsNet.REQUEST_KINDS + CompanyLayoutNet.REQUEST_KINDS
	+ CompanyTableNet.REQUEST_KINDS + CompanyPackages.REQUEST_KINDS + CompanyCarts.REQUEST_KINDS
	+ CompanyPallets.REQUEST_KINDS + CompanyTripsView.REQUEST_KINDS + CompanyOrdersNet.REQUEST_KINDS
	+ CompanySupplierNet.REQUEST_KINDS + CompanyWalletNet.REQUEST_KINDS + CompanyShopNet.REQUEST_KINDS
	+ CompanyTowNet.REQUEST_KINDS + CompanyColdNet.REQUEST_KINDS)
## Requests whose loss leaves a player stuck (rule 8: letting go; a package ack is sent once).
## They spend RpcGuard's critical reserve once the sender's budget is gone.
const CRITICAL_KINDS: Array[StringName] = (
	CompanyUnitsNet.CRITICAL_KINDS + CompanyLayoutNet.CRITICAL_KINDS
	+ CompanyTableNet.CRITICAL_KINDS + CompanyPackages.CRITICAL_KINDS + CompanyCarts.CRITICAL_KINDS
	+ CompanyPallets.CRITICAL_KINDS + CompanyTripsView.CRITICAL_KINDS + CompanyOrdersNet.CRITICAL_KINDS
	+ CompanySupplierNet.CRITICAL_KINDS + CompanyWalletNet.CRITICAL_KINDS + CompanyShopNet.CRITICAL_KINDS
	+ CompanyTowNet.CRITICAL_KINDS + CompanyColdNet.CRITICAL_KINDS)
## Event kinds every peer applies: its own and each domain's, one list each as for the requests.
const EVENT_KINDS: Array[StringName] = (
	OWN_EVENT_KINDS + CompanyUnitsNet.EVENT_KINDS + CompanyLayoutNet.EVENT_KINDS
	+ CompanyTableNet.EVENT_KINDS + CompanyPackages.EVENT_KINDS + CompanyCarts.EVENT_KINDS
	+ CompanyPallets.EVENT_KINDS + CompanyTripsView.EVENT_KINDS + CompanyOrdersNet.EVENT_KINDS
	+ CompanySupplierNet.EVENT_KINDS + CompanyWalletNet.EVENT_KINDS + CompanyShopNet.EVENT_KINDS
	+ CompanyTowNet.EVENT_KINDS + CompanyColdNet.EVENT_KINDS)
## Kinds the host may publish() with no request, its own rules (clock, phases, trips, truck, orders, its wallet:
## publish_wallet(), the supplier order of the day's close: SupplierAutoOrderHook); never units_moved.
const HOST_EVENT_KINDS: Array[StringName] = (
	OWN_EVENT_KINDS + CompanyUnitsNet.HOST_EVENT_KINDS + CompanyLayoutNet.HOST_EVENT_KINDS
	+ CompanyTableNet.HOST_EVENT_KINDS + CompanyPackages.HOST_EVENT_KINDS + CompanyCarts.HOST_EVENT_KINDS
	+ CompanyPallets.HOST_EVENT_KINDS + CompanyTripsView.HOST_EVENT_KINDS + CompanyOrdersNet.HOST_EVENT_KINDS
	+ CompanySupplierNet.HOST_EVENT_KINDS + CompanyWalletNet.HOST_EVENT_KINDS + CompanyShopNet.HOST_EVENT_KINDS
	+ CompanyTowNet.HOST_EVENT_KINDS + CompanyColdNet.HOST_EVENT_KINDS)
## Host: one snapshot request per peer in this long (a broken client asks once per event); the client waits as long.
const SNAPSHOT_INTERVAL_MSEC: int = 5000
## Events a peer holds while it waits for a snapshot. Past this the oldest go: a later snapshot covers them anyway.
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
const SNAPSHOT_KEYS: Array[String] = ["seq", "inventory", "company", "floor"]
const HANDS_PREFIX: String = "hands:"
## Inventory locations of the bundles of units on the floor: floor:<n> (D-2006).
const FLOOR_PREFIX: String = FloorBundles.PREFIX

const REASON_BAD_DATA: StringName = &"bad_data"
const REASON_NO_STATION: StringName = &"no_station"
const REASON_OUT_OF_REACH: StringName = &"out_of_reach"
const REASON_NOT_ENOUGH: StringName = &"not_enough"
const REASON_HANDS_FULL: StringName = &"hands_full"
const REASON_HANDS_BUSY: StringName = &"hands_busy"
const REASON_WRONG_PRODUCT: StringName = &"wrong_product"
const REASON_NO_ROOM: StringName = &"no_room"

## The stock every units event moves. The owner sets it (CompanyRoot: CompanyState.stock()); the host and each client
## hold their own copy, kept equal by the events. Writing it back to CompanyState before a save is D-0206's.
var inventory: Inventory = Inventory.new()
## The CompanyState node (by reference, never by autoload name), or null. The host puts its to_dict() in every snapshot;
## a client loads the host's into it, its only write there (rule 1). The owner sets it on every peer (CompanyRoot).
var company: Object = null
## Where each bundle of units on the floor lies (D-2006), kept by the units_moved events and
## the snapshot on every peer. Read it, never write it: only events change it.
var floor_bundles: FloorBundles = FloorBundles.new()
## The day's clock (D-0219), or null: clock_anchor events land in its apply_anchor(). Set on
## every peer by GameClock.attach(), which also adds the anchor to the snapshot.
var clock: GameClock = null
## The day's phases (D-0203), or null: day_phase events land in its apply_phase(). Set on every peer
## by DayCycle.attach(), which also adds the phase to the snapshot.
var day_cycle: DayCycle = null
## The trips out (D-0302.2.a) or null, trip_* events land in its apply_trip(); set by its attach().
var trips_view: CompanyTripsView = null
## The units requests (rows 5 to 7) and the reach every request at a station is measured with (rule 4).
var units: CompanyUnitsNet = CompanyUnitsNet.new()
## The snapshot on its way (D-2004): the host's rate limit and chunks, the client's wait and the chunks it joins.
var sync: CompanySnapshotSync = CompanySnapshotSync.new()
## The shed layout's build requests (host) and events (every peer) on `company`'s layout (D-0910).
var build: CompanyLayoutNet = CompanyLayoutNet.new()
## The shared packing tables' requests (host), events (every peer) and state (D-0715); in every snapshot.
var table: CompanyTableNet = CompanyTableNet.new()
## Where the picking carts stand after a push (D-0610.b); a snapshot part.
var carts: CompanyCarts = CompanyCarts.new()
## The supplier pallets and the pallet jack (D-0605.b); a snapshot part.
var pallets: CompanyPallets = CompanyPallets.new()
## The day's orders (D-0813): the book every peer shares, the host's plan and their events; in every snapshot.
var orders: CompanyOrdersNet = CompanyOrdersNet.new()
## The supplier orders (D-0603.b.2) on the calendar `supplier.schedule` (the truck's); a snapshot part.
var supplier: CompanySupplierNet = CompanySupplierNet.new()
## The wallet's own events (D-0517): wallet_moved, built and applied there (publish_wallet()).
var wallet: CompanyWalletNet = CompanyWalletNet.new()
## The shop's purchases (D-0518): only the host's go through; what they change is in `company`'s snapshot part.
var shop: CompanyShopNet = CompanyShopNet.new()
## The tow home (D-0307.1): a peer asks, the host's world (CompanyTow) does it; no event of its own.
var tow: CompanyTowNet = CompanyTowNet.new()
## Host: size of the chunks a snapshot is cut into, up to SNAPSHOT_CHUNK_BYTES (tests force small ones).
var snapshot_chunk_bytes: int = SNAPSHOT_CHUNK_BYTES
## Host: a station id -> what the host needs to check a request at it (rule 4), as Callable(station) -> Dictionary:
##   location  StringName  where its units are counted (pallet:<id>, shelf:<id>_<slot>...)
##   spot      Vector3     where reach is measured to: the slot or cell, not the furniture
##   accepts   StringName  optional: the only product a store may put there (a slot label)
##   capacity  int         optional: units it holds at most (0 or missing: no limit)
## A packing table's location is table:<uid>, its spot the box's hollow (D-0715). {} for an
## unknown station. Unset (no stations exist yet), every request names an unknown
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
## Snapshot parts kept outside CompanyNet, {key: [take, put]} (add_snapshot_part()).
var _parts: Dictionary = {}

func _init() -> void:
	sync.started = _start_waiting
	add_snapshot_part(CompanyTableNet.SNAPSHOT_KEY, func() -> Variant: return table.to_dict(),
		func(value: Variant) -> bool: return table.put_snapshot(value))
	table.packages.ask = request
	table.bundles = floor_bundles
	add_snapshot_part(CompanyCarts.SNAPSHOT_KEY, carts.to_dict, carts.put_snapshot)
	add_snapshot_part(CompanyPallets.SNAPSHOT_KEY, pallets.to_dict, pallets.put_snapshot)
	add_snapshot_part(CompanyOrdersNet.SNAPSHOT_KEY, orders.to_dict, orders.put_snapshot)
	add_snapshot_part(CompanySupplierNet.SNAPSHOT_KEY, supplier.to_dict, supplier.put_snapshot)


func _ready() -> void:
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	# A leaver lets go (D-2006): peer_removed comes with its player still there, and before a
	# dropped ghost's peer_disconnected (N-221); peer_returned for one back under the same id.
	var hooks: Dictionary = {
		&"peer_level_ready": _on_peer_level_ready, &"peer_removed": _on_peer_removed,
		&"peer_returned": _on_peer_returned,
	}
	for hook: StringName in hooks:
		if network != null and network.has_signal(hook) and not network.is_connected(hook, hooks[hook]):
			network.connect(hook, hooks[hook])
	# Peers already up when this world came up won't fire peer_level_ready again. Deferred: the
	# owner hands over the stock and the company right after adding this node.
	_snapshot_ready_peers.call_deferred()
	set_process(_awaiting_snapshot)


## Client: while it waits for a snapshot, asks again every SNAPSHOT_INTERVAL_MSEC (one lost,
## dropped by the host's limit, or never sent).
func _process(_delta: float) -> void:
	poll_snapshot(Time.get_ticks_msec())


## Asks the host for `kind` with `data` and returns the request id a refusal will carry (request_rejected), 0
## when there is nobody to ask (no tree, or a connection not up). On the host, and playing solo, it goes through
## the same checks at once, as this peer's own request (also when called while handling another peer's RPC).
## Nothing changes here until the host's event comes back (rule 1: no prediction). The actor is whoever sends
## it: a peer field in `data` means nothing. Called while an event is being applied (a stock_changed listener),
## it is refused with an error and returns 0.
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


## Host: a request for `peer` from code that runs on the host (D-0609); same checks, refusals carry rid 0.
func request_for(peer: int, kind: StringName, data: Dictionary = {}) -> bool:
	if not is_host() or not (peer == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer)):
		return false
	_take_request(peer, kind, data.merged({"rid": 0}, true))
	return true


## Host: an event no request led to, decided by the host's own rules (the clock's pace, D-0219;
## the day's phases, D-0203; the day's orders, D-0813). It takes the same path as one a request led
## to: applied here first, numbered, sent to every ready peer, then event_applied. False, with
## nothing sent, on a client, for a kind not in HOST_EVENT_KINDS, while another event is applied or when the
## state here doesn't take it.
func publish(kind: StringName, data: Dictionary) -> bool:
	if not is_host() or not HOST_EVENT_KINDS.has(kind):
		return false
	return _publish(kind, data)


## Host: moves the company's money by `amount` (signed; a charge may leave it in the red) for the ledger's `reason`
## on every peer, as one wallet_moved (D-0517). The way in for every payment, tip, rent or purchase no request led
## to (CompanyWalletNet), never CompanyState.earn() / charge() straight: those move the host's wallet alone. False,
## moving nothing, as publish(), and for 0, a reason that isn't a short id (CompanyWalletNet.reason_ok()) or no company.
func publish_wallet(amount: int, reason: StringName) -> bool:
	var data: Dictionary = wallet.moved(company, amount, reason) if is_host() else {}
	return not data.is_empty() and publish(WALLET, data)


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


## Client (and the host's own player): asks to let go of `qty` of `product` from its hands at
## `pos` (units_drop, critical). As request(): the request id, 0 with nobody to ask.
func drop(product: StringName, qty: int, pos: Vector3) -> int:
	return request(UNITS_DROP, {"product": product, "qty": qty, "pos": pos})


## Rule 4's shared check (CompanyUnitsNet.within_reach()): a spot (a pallet, a shelf slot, a grid cell) is within
## reach of `origin` (the player's reach origin) up to Interactable.REMOTE_REACH plus `slack`.
static func within_reach(origin: Vector3, spot: Vector3, slack: float = 0.0) -> bool:
	return CompanyUnitsNet.within_reach(origin, spot, slack)


## Host: where `peer` stood at its last units request, null if it never made one or it left
## (D-2006: what a leaver held is dropped there when its player is already gone).
func last_known_position(peer: int) -> Variant:
	return units.last_known_position(peer)


## Host: lets a snapshot request from `peer` through at `now_msec` unless one already went
## through less than SNAPSHOT_INTERVAL_MSEC before (CompanySnapshotSync.may_grant()); then sends it the snapshot
## and emits snapshot_requested. The host never asks itself. True when it went through; a snapshot that
## could not be sent (send_snapshot()) doesn't count, so the next request may try again.
func grant_snapshot(peer: int, now_msec: int) -> bool:
	if peer == multiplayer.get_unique_id() or not sync.may_grant(peer, now_msec) or not send_snapshot(peer):
		return false
	sync.granted(peer, now_msec)
	snapshot_requested.emit(peer)
	return true


## Adds a part to the snapshot under `key`: state an event of section 2 changes that lives
## outside CompanyNet's stock and `company` (the order book, the day phase and clock anchor,
## the trips out, pallets, packing tables, live boxes, units on the floor). `take` (host) is
## Callable() -> Variant and returns that part as plain data var_to_bytes keeps (no Object,
## no Callable); `put` (client) is Callable(value: Variant) -> bool, puts the host's value in
## place of what is there without firing fact signals, checks it like any data from the
## network (rule 5) and returns false when it doesn't fit (the client then waits for another
## snapshot). Every peer adds the same parts before its world is up. False, adding nothing,
## when `key` is taken or a callable isn't valid.
func add_snapshot_part(key: String, take: Callable, put: Callable) -> bool:
	if key.is_empty() or SNAPSHOT_KEYS.has(key) or _parts.has(key) or not take.is_valid() or not put.is_valid():
		return false
	_parts[key] = [take, put]
	return true


## Takes back the part under `key` (its owner left the world: GameClock._exit_tree()). Snapshots
## from now on go without it; a client applying one keeps what that part last put there. False
## when there is no such part (the keys CompanyNet fills itself are never parts).
func remove_snapshot_part(key: String) -> bool:
	return _parts.erase(key)


## Host: the business state as a snapshot carries it (section 3), as plain data:
##   seq        int: the last event it covers; the peer drops every event up to it
##   inventory  the live stock with its reservations (Inventory.to_dict())
##   company    CompanyState.to_dict() without its stored stock, calendar and pallets (live: `inventory`,
##              `supplier`, `pallets`):
##              money, day and clock, reputation, gates (the locks), fleet, employees,
##              milestones, layout, ledger. Missing without a `company`
##   floor      {floor:<n>: Vector3}: where each bundle on the floor lies (FloorBundles)
##   <part>     one per add_snapshot_part()
func snapshot() -> Dictionary:
	var stock: Inventory = inventory if inventory != null else Inventory.new()
	var data: Dictionary = {"seq": seq, "inventory": stock.to_dict(), "floor": floor_bundles.to_dict()}
	if company != null and company.has_method(&"to_dict"):
		var state: Variant = company.call(&"to_dict")
		if state is Dictionary:
			var stored: Dictionary = state
			stored.erase("inventory")
			stored.erase("supplier_calendar")
			stored.erase("pallets")
			stored.erase("cold_clocks")
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
## is over SNAPSHOT_MAX_BYTES or SNAPSHOT_MAX_CHUNKS (an error, once per peer until one fits:
## CompanySnapshotSync.pack(), which also numbers it).
func send_snapshot(peer: int) -> bool:
	if not is_host() or peer == multiplayer.get_unique_id():
		return false
	if not multiplayer.get_peers().has(peer):
		return false
	if _applying:
		push_error("CompanyNet: a snapshot for peer %d while an event is applied" % peer)
		return false
	var packed: Dictionary = sync.pack(peer, snapshot(), snapshot_chunk_bytes)
	if packed.is_empty():
		return false
	var id: int = packed["id"]
	var chunks: Array[PackedByteArray] = packed["chunks"]
	var size: int = packed["size"]
	for index: int in range(chunks.size()):
		_snapshot.rpc_id(peer, id, index, chunks.size(), size, chunks[index])
	return true


## A snapshot as _snapshot carries it, {size, chunks}, or {} over SNAPSHOT_MAX_BYTES or
## SNAPSHOT_MAX_CHUNKS (CompanySnapshot.pack()).
static func pack_snapshot(data: Dictionary, chunk_bytes: int = SNAPSHOT_CHUNK_BYTES) -> Dictionary:
	return CompanySnapshot.pack(data, chunk_bytes)


## The snapshot back from its joined chunks, or {} when they don't make one
## (CompanySnapshot.unpack()).
static func unpack_snapshot(packed: PackedByteArray, size: int) -> Dictionary:
	return CompanySnapshot.unpack(packed, size)


## A stock in Inventory.to_dict() form that came over the network (CompanySnapshot.stock_ok()).
static func stock_ok(value: Variant) -> bool:
	return CompanySnapshot.stock_ok(value)


## Client: puts the host's snapshot (snapshot()) in place of the business state here: the
## stock with its reservations, the floor bundles' positions (none if `floor` is missing), the
## company and every part, without a fact signal; emits
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
	var floor_part: Variant = data.get("floor", {})
	if not stock_ok(stock) or not state is Dictionary or inventory == null:
		return false
	if not FloorBundles.positions_ok(floor_part):
		return false
	_applying = true
	inventory.from_dict(stock)
	floor_bundles.from_dict(floor_part)
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
	sync.asked_msec = Time.get_ticks_msec()


## Client: while waiting for a snapshot, asks for one if SNAPSHOT_INTERVAL_MSEC passed since
## the last time (or it never asked: CompanySnapshotSync.ask_due()). `now_msec` is Time.get_ticks_msec()
## (_process), or a clock a test drives. True when it asked.
func poll_snapshot(now_msec: int) -> bool:
	if not _awaiting_snapshot or is_host() or not sync.ask_due(now_msec):
		return false
	return request(SNAPSHOT_REQUEST) > 0


## Client: a snapshot taken at `snapshot_seq` is in place here (apply_snapshot()). Events up to
## it are in the snapshot and dropped; those held since the gap are applied in order. If one is
## still missing, the rest stay held and a snapshot is asked for again at once.
func resume_after_snapshot(snapshot_seq: int) -> void:
	seq = snapshot_seq
	_awaiting_snapshot = false
	sync.asked_msec = -1
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


## True while an event changes the state here: nothing may request or publish now (a host rule
## the business tick polls checks it first, CompanyOrdersNet.poll()).
func is_applying() -> bool:
	return _applying


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
## CompanySnapshotSync.take_chunk() keeps it; with the last one in, the snapshot is applied. One that doesn't
## unpack or apply leaves this peer waiting: it asks again (poll_snapshot()).
@rpc("authority", "call_remote", "reliable")
func _snapshot(id: int, chunk: int, total: int, size: int, bytes: PackedByteArray) -> void:
	if not RpcGuard.from_host(self) or is_host():
		return
	var data: Variant = sync.take_chunk(id, chunk, total, size, bytes)
	if data is Dictionary and ((data as Dictionary).is_empty() or not apply_snapshot(data)):
		push_warning("CompanyNet: snapshot %d could not be applied; waiting for another" % id)
		_start_waiting()


## The requester: the host refused request `rid`. Draws a notice at most; no state changes.
@rpc("authority", "call_remote", "reliable")
func _rejected(rid: int, reason: StringName) -> void:
	if not RpcGuard.from_host(self):
		return
	request_rejected.emit(rid, reason)


## Host: what a valid request does, or the reason it is refused (&"" when it went through). The domain that
## declares the kind (its REQUEST_KINDS) checks it with what this node knows (on_request() or ask(): the stock,
## the sender's reach and hands), and no other: one branch per domain and no `else`. Its answer is the refusal
## or the one event, which _grant() publishes; the tow and the package ack have no event of their own.
func _handle_request(peer: int, kind: StringName, data: Dictionary) -> StringName:
	var reason: StringName = &""
	if CompanyUnitsNet.REQUEST_KINDS.has(kind):
		reason = _grant(units.on_request(self, peer, kind, data))
	elif CompanyLayoutNet.REQUEST_KINDS.has(kind):
		reason = _grant(build.on_request(self, peer, kind, data))
	elif CompanyTableNet.REQUEST_KINDS.has(kind):
		reason = _grant(table.on_request(self, peer, kind, data))
	elif CompanyPackages.REQUEST_KINDS.has(kind):
		reason = table.packages.ack(peer, data)
	elif CompanyCarts.REQUEST_KINDS.has(kind):
		reason = _grant(carts.on_request(self, peer, data))
	elif CompanyPallets.REQUEST_KINDS.has(kind):
		reason = _grant(pallets.on_request(self, peer, kind, data))
	elif CompanySupplierNet.REQUEST_KINDS.has(kind):
		reason = _grant(supplier.ask(self, peer, data))
	elif CompanyShopNet.REQUEST_KINDS.has(kind):
		reason = _grant(shop.ask(self, peer, data))
	elif CompanyTowNet.REQUEST_KINDS.has(kind):
		reason = tow.ask(peer, data)
	elif kind == SNAPSHOT_REQUEST:
		# Over the limit it is dropped, not refused: the client asks again on its own.
		grant_snapshot(peer, Time.get_ticks_msec())
	return reason


## Host: the refusal of a checked request ({reason}), or its one event ({reason: &"", kind, data})
## published (bad_data when the state here doesn't take it).
func _grant(ask: Dictionary) -> StringName:
	if ask["reason"] != &"":
		return ask["reason"]
	return &"" if _publish(ask["kind"], ask["data"]) else REASON_BAD_DATA


## Host: `peer` left (peer_removed or peer_disconnected, whichever comes first; the second finds empty hands and
## no forklift). What it held goes onto the floor, one units_moved per product into a new bundle at its feet
## (CompanyUnitsNet.feet_of()), else the origin; the forklift it drove stays where it is. Mid-event it waits for
## the next frame.
func _let_go(peer: int) -> void:
	if _applying:
		_let_go.call_deferred(peer)
		return
	var held: Dictionary = {}
	if is_host() and peer != multiplayer.get_unique_id() and inventory != null:
		held = inventory.contents_at(hands_location(peer))
		_grant(pallets.let_go(peer, units.station_of(self, {"station": CompanyPallets.FORK_STATION})))
	var pos: Variant = units.feet_of(self, peer) if not held.is_empty() else null
	for product: StringName in held:
		var at: Vector3 = pos if pos != null else Vector3.ZERO
		if _grant(units.dropped(self, peer, product, int(held[product]), at)) != &"":
			push_error("CompanyNet: what peer %d held (%s) could not be dropped" % [peer, product])
	units.forget(peer)


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
	var drifts: Array[bool] = [
		build.take_drift(), table.take_drift(), wallet.take_drift(), shop.take_drift(),
	]
	if drifts.has(true):
		# Its wallet was off the host's (set right now, D-0910, D-0517, D-0518): the missed history comes by snapshot.
		_start_waiting()
		poll_snapshot(Time.get_ticks_msec())


## The one place an event changes state, with the same code on every peer (rule 6: no game
## rule is checked again, only that the data fits). False when it doesn't. While it runs
## (Inventory signals fire inside it) no request or event may start: _applying.
## The domain that declares the kind (its EVENT_KINDS) applies it, and no other: one branch per domain and no
## `else`, so a kind added later can't fall into somebody else's code (test_company_layout_net reads it here).
func _apply_state(kind: StringName, data: Dictionary) -> bool:
	if inventory == null or not EVENT_KINDS.has(kind):
		return false
	_applying = true
	var applied: bool = false
	if CompanyUnitsNet.EVENT_KINDS.has(kind):
		applied = CompanyUnitsNet.apply(inventory, floor_bundles, data)
	elif kind == CLOCK_ANCHOR:
		if clock == null or not is_instance_valid(clock):
			push_warning("CompanyNet: a clock_anchor event but no clock here (GameClock.attach())")
		else:
			applied = clock.apply_anchor(data)
	elif kind == DAY_PHASE:
		if day_cycle == null or not is_instance_valid(day_cycle):
			push_warning("CompanyNet: a day_phase event but no day cycle here (DayCycle.attach())")
		else:
			applied = day_cycle.apply_phase(data)
	elif CompanyTripsView.EVENT_KINDS.has(kind):
		applied = is_instance_valid(trips_view) and trips_view.apply_trip(kind, data)
	elif CompanyLayoutNet.EVENT_KINDS.has(kind):
		applied = build.apply(company, kind, data)
		if applied and kind == CompanyLayoutNet.SOLD:
			table.forget(CompanyAsk.as_id(data.get("uid")))
	elif CompanyTableNet.EVENT_KINDS.has(kind):
		applied = table.apply(company, inventory, kind, data)
	elif CompanyCarts.EVENT_KINDS.has(kind):
		applied = carts.apply(data)
	elif CompanyPallets.EVENT_KINDS.has(kind):
		applied = pallets.apply(inventory, kind, data)
	elif CompanyOrdersNet.EVENT_KINDS.has(kind):
		applied = orders.apply(kind, data)
	elif CompanySupplierNet.EVENT_KINDS.has(kind):
		applied = supplier.apply(data)
	elif CompanyWalletNet.EVENT_KINDS.has(kind):
		applied = wallet.apply(company, data)
	elif CompanyShopNet.EVENT_KINDS.has(kind):
		applied = shop.apply(company, data)
	elif CompanyColdNet.EVENT_KINDS.has(kind):
		applied = CompanyColdNet.apply(inventory, data)
	if applied:
		floor_bundles.prune(inventory)
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


func _on_peer_disconnected(peer: int) -> void:
	sync.forget(peer)
	_let_go(peer)


## Host: `peer` left the session's roster (NetworkManager.peer_removed): it lets go (_let_go()).
func _on_peer_removed(peer: int) -> void:
	_let_go(peer)


## Host: `id` is back (NetworkManager.peer_returned). Back under the same id (Steam may hand it out
## again) it never left the roster, so what it held is let go here.
func _on_peer_returned(id: int, previous_id: int) -> void:
	if id == previous_id:
		_let_go(id)


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
