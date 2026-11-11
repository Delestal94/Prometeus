extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_expansion_resources.gd
##
## Transversal check of the expansion's .tres (D-0245, scripts/core/company/expansion_resource_check.gd):
## - the real data/ (products, zones, vehicles, gates, suppliers, boxes, placeables,
##   order_requirements, shop, shed) has zero problems: unique ids equal to the file name, files
##   that load, references that resolve (supplier -> products, product -> zones and trap, zone ->
##   gates, gate -> fleet keys) and numbers in range. A bad .tres fails CI here instead of
##   showing up as a half-empty catalog at runtime;
## - a repeated product id in an extra root under user:// is reported and names the id (the
##   "done when" of D-0245), also against data/;
## - a supplier selling a product that does not exist, a zone with a missing gate, a box with 0
##   cells or a negative price, and a shop item of an unknown kind are each reported with the
##   folder and file name;
## - the fixtures are removed from user:// at the end.

const TEST_ROOT: String = "user://expansion_resources_test"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	var real: Array[String] = ExpansionResourceCheck.run()
	_expect(real.is_empty(), "data/ has no problems (got %s)" % [real])
	_check_duplicate_id()
	_clean()
	_check_broken_reference()
	_clean()
	_check_bad_range()
	_clean()
	if _failures == 0:
		print("PASS: expansion resources validate: unique ids, references and ranges")
	quit(_failures)


func _check_duplicate_id() -> void:
	_save_product("products/gadget_a.tres", &"gadget")
	_save_product("products/gadget_b.tres", &"gadget")
	_save_product("products/hen_clone.tres", &"hen")
	var problems: Array[String] = ExpansionResourceCheck.run([TEST_ROOT])
	_expect(_has(problems, "duplicate id 'gadget'", "gadget_b.tres"),
		"a repeated id inside the extra root names the id and the file (got %s)" % [problems])
	_expect(_has(problems, "duplicate id 'hen'", "hen_clone.tres"),
		"a repeated id against data/ names the id and the file (got %s)" % [problems])
	_expect(not _has(problems, "gadget_a.tres", ""), "the first file is not blamed (got %s)" % [problems])


func _check_broken_reference() -> void:
	var supplier := SupplierDefinition.new()
	supplier.id = &"ghost_supplier"
	supplier.products = [&"hen", &"no_such_product"]
	supplier.arrival_min = 600
	supplier.wait_minutes = 60
	_save(supplier, "suppliers/ghost_supplier.tres")
	var zone := ZoneDefinition.new()
	zone.id = &"ghost_zone"
	zone.display_key = "WORLD_ZONE_GHOST"
	zone.bounds = Rect2(0, 0, 10, 10)
	zone.gates = [&"gate_nowhere"]
	_save(zone, "zones/ghost_zone.tres")
	var problems: Array[String] = ExpansionResourceCheck.run([TEST_ROOT])
	_expect(_has(problems, "suppliers/ghost_supplier.tres", "no_such_product"),
		"a supplier selling a missing product is reported (got %s)" % [problems])
	_expect(_has(problems, "zones/ghost_zone.tres", "gate_nowhere"),
		"a zone with a missing gate is reported (got %s)" % [problems])
	_expect(not _has(problems, "ghost_supplier.tres", "'hen'"),
		"the valid product of that supplier is not blamed (got %s)" % [problems])


func _check_bad_range() -> void:
	var box := BoxDefinition.new()
	box.id = &"flat"
	box.cells = Vector3i(0, 2, 2)
	box.cost = -3
	_save(box, "boxes/flat.tres")
	var item := ShopItem.new()
	item.id = &"odd"
	item.display_key = "WORLD_SHOP_ODD"
	item.kind = &"teleporter"
	item.price = 10
	item.grant_key = &"odd"
	_save(item, "shop/odd.tres")
	var problems: Array[String] = ExpansionResourceCheck.run([TEST_ROOT])
	_expect(_has(problems, "boxes/flat.tres", "cells"),
		"a box with 0 cells on an axis is reported (got %s)" % [problems])
	_expect(_has(problems, "boxes/flat.tres", "cost"),
		"a box with a negative cost is reported (got %s)" % [problems])
	_expect(_has(problems, "shop/odd.tres", "kind"),
		"a shop item of an unknown kind is reported (got %s)" % [problems])


func _save_product(relative: String, id: StringName) -> void:
	var product := ProductDefinition.new()
	product.id = id
	_save(product, relative)


func _save(res: Resource, relative: String) -> void:
	var path: String = TEST_ROOT.path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: Error = ResourceSaver.save(res, path)
	_expect(err == OK, "fixture saved to %s (got %s)" % [path, error_string(err)])


## True when one problem contains both texts (`second` may be empty).
func _has(problems: Array[String], first: String, second: String) -> bool:
	for message: String in problems:
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
