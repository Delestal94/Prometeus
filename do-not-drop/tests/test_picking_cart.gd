extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_picking_cart.gd
##
## Picking cart that carries several products (expansion D-0610.a, picking_cart.gd):
## - the location of a cart is cart:<id> and parses back; a cart without id carries and accepts nothing;
## - it carries CompanyTuning.CART_MAX_UNITS (6) units, which is more than the hands hold (4);
## - the 7th unit is refused (full) and nothing changes, neither with the exact quantity nor "as many
##   as fit" (that one loads only what fits);
## - products mix on the cart up to the total; count, free_space and products answer from the Inventory;
## - hands holding two products or another product than asked are hands_busy, empty hands are empty;
## - emptying the cart into the hands respects HAND_MAX_UNITS (hands_full, hands_busy, one product);
## - 50 moves between shelf, hands and cart keep the total of units and never pass either limit;
## - the cart and the Inventory that holds its units survive a JSON round trip; a bad dictionary does
##   not fail.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_location()
	_test_capacity()
	_test_mixed()
	_test_busy_hands()
	_test_unload_limit()
	_test_conservation()
	_test_json()
	if _failures == 0:
		print("PASS: the picking cart carries 6 mixed units, refuses the 7th and never loses a unit")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_location() -> void:
	_expect(CompanyTuning.CART_MAX_UNITS == 6 and CompanyTuning.CART_MAX_UNITS > CompanyTuning.HAND_MAX_UNITS,
		"The cart carries 6, more than the hands")
	var cart: PickingCart = PickingCart.make(&"c1")
	_expect(cart.location() == &"cart:c1" and PickingCart.parse_location(cart.location()) == &"c1",
		"The location is cart:<id> and parses back (%s)" % cart.location())
	_expect(PickingCart.parse_location(&"hands:1") == &"" and PickingCart.parse_location(&"cart:") == &"",
		"A name that is no cart parses to empty")
	var ghost := PickingCart.new()
	var inv := Inventory.new()
	var hands: StringName = CompanyNet.hands_location(1)
	inv.receive(&"hen", 2, hands)
	_expect(not ghost.is_valid() and ghost.load_from_hands(inv, hands) == 0 and inv.count(&"hen", hands) == 2,
		"A cart without id refuses and changes nothing")


func _test_capacity() -> void:
	var cart: PickingCart = PickingCart.make(&"c1")
	var inv := Inventory.new()
	var hands: StringName = CompanyNet.hands_location(1)
	inv.receive(&"hen", CompanyTuning.HAND_MAX_UNITS, hands)
	_expect(cart.load_from_hands(inv, hands) == 4 and cart.count(inv) == 4 and cart.free_space(inv) == 2,
		"Four hens go on the cart, 2 places are left")
	inv.receive(&"hen", 3, hands)
	_expect(cart.plan_load(inv, hands, &"hen", 3).get("reason") == PickingCart.REASON_FULL,
		"3 more hens do not fit and are refused with full")
	_expect(cart.load_from_hands(inv, hands, &"hen", 3) == 0 and cart.count(inv) == 4
		and inv.count(&"hen", hands) == 3, "A refused load changes nothing")
	_expect(cart.load_from_hands(inv, hands) == 2 and cart.count(inv) == 6 and cart.free_space(inv) == 0
		and inv.count(&"hen", hands) == 1, "As many as fit loads the 2 that fit, the cart has 6")
	_expect(cart.plan_load(inv, hands).get("reason") == PickingCart.REASON_FULL
		and cart.load_from_hands(inv, hands) == 0 and cart.count(inv) == 6 and inv.total_units() == 7,
		"The 7th unit is refused and nothing changes (cart %d, total %d)" % [cart.count(inv), inv.total_units()])
	_expect(cart.plan_load(inv, CompanyNet.hands_location(2)).get("reason") == PickingCart.REASON_EMPTY,
		"Empty hands have nothing to load")
	_expect(cart.plan_load(inv, hands, &"lamp").get("reason") == PickingCart.REASON_EMPTY
		and cart.plan_load(inv, hands, &"hen", 2).get("reason") == PickingCart.REASON_FULL,
		"A product not in the hands is empty; an exact quantity over the free space is full")


