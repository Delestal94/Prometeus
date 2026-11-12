class_name CompanyDoor
extends Node
## The customer's door in the company world (expansion D-0340, D-0815.b; contract
## docs/expansion-distritos/diseno/red-autoridad.md, row 20).
##
## Child of CompanyRoot on every peer, named NODE_NAME (add_to()). Every DeliveryHouse of this world is kept here as
## it enters the tree (the Centro cells put HouseMap.instance()s in it a few per frame, each named by its house id,
## D-0314) and forgotten as it leaves. On the host each one gets DeliveryHouse.door_check = ring(): a box rung at a
## house settles the order it was dispatched for (order_for(): an order of a trip out, for this house, still out on
## the road or late); anything else is handed back (a box of another house's order, one nobody dispatched, a house
## with no order out). An empty-handed ring only rings, and a house takes any number of orders, the same day or the
## next (DeliveryHouse.door_check: the delivery run's door is unchanged).
##
## Settling (settle(), host): OrderSettlement.settle() on the trips' own book (CompanyTrips.book) with what the box
## holds (BoxToPackage.META_PACKED_BOX) against the order, its broken units (every unit of a wrecked box, broken_of())
## and the shed's minute (CompanyTrips.delivery_minute()); the Trip records it (Trip.record_settled()). The customer's
## money never goes into CompanyState straight: settle() is handed a Till that keeps each earn(), and the host
## publishes, in this order, order_delivered (CompanyOrdersNet: every peer closes the order in the shared book with
## the host's pay and stars, the box's units leave its stock and the host's reputation is taken) and one wallet_moved
## per payment (order_paid, then tip: CompanyNet.publish_wallet()). The reputation settle() moves is the host's, as
## an order_closed's; order_delivered carries the host's, absolute, to every peer.
##
## Every peer, on order_delivered (CompanyNet.event_applied): EventBus.order_delivered(order) and the customer's
## reaction at that house's door when the house is in this peer's tree (D-0817.b: OrderDoorReaction from the host's
## stars, cheer, shrug or angry, its line in this peer's language, its gesture and the resident's sound, the same seed
## and house on every peer). It names no autoload: EventBus and NetworkManager are reached by path (N-919).
##
## A script (the company-day bot) delivers through the game's path: take the DeliveryPackage off the van's rack
## (its InteractionArea's interact(player)), ring the DoorbellPoint of the order's house (house.doorbell.interact(
## player)); `settled` (host) or EventBus.order_delivered / CompanyNet.event_applied with order_delivered (every peer)
## say it went through, DeliveryHouse.wrong_package_offered that the box was handed back.

## Host: an order was settled at a door, with OrderSettlement.settle()'s result ({ok, paid, tip, reputation, kinds,
## lost, stars}), after its events went out.
signal settled(order_id: StringName, result: Dictionary)

const NODE_NAME: String = "CompanyDoor"
const HOUSE_GROUP: StringName = &"delivery_house"
## The door's scene (DoorReaction.react()) for each customer's reaction.
const SCENE_OF: Dictionary = {
	OrderDoorReaction.CHEER: DeliveryHouse.OUTCOME_OK,
	OrderDoorReaction.SHRUG: DeliveryHouse.OUTCOME_AT_RISK,
	OrderDoorReaction.ANGRY: DeliveryHouse.OUTCOME_RUINED,
}

## The business events, on every peer.
var net: CompanyNet = null
## Host: the trips out, whose book the door settles on. Null on a client.
var trips: CompanyTrips = null

## house id -> the DeliveryHouse of this world standing for it.
var _houses: Dictionary = {}
var _catalog: CompanyCatalog = null


## The door of `root`'s world: `company_net` on every peer, `company_trips` the host's (null on a client).
static func add_to(root: Node, company_net: CompanyNet, company_trips: CompanyTrips) -> CompanyDoor:
	var door := CompanyDoor.new()
	door.name = NODE_NAME
	door.net = company_net
	door.trips = company_trips
	root.add_child(door)
	return door


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for node: Node in get_tree().get_nodes_in_group(HOUSE_GROUP):
		_on_node_added(node)
	if net != null and not net.event_applied.is_connected(_on_event_applied):
		net.event_applied.connect(_on_event_applied)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if net != null and is_instance_valid(net) and net.event_applied.is_connected(_on_event_applied):
		net.event_applied.disconnect(_on_event_applied)
	for house: Variant in _houses.values():
		if is_instance_valid(house) and (house as DeliveryHouse).door_check.get_object() == self:
			(house as DeliveryHouse).door_check = Callable()
	_houses.clear()


