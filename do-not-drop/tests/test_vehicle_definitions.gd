extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_definitions.gd
##
## The fleet data of the company mode (expansion D-0207, vehicle_definition.gd):
## - data/vehicles/ holds van_classic, van_agile and van_vintage, each loading as
##   VehicleDefinition with the file name as id and passing is_valid();
## - each variant is a key of vehicle.gd VARIANTS and there is exactly one definition
##   per key of unlock_manager.gd TRUCKS (Partida rapida keeps using TRUCKS);
## - seats, cargo and price are the ones of docs/expansion-distritos/diseno/flota.md,
##   the movement is an allowed one and the fleet key is `van`;
## - the scene instantiates a VehicleBody3D that takes the variant (variant_id sticks and
##   maximum_speed_kmh is the one of VARIANTS), and it is freed;
## - every id of CompanyTuning.STARTING_FLEET has its .tres.

const VEHICLES_DIR := "res://data/vehicles"
const VEHICLE_SCRIPT := "res://scripts/gameplay/vehicle/vehicle.gd"
const UNLOCK_SCRIPT := "res://scripts/core/unlock_manager.gd"
## id -> [variant, seats, cargo_slots, cargo_kg, price] (flota.md).
const EXPECTED: Dictionary = {
	"van_classic": [&"classic", 8, 7, 300.0, 1500],
	"van_agile": [&"agile", 8, 7, 300.0, 1800],
	"van_vintage": [&"vintage", 8, 7, 300.0, 2000],
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array[String] = _list_ids(VEHICLES_DIR)
	var expected_ids: Array[String] = []
	for key: String in EXPECTED:
		expected_ids.append(key)
	expected_ids.sort()
	_expect(ids == expected_ids, "data/vehicles/ holds the three vans (got %s)" % [ids])

	var variants: Dictionary = (load(VEHICLE_SCRIPT) as GDScript).get("VARIANTS")
	var trucks: Dictionary = (load(UNLOCK_SCRIPT) as GDScript).get("TRUCKS")
	var variant_count: Dictionary = {}
	for file_id: String in ids:
		var def: VehicleDefinition = load("%s/%s.tres" % [VEHICLES_DIR, file_id]) as VehicleDefinition
		_expect(def != null, "%s loads as VehicleDefinition" % file_id)
		if def == null:
			continue
		_check_definition(file_id, def, variants, trucks)
		variant_count[def.variant] = int(variant_count.get(def.variant, 0)) + 1
		await _check_scene(file_id, def, variants)

	for truck_id: StringName in trucks:
		_expect(
			int(variant_count.get(truck_id, 0)) == 1,
			"TRUCKS key %s has exactly one definition (got %s)" % [truck_id, variant_count.get(truck_id, 0)]
		)

	for start_id: StringName in CompanyTuning.STARTING_FLEET:
		_expect(
			ResourceLoader.exists("%s/%s.tres" % [VEHICLES_DIR, start_id]),
			"STARTING_FLEET %s has its .tres" % start_id
		)
	_expect(not CompanyTuning.STARTING_FLEET.is_empty(), "the new company starts with a vehicle")

	var empty := VehicleDefinition.new()
	_expect(not empty.is_valid(), "a blank VehicleDefinition is not valid")

	if _failures == 0:
		print("PASS: vehicle definitions (%d vehicles)" % ids.size())
	quit(_failures)


func _check_definition(file_id: String, def: VehicleDefinition, variants: Dictionary, trucks: Dictionary) -> void:
	_expect(String(def.id) == file_id, "%s: id equals the file name (got %s)" % [file_id, def.id])
	_expect(def.is_valid(), "%s: is_valid()" % file_id)
	_expect(variants.has(def.variant), "%s: variant %s is in VARIANTS" % [file_id, def.variant])
	_expect(trucks.has(def.variant), "%s: variant %s is in TRUCKS" % [file_id, def.variant])
	var row: Array = EXPECTED.get(file_id, [])
	if row.is_empty():
		return
	_expect(def.variant == row[0], "%s: variant is %s (got %s)" % [file_id, row[0], def.variant])
	_expect(def.seats == row[1], "%s: seats is %d (got %d)" % [file_id, row[1], def.seats])
	_expect(def.cargo_slots == row[2], "%s: cargo_slots is %d (got %d)" % [file_id, row[2], def.cargo_slots])
	_expect(is_equal_approx(def.cargo_kg, row[3]), "%s: cargo_kg is %s (got %s)" % [file_id, row[3], def.cargo_kg])
	_expect(def.price == row[4], "%s: price is %d (got %d)" % [file_id, row[4], def.price])
	_expect(VehicleDefinition.MOVEMENTS.has(def.movement), "%s: movement %s is allowed" % [file_id, def.movement])
	_expect(def.movement == &"wheels", "%s: a van moves on wheels (got %s)" % [file_id, def.movement])
	_expect(def.fleet_key == &"van", "%s: fleet_key is van (got %s)" % [file_id, def.fleet_key])
	_expect(def.gate_key == &"" and def.amplified_trap == &"", "%s: no gate key, no amplified trap" % file_id)


func _check_scene(file_id: String, def: VehicleDefinition, variants: Dictionary) -> void:
	if def.scene == null or not variants.has(def.variant):
		return
	var van := def.scene.instantiate() as VehicleBody3D
	_expect(van != null, "%s: the scene instantiates a VehicleBody3D" % file_id)
	if van == null:
		return
	van.set(&"variant_id", def.variant)
	root.add_child(van)
	await process_frame
	_expect(van.get(&"variant_id") == def.variant, "%s: variant_id stuck (got %s)" % [file_id, van.get(&"variant_id")])
	var speed: float = float(variants[def.variant]["maximum_speed_kmh"])
	_expect(
		is_equal_approx(float(van.get(&"maximum_speed_kmh")), speed),
		"%s: maximum_speed_kmh is %s (got %s)" % [file_id, speed, van.get(&"maximum_speed_kmh")]
	)
	van.queue_free()
	await process_frame


func _list_ids(dir_path: String) -> Array[String]:
	var ids: Array[String] = []
	for file_name: String in DirAccess.get_files_at(dir_path):
		var clean: String = file_name.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			ids.append(clean.get_basename())
	ids.sort()
	return ids


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
