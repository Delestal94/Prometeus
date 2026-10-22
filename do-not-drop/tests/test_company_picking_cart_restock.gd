extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_picking_cart_restock.gd
##
## Putting a cart's stock back on its shelf (expansion D-0610.c2.c: picking_cart_view.gd restock_point,
## picking_cart_point.gd ACTION_RESTOCK, picking_cart_use.gd _restock):
## - the cart has a restock point at its far end with a prompt of its own;
## - using it sends the first product on the cart (text order) to the shelf slot labeled for it, as the
##   peer's own units_take + units_store, so the hands end up empty and the cart and the shelf agree;
## - only what fits goes: a slot with room for fewer units takes that many and the rest stays on the cart;
## - a full slot (no room) is no_shelf and nothing moves; an empty cart is empty; other units in the hands
##   are hands_busy;
## - out of reach of the shelf the store is refused and the units are put back on the cart, nothing lost;
## - a second peer fed the host's events draws the same cart;
## - the total of units never changes.
## Loading, taking, pushing: test_company_picking_cart_world / _take.

const HEN: StringName = &"hen"
const CART: StringName = &"cart_1"

var _failures: int = 0
var _net: CompanyNet
var _shed: CompanyShed
var _mirror: CompanyNet
var _mirror_shed: CompanyShed
var _player_at: Vector3 = Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_restock()
	if _failures == 0:
		print("PASS: a picking cart puts its stock back on the shelf, the same on every peer")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_restock() -> void:
	var state := DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(state)
	var stock: Inventory = state.stock()
	_net = CompanyNet.new()
	_net.name = "TakeNet"
	_net.company = state
	_net.inventory = stock
	root.add_child(_net)
	_shed = CompanyShed.new()
	_shed.name = "HostShed"
	root.add_child(_shed)
	_shed.follow(_net)
	_shed.rebuild(state, stock)
	_net.stations = _shed.station_for
	_net.player_origin = func(_peer: int) -> Variant: return _player_at
	_net.event_applied.connect(func(event_seq: int, kind: StringName, data: Dictionary) -> void:
		_mirror._receive(event_seq, kind, data))
	_mirror = CompanyNet.new()
	_mirror.name = "MirrorNet"
	_mirror.company = state
	_mirror.inventory.from_dict(stock.to_dict())
	root.add_child(_mirror)
	_mirror_shed = CompanyShed.new()
	_mirror_shed.name = "MirrorShed"
	root.add_child(_mirror_shed)
	_mirror_shed.follow(_mirror)
	_mirror_shed.rebuild(state, _mirror.inventory)
	await process_frame

	var view: PickingCartView = _view(_shed)
	_expect(view != null and view.restock_point != null, "The default shed's cart has a restock point")
	if view == null or view.restock_point == null:
		return
	_expect(view.restock_point.get_prompt() != "" and view.restock_point.get_prompt() != view.load_point.get_prompt(),
		"The restock point's prompt is its own (%s)" % view.restock_point.get_prompt())

	var hands: StringName = CompanyNet.hands_location(1)
	var slot_where: Dictionary = _slot_of(HEN)
	_expect(not slot_where.is_empty(), "The default shed has a shelf slot for hens")
	if slot_where.is_empty():
		return
	var shelf: Shelf = _shed.shelves[slot_where["uid"]] as Shelf
	var slot: int = slot_where["slot"]
	var shelf_station: Dictionary = _shed.station_for(ShelfPicking.station_id(slot_where["uid"], slot))
	_player_at = view.global_position + Vector3(-1.2, 1.5, 0.0)
	# Stand where both the cart and the shelf are in reach.
	_player_at = (view.global_position + shelf_station["spot"]) * 0.5 + Vector3(0.0, 1.5, 0.0)

	# An empty cart has nothing to put back.
	_expect(_use() == PickingCart.REASON_EMPTY, "An empty cart: empty")

	# Load 3 hens and put them back: the shelf slot gains them, hands and cart end up empty.
	var on_shelf: int = shelf.count(_net.inventory, slot)
	_give(HEN, 3)
	_use_action(PickingCartPoint.ACTION_LOAD)
	_expect(view.cart.count(_net.inventory) == 3, "3 hens on the cart")
	var shelf_room: int = shelf.free_space(_net.inventory, slot)
	if shelf_room < 3:
		# Make room: park units from the slot in limbo (they stay in the Inventory).
		_off(HEN, 3 - shelf_room, shelf.location(slot))
		on_shelf = shelf.count(_net.inventory, slot)
	_mirror_note()
	var result: StringName = _use()
	_expect(result == PickingCartUse.RESULT_RESTOCKED, "Restocking reports restocked (%s)" % result)
	_expect(view.cart.count(_net.inventory) == 0 and _net.inventory.contents_at(hands).is_empty()
		and shelf.count(_net.inventory, slot) == on_shelf + 3,
		"The 3 hens are on the shelf, none left in the hands or on the cart")
	_same_cart("after restocking")

	# Only what fits goes: leave room for 2 of 4 hens (fill the slot first).
	var topped: int = shelf.free_space(_net.inventory, slot) - 2
	_net.inventory.receive(HEN, topped, shelf.location(slot))
	_mirror.inventory.from_dict(_net.inventory.to_dict())
	_give(HEN, 4)
	_use_action(PickingCartPoint.ACTION_LOAD)
	_mirror_note()
	_expect(_use() == PickingCartUse.RESULT_RESTOCKED and view.cart.count(_net.inventory) == 2
		and shelf.free_space(_net.inventory, slot) == 0, "A slot with room for 2 takes 2, 2 stay on the cart")
	_expect(_net.inventory.contents_at(hands).is_empty(), "Nothing left in the hands")
	# Now the slot is full: no_shelf, nothing moves.
	var seq: int = _net.seq
	_expect(_use() == PickingCartUse.REASON_NO_SHELF and _net.seq == seq and view.cart.count(_net.inventory) == 2,
		"A full slot is no_shelf and nothing moves")

	# Other units in the hands are in the way.
	_give(&"antique_lamp", 1)
	_expect(_use() == PickingCart.REASON_HANDS_BUSY and _net.seq == seq, "Another product in the hands: hands_busy")
	_off(&"antique_lamp", 1, hands)

	# Out of reach of the shelf: the units are put back on the cart.
	_off(HEN, 2, shelf.location(slot))
	_mirror_note()
	_player_at = view.global_position + Vector3(-1.2, 1.5, 0.0) + Vector3(0.0, 0.0, 60.0)
	var cart_before: int = view.cart.count(_net.inventory)
	var total_before: int = _net.inventory.total_units()
	_expect(_use() == PickingCartUse.REASON_REFUSED, "Out of reach is refused")
	_expect(view.cart.count(_net.inventory) == cart_before and _net.inventory.contents_at(hands).is_empty(),
		"Refused: the cart keeps its units, the hands stay empty")
	_expect(_net.inventory.total_units() == total_before, "No unit was created or lost (%d)"
		% _net.inventory.total_units())

	for node: Node in [_mirror_shed, _mirror, _shed, _net]:
		node.free()


