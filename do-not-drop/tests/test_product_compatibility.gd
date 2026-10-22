extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_product_compatibility.gd
##
## Products that cannot share a box (expansion D-0726, product_compatibility.gd):
## - fireworks clash with food and with live animals, in either order; food and animals mix;
## - products in no group (glass, lamps) mix with everything, and a product never clashes with its group;
## - conflicts() reads a real PackedBox: a safe box is empty, a mixed one lists each clashing pair once;
## - penalty() is INCOMPATIBLE_QUALITY_PENALTY per pair; a null box is safe;
## - every grouped id is a product of the catalog.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _box_with(ids: Array) -> PackedBox:
	var box := PackedBox.new(&"XL")
	for id: StringName in ids:
		var def: ProductDefinition = load("res://data/products/%s.tres" % id)
		_expect(box.place(def, box.first_fit(def)), "placed " + String(id))
	return box


func _run() -> void:
	_expect(ProductCompatibility.clash(&"fireworks_crate", &"sourdough"), "fireworks clash with food")
	_expect(ProductCompatibility.clash(&"hen", &"fireworks_crate"), "animals clash with fireworks (reversed)")
	_expect(not ProductCompatibility.clash(&"hen", &"sourdough"), "animals and food mix")
	_expect(not ProductCompatibility.clash(&"hen", &"puppy"), "same group never clashes")
	_expect(not ProductCompatibility.clash(&"antique_lamp", &"fireworks_crate"), "ungrouped mixes with everything")
	_expect(ProductCompatibility.group_of(&"glass_tower") == &"", "glass has no group")

	_expect(ProductCompatibility.is_safe(_box_with([&"hen", &"sourdough", &"antique_lamp"])), "safe box")
	var mixed: PackedBox = _box_with([&"fireworks_crate", &"milk_canister", &"wedding_cake"])
	_expect(ProductCompatibility.conflicts(mixed).size() == 1, "fireworks + two foods is one pair")
	_expect(ProductCompatibility.penalty(mixed) == CompanyTuning.INCOMPATIBLE_QUALITY_PENALTY, "one pair, one penalty")
	var worse: PackedBox = _box_with([&"fireworks_crate", &"milk_canister", &"hen"])
	_expect(ProductCompatibility.conflicts(worse).size() == 2, "fireworks with food and animal is two pairs")
	var two_pairs: int = 2 * CompanyTuning.INCOMPATIBLE_QUALITY_PENALTY
	_expect(ProductCompatibility.penalty(worse) == two_pairs, "two pairs, two penalties")
	_expect(ProductCompatibility.is_safe(null) and ProductCompatibility.penalty(null) == 0, "null box is safe")

	for id: StringName in ProductCompatibility.GROUP_OF:
		_expect(ResourceLoader.exists("res://data/products/%s.tres" % id), "catalog has " + String(id))

	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)
