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
##   deliver       an order is delivered (also late);
##   return        a trip came back through the gate (CompanyTripsView.trip_closed, or the host's closed trips);
##   unload        the supplier pallets of a day from 2 on were waiting and are not any more;
##   order_more    this peer's supplier order (supplier_ordered with its peer) after the row showed.
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
const DONE_STATES: Array[StringName] = [&"packed", &"out", &"delivered", &"late"]
const DELIVERED_STATES: Array[StringName] = [&"delivered", &"late"]

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
var _returned: bool = false


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
	_poll_world()
	var next: Dictionary = CompanyOnboarding.current(_player_ctx(), _company_ctx(), _seen)
	if next != _line:
		_line = next
		line_changed.emit(_line)


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= POLL_SECONDS:
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
	if kind == &"units_moved":
		var hands: String = String(CompanyNet.hands_location(_peer()))
		var from: String = String(data.get("from", ""))
		var to: String = String(data.get("to", ""))
		if from == hands and to.begins_with("shelf:"):
			mark(CompanyOnboarding.STOCK_PALLET)
		elif from.begins_with("shelf:") and to == hands:
			mark(CompanyOnboarding.PICK)
	elif kind == CompanySupplierNet.ORDERED and int(data.get("peer", 0)) == _peer():
		if _line.get("id", &"") == CompanyOnboarding.ORDER_MORE:
			mark(CompanyOnboarding.ORDER_MORE)
	refresh()


func _on_trip_closed(_trip_id: StringName, _vehicle_id: StringName, _failed: Array) -> void:
	_returned = true
	refresh()


## What no event of this peer says: the books, the seat, the trips back, the supplier pallets.
func _poll_world() -> void:
	var states: Dictionary = _order_states()
	if _any(states, DONE_STATES):
		mark(CompanyOnboarding.PACK)
	var player: Node = _player()
	if player != null and _any(states, [&"out"]):
		var seat: NodePath = player.get(&"seat_node_path")
		if not seat.is_empty():
			mark(CompanyOnboarding.DRIVE)
	if _any(states, DELIVERED_STATES):
		mark(CompanyOnboarding.DELIVER)
	var trips: CompanyTrips = trips_of.call() as CompanyTrips if trips_of.is_valid() else null
	if trips != null and not trips.closed_trips().is_empty():
		_returned = true
	if _returned and is_done(CompanyOnboarding.DELIVER):
		mark(CompanyOnboarding.RETURN)
	var waiting: bool = _pallets_waiting()
	if _unload_waiting and not waiting and _day() >= int(CompanyOnboarding.LATER[CompanyOnboarding.UNLOAD]):
		mark(CompanyOnboarding.UNLOAD)
	_unload_waiting = waiting and _day() >= int(CompanyOnboarding.LATER[CompanyOnboarding.UNLOAD])


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
	if _day() >= int(CompanyOnboarding.LATER[CompanyOnboarding.ORDER_MORE]) and _short_today():
		triggers[CompanyOnboarding.ORDER_MORE] = true
	return {"day": _day(), "pallet_left": _pallet_units() > 0, "triggers": triggers}


## Order id -> state over every book read (a later book wins: CompanyTrips' is the one packing moves).
func _order_states() -> Dictionary:
	var out: Dictionary = {}
	var books: Array = books_of.call() if books_of.is_valid() else []
	for book: Variant in books:
		if not book is OrderBook:
			continue
		for order: Variant in (book as OrderBook).to_dict().get("orders", []):
			if order is Dictionary:
				out[StringName((order as Dictionary).get("id", ""))] = StringName((order as Dictionary).get("state", ""))
	return out


static func _any(states: Dictionary, wanted: Array) -> bool:
	for id: StringName in states:
		if wanted.has(states[id]):
			return true
	return false


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
