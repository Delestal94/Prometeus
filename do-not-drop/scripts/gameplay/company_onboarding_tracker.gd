class_name CompanyOnboardingTracker
extends Node
## Follows what this player does in the company's world and keeps the first week's guide line
## (expansion D-1901, diseno/onboarding.md §4): CompanyOnboarding.current() over this peer's copy, no RPC.
##
## Done for this player (each one ticked once, in the profile: UnlockManager.mark_tip_seen("company_onboard_<id>"),
## local like the trap cards, so who already learned it in another company does not see it again):
##   stock_pallet  a units_moved from this peer's hands to a shelf slot (shelf:...);
##   pick          a units_moved from a shelf slot into this peer's hands;
##   pack          an order of the day is packed (packed, out or delivered in the books it reads);
##   drive         this player sits in a seat while an order is out;
##   deliver       an order is delivered;
##   return        a trip came back through the gate after that (CompanyTripsView.trip_closed, or the host's closed
##                 trips growing);
##   unload        the supplier pallets of a day from 2 on were waiting and are not any more;
##   order_more    this peer's supplier order (supplier_ordered with its peer) after the row showed.
## The books count only from what this peer first saw (its first poll, or each snapshot): who joins mid-day does not
## tick the crew's earlier work. "At the packing table" is not known yet (the line shows pack after pick instead).
## Past the first week, or with every row done, the tracker stops (no poll, no event handler).
## pack, deliver and return read the company's books: in F1 the table and the door are not per player events yet,
## so a crew ticks them together (onboarding §3 asks per player; that waits for the table's and the door's events).
## restock and fill have no trigger yet (the table's supplies and the box's Q are host-side only): their rows wait
## (D-1901 notes them in tareas-slatex.md).
##
## The line goes out through `line_changed` (the screen draws it, CompanyOnboardingLine) and `ticked` says which
## objective was just done. Autoloads by path (lesson N-919).

signal line_changed(line: Dictionary)
signal ticked(id: StringName)

const POLL_SECONDS: float = 0.25
## Order states that mean the box was packed (`late` is the overdue state, not a delivery: a late order may still be
## open, so a packed late one is told by its box_id).
const PACKED_STATES: Array[StringName] = [&"packed", &"out", &"delivered"]
const DELIVERED: StringName = &"delivered"
const OUT: StringName = &"out"

var net: CompanyNet
## Returns this peer's own player (or null).
var player_of: Callable = Callable()
## Returns the OrderBooks to read (the shared one and, on the host, CompanyTrips' own).
var books_of: Callable = Callable()
## Returns the host's CompanyTrips (null on a client): its closed trips.
var trips_of: Callable = Callable()
## Where the done steps are remembered: an object with seen_tips and mark_tip_seen() (UnlockManager by default;
## a test hands its own). Null keeps them only in memory.
var profile: Object = null
## This peer's id; unset, the multiplayer's (a test drives it).
var peer_id: Callable = Callable()

var _seen: Dictionary = {}
var _line: Dictionary = {}
var _poll: float = 0.0
var _unload_waiting: bool = false
## Trips back through the gate seen since deliver was ticked (return needs one after it).
var _trips_back: int = 0
var _closed_at_deliver: int = -1
## Order id -> what it was when this peer first saw it (its first poll, or a snapshot): only what changes after
## counts, so who joins a company mid-day does not tick the crew's work as their own.
var _baseline: Dictionary = {}
var _has_baseline: bool = false
var _dirty: bool = true


## The tracker and its line on the company's world `root` (CompanyRoot): reads its net, player, books and trips
## when used. Returns the tracker.
static func add_to(root: Node) -> CompanyOnboardingTracker:
	var tracker := CompanyOnboardingTracker.new()
	tracker.name = "Onboarding"
	tracker.net = root.get(&"net") as CompanyNet
	tracker.player_of = func() -> Node:
		return root.get(&"player") as Node if is_instance_valid(root) else null
	tracker.trips_of = func() -> CompanyTrips:
		return root.get(&"trips") as CompanyTrips if is_instance_valid(root) else null
	tracker.books_of = func() -> Array:
		var out: Array = []
		var company_net: CompanyNet = tracker.net
		if company_net != null and company_net.orders != null and company_net.orders.book != null:
			out.append(company_net.orders.book)
		var trips: CompanyTrips = tracker.trips_of.call()
		if trips != null and trips.book != null:
			out.append(trips.book)
		return out
	var view: Node = root.get(&"trips_view") as Node
	root.add_child(tracker)
	if view != null and view.has_signal(&"trip_closed"):
		view.connect(&"trip_closed", tracker._on_trip_closed)
	var layer := CanvasLayer.new()
	layer.name = "OnboardingLayer"
	root.add_child(layer)
	var line := CompanyOnboardingLine.new()
	line.name = "OnboardingLine"
	layer.add_child(line)
	tracker.line_changed.connect(line.show_line)
	tracker.ticked.connect(line.tick)
	line.show_line(tracker.line())
	return tracker