## The DeliveryHouse standing for `house_id` in this world, or null when it isn't in the tree.
func house(house_id: StringName) -> DeliveryHouse:
	var found: Variant = _houses.get(house_id)
	return found as DeliveryHouse if is_instance_valid(found) else null


## True where orders are settled: the host (solo too) with its trips.
func is_host() -> bool:
	return net != null and is_instance_valid(net) and net.is_host() and trips != null and is_instance_valid(trips)


## Host, DeliveryHouse.door_check: `box` rung at `at` (the outcome its state gives is the house's, for its own
## sound; the door judges the box by TripCargo.is_broken()). True when it settled the order it was dispatched for
## (settle()), false when the house hands it back.
func ring(at: DeliveryHouse, box: DeliveryPackage, _outcome: StringName) -> bool:
	if box == null or at == null:
		return false
	var order_id: StringName = order_for(StringName(at.name), box)
	if order_id == &"":
		return false
	var packed: PackedBox = packed_box_of(box)
	return bool(settle(order_id, packed, broken_of(packed, TripCargo.is_broken(box)), box.package_id)["ok"])


## Host: the order `box` settles at house `house_id`: one of a trip out, for that house, not delivered yet, whose box
## is this one (the trips' book box_of(), or the box's own order label when the book has no box for it). &"" for none.
func order_for(house_id: StringName, box: DeliveryPackage) -> StringName:
	if not is_host() or box == null:
		return &""
	var label := StringName(box.get_meta(BoxToPackage.META_ORDER_ID, &""))
	for trip: Trip in trips.active_trips():
		for order_id: StringName in trip.order_ids:
			if order_id in trip.delivered_ids:
				continue
			if StringName(trips.book.get_order(order_id).get("house_id", "")) != house_id:
				continue
			var box_id: StringName = trips.book.box_of(order_id)
			if box_id == box.package_id or (box_id == &"" and label == order_id):
				return order_id
	return &""


## Host: the order `order_id` handed over in `packed` (the box `package_id`) with `broken` (one product id per broken
## unit): settled on the trips' book at the shed's minute and recorded on its Trip, then order_delivered and the
## wallet's movements go out (see above). OrderSettlement.settle()'s result; {ok: false} with nothing changed on a
## client, for an order no trip out carries, one the shared book has no longer out or late, or with no company.
func settle(order_id: StringName, packed: PackedBox, broken: Array, package_id: StringName) -> Dictionary:
	var failed: Dictionary = {"ok": false}
	if not is_host() or net.company == null or packed == null:
		return failed
	var trip: Trip = _trip_of(order_id)
	var shared: StringName = net.orders.book.state_of(order_id)
	if trip == null or (shared != Order.STATE_OUT and shared != Order.STATE_LATE):
		return failed
	# What would keep order_delivered from going out is checked before anything changes: refused after settling, the
	# shared book would keep the order out (-3 at the close) for a box already paid for and gone.
	if net.is_applying() or not CompanyOrdersNet.delivered_ok(_probe(order_id, package_id)):
		return failed
	var till := Till.new(net.company)
	var result: Dictionary = OrderSettlement.settle(
		trips.book, till, order_id, packed, trips.delivery_minute(), broken, _products_of(packed))
	if not bool(result["ok"]):
		return result
	trip.record_settled(order_id, trips.book)
	var order: Dictionary = trips.book.get_order(order_id)
	var penalties: Array = []
	penalties.assign(result["kinds"])
	var data: Dictionary = {
		"order": order_id, "package_id": package_id, "paid": int(result["paid"]), "tip": int(result["tip"]),
		"stars": int(result["stars"]), "quality": int(order.get("quality", 0)),
		"intact": bool(order.get("intact", true)), "penalties": penalties,
		"reputation": float(net.company.get(&"reputation")),
	}
	if not net.publish(CompanyOrdersNet.DELIVERED, data):
		push_error("CompanyDoor: order_delivered of %s did not go out (%s)" % [order_id, data])
	for entry: Array in till.earned:
		if not net.publish_wallet(int(entry[0]), StringName(entry[1])):
			# The customer paid: the host keeps it, and a mirror finds its wallet off at the next movement.
			push_warning("CompanyDoor: %s of %d for %s moved the host's wallet alone" % [entry[1], entry[0], order_id])
			net.company.call(&"earn", int(entry[0]), StringName(entry[1]))
	settled.emit(order_id, result)
	return result


## What `box` holds, from the box it was built from (BoxToPackage.META_PACKED_BOX); an empty box when it carries none
## (it then settles as the wrong box).
static func packed_box_of(box: DeliveryPackage) -> PackedBox:
	var saved: Variant = box.get_meta(BoxToPackage.META_PACKED_BOX, {}) if box != null else {}
	if saved is Dictionary and not (saved as Dictionary).is_empty():
		return PackedBox.from_dict(saved)
	return PackedBox.new()


