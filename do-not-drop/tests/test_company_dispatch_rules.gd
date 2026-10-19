extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_dispatch_rules.gd
##
## Which vehicle can go where (expansion D-0309, dispatch_rules.gd, over
## data/zones/*.tres and data/gates/*.tres):
## - a van loads Centro orders, and Campo ones once its roadblock milestone is done; an Islas order is refused with the
##   reason "needs boat", even when the gate is marked open;
## - a boat (a VehicleDefinition built here) loads the Islas order and a plane
##   the Montana one, while the van gets "needs plane" there;
## - a Suburbio order with the barrier closed is refused with the milestone
##   missing; with the milestone done, or the gate opened, it loads;
## - gear gates (Nieve) name the missing equipment until the company owns it;
## - an unknown zone is refused, and every refusal key has a translation row.

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
	_test_van()
	_test_water_and_altitude()
	_test_barrier()
	_test_equipment()
	_test_unknown_zone_and_keys()
	if _failures == 0:
		print("PASS: dispatch rules refuse a vehicle that cannot reach the order, with the reason")
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


func _van() -> VehicleDefinition:
	return load("res://data/vehicles/van_classic.tres")


func _vehicle(fleet_key: StringName) -> VehicleDefinition:
	var def := VehicleDefinition.new()
	def.id = fleet_key
	def.fleet_key = fleet_key
	return def


func _owned(milestones: Array = [], equipment: Array = [], vehicles: Array = []) -> Dictionary:
	return {"milestones": milestones, "equipment": equipment, "vehicles": vehicles}


func _check(zone: StringName, vehicle: VehicleDefinition, owned: Dictionary, opened: Array = []) -> Dictionary:
	return DispatchRules.check(zone, vehicle, _zones, _gates, owned, opened)


func _test_van() -> void:
	var centro: Dictionary = _check(&"centro", _van(), _owned())
	_expect(centro["ok"], "van loads Centro (" + str(centro) + ")")
	var campo: Dictionary = _check(&"campo", _van(), _owned())
	_expect(not campo["ok"] and campo["args"] == ["reputation_60"], "Campo roadblock closed: " + str(campo))
	_expect(_check(&"campo", _van(), _owned([&"reputation_60"]))["ok"], "van loads Campo once the works end")
	var order := {"zone": &"centro"}
	_expect(DispatchRules.check_order(order, _van(), _zones, _gates, _owned())["ok"], "check_order reads the zone key")


func _test_water_and_altitude() -> void:
	var owned: Dictionary = _owned([], [], [&"van", &"boat", &"plane"])
	var van_islas: Dictionary = _check(&"islas", _van(), owned)
	_expect(not van_islas["ok"] and van_islas["key"] == DispatchRules.NEEDS_VEHICLE, "van refused at Islas")
	_expect(van_islas["args"] == ["boat"], "reason names the boat: " + str(van_islas["args"]))
	var open_islas: Dictionary = _check(&"islas", _van(), owned, [&"gate_islas_agua"])
	_expect(not open_islas["ok"], "an opened water gate still does not carry a van")
	_expect(_check(&"islas", _vehicle(&"boat"), owned)["ok"], "boat loads the Islas order")
	var van_mountain: Dictionary = _check(&"montana", _van(), owned)
	_expect(not van_mountain["ok"] and van_mountain["args"] == ["plane"], "van refused at Montana: needs plane")
	_expect(_check(&"montana", _vehicle(&"plane"), owned)["ok"], "plane loads the Montana order")


func _test_barrier() -> void:
	var closed: Dictionary = _check(&"suburbio", _van(), _owned())
	_expect(not closed["ok"] and closed["key"] == DispatchRules.NEEDS_MILESTONE, "closed barrier refuses Suburbio")
	_expect(closed["args"] == ["deliveries_25"], "reason names the milestone: " + str(closed["args"]))
	_expect(_check(&"suburbio", _van(), _owned([&"deliveries_25"]))["ok"], "milestone done: Suburbio loads")
	_expect(_check(&"suburbio", _van(), _owned(), [&"gate_suburbio"])["ok"], "gate opened: Suburbio loads")


func _test_equipment() -> void:
	var bare: Dictionary = _check(&"nieve", _van(), _owned([&"deliveries_25"]))
	_expect(not bare["ok"], "Nieve refused without gear or milestone: " + str(bare))
	var gate: GateRequirement = _gates.get(&"gate_nieve_equipo")
	if gate == null or gate.equipment.is_empty():
		_expect(false, "gate_nieve_equipo lists equipment")
		return
	var milestones: Array = [gate.milestone] if gate.milestone != &"" else []
	var no_gear: Dictionary = _check(&"nieve", _van(), _owned(milestones))
	_expect(not no_gear["ok"] and no_gear["key"] == DispatchRules.NEEDS_EQUIPMENT, "gear named: " + str(no_gear))
	_expect(_check(&"nieve", _van(), _owned(milestones, gate.equipment.duplicate()))["ok"], "with the gear Nieve loads")


func _test_unknown_zone_and_keys() -> void:
	_expect(not _check(&"atlantida", _van(), _owned())["ok"], "unknown zone refused")
	var csv := FileAccess.get_file_as_string("res://translations/strings_world.csv")
	for key: String in [DispatchRules.NEEDS_VEHICLE, DispatchRules.NEEDS_MILESTONE, DispatchRules.NEEDS_EQUIPMENT]:
		_expect(csv.contains("\n" + key + ","), "translation row for " + key)
