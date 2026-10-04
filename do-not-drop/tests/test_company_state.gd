extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_state.gd
##
## Company state (expansion D-0202, company_state.gd + company_tuning.gd):
## - the CompanyState autoload exists, sits right after UnlockManager and is
##   inactive at boot (Delivery and Endless ignore it);
## - new_company() gives 500 money, day 1, reputation 50 and the 08:00 clock;
## - to_dict() -> from_dict() returns the same company, every field included
##   (stock through Inventory), also through a JSON round trip;
## - a malformed or empty dictionary never crashes: defaults, clamped numbers,
##   and an empty one loads nothing;
## - reset() switches it off; starting a Delivery run does not activate it;
## - the numbers Order, Pallet and ProductDefinition used to hold are read from
##   CompanyTuning and keep their values.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	_expect(state != null and state.get_script() != null, "CompanyState autoload keeps its script")
	if state == null:
		quit(1)
		return
	_test_autoload_order()
	_test_boot_inactive(state)
	_test_new_company(state)
	_test_round_trip(state)
	_test_malformed(state)
	_test_reset(state)
	_test_delivery_does_not_activate(state)
	_test_tuning_owns_numbers()
	state.reset()
	if _failures == 0:
		print("PASS: CompanyState starts inactive, new_company/to_dict/from_dict round-trip, tuning owns the numbers")
	quit(_failures)


func _test_autoload_order() -> void:
	var names: Array[String] = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		if str(prop["name"]).begins_with("autoload/"):
			names.append(str(prop["name"]).trim_prefix("autoload/"))
	var unlock_at: int = names.find("UnlockManager")
	_expect(unlock_at >= 0 and names.find("CompanyState") == unlock_at + 1,
		"CompanyState is registered right after UnlockManager (got %s)" % [names])


func _test_boot_inactive(state: Node) -> void:
	_expect(not state.is_active(), "inactive at boot, before new_company()")


func _test_new_company(state: Node) -> void:
	state.new_company("Acme")
	_expect(state.is_active(), "new_company() activates")
	_expect(state.money == 500, "starting money is 500 (got %d)" % state.money)
	_expect(state.day == 1, "starts on day 1")
	_expect(is_equal_approx(state.reputation, 50.0), "starting reputation is 50")
	_expect(state.clock_minutes == 8 * 60, "the clock opens at 08:00")
	_expect(state.company_name == "Acme", "the company keeps its name")
	_expect(state.opened_gates.is_empty() and state.fleet.is_empty() and state.employees.is_empty(),
		"gates, fleet and employees start empty")


func _test_round_trip(state: Node) -> void:
	state.new_company("Round Trip SA")
	state.money = 1234
	state.day = 7
	state.clock_minutes = 13 * 60 + 15
	state.reputation = 72.5
	state.district_reputation = {&"centro": 80.0, &"campo": 41.5}
	state.opened_gates.assign([&"gate_bridge", &"gate_ferry"])
	state.fleet.assign([{"id": &"classic", "seats": 2}])
	state.employees.assign([{"name": "Ana", "wage": 40}])
	state.milestones_done.assign([&"first_delivery"])
	state.layout.assign([{"piece": &"shelf", "x": 1, "z": 2}])
	var stock := Inventory.new()
	stock.receive(&"hen", 12, &"dock")
	stock.receive(&"sourdough", 5, &"shelf:a1")
	stock.reserve(&"hen", 3, &"order_1")
	state.store_stock(stock)
	var saved: Dictionary = state.to_dict()

	# The dictionary is a copy: touching it changes nothing in the state.
	saved["fleet"].append({"id": &"agile"})
	_expect(state.fleet.size() == 1, "to_dict() hands out a deep copy")
	saved["fleet"].pop_back()

	state.reset()
	_expect(not state.is_active() and state.money == 500, "reset() before loading")
	_expect(state.from_dict(saved), "from_dict() accepts what to_dict() wrote")
	_expect(state.is_active(), "from_dict() activates")
	_expect(state.to_dict() == saved, "to_dict() -> from_dict() -> to_dict() is the same")
	_expect(state.money == 1234 and state.day == 7 and state.clock_minutes == 795,
		"money, day and clock come back")
	_expect(is_equal_approx(state.reputation, 72.5), "reputation comes back")
	_expect(state.district_reputation.get(&"campo") == 41.5, "district reputation comes back")
	_expect(state.opened_gates == [&"gate_bridge", &"gate_ferry"], "gates come back")
	_expect(state.milestones_done == [&"first_delivery"], "milestones come back")
	var back: Inventory = state.stock()
	_expect(back.count(&"hen") == 12 and back.count(&"sourdough", &"shelf:a1") == 5,
		"stock comes back through Inventory")
	_expect(back.reserved_by(&"order_1") == {&"hen": 3}, "reservations come back")

	# Through real JSON text: ids become String and numbers float.
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	_expect(parsed is Dictionary, "the save is valid JSON")
	state.reset()
	_expect(state.from_dict(parsed), "from_dict() accepts a JSON round trip")
	var again: Dictionary = state.to_dict()
	for key: String in ["money", "day", "clock_minutes", "reputation", "company_name",
			"district_reputation", "opened_gates", "milestones_done", "inventory"]:
		_expect(again[key] == saved[key], "%s survives JSON (got %s)" % [key, again[key]])
	_expect(typeof(state.money) == TYPE_INT and typeof(state.day) == TYPE_INT,
		"money and day are ints again after JSON")
	_expect(state.opened_gates[0] is StringName, "gate ids are StringName again")
	_expect(state.fleet.size() == 1 and state.employees.size() == 1 and state.layout.size() == 1,
		"fleet, employees and layout keep their entries")