## The broken units of a box handed over `wrecked` (TripCargo.is_broken(): ruined, or its contents out and not put
## back, care.needs_restore, the rule the trip's close uses): every unit of it, one product id per unit; none for a
## box only dented or open (it arrives whole: decisión 2026-11-11-puerta-del-cliente).
static func broken_of(packed: PackedBox, wrecked: bool) -> Array:
	var broken: Array = []
	if packed == null or not wrecked:
		return broken
	var contents: Dictionary = packed.contents()
	for product: StringName in contents:
		for _unit: int in int(contents[product]):
			broken.append(product)
	return broken


## An order_delivered for `order_id` and the box `package_id` with every number settle() can give in range: what
## delivered_ok() says of it is what it says of the real one for the ids and the host's reputation.
func _probe(order_id: StringName, package_id: StringName) -> Dictionary:
	return {
		"order": order_id, "package_id": package_id, "paid": 0, "tip": 0, "stars": CompanyTuning.STARS_MIN,
		"quality": 0, "intact": true, "penalties": [], "reputation": float(net.company.get(&"reputation")),
	}


## The trip out that carries `order_id`, or null.
func _trip_of(order_id: StringName) -> Trip:
	for trip: Trip in trips.active_trips():
		if order_id in trip.order_ids:
			return trip
	return null


## The catalog's definitions of the products in `packed` (what a broken unit costs, OrderPenalties).
func _products_of(packed: PackedBox) -> Dictionary:
	if _catalog == null:
		_catalog = CompanyCatalog.load_all()
	var products: Dictionary = {}
	for product: StringName in packed.contents():
		var definition: ProductDefinition = _catalog.product(product)
		if definition != null:
			products[product] = definition
	return products


## A house of this world enters the tree: kept by its id, and on the host its door is this one.
func _on_node_added(node: Node) -> void:
	var entered := node as DeliveryHouse
	if entered == null or entered.multiplayer != multiplayer:
		return
	var id := StringName(entered.name)
	_houses[id] = entered
	if not entered.tree_exiting.is_connected(_forget):
		entered.tree_exiting.connect(_forget.bind(entered))
	if is_host():
		entered.door_check = ring


func _forget(gone: DeliveryHouse) -> void:
	var id := StringName(gone.name)
	if _houses.get(id) == gone:
		_houses.erase(id)


## Every peer: an order was delivered here too. EventBus hears it and the customer reacts at the door.
func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind != CompanyOrdersNet.DELIVERED:
		return
	var order_id := StringName(data["order"])
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.emit_signal(&"order_delivered", order_id)
	var at: DeliveryHouse = house(StringName(net.orders.book.get_order(order_id).get("house_id", "")))
	if at != null and at.reaction != null:
		var shown: Dictionary = reaction_of(data, at.house_index, _session_seed())
		# The sound follows the customer's verdict, not the box's looks: a box in good shape missing a product is no cheer.
		at.play_reaction_sound(shown["scene"])
		at.reaction.react(shown["scene"], tr(shown["line"]))


## The customer's reaction to an order_delivered at the house numbered `house_index` (D-0817.b): {reaction, scene,
## line} (line a translation key), from the host's stars and penalties, the same for one seed and house on every peer.
static func reaction_of(data: Dictionary, house_index: int, session_seed: int) -> Dictionary:
	var reaction: StringName = OrderDoorReaction.reaction_for(int(data.get("stars", 0)))
	var client: StringName = ClientComplaints.client_for(&"", session_seed, house_index)
	var result: Dictionary = {"kinds": data.get("penalties", [])}
	return {
		"reaction": reaction,
		"scene": SCENE_OF.get(reaction, DeliveryHouse.OUTCOME_OK),
		"line": OrderDoorReaction.line_for(reaction, result, client, session_seed, house_index),
	}


func _session_seed() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	var value: Variant = network.get(&"world_seed") if network != null else 0
	return int(value) if value is int else 0


## What settle() hands OrderSettlement as the company: each payment is kept for the wallet's events instead of being
## earned here; the reputation goes to the host's company at once.
class Till:
	extends RefCounted
	## [amount, reason] per payment, in the order settle() made them.
	var earned: Array = []
	var _company: Object

	func _init(company: Object) -> void:
		_company = company

	func earn(amount: int, reason: StringName) -> void:
		if amount > 0:
			earned.append([amount, reason])

	func add_reputation(delta: float) -> float:
		return float(_company.call(&"add_reputation", delta))
