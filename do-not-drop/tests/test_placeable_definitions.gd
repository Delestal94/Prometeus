extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_placeable_definitions.gd
##
## The objects the crew can place in the warehouse (expansion D-0904,
## placeable_definition.gd):
## - data/placeables/ holds the four initial objects (assembly table, shelf,
##   fridge, dispatch zone), each loading as PlaceableDefinition with the file
##   name as id and a WORLD_PLACEABLE_<ID> display key;
## - every footprint, height and price is positive, and the role is one of
##   assembly / storage / dispatch;
## - only storage holds product slots, and only the fridge is cold;
## - the dispatch zone does not block walking, the rest do;
## - footprint_for() swaps X and Z on odd quarter turns (also negative ones);
## - refund() gives back CompanyTuning.PLACEABLE_REFUND_RATIO of the price,
##   rounded down, and never more than the price.

const DIR := "res://data/placeables"
const IDS: Array[String] = ["assembly_table", "dispatch_zone", "fridge", "shelf"]
const ROLES: Array[StringName] = [&"assembly", &"storage", &"dispatch"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array[String] = _list_ids(DIR)
	_expect(ids == IDS, "data/placeables/ holds the four objects (got %s)" % [ids])

	for file_id: String in ids:
		var def: PlaceableDefinition = load("%s/%s.tres" % [DIR, file_id]) as PlaceableDefinition
		_expect(def != null, "%s loads as PlaceableDefinition" % file_id)
		if def != null:
			_check_definition(file_id, def)

	var table: PlaceableDefinition = load("%s/assembly_table.tres" % DIR) as PlaceableDefinition
	if table != null:
		_check_rotation_and_refund(table)

	if _failures == 0:
		print("PASS: placeable definitions (%d objects)" % ids.size())
	quit(_failures)


func _check_definition(file_id: String, def: PlaceableDefinition) -> void:
	_expect(String(def.id) == file_id, "%s: id equals the file name (got %s)" % [file_id, def.id])
	_expect(
		def.display_key == "WORLD_PLACEABLE_" + file_id.to_upper(),
		"%s: display_key is WORLD_PLACEABLE_<ID> (got %s)" % [file_id, def.display_key]
	)
	_expect(
		def.footprint.x > 0 and def.footprint.y > 0,
		"%s: footprint has an area (got %s)" % [file_id, def.footprint]
	)
	_expect(def.height_m > 0.0, "%s: height is positive (got %f)" % [file_id, def.height_m])
	_expect(def.price > 0, "%s: price is positive (got %d)" % [file_id, def.price])
	_expect(ROLES.has(def.role), "%s: role %s is known" % [file_id, def.role])
	var is_storage: bool = def.role == &"storage"
	_expect(
		(def.slots > 0) == is_storage,
		"%s: only storage has slots (role %s, slots %d)" % [file_id, def.role, def.slots]
	)
	_expect(def.cold == (file_id == "fridge"), "%s: cold only for the fridge" % file_id)
	_expect(
		def.blocks_walking == (def.role != &"dispatch"),
		"%s: only the dispatch zone lets you walk over it" % file_id
	)


func _check_rotation_and_refund(def: PlaceableDefinition) -> void:
	_expect(def.footprint == Vector2i(2, 1), "the table covers 2x1 cells")
	_expect(def.footprint_for(0) == Vector2i(2, 1), "no turn keeps the footprint")
	_expect(def.footprint_for(1) == Vector2i(1, 2), "one turn swaps X and Z")
	_expect(def.footprint_for(2) == Vector2i(2, 1), "two turns are back to the start")
	_expect(def.footprint_for(-1) == Vector2i(1, 2), "a negative odd turn swaps too")
	_expect(def.footprint_for(7) == Vector2i(1, 2), "seven turns swap like one")
	var expected: int = floori(def.price * CompanyTuning.PLACEABLE_REFUND_RATIO)
	_expect(def.refund() == expected, "refund is the ratio of the price (got %d)" % def.refund())
	_expect(def.refund() < def.price, "selling never gives back the full price")
	_expect(
		CompanyTuning.PLACEABLE_REFUND_RATIO > 0.0 and CompanyTuning.PLACEABLE_REFUND_RATIO < 1.0,
		"the refund ratio is between 0 and 1"
	)


## The ids of the .tres files in a folder, sorted. Exported builds list them
## as "<name>.tres.remap", so that suffix is stripped.
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
