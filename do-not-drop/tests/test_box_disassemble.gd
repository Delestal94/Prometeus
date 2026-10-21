extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_disassemble.gd
##
## Taking a badly packed box apart (expansion D-0719, PackingStation.disassemble):
## - with no box on the table there is nothing to do and the answer is empty;
## - every product goes back to the table, in the order it was packed, and the box stays on the
##   table empty, open, unlabeled and unstamped, with its size;
## - a taped box can be taken apart too (the tape is lost);
## - what does not fit on the table (STAGING_SLOTS) comes back as overflow, none is lost;
## - after taking apart the same products fit again in the same box.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_no_box()
	_test_back_to_table()
	_test_taped_box()
	_test_overflow()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _product(id: StringName, cells: Vector3i) -> ProductDefinition:
	var p := ProductDefinition.new()
	p.id = id
	p.cells = cells
	return p


func _packed(products: Array[ProductDefinition], size: StringName = &"M") -> PackingStation:
	var table: PackingStation = PackingStation.make(&"t1")
	table.start_box(size)
	for product: ProductDefinition in products:
		table.stage_product(product.id)
		table.put_in_box(product, table.box.first_fit(product))
	return table


func _test_no_box() -> void:
	var table: PackingStation = PackingStation.make(&"t1")
	_expect(table.disassemble().is_empty(), "no box, nothing to take apart")
	_expect(not table.has_box(), "the table stays free")


func _test_back_to_table() -> void:
	var cup: ProductDefinition = _product(&"cup", Vector3i(1, 1, 1))
	var vase: ProductDefinition = _product(&"vase", Vector3i(2, 1, 1))
	var table: PackingStation = _packed([cup, vase])
	table.box.fill_free_cells(3)
	table.box.label_order_id = &"o1"
	table.box.stamps.append(&"fragile")
	var out: Dictionary = table.disassemble()
	_expect(out["staged"] == [&"cup", &"vase"], "products come back in packed order")
	_expect(out["overflow"].is_empty(), "nothing overflows")
	_expect(table.staged == [&"cup", &"vase"], "they wait on the table again")
	_expect(table.has_box() and table.box.box_size == &"M", "the same size of box stays")
	_expect(table.box.items.is_empty() and table.box.grid.is_empty(), "the box is empty, padding gone")
	_expect(not table.box.taped and table.box.label_order_id == &"" and table.box.stamps.is_empty(),
		"no tape, label or stamps left")
	for product: ProductDefinition in [cup, vase]:
		_expect(table.put_in_box(product, table.box.first_fit(product)), "%s fits again" % product.id)


func _test_taped_box() -> void:
	var cup: ProductDefinition = _product(&"cup", Vector3i(1, 1, 1))
	var table: PackingStation = _packed([cup])
	table.box.taped = true
	_expect(table.dispatch() != null and not table.has_box(), "sanity: a taped box leaves")
	table = _packed([cup])
	table.box.taped = true
	table.disassemble()
	_expect(not table.is_sealed(), "a taped box is opened by taking it apart")
	_expect(table.dispatch() == null, "and it cannot be dispatched afterwards")


func _test_overflow() -> void:
	var cube: ProductDefinition = _product(&"cube", Vector3i(1, 1, 1))
	var products: Array[ProductDefinition] = []
	for i: int in 6:
		products.append(cube)
	var table: PackingStation = _packed(products, &"L")
	_expect(table.box.items.size() == 6, "six units are packed")
	var out: Dictionary = table.disassemble()
	_expect(out["staged"].size() == PackingStation.STAGING_SLOTS, "the table takes its slots")
	_expect(out["overflow"].size() == 2, "the rest overflows, nothing is lost")
	_expect(table.staged.size() == PackingStation.STAGING_SLOTS, "table full")
