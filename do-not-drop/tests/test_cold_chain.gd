extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cold_chain.gd
##
## Cold products out of the fridge rot (expansion D-0616, cold_chain.gd and Inventory.discard):
## - milk on an ordinary shelf rots after COLD_SPOIL_MINUTES (2 h) and leaves the stock; the same
##   milk in a fridge (cold shelf) never does; ambient products never do;
## - the clock stops in the fridge but doesn't reset: taking milk out and back keeps its age;
## - moving carries the clock, and units that join others average it by units;
## - rotting trims the newest reservations that no longer fit (and says which orders lost units);
## - a place with no units has no clock; a bad move changes nothing;
## - the clocks survive a JSON round trip; discard() refuses more than the place holds.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var milk: ProductDefinition = load("res://data/products/milk_canister.tres")
	var vase: ProductDefinition = load("res://data/products/porcelain_vase.tres")
	var products: Dictionary = {milk.id: milk, vase.id: vase}
	var fridges: Dictionary = {&"fridge_1": true}
	var limit: float = CompanyTuning.COLD_SPOIL_MINUTES
	var shelf: StringName = &"shelf:shelf_1_0"
	var cold: StringName = &"shelf:fridge_1_0"

	_expect(ColdChain.is_cold_location(cold, fridges), "fridge slot is cold")
	_expect(not ColdChain.is_cold_location(shelf, fridges), "ordinary shelf slot is not cold")
	_expect(not ColdChain.is_cold_location(&"cart:1", fridges), "a cart is not cold")
	_expect(not ColdChain.is_cold_location(&"shelf:_0", fridges), "malformed location is not cold")

	# Rots out of the fridge, never in it, ambient never.
	var inv := Inventory.new()
	var chain := ColdChain.new()
	chain.receive(inv, milk.id, 3, shelf)
	chain.receive(inv, milk.id, 2, cold)
	chain.receive(inv, vase.id, 4, shelf)
	chain.advance(inv, products, fridges, limit - 1.0)
	_expect(inv.count(milk.id, shelf) == 3, "milk holds just before the limit")
	_expect(is_equal_approx(chain.minutes_left(milk.id, shelf), 1.0), "one minute left")
	var rotten: Array[Dictionary] = chain.advance(inv, products, fridges, 1.0)
	_expect(rotten.size() == 1, "one place rotted")
	_expect(rotten[0]["qty"] == 3 and rotten[0]["location"] == shelf, "the shelf milk rotted")
	_expect(inv.count(milk.id, shelf) == 0, "rotten milk left the stock")
	_expect(inv.count(milk.id, cold) == 2, "milk in the fridge is fine")
	_expect(inv.count(vase.id, shelf) == 4, "ambient products never rot")
	chain.advance(inv, products, fridges, limit * 5.0)
	_expect(inv.count(milk.id, cold) == 2, "the fridge keeps the milk for any time")
	_expect(is_zero_approx(chain.warm_minutes(milk.id, shelf)), "a place with no units has no clock")

	# The clock stops in the fridge, travels with the units and doesn't reset.
	inv = Inventory.new()
	chain = ColdChain.new()
	chain.receive(inv, milk.id, 4, shelf)
	chain.advance(inv, products, fridges, 90.0)
	_expect(chain.move(inv, milk.id, 4, shelf, cold), "milk goes to the fridge")
	_expect(is_equal_approx(chain.warm_minutes(milk.id, cold), 90.0), "it arrives with its age")
	chain.advance(inv, products, fridges, 600.0)
	_expect(is_equal_approx(chain.warm_minutes(milk.id, cold), 90.0), "age stops in the fridge")
	_expect(chain.move(inv, milk.id, 4, cold, shelf), "and comes out again")
	chain.advance(inv, products, fridges, 29.0)
	_expect(inv.count(milk.id, shelf) == 4, "29 more minutes still hold")
	chain.advance(inv, products, fridges, 1.0)
	_expect(inv.count(milk.id, shelf) == 0, "the fridge didn't make it fresh")

	# Joining units average the clock by units; a partial move leaves the rest's clock.
	inv = Inventory.new()
	chain = ColdChain.new()
	chain.receive(inv, milk.id, 2, shelf)
	chain.advance(inv, products, fridges, 60.0)
	chain.receive(inv, milk.id, 2, shelf)
	_expect(is_equal_approx(chain.warm_minutes(milk.id, shelf), 30.0), "2 old + 2 fresh = 30")
	_expect(chain.move(inv, milk.id, 1, shelf, &"cart:1"), "one unit to a cart")
	_expect(is_equal_approx(chain.warm_minutes(milk.id, &"cart:1"), 30.0), "the cart gets it")
	_expect(is_equal_approx(chain.warm_minutes(milk.id, shelf), 30.0), "the shelf keeps its own")
	_expect(not chain.move(inv, milk.id, 9, shelf, &"cart:1"), "can't move more than there is")
	_expect(not chain.move(inv, milk.id, 1, shelf, shelf), "can't move to the same place")
	_expect(inv.count(milk.id) == 4, "nothing was lost or created")

	# Rotting trims reservations that no longer fit, newest order first.
	inv = Inventory.new()
	chain = ColdChain.new()
	chain.receive(inv, milk.id, 3, shelf)
	chain.receive(inv, milk.id, 2, cold)
	_expect(inv.reserve(milk.id, 2, &"o1"), "first order reserves 2")
	_expect(inv.reserve(milk.id, 2, &"o2"), "second order reserves 2")
	rotten = chain.advance(inv, products, fridges, limit)
	_expect(inv.count(milk.id) == 2, "only the fridge milk is left")
	_expect(inv.reserved_total(milk.id) == 2, "reservations fit the stock again")
	_expect(inv.reserved_by(&"o1").get(milk.id, 0) == 2, "the oldest order keeps its milk")
	_expect(not inv.reserved_by(&"o2").has(milk.id), "the newest order lost it")
	_expect(rotten[0]["lost"] == {&"o2": 2}, "the report names the order that lost units")

	# JSON round trip of the clocks.
	inv = Inventory.new()
	chain = ColdChain.new()
	chain.receive(inv, milk.id, 2, shelf)
	chain.advance(inv, products, fridges, 45.0)
	var copy := ColdChain.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(chain.to_dict())))
	_expect(is_equal_approx(copy.warm_minutes(milk.id, shelf), 45.0), "clock survives JSON")
	copy.from_dict({"warm": {"milk_canister": {"shelf:s_0": limit + 5.0, "x": -3.0}}})
	_expect(is_zero_approx(copy.warm_minutes(milk.id, &"shelf:s_0")), "bad clocks are dropped")

	# discard() on its own.
	inv = Inventory.new()
	inv.receive(milk.id, 3, shelf)
	_expect(inv.discard(milk.id, 4, shelf) == false, "discard refuses more than the place holds")
	_expect(inv.discard(milk.id, 0, shelf) == false, "discard refuses zero")
	_expect(inv.discard(milk.id, 3, shelf) == {}, "discard of unreserved units reports nobody")
	_expect(inv.count(milk.id) == 0, "and they are gone")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)
