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
## Host only; nothing here changes state by itself. The answer is what happened: RESULT_* or the reason.

const RESULT_LOADED: StringName = &"loaded"
const RESULT_UNLOADED: StringName = &"unloaded"
const RESULT_PUSHED: StringName = &"pushed"
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
