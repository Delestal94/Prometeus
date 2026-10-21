class_name CompanyCatalog
extends RefCounted
## Every Resource of the company registries, read from data/ by id (expansion D-0216).
##
## One folder per kind (products, zones, vehicles, gates, suppliers, boxes): a new .tres joins
## with no code. Any Resource with an `id` property counts, so the classes of suppliers and
## boxes (D-0217, D-0218) only add files. Empty folders are fine. Repeated or missing ids and
## files that don't load are not fatal: they are kept in `errors` (and push_error'd) and the
## first file wins. Nothing here draws or plays sound.

const DATA_ROOT: String = "res://data"
const PRODUCTS: StringName = &"products"
const ZONES: StringName = &"zones"
const VEHICLES: StringName = &"vehicles"
const GATES: StringName = &"gates"
const SUPPLIERS: StringName = &"suppliers"
const BOXES: StringName = &"boxes"
## Folder name under a root, in the order the kinds are read.
const KINDS: Array[StringName] = [PRODUCTS, ZONES, VEHICLES, GATES, SUPPLIERS, BOXES]

## Human readable problems of the last load; empty when everything was clean.
var errors: Array[String] = []
## kind -> { id: Resource }.
var _by_id: Dictionary = {}
## kind -> Array[Resource], in file name order (the same on every peer).
var _ordered: Dictionary = {}


## Reads data/ plus, for tests and mods, the same kind folders under each of `extra_roots`
## (for example "user://catalog_test": its products go in "user://catalog_test/products/").
static func load_all(extra_roots: Array[String] = []) -> CompanyCatalog:
	var catalog := CompanyCatalog.new()
	var roots: Array[String] = [DATA_ROOT]
	roots.append_array(extra_roots)
	for kind: StringName in KINDS:
		catalog._by_id[kind] = {}
		catalog._ordered[kind] = [] as Array[Resource]
		for root: String in roots:
			catalog._read_dir(kind, root.path_join(String(kind)))
	return catalog


## Names of the .tres in `dir`, sorted. In an export they can come as "x.tres.remap":
## the suffix is dropped and load() resolves the remap.
static func tres_files(dir: String) -> PackedStringArray:
	var names: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		var name: String = file.trim_suffix(".remap")
		if name.ends_with(".tres") and not names.has(name):
			names.append(name)
	names.sort()
	return PackedStringArray(names)


func has(kind: StringName, id: StringName) -> bool:
	return _by_id.get(kind, {}).has(id)


## The Resource of `kind` with that id, or null.
func get_resource(kind: StringName, id: StringName) -> Resource:
	return _by_id.get(kind, {}).get(id) as Resource


## Every Resource of `kind`, in file name order.
func all(kind: StringName) -> Array[Resource]:
	var found: Array[Resource] = []
	found.append_array(_ordered.get(kind, [] as Array[Resource]))
	return found


## Ids of `kind`, in file name order.
func ids(kind: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for res: Resource in all(kind):
		found.append(_id_of(res))
	return found


func product(id: StringName) -> ProductDefinition:
	return get_resource(PRODUCTS, id) as ProductDefinition


func zone(id: StringName) -> ZoneDefinition:
	return get_resource(ZONES, id) as ZoneDefinition


func vehicle(id: StringName) -> VehicleDefinition:
	return get_resource(VEHICLES, id) as VehicleDefinition


func gate(id: StringName) -> GateRequirement:
	return get_resource(GATES, id) as GateRequirement


func supplier(id: StringName) -> SupplierDefinition:
	return get_resource(SUPPLIERS, id) as SupplierDefinition


func box(id: StringName) -> BoxDefinition:
	return get_resource(BOXES, id) as BoxDefinition


## Every box, smallest first (by cell count; file name order breaks ties).
func boxes() -> Array[BoxDefinition]:
	var found: Array[BoxDefinition] = []
	for res: Resource in all(BOXES):
		var box_def := res as BoxDefinition
		if box_def != null:
			found.append(box_def)
	found.sort_custom(func(a: BoxDefinition, b: BoxDefinition) -> bool:
		return a.volume() < b.volume())
	return found


## Every zone, in file name order (what the world builds its slabs from).
func zones() -> Array[ZoneDefinition]:
	var found: Array[ZoneDefinition] = []
	for res: Resource in all(ZONES):
		var zone_def := res as ZoneDefinition
		if zone_def != null:
			found.append(zone_def)
	return found


func _read_dir(kind: StringName, dir: String) -> void:
	for file: String in tres_files(dir):
		var path: String = dir.path_join(file)
		var res: Resource = load(path)
		if res == null:
			_fail("%s: cannot load %s" % [kind, path])
			continue
		var id: StringName = _id_of(res)
		if id == &"":
			_fail("%s: %s has no id" % [kind, path])
			continue
		var by_id: Dictionary = _by_id[kind]
		if by_id.has(id):
			var first: Resource = by_id[id]
			_fail("%s: duplicate id '%s' in %s (already in %s)"
				% [kind, id, path, first.resource_path])
			continue
		by_id[id] = res
		var ordered: Array[Resource] = _ordered[kind]
		ordered.append(res)


func _fail(message: String) -> void:
	errors.append(message)
	push_error("CompanyCatalog: " + message)


static func _id_of(res: Resource) -> StringName:
	var value: Variant = res.get(&"id")
	if value is StringName or value is String:
		return StringName(value)
	return &""
