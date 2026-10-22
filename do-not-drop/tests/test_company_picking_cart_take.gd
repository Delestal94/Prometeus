extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_picking_cart_take.gd
##
## Picking one product off a picking cart by aiming at it (expansion D-0610.c2.a: picking_cart_view.gd
## take points, picking_cart_point.gd ACTION_TAKE, picking_cart_use.gd, CompanyShed.cart_used):
## - the cart has one take point per product on it, at the middle of that product's cubes (inside the
##   platform), in the order of the slots; the others have no product, no prompt and cannot be used;
## - a take point's prompt names its product and differs from the platform's;
## - with empty hands a take point unloads THAT product (not the first one), up to the hand limit, as one
##   units_take; the points follow what stays on the cart;
## - onto hands that hold some of the same product it tops them up to the hand limit; with another product
##   in the hands (or one no longer on the cart) it is hands_busy, and a point with no product is empty:
##   nothing moves;
## - a take point's `used` reaches CompanyShed.cart_used with its product;
## - a second peer fed the host's events draws the same take points (product and spot) after every use;
## - the total of units never changes.
## Loading, the platform's unload, pushing and the snapshot: test_company_picking_cart_world.

const HEN: StringName = &"hen"
const LAMP: StringName = &"antique_lamp"
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
	await _test_take()
	if _failures == 0:
		print("PASS: a picking cart hands out the product the player aims at, the same on every peer")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_take() -> void:
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
	_expect(view != null, "The default shed has its picking cart")
	if view == null:
		return
	_expect(view.take_points.size() == CompanyTuning.CART_MAX_UNITS, "One take point per slot at most (%d)"
		% view.take_points.size())
	_expect(_products(view).is_empty(), "An empty cart has no take point in use")
	for point: PickingCartPoint in view.take_points:
		_expect(point.get_prompt() == "" and not point.can_interact(null),
			"An unused take point has no prompt and cannot be used")

	var hands: StringName = CompanyNet.hands_location(1)
	_player_at = view.global_position + Vector3(-1.2, 1.5, 0.0)
	var units_before: int = _net.inventory.total_units()
	_give(HEN, 4)
	_use(PickingCartPoint.ACTION_LOAD)
	_give(LAMP, 2)
	_use(PickingCartPoint.ACTION_LOAD)
	_expect(view.slot_products() == [LAMP, LAMP, HEN, HEN, HEN, HEN], "Loaded 2 lamps and 4 hens (%s)"
		% [view.slot_products()])

	# One point per product, over its own cubes.
	_expect(_products(view) == [LAMP, HEN], "Two take points: lamp, then hen (%s)" % [_products(view)])
	_expect_centres(view, "after loading")
	var lamp_point: PickingCartPoint = view.take_point_of(LAMP)
	var hen_point: PickingCartPoint = view.take_point_of(HEN)
	_expect(lamp_point != null and hen_point != null and lamp_point.position != hen_point.position,
		"Each product has its own point, apart from the other's")
	if lamp_point == null or hen_point == null:
		return
	_expect(lamp_point.get_prompt() != "" and lamp_point.get_prompt() != view.load_point.get_prompt()
		and lamp_point.get_prompt().contains(PickingCartPoint.product_name(LAMP))
		and hen_point.get_prompt().contains(PickingCartPoint.product_name(HEN)),
		"A take point's prompt names its product (%s / %s)" % [lamp_point.get_prompt(), hen_point.get_prompt()])
	_same_as_mirror("after loading")

	# The point says which product: CompanyShed.cart_used carries it.
	var heard: Array = []
	_shed.cart_used.connect(func(cart_id: StringName, action: StringName, peer_id: int, _from: Vector3,
			product: StringName) -> void:
		heard.append([cart_id, action, peer_id, product]))
	hen_point.used.emit(CART, PickingCartPoint.ACTION_TAKE, 1, _player_at, hen_point.product)
	_expect(heard == [[CART, PickingCartPoint.ACTION_TAKE, 1, HEN]],
		"A take point's use reaches the shed with its product (%s)" % [heard])

	# Empty hands: the hens, not the first product (lamps).
	var seq_take: int = _net.seq
	_expect(_use(PickingCartPoint.ACTION_TAKE, HEN) == PickingCartUse.RESULT_UNLOADED and _net.seq == seq_take + 1,
		"Aiming at the hens takes them, as one event")
	_expect(_net.inventory.count(HEN, hands) == CompanyTuning.HAND_MAX_UNITS
		and _net.inventory.count(LAMP, hands) == 0 and view.slot_products() == [LAMP, LAMP],
		"The hands hold 4 hens, both lamps stay on the cart (%s)" % [view.slot_products()])
	_expect(_products(view) == [LAMP], "Only the lamps' point is left (%s)" % [_products(view)])
	_expect_centres(view, "after taking the hens")
	_same_as_mirror("after taking the hens")

	# Another product in the hands, or one not on the cart: nothing moves.
	var seq_busy: int = _net.seq
	_expect(_use(PickingCartPoint.ACTION_TAKE, LAMP) == PickingCart.REASON_HANDS_BUSY,
		"With hens in the hands the lamps are hands_busy")
	_expect(_use(PickingCartPoint.ACTION_TAKE, HEN) == PickingCart.REASON_HANDS_BUSY,
		"Hens are no longer on the cart: the hens in the hands are in the way (PickingCart.plan_unload)")
	_expect(_use(PickingCartPoint.ACTION_TAKE, &"") == PickingCart.REASON_EMPTY, "A point with no product: empty")
	_expect(_net.seq == seq_busy and view.slot_products() == [LAMP, LAMP]
		and _net.inventory.count(HEN, hands) == CompanyTuning.HAND_MAX_UNITS, "None of those moved anything")

	# Same product in the hands: topped up to the hand limit.
	_use(PickingCartPoint.ACTION_LOAD)
	_expect(view.slot_products() == [LAMP, LAMP, HEN, HEN, HEN, HEN] and _net.inventory.contents_at(hands).is_empty(),
		"The hens went back on the cart")
	_give(HEN, 1)
	_mirror_note()
	_expect(_use(PickingCartPoint.ACTION_TAKE, HEN) == PickingCartUse.RESULT_UNLOADED
		and _net.inventory.count(HEN, hands) == CompanyTuning.HAND_MAX_UNITS
		and view.cart.contents(_net.inventory).get(HEN, 0) == 1,
		"Holding one hen, the point tops the hands up to 4 and leaves one hen (%s)" % [view.slot_products()])
	_expect(_products(view) == [LAMP, HEN], "Both points stay while both products are on the cart")
	_expect_centres(view, "after topping up")
	_same_as_mirror("after topping up")
	_expect(_net.inventory.total_units() == units_before + 7,
		"No unit was created or lost (%d)" % _net.inventory.total_units())

	for node: Node in [_mirror_shed, _mirror, _shed, _net]:
		node.free()


