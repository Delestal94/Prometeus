extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_product_definitions.gd
##
## The company catalog data (expansion D-0204, product_definition.gd):
## - the ten files in data/products/ load as ProductDefinition, one per
##   data/contents/*.tres, with the file name as id and the same content;
## - sizes fit the XL box (4x4x4 cells), prices sit in the 20..80 range and
##   the sell price is buy x 1.6 (vase: 80);
## - temperature is one of the three allowed values;
## - trap_id points to a real data/traps/<trap_id>.tres that carries this
##   product's content (TrapDefinition.contents), and it has a district.

const PRODUCTS_DIR := "res://data/products"
const CONTENTS_DIR := "res://data/contents"
const TRAPS_DIR := "res://data/traps"
const TEMPERATURES: Array[StringName] = [&"ambient", &"cold", &"heat"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array[String] = _list_ids(PRODUCTS_DIR)
	var content_ids: Array[String] = _list_ids(CONTENTS_DIR)
	_expect(ids.size() == 10, "data/products/ has 10 products (got %d)" % ids.size())
	_expect(
		ids == content_ids,
		"one product per content (products %s, contents %s)" % [ids, content_ids]
	)

	var seen: Dictionary = {}
	for file_id: String in ids:
		var product: ProductDefinition = (
			load("%s/%s.tres" % [PRODUCTS_DIR, file_id]) as ProductDefinition
		)
		_expect(product != null, "%s loads as ProductDefinition" % file_id)
		if product == null:
			continue
		_check_product(file_id, product, seen)

	# The sell price falls back to buy x 1.6 and an explicit one wins.
	var vase: ProductDefinition = load(PRODUCTS_DIR + "/porcelain_vase.tres") as ProductDefinition
	_expect(
		vase != null and vase.get_sell_price() == 80,
		"vase sells for 80 (got %s)" % vase.get_sell_price()
	)
	var custom := ProductDefinition.new()
	custom.buy_price = 50
	custom.sell_price = 90
	_expect(
		custom.get_sell_price() == 90, "explicit sell_price wins (got %d)" % custom.get_sell_price()
	)

	if _failures == 0:
		print("PASS: product definitions (%d products)" % ids.size())
	quit(_failures)


func _check_product(file_id: String, product: ProductDefinition, seen: Dictionary) -> void:
	_expect(
		String(product.id) == file_id,
		"%s: id equals the file name (got %s)" % [file_id, product.id]
	)
	_expect(not seen.has(product.id), "%s: id is unique" % file_id)
	seen[product.id] = true
	_expect(product.content != null, "%s: content is set" % file_id)
	if product.content != null:
		_expect(
			product.content.id == product.id,
			"%s: content.id matches (got %s)" % [file_id, product.content.id]
		)
	for axis: int in 3:
		_expect(
			product.cells[axis] >= 1 and product.cells[axis] <= 4,
			"%s: cells axis %d fits the XL box (got %s)" % [file_id, axis, product.cells],
		)
	_expect(
		product.buy_price >= 20 and product.buy_price <= 80,
		"%s: buy_price in 20..80 (got %d)" % [file_id, product.buy_price]
	)
	var expected_sell: int = roundi(product.buy_price * 1.6)
	_expect(
		product.get_sell_price() == expected_sell,
		"%s: sell price is buy x 1.6 (got %d)" % [file_id, product.get_sell_price()]
	)
	_expect(product.weight_kg > 0.0, "%s: weight_kg > 0 (got %s)" % [file_id, product.weight_kg])
	_expect(
		TEMPERATURES.has(product.temperature),
		"%s: temperature is allowed (got %s)" % [file_id, product.temperature]
	)
	_expect(not product.districts.is_empty(), "%s: districts is not empty" % file_id)

	var trap_path: String = "%s/%s.tres" % [TRAPS_DIR, product.trap_id]
	_expect(ResourceLoader.exists(trap_path), "%s: trap %s exists" % [file_id, product.trap_id])
	if not ResourceLoader.exists(trap_path):
		return
	var trap: Resource = load(trap_path)
	var carried: bool = false
	for entry: Resource in trap.get("contents"):
		if entry == product.content:
			carried = true
	_expect(carried, "%s: trap %s carries this content" % [file_id, product.trap_id])


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
