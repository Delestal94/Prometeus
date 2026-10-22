extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_picking_cart_world.gd
##
## The picking cart in the shed's world (expansion D-0610.b: picking_cart_view.gd, picking_cart_point.gd,
## picking_cart_use.gd, company_carts.gd, CompanyShed.station_for / cart_can_stand, CompanyNet cart_push):
## - the six slots of the platform are inside its rails, above its deck, and none overlaps another: six
##   units fit without any physics, so nothing can fall;
## - the default shed has one cart near the shelves; loading 4 + 2 units from the hands (the platform's
##   point, units_store at the station cart:cart_1) draws six cubes in their slots, sorted by product
##   whatever the order they came in, and they are still there after physics frames; the total of units
##   never changes;
## - the 7th unit is refused: by the plan (full) and, asked past it, by the host (no_room), nothing changes;
## - with empty hands the same point unloads (units_take) the first product, up to the hand limit;
## - reach is the host's: a player 40 m away is refused (out_of_reach) and nothing moves;
## - a push (the handle's point, cart_push) rolls the cart one step away from the player, the host
##   publishes one cart_moved, the cart's node, its reach spot and CompanyCarts agree; pushing it into a
##   shelf is refused (blocked); a malformed push is dropped and an unknown cart is no_station;
## - a second peer (its own CompanyNet fed the host's events in order, and its own CompanyShed following it)
##   draws the same cart: same spot, same cubes in the same slots, after loads, an unload and pushes;
## - a peer that joins late gets the cart's spot and units from the host's snapshot parts and draws the same;
##   a snapshot part that does not fit (bad id, NaN, too many carts) is refused and changes nothing.
## The ENet pair (a client's request over the wire) and two carts side by side: test_company_picking_cart_net.

const HEN: StringName = &"hen"
const LAMP: StringName = &"antique_lamp"
const CART: StringName = &"cart_1"
const EPS: float = 0.0001

var _failures: int = 0
var _net: CompanyNet
var _shed: CompanyShed
var _mirror: CompanyNet
var _mirror_shed: CompanyShed
var _events: Array = []
var _refusals: Array = []
## Where the test's player stands (its reach origin), as CompanyNet.player_origin answers.
var _player_at: Vector3 = Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_slots()
	await _test_world()
	if _failures == 0:
		print("PASS: the picking cart carries six units in fixed slots, refuses a 7th and rolls the same on all peers")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


# --- Slots ---


func _test_slots() -> void:
	_expect(PickingCartView.SLOT_X.size() * PickingCartView.SLOT_Z.size() == CompanyTuning.CART_MAX_UNITS,
		"The platform has one slot per unit the cart carries (%d)" % CompanyTuning.CART_MAX_UNITS)
	var half: float = PickingCartView.UNIT_SIZE * 0.5
	for slot: int in CompanyTuning.CART_MAX_UNITS:
		var at: Vector3 = PickingCartView.slot_centre(slot)
		_expect(at.y - half >= PickingCartView.DECK_TOP - EPS,
			"Slot %d stands on the deck, not under it (bottom %.3f)" % [slot, at.y - half])
		_expect(absf(at.x) + half <= PickingCartView.LENGTH * 0.5 - PickingCartView.RAIL_THICKNESS + EPS
			and absf(at.z) + half <= PickingCartView.WIDTH * 0.5 - PickingCartView.RAIL_THICKNESS + EPS,
			"Slot %d is inside the rails (%s)" % [slot, at])
		for other: int in range(slot + 1, CompanyTuning.CART_MAX_UNITS):
			var apart: Vector3 = (PickingCartView.slot_centre(other) - at).abs()
			_expect(apart.x >= PickingCartView.UNIT_SIZE - EPS or apart.z >= PickingCartView.UNIT_SIZE - EPS,
				"Slots %d and %d do not overlap" % [slot, other])
	_expect(PickingCartView.HEIGHT == 1.0 and PickingCartView.LENGTH == 1.0 and PickingCartView.WIDTH == 0.6,
		"The cart is 1.0 x 1.0 x 0.6 m (arte-pendiente/D-0610.md)")


# --- The world ---