# --- Helpers ---


func _view(shed: CompanyShed) -> PickingCartView:
	return shed.cart_views.get(CART) as PickingCartView


## Units into the hands of peer 1 on both peers, with no event (the way a shelf would have, minus the event).
func _give(product: StringName, qty: int) -> void:
	var hands: StringName = CompanyNet.hands_location(1)
	_net.inventory.receive(product, qty, hands)
	_mirror.inventory.receive(product, qty, hands)


## The mirror's shed redraws its cart from its own Inventory, as a units event would make it.
func _mirror_note() -> void:
	_mirror_shed.refresh_stock(_mirror.inventory)


## One use of the cart by peer 1 at `_player_at`.
func _use(action: StringName, product: StringName = &"") -> StringName:
	return PickingCartUse.use(_net, _view(_shed), action, 1, _player_at, product)


## The products of the take points in use, in order.
func _products(view: PickingCartView) -> Array[StringName]:
	var found: Array[StringName] = []
	for point: PickingCartPoint in view.take_points:
		if point.product != &"":
			found.append(point.product)
	return found


## Every point in use stands at the middle of its product's cubes, inside the platform.
func _expect_centres(view: PickingCartView, when: String) -> void:
	var slots: Array[StringName] = view.slot_products()
	for product: StringName in _products(view):
		var sum := Vector3.ZERO
		var count: int = 0
		for slot: int in slots.size():
			if slots[slot] == product:
				sum += PickingCartView.slot_centre(slot)
				count += 1
		var point: PickingCartPoint = view.take_point_of(product)
		_expect(count > 0 and point.position.is_equal_approx(sum / float(count)),
			"The %s point is over its cubes %s (%s)" % [product, when, point.position])
		_expect(absf(point.position.x) < PickingCartView.LENGTH * 0.5
			and absf(point.position.z) < PickingCartView.WIDTH * 0.5 and point.position.y > PickingCartView.DECK_TOP,
			"The %s point is over the platform %s" % [product, when])


## What a peer offers to take: each point's product and spot.
func _take_look(shed: CompanyShed) -> Array:
	var look: Array = []
	for point: PickingCartPoint in _view(shed).take_points:
		look.append([point.product, point.position])
	return look


func _same_as_mirror(when: String) -> void:
	_expect(_take_look(_shed) == _take_look(_mirror_shed),
		"The second peer offers the same take points %s: %s vs %s" % [when, _take_look(_mirror_shed),
		_take_look(_shed)])