func _test_mixed() -> void:
	var cart: PickingCart = PickingCart.make(&"c1")
	var inv := Inventory.new()
	var hands: StringName = CompanyNet.hands_location(1)
	inv.receive(&"hen", 3, hands)
	cart.load_from_hands(inv, hands)
	inv.receive(&"lamp", 2, hands)
	cart.load_from_hands(inv, hands)
	inv.receive(&"cake", 1, hands)
	cart.load_from_hands(inv, hands)
	_expect(cart.count(inv) == 6 and _names(cart.products(inv)) == "cake,hen,lamp"
		and cart.contents(inv) == {&"hen": 3, &"lamp": 2, &"cake": 1},
		"Three products mix up to 6 units (%s)" % [cart.contents(inv)])
	inv.receive(&"mug", 1, hands)
	_expect(cart.load_from_hands(inv, hands) == 0 and inv.count(&"mug", hands) == 1,
		"A 7th unit of a fourth product is refused too")
	var other: PickingCart = PickingCart.make(&"c2")
	_expect(other.count(inv) == 0 and other.products(inv).is_empty() and other.free_space(inv) == 6,
		"Another cart does not see these units")


func _test_busy_hands() -> void:
	var cart: PickingCart = PickingCart.make(&"c1")
	var inv := Inventory.new()
	var hands: StringName = CompanyNet.hands_location(1)
	inv.receive(&"hen", 1, hands)
	inv.receive(&"lamp", 1, hands)
	_expect(cart.plan_load(inv, hands).get("reason") == PickingCart.REASON_HANDS_BUSY,
		"Hands with two products must say which: hands_busy")
	_expect(cart.load_from_hands(inv, hands, &"lamp") == 1 and cart.contents(inv) == {&"lamp": 1},
		"Naming the product loads just that one")
	_expect(cart.plan_unload(inv, hands, &"lamp").get("reason") == PickingCart.REASON_HANDS_BUSY,
		"Hands holding a hen cannot take a lamp: hands_busy")
	inv.receive(&"cake", 1, hands)
	_expect(cart.plan_unload(inv, hands).get("reason") == PickingCart.REASON_HANDS_BUSY,
		"Unloading into hands with two products is hands_busy")
	inv.consume(&"cake", 1, hands)
	inv.consume(&"hen", 1, hands)
	_expect(cart.plan_unload(inv, hands).get("product") == &"lamp",
		"With free hands the unload offers the lamp")
	_expect(PickingCart.make(&"c9").plan_unload(inv, hands).get("reason") == PickingCart.REASON_EMPTY,
		"An empty cart is refused with empty")


func _test_unload_limit() -> void:
	var cart: PickingCart = PickingCart.make(&"c1")
	var inv := Inventory.new()
	var hands: StringName = CompanyNet.hands_location(1)
	inv.receive(&"hen", 5, cart.location())
	inv.receive(&"lamp", 1, cart.location())
	_expect(cart.count(inv) == 6, "A cart with 6 units")
	_expect(cart.unload_to_hands(inv, hands) == 4 and inv.count(&"hen", hands) == 4
		and cart.count(inv) == 2, "Emptying into the hands takes 4, the hand limit")
	_expect(cart.plan_unload(inv, hands).get("reason") == PickingCart.REASON_HANDS_FULL
		and cart.unload_to_hands(inv, hands) == 0 and cart.count(inv) == 2, "Full hands: hands_full, nothing moves")
	inv.consume(&"hen", 4, hands)
	_expect(cart.plan_unload(inv, hands, &"hen", 5).get("reason") == PickingCart.REASON_NOT_ENOUGH
		or cart.plan_unload(inv, hands, &"hen", 5).get("reason") == PickingCart.REASON_HANDS_FULL,
		"More than the hands take is refused")
	_expect(cart.unload_to_hands(inv, hands) == 1 and inv.count(&"hen", hands) == 1,
		"The next unload takes the last hen (sorted first), with room left")
	_expect(cart.plan_unload(inv, hands).get("reason") == PickingCart.REASON_HANDS_BUSY
		and cart.unload_to_hands(inv, hands, &"hen") == 0, "The lamp waits until the hands are free")
	inv.consume(&"hen", 1, hands)
	_expect(cart.unload_to_hands(inv, hands) == 1 and cart.count(inv) == 0
		and cart.plan_unload(inv, hands).get("reason") == PickingCart.REASON_EMPTY,
		"The cart ends empty and then refuses with empty")