# --- Helpers ---


func _view(shed: CompanyShed) -> PickingCartView:
	return shed.cart_views.get(CART) as PickingCartView


## {uid, slot} of a shelf slot labeled for `product`, or {}.
func _slot_of(product: StringName) -> Dictionary:
	for uid: StringName in _shed.shelves:
		var slot: int = (_shed.shelves[uid] as Shelf).find_slot(product)
		if slot != -1:
			return {"uid": uid, "slot": slot}
	return {}


## Units into the hands of peer 1 on both peers, with no event.
func _give(product: StringName, qty: int) -> void:
	var hands: StringName = CompanyNet.hands_location(1)
	_net.inventory.receive(product, qty, hands)
	_mirror.inventory.receive(product, qty, hands)


func _mirror_note() -> void:
	_mirror_shed.refresh_stock(_mirror.inventory)


func _use_action(action: StringName) -> StringName:
	return PickingCartUse.use(_net, _view(_shed), action, 1, _player_at)


## One use of the restock point by peer 1 at `_player_at`.
func _use() -> StringName:
	return _use_action(PickingCartPoint.ACTION_RESTOCK)


func _same_cart(when: String) -> void:
	_expect(_view(_shed).slot_products() == _view(_mirror_shed).slot_products(),
		"The second peer draws the same cart %s" % when)


## Parks `qty` units of `product` from `location` in limbo on both peers (still counted, out of the way).
func _off(product: StringName, qty: int, location: StringName) -> void:
	_net.inventory.move(product, qty, location, &"limbo")
	_mirror.inventory.move(product, qty, location, &"limbo")