func _ready() -> void:
	if profile == null:
		profile = get_node_or_null(^"/root/UnlockManager")
	_load_seen()
	if net != null:
		net.event_applied.connect(_on_event_applied)
		net.company_state_restored.connect(_on_restored)
	refresh()


## The line showing now ({} for none).
func line() -> Dictionary:
	return _line


func is_done(id: StringName) -> bool:
	return bool(_seen.get(id, false))


## Ticks `id` for this player (once): the profile keeps it. True when it was new.
func mark(id: StringName) -> bool:
	if is_done(id) or not CompanyOnboarding.KEYS.has(id):
		return false
	_seen[id] = true
	if profile != null and profile.has_method(&"mark_tip_seen"):
		profile.call(&"mark_tip_seen", CompanyOnboarding.tip_id(id))
	ticked.emit(id)
	return true


## Looks at the world (what the events do not say) and recomputes the line.
func refresh() -> void:
	_dirty = false
	if is_over():
		_stop()
		return
	_poll_world()
	var next: Dictionary = CompanyOnboarding.current(_player_ctx(), _company_ctx(), _seen)
	if next != _line:
		_line = next
		line_changed.emit(_line)


## Nothing left to teach: past the first week, or every row done. The tracker then stops looking.
func is_over() -> bool:
	if _day() > CompanyOnboarding.GUIDE_LAST_DAY:
		return true
	for id: StringName in CompanyOnboarding.KEYS:
		if not is_done(id):
			return false
	return true


func _stop() -> void:
	set_process(false)
	if net != null and net.event_applied.is_connected(_on_event_applied):
		net.event_applied.disconnect(_on_event_applied)
	if not _line.is_empty():
		_line = {}
		line_changed.emit(_line)


## The poll runs every POLL_SECONDS, or sooner after an event marked something to look at.
func _process(delta: float) -> void:
	_poll += delta
	if _poll >= POLL_SECONDS or (_dirty and _poll >= POLL_SECONDS * 0.2):
		_poll = 0.0
		refresh()


func _load_seen() -> void:
	_seen.clear()
	if profile == null:
		return
	var tips: Variant = profile.get(&"seen_tips")
	if not tips is Dictionary:
		return
	for id: StringName in CompanyOnboarding.KEYS:
		if bool((tips as Dictionary).get(CompanyOnboarding.tip_id(id), false)):
			_seen[id] = true


func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	var ticked_now: bool = false
	if kind == &"units_moved":
		var hands: String = String(CompanyNet.hands_location(_peer()))
		var from: String = String(data.get("from", ""))
		var to: String = String(data.get("to", ""))
		if from == hands and to.begins_with("shelf:"):
			ticked_now = mark(CompanyOnboarding.STOCK_PALLET)
		elif from.begins_with("shelf:") and to == hands:
			ticked_now = mark(CompanyOnboarding.PICK)
	elif kind == CompanySupplierNet.ORDERED and int(data.get("peer", 0)) == _peer():
		if _line.get("id", &"") == CompanyOnboarding.ORDER_MORE:
			ticked_now = mark(CompanyOnboarding.ORDER_MORE)
	# A tick moves the line at once; anything else waits for the poll (events come many a second).
	if ticked_now:
		refresh()
	else:
		_dirty = true


## A snapshot replaced the books: what they hold now is the new baseline (nothing in them was this peer's doing).
func _on_restored(_snapshot_seq: int) -> void:
	_has_baseline = false
	_dirty = true


func _on_trip_closed(_trip_id: StringName, _vehicle_id: StringName, _failed: Array) -> void:
	if is_done(CompanyOnboarding.DELIVER):
		_trips_back += 1
	_dirty = true


## What no event of this peer says: the books, the seat, the trips back, the supplier pallets.
func _poll_world() -> void:
	var road: Array[StringName] = [
		CompanyOnboarding.PACK, CompanyOnboarding.DRIVE, CompanyOnboarding.DELIVER, CompanyOnboarding.RETURN,
	]
	if not road.all(is_done):
		_poll_books()
	if not is_done(CompanyOnboarding.UNLOAD):
		_poll_unload()


