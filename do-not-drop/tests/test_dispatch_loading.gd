extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dispatch_loading.gd
##
## Loading a vehicle from the dispatch zone (expansion D-0717, dispatch_loading.gd):
## - the van takes the waiting boxes oldest first, up to its cargo_slots, and the trip that
##   leaves through the gate carries exactly those orders (the rest stay PACKED);
## - a box that would pass the vehicle's cargo_kg stays waiting with the "over weight" reason,
##   and a lighter box behind it still goes;
## - a box for a zone the vehicle cannot reach (Islas by van) stays with DispatchRules' reason;
## - the boxes left stay in the zone and go with the next vehicle; plan() alone changes nothing;
## - the two new refusal keys have a translation row.

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
	_test_slots()
	_test_weight()
	_test_rules()
	_test_keys()
	if _failures == 0:
		print("PASS: vehicle takes from dispatch what fits and the trip leaves with it")
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


## Order ids with their zone; every one packed in box_<id>, sealed and waiting in the zone.
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


func _test_slots() -> void:
	var s: Dictionary = _setup({&"o1": &"centro", &"o2": &"centro", &"o3": &"centro"})
	var zone: DispatchZone = s["zone"]
	var book: OrderBook = s["book"]
	var van := _van(2, 100.0)
	var kg: Dictionary = {&"box_o1": 3.0, &"box_o2": 3.0, &"box_o3": 3.0}
	var plan: Dictionary = DispatchLoading.plan(zone, book, van, kg, _zones, _gates, {})
	_expect(plan["load"] == [&"box_o1", &"box_o2"], "oldest two fit the two slots")
	_expect(
		plan["left"].size() == 1 and plan["left"][0]["key"] == DispatchLoading.NO_SLOTS,
		"the third waits: no slot"
	)
	_expect(zone.boxes().size() == 3, "plan() leaves the zone as it was")
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 2.0)
	trips.book = book
	DispatchLoading.load_vehicle(zone, trips, &"van", book, van, kg, _zones, _gates, {})
	_expect(zone.boxes() == [&"box_o3"], "the third box still waits in the zone")
	trips.track(&"van", Vector3(0, 0, -1))
	trips.track(&"van", Vector3(0, 0, -8))
	var trip: Trip = trips.trip_of(&"van")
	_expect(trip != null and trip.order_ids == [&"o1", &"o2"], "the van left with the two")
	_expect(
		book.state_of(&"o1") == Order.STATE_OUT and book.state_of(&"o3") == Order.STATE_PACKED,
		"o1 out, o3 still packed"
	)
	DispatchLoading.load_vehicle(zone, trips, &"van2", book, van, kg, _zones, _gates, {})
	_expect(zone.boxes().is_empty(), "the next vehicle takes the box that was left")
	trips.free()


func _test_weight() -> void:
	var s: Dictionary = _setup({&"o1": &"centro", &"o2": &"centro", &"o3": &"centro"})
	var zone: DispatchZone = s["zone"]
	var kg: Dictionary = {&"box_o1": 6.0, &"box_o2": 6.0, &"box_o3": 2.0}
	var plan: Dictionary = DispatchLoading.plan(zone, s["book"], _van(7, 10.0), kg, _zones, _gates, {})
	_expect(plan["load"] == [&"box_o1", &"box_o3"], "the heavy second box skipped, the light one goes")
	_expect(
		plan["left"].size() == 1
		and plan["left"][0]["box"] == &"box_o2"
		and plan["left"][0]["key"] == DispatchLoading.NO_WEIGHT,
		"o2 stays: over weight"
	)


func _test_rules() -> void:
	var s: Dictionary = _setup({&"o1": &"centro", &"o2": &"islas"})
	var plan: Dictionary = DispatchLoading.plan(
		s["zone"], s["book"], _van(7, 100.0), {}, _zones, _gates, {}
	)
	_expect(plan["load"] == [&"box_o1"], "the Centro box goes")
	_expect(
		plan["left"].size() == 1
		and plan["left"][0]["order"] == &"o2"
		and plan["left"][0]["key"] == DispatchRules.NEEDS_VEHICLE,
		"the Islas box stays with the dispatch rule's reason"
	)


func _test_keys() -> void:
	var csv := FileAccess.get_file_as_string("res://translations/strings_world.csv")
	for key: String in [DispatchLoading.NO_SLOTS, DispatchLoading.NO_WEIGHT]:
		_expect(csv.contains("\n" + key + ","), "translation row for " + key)