func _test_malformed(state: Node) -> void:
	state.reset()
	_expect(not state.from_dict({}), "an empty dictionary loads nothing")
	_expect(not state.is_active(), "an empty dictionary does not activate")
	var junk: Dictionary = {
		"money": "lots", "day": -4, "clock_minutes": 99999, "reputation": 400.0,
		"district_reputation": [1, 2], "opened_gates": "gate", "fleet": [1, {"id": "van"}],
		"inventory": 5, "layout": null,
	}
	_expect(state.from_dict(junk), "a malformed dictionary still loads, with defaults")
	_expect(state.day == 1, "day is at least 1")
	_expect(state.clock_minutes == 24 * 60 - 1, "clock is clamped to the day")
	_expect(is_equal_approx(state.reputation, 100.0), "reputation is clamped to 100")
	_expect(state.district_reputation.is_empty() and state.opened_gates.is_empty(),
		"wrong-typed collections are dropped")
	_expect(state.fleet.size() == 1, "non-dictionary fleet entries are dropped")
	_expect(state.layout.is_empty(), "null layout becomes empty")
	_expect(state.stock().total_units() == 0, "a wrong-typed inventory becomes empty stock")
	_expect(state.money == 500, "a non-numeric money takes the default")
	var nulls: Dictionary = {
		"money": null, "reputation": null, "district_reputation": {"centro": null, "campo": 70.0},
		"opened_gates": [1.0, "gate_puerto"], "milestones_done": [null],
	}
	_expect(state.from_dict(nulls), "nulls and numbers as ids still load")
	_expect(state.money == 500 and is_equal_approx(state.reputation, 50.0), "null numbers take the defaults")
	_expect(state.district_reputation.size() == 1, "a null zone reputation is dropped")
	var gates: Array[StringName] = [&"gate_puerto"]
	_expect(state.opened_gates == gates, "a number is not a gate id")
	_expect(state.milestones_done.is_empty(), "a null milestone is dropped")


func _test_reset(state: Node) -> void:
	state.new_company("Gone")
	state.money = 9
	state.reset()
	_expect(not state.is_active(), "reset() deactivates")
	_expect(state.money == 500 and state.company_name == "", "reset() restores the defaults")


func _test_delivery_does_not_activate(state: Node) -> void:
	state.reset()
	var run_manager: Node = root.get_node_or_null(^"RunManager")
	_expect(run_manager != null, "RunManager autoload is there")
	if run_manager == null:
		return
	run_manager.start_run(&"delivery")
	_expect(run_manager.is_running, "the Delivery run started")
	_expect(not state.is_active(), "starting a Delivery run leaves CompanyState inactive")
	run_manager.is_running = false
	run_manager.current_mode = run_manager.MODE_DELIVERY


func _test_tuning_owns_numbers() -> void:
	_expect(Order.WINDOW_MIN == CompanyTuning.ORDER_WINDOW_MIN and Order.WINDOW_MIN == 240,
		"Order window comes from CompanyTuning (4 game hours)")
	_expect(is_equal_approx(Order.LATE_PENALTY, 0.25), "late penalty is 25 %")
	_expect(Order.SHIPPING_FEE == {&"centro": 40, &"campo": 60}, "shipping fees keep their values")
	_expect(Order.MAX_ITEMS == 3, "an order holds up to 3 products")
	_expect(CompanyTuning.PALLET_MAX_UNITS == 24, "a pallet holds 24 units")
	_expect(Pallet.make(&"p", &"hen", 25).is_empty(), "Pallet rejects more than the tuning allows")
	_expect(not Pallet.make(&"p", &"hen", 24).is_empty(), "Pallet takes exactly the tuning's cap")
	var product := ProductDefinition.new()
	product.buy_price = 50
	_expect(product.get_sell_price() == 80, "sell price is buy x CompanyTuning.SELL_MARKUP")
	_expect(CompanyTuning.SECONDS_PER_GAME_HOUR == 90.0, "1 game hour is 90 real seconds")
	_expect(CompanyTuning.DAY_END_MIN - CompanyTuning.DAY_START_MIN == 12 * 60,
		"the day runs 08:00 to 20:00")
	_expect(CompanyTuning.RENT_PER_DAY == 100, "rent is 100 a day")
	_expect(CompanyTuning.BOX_CELLS[&"XL"] == Vector3i(4, 4, 4), "XL box is 4x4x4")
	_expect(CompanyTuning.BOX_COST[&"L"] == 5, "L box costs 5")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