func _test_world() -> void:
	var state := DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(state)
	var stock: Inventory = state.stock()
	_net = CompanyNet.new()
	_net.name = "CartNet"
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
	_net.request_rejected.connect(func(_rid: int, reason: StringName) -> void: _refusals.append(reason))
	_net.event_applied.connect(func(event_seq: int, kind: StringName, data: Dictionary) -> void:
		_events.append(event_seq)
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
	_expect(view != null and _shed.cart_views.size() == 1, "The default shed has one picking cart")
	if view == null:
		return
	var spot: Vector3 = _shed.cell_to_local(DefaultShed.load_default().cart_spots[0])
	_expect(view.position.is_equal_approx(spot) and view.cart.id == CART and view.cart.location() == &"cart:cart_1",
		"It stands at the default spot, named cart_1 (%s)" % view.position)
	var near_shelf: bool = false
	for point: ShedPiecePoint in _shed.use_points.values():
		var apart: float = point.global_position.distance_to(view.global_position)
		if point.role == &"storage" and apart < Interactable.REMOTE_REACH:
			near_shelf = true
	_expect(near_shelf, "The cart is within reach of a shelf's use point")
	_expect(view.load_point.get_prompt() != "" and view.push_point.get_prompt() != ""
		and view.load_point.get_prompt() != view.push_point.get_prompt(), "Both points have their own prompt")
	_expect(_shed.station_for(&"cart:no_such_cart").is_empty(), "An unknown cart is no station")
	var station: Dictionary = _shed.station_for(view.cart.location())
	_expect(station.get("location") == &"cart:cart_1" and station.get("capacity") == CompanyTuning.CART_MAX_UNITS
		and station.get("spot") is Vector3 and station.get("at") is Vector3 and station.get("stand_ok") is Callable,
		"The shed resolves the cart as a station (%s)" % [station.keys()])

	var hands: StringName = CompanyNet.hands_location(1)
	_player_at = view.global_position + Vector3(-1.2, 1.5, 0.0)
	var units_before: int = _net.inventory.total_units()

	# Load 4 hens, then 2 lamps: six units, sorted by product (lamp before hen) whatever the order.
	_give(HEN, 4)
	_expect(_use(PickingCartPoint.ACTION_LOAD) == PickingCartUse.RESULT_LOADED, "Four hens go on the cart")
	_give(LAMP, 2)
	_expect(_use(PickingCartPoint.ACTION_LOAD) == PickingCartUse.RESULT_LOADED, "Two lamps go on the cart too")
	var on_cart: StringName = view.cart.location()
	_expect(_net.inventory.count(HEN, on_cart) == 4 and _net.inventory.count(LAMP, on_cart) == 2
		and view.cart.count(_net.inventory) == 6 and _net.inventory.contents_at(hands).is_empty(),
		"The cart holds 4 hens and 2 lamps, the hands are empty")
	_expect(_net.inventory.total_units() == units_before + 6,
		"Loading created or lost no unit (%d)" % _net.inventory.total_units())
	_expect(view.slot_products() == [LAMP, LAMP, HEN, HEN, HEN, HEN],
		"The cubes stand in slots sorted by product (%s)" % [view.slot_products()])
	var standing: Array[Vector3] = _check_cubes(view, "after loading six")
	_expect(standing.size() == 6, "Six cubes are drawn (%d)" % standing.size())
	_same_as_mirror("after loading six")

	# Physics frames change nothing: the cubes are not bodies.
	for _frame: int in 3:
		await physics_frame
	_expect(_cube_spots(view) == standing, "The six cubes are where they were after three physics frames")

	# The 7th unit.
	_give(HEN, 1)
	var seq_full: int = _net.seq
	_expect(_use(PickingCartPoint.ACTION_LOAD) == PickingCart.REASON_FULL, "The plan refuses a 7th unit with full")
	_net.request_for(1, &"units_store", {"station": view.cart.location(), "product": HEN, "qty": 1})
	_expect(_refusals.size() == 1 and _refusals[0] == CompanyNet.REASON_NO_ROOM,
		"Asked anyway, the host refuses the 7th with no_room (%s)" % [_refusals])
	_expect(_net.seq == seq_full and view.cart.count(_net.inventory) == 6 and _net.inventory.count(HEN, hands) == 1,
		"Nothing moved: six on the cart, the hen still in the hands")
	_net.inventory.consume(HEN, 1, hands)
	_mirror.inventory.consume(HEN, 1, hands)

	# Unload into the empty hands: the first product, up to the hand limit.
	_expect(_use(PickingCartPoint.ACTION_LOAD) == PickingCartUse.RESULT_UNLOADED,
		"With empty hands the platform unloads")
	_expect(_net.inventory.count(LAMP, hands) == 2 and view.cart.count(_net.inventory) == 4
		and view.slot_products() == [HEN, HEN, HEN, HEN],
		"Both lamps came to the hands, four hens stay (%s)" % [view.slot_products()])
	_check_cubes(view, "after unloading the lamps")
	_same_as_mirror("after unloading")

	# Reach is the host's.
	var seq_reach: int = _net.seq
	_refusals.clear()
	_player_at = view.global_position + Vector3(40.0, 1.5, 0.0)
	_expect(_use(PickingCartPoint.ACTION_LOAD) == PickingCartUse.REASON_REFUSED
		and _refusals == [CompanyNet.REASON_OUT_OF_REACH], "40 m away the host refuses to load (%s)" % [_refusals])
	_expect(_use(PickingCartPoint.ACTION_PUSH) == PickingCartUse.REASON_REFUSED
		and _refusals.back() == CompanyNet.REASON_OUT_OF_REACH, "... and to push")
	_expect(_net.seq == seq_reach and view.cart.count(_net.inventory) == 4 and _net.inventory.count(LAMP, hands) == 2
		and view.position.is_equal_approx(spot), "Out of reach nothing moved and the cart stayed")

	# Push: away from the player, one step.
	_player_at = view.global_position + Vector3(-1.2, 1.5, 0.0)
	var step: float = CompanyTuning.CART_PUSH_STEP_M
	var pushed_to: Vector3 = spot + Vector3(step, 0.0, 0.0)
	var seq_push: int = _net.seq
	_expect(_use(PickingCartPoint.ACTION_PUSH, _player_at) == PickingCartUse.RESULT_PUSHED
		and _net.seq == seq_push + 1, "A push is one event (seq %d)" % _net.seq)
	_expect(view.position.is_equal_approx(pushed_to) and _net.carts.position_of(CART) is Vector3
		and (_net.carts.position_of(CART) as Vector3).is_equal_approx(pushed_to),
		"The cart rolled one step away from the player and CompanyCarts says so (%s)" % view.position)
	var moved_station: Dictionary = _shed.station_for(view.cart.location())
	var moved_spot: Vector3 = moved_station["spot"]
	_expect(moved_spot.is_equal_approx(view.global_position + Vector3.UP * 0.5), "Its reach spot follows the cart")
	_expect(view.cart.count(_net.inventory) == 4 and view.slot_products().size() == 4, "The units rode along")
	await create_timer(PickingCartView.SLIDE_SECONDS + 0.15).timeout
	_check_cubes(view, "after the push")
	_same_as_mirror("after the push")

	# Push into the shelves: east of the cart pushing west until the host says blocked.
	var blocked: bool = false
	for _try: int in 8:
		_player_at = view.global_position + Vector3(1.2, 1.5, 0.0)
		var before_seq: int = _net.seq
		var before_at: Vector3 = view.position
		_refusals.clear()
		var result: StringName = _use(PickingCartPoint.ACTION_PUSH, _player_at)
		if result == PickingCartUse.REASON_REFUSED:
			blocked = _refusals == [CompanyCarts.REASON_BLOCKED] and _net.seq == before_seq \
				and view.position.is_equal_approx(before_at)
			break
	_expect(blocked, "Pushed into the shelves the host refuses with blocked and the cart stays (%s)" % [_refusals])
	_expect(_shed.cart_can_stand(view.position, CART) and not _shed.cart_can_stand(view.position)
		and not _shed.cart_can_stand(_shed.cell_to_local(Vector2(0.5, 2.5)))
		and not _shed.cart_can_stand(Vector3(500.0, 0.0, 0.0)),
		"The floor check knows shelves and walls, and the cart's own spot is taken for any other cart")

	# Bad pushes.
	var seq_bad: int = _net.seq
	_refusals.clear()
	_net.request_for(1, CompanyCarts.PUSH, {"cart": CART, "dir": Vector3(NAN, 0.0, 0.0)})
	_net.request_for(1, CompanyCarts.PUSH, {"cart": CART, "dir": Vector3.ZERO})
	_net.request_for(1, CompanyCarts.PUSH, {"cart": "not an id!", "dir": Vector3.RIGHT})
	_net.request_for(1, CompanyCarts.PUSH, {"cart": &"cart_9", "dir": Vector3.RIGHT})
	_expect(_net.seq == seq_bad and _refusals == [CompanyCarts.REASON_BAD_DATA, CompanyCarts.REASON_BAD_DATA,
		CompanyCarts.REASON_NO_STATION],
		"A NaN push is dropped; zero, a bad id and an unknown cart are refused, none pushes (%s)" % [_refusals])
	await create_timer(PickingCartView.SLIDE_SECONDS + 0.15).timeout
	_same_as_mirror("after all pushes")
	_expect(_events.size() == _net.seq and _mirror.seq == _net.seq, "Both peers applied every event in order (%d / %d)"
		% [_mirror.seq, _net.seq])
	_expect(_net.inventory.total_units() == units_before + 6,
		"The total of units never changed (%d)" % _net.inventory.total_units())

	# A late peer: the snapshot parts bring the spot and the units.
	var snapshot: Dictionary = _net.snapshot()
	_expect(snapshot.get("carts") is Dictionary and (snapshot["carts"] as Dictionary).size() == 1
		and snapshot.has("inventory"), "The host's snapshot carries the cart's spot (%s)" % [snapshot.get("carts")])
	var late := CompanyNet.new()
	late.name = "LateNet"
	late.company = state
	root.add_child(late)
	_expect(late.carts.put_snapshot(snapshot["carts"]), "The late peer takes the cart part")
	late.inventory.from_dict(snapshot["inventory"])
	var late_shed := CompanyShed.new()
	late_shed.name = "LateShed"
	root.add_child(late_shed)
	late_shed.follow(late)
	late_shed.rebuild(state, late.inventory)
	await process_frame
	_expect(_cart_look(late_shed) == _cart_look(_shed), "The late peer draws the same cart: %s vs %s"
		% [_cart_look(late_shed), _cart_look(_shed)])
	var keep: Dictionary = late.carts.to_dict()
	_expect(not late.carts.put_snapshot({"x y": Vector3.ZERO})
		and not late.carts.put_snapshot({"cart_1": Vector3(NAN, 0, 0)})
		and not late.carts.put_snapshot("nope") and late.carts.to_dict() == keep, "A bad snapshot part changes nothing")
	var many: Dictionary = {}
	for index: int in CompanyCarts.MAX_CARTS + 1:
		many["c%d" % index] = Vector3.ZERO
	_expect(not late.carts.put_snapshot(many) and late.carts.to_dict() == keep, "Too many carts are refused")

	for node: Node in [late_shed, late, _mirror_shed, _mirror, _shed, _net]:
		node.free()


# --- Helpers ---


func _view(shed: CompanyShed) -> PickingCartView:
	return shed.cart_views.get(CART) as PickingCartView


## Units into the hands of peer 1 on both peers, with no event (the way a shelf would have, minus the event).
func _give(product: StringName, qty: int) -> void:
	var hands: StringName = CompanyNet.hands_location(1)
	_net.inventory.receive(product, qty, hands)
	_mirror.inventory.receive(product, qty, hands)


## One use of the cart's point by peer 1 at `_player_at`.
func _use(action: StringName, from: Vector3 = Vector3.ZERO) -> StringName:
	var standing: Vector3 = from if from != Vector3.ZERO else _player_at
	return PickingCartUse.use(_net, _view(_shed), action, 1, standing)


## Every drawn cube is above the deck, inside the rails and apart from the others; the world positions of
## the cubes, in slot order.
func _check_cubes(view: PickingCartView, when: String) -> Array[Vector3]:
	var half: float = PickingCartView.UNIT_SIZE * 0.5
	var spots: Array[Vector3] = _cube_spots(view)
	for world: Vector3 in spots:
		var frame: Vector3 = view.to_local(world)
		_expect(frame.y - half >= PickingCartView.DECK_TOP - EPS and frame.y < PickingCartView.HEIGHT,
			"A cube is on the deck, not under it, %s (y %.3f)" % [when, frame.y])
		_expect(absf(frame.x) + half <= PickingCartView.LENGTH * 0.5 + EPS
			and absf(frame.z) + half <= PickingCartView.WIDTH * 0.5 + EPS,
			"A cube is inside the platform %s (%s)" % [when, frame])
	return spots


func _cube_spots(view: PickingCartView) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for unit: MeshInstance3D in view.shown_units():
		spots.append(unit.global_position)
	return spots


## What a peer draws of the cart: its spot, the product on each slot and where each cube stands in its frame.
func _cart_look(shed: CompanyShed) -> Array:
	var view: PickingCartView = _view(shed)
	var cubes: Array[Vector3] = []
	for unit: MeshInstance3D in view.shown_units():
		cubes.append(unit.position)
	return [view.position, view.slot_products(), cubes]


func _same_as_mirror(when: String) -> void:
	_expect(_cart_look(_shed) == _cart_look(_mirror_shed),
		"The second peer draws the same cart %s: %s vs %s" % [when, _cart_look(_mirror_shed), _cart_look(_shed)])
	_expect(_mirror.inventory.to_dict() == _net.inventory.to_dict() and _mirror.carts.to_dict() == _net.carts.to_dict(),
		"... and holds the same units and spot %s" % when)
