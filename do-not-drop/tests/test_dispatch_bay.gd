extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dispatch_bay.gd
##
## Loading several vehicles from the dispatch zone at once (expansion D-0931, dispatch_bay.gd):
## - boxes go oldest first to the first vehicle with room, and the next vehicle takes the overflow;
## - a box the first vehicle cannot take by rule (Islas by van) goes to the vehicle that can;
## - a box no vehicle takes stays waiting with a reason, and plan() alone changes nothing;
## - load_bay() stages each vehicle's boxes, so both trips leave with exactly their orders;
## - only MAX_VEHICLES vehicles count.

const ZONE_DIR: String = "res://data/zones/"
const GATE_DIR: String = "res://data/gates/"

var _failures: int = 0
var _zones: Dictionary = {}
var _gates: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_zones = _load_dir(ZONE_DIR)
	_gates = _load_dir(GATE_DIR)
	_test_overflow_and_load()
	_test_rules_pick_vehicle()
	_test_nobody_takes()
	_test_cap()
	if _failures == 0:
		print("PASS: several vehicles load from dispatch at once")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _load_dir(dir: String) -> Dictionary:
	var result: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			var res: Resource = load(dir + file)
			result[res.get("id")] = res
	return result


func _van(slots: int, kg: float) -> VehicleDefinition:
	var def := VehicleDefinition.new()
	def.id = &"van_test"
	def.fleet_key = &"van"
	def.cargo_slots = slots
	def.cargo_kg = kg
	return def


func _setup(zones_of: Dictionary) -> Dictionary:
	var book := OrderBook.new()
	var zone := DispatchZone.new(AABB(Vector3(0, 0, 4), Vector3(4, 2, 3)))
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	for id: StringName in zones_of:
		book.add(
			Order.make(
				id, "Ana", zones_of[id], &"house_1", [{"product": &"hen", "qty": 1}], 0, products
			)
		)
		book.mark_packed(id, StringName("box_" + str(id)))
		zone.update_box(StringName("box_" + str(id)), id, Vector3(1, 0, 5), true, true, book)
	return {"book": book, "zone": zone}


func _bay(a_slots: int, b_slots: int) -> Array:
	return [
		{"id": &"van_a", "def": _van(a_slots, 100.0)},
		{"id": &"van_b", "def": _van(b_slots, 100.0)},
	]


func _test_overflow_and_load() -> void:
	var s: Dictionary = _setup({&"o1": &"centro", &"o2": &"centro", &"o3": &"centro"})
	var zone: DispatchZone = s["zone"]
	var book: OrderBook = s["book"]
	var plan: Dictionary = DispatchBay.plan(zone, book, _bay(2, 2), {}, _zones, _gates, {})
	_expect(plan["loads"][&"van_a"] == [&"box_o1", &"box_o2"], "first van takes the oldest two")
	_expect(plan["loads"][&"van_b"] == [&"box_o3"], "second van takes the overflow")
	_expect(plan["left"].is_empty(), "nothing left")
	_expect(zone.boxes().size() == 3, "plan() leaves the zone as it was")
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 2.0)
	trips.book = book
	DispatchBay.load_bay(zone, trips, book, _bay(2, 2), {}, _zones, _gates, {})
	_expect(zone.boxes().is_empty(), "the zone is empty after loading both")
	for id: StringName in [&"van_a", &"van_b"]:
		trips.track(id, Vector3(0, 0, -1))
		trips.track(id, Vector3(0, 0, -8))
	var ta: Trip = trips.trip_of(&"van_a")
	var tb: Trip = trips.trip_of(&"van_b")
	_expect(ta != null and ta.order_ids == [&"o1", &"o2"], "van_a left with o1 and o2")
	_expect(tb != null and tb.order_ids == [&"o3"], "van_b left with o3")
	trips.free()


func _test_rules_pick_vehicle() -> void:
	var s: Dictionary = _setup({&"o1": &"islas", &"o2": &"centro"})
	var vehicles: Array = _bay(3, 3)
	var plan: Dictionary = DispatchBay.plan(s["zone"], s["book"], vehicles, {}, _zones, _gates, {})
	_expect(plan["loads"][&"van_a"] == [&"box_o2"], "the Centro box goes to the first van")
	_expect(
		plan["left"].size() == 1 and plan["left"][0]["key"] == DispatchRules.NEEDS_VEHICLE,
		"the Islas box stays with the rule's reason when no van can take it"
	)


func _test_nobody_takes() -> void:
	var s: Dictionary = _setup({&"o1": &"centro", &"o2": &"centro", &"o3": &"centro"})
	var plan: Dictionary = DispatchBay.plan(s["zone"], s["book"], _bay(1, 1), {}, _zones, _gates, {})
	_expect(plan["left"].size() == 1 and plan["left"][0]["box"] == &"box_o3", "third box waits")
	_expect(plan["left"][0]["key"] == DispatchLoading.NO_SLOTS, "reason: no slot")
	var kg: Dictionary = {&"box_o1": 60.0, &"box_o2": 60.0, &"box_o3": 1.0}
	var heavy: Dictionary = DispatchBay.plan(s["zone"], s["book"], _bay(5, 5), kg, _zones, _gates, {})
	_expect(heavy["loads"][&"van_b"] == [&"box_o2"], "over-weight box moves to the second van")
	_expect(heavy["loads"][&"van_a"] == [&"box_o1", &"box_o3"], "the light one still fits the first")


func _test_cap() -> void:
	var s: Dictionary = _setup({&"o1": &"centro"})
	var vehicles: Array = []
	for i: int in 5:
		vehicles.append({"id": StringName("v%d" % i), "def": _van(1, 10.0)})
	var plan: Dictionary = DispatchBay.plan(s["zone"], s["book"], vehicles, {}, _zones, _gates, {})
	_expect(plan["loads"].size() == DispatchBay.MAX_VEHICLES, "only MAX_VEHICLES count")