## pack, drive, deliver and return from the books, counting only what changed since the baseline.
func _poll_books() -> void:
	var orders: Dictionary = _orders()
	if not _has_baseline:
		_baseline = orders
		_has_baseline = true
		return
	var packed: bool = false
	var out: bool = false
	var delivered: bool = false
	for id: StringName in orders:
		var now: Dictionary = orders[id]
		var before: Dictionary = _baseline.get(id, {"state": Order.STATE_OPEN, "box_id": ""})
		packed = packed or (_was_packed(now) and not _was_packed(before))
		out = out or (now["state"] == OUT and before["state"] != OUT)
		delivered = delivered or (now["state"] == DELIVERED and before["state"] != DELIVERED)
	if packed:
		mark(CompanyOnboarding.PACK)
	var player: Node = _player()
	if out and player != null:
		var seat: NodePath = player.get(&"seat_node_path")
		if not seat.is_empty():
			mark(CompanyOnboarding.DRIVE)
	if delivered and mark(CompanyOnboarding.DELIVER):
		_closed_at_deliver = _closed_count()
		_trips_back = 0
	var back: bool = _trips_back > 0 or (_closed_at_deliver >= 0 and _closed_count() > _closed_at_deliver)
	if is_done(CompanyOnboarding.DELIVER) and back:
		mark(CompanyOnboarding.RETURN)


static func _was_packed(order: Dictionary) -> bool:
	return PACKED_STATES.has(order["state"]) or String(order.get("box_id", "")) != ""


## The host's trips back through the gate (-1 on a client: the view's trip_closed counts there).
func _closed_count() -> int:
	var trips: CompanyTrips = trips_of.call() as CompanyTrips if trips_of.is_valid() else null
	return trips.closed_trips().size() if trips != null else -1


## unload: from its first day, the supplier pallets were waiting and are not any more.
func _poll_unload() -> void:
	if _day() < int(CompanyOnboarding.LATER[CompanyOnboarding.UNLOAD]):
		return
	var waiting: bool = _pallets_waiting()
	if _unload_waiting and not waiting:
		mark(CompanyOnboarding.UNLOAD)
	_unload_waiting = waiting


func _player_ctx() -> Dictionary:
	var player: Node = _player()
	if player == null:
		return {}
	var seat: NodePath = player.get(&"seat_node_path")
	var holding: bool = is_instance_valid(player.get(&"carried_package"))
	if net != null and net.inventory != null:
		holding = holding or not net.inventory.contents_at(CompanyNet.hands_location(_peer())).is_empty()
	return {"driving": not seat.is_empty(), "packing": false, "holding": holding}


func _company_ctx() -> Dictionary:
	var triggers: Dictionary = {}
	if _unload_waiting:
		triggers[CompanyOnboarding.UNLOAD] = true
	var order_more: bool = not is_done(CompanyOnboarding.ORDER_MORE)
	if order_more and _day() >= int(CompanyOnboarding.LATER[CompanyOnboarding.ORDER_MORE]) and _short_today():
		triggers[CompanyOnboarding.ORDER_MORE] = true
	var pallet_left: bool = is_done(CompanyOnboarding.STOCK_PALLET) or _pallet_units() > 0
	return {"day": _day(), "pallet_left": pallet_left, "triggers": triggers}


## Order id -> {state, box_id} over every book read (a later book wins: CompanyTrips' is the one packing moves).
func _orders() -> Dictionary:
	var out: Dictionary = {}
	var books: Array = books_of.call() if books_of.is_valid() else []
	for book: Variant in books:
		if not book is OrderBook:
			continue
		for order: Variant in (book as OrderBook).to_dict().get("orders", []):
			if order is Dictionary:
				var entry: Dictionary = order
				var id := StringName(entry.get("id", ""))
				out[id] = {"state": StringName(entry.get("state", "")), "box_id": String(entry.get("box_id", ""))}
	return out


## Units still on a supplier pallet (pallet:<id>, before it is opened and put away).
func _pallet_units() -> int:
	if net == null or net.inventory == null:
		return 0
	var total: int = 0
	var stock: Dictionary = net.inventory.to_dict().get("stock", {})
	for product: Variant in stock:
		var places: Dictionary = net.inventory.locations_of(StringName(product))
		for place: StringName in places:
			if String(place).begins_with("pallet:"):
				total += int(places[place])
	return total


func _pallets_waiting() -> bool:
	return net != null and net.inventory != null and not CompanyShed.pallets_in(net.inventory).is_empty()


## Today's pending orders miss stock (StockAlert, as the Stock sheet marks it).
func _short_today() -> bool:
	if net == null or net.inventory == null or net.orders == null:
		return false
	var context: Dictionary = StockBoard.context(net.inventory, net.orders.book, {}, {}, _day())
	return not (context["shortages"] as Array).is_empty()


func _day() -> int:
	var company: Object = net.company if net != null else null
	return int(company.get(&"day")) if company != null else 1


func _player() -> Node:
	var player: Node = player_of.call() as Node if player_of.is_valid() else null
	return player if player != null and is_instance_valid(player) and not player.is_queued_for_deletion() else null


func _peer() -> int:
	if peer_id.is_valid():
		return int(peer_id.call())
	return multiplayer.get_unique_id() if is_inside_tree() and multiplayer != null else 1
