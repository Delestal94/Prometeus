class_name PickingCartUse
extends RefCounted
## What one use of a picking cart asks of the host (expansion D-0610.b), the cart's counterpart of what
## CompanyRoot does for a shelf (ShelfPicking): the cart points say who used which cart and how
## (PickingCartPoint.used), this turns it into the host's own requests on that peer's behalf
## (CompanyNet.request_for), which check reach, hands and room again before anything moves.
##
## - the platform: with something in the hands it loads the cart (units_store, the hands' product, as
##   many as fit); with empty hands it unloads (units_take, the first product on the cart, up to the hand
##   limit). PickingCart plans what to ask for and says why it cannot (empty, full, hands_busy...).
## - the handle: cart_push away from the player, one step (CompanyCarts).
## - a take point (D-0610.c2): units_take of that product, up to the hand limit, also onto hands that
##   already hold some of it; other products in the hands are hands_busy.
##
## - the restock point (D-0610.c2.c): the first product on the cart goes back to the shelf slot labeled for it
##   with the most room that is within the player's reach: units_take cart -> hands, then units_store
##   hands -> slot, both as that peer's own requests (no new RPC). If the shelf refuses, the units go back
##   on the cart, so nothing is lost or left in the hands.
##
## Host only; nothing here changes state by itself. The answer is what happened: RESULT_* or the reason.

const RESULT_LOADED: StringName = &"loaded"
const RESULT_UNLOADED: StringName = &"unloaded"
const RESULT_PUSHED: StringName = &"pushed"
const RESULT_RESTOCKED: StringName = &"restocked"
## No shelf slot labeled for the product has room.
const REASON_NO_SHELF: StringName = &"no_shelf"
## The request reached the host's checks and they said no (out of reach, no room, blocked...).
const REASON_REFUSED: StringName = &"refused"
const REASON_NO_CART: StringName = &"no_cart"


## `from` is where the user stands (world), `peer` who they are, `product` what a take point hands out.
## Returns RESULT_* or a reason.
static func use(net: CompanyNet, view: PickingCartView, action: StringName, peer: int,
		from: Vector3, product: StringName = &"") -> StringName:
	if net == null or not net.is_host() or view == null or not is_instance_valid(view) \
			or not view.is_inside_tree():
		return REASON_NO_CART
	match action:
		PickingCartPoint.ACTION_LOAD:
			return _load_or_unload(net, view.cart, peer)
		PickingCartPoint.ACTION_PUSH:
			return _push(net, view, peer, from)
		PickingCartPoint.ACTION_TAKE:
			return _take(net, view.cart, peer, product)
		PickingCartPoint.ACTION_RESTOCK:
			return _restock(net, view, peer)
	return REASON_NO_CART


static func _load_or_unload(net: CompanyNet, cart: PickingCart, peer: int) -> StringName:
	var hands: StringName = CompanyNet.hands_location(peer)
	var loading: bool = not net.inventory.contents_at(hands).is_empty()
	var plan: Dictionary = (cart.plan_load(net.inventory, hands) if loading
		else cart.plan_unload(net.inventory, hands))
	if plan.has("reason"):
		return plan["reason"]
	var before: int = net.seq
	net.request_for(peer, &"units_store" if loading else &"units_take",
		{"station": cart.location(), "product": plan["product"], "qty": plan["qty"]})
	if net.seq == before:
		return REASON_REFUSED
	return RESULT_LOADED if loading else RESULT_UNLOADED


static func _take(net: CompanyNet, cart: PickingCart, peer: int, product: StringName) -> StringName:
	if product == &"":
		return PickingCart.REASON_EMPTY
	var plan: Dictionary = cart.plan_unload(net.inventory, CompanyNet.hands_location(peer), product)
	if plan.has("reason"):
		return plan["reason"]
	var before: int = net.seq
	net.request_for(peer, &"units_take", {"station": cart.location(), "product": plan["product"], "qty": plan["qty"]})
	return RESULT_UNLOADED if net.seq != before else REASON_REFUSED


## Away from the player: from where they stand to the cart, flattened, in the shed's frame.
static func _push(net: CompanyNet, view: PickingCartView, peer: int, from: Vector3) -> StringName:
	var shed := view.get_parent() as Node3D
	if shed == null or not shed.is_inside_tree():
		return REASON_NO_CART
	var away: Vector3 = view.position - shed.to_local(from)
	var before: int = net.seq
	net.request_for(peer, CompanyCarts.PUSH, {"cart": view.cart.id, "dir": Vector3(away.x, 0.0, away.z)})
	return RESULT_PUSHED if net.seq != before else REASON_REFUSED


## The first product on the cart back on a shelf: the slot labeled for it with room, nearest to the cart.
## The units pass through the peer's hands (take, then store), the way the checks want them; a refused
## store puts them back on the cart.
static func _restock(net: CompanyNet, view: PickingCartView, peer: int) -> StringName:
	var cart: PickingCart = view.cart
	var hands: StringName = CompanyNet.hands_location(peer)
	var plan: Dictionary = cart.plan_unload(net.inventory, hands)
	if plan.has("reason"):
		return plan["reason"]
	var product: StringName = plan["product"]
	var target: Dictionary = _shelf_slot_for(view, net.inventory, product)
	if target.is_empty():
		return REASON_NO_SHELF
	var held: int = net.inventory.count(product, hands)
	var qty: int = mini(int(plan["qty"]), int(target["room"]))
	var before: int = net.seq
	net.request_for(peer, &"units_take", {"station": cart.location(), "product": product, "qty": qty})
	if net.seq == before:
		return REASON_REFUSED
	var moved: int = net.inventory.count(product, hands) - held
	before = net.seq
	net.request_for(peer, &"units_store", {"station": target["station"], "product": product, "qty": moved})
	if net.seq != before:
		return RESULT_RESTOCKED
	net.request_for(peer, &"units_store", {"station": cart.location(), "product": product, "qty": moved})
	return REASON_REFUSED


## {station, room} of the shed's slot labeled for `product` with free space, nearest to the cart, or {}.
static func _shelf_slot_for(view: PickingCartView, stock: Inventory, product: StringName) -> Dictionary:
	var shed := view.get_parent() as CompanyShed
	if shed == null:
		return {}
	var best: Dictionary = {}
	var best_distance: float = INF
	for uid: StringName in shed.shelves:
		var shelf: Shelf = shed.shelves[uid] as Shelf
		var point: ShedPiecePoint = shed.use_points.get(uid) as ShedPiecePoint
		var slot: int = shelf.find_slot(product) if shelf != null else -1
		if slot == -1 or point == null or not point.is_inside_tree() or shelf.free_space(stock, slot) <= 0:
			continue
		var distance: float = point.global_position.distance_to(view.global_position)
		if distance < best_distance:
			best_distance = distance
			best = {"station": ShelfPicking.station_id(uid, slot), "room": shelf.free_space(stock, slot)}
	return best
