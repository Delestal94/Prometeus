extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_catalog.gd
##
## Registries of the company read from data/ (expansion D-0216, scripts/core/company/catalog.gd):
## - the current 10 products, 9 zones, 3 vehicles and 7 gates load by id, each under its own id,
##   and boxes (README only today) load empty with no error;
## - the supplier distribuidora_central (D-0218) loads by id, sells the 10 products, every one of
##   them exists in the catalog, and its arrival and wait match CompanyTuning (08:30, 180 min);
## - zones() keeps the file name order company_root.gd's load_zones() has always had;
## - a ProductDefinition .tres written in user:// and read through the extra root shows up by id
##   with no code change, next to the data/ ones;
## - a repeated id (inside the extra root, or against data/) gives a clear entry in `errors`, the
##   first file wins and the load goes on; a .tres with no id is reported too;
## - export: a "x.tres.remap" name resolves to "x.tres", once.

const TEST_ROOT: String = "user://catalog_test"
const REMAP_DIR: String = "user://catalog_test/remap"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	_check_data()
	_check_supplier()
	_check_extra_root()
	_check_duplicates()
	_check_remap()
	_clean()
	if _failures == 0:
		print("PASS: company catalog reads data/ by id, extra roots and clear errors")
	quit(_failures)


func _check_data() -> void:
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	_expect(catalog.errors.is_empty(), "data/ loads with no errors (got %s)" % [catalog.errors])
	var expected: Dictionary = {
		CompanyCatalog.PRODUCTS: 10, CompanyCatalog.ZONES: 9, CompanyCatalog.VEHICLES: 3,
		CompanyCatalog.GATES: 7, CompanyCatalog.SUPPLIERS: 1, CompanyCatalog.BOXES: 0,
	}
	for kind: StringName in expected:
		var count: int = catalog.all(kind).size()
		_expect(count == expected[kind], "%s: %d entries (got %d)" % [kind, expected[kind], count])
	_expect(catalog.product(&"hen") != null, "product 'hen' loads by id")
	_expect(catalog.product(&"hen").id == &"hen", "product 'hen' carries its own id")
	_expect(catalog.zone(&"puerto") != null, "zone 'puerto' loads by id")
	_expect(catalog.vehicle(&"van_agile") != null, "vehicle 'van_agile' loads by id")
	_expect(catalog.gate(&"gate_puerto") != null, "gate 'gate_puerto' loads by id")
	_expect(catalog.get_resource(CompanyCatalog.PRODUCTS, &"nope") == null, "unknown id is null")
	_expect(not catalog.has(CompanyCatalog.ZONES, &"nope"), "has() is false for an unknown id")
	var by_file: Array[StringName] = []
	for file: String in CompanyCatalog.tres_files("res://data/zones/"):
		by_file.append(StringName(file.get_basename()))
	_expect(catalog.ids(CompanyCatalog.ZONES) == by_file,
		"zones() keeps the file name order (got %s)" % [catalog.ids(CompanyCatalog.ZONES)])
	_expect(catalog.zones().size() == 9, "zones() returns 9 typed zones (got %d)" % catalog.zones().size())


func _check_supplier() -> void:
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	var supplier: SupplierDefinition = catalog.supplier(&"distribuidora_central")
	_expect(supplier != null, "supplier 'distribuidora_central' loads by id")
	if supplier == null:
		return
	_expect(supplier.id == &"distribuidora_central", "the supplier carries its own id")
	_expect(supplier.products.size() == 10, "it sells 10 products (got %d)" % supplier.products.size())
	for id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		_expect(supplier.sells(id), "it sells catalog product '%s'" % id)
	for id: StringName in supplier.products:
		_expect(catalog.product(id) != null, "its product '%s' exists in the catalog" % id)
	_expect(supplier.arrival_min == CompanyTuning.SUPPLIER_ARRIVAL_MIN,
		"its truck arrives at 08:30 (got %d)" % supplier.arrival_min)
	_expect(supplier.wait_minutes == CompanyTuning.SUPPLIER_WAIT_MIN,
		"it waits 180 min (got %d)" % supplier.wait_minutes)
	var hen: ProductDefinition = catalog.product(&"hen")
	_expect(supplier.unit_price(hen) == hen.buy_price,
		"price factor 1.0 keeps the list price (got %d)" % supplier.unit_price(hen))


func _check_extra_root() -> void:
	_save_product(TEST_ROOT + "/products/test_gadget.tres", &"test_gadget")
	var catalog: CompanyCatalog = CompanyCatalog.load_all([TEST_ROOT])
	_expect(catalog.errors.is_empty(), "extra root loads with no errors (got %s)" % [catalog.errors])
	var gadget: ProductDefinition = catalog.product(&"test_gadget")
	_expect(gadget != null, "the product written in user:// shows up by id")
	_expect(catalog.all(CompanyCatalog.PRODUCTS).size() == 11,
		"it joins the 10 of data/ (got %d)" % catalog.all(CompanyCatalog.PRODUCTS).size())
	_expect(catalog.product(&"hen") != null, "the data/ products are still there")


func _check_duplicates() -> void:
	_save_product(TEST_ROOT + "/products/test_gadget_copy.tres", &"test_gadget")
	_save_product(TEST_ROOT + "/products/test_hen_clone.tres", &"hen")
	_save_product(TEST_ROOT + "/products/test_no_id.tres", &"")
	var catalog: CompanyCatalog = CompanyCatalog.load_all([TEST_ROOT])
	_expect(catalog.errors.size() == 3, "three problems reported (got %s)" % [catalog.errors])
	_expect(_has_error(catalog, "duplicate id 'test_gadget'", "test_gadget_copy.tres"),
		"duplicate inside the extra root names the id and the file (got %s)" % [catalog.errors])
	_expect(_has_error(catalog, "duplicate id 'hen'", "test_hen_clone.tres"),
		"duplicate against data/ names the id and the file (got %s)" % [catalog.errors])
	_expect(_has_error(catalog, "has no id", "test_no_id.tres"),
		"a file with no id is reported (got %s)" % [catalog.errors])
	_expect(catalog.product(&"test_gadget").resource_path.ends_with("/test_gadget.tres"),
		"the first file wins")
	_expect(catalog.product(&"hen").resource_path.begins_with("res://data/"),
		"data/ wins over the extra root")
	_expect(catalog.all(CompanyCatalog.PRODUCTS).size() == 11,
		"nothing extra was added (got %d)" % catalog.all(CompanyCatalog.PRODUCTS).size())


func _check_remap() -> void:
	DirAccess.make_dir_recursive_absolute(REMAP_DIR)
	for name: String in ["b.tres.remap", "a.tres", "a.tres.remap", "notes.txt"]:
		var file := FileAccess.open(REMAP_DIR.path_join(name), FileAccess.WRITE)
		file.close()
	var names: PackedStringArray = CompanyCatalog.tres_files(REMAP_DIR)
	_expect(names == PackedStringArray(["a.tres", "b.tres"]),
		".remap suffix dropped, once, sorted (got %s)" % [names])


func _save_product(path: String, id: StringName) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var product := ProductDefinition.new()
	product.id = id
	var err: Error = ResourceSaver.save(product, path)
	_expect(err == OK, "test product saved to %s (got %s)" % [path, error_string(err)])


func _has_error(catalog: CompanyCatalog, first: String, second: String) -> bool:
	for message: String in catalog.errors:
		if message.contains(first) and message.contains(second):
			return true
	return false


func _clean() -> void:
	_remove_dir(TEST_ROOT)


func _remove_dir(dir: String) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_dir(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