func _test_conservation() -> void:
	var cart: PickingCart = PickingCart.make(&"c1")
	var inv := Inventory.new()
	var hands: StringName = CompanyNet.hands_location(1)
	var shelf: StringName = &"shelf:s1_0"
	var names: Array[StringName] = [&"hen", &"lamp", &"cake"]
	inv.receive(&"hen", 10, shelf)
	inv.receive(&"lamp", 10, shelf)
	inv.receive(&"cake", 10, shelf)
	var rng := RandomNumberGenerator.new()
	rng.seed = 610
	var worst_cart: int = 0
	var worst_hands: int = 0
	for step: int in 50:
		var product: StringName = names[rng.randi_range(0, 2)]
		match rng.randi_range(0, 3):
			0:
				# Like the host on units_take: one product in the hands, up to the hand limit.
				var held_now: Dictionary = inv.contents_at(hands)
				var room: int = CompanyTuning.HAND_MAX_UNITS - int(held_now.get(product, 0))
				if held_now.is_empty() or held_now.has(product):
					inv.move(product, mini(mini(rng.randi_range(1, 4), room), inv.count(product, shelf)),
						shelf, hands)
			1:
				cart.load_from_hands(inv, hands)
			2:
				cart.unload_to_hands(inv, hands, product)
			_:
				var held: Dictionary = inv.contents_at(hands)
				for held_product: StringName in held:
					inv.move(held_product, held[held_product], hands, shelf)
		worst_cart = maxi(worst_cart, cart.count(inv))
		var in_hands: int = 0
		for qty: int in inv.contents_at(hands).values():
			in_hands += qty
		worst_hands = maxi(worst_hands, in_hands)
		if inv.total_units() != 30:
			_expect(false, "Step %d: the total is %d, not 30" % [step, inv.total_units()])
			return
	_expect(inv.total_units() == 30 and worst_cart <= CompanyTuning.CART_MAX_UNITS
		and worst_hands <= CompanyTuning.HAND_MAX_UNITS and worst_cart >= 4,
		"50 moves keep the 30 units; cart never over 6, hands over 4 (cart %d, hands %d)"
		% [worst_cart, worst_hands])


func _test_json() -> void:
	var cart: PickingCart = PickingCart.make(&"c1")
	var inv := Inventory.new()
	inv.receive(&"hen", 4, cart.location())
	inv.receive(&"lamp", 2, cart.location())
	var back := PickingCart.new()
	back.from_dict(JSON.parse_string(JSON.stringify(cart.to_dict())))
	var inv_back := Inventory.new()
	inv_back.from_dict(JSON.parse_string(JSON.stringify(inv.to_dict())))
	_expect(back.id == &"c1" and back.location() == cart.location() and back.count(inv_back) == 6
		and back.contents(inv_back) == {&"hen": 4, &"lamp": 2},
		"The cart and its units survive a JSON round trip (%s)" % [back.contents(inv_back)])
	back.from_dict({"id": 7})
	_expect(not back.is_valid(), "A non-text id gives an invalid cart")
	back.from_dict({})
	_expect(not back.is_valid() and back.count(inv_back) == 0, "A missing id gives an invalid cart, no error")


func _names(list: Array[StringName]) -> String:
	var out: PackedStringArray = []
	for item: StringName in list:
		out.append(String(item))
	return ",".join(out)
