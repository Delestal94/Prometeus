extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_trap.gd
##
## Packing quality to trap intensity (expansion D-0710, box_trap.gd), for an order of one porcelain
## vase (examples 1-3 of diseno/armado-y-trampas.md):
## - intensity is 1 - quality / 100 and stays inside 0..1;
## - glass in an M box with every gap padded: fragile, quality 100, intensity 0, low;
## - the same unpadded: quality 68.33, intensity 0.317, high, plus a low Balance (0.3);
## - 10 of 19 gaps padded: quality 85, intensity 0.15, mid, no extra trap;
## - the plan's trap and absorption are the package's, and BoxToPackage.build with an order
##   stores it as META_TRAP_PLAN (without an order it stores none);
## - a box with no known product gives an empty plan.

const VASE: ProductDefinition = preload("res://data/products/porcelain_vase.tres")

var _failures: int = 0
var _packages: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var order: Dictionary = {
		"id": &"o1", "items": [{"product": &"porcelain_vase", "qty": 1}], "requirements": []
	}
	var products: Dictionary = {&"porcelain_vase": VASE}
	_test_formula()
	_test_glass(order, products)
	_test_package(order, products)
	_expect(BoxTrap.plan(PackedBox.new(&"M"), order, products).is_empty(), "empty box, empty plan")
	for package: Node in _packages:
		package.free()
	quit(_failures)


func _test_formula() -> void:
	_expect_near(BoxTrap.intensity(100.0), 0.0, "perfect box")
	_expect_near(BoxTrap.intensity(0.0), 1.0, "worthless box")
	_expect_near(BoxTrap.intensity(150.0), 0.0, "clamped below")
	_expect_near(BoxTrap.intensity(-20.0), 1.0, "clamped above")
	_expect(BoxTrap.level(0.0) == BoxTrap.LEVEL_LOW, "0 is low")
	_expect(BoxTrap.level(0.15) == BoxTrap.LEVEL_MID, "0.15 is mid")
	_expect(BoxTrap.level(0.3) == BoxTrap.LEVEL_HIGH, "0.3 is high")


func _test_glass(order: Dictionary, products: Dictionary) -> void:
	var padded: Dictionary = BoxTrap.plan(_box(19), order, products)
	_expect(padded["trap_id"] == &"fragile", "padded glass rides fragile")
	_expect_near(padded["quality"], 100.0, "padded quality")
	_expect_near(padded["intensity"], 0.0, "padded intensity")
	_expect(padded["level"] == BoxTrap.LEVEL_LOW, "padded glass: low")
	_expect(padded["extra"].is_empty(), "padded glass: no extra trap")
	_expect_near(padded["absorption"], 0.6, "padded absorption")
	var bare: Dictionary = BoxTrap.plan(_box(0), order, products)
	_expect(bare["trap_id"] == &"fragile", "bare glass still rides fragile")
	_expect_near(bare["quality"], 100.0 - 30.0 * 1.5 * 19.0 / 27.0, "bare quality")
	_expect_near(bare["intensity"], 0.3167, "bare intensity")
	_expect(bare["level"] == BoxTrap.LEVEL_HIGH, "bare glass: high")
	_expect(bare["intensity"] > padded["intensity"], "no padding hits harder than padding")
	_expect(bare["extra"].size() == 1, "bare glass in a big box adds one trap")
	_expect(bare["extra"][0]["trap_id"] == &"balance", "...Balance")
	_expect_near(bare["extra"][0]["intensity"], 0.3, "...at low intensity")
	var half: Dictionary = BoxTrap.plan(_box(10), order, products)
	_expect_near(half["quality"], 85.0, "half padded quality")
	_expect(half["level"] == BoxTrap.LEVEL_MID, "half padded: mid")
	_expect(half["extra"].is_empty(), "half padded: not loose, no extra trap")


func _test_package(order: Dictionary, products: Dictionary) -> void:
	var package: DeliveryPackage = BoxToPackage.build(_box(0), products, order)
	_expect(package != null, "a package comes out")
	if package == null:
		return
	_packages.append(package)
	var plan: Dictionary = package.get_meta(BoxToPackage.META_TRAP_PLAN, {})
	_expect(plan.get("trap_id", &"") == package.trap_definition.id, "plan trap is the package's")
	_expect_near(plan.get("absorption", -1.0), package.impact_absorption, "plan absorption")
	var plain: DeliveryPackage = BoxToPackage.build(_box(0), products)
	if plain != null:
		_packages.append(plain)
	_expect(plain != null and not plain.has_meta(BoxToPackage.META_TRAP_PLAN), "no order, no plan")


func _box(padding: int) -> PackedBox:
	var box := PackedBox.new(&"M")
	box.place(VASE, Vector3i.ZERO)
	box.fill_free_cells(padding)
	box.taped = true
	box.label_order_id = &"o1"
	return box


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _expect_near(got: float, want: float, label: String) -> void:
	_expect(absf(got - want) < 0.01, "%s (got %.3f, want %.3f)" % [label, got, want])
