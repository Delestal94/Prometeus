extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_to_package.gd
##
## Packed box to delivery package (expansion D-0213, box_to_package.gd):
## - a vase alone with every free cell padded rides as `fragile` with absorption 0.6,
##   its content is the vase's and the box travels as metadata with its order id;
## - with no padding the absorption is 1.0, and 10 of 19 gaps padded give 0.789
##   (example 3 of diseno/armado-y-trampas.md);
## - vase + wedding cake rides with the hardest trap (`balance`), whatever goes in first;
## - an XL box with one 1x1x1 product and no padding is marked `loose_box`; a padded one is not;
## - a box with nothing known in it gives no package.

const VASE: ProductDefinition = preload("res://data/products/porcelain_vase.tres")
const CAKE: ProductDefinition = preload("res://data/products/wedding_cake.tres")

var _failures: int = 0
var _packages: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_padded_vase()
	_test_absorption()
	_test_hardest_trap()
	_test_loose_box()
	_test_empty_box()
	for package: Node in _packages:
		package.free()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _build(box: PackedBox, products: Dictionary = {}) -> DeliveryPackage:
	var package: DeliveryPackage = BoxToPackage.build(box, products)
	if package != null:
		_packages.append(package)
	return package


func _vase_box(padding: int) -> PackedBox:
	var box := PackedBox.new(&"M")
	box.place(VASE, Vector3i.ZERO)
	box.fill_free_cells(padding)
	box.taped = true
	box.label_order_id = &"o7"
	return box


func _test_padded_vase() -> void:
	var box: PackedBox = _vase_box(19)
	var package: DeliveryPackage = _build(box)
	_expect(package != null, "a packed vase gives a package")
	if package == null:
		return
	_expect(package.trap_definition.id == &"fragile", "the vase rides as fragile")
	_expect(package.content == VASE.content, "the content is the vase's")
	_expect(is_equal_approx(package.impact_absorption, 0.6), "full padding absorbs 0.6")
	_expect(package.get_meta(BoxToPackage.META_ORDER_ID) == &"o7", "order id travels as metadata")
	_expect(package.package_id == &"box_o7", "the package is named after its order")
	var saved: Dictionary = package.get_meta(BoxToPackage.META_PACKED_BOX)
	_expect(saved == box.to_dict(), "the box travels as its to_dict()")
	_expect(not package.has_meta(BoxToPackage.META_LOOSE_BOX), "a padded box is not loose")


func _test_absorption() -> void:
	var bare: DeliveryPackage = _build(_vase_box(0))
	_expect(bare != null and is_equal_approx(bare.impact_absorption, 1.0), "no padding absorbs 1.0")
	var half: DeliveryPackage = _build(_vase_box(10))
	_expect(
		half != null and absf(half.impact_absorption - 0.7895) < 0.001,
		"10 of 19 gaps padded absorb 0.789"
	)
	var full := PackedBox.new(&"S")
	full.place(VASE, Vector3i.ZERO)
	_expect(is_equal_approx(BoxToPackage.absorption(full), 0.6), "a box full of product absorbs 0.6")


func _test_hardest_trap() -> void:
	for cake_first: bool in [false, true]:
		var box := PackedBox.new(&"L")
		if cake_first:
			box.place(CAKE, Vector3i(2, 0, 0))
			box.place(VASE, Vector3i.ZERO)
		else:
			box.place(VASE, Vector3i.ZERO)
			box.place(CAKE, Vector3i(2, 0, 0))
		var package: DeliveryPackage = _build(box)
		_expect(
			package != null and package.trap_definition.id == &"balance",
			"vase + cake rides as balance (cake first: %s)" % cake_first
		)
		_expect(package != null and package.content == CAKE.content, "the content is the cake's")


func _test_loose_box() -> void:
	var tiny := ProductDefinition.new()
	tiny.id = &"tiny_vase"
	tiny.content = VASE.content
	tiny.trap_id = &"fragile"
	tiny.cells = Vector3i.ONE
	var products: Dictionary = {&"tiny_vase": tiny}
	var box := PackedBox.new(&"XL")
	box.place(tiny, Vector3i.ZERO)
	var loose: DeliveryPackage = _build(box, products)
	_expect(loose != null and loose.get_meta(BoxToPackage.META_LOOSE_BOX, false), "XL with 1 cell is loose")
	box.fill_free_cells(box.total_cells())
	var padded: DeliveryPackage = _build(box, products)
	_expect(padded != null and not padded.has_meta(BoxToPackage.META_LOOSE_BOX), "padded XL is not loose")


func _test_empty_box() -> void:
	_expect(BoxToPackage.build(PackedBox.new(&"M")) == null, "an empty box gives no package")
	var unknown := PackedBox.new(&"M")
	var ghost := ProductDefinition.new()
	ghost.id = &"no_such_product"
	ghost.cells = Vector3i.ONE
	unknown.place(ghost, Vector3i.ZERO)
	_expect(BoxToPackage.build(unknown) == null, "an unknown product gives no package")
